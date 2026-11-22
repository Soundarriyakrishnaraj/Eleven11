import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_model.dart';
import '../models/notification_preferences_model.dart';

enum NotificationOperationKind {
  create,
  markRead,
  markUnread,
  delete,
  markAllRead,
  clearAll,
}

typedef NotificationStringWriter = Future<bool> Function(
  SharedPreferences prefs,
  String key,
  String value,
);
typedef NotificationStringListWriter = Future<bool> Function(
  SharedPreferences prefs,
  String key,
  List<String> value,
);
typedef NotificationIntWriter = Future<bool> Function(
  SharedPreferences prefs,
  String key,
  int value,
);
typedef NotificationRemoveWriter = Future<bool> Function(
  SharedPreferences prefs,
  String key,
);

class NotificationOutboxOperation {
  const NotificationOutboxOperation({
    required this.operationId,
    required this.userId,
    required this.kind,
    required this.occurredAt,
    this.notification,
    this.targetId,
    this.sourceEventId,
  });

  final String operationId;
  final String userId;
  final NotificationOperationKind kind;
  final DateTime occurredAt;
  final AppNotification? notification;
  final String? targetId;
  final String? sourceEventId;

  factory NotificationOutboxOperation.create({
    required String userId,
    required NotificationOperationKind kind,
    AppNotification? notification,
    String? targetId,
    String? sourceEventId,
    DateTime? occurredAt,
  }) {
    final random = Random.secure();
    return NotificationOutboxOperation(
      operationId:
          '${DateTime.now().microsecondsSinceEpoch}-'
          '${random.nextInt(1 << 32)}',
      userId: userId,
      kind: kind,
      occurredAt: occurredAt ?? DateTime.now(),
      notification: notification,
      targetId: targetId,
      sourceEventId: sourceEventId,
    );
  }

  factory NotificationOutboxOperation.fromJson(Map<String, dynamic> json) {
    final kind = NotificationOperationKind.values.firstWhere(
      (value) => value.name == json['kind'],
    );
    final notificationJson = json['notification'];
    return NotificationOutboxOperation(
      operationId: json['operation_id'] as String,
      userId: json['user_id'] as String,
      kind: kind,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      notification: notificationJson is Map
          ? AppNotification.fromJson(
              Map<String, dynamic>.from(notificationJson),
            )
          : null,
      targetId: json['target_id'] as String?,
      sourceEventId: json['source_event_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'user_id': userId,
    'kind': kind.name,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    if (notification != null) 'notification': notification!.toJson(),
    if (targetId != null) 'target_id': targetId,
    if (sourceEventId != null) 'source_event_id': sourceEventId,
  };
}

class NotificationStorage {
  NotificationStorage._({
    NotificationStringWriter? writeString,
    NotificationStringListWriter? writeStringList,
    NotificationIntWriter? writeInt,
    NotificationRemoveWriter? removeKey,
  }) : _writeString = writeString ?? _defaultWriteString,
       _writeStringList = writeStringList ?? _defaultWriteStringList,
       _writeInt = writeInt ?? _defaultWriteInt,
       _removeKey = removeKey ?? _defaultRemoveKey;

  @visibleForTesting
  factory NotificationStorage.forTesting({
    NotificationStringWriter? writeString,
    NotificationStringListWriter? writeStringList,
    NotificationIntWriter? writeInt,
    NotificationRemoveWriter? removeKey,
  }) => NotificationStorage._(
    writeString: writeString,
    writeStringList: writeStringList,
    writeInt: writeInt,
    removeKey: removeKey,
  );

  static final NotificationStorage instance = NotificationStorage._();

  static const String guestUserId = 'guest';
  static const String _prefixNotifications = 'notifications_cache_';
  static const String _prefixUnread = 'notification_unread_count_';
  static const String _prefixPrefs = 'notification_preferences_';
  static const String _prefixOutbox = 'notification_outbox_v1_';
  static const String _prefixOutboxQuarantine =
      'notification_outbox_quarantine_v1_';
  static const String _prefixKnownRemoteIds = 'notification_remote_ids_v1_';
  static const String _prefixSnapshotJournal =
      'notification_snapshot_journal_v1_';
  static const String _prefixLegacyPendingRead = 'notification_pending_read_';

  final NotificationStringWriter _writeString;
  final NotificationStringListWriter _writeStringList;
  final NotificationIntWriter _writeInt;
  final NotificationRemoveWriter _removeKey;
  Future<void> _writeTail = Future<void>.value();

  String _notificationsKey(String userId) => '$_prefixNotifications$userId';
  String _unreadKey(String userId) => '$_prefixUnread$userId';
  String _prefsKey(String userId) => '$_prefixPrefs$userId';
  String _outboxKey(String userId) => '$_prefixOutbox$userId';
  String _outboxQuarantineKey(String userId) =>
      '$_prefixOutboxQuarantine$userId';
  String _knownRemoteIdsKey(String userId) => '$_prefixKnownRemoteIds$userId';
  String _snapshotJournalKey(String userId) => '$_prefixSnapshotJournal$userId';

  static Future<bool> _defaultWriteString(
    SharedPreferences prefs,
    String key,
    String value,
  ) => prefs.setString(key, value);

  static Future<bool> _defaultWriteStringList(
    SharedPreferences prefs,
    String key,
    List<String> value,
  ) => prefs.setStringList(key, value);

  static Future<bool> _defaultWriteInt(
    SharedPreferences prefs,
    String key,
    int value,
  ) => prefs.setInt(key, value);

  static Future<bool> _defaultRemoveKey(SharedPreferences prefs, String key) =>
      prefs.remove(key);

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<AppNotification>> _readBase(
    SharedPreferences prefs,
    String userId,
  ) async {
    final raw = prefs.getString(_notificationsKey(userId));
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map(
          (item) =>
              AppNotification.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<NotificationOutboxOperation>> _readOutbox(
    SharedPreferences prefs,
    String userId,
  ) async {
    final raw = prefs.getString(_outboxKey(userId));
    final operations = <NotificationOutboxOperation>[];
    final invalidEntries = <Map<String, dynamic>>[];
    List<dynamic>? decoded;
    if (raw != null && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is List) {
          decoded = value;
        } else {
          invalidEntries.add({
            'raw_outbox': raw,
            'error': 'Outbox root is not a list.',
          });
        }
      } on FormatException catch (error) {
        invalidEntries.add({'raw_outbox': raw, 'error': error.toString()});
      }

      for (final entry in decoded ?? const <dynamic>[]) {
        try {
          if (entry is! Map) {
            throw const FormatException('Outbox entry is not an object.');
          }
          final operation = NotificationOutboxOperation.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (operation.userId != userId) {
            throw const FormatException(
              'Outbox entry belongs to a different user.',
            );
          }
          operations.add(operation);
        } on Object catch (error) {
          invalidEntries.add({'entry': entry, 'error': error.toString()});
        }
      }
    }

    if (invalidEntries.isNotEmpty) {
      await _appendOutboxQuarantine(prefs, userId, invalidEntries);
      await _writeOutbox(prefs, userId, operations);
      debugPrint(
        'Quarantined ${invalidEntries.length} malformed notification '
        'outbox entr${invalidEntries.length == 1 ? 'y' : 'ies'} for $userId.',
      );
    }

    final legacyKey = '$_prefixLegacyPendingRead$userId';
    final legacyReadIds = prefs.getStringList(legacyKey) ?? [];
    if (legacyReadIds.isNotEmpty) {
      for (final id in legacyReadIds) {
        if (!operations.any(
          (operation) =>
              operation.kind == NotificationOperationKind.markRead &&
              operation.targetId == id,
        )) {
          operations.add(
            NotificationOutboxOperation.create(
              userId: userId,
              kind: NotificationOperationKind.markRead,
              targetId: id,
            ),
          );
        }
      }
      await _writeOutbox(prefs, userId, operations);
      await prefs.remove(legacyKey);
    }

    return operations;
  }

  Future<void> _appendOutboxQuarantine(
    SharedPreferences prefs,
    String userId,
    List<Map<String, dynamic>> invalidEntries,
  ) async {
    final key = _outboxQuarantineKey(userId);
    final existingRaw = prefs.getString(key);
    final entries = <dynamic>[];
    if (existingRaw != null) {
      try {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          entries.addAll(decoded);
        } else {
          entries.add({'raw_quarantine': existingRaw});
        }
      } on FormatException {
        entries.add({'raw_quarantine': existingRaw});
      }
    }
    entries.addAll(
      invalidEntries.map(
        (entry) => {
          'quarantined_at': DateTime.now().toUtc().toIso8601String(),
          ...entry,
        },
      ),
    );
    final saved = await _writeString(prefs, key, jsonEncode(entries));
    if (!saved) {
      throw StateError('Could not retain malformed notification outbox data.');
    }
  }

  Future<void> _writeBase(
    SharedPreferences prefs,
    String userId,
    List<AppNotification> notifications,
  ) async {
    final sorted = _sort(notifications);
    final savedNotifications = await _writeString(
      prefs,
      _notificationsKey(userId),
      jsonEncode(sorted.map((item) => item.toJson()).toList()),
    );
    if (!savedNotifications) {
      throw StateError('Could not persist the notification cache.');
    }
    final savedUnreadCount = await _writeInt(
      prefs,
      _unreadKey(userId),
      sorted.where((item) => !item.isRead).length,
    );
    if (!savedUnreadCount) {
      throw StateError('Could not persist the notification unread count.');
    }
  }

  Future<void> _writeOutbox(
    SharedPreferences prefs,
    String userId,
    List<NotificationOutboxOperation> operations,
  ) async {
    final saved = await _writeString(
      prefs,
      _outboxKey(userId),
      jsonEncode(operations.map((operation) => operation.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Could not persist the notification outbox.');
    }
  }

  Future<void> _persistSnapshot(
    SharedPreferences prefs,
    String userId,
    List<AppNotification> notifications,
    Set<String> remoteIdentities,
  ) async {
    final journalKey = _snapshotJournalKey(userId);
    final sortedRemoteIdentities = remoteIdentities.toList()..sort();
    final journal = jsonEncode({
      'user_id': userId,
      'notifications': notifications.map((item) => item.toJson()).toList(),
      'remote_ids': sortedRemoteIdentities,
    });
    final staged = await _writeString(prefs, journalKey, journal);
    if (!staged) {
      throw StateError('Could not stage the notification snapshot.');
    }

    await _writeBase(prefs, userId, notifications);
    final savedRemoteIds = await _writeStringList(
      prefs,
      _knownRemoteIdsKey(userId),
      sortedRemoteIdentities,
    );
    if (!savedRemoteIds) {
      throw StateError('Could not persist remote notification identities.');
    }
    final cleared = await _removeKey(prefs, journalKey);
    if (!cleared) {
      throw StateError('Could not finalize the notification snapshot.');
    }
  }

  Future<void> _recoverSnapshot(SharedPreferences prefs, String userId) async {
    final raw = prefs.getString(_snapshotJournalKey(userId));
    if (raw == null) return;

    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['user_id'] != userId) {
      throw const FormatException('Invalid notification snapshot journal.');
    }
    final rawNotifications = decoded['notifications'];
    final rawRemoteIds = decoded['remote_ids'];
    if (rawNotifications is! List || rawRemoteIds is! List) {
      throw const FormatException('Incomplete notification snapshot journal.');
    }

    final notifications = rawNotifications.map((item) {
      if (item is! Map) {
        throw const FormatException(
          'Invalid notification in snapshot journal.',
        );
      }
      final notification = AppNotification.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (notification.userId != userId) {
        throw const FormatException(
          'Snapshot journal contains another user notification.',
        );
      }
      return notification;
    }).toList();
    final remoteIdentities = rawRemoteIds.map((item) {
      if (item is! String || item.isEmpty) {
        throw const FormatException(
          'Invalid remote identity in snapshot journal.',
        );
      }
      return item;
    }).toList();

    await _writeBase(prefs, userId, notifications);
    final savedRemoteIds = await _writeStringList(
      prefs,
      _knownRemoteIdsKey(userId),
      remoteIdentities,
    );
    if (!savedRemoteIds) {
      throw StateError('Could not recover remote notification identities.');
    }
    final cleared = await _removeKey(prefs, _snapshotJournalKey(userId));
    if (!cleared) {
      throw StateError('Could not clear the recovered notification snapshot.');
    }
  }

  String _identity(AppNotification item) {
    final sourceEventId = item.sourceEventId;
    return sourceEventId == null || sourceEventId.isEmpty
        ? 'id:${item.id}'
        : 'source:$sourceEventId';
  }

  List<AppNotification> _sort(List<AppNotification> items) {
    return items..sort((a, b) {
      final byCreatedAt = b.createdAt.compareTo(a.createdAt);
      return byCreatedAt != 0 ? byCreatedAt : a.id.compareTo(b.id);
    });
  }

  List<AppNotification> _applyOperation(
    List<AppNotification> items,
    NotificationOutboxOperation operation,
  ) {
    bool matches(AppNotification item) {
      return (operation.sourceEventId != null &&
              item.sourceEventId == operation.sourceEventId) ||
          (operation.targetId != null && item.id == operation.targetId);
    }

    switch (operation.kind) {
      case NotificationOperationKind.create:
        final notification = operation.notification;
        if (notification == null) return items;
        final key = _identity(notification);
        final index = items.indexWhere((item) => _identity(item) == key);
        if (index == -1) {
          items.insert(0, notification);
        } else {
          items[index] = notification;
        }
        break;
      case NotificationOperationKind.markRead:
        items = items
            .map(
              (item) => matches(item)
                  ? item.copyWith(isRead: true, readAt: operation.occurredAt)
                  : item,
            )
            .toList();
        break;
      case NotificationOperationKind.markUnread:
        items = items
            .map(
              (item) => matches(item)
                  ? item.copyWith(isRead: false, clearReadAt: true)
                  : item,
            )
            .toList();
        break;
      case NotificationOperationKind.delete:
        items = items.where((item) => !matches(item)).toList();
        break;
      case NotificationOperationKind.markAllRead:
        items = items
            .map(
              (item) => !item.createdAt.isAfter(operation.occurredAt)
                  ? item.copyWith(
                      isRead: true,
                      readAt: item.readAt ?? operation.occurredAt,
                    )
                  : item,
            )
            .toList();
        break;
      case NotificationOperationKind.clearAll:
        items = items
            .where((item) => item.createdAt.isAfter(operation.occurredAt))
            .toList();
        break;
    }
    return _sort(items);
  }

  /// Returns cached notifications with queued changes applied.
  Future<List<AppNotification>> getCachedNotifications(String userId) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await _recoverSnapshot(prefs, userId);
      var items = await _readBase(prefs, userId);
      for (final operation in await _readOutbox(prefs, userId)) {
        items = _applyOperation(items, operation);
      }
      return _sort(items);
    });
  }

  Future<List<NotificationOutboxOperation>> getPendingOperations(
    String userId,
  ) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      return _readOutbox(prefs, userId);
    });
  }

  /// Appends an operation before any network request, preserving it for retry.
  /// Returns false when a create with the same stable source ID already exists.
  Future<bool> enqueueOperation(
    String userId,
    NotificationOutboxOperation operation,
  ) {
    return _serialized(() async {
      if (operation.userId != userId) {
        throw ArgumentError('Outbox operation belongs to another user.');
      }
      final prefs = await SharedPreferences.getInstance();
      final outbox = await _readOutbox(prefs, userId);
      if (operation.kind == NotificationOperationKind.create) {
        final sourceEventId = operation.notification?.sourceEventId;
        if (sourceEventId == null || sourceEventId.isEmpty) {
          throw ArgumentError('Created notifications require a source ID.');
        }
        final base = await _readBase(prefs, userId);
        if (base.any((item) => item.sourceEventId == sourceEventId) ||
            outbox.any(
              (item) =>
                  item.kind == NotificationOperationKind.create &&
                  item.notification?.sourceEventId == sourceEventId,
            )) {
          return false;
        }
      }
      outbox.add(operation);
      await _writeOutbox(prefs, userId, outbox);
      return true;
    });
  }

  /// Merges server rows into the local base cache by source ID or row ID.
  Future<List<AppNotification>> mergeRemoteNotifications(
    String userId,
    List<AppNotification> remoteItems,
  ) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await _recoverSnapshot(prefs, userId);
      final base = await _readBase(prefs, userId);
      final outbox = await _readOutbox(prefs, userId);
      final knownRemoteIdsKey = _knownRemoteIdsKey(userId);
      final hasRemoteSnapshot = prefs.containsKey(knownRemoteIdsKey);
      final previouslyRemote =
          prefs.getStringList(knownRemoteIdsKey)?.toSet() ?? <String>{};
      final remoteIdentities = <String>{};
      final merged = <String, AppNotification>{};
      for (final item in base) {
        final identity = _identity(item);
        final isUntrackedRemote =
            !hasRemoteSnapshot &&
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              caseSensitive: false,
            ).hasMatch(item.id);
        if (!previouslyRemote.contains(identity) && !isUntrackedRemote) {
          merged[identity] = item;
        }
      }
      for (final item in remoteItems) {
        if (item.userId != userId) continue;
        final identity = _identity(item);
        remoteIdentities.add(identity);
        merged[identity] = item;
      }
      for (final operation in outbox) {
        final pendingCreate = operation.notification;
        if (operation.kind == NotificationOperationKind.create &&
            pendingCreate != null &&
            pendingCreate.userId == userId) {
          merged.putIfAbsent(_identity(pendingCreate), () => pendingCreate);
        }
      }
      await _persistSnapshot(
        prefs,
        userId,
        merged.values.toList(),
        remoteIdentities,
      );

      var visible = await _readBase(prefs, userId);
      for (final operation in outbox) {
        visible = _applyOperation(visible, operation);
      }
      return _sort(visible);
    });
  }

  /// Commits a confirmed operation locally, then removes it from the outbox.
  Future<void> commitOperation(
    String userId,
    NotificationOutboxOperation operation, {
    AppNotification? serverNotification,
  }) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      await _recoverSnapshot(prefs, userId);
      final outbox = await _readOutbox(prefs, userId);
      if (!outbox.any((item) => item.operationId == operation.operationId)) {
        return;
      }

      var base = await _readBase(prefs, userId);
      if (operation.kind == NotificationOperationKind.create &&
          serverNotification != null) {
        final identity = _identity(serverNotification);
        base.removeWhere((item) => _identity(item) == identity);
        base.add(serverNotification);
        final remoteIds =
            prefs.getStringList(_knownRemoteIdsKey(userId))?.toSet() ??
            <String>{};
        remoteIds.add(identity);
        await _persistSnapshot(prefs, userId, base, remoteIds);
      } else {
        base = _applyOperation(base, operation);
        await _writeBase(prefs, userId, base);
      }

      outbox.removeWhere((item) => item.operationId == operation.operationId);
      await _writeOutbox(prefs, userId, outbox);
    });
  }

  Future<int> getCachedUnreadCount(String userId) async {
    final items = await getCachedNotifications(userId);
    return items.where((item) => !item.isRead).length;
  }

  Future<void> setCachedUnreadCount(String userId, int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await _writeInt(
        prefs,
        _unreadKey(userId),
        count.clamp(0, 99999),
      );
      if (!saved) {
        throw StateError('Could not persist the notification unread count.');
      }
    } catch (error) {
      debugPrint('Error saving unread notification count: $error');
    }
  }

  Future<void> savePreferences(
    String userId,
    NotificationPreferences prefsModel,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await _writeString(
        prefs,
        _prefsKey(userId),
        jsonEncode(prefsModel.toJson()),
      );
      if (!saved) {
        throw StateError('Could not persist notification preferences.');
      }
    } catch (error) {
      debugPrint('Error saving notification preferences cache: $error');
    }
  }

  Future<NotificationPreferences?> getCachedPreferences(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(userId));
      if (raw == null || raw.isEmpty) return null;
      return NotificationPreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error) {
      debugPrint('Error reading notification preferences cache: $error');
      return null;
    }
  }
}
