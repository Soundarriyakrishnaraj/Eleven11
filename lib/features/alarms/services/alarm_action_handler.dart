import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_schedule_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  unawaited(
    AlarmActionHandler.handleResponse(response).catchError((Object error) {
      debugPrint('Background notification response failed: $error');
    }),
  );
}

class AlarmActionHandler {
  AlarmActionHandler._();

  static const String actionSnooze = 'action_snooze';
  static const String actionDismiss = 'action_dismiss';
  static const String _pendingDeliveriesPrefix =
      'eleven11_pending_local_notification_deliveries_v1_';
  static Future<void> Function(Map<String, dynamic>)? onDelivery;
  static Future<void> Function(String?)? onBodyTap;

  static Future<List<String>> pendingDeliveryPayloads(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_pendingDeliveriesPrefix$userId') ?? [];
  }

  static String occurrenceEventId({
    required String occurrenceBaseId,
    required DateTime localOccurrenceDate,
  }) {
    final date =
        '${localOccurrenceDate.year.toString().padLeft(4, '0')}-'
        '${localOccurrenceDate.month.toString().padLeft(2, '0')}-'
        '${localOccurrenceDate.day.toString().padLeft(2, '0')}';
    return '$occurrenceBaseId:$date';
  }

  static String alarmOccurrenceEventId({
    required String alarmInstanceId,
    required DateTime scheduledAt,
  }) => 'alarm:$alarmInstanceId:${scheduledAt.toUtc().microsecondsSinceEpoch}';

  static Future<void> acknowledgeDeliveryPayload(
    String userId,
    String payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pendingDeliveriesPrefix$userId';
    final pending = prefs.getStringList(key) ?? [];
    pending.remove(payload);
    final saved = await prefs.setStringList(key, pending);
    if (!saved) {
      throw StateError('Could not acknowledge local notification delivery.');
    }
  }

  /// Handles both foreground and background notification responses.
  static Future<void> handleResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    final payloadString = response.payload;

    debugPrint(
      'ALARM ACTION EVENT: actionId=$actionId, notificationId=${response.id}',
    );

    Map<String, dynamic> payload = {};
    if (payloadString != null && payloadString.isNotEmpty) {
      try {
        payload = jsonDecode(payloadString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error decoding notification payload: $e');
      }
    }

    if (actionId == null || actionId.isEmpty) {
      if (payload.isNotEmpty) {
        final deliveryPayload = withOccurrenceIdentity(payload);
        await _queueDelivery(deliveryPayload);
        final deliveryCallback = onDelivery;
        if (deliveryCallback != null) {
          await deliveryCallback(deliveryPayload);
        }
        final bodyTapCallback = onBodyTap;
        if (bodyTapCallback != null) {
          await bodyTapCallback(jsonEncode(deliveryPayload));
        }
      }
      return;
    }

    final deliveryPayload = withOccurrenceIdentity(payload);
    await _queueDelivery(deliveryPayload);
    final deliveryCallback = onDelivery;
    if (deliveryCallback != null) {
      await deliveryCallback(deliveryPayload);
    }

    final rawAlarmId = payload['alarmId'] ?? response.id;
    final alarmId = rawAlarmId is num
        ? rawAlarmId.toInt()
        : int.tryParse(rawAlarmId.toString()) ?? (response.id ?? 0);

    if (actionId == actionSnooze) {
      final title = payload['title']?.toString() ?? 'Alarm';
      final description = payload['description']?.toString() ?? '';
      final soundUri = payload['soundUri']?.toString();
      final soundName = payload['soundName']?.toString();
      final soundEnabled = payload['soundEnabled'] as bool? ?? true;
      final vibrationEnabled = payload['vibrationEnabled'] as bool? ?? true;

      final prefs = await SharedPreferences.getInstance();
      final configuredMinutes =
          prefs.getInt('alarm_snooze_interval_minutes') ?? 5;
      final snoozeMinutes =
          (payload['snoozeIntervalMinutes'] as num?)?.toInt() ??
          configuredMinutes;

      debugPrint('Snoozing alarm $alarmId for $snoozeMinutes minutes...');

      await AlarmScheduleService.instance.scheduleSnoozeAlarm(
        alarmId: alarmId,
        title: title,
        description: description,
        soundUri: soundUri,
        soundName: soundName,
        soundEnabled: soundEnabled,
        vibrationEnabled: vibrationEnabled,
        snoozeMinutes: snoozeMinutes,
        originalPayload: deliveryPayload,
      );
    } else if (actionId == actionDismiss) {
      debugPrint('Dismissing alarm $alarmId (clearing active snooze)...');
      await AlarmScheduleService.instance.cancelSnoozeAlarm(alarmId);
    }
  }

  static Map<String, dynamic> withOccurrenceIdentity(
    Map<String, dynamic> payload,
  ) {
    final result = Map<String, dynamic>.from(payload);
    final existingId = result['sourceEventId']?.toString().trim();
    if (existingId != null && existingId.isNotEmpty) return result;

    final scheduledAt = DateTime.tryParse(
      result['scheduledAt']?.toString() ?? '',
    );
    final instanceId = result['alarmInstanceId']?.toString().trim();
    if (scheduledAt != null && instanceId != null && instanceId.isNotEmpty) {
      result['occurrenceDate'] ??= _dateKey(scheduledAt);
      result['sourceEventId'] = alarmOccurrenceEventId(
        alarmInstanceId: instanceId,
        scheduledAt: scheduledAt,
      );
      return result;
    }

    final occurrenceBaseId = result['occurrenceBaseId']?.toString();
    if (occurrenceBaseId != null && occurrenceBaseId.isNotEmpty) {
      final date =
          DateTime.tryParse(result['occurrenceDate']?.toString() ?? '') ??
          scheduledAt ??
          DateTime.now();
      result['occurrenceDate'] = _dateKey(date);
      result['sourceEventId'] = occurrenceEventId(
        occurrenceBaseId: occurrenceBaseId,
        localOccurrenceDate: date,
      );
    }
    return result;
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static Future<void> _queueDelivery(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = payload['userId']?.toString() ?? 'guest';
    final key = '$_pendingDeliveriesPrefix$userId';
    final pending = prefs.getStringList(key) ?? [];
    final encoded = jsonEncode(payload);
    if (!pending.contains(encoded)) {
      pending.add(encoded);
      final saved = await prefs.setStringList(key, pending);
      if (!saved) {
        throw StateError('Could not persist local notification delivery.');
      }
    }
  }
}
