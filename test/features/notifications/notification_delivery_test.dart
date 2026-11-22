import 'dart:convert';

import 'package:eleven11/features/alarms/services/alarm_action_handler.dart';
import 'package:eleven11/features/notifications/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recurring reminder occurrence IDs are stable per local date', () {
    final firstAttempt = AlarmActionHandler.occurrenceEventId(
      occurrenceBaseId: 'alarm:42:weekday:2',
      localOccurrenceDate: DateTime(2026, 4, 7),
    );
    final snoozedAttempt = AlarmActionHandler.occurrenceEventId(
      occurrenceBaseId: 'alarm:42:weekday:2',
      localOccurrenceDate: DateTime(2026, 4, 7),
    );
    final followingWeek = AlarmActionHandler.occurrenceEventId(
      occurrenceBaseId: 'alarm:42:weekday:2',
      localOccurrenceDate: DateTime(2026, 4, 14),
    );

    expect(snoozedAttempt, firstAttempt);
    expect(followingWeek, isNot(firstAttempt));
  });

  test(
    'background FCM messages are queued once for their registered user',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eleven11_notification_fcm_owner', 'user-a');
      final message = RemoteMessage(
        messageId: 'message-123',
        data: {'userId': 'user-a', 'type': 'task', 'taskId': 'task-123'},
        notification: const RemoteNotification(
          title: 'Task reminder',
          body: 'Time to work on your task.',
        ),
      );

      await NotificationService.queueBackgroundFcmMessage(message);
      await NotificationService.queueBackgroundFcmMessage(message);

      final pending = prefs.getStringList('notification_pending_fcm_v1_user-a');
      expect(pending, hasLength(1));
      final payload = jsonDecode(pending!.single) as Map<String, dynamic>;
      expect(payload['sourceEventId'], 'fcm:message-123');
      expect(payload['userId'], 'user-a');
      expect((payload['data'] as Map)['taskId'], 'task-123');
    },
  );

  test('background FCM messages without a recipient are not queued', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('eleven11_notification_fcm_owner', 'user-a');
    final message = RemoteMessage(
      messageId: 'message-without-owner',
      data: {'type': 'task'},
    );

    await NotificationService.queueBackgroundFcmMessage(message);

    expect(prefs.getStringList('notification_pending_fcm_v1_user-a'), isNull);
  });
}
