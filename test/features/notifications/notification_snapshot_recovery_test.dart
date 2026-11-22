import 'package:eleven11/features/notifications/models/notification_model.dart';
import 'package:eleven11/features/notifications/services/notification_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'user-a';

  for (final failedKey in <String>[
    'notification_snapshot_journal_v1_user-a',
    'notifications_cache_user-a',
    'notification_unread_count_user-a',
    'notification_remote_ids_v1_user-a',
    'notification_snapshot_journal_v1_user-a:remove',
  ]) {
    test('remote deletion recovers after failure at $failedKey', () async {
      SharedPreferences.setMockInitialValues({});
      final initialStorage = NotificationStorage.instance;
      final remoteNotification = _notification();
      await initialStorage.mergeRemoteNotifications(userId, [
        remoteNotification,
      ]);

      final storage = _storageFailingOnce(failedKey);
      await expectLater(
        storage.mergeRemoteNotifications(userId, const []),
        throwsA(isA<StateError>()),
      );

      await storage.mergeRemoteNotifications(userId, const []);
      expect(await storage.getCachedNotifications(userId), isEmpty);
    });
  }

  test('failed snapshot recovery preserves pending local creates', () async {
    SharedPreferences.setMockInitialValues({});
    final initialStorage = NotificationStorage.instance;
    await initialStorage.mergeRemoteNotifications(userId, [_notification()]);

    final pending = _notification(
      id: 'local:pending',
      sourceEventId: 'pending-event',
    );
    await initialStorage.enqueueOperation(
      userId,
      NotificationOutboxOperation.create(
        userId: userId,
        kind: NotificationOperationKind.create,
        notification: pending,
        sourceEventId: pending.sourceEventId,
      ),
    );

    final storage = _storageFailingOnce('notification_remote_ids_v1_user-a');
    await expectLater(
      storage.mergeRemoteNotifications(userId, const []),
      throwsA(isA<StateError>()),
    );

    final recovered = await storage.getCachedNotifications(userId);
    expect(recovered.map((item) => item.sourceEventId), ['pending-event']);
  });
}

NotificationStorage _storageFailingOnce(String target) {
  var failed = false;
  final targetKey = target.replaceFirst(':remove', '');
  bool shouldFail(String key, {bool remove = false}) {
    if (failed || key != targetKey) return false;
    if (remove != target.endsWith(':remove')) return false;
    failed = true;
    return true;
  }

  return NotificationStorage.forTesting(
    writeString: (prefs, key, value) async {
      if (shouldFail(key)) return false;
      return prefs.setString(key, value);
    },
    writeStringList: (prefs, key, value) async {
      if (shouldFail(key)) return false;
      return prefs.setStringList(key, value);
    },
    writeInt: (prefs, key, value) async {
      if (shouldFail(key)) return false;
      return prefs.setInt(key, value);
    },
    removeKey: (prefs, key) async {
      if (shouldFail(key, remove: true)) return false;
      return prefs.remove(key);
    },
  );
}

AppNotification _notification({
  String id = 'remote-row',
  String? sourceEventId,
}) => AppNotification(
  id: id,
  userId: 'user-a',
  sourceEventId: sourceEventId,
  category: NotificationCategory.task,
  rawType: 'task',
  title: 'Task reminder',
  body: 'Time to work on the task.',
  createdAt: DateTime.utc(2026, 11, 20),
);
