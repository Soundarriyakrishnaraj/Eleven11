import 'package:eleven11/features/notifications/services/notification_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a matching authenticated recipient', () {
    expect(
      NotificationOwnership.matchesAuthenticatedUser(
        recipientUserId: 'user-a',
        authenticatedUserId: 'user-a',
      ),
      isTrue,
    );
  });

  test(
    'rejects mismatched, missing, malformed, and unauthenticated owners',
    () {
      for (final recipient in <Object?>['user-b', null, '', '  ', 42]) {
        expect(
          NotificationOwnership.matchesAuthenticatedUser(
            recipientUserId: recipient,
            authenticatedUserId: 'user-a',
          ),
          isFalse,
          reason: 'recipient=$recipient',
        );
      }
      expect(
        NotificationOwnership.matchesAuthenticatedUser(
          recipientUserId: 'user-a',
          authenticatedUserId: null,
        ),
        isFalse,
      );
    },
  );

  test(
    'local notification payload retains its validated owner for tap checks',
    () {
      final payload = NotificationOwnership.localTapPayload(
        recipientUserId: 'user-a',
        type: 'task',
        title: 'Task reminder',
        body: 'Time to work.',
        sourceEventId: 'fcm:event-1',
        data: const {'taskId': 'task-1'},
      );

      expect(payload['userId'], 'user-a');
      expect(
        NotificationOwnership.matchesAuthenticatedUser(
          recipientUserId: payload['userId'],
          authenticatedUserId: 'user-b',
        ),
        isFalse,
      );
    },
  );
}
