import 'dart:async';
import 'dart:convert';

import 'package:eleven11/features/notifications/models/notification_model.dart';
import 'package:eleven11/features/notifications/services/notification_storage.dart';
import 'package:eleven11/features/notifications/services/notification_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NotificationStorage storage;
  late FakeNotificationRemote remote;
  late String? activeUserId;
  late NotificationSyncCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = NotificationStorage.instance;
    remote = FakeNotificationRemote();
    activeUserId = 'user-a';
    coordinator = NotificationSyncCoordinator(
      storage: storage,
      remote: remote,
      currentUserId: () => activeUserId,
    );
  });

  test(
    'offline creates remain queued and sync exactly once on retry',
    () async {
      final notification = _notification(
        userId: 'user-a',
        id: 'local:event-1',
        sourceEventId: 'event-1',
      );
      final create = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.create,
        notification: notification,
        sourceEventId: 'event-1',
      );
      await storage.enqueueOperation('user-a', create);

      final locallyCached = await storage.getCachedNotifications('user-a');
      expect(locallyCached, hasLength(1));
      expect(locallyCached.single.sourceEventId, 'event-1');
      expect(locallyCached.single.id, notification.id);
      remote.failAfterCreate = true;
      await expectLater(coordinator.syncPending('user-a'), throwsStateError);
      expect(remote.recordsFor('user-a'), hasLength(1));
      expect(
        (await storage.getPendingOperations('user-a')).single.operationId,
        create.operationId,
      );

      await coordinator.syncPending('user-a');
      expect(await storage.getPendingOperations('user-a'), isEmpty);
      expect(remote.recordsFor('user-a'), hasLength(1));
      expect(
        (await storage.getCachedNotifications('user-a')).single.id,
        'server:event-1',
      );
    },
  );

  test('read and unread changes update read_at and synchronize', () async {
    final item = _notification(userId: 'user-a', id: 'row-1');
    remote.seed(item);
    await storage.mergeRemoteNotifications('user-a', [item]);

    final read = _operation(
      userId: 'user-a',
      kind: NotificationOperationKind.markRead,
      targetId: item.id,
      occurredAt: DateTime.utc(2026, 1, 1),
    );
    await storage.enqueueOperation('user-a', read);
    var cached = (await storage.getCachedNotifications('user-a')).single;
    expect(cached.isRead, isTrue);
    expect(cached.readAt?.isAtSameMomentAs(read.occurredAt), isTrue);
    await coordinator.syncPending('user-a');
    expect(
      remote
          .recordsFor('user-a')
          .single
          .readAt
          ?.isAtSameMomentAs(read.occurredAt),
      isTrue,
    );

    final unread = _operation(
      userId: 'user-a',
      kind: NotificationOperationKind.markUnread,
      targetId: item.id,
    );
    await storage.enqueueOperation('user-a', unread);
    cached = (await storage.getCachedNotifications('user-a')).single;
    expect(cached.isRead, isFalse);
    expect(cached.readAt, isNull);
    await coordinator.syncPending('user-a');
    expect(remote.recordsFor('user-a').single.isRead, isFalse);
    expect(remote.recordsFor('user-a').single.readAt, isNull);

    final markAllAt = DateTime.now().add(const Duration(seconds: 1));
    await storage.enqueueOperation(
      'user-a',
      _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.markAllRead,
        occurredAt: markAllAt,
      ),
    );
    expect(
      (await storage.getCachedNotifications('user-a')).single.readAt
          ?.isAtSameMomentAs(markAllAt),
      isTrue,
    );
    await coordinator.syncPending('user-a');
    expect(
      remote.recordsFor('user-a').single.readAt?.isAtSameMomentAs(markAllAt),
      isTrue,
    );
  });

  test(
    'individual deletion and clear-all remain queued until confirmed',
    () async {
      final first = _notification(userId: 'user-a', id: 'row-1');
      final second = _notification(
        userId: 'user-a',
        id: 'row-2',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      remote.seed(first);
      remote.seed(second);
      await storage.mergeRemoteNotifications('user-a', [first, second]);

      final delete = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.delete,
        targetId: first.id,
      );
      await storage.enqueueOperation('user-a', delete);
      expect(
        (await storage.getCachedNotifications('user-a')).map((item) => item.id),
        ['row-2'],
      );
      remote.failNextOperation = true;
      await expectLater(coordinator.syncPending('user-a'), throwsStateError);
      expect(
        (await storage.getPendingOperations('user-a')).single.operationId,
        delete.operationId,
      );
      await coordinator.syncPending('user-a');
      expect(remote.recordsFor('user-a').map((item) => item.id), ['row-2']);

      final clear = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.clearAll,
        occurredAt: DateTime.now().add(const Duration(seconds: 1)),
      );
      await storage.enqueueOperation('user-a', clear);
      expect(await storage.getCachedNotifications('user-a'), isEmpty);
      await coordinator.syncPending('user-a');
      expect(remote.recordsFor('user-a'), isEmpty);
      expect(await storage.getPendingOperations('user-a'), isEmpty);
    },
  );

  test(
    'duplicate source event IDs are accepted and synchronized once',
    () async {
      final notification = _notification(
        userId: 'user-a',
        id: 'local:event-duplicate',
        sourceEventId: 'event-duplicate',
      );
      final first = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.create,
        notification: notification,
        sourceEventId: 'event-duplicate',
      );
      final duplicate = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.create,
        notification: notification.copyWith(id: 'local:duplicate-copy'),
        sourceEventId: 'event-duplicate',
      );
      expect(await storage.enqueueOperation('user-a', first), isTrue);
      expect(await storage.enqueueOperation('user-a', duplicate), isFalse);

      await coordinator.syncPending('user-a');
      expect(remote.recordsFor('user-a'), hasLength(1));
      expect(await storage.enqueueOperation('user-a', duplicate), isFalse);
    },
  );

  test('remote merge preserves pending local records', () async {
    final local = _notification(
      userId: 'user-a',
      id: 'local:pending',
      sourceEventId: 'pending',
    );
    await storage.enqueueOperation(
      'user-a',
      _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.create,
        notification: local,
        sourceEventId: 'pending',
      ),
    );
    final remoteItem = _notification(userId: 'user-a', id: 'server:old');

    final merged = await storage.mergeRemoteNotifications('user-a', [
      remoteItem,
    ]);
    expect(
      merged.map((item) => item.id),
      containsAll([local.id, remoteItem.id]),
    );
  });

  test(
    'remote deletions remove stale cache but preserve pending creates',
    () async {
      final remoteItem = _notification(userId: 'user-a', id: 'remote-row');
      remote.seed(remoteItem);
      await storage.mergeRemoteNotifications('user-a', [remoteItem]);
      remote.remove(remoteItem);

      expect(await coordinator.fetchAndMerge('user-a'), isEmpty);

      final pending = _notification(
        userId: 'user-a',
        id: 'local:pending-after-delete',
        sourceEventId: 'pending-after-delete',
      );
      await storage.enqueueOperation(
        'user-a',
        _operation(
          userId: 'user-a',
          kind: NotificationOperationKind.create,
          notification: pending,
          sourceEventId: pending.sourceEventId,
        ),
      );
      expect(
        (await coordinator.fetchAndMerge('user-a')).map((item) => item.id),
        [pending.id],
      );
    },
  );

  test(
    'malformed outbox entries are retained separately and do not block sync',
    () async {
      final operation = _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.create,
        notification: _notification(
          userId: 'user-a',
          id: 'local:valid-after-malformed',
          sourceEventId: 'valid-after-malformed',
        ),
        sourceEventId: 'valid-after-malformed',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'notification_outbox_v1_user-a',
        jsonEncode([
          {'kind': 'not-a-valid-operation'},
          operation.toJson(),
        ]),
      );

      expect(
        (await storage.getPendingOperations('user-a'))
            .map((item) => item.operationId),
        [operation.operationId],
      );
      expect(
        prefs.getString('notification_outbox_quarantine_v1_user-a'),
        contains('not-a-valid-operation'),
      );
      await coordinator.syncPending('user-a');
      expect(remote.recordsFor('user-a'), hasLength(1));
    },
  );

  test('one user cannot run concurrent outbox syncs', () async {
    final operation = _operation(
      userId: 'user-a',
      kind: NotificationOperationKind.create,
      notification: _notification(
        userId: 'user-a',
        id: 'local:single-flight',
        sourceEventId: 'single-flight',
      ),
      sourceEventId: 'single-flight',
    );
    await storage.enqueueOperation('user-a', operation);
    final gate = Completer<void>();
    remote.createGate = gate;

    final first = coordinator.syncPending('user-a');
    final second = coordinator.syncPending('user-a');
    await Future<void>.delayed(Duration.zero);
    expect(remote.createCalls, 1);

    gate.complete();
    await Future.wait([first, second]);
    expect(remote.createCalls, 1);
  });

  test('account switching never syncs or exposes another user cache', () async {
    final notificationA = _notification(userId: 'user-a', id: 'a-row');
    final notificationB = _notification(userId: 'user-b', id: 'b-row');
    await storage.mergeRemoteNotifications('user-a', [notificationA]);
    await storage.mergeRemoteNotifications('user-b', [notificationB]);
    await storage.enqueueOperation(
      'user-a',
      _operation(
        userId: 'user-a',
        kind: NotificationOperationKind.delete,
        targetId: notificationA.id,
      ),
    );

    activeUserId = 'user-b';
    await coordinator.syncPending('user-a');
    expect(await storage.getPendingOperations('user-a'), hasLength(1));
    expect(await storage.getCachedNotifications('user-a'), isEmpty);
    expect((await storage.getCachedNotifications('user-b')).single.id, 'b-row');
    expect(remote.recordsFor('user-a'), isEmpty);

    await coordinator.syncPending('user-b');
    expect(remote.recordsFor('user-b'), isEmpty);
    expect(await storage.getPendingOperations('user-a'), hasLength(1));
  });

  test(
    'guest history remains local and is not exposed to signed-in users',
    () async {
      final guestNotification = _notification(
        userId: NotificationStorage.guestUserId,
        id: 'guest-row',
      );
      await storage.enqueueOperation(
        NotificationStorage.guestUserId,
        _operation(
          userId: NotificationStorage.guestUserId,
          kind: NotificationOperationKind.create,
          notification: guestNotification.copyWith(
            sourceEventId: 'guest-event',
          ),
          sourceEventId: 'guest-event',
        ),
      );

      activeUserId = null;
      await coordinator.syncPending(NotificationStorage.guestUserId);
      expect(
        (await storage.getCachedNotifications(NotificationStorage.guestUserId))
            .single
            .userId,
        NotificationStorage.guestUserId,
      );
      expect(await storage.getCachedNotifications('user-a'), isEmpty);
      expect(remote.recordsFor(NotificationStorage.guestUserId), isEmpty);
    },
  );
}

NotificationOutboxOperation _operation({
  required String userId,
  required NotificationOperationKind kind,
  AppNotification? notification,
  String? targetId,
  String? sourceEventId,
  DateTime? occurredAt,
}) {
  return NotificationOutboxOperation.create(
    userId: userId,
    kind: kind,
    notification: notification,
    targetId: targetId,
    sourceEventId: sourceEventId,
    occurredAt: occurredAt ?? DateTime.now(),
  );
}

AppNotification _notification({
  required String userId,
  required String id,
  String? sourceEventId,
  DateTime? createdAt,
}) {
  return AppNotification(
    id: id,
    userId: userId,
    sourceEventId: sourceEventId,
    category: NotificationCategory.task,
    rawType: 'task',
    title: 'Task reminder',
    body: 'Time to work on the task.',
    createdAt: createdAt ?? DateTime.now(),
  );
}

class FakeNotificationRemote implements NotificationRemoteStore {
  final Map<String, AppNotification> _records = {};
  bool failNextOperation = false;
  bool failAfterCreate = false;
  int createCalls = 0;
  Completer<void>? createGate;

  String _key(String userId, AppNotification item) =>
      '$userId:${item.sourceEventId ?? item.id}';

  void _maybeFail() {
    if (failNextOperation) {
      failNextOperation = false;
      throw StateError('Simulated network failure.');
    }
  }

  void seed(AppNotification item) {
    _records[_key(item.userId, item)] = item;
  }

  void remove(AppNotification item) {
    _records.remove(_key(item.userId, item));
  }

  List<AppNotification> recordsFor(String userId) =>
      _records.values.where((item) => item.userId == userId).toList();

  @override
  Future<List<AppNotification>> fetchAll(String userId) async {
    _maybeFail();
    return recordsFor(userId);
  }

  @override
  Future<AppNotification> createOrGet(
    String userId,
    AppNotification notification,
  ) async {
    _maybeFail();
    createCalls++;
    await createGate?.future;
    final key = _key(userId, notification);
    final serverItem = _records.putIfAbsent(
      key,
      () => notification.copyWith(id: 'server:${notification.sourceEventId}'),
    );
    if (failAfterCreate) {
      failAfterCreate = false;
      throw StateError('Simulated lost create response.');
    }
    return serverItem;
  }

  @override
  Future<void> setReadState(
    String userId,
    NotificationOutboxOperation operation,
  ) async {
    _maybeFail();
    for (final entry in _records.entries.toList()) {
      final item = entry.value;
      if (item.userId == userId &&
          ((operation.sourceEventId != null &&
                  item.sourceEventId == operation.sourceEventId) ||
              item.id == operation.targetId)) {
        _records[entry.key] = item.copyWith(
          isRead: operation.kind == NotificationOperationKind.markRead,
          readAt: operation.kind == NotificationOperationKind.markRead
              ? operation.occurredAt
              : null,
          clearReadAt: operation.kind == NotificationOperationKind.markUnread,
        );
      }
    }
  }

  @override
  Future<void> deleteOne(
    String userId,
    NotificationOutboxOperation operation,
  ) async {
    _maybeFail();
    _records.removeWhere((_, item) {
      return item.userId == userId &&
          ((operation.sourceEventId != null &&
                  item.sourceEventId == operation.sourceEventId) ||
              item.id == operation.targetId);
    });
  }

  @override
  Future<void> markAllRead(String userId, DateTime occurredAt) async {
    _maybeFail();
    for (final entry in _records.entries.toList()) {
      final item = entry.value;
      if (item.userId == userId &&
          !item.createdAt.isAfter(occurredAt) &&
          !item.isRead) {
        _records[entry.key] = item.copyWith(isRead: true, readAt: occurredAt);
      }
    }
  }

  @override
  Future<void> clearAll(String userId, DateTime occurredAt) async {
    _maybeFail();
    _records.removeWhere(
      (_, item) => item.userId == userId && !item.createdAt.isAfter(occurredAt),
    );
  }
}
