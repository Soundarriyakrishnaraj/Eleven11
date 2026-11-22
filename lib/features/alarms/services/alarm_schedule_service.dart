import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../screens/alarm_audio_service.dart';
import 'alarm_action_handler.dart';

/// A single independent alarm/reminder.
class AlarmSchedule {
  const AlarmSchedule({
    required this.id,
    required this.instanceId,
    required this.userId,
    required this.title,
    this.description = '',
    required this.hour,
    required this.minute,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.enabled = true,
    this.vibrationEnabled = true,
    this.soundEnabled = true,
    this.soundUri,
    this.soundName,
    this.taskId,
  });

  final int id;
  final String instanceId;
  final String userId;
  final String title;
  final String description;
  final int hour;
  final int minute;

  /// Monday = 1, Tuesday = 2, ... Sunday = 7.
  final List<int> weekdays;

  final bool enabled;
  final bool vibrationEnabled;
  final bool soundEnabled;
  final String? soundUri;
  final String? soundName;
  final String? taskId;

  AlarmSchedule copyWith({
    String? title,
    String? description,
    int? hour,
    int? minute,
    List<int>? weekdays,
    bool? enabled,
    bool? vibrationEnabled,
    bool? soundEnabled,
    String? soundUri,
    String? soundName,
    bool clearSoundUri = false,
    String? taskId,
  }) {
    return AlarmSchedule(
      id: id,
      instanceId: instanceId,
      userId: userId,
      title: title ?? this.title,
      description: description ?? this.description,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundUri: clearSoundUri ? null : (soundUri ?? this.soundUri),
      soundName: clearSoundUri ? null : (soundName ?? this.soundName),
      taskId: taskId ?? this.taskId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'instanceId': instanceId,
    'userId': userId,
    'title': title,
    'description': description,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'enabled': enabled,
    'vibrationEnabled': vibrationEnabled,
    'soundEnabled': soundEnabled,
    'soundUri': soundUri,
    'soundName': soundName,
    'taskId': taskId,
  };

  factory AlarmSchedule.fromJson(Map<String, dynamic> json) {
    final storedInstanceId = json['instanceId'];
    final soundUri = json['soundUri'] as String?;
    final soundName =
        json['soundName'] as String? ??
        AlarmAudioService.getSoundDisplayName(soundUri);

    return AlarmSchedule(
      id: (json['id'] as num).toInt(),
      instanceId: _isAlarmInstanceId(storedInstanceId)
          ? (storedInstanceId as String).trim()
          : generateInstanceId(),
      userId: json['userId'] as String,
      title: json['title'] as String? ?? 'Reminder',
      description: json['description'] as String? ?? '',
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
      weekdays: (json['weekdays'] as List<dynamic>? ?? [1, 2, 3, 4, 5, 6, 7])
          .map((e) => (e as num).toInt())
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      soundUri: soundUri,
      soundName: soundName,
      taskId: json['taskId'] as String?,
    );
  }

  static String generateInstanceId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static bool _isAlarmInstanceId(Object? value) =>
      value is String &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value.trim());
}

class AlarmScheduleOccurrence {
  const AlarmScheduleOccurrence({
    required this.alarm,
    required this.scheduledAt,
  });

  final AlarmSchedule alarm;
  final DateTime scheduledAt;

  String get sourceEventId => AlarmActionHandler.alarmOccurrenceEventId(
    alarmInstanceId: alarm.instanceId,
    scheduledAt: scheduledAt,
  );
}

/// Stores and schedules multiple independent alarms.
class AlarmScheduleService {
  AlarmScheduleService._();

  static final AlarmScheduleService instance = AlarmScheduleService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _storagePrefix = 'eleven11_alarm_schedules_';
  static const String _counterKey = 'eleven11_alarm_next_id';
  static const String _scheduledIdsPrefix =
      'eleven11_alarm_scheduled_occurrences_v1_';
  // Keep below iOS' pending-request cap; the horizon is refreshed on resume.
  static const int _maxPendingOccurrences = 48;

  static const String actionSnooze = 'action_snooze';
  static const String actionDismiss = 'action_dismiss';

  /// Separate ID range for temporary snooze notifications.
  static int snoozeNotificationId(int alarmId) {
    return 8000000 + (alarmId % 100000);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      debugPrint('Timezone setup failed in AlarmScheduleService: $e');
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(
        notificationCategories: [
          DarwinNotificationCategory(
            'eleven11_alarm_category',
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain(actionSnooze, 'Snooze (5m)'),
              DarwinNotificationAction.plain(
                actionDismiss,
                'Dismiss',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.destructive,
                },
              ),
            ],
          ),
        ],
      ),
    );

    await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: AlarmActionHandler.handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _initialized = true;
  }

  /// Requests notification and exact-alarm permission.
  Future<bool> requestPermissions() async {
    await initialize();

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return true;

    try {
      final notificationPermission = await android
          .requestNotificationsPermission();

      if (notificationPermission == false) return false;

      var exactAllowed = await android.canScheduleExactNotifications() ?? false;

      if (!exactAllowed) {
        await android.requestExactAlarmsPermission();
        exactAllowed = await android.canScheduleExactNotifications() ?? false;
      }

      return exactAllowed;
    } catch (e) {
      debugPrint('Alarm permission request error: $e');
      return false;
    }
  }

  Future<bool> canScheduleExactAlarms() async {
    await initialize();

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return true;

    try {
      return await android.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  String _storageKey(String userId) => '$_storagePrefix$userId';
  String _scheduledIdsKey(String userId) => '$_scheduledIdsPrefix$userId';

  Future<List<AlarmSchedule>> getAlarms(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(userId));

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      var migrated = false;
      final alarms = decoded.map((item) {
        final json = Map<String, dynamic>.from(item as Map);
        final alarm = AlarmSchedule.fromJson(json);
        if (json['instanceId'] != alarm.instanceId) migrated = true;
        return alarm;
      }).toList();
      if (migrated) await _saveAlarms(userId, alarms);
      return alarms..sort(_compareAlarms);
    } catch (e) {
      Error.throwWithStackTrace(
        StateError('Unable to read or migrate saved alarms for $userId: $e'),
        StackTrace.current,
      );
    }
  }

  int _compareAlarms(AlarmSchedule a, AlarmSchedule b) {
    final aTime = a.hour * 60 + a.minute;
    final bTime = b.hour * 60 + b.minute;
    return aTime.compareTo(bTime);
  }

  Future<void> _saveAlarms(String userId, List<AlarmSchedule> alarms) async {
    final prefs = await SharedPreferences.getInstance();

    final saved = await prefs.setString(
      _storageKey(userId),
      jsonEncode(alarms.map((alarm) => alarm.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Could not persist alarms for $userId.');
    }
  }

  Future<int> _nextId() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_counterKey) ?? 1000) + 1;
    final saved = await prefs.setInt(_counterKey, next);
    if (!saved) {
      throw StateError('Could not allocate a local alarm scheduling ID.');
    }
    return next;
  }

  Future<void> _replaceAlarms(
    String userId,
    List<AlarmSchedule> previousAlarms,
    List<AlarmSchedule> updatedAlarms, {
    List<AlarmSchedule> legacyAlarms = const [],
  }) async {
    final alarmsToCancel = <AlarmSchedule>[
      ...previousAlarms,
      ...updatedAlarms,
      ...legacyAlarms,
    ];
    try {
      await _scheduleUserAlarms(
        userId,
        updatedAlarms,
        legacyAlarms: alarmsToCancel,
      );
      await _saveAlarms(userId, updatedAlarms);
    } catch (error, stackTrace) {
      try {
        await _scheduleUserAlarms(
          userId,
          previousAlarms,
          legacyAlarms: alarmsToCancel,
        );
        await _saveAlarms(userId, previousAlarms);
      } catch (restoreError) {
        throw StateError(
          'Alarm change failed ($error), and restoring the previous schedule '
          'also failed ($restoreError).',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Creates and schedules a new alarm.
  Future<AlarmSchedule> createAlarm({
    required String userId,
    required String title,
    String description = '',
    required int hour,
    required int minute,
    List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    bool enabled = true,
    bool vibrationEnabled = true,
    bool soundEnabled = true,
    String? soundUri,
    String? soundName,
    String? taskId,
  }) async {
    await initialize();

    _validateTime(hour, minute);
    _validateWeekdays(weekdays);

    final previousAlarms = await getAlarms(userId);
    final alarm = AlarmSchedule(
      id: await _nextId(),
      instanceId: AlarmSchedule.generateInstanceId(),
      userId: userId,
      title: title,
      description: description,
      hour: hour,
      minute: minute,
      weekdays: List<int>.from(weekdays),
      enabled: enabled,
      vibrationEnabled: vibrationEnabled,
      soundEnabled: soundEnabled,
      soundUri: soundUri,
      soundName: soundName,
      taskId: taskId,
    );

    final updatedAlarms = [...previousAlarms, alarm];
    await _replaceAlarms(userId, previousAlarms, updatedAlarms);

    return alarm;
  }

  /// Updates an existing alarm.
  Future<void> updateAlarm(AlarmSchedule updated) async {
    await initialize();

    _validateTime(updated.hour, updated.minute);

    if (updated.enabled) {
      _validateWeekdays(updated.weekdays);
    }

    final previousAlarms = await getAlarms(updated.userId);
    final updatedAlarms = List<AlarmSchedule>.from(previousAlarms);
    final index = updatedAlarms.indexWhere((a) => a.id == updated.id);

    if (index == -1) {
      throw Exception('Alarm not found.');
    }

    final previous = updatedAlarms[index];

    await cancelSnoozeAlarm(updated.id);

    updatedAlarms[index] = updated;
    await _replaceAlarms(
      updated.userId,
      previousAlarms,
      updatedAlarms,
      legacyAlarms: [previous, updated],
    );
  }

  /// Deletes an alarm and its scheduled notifications.
  Future<void> deleteAlarm(AlarmSchedule alarm) async {
    await initialize();

    await cancelSnoozeAlarm(alarm.id);

    final previousAlarms = await getAlarms(alarm.userId);
    final updatedAlarms = previousAlarms
        .where((a) => a.id != alarm.id)
        .toList();
    await _replaceAlarms(
      alarm.userId,
      previousAlarms,
      updatedAlarms,
      legacyAlarms: [alarm],
    );
  }

  Future<void> setAlarmEnabled(AlarmSchedule alarm, bool enabled) async {
    await updateAlarm(alarm.copyWith(enabled: enabled));
  }

  /// Cancels the recurring notifications belonging to this alarm.
  Future<void> cancelAlarm(AlarmSchedule alarm) async {
    await initialize();

    for (final weekday in alarm.weekdays) {
      await _notifications.cancel(id: _notificationId(alarm.id, weekday));
    }
  }

  /// Schedules a rolling set of dated, one-shot occurrences for an alarm.
  Future<void> scheduleAlarm(AlarmSchedule alarm) async {
    await initialize();

    _validateTime(alarm.hour, alarm.minute);
    _validateWeekdays(alarm.weekdays);
    final alarms = await getAlarms(alarm.userId);
    final index = alarms.indexWhere((item) => item.id == alarm.id);
    if (index == -1) {
      alarms.add(alarm);
    } else {
      alarms[index] = alarm;
    }
    await _scheduleUserAlarms(alarm.userId, alarms, legacyAlarms: [alarm]);
  }

  Future<void> _scheduleUserAlarms(
    String userId,
    List<AlarmSchedule> alarms, {
    List<AlarmSchedule> legacyAlarms = const [],
  }) async {
    if (alarms.any((alarm) => alarm.enabled)) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null &&
          !(await android.canScheduleExactNotifications() ?? false)) {
        throw StateError(
          'Exact alarm permission is not enabled. '
          'Allow Alarms and reminders for Eleven11 in Android settings.',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final scheduledIdsKey = _scheduledIdsKey(userId);
    final previouslyScheduledIds = prefs.getStringList(scheduledIdsKey) ?? [];
    for (final id in previouslyScheduledIds) {
      final notificationId = int.tryParse(id);
      if (notificationId != null) {
        await _notifications.cancel(id: notificationId);
      }
    }

    final legacyIds = <int>{};
    for (final alarm in [...alarms, ...legacyAlarms]) {
      for (final weekday in alarm.weekdays) {
        legacyIds.add(_notificationId(alarm.id, weekday));
      }
    }
    for (final id in legacyIds) {
      await _notifications.cancel(id: id);
    }

    final occurrences = planUpcomingOccurrences(alarms, now: DateTime.now());
    final usedNotificationIds = <int>{};
    final notificationIds = <int>[];
    for (final occurrence in occurrences) {
      var notificationId = _notificationIdForSourceEvent(
        occurrence.sourceEventId,
      );
      while (!usedNotificationIds.add(notificationId)) {
        notificationId = notificationId == 1999999999
            ? 1500000000
            : notificationId + 1;
      }
      notificationIds.add(notificationId);
    }

    final savedIds = await prefs.setStringList(
      scheduledIdsKey,
      notificationIds.map((id) => id.toString()).toList(),
    );
    if (!savedIds) {
      throw StateError('Could not persist scheduled alarm occurrence IDs.');
    }

    for (var index = 0; index < occurrences.length; index++) {
      final occurrence = occurrences[index];
      final alarm = occurrence.alarm;
      final scheduledDate = tz.TZDateTime.from(
        occurrence.scheduledAt,
        tz.local,
      );
      final body = alarm.description.isEmpty
          ? 'It is time for your reminder.'
          : alarm.description;

      await _notifications.zonedSchedule(
        id: notificationIds[index],
        title: alarm.title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: await _notificationDetails(alarm),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: jsonEncode({
          'type': alarm.taskId == null ? 'alarm' : 'task',
          'target': alarm.taskId == null ? 'alarm' : 'task',
          'alarmId': alarm.id,
          'alarmInstanceId': alarm.instanceId,
          'userId': alarm.userId,
          'taskId': alarm.taskId,
          'weekday': scheduledDate.weekday,
          'occurrenceDate': _dateKey(scheduledDate),
          'scheduledAt': scheduledDate.toUtc().toIso8601String(),
          'occurrenceBaseId': 'alarm:${alarm.instanceId}',
          'sourceEventId': occurrence.sourceEventId,
          'title': alarm.title,
          'body': body,
          'description': alarm.description,
          'soundUri': alarm.soundUri,
          'soundName': alarm.soundName,
          'soundEnabled': alarm.soundEnabled,
          'vibrationEnabled': alarm.vibrationEnabled,
        }),
      );
    }
  }

  static List<AlarmScheduleOccurrence> planUpcomingOccurrences(
    List<AlarmSchedule> alarms, {
    required DateTime now,
    int maxOccurrences = _maxPendingOccurrences,
    int weeks = 12,
  }) {
    final occurrences = <AlarmScheduleOccurrence>[];
    for (final alarm in alarms.where((item) => item.enabled)) {
      for (final weekday in alarm.weekdays.toSet()) {
        var date = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.hour,
          alarm.minute,
        );
        while (date.weekday != weekday || !date.isAfter(now)) {
          date = DateTime(
            date.year,
            date.month,
            date.day + 1,
            alarm.hour,
            alarm.minute,
          );
        }
        for (var week = 0; week < weeks; week++) {
          final scheduledAt = DateTime(
            date.year,
            date.month,
            date.day + (week * 7),
            alarm.hour,
            alarm.minute,
          );
          occurrences.add(
            AlarmScheduleOccurrence(alarm: alarm, scheduledAt: scheduledAt),
          );
        }
      }
    }
    occurrences.sort((a, b) {
      final byTime = a.scheduledAt.compareTo(b.scheduledAt);
      return byTime != 0 ? byTime : a.sourceEventId.compareTo(b.sourceEventId);
    });
    return occurrences.take(maxOccurrences).toList();
  }

  int _notificationIdForSourceEvent(String sourceEventId) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(sourceEventId)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return 1500000000 + (hash % 500000000);
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Schedules a one-time snooze without cancelling recurring alarms.
  Future<void> scheduleSnoozeAlarm({
    required int alarmId,
    required String title,
    String description = '',
    String? soundUri,
    String? soundName,
    bool soundEnabled = true,
    bool vibrationEnabled = true,
    int snoozeMinutes = 5,
    Map<String, dynamic>? originalPayload,
  }) async {
    await initialize();

    if (snoozeMinutes <= 0) {
      throw ArgumentError.value(
        snoozeMinutes,
        'snoozeMinutes',
        'Must be greater than zero.',
      );
    }

    final snoozeId = snoozeNotificationId(alarmId);
    await _notifications.cancel(id: snoozeId);

    final scheduledDate = tz.TZDateTime.now(tz.local)
        .add(Duration(minutes: snoozeMinutes));

    final soundInfo = AlarmAudioService.resolveAndroidSound(
      soundUri,
      soundEnabled,
    );

    final soundKey = soundEnabled ? soundInfo.$2 : 'muted';
    final vibrateKey = vibrationEnabled ? 'vibrate' : 'silent';
    final channelId = 'eleven11_snooze_${_stableHash(soundKey)}_$vibrateKey';

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          'Eleven11 Snooze Alarms',
          description: 'Snoozed alarm reminders',
          importance: Importance.max,
          sound: soundInfo.$1,
          playSound: soundEnabled,
          enableVibration: vibrationEnabled,
          vibrationPattern: vibrationEnabled
              ? Int64List.fromList([0, 500, 250, 500])
              : null,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Eleven11 Snooze Alarms',
      channelDescription: 'Snoozed alarm reminders',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      playSound: soundEnabled,
      sound: soundInfo.$1,
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled
          ? Int64List.fromList([0, 500, 250, 500])
          : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          actionSnooze,
          'Snooze (5m)',
          cancelNotification: true,
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          actionDismiss,
          'Dismiss',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    );

    final payloadMap = Map<String, dynamic>.from(
      originalPayload ?? <String, dynamic>{},
    );

    payloadMap['alarmId'] = alarmId;
    payloadMap['title'] = title;
    payloadMap['description'] = description;
    payloadMap['soundUri'] = soundUri;
    payloadMap['soundName'] = soundName;
    payloadMap['soundEnabled'] = soundEnabled;
    payloadMap['vibrationEnabled'] = vibrationEnabled;
    payloadMap['isSnooze'] = true;

    await _notifications.zonedSchedule(
      id: snoozeId,
      title: title,
      body: description.isEmpty ? 'Snoozed reminder' : description,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          categoryIdentifier: 'eleven11_alarm_category',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: jsonEncode(payloadMap),
    );
  }

  /// Cancels a pending snooze for this alarm.
  Future<void> cancelSnoozeAlarm(int alarmId) async {
    await initialize();
    await _notifications.cancel(id: snoozeNotificationId(alarmId));
  }

  /// Restores saved alarms for a signed-in user.
  Future<void> restoreAlarms(String userId) async {
    await initialize();

    final alarms = await getAlarms(userId);
    final exactAllowed = await canScheduleExactAlarms();

    if (!exactAllowed) return;
    await _scheduleUserAlarms(userId, alarms);
  }

  void _validateTime(int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('Invalid alarm time.');
    }
  }

  void _validateWeekdays(List<int> weekdays) {
    if (weekdays.isEmpty || weekdays.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('Select valid repeat days.');
    }
  }

  int _notificationId(int alarmId, int weekday) {
    return 1000000 + (alarmId * 10) + weekday;
  }

  Future<NotificationDetails> _notificationDetails(AlarmSchedule alarm) async {
    final soundUri = alarm.soundEnabled ? alarm.soundUri : null;

    final soundInfo = AlarmAudioService.resolveAndroidSound(
      soundUri,
      alarm.soundEnabled,
    );

    final soundKey = alarm.soundEnabled ? soundInfo.$2 : 'muted';
    final vibrateKey = alarm.vibrationEnabled ? 'vibrate' : 'silent';

    final channelId = 'eleven11_alarm_${_stableHash(soundKey)}_$vibrateKey';

    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          'Eleven11 Alarms',
          description: 'Scheduled alarms and personal reminders',
          importance: Importance.max,
          sound: soundInfo.$1,
          playSound: alarm.soundEnabled,
          enableVibration: alarm.vibrationEnabled,
          vibrationPattern: alarm.vibrationEnabled
              ? Int64List.fromList([0, 500, 250, 500])
              : null,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Eleven11 Alarms',
      channelDescription: 'Scheduled alarms and personal reminders',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      playSound: alarm.soundEnabled,
      sound: soundInfo.$1,
      enableVibration: alarm.vibrationEnabled,
      vibrationPattern: alarm.vibrationEnabled
          ? Int64List.fromList([0, 500, 250, 500])
          : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          actionSnooze,
          'Snooze (5m)',
          cancelNotification: true,
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          actionDismiss,
          'Dismiss',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        categoryIdentifier: 'eleven11_alarm_category',
      ),
    );
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;

    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }

    return hash;
  }
}
