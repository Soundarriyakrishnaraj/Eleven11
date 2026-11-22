import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../alarms/screens/alarm_audio_service.dart';
import '../alarms/services/alarm_action_handler.dart';
import '../alarms/services/alarm_schedule_service.dart';
import 'models/notification_model.dart';
import 'models/notification_preferences_model.dart';
import 'services/notification_navigation.dart';
import 'services/notification_ownership.dart';
import 'services/notification_sync.dart';
import 'services/notification_storage.dart';

class NotificationService with WidgetsBindingObserver {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final NotificationStorage _storage = NotificationStorage.instance;

  bool _initialized = false;
  bool _syncing = false;
  bool _syncRequested = false;
  int _currentUnreadCount = 0;
  String? _activeAuthUserId;
  String? _installationId;
  String? _installationOwnerUserId;
  Timer? _outboxRetryTimer;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundFcmSubscription;
  StreamSubscription<RemoteMessage>? _openedFcmSubscription;
  StreamSubscription<String>? _installationSubscription;
  NotificationSyncCoordinator? _notificationSyncCoordinator;

  // Real-time broadcast streams for reactive UI updates
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();
  final StreamController<List<AppNotification>> _notificationsController =
      StreamController<List<AppNotification>>.broadcast();

  Stream<int> get unreadCountStream => _unreadCountController.stream;
  Stream<List<AppNotification>> get notificationsStream =>
      _notificationsController.stream;
  int get currentUnreadCount => _currentUnreadCount;

  static const String _scheduleOwnerKey =
      'eleven11_notification_schedule_owner';
  static const String _fcmOwnerKey = 'eleven11_notification_fcm_owner';
  static const String _installationIdKey =
      'eleven11_notification_installation_id';
  static const String _pendingFcmPrefix = 'notification_pending_fcm_v1_';
  static const String _dailyOccurrencesPrefix =
      'eleven11_daily_notification_occurrences_v1_';
  static const String _dailyAlarmSettingsPrefix =
      'eleven11_daily_alarm_settings_v1_';
  static const String _pendingDeviceTokenCleanupsKey =
      'eleven11_pending_device_token_cleanups_v1';
  static const int _dailyOccurrenceHorizon = 4;

  static Future<void> queueBackgroundFcmMessage(RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final incomingOwner = message.data['userId']?.toString();
    final registeredOwner = prefs.getString(_fcmOwnerKey);
    if (incomingOwner == null ||
        incomingOwner.trim().isEmpty ||
        registeredOwner == null ||
        incomingOwner.trim() != registeredOwner) {
      debugPrint('Ignoring background notification for a different account.');
      return;
    }
    final userId = incomingOwner.trim();

    final data = _sanitizeNotificationData(
      Map<String, dynamic>.from(message.data),
    );
    final sourceEventId = _fcmSourceEventId(message);
    final payload = <String, dynamic>{
      'type': data['type']?.toString() ?? 'motivation',
      'title':
          message.notification?.title ??
          data['title']?.toString() ??
          'Eleven11',
      'body':
          message.notification?.body ??
          data['body']?.toString() ??
          'Your daily motivation is waiting.',
      'sourceEventId': sourceEventId,
      'userId': userId,
      'data': data,
    };
    final key = '$_pendingFcmPrefix$userId';
    final pending = prefs.getStringList(key) ?? [];
    final alreadyQueued = pending.any((encoded) {
      try {
        return jsonDecode(encoded)['sourceEventId'] == sourceEventId;
      } on Object {
        return false;
      }
    });
    if (!alreadyQueued) {
      pending.add(jsonEncode(payload));
      final saved = await prefs.setStringList(key, pending);
      if (!saved) {
        throw StateError('Could not retain background notification delivery.');
      }
    }
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'eleven11_daily_quotes',
    'Eleven11 Reminders',
    description: 'Daily motivation and personal reminders.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _dailyAlarmChannel =
      AndroidNotificationChannel(
        'eleven11_daily_alarm',
        'Eleven11 Daily Alarm',
        description: 'Your daily Eleven11 alarm.',
        importance: Importance.max,
      );

  static const AndroidNotificationChannel _taskAlarmChannel =
      AndroidNotificationChannel(
        'eleven11_task_alarm',
        'Eleven11 Task Reminders',
        description: 'Reminders for your tasks and goals.',
        importance: Importance.max,
      );

  static const int motivationReminderId = 1101;
  static const int taskReminderId = 1102;
  static const int dailyAlarmId = 1103;
  static const int todayTaskReminderId = 1104;

  SupabaseClient get _supabase => Supabase.instance.client;
  String? get _currentUserId => _supabase.auth.currentUser?.id;
  String get _storageUserId =>
      _currentUserId ?? NotificationStorage.guestUserId;

  void _emitUnreadCount(int count) {
    _currentUnreadCount = count;
    _unreadCountController.add(count);
  }

  NotificationSyncCoordinator get _syncCoordinator =>
      _notificationSyncCoordinator ??= NotificationSyncCoordinator(
        storage: _storage,
        remote: SupabaseNotificationRemoteStore(_supabase),
        currentUserId: () => _currentUserId,
      );

  // ============================================================
  // CUSTOM ALARM SOUNDS, SOUND AND VIBRATION
  // ============================================================

  Future<NotificationDetails> _alarmDetails(
    String type,
    AndroidNotificationChannel fallbackChannel,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final soundEnabled = prefs.getBool('alarm_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('alarm_vibration_enabled') ?? true;

    String? soundUri;
    switch (type) {
      case 'daily':
        soundUri = prefs.getString('alarm_daily_audio_uri');
        break;
      case 'task':
        soundUri = prefs.getString('alarm_task_audio_uri');
        break;
      case 'goal':
        soundUri = prefs.getString('alarm_goal_audio_uri');
        break;
    }

    final soundInfo = AlarmAudioService.resolveAndroidSound(
      soundUri,
      soundEnabled,
    );

    final channelId =
        '${fallbackChannel.id}_${type}_'
        '${soundEnabled ? 1 : 0}_'
        '${vibrationEnabled ? 1 : 0}_'
        '${soundInfo.$2}';

    if (Platform.isAndroid) {
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await android?.deleteNotificationChannel(channelId: channelId);
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          '${fallbackChannel.name} $type',
          description: fallbackChannel.description,
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

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        '${fallbackChannel.name} $type',
        channelDescription: fallbackChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        sound: soundInfo.$1,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled
            ? Int64List.fromList([0, 500, 250, 500])
            : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        autoCancel: true,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'action_snooze',
            'Snooze (5m)',
            cancelNotification: true,
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'action_dismiss',
            'Dismiss',
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        categoryIdentifier: 'eleven11_alarm_category',
      ),
    );
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      debugPrint('Timezone setup failed: $e');
    }

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        notificationCategories: [
          DarwinNotificationCategory(
            'eleven11_alarm_category',
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain('action_snooze', 'Snooze (5m)'),
              DarwinNotificationAction.plain(
                'action_dismiss',
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

    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    AlarmActionHandler.onBodyTap = handleLocalNotificationTap;
    AlarmActionHandler.onDelivery = _recordLocalDelivery;

    NotificationAppLaunchDetails? localLaunchDetails;
    RemoteMessage? initialFcmMessage;
    try {
      localLaunchDetails = await _local.getNotificationAppLaunchDetails();
    } catch (error) {
      debugPrint('Reading local notification launch details failed: $error');
    }

    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_dailyAlarmChannel);
    await androidPlugin?.createNotificationChannel(_taskAlarmChannel);

    WidgetsBinding.instance.addObserver(this);
    _foregroundFcmSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );

    _openedFcmSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      _handleFcmNotificationTap(message);
    });

    _installationSubscription = _messaging.onRegistered.listen((
      installationId,
    ) {
      _installationId = installationId;
      unawaited(
        _saveInstallationId(installationId).catchError((Object error) {
          debugPrint('Saving device installation failed: $error');
        }),
      );
    });

    final devicePrefs = await SharedPreferences.getInstance();
    _installationId ??= devicePrefs.getString(_installationIdKey);
    _activeAuthUserId = _currentUserId;
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) async {
      final userId = _supabase.auth.currentUser?.id;
      if (event.event == AuthChangeEvent.signedIn && userId != null) {
        final previousUserId = _activeAuthUserId;
        if (previousUserId != null && previousUserId != userId) {
          final prefs = await SharedPreferences.getInstance();
          final previousToken =
              _installationId ?? prefs.getString(_installationIdKey);
          if (previousToken != null) {
            await _queuePendingDeviceTokenCleanup(
              previousUserId,
              previousToken,
            );
          }
          await _messaging.unregister().timeout(const Duration(seconds: 5));
          await _clearDeviceTokenLocalState();
        }
        await _retryPendingDeviceTokenCleanups(userId);
        _activeAuthUserId = userId;
        _notificationsController.add([]);
        _emitUnreadCount(0);
        await _activateNotificationSchedules(userId);
        await _publishCachedNotifications(userId);
        await registerDeviceToken();
        await syncReminderPreferences();
        await _synchronizeUserNotifications(userId);
        await _drainPendingLocalDeliveries();
        await _drainPendingFcmMessages();
      } else if (event.event == AuthChangeEvent.signedOut) {
        final previousUserId = _activeAuthUserId;
        _activeAuthUserId = null;
        var tokenInvalidated = _installationId == null;
        if (previousUserId != null && _installationId != null) {
          try {
            await _queuePendingDeviceTokenCleanup(
              previousUserId,
              _installationId!,
            );
            await _messaging.unregister().timeout(const Duration(seconds: 5));
            tokenInvalidated = true;
          } catch (error) {
            debugPrint(
              'Invalidating the signed-out Firebase installation failed: '
              '$error',
            );
          }
        }
        if (tokenInvalidated) {
          await _clearDeviceTokenLocalState();
        }
        await _deactivateNotificationSchedules();
        _outboxRetryTimer?.cancel();
        _outboxRetryTimer = null;
        _syncRequested = false;
        _emitUnreadCount(0);
        _notificationsController.add([]);
      }
    });

    try {
      initialFcmMessage = await _messaging.getInitialMessage();
    } catch (error) {
      debugPrint('Reading initial Firebase notification failed: $error');
    }

    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (permission.authorizationStatus != AuthorizationStatus.denied) {
      await registerDeviceToken();
    }

    _initialized = true;

    if (_currentUserId != null) {
      await _activateNotificationSchedules(_currentUserId!);
      await syncReminderPreferences();
      await _publishCachedNotifications(_currentUserId!);
      await _synchronizeUserNotifications(_currentUserId!);
    }

    await _drainPendingLocalDeliveries();
    await _drainPendingFcmMessages();
    await _reconcileActiveNotifications();
    await WidgetsBinding.instance.endOfFrame;
    final launchResponse = localLaunchDetails?.notificationResponse;
    if (localLaunchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      if (launchResponse.actionId != null &&
          launchResponse.actionId!.isNotEmpty) {
        await AlarmActionHandler.handleResponse(launchResponse);
      } else {
        await handleLocalNotificationTap(launchResponse.payload);
      }
    } else if (initialFcmMessage != null) {
      await _handleFcmNotificationTap(initialFcmMessage);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final userId = _currentUserId;
      unawaited(_drainPendingLocalDeliveries());
      unawaited(_drainPendingFcmMessages());
      unawaited(_reconcileActiveNotifications());
      if (userId != null) {
        unawaited(
          AlarmScheduleService.instance.restoreAlarms(userId).catchError((
            Object error,
          ) {
            debugPrint('Refreshing recurring alarm schedules failed: $error');
          }),
        );
        unawaited(
          restoreDailyAlarm(userId).catchError((Object error) {
            debugPrint('Refreshing the daily alarm schedule failed: $error');
          }),
        );
        unawaited(
          syncReminderPreferences().catchError((Object error) {
            debugPrint('Refreshing daily reminder schedules failed: $error');
          }),
        );
        unawaited(_synchronizeUserNotifications(userId));
      }
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _outboxRetryTimer?.cancel();
    _outboxRetryTimer = null;
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _foregroundFcmSubscription?.cancel();
    _foregroundFcmSubscription = null;
    await _openedFcmSubscription?.cancel();
    _openedFcmSubscription = null;
    await _installationSubscription?.cancel();
    _installationSubscription = null;
    AlarmActionHandler.onBodyTap = null;
    AlarmActionHandler.onDelivery = null;
    _initialized = false;
  }

  void _onNotificationResponse(NotificationResponse response) async {
    if (response.actionId != null && response.actionId!.isNotEmpty) {
      await AlarmActionHandler.handleResponse(response);
      return;
    }

    await handleLocalNotificationTap(response.payload);
  }

  Future<void> handleLocalNotificationTap(String? payloadString) async {
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final payload = Map<String, dynamic>.from(
        jsonDecode(payloadString) as Map,
      );
      if (!_payloadBelongsToCurrentUser(payload)) return;
      final userId = _currentUserId!;
      final sourceEventId = _sourceEventIdForPayload(payload);
      payload['sourceEventId'] = sourceEventId;
      await _recordLocalDelivery(payload);
      if (_currentUserId != userId) return;
      await _markSourceEventRead(sourceEventId, userId: userId);
      if (_currentUserId != userId) return;

      final type = payload['type']?.toString() ?? 'general';
      await NotificationNavigation.navigateToTarget(
        category: NotificationCategory.fromString(type),
        data: payload,
      );
    } catch (error) {
      debugPrint('Error handling local notification tap: $error');
    }
  }

  Future<void> _handleFcmNotificationTap(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? 'motivation';
    final title =
        message.notification?.title ?? data['title']?.toString() ?? 'Eleven11';
    final body =
        message.notification?.body ??
        data['body']?.toString() ??
        'Your daily motivation is waiting.';
    final sourceEventId = _fcmSourceEventId(message);
    data['sourceEventId'] = sourceEventId;
    data['title'] = title;
    data['body'] = body;

    if (!_payloadBelongsToCurrentUser(data)) return;
    final userId = _currentUserId!;
    await _recordLocalDelivery(data);
    if (_currentUserId != userId) return;
    await _markSourceEventRead(sourceEventId, userId: userId);
    if (_currentUserId != userId) return;

    await NotificationNavigation.navigateToTarget(
      category: NotificationCategory.fromString(type),
      data: data,
    );
  }

  bool _payloadBelongsToCurrentUser(Map<String, dynamic> payload) {
    return NotificationOwnership.matchesAuthenticatedUser(
      recipientUserId: payload['userId'],
      authenticatedUserId: _currentUserId,
    );
  }

  String _sourceEventIdForPayload(Map<String, dynamic> payload) {
    final existing = payload['sourceEventId']?.toString();
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();

    final base = payload['occurrenceBaseId']?.toString();
    final alarmInstanceId = payload['alarmInstanceId']?.toString();
    final scheduledAt = DateTime.tryParse(
      payload['scheduledAt']?.toString() ?? '',
    );
    if (alarmInstanceId != null &&
        alarmInstanceId.isNotEmpty &&
        scheduledAt != null) {
      return AlarmActionHandler.alarmOccurrenceEventId(
        alarmInstanceId: alarmInstanceId,
        scheduledAt: scheduledAt,
      );
    }
    if (base != null && base.isNotEmpty) {
      final date = payload['occurrenceDate']?.toString() ?? _localDateKey();
      return '$base:$date';
    }

    final id = payload['alarmId']?.toString() ?? payload['id']?.toString();
    if (id != null && id.isNotEmpty) {
      return 'local:$id:${_localDateKey()}';
    }

    final canonical = jsonEncode(
      Map<String, dynamic>.fromEntries(
        payload.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    return 'local:${_stableHash(canonical)}:${_localDateKey()}';
  }

  static String _fcmSourceEventId(RemoteMessage message) {
    final explicit =
        message.messageId ??
        message.data['source_event_id']?.toString() ??
        message.data['event_id']?.toString();
    if (explicit != null && explicit.trim().isNotEmpty) {
      return 'fcm:${explicit.trim()}';
    }

    final canonical = jsonEncode(
      Map<String, dynamic>.fromEntries(
        message.data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    return 'fcm:${_stableHash('${message.notification?.title ?? ''}|'
    '${message.notification?.body ?? ''}|$canonical')}';
  }

  static String _stableHash(String value) {
    var firstHash = 0x811c9dc5;
    var secondHash = 0x9e3779b9;
    for (final byte in utf8.encode(value)) {
      firstHash = ((firstHash ^ byte) * 0x01000193) & 0xffffffff;
      secondHash = ((secondHash ^ byte) * 0x85ebca6b) & 0xffffffff;
    }
    return '${firstHash.toRadixString(16).padLeft(8, '0')}'
        '${secondHash.toRadixString(16).padLeft(8, '0')}';
  }

  String _localDateKey([DateTime? date]) {
    final value = date ?? DateTime.now();
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _recordLocalDelivery(Map<String, dynamic> payload) async {
    if (!_payloadBelongsToCurrentUser(payload)) return;
    final type = payload['type']?.toString() ?? 'general';
    final title = payload['title']?.toString() ?? 'Eleven11';
    final body =
        payload['body']?.toString() ??
        payload['description']?.toString() ??
        'A reminder from Eleven11.';
    final sourceEventId = _sourceEventIdForPayload(payload);
    await saveInAppNotification(
      type: type,
      title: title,
      body: body,
      data: payload,
      sourceEventId: sourceEventId,
      respectPreferences: false,
    );
  }

  Future<void> _markSourceEventRead(
    String sourceEventId, {
    required String userId,
  }) async {
    if (_currentUserId != userId) return;
    final items = await _storage.getCachedNotifications(userId);
    if (_currentUserId != userId) return;
    final notification = items
        .where((item) => item.sourceEventId == sourceEventId)
        .firstOrNull;
    if (notification != null && !notification.isRead) {
      await _queueAndSync(
        userId,
        NotificationOutboxOperation.create(
          userId: userId,
          kind: NotificationOperationKind.markRead,
          targetId: notification.id,
          sourceEventId: notification.sourceEventId,
        ),
      );
    }
  }

  Future<void> _drainPendingLocalDeliveries() async {
    final userId = _storageUserId;
    final pending = await AlarmActionHandler.pendingDeliveryPayloads(userId);
    for (final encoded in pending) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        if (_payloadBelongsToCurrentUser(payload)) {
          await _recordLocalDelivery(payload);
        }
        await AlarmActionHandler.acknowledgeDeliveryPayload(userId, encoded);
      } catch (error) {
        debugPrint(
          'Could not process queued local notification delivery: $error',
        );
      }
    }
  }

  Future<void> _drainPendingFcmMessages() async {
    final userId = _currentUserId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pendingFcmPrefix$userId';
    final pending = prefs.getStringList(key) ?? [];
    for (final encoded in pending) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        if (payload['userId']?.toString() != userId) {
          await _removePendingFcmPayload(prefs, key, encoded);
          continue;
        }
        await _recordLocalDelivery(payload);
        await _removePendingFcmPayload(prefs, key, encoded);
      } catch (error) {
        debugPrint('Could not process queued Firebase notification: $error');
      }
    }
  }

  Future<void> _removePendingFcmPayload(
    SharedPreferences prefs,
    String key,
    String payload,
  ) async {
    final pending = prefs.getStringList(key) ?? [];
    pending.remove(payload);
    final saved = await prefs.setStringList(key, pending);
    if (!saved) {
      throw StateError('Could not acknowledge Firebase notification delivery.');
    }
  }

  Future<void> _reconcileActiveNotifications() async {
    // The plugin exposes active payloads on iOS/macOS, but not Android;
    // dismissed notifications that never launch the app cannot be recovered.
    try {
      final active = await _local.getActiveNotifications();
      for (final notification in active) {
        final payloadString = notification.payload;
        if (payloadString == null || payloadString.isEmpty) continue;
        final payload = Map<String, dynamic>.from(
          jsonDecode(payloadString) as Map,
        );
        if (_payloadBelongsToCurrentUser(payload)) {
          await _recordLocalDelivery(payload);
        }
      }
    } on UnimplementedError {
      debugPrint('Active notification reconciliation is unsupported here.');
    } catch (error) {
      debugPrint('Active notification reconciliation failed: $error');
    }
  }

  // ============================================================
  // PERMISSIONS
  // ============================================================

  Future<bool> requestAlarmPermissions() async {
    if (Platform.isAndroid) {
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final notificationGranted =
          await android?.requestNotificationsPermission() ?? true;

      if (!notificationGranted) return false;

      var canScheduleExact =
          await android?.canScheduleExactNotifications() ?? false;

      if (!canScheduleExact) {
        await android?.requestExactAlarmsPermission();

        canScheduleExact =
            await android?.canScheduleExactNotifications() ?? false;
      }

      return canScheduleExact;
    }

    if (Platform.isIOS) {
      final ios = _local
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  Future<bool> _hasExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    return await android?.canScheduleExactNotifications() ?? false;
  }

  Future<AndroidScheduleMode> _getAndroidScheduleMode() async {
    if (!Platform.isAndroid) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }

    final exactPermission = await _hasExactAlarmPermission();

    return exactPermission
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  // ============================================================
  // DEVICE REGISTRATION
  // ============================================================

  Future<void> registerDeviceToken() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _retryPendingDeviceTokenCleanups(user.id);
    final prefs = await SharedPreferences.getInstance();
    final owner = _installationOwnerUserId ?? prefs.getString(_fcmOwnerKey);
    if (owner != null && owner != user.id) {
      throw StateError(
        'The current Firebase installation is still owned by another account.',
      );
    }

    await _messaging.register();

    if (_installationId != null) {
      await _saveInstallationId(_installationId!);
    }
  }

  Future<void> _saveInstallationId(String installationId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _installationId = installationId;
    final prefs = await SharedPreferences.getInstance();
    final owner = _installationOwnerUserId ?? prefs.getString(_fcmOwnerKey);
    if (owner != null && owner != user.id) {
      throw StateError(
        "Refusing to associate another account's Firebase installation.",
      );
    }
    final savedInstallationId = await prefs.setString(
      _installationIdKey,
      installationId,
    );
    if (!savedInstallationId) {
      throw StateError('Could not persist the Firebase installation ID.');
    }

    await _supabase.from('user_device_tokens').upsert({
      'user_id': user.id,
      'fcm_token': installationId,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'fcm_token');
    if (_currentUserId != user.id) {
      throw StateError(
        'The authenticated account changed while registering notifications.',
      );
    }
    _installationOwnerUserId = user.id;
    final savedOwner = await prefs.setString(_fcmOwnerKey, user.id);
    if (!savedOwner) {
      throw StateError('Could not persist the notification token owner.');
    }
  }

  Future<void> unregisterDeviceToken() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('A signed-in session is required to remove its token.');
    }

    await _retryPendingDeviceTokenCleanups(userId);
    final prefs = await SharedPreferences.getInstance();
    final owner = _installationOwnerUserId ?? prefs.getString(_fcmOwnerKey);
    if (owner != null && owner != userId) {
      final staleInstallationId =
          _installationId ?? prefs.getString(_installationIdKey);
      if (staleInstallationId != null) {
        await _queuePendingDeviceTokenCleanup(owner, staleInstallationId);
      }
      await _messaging.unregister().timeout(const Duration(seconds: 5));
      await _clearDeviceTokenLocalState(prefs);
      throw StateError(
        'The previous account token was disabled. Please retry sign-out.',
      );
    }
    final installationId =
        _installationId ?? prefs.getString(_installationIdKey);
    if (installationId == null) {
      if (owner == userId) {
        throw StateError(
          'The registered device token is unavailable for safe removal.',
        );
      }
      return;
    }

    final removed = await _supabase
        .from('user_device_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('fcm_token', installationId)
        .select('fcm_token');
    if (removed.isEmpty) {
      final stillAttached = await _supabase
          .from('user_device_tokens')
          .select('fcm_token')
          .eq('user_id', userId)
          .eq('fcm_token', installationId)
          .maybeSingle();
      if (stillAttached != null) {
        throw StateError('The device token is still attached to this account.');
      }
    }
    if (_currentUserId != userId) {
      throw StateError(
        'The authenticated account changed during device-token cleanup.',
      );
    }
    await _messaging.unregister().timeout(const Duration(seconds: 5));
    await _clearDeviceTokenLocalState(prefs);
  }

  Future<void> _clearDeviceTokenLocalState([
    SharedPreferences? preferences,
  ]) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final ownerRemoved =
        !prefs.containsKey(_fcmOwnerKey) || await prefs.remove(_fcmOwnerKey);
    final installationRemoved =
        !prefs.containsKey(_installationIdKey) ||
        await prefs.remove(_installationIdKey);
    if (!ownerRemoved || !installationRemoved) {
      throw StateError('Could not clear local Firebase installation state.');
    }
    _installationOwnerUserId = null;
    _installationId = null;
  }

  Future<void> _queuePendingDeviceTokenCleanup(
    String userId,
    String installationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries =
        prefs.getStringList(_pendingDeviceTokenCleanupsKey) ?? [];
    final alreadyQueued = rawEntries.any((raw) {
      try {
        final value = jsonDecode(raw);
        return value is Map &&
            value['user_id'] == userId &&
            value['installation_id'] == installationId;
      } on FormatException {
        return false;
      }
    });
    if (alreadyQueued) return;

    rawEntries.add(
      jsonEncode({'user_id': userId, 'installation_id': installationId}),
    );
    final saved = await prefs.setStringList(
      _pendingDeviceTokenCleanupsKey,
      rawEntries,
    );
    if (!saved) {
      throw StateError('Could not queue pending device-token cleanup.');
    }
  }

  Future<void> _retryPendingDeviceTokenCleanups(
    String authenticatedUserId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries =
        prefs.getStringList(_pendingDeviceTokenCleanupsKey) ?? [];
    if (rawEntries.isEmpty) return;

    final remaining = <String>[];
    var changed = false;
    for (final raw in rawEntries) {
      Map<String, dynamic>? entry;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) entry = Map<String, dynamic>.from(decoded);
      } on FormatException {
        remaining.add(raw);
        continue;
      }
      final userId = entry?['user_id'];
      final installationId = entry?['installation_id'];
      if (userId is! String ||
          installationId is! String ||
          installationId.isEmpty) {
        remaining.add(raw);
        continue;
      }
      if (userId != authenticatedUserId) {
        remaining.add(raw);
        continue;
      }

      try {
        await _supabase
            .from('user_device_tokens')
            .delete()
            .eq('user_id', authenticatedUserId)
            .eq('fcm_token', installationId);
        changed = true;
      } catch (error) {
        debugPrint('Retrying prior device-token cleanup failed: $error');
        remaining.add(raw);
      }
    }
    if (changed || remaining.length != rawEntries.length) {
      final saved = await prefs.setStringList(
        _pendingDeviceTokenCleanupsKey,
        remaining,
      );
      if (!saved) {
        throw StateError('Could not update pending device-token cleanups.');
      }
    }
  }

  Future<void> _activateNotificationSchedules(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final scheduledUserId = prefs.getString(_scheduleOwnerKey);
    if (scheduledUserId != userId) {
      await _local.cancelAll();
      final saved = await prefs.setString(_scheduleOwnerKey, userId);
      if (!saved) {
        throw StateError('Could not persist the notification schedule owner.');
      }
    }
    await AlarmScheduleService.instance.restoreAlarms(userId);
    await restoreDailyAlarm(userId);
  }

  Future<void> _deactivateNotificationSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await _local.cancelAll();
    await prefs.remove(_scheduleOwnerKey);
  }

  // ============================================================
  // IN-APP NOTIFICATION HISTORY & CACHE
  // ============================================================

  /// Returns whether a notification of this type is permitted by user preferences.
  Future<bool> shouldDeliverNotification(String type) async {
    final prefs = await fetchPreferences();
    final category = NotificationCategory.fromString(type);

    switch (category) {
      case NotificationCategory.alarm:
        return prefs.alarmNotificationsEnabled;
      case NotificationCategory.task:
        return prefs.taskRemindersEnabled;
      case NotificationCategory.goal:
        return prefs.goalRemindersEnabled;
      case NotificationCategory.motivation:
        return prefs.motivationEnabled;
      case NotificationCategory.announcement:
        return prefs.announcementsEnabled;
      case NotificationCategory.general:
        return true;
    }
  }

  /// Saves notification into in-app history, updating both local storage and Supabase.
  Future<void> saveInAppNotification({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    String? sourceEventId,
    bool respectPreferences = true,
  }) async {
    final userId = _storageUserId;

    if (respectPreferences) {
      final allowed = await shouldDeliverNotification(type);
      if (!allowed) {
        debugPrint('Notification skipped due to user preferences: $type');
        return;
      }
    }

    final occurredAt = DateTime.now();
    final stableSourceId = sourceEventId?.trim().isNotEmpty == true
        ? sourceEventId!.trim()
        : _newSourceEventId();
    final newNotification = AppNotification(
      id: 'local:$stableSourceId',
      userId: userId,
      sourceEventId: stableSourceId,
      category: NotificationCategory.fromString(type),
      rawType: type,
      title: title,
      body: body,
      data: _sanitizeNotificationData(data),
      isRead: false,
      createdAt: occurredAt,
    );

    final operation = NotificationOutboxOperation.create(
      userId: userId,
      kind: NotificationOperationKind.create,
      notification: newNotification,
      sourceEventId: stableSourceId,
      occurredAt: occurredAt,
    );
    final queued = await _storage.enqueueOperation(userId, operation);
    if (!queued) return;

    await _publishCachedNotifications(userId);
    if (_currentUserId == userId) {
      await _synchronizeUserNotifications(userId);
    }
  }

  /// Loads a merged local/server snapshot and retries queued operations.
  Future<List<AppNotification>> fetchNotifications({
    bool forceRefresh = false,
    int limit = 100,
  }) async {
    final userId = _storageUserId;
    await _publishCachedNotifications(userId);
    if (_currentUserId != userId) {
      return _storage.getCachedNotifications(userId);
    }

    await _synchronizeUserNotifications(
      userId,
      fetchRemote: true,
      forceRefresh: forceRefresh,
    );
    return _storage.getCachedNotifications(userId);
  }

  /// Backward-compatible raw fetch returning `Map<String, dynamic>`.
  Future<List<Map<String, dynamic>>> fetchNotificationsRaw({
    int limit = 100,
  }) async {
    final items = await fetchNotifications(limit: limit);
    return items.map((n) => n.toJson()).toList();
  }

  /// Calculates and emits the unread count from the merged local state.
  Future<int> refreshUnreadCount() async {
    final userId = _storageUserId;
    if (_currentUserId == userId) {
      await _synchronizeUserNotifications(userId, fetchRemote: true);
    }
    final count = await _storage.getCachedUnreadCount(userId);
    _emitUnreadCount(count);
    return count;
  }

  /// Marks one notification as read locally and queues a durable sync operation.
  Future<void> markNotificationRead(String notificationId) async {
    await _queueNotificationState(
      notificationId,
      NotificationOperationKind.markRead,
    );
  }

  /// Marks one notification unread and clears its local read timestamp.
  Future<void> markNotificationUnread(String notificationId) async {
    await _queueNotificationState(
      notificationId,
      NotificationOperationKind.markUnread,
    );
  }

  Future<void> _queueNotificationState(
    String notificationId,
    NotificationOperationKind kind,
  ) async {
    final userId = _storageUserId;
    final items = await _storage.getCachedNotifications(userId);
    final notification = items
        .where((item) => item.id == notificationId)
        .firstOrNull;
    final operation = NotificationOutboxOperation.create(
      userId: userId,
      kind: kind,
      targetId: notificationId,
      sourceEventId: notification?.sourceEventId,
    );
    await _queueAndSync(userId, operation);
  }

  /// Marks all notifications currently present as read.
  Future<void> markAllNotificationsRead() async {
    final userId = _storageUserId;
    await _queueAndSync(
      userId,
      NotificationOutboxOperation.create(
        userId: userId,
        kind: NotificationOperationKind.markAllRead,
      ),
    );
  }

  /// Deletes one notification locally, retaining the remote delete until sync.
  Future<void> deleteNotification(String notificationId) async {
    final userId = _storageUserId;
    final items = await _storage.getCachedNotifications(userId);
    final notification = items
        .where((item) => item.id == notificationId)
        .firstOrNull;
    await _queueAndSync(
      userId,
      NotificationOutboxOperation.create(
        userId: userId,
        kind: NotificationOperationKind.delete,
        targetId: notificationId,
        sourceEventId: notification?.sourceEventId,
      ),
    );
  }

  /// Clears history locally while retaining the scoped remote delete for retry.
  Future<void> clearNotificationHistory() async {
    final userId = _storageUserId;
    await _queueAndSync(
      userId,
      NotificationOutboxOperation.create(
        userId: userId,
        kind: NotificationOperationKind.clearAll,
      ),
    );
  }

  Future<void> _queueAndSync(
    String userId,
    NotificationOutboxOperation operation,
  ) async {
    await _storage.enqueueOperation(userId, operation);
    await _publishCachedNotifications(userId);
    if (_currentUserId == userId) {
      await _synchronizeUserNotifications(userId);
    }
  }

  Future<void> _publishCachedNotifications(String userId) async {
    if (userId != NotificationStorage.guestUserId && _currentUserId != userId) {
      return;
    }
    final items = await _storage.getCachedNotifications(userId);
    if (userId != NotificationStorage.guestUserId && _currentUserId != userId) {
      return;
    }
    _notificationsController.add(items);
    _emitUnreadCount(items.where((item) => !item.isRead).length);
  }

  Future<void> _synchronizeUserNotifications(
    String userId, {
    bool fetchRemote = true,
    bool forceRefresh = false,
  }) async {
    if (_currentUserId != userId) return;
    if (_syncing) {
      _syncRequested = true;
      return;
    }

    _syncing = true;
    try {
      final coordinator = _syncCoordinator;
      try {
        await coordinator.syncPending(userId);
      } catch (error) {
        debugPrint(
          'Notification outbox sync failed; retaining operations: $error',
        );
      }

      final shouldFetchRemote = fetchRemote || forceRefresh;
      if (shouldFetchRemote && _currentUserId == userId) {
        try {
          final merged = await coordinator.fetchAndMerge(userId);
          if (_currentUserId == userId) {
            _notificationsController.add(merged);
            _emitUnreadCount(merged.where((item) => !item.isRead).length);
          }
        } catch (error) {
          debugPrint('Fetching notification history failed: $error');
        }
      } else {
        await _publishCachedNotifications(userId);
      }
    } finally {
      _syncing = false;
      if (_currentUserId == userId) {
        await _publishCachedNotifications(userId);
      }
      await _updateOutboxRetryTimer(userId);
      if (_syncRequested) {
        _syncRequested = false;
        final currentUserId = _currentUserId;
        if (currentUserId != null) {
          unawaited(_synchronizeUserNotifications(currentUserId));
        }
      }
    }
  }

  Future<void> _updateOutboxRetryTimer(String userId) async {
    final operations = await _storage.getPendingOperations(userId);
    if (operations.isEmpty || _currentUserId != userId) {
      _outboxRetryTimer?.cancel();
      _outboxRetryTimer = null;
      return;
    }
    _outboxRetryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final activeUserId = _currentUserId;
      if (activeUserId != null) {
        unawaited(_synchronizeUserNotifications(activeUserId));
      }
    });
  }

  String _newSourceEventId() {
    final random = Random.secure();
    return 'app-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(1 << 32)}';
  }

  static Map<String, dynamic> _sanitizeNotificationData(
    Map<String, dynamic> data,
  ) {
    final sensitiveKey = RegExp(
      r'password|passphrase|secret|token|authorization|credential|email|user.?id|dob|date.?of.?birth|phone|otp|verification.?code|sound.?uri|sound.?name',
      caseSensitive: false,
    );

    dynamic sanitizeValue(dynamic value) {
      if (value is Map) {
        return <String, dynamic>{
          for (final entry in value.entries)
            if (entry.key is String &&
                !sensitiveKey.hasMatch(entry.key as String))
              entry.key as String: sanitizeValue(entry.value),
        };
      }
      if (value is List) {
        return value.map(sanitizeValue).toList();
      }
      if (value is String || value is num || value is bool || value == null) {
        return value;
      }
      return value.toString();
    }

    return Map<String, dynamic>.from(sanitizeValue(data) as Map);
  }

  // ============================================================
  // FOREGROUND FIREBASE NOTIFICATIONS
  // ============================================================

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final recipientUserId = message.data['userId'];
    if (!NotificationOwnership.matchesAuthenticatedUser(
      recipientUserId: recipientUserId,
      authenticatedUserId: _currentUserId,
    )) {
      debugPrint(
        'Ignoring foreground notification with missing or mismatched owner.',
      );
      return;
    }
    final userId = (recipientUserId as String).trim();

    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'Eleven11';

    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Your daily motivation is waiting.';

    final type = message.data['type']?.toString() ?? 'motivation';

    // Check user preference
    final allowed = await shouldDeliverNotification(type);
    if (!allowed || _currentUserId != userId) {
      debugPrint(
        'Foreground notification suppressed by preference or account change: '
        '$type',
      );
      return;
    }

    final sourceEventId = _fcmSourceEventId(message);
    try {
      await saveInAppNotification(
        type: type,
        title: title,
        body: body,
        data: Map<String, dynamic>.from(message.data),
        sourceEventId: sourceEventId,
      );
    } catch (e) {
      debugPrint('Saving notification history failed: $e');
    }

    if (_currentUserId != userId) return;
    await _local.show(
      id: message.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(),
      payload: jsonEncode(
        NotificationOwnership.localTapPayload(
          recipientUserId: userId,
          type: type,
          title: title,
          body: body,
          sourceEventId: sourceEventId,
          data: _sanitizeNotificationData(
            Map<String, dynamic>.from(message.data),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NOTIFICATION PREFERENCES (SUPABASE + LOCAL)
  // ============================================================

  /// Fetches typed NotificationPreferences from local cache or Supabase.
  Future<NotificationPreferences> fetchPreferences() async {
    final userId = _currentUserId;
    if (userId == null) return const NotificationPreferences();

    // 1. Try local cache
    final cached = await _storage.getCachedPreferences(userId);

    // 2. Try Supabase
    try {
      final row = await _supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) {
        final prefs = NotificationPreferences.fromJson(row);
        await _storage.savePreferences(userId, prefs);
        return prefs;
      } else {
        // Create initial default row in Supabase
        const defaultPrefs = NotificationPreferences();
        await _supabase.from('notification_preferences').insert({
          'user_id': userId,
          ...defaultPrefs.toJson(),
        });
        await _storage.savePreferences(userId, defaultPrefs);
        return defaultPrefs;
      }
    } catch (e) {
      debugPrint('Fetching preferences from Supabase failed (using cache): $e');
      return cached ?? const NotificationPreferences();
    }
  }

  /// Backward-compatible map fetcher for preferences.
  Future<Map<String, dynamic>?> fetchReminderPreferences() async {
    final prefs = await fetchPreferences();
    return prefs.toJson();
  }

  /// Saves updated preferences both locally and in Supabase, and updates schedules.
  Future<void> savePreferences(NotificationPreferences prefs) async {
    final userId = _currentUserId;
    if (userId == null) return;

    // Save locally first
    await _storage.savePreferences(userId, prefs);

    // Persist to Supabase
    try {
      await _supabase.from('notification_preferences').upsert({
        'user_id': userId,
        ...prefs.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('Saving preferences to Supabase failed: $e');
    }

    // Sync schedules with new preferences
    await syncReminderPreferences();
  }

  /// Backward-compatible legacy save method.
  Future<void> saveReminderPreferences({
    required bool motivationEnabled,
    required String motivationTime,
    required bool taskRemindersEnabled,
    required String taskReminderTime,
    required bool goalRemindersEnabled,
    required bool soundEnabled,
    required bool vibrationEnabled,
    bool alarmNotificationsEnabled = true,
    bool announcementsEnabled = true,
  }) async {
    final prefs = NotificationPreferences(
      motivationEnabled: motivationEnabled,
      motivationTime: motivationTime,
      taskRemindersEnabled: taskRemindersEnabled,
      taskReminderTime: taskReminderTime,
      goalRemindersEnabled: goalRemindersEnabled,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      alarmNotificationsEnabled: alarmNotificationsEnabled,
      announcementsEnabled: announcementsEnabled,
    );

    await savePreferences(prefs);
  }

  /// Syncs active local schedules with user's saved preferences.
  Future<void> syncReminderPreferences() async {
    final preferences = await fetchPreferences();

    if (preferences.motivationEnabled) {
      final time = _parseTime(preferences.motivationTime);

      await scheduleDailyReminder(
        id: motivationReminderId,
        title: 'Your Daily Motivation',
        body: 'Take a moment to focus on your goals.',
        hour: time.$1,
        minute: time.$2,
      );
    } else {
      await cancelReminder(motivationReminderId);
    }

    if (preferences.taskRemindersEnabled) {
      final time = _parseTime(preferences.taskReminderTime);

      await scheduleDailyReminder(
        id: taskReminderId,
        title: 'Your Daily To-do',
        body: 'Check your tasks and make today count.',
        hour: time.$1,
        minute: time.$2,
      );
    } else {
      await cancelReminder(taskReminderId);
    }
  }

  (int, int) _parseTime(String? value) {
    if (value == null || value.isEmpty) return (8, 0);

    final parts = value.split(':');
    if (parts.length < 2) return (8, 0);

    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts[1]) ?? 0;

    return (hour.clamp(0, 23).toInt(), minute.clamp(0, 59).toInt());
  }

  // ============================================================
  // ONBOARDING ALARMS
  // ============================================================

  Future<bool> scheduleOnboardingAlarms({
    required String dailyAlarmTime,
    required bool todayTaskReminderEnabled,
    String? todayTaskReminderAt,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final permissionGranted = await requestAlarmPermissions();

    if (!permissionGranted) return false;

    final time = _parseTime(dailyAlarmTime);

    await scheduleDailyAlarm(hour: time.$1, minute: time.$2);

    await cancelReminder(todayTaskReminderId);

    if (todayTaskReminderEnabled && todayTaskReminderAt != null) {
      final parsedDate = DateTime.tryParse(todayTaskReminderAt);

      if (parsedDate != null && parsedDate.isAfter(DateTime.now())) {
        await scheduleOneTimeTaskReminder(scheduledAt: parsedDate);
      } else {
        debugPrint('Today task reminder skipped: invalid or past time.');
      }
    }

    return true;
  }

  Future<void> scheduleDailyAlarm({
    required int hour,
    required int minute,
  }) async {
    final userId = _currentUserId ?? NotificationStorage.guestUserId;
    final prefs = await SharedPreferences.getInstance();
    final savedSettings = await prefs.setString(
      '$_dailyAlarmSettingsPrefix$userId',
      jsonEncode({'hour': hour, 'minute': minute}),
    );
    if (!savedSettings) {
      throw StateError('Could not persist the daily alarm time.');
    }
    await AlarmScheduleService.instance.cancelSnoozeAlarm(dailyAlarmId);

    final soundUri = prefs.getString('alarm_daily_audio_uri');
    final soundName = prefs.getString('alarm_daily_audio_name');
    final soundEnabled = prefs.getBool('alarm_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('alarm_vibration_enabled') ?? true;

    await _scheduleDailyOccurrences(
      id: dailyAlarmId,
      userId: userId,
      title: 'Eleven11 Daily Alarm',
      body: 'A new day. A fresh opportunity. Make it count.',
      type: 'alarm',
      target: 'alarm',
      hour: hour,
      minute: minute,
      notificationDetails: await _alarmDetails('daily', _dailyAlarmChannel),
      extraPayload: {
        'alarmId': dailyAlarmId,
        'description': 'A new day. A fresh opportunity. Make it count.',
        'soundUri': soundUri,
        'soundName': soundName,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      },
      scheduleMode: AndroidScheduleMode.alarmClock,
    );
  }

  Future<void> restoreDailyAlarm(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_dailyAlarmSettingsPrefix$userId');
    if (raw == null) return;

    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['hour'] is! num ||
        decoded['minute'] is! num) {
      throw FormatException('Invalid saved daily alarm settings for $userId.');
    }
    final hour = (decoded['hour'] as num).toInt();
    final minute = (decoded['minute'] as num).toInt();
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw FormatException('Invalid saved daily alarm time for $userId.');
    }

    final soundUri = prefs.getString('alarm_daily_audio_uri');
    final soundName = prefs.getString('alarm_daily_audio_name');
    final soundEnabled = prefs.getBool('alarm_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('alarm_vibration_enabled') ?? true;
    await _scheduleDailyOccurrences(
      id: dailyAlarmId,
      userId: userId,
      title: 'Eleven11 Daily Alarm',
      body: 'A new day. A fresh opportunity. Make it count.',
      type: 'alarm',
      target: 'alarm',
      hour: hour,
      minute: minute,
      notificationDetails: await _alarmDetails('daily', _dailyAlarmChannel),
      extraPayload: {
        'alarmId': dailyAlarmId,
        'description': 'A new day. A fresh opportunity. Make it count.',
        'soundUri': soundUri,
        'soundName': soundName,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      },
      scheduleMode: AndroidScheduleMode.alarmClock,
    );
  }

  Future<void> scheduleOneTimeTaskReminder({
    required DateTime scheduledAt,
  }) async {
    if (!await _hasExactAlarmPermission()) {
      throw StateError('Exact alarm permission has not been granted.');
    }

    final localDate = tz.TZDateTime.from(scheduledAt, tz.local);

    if (!localDate.isAfter(tz.TZDateTime.now(tz.local))) {
      throw ArgumentError('Reminder time must be in the future.');
    }

    await cancelReminder(todayTaskReminderId);
    await AlarmScheduleService.instance.cancelSnoozeAlarm(todayTaskReminderId);

    final prefs = await SharedPreferences.getInstance();
    final soundUri = prefs.getString('alarm_task_audio_uri');
    final soundName = prefs.getString('alarm_task_audio_name');
    final soundEnabled = prefs.getBool('alarm_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('alarm_vibration_enabled') ?? true;

    await _local.zonedSchedule(
      id: todayTaskReminderId,
      title: 'Your Eleven11 Task Reminder',
      body: 'Take a moment to review your tasks for today.',
      scheduledDate: localDate,
      notificationDetails: await _alarmDetails('task', _taskAlarmChannel),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: jsonEncode({
        'alarmId': todayTaskReminderId,
        'userId': _currentUserId ?? NotificationStorage.guestUserId,
        'type': 'task',
        'target': 'task',
        'sourceEventId':
            'today-task-reminder:'
            '${localDate.toUtc().microsecondsSinceEpoch}',
        'occurrenceDate': _localDateKey(localDate),
        'scheduledAt': localDate.toUtc().toIso8601String(),
        'title': 'Your Eleven11 Task Reminder',
        'description': 'Take a moment to review your tasks for today.',
        'body': 'Take a moment to review your tasks for today.',
        'soundUri': soundUri,
        'soundName': soundName,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      }),
    );
  }

  Future<void> cancelOnboardingDailyAlarm() async {
    final userId = _currentUserId ?? NotificationStorage.guestUserId;
    final prefs = await SharedPreferences.getInstance();
    await _cancelDailyOccurrences(dailyAlarmId, userId, prefs);
    final removed = await prefs.remove('$_dailyAlarmSettingsPrefix$userId');
    if (!removed) {
      throw StateError('Could not clear the saved daily alarm time.');
    }
    await AlarmScheduleService.instance.cancelSnoozeAlarm(dailyAlarmId);
  }

  Future<void> cancelOnboardingTodayTaskReminder() async {
    await cancelReminder(todayTaskReminderId);
  }

  // ============================================================
  // NOTIFICATION DETAILS
  // ============================================================

  NotificationDetails _notificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  String _dailyOccurrencesKey(String userId, int id) =>
      '$_dailyOccurrencesPrefix${userId}_$id';

  Future<void> _cancelDailyOccurrences(
    int id,
    String userId,
    SharedPreferences prefs,
  ) async {
    final key = _dailyOccurrencesKey(userId, id);
    for (final rawId in prefs.getStringList(key) ?? const <String>[]) {
      final notificationId = int.tryParse(rawId);
      if (notificationId != null) {
        await _local.cancel(id: notificationId);
      }
    }
    await _local.cancel(id: id);
    if (prefs.containsKey(key) && !await prefs.remove(key)) {
      throw StateError('Could not clear daily notification schedule IDs.');
    }
  }

  int _dailyNotificationId(String sourceEventId) {
    final hash = int.parse(
      _stableHash(sourceEventId).substring(0, 8),
      radix: 16,
    );
    return 1000000000 + (hash % 400000000);
  }

  Future<void> _scheduleDailyOccurrences({
    required int id,
    required String userId,
    required String title,
    required String body,
    required String type,
    required String target,
    required int hour,
    required int minute,
    required FutureOr<NotificationDetails> notificationDetails,
    required Map<String, dynamic> extraPayload,
    AndroidScheduleMode? scheduleMode,
  }) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('Invalid daily notification time.');
    }
    final mode = scheduleMode ?? await _getAndroidScheduleMode();
    if (mode == AndroidScheduleMode.alarmClock &&
        !await _hasExactAlarmPermission()) {
      throw StateError('Exact alarm permission has not been granted.');
    }

    final prefs = await SharedPreferences.getInstance();
    await _cancelDailyOccurrences(id, userId, prefs);
    final now = tz.TZDateTime.now(tz.local);
    var occurrence = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!occurrence.isAfter(now)) {
      occurrence = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }

    final scheduledDates = <tz.TZDateTime>[];
    for (var index = 0; index < _dailyOccurrenceHorizon; index++) {
      scheduledDates.add(
        tz.TZDateTime(
          tz.local,
          occurrence.year,
          occurrence.month,
          occurrence.day + index,
          hour,
          minute,
        ),
      );
    }
    final sourceEventIds = scheduledDates
        .map((date) => 'daily:$id:${date.toUtc().microsecondsSinceEpoch}')
        .toList();
    final usedIds = <int>{};
    final notificationIds = <int>[];
    for (final sourceEventId in sourceEventIds) {
      var notificationId = _dailyNotificationId(sourceEventId);
      while (!usedIds.add(notificationId)) {
        notificationId = notificationId == 1399999999
            ? 1000000000
            : notificationId + 1;
      }
      notificationIds.add(notificationId);
    }

    final savedIds = await prefs.setStringList(
      _dailyOccurrencesKey(userId, id),
      notificationIds.map((value) => value.toString()).toList(),
    );
    if (!savedIds) {
      throw StateError('Could not persist daily notification schedule IDs.');
    }

    final details = await notificationDetails;
    for (var index = 0; index < scheduledDates.length; index++) {
      final scheduledDate = scheduledDates[index];
      await _local.zonedSchedule(
        id: notificationIds[index],
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: mode,
        payload: jsonEncode({
          ...extraPayload,
          'id': id,
          'type': type,
          'target': target,
          'userId': userId,
          'occurrenceBaseId': 'daily-reminder:$id',
          'sourceEventId': sourceEventIds[index],
          'occurrenceDate': _localDateKey(scheduledDate),
          'scheduledAt': scheduledDate.toUtc().toIso8601String(),
          'title': title,
          'body': body,
        }),
      );
    }
  }

  // ============================================================
  // GENERAL LOCAL REMINDERS
  // ============================================================

  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final type = id == motivationReminderId
        ? 'motivation'
        : (id == taskReminderId ? 'task' : 'reminder');

    await _scheduleDailyOccurrences(
      id: id,
      userId: _currentUserId ?? NotificationStorage.guestUserId,
      title: title,
      body: body,
      type: type,
      target: type,
      hour: hour,
      minute: minute,
      notificationDetails: _notificationDetails(),
      extraPayload: {'id': id},
    );
  }

  Future<void> scheduleCustomReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final localDate = tz.TZDateTime.from(scheduledAt, tz.local);

    if (!localDate.isAfter(tz.TZDateTime.now(tz.local))) {
      throw ArgumentError('Reminder time must be in the future.');
    }

    await _local.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: localDate,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: await _getAndroidScheduleMode(),
      payload: jsonEncode({
        'id': id,
        'type': 'task',
        'target': 'task',
        'userId': _currentUserId ?? NotificationStorage.guestUserId,
        'sourceEventId':
            'custom-task-reminder:'
            '$id:${localDate.toUtc().microsecondsSinceEpoch}',
        'occurrenceDate': _localDateKey(localDate),
        'scheduledAt': localDate.toUtc().toIso8601String(),
        'title': title,
        'body': body,
      }),
    );
  }

  // ============================================================
  // CANCELLATION
  // ============================================================

  Future<void> cancelReminder(int id) async {
    final userId = _currentUserId ?? NotificationStorage.guestUserId;
    final prefs = await SharedPreferences.getInstance();
    await _cancelDailyOccurrences(id, userId, prefs);
  }

  Future<void> cancelAllReminders() async {
    await _local.cancelAll();
  }
}
