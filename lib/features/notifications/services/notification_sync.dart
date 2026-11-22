import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import 'notification_storage.dart';

abstract interface class NotificationRemoteStore {
  Future<List<AppNotification>> fetchAll(String userId);

  Future<AppNotification> createOrGet(
    String userId,
    AppNotification notification,
  );

  Future<void> setReadState(
    String userId,
    NotificationOutboxOperation operation,
  );

  Future<void> deleteOne(String userId, NotificationOutboxOperation operation);

  Future<void> markAllRead(String userId, DateTime occurredAt);

  Future<void> clearAll(String userId, DateTime occurredAt);
}

class SupabaseNotificationRemoteStore implements NotificationRemoteStore {
  SupabaseNotificationRemoteStore(this._client);

  final SupabaseClient _client;

  void _requireCurrentUser(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Notification operation does not match the session.');
    }
  }

  @override
  Future<List<AppNotification>> fetchAll(String userId) async {
    _requireCurrentUser(userId);
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('user_notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      final pageRows = List<Map<String, dynamic>>.from(page);
      rows.addAll(pageRows);
      if (pageRows.length < pageSize) break;
      offset += pageSize;
    }
    return rows.map(AppNotification.fromJson).toList();
  }

  @override
  Future<AppNotification> createOrGet(
    String userId,
    AppNotification notification,
  ) async {
    _requireCurrentUser(userId);
    final sourceEventId = notification.sourceEventId;
    if (sourceEventId == null || sourceEventId.isEmpty) {
      throw ArgumentError('Notification source ID is required for sync.');
    }

    final row = await _client
        .from('user_notifications')
        .upsert({
          'user_id': userId,
          'source_event_id': sourceEventId,
          'type': notification.rawType,
          'title': notification.title,
          'body': notification.body,
          'data': notification.data,
          'created_at': notification.createdAt.toUtc().toIso8601String(),
        }, onConflict: 'user_id,source_event_id')
        .select()
        .single();
    return AppNotification.fromJson(row);
  }

  @override
  Future<void> setReadState(
    String userId,
    NotificationOutboxOperation operation,
  ) async {
    _requireCurrentUser(userId);
    final isRead = operation.kind == NotificationOperationKind.markRead;
    final values = {
      'is_read': isRead,
      'read_at': isRead ? operation.occurredAt.toUtc().toIso8601String() : null,
    };
    final sourceEventId = operation.sourceEventId;
    if (sourceEventId != null && sourceEventId.isNotEmpty) {
      await _client
          .from('user_notifications')
          .update(values)
          .eq('user_id', userId)
          .eq('source_event_id', sourceEventId);
      return;
    }
    final targetId = operation.targetId;
    if (targetId == null || targetId.isEmpty) {
      throw ArgumentError('Notification operation has no target.');
    }
    await _client
        .from('user_notifications')
        .update(values)
        .eq('user_id', userId)
        .eq('id', targetId);
  }

  @override
  Future<void> deleteOne(
    String userId,
    NotificationOutboxOperation operation,
  ) async {
    _requireCurrentUser(userId);
    final sourceEventId = operation.sourceEventId;
    if (sourceEventId != null && sourceEventId.isNotEmpty) {
      await _client
          .from('user_notifications')
          .delete()
          .eq('user_id', userId)
          .eq('source_event_id', sourceEventId);
      return;
    }
    final targetId = operation.targetId;
    if (targetId == null || targetId.isEmpty) {
      throw ArgumentError('Notification operation has no target.');
    }
    await _client
        .from('user_notifications')
        .delete()
        .eq('user_id', userId)
        .eq('id', targetId);
  }

  @override
  Future<void> markAllRead(String userId, DateTime occurredAt) async {
    _requireCurrentUser(userId);
    await _client
        .from('user_notifications')
        .update({
          'is_read': true,
          'read_at': occurredAt.toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('is_read', false)
        .lte('created_at', occurredAt.toUtc().toIso8601String());
  }

  @override
  Future<void> clearAll(String userId, DateTime occurredAt) async {
    _requireCurrentUser(userId);
    await _client
        .from('user_notifications')
        .delete()
        .eq('user_id', userId)
        .lte('created_at', occurredAt.toUtc().toIso8601String());
  }
}

class NotificationSyncCoordinator {
  NotificationSyncCoordinator({
    required this.storage,
    required this.remote,
    required this.currentUserId,
  });

  final NotificationStorage storage;
  final NotificationRemoteStore remote;
  final String? Function() currentUserId;
  final Map<String, Future<void>> _inFlightSyncs = {};

  bool _isCurrentUser(String userId) => currentUserId() == userId;

  Future<void> syncPending(String userId) {
    final inFlight = _inFlightSyncs[userId];
    if (inFlight != null) return inFlight;

    late final Future<void> sync;
    sync = _syncPending(userId).whenComplete(() {
      if (identical(_inFlightSyncs[userId], sync)) {
        _inFlightSyncs.remove(userId);
      }
    });
    _inFlightSyncs[userId] = sync;
    return sync;
  }

  Future<void> _syncPending(String userId) async {
    if (!_isCurrentUser(userId)) return;
    final operations = await storage.getPendingOperations(userId);
    for (final operation in operations) {
      if (!_isCurrentUser(userId)) return;

      AppNotification? serverNotification;
      switch (operation.kind) {
        case NotificationOperationKind.create:
          final notification = operation.notification;
          if (notification == null) {
            throw StateError('Queued create has no notification.');
          }
          serverNotification = await remote.createOrGet(userId, notification);
          break;
        case NotificationOperationKind.markRead:
        case NotificationOperationKind.markUnread:
          await remote.setReadState(userId, operation);
          break;
        case NotificationOperationKind.delete:
          await remote.deleteOne(userId, operation);
          break;
        case NotificationOperationKind.markAllRead:
          await remote.markAllRead(userId, operation.occurredAt);
          break;
        case NotificationOperationKind.clearAll:
          await remote.clearAll(userId, operation.occurredAt);
          break;
      }

      if (!_isCurrentUser(userId)) return;
      await storage.commitOperation(
        userId,
        operation,
        serverNotification: serverNotification,
      );
    }
  }

  Future<List<AppNotification>> syncAndFetch(String userId) async {
    if (!_isCurrentUser(userId)) {
      return storage.getCachedNotifications(userId);
    }
    await syncPending(userId);
    return fetchAndMerge(userId);
  }

  Future<List<AppNotification>> fetchAndMerge(String userId) async {
    if (!_isCurrentUser(userId)) {
      return storage.getCachedNotifications(userId);
    }
    final remoteItems = await remote.fetchAll(userId);
    if (!_isCurrentUser(userId)) {
      return storage.getCachedNotifications(userId);
    }
    return storage.mergeRemoteNotifications(userId, remoteItems);
  }
}
