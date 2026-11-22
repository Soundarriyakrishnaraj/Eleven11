import 'dart:async';

import 'package:eleven11/features/authentication/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'device-token cleanup completes before the auth session is signed out',
    () async {
      final events = <String>[];
      final coordinator = AuthSignOutCoordinator(
        unregisterDeviceToken: () async {
          events.add('cleanup');
        },
        signOut: () async {
          events.add('signout');
        },
      );

      await coordinator.run();

      expect(events, ['cleanup', 'signout']);
    },
  );

  test('cleanup failure keeps the authenticated session active', () async {
    var signedOut = false;
    final coordinator = AuthSignOutCoordinator(
      unregisterDeviceToken: () async => throw StateError('offline'),
      signOut: () async {
        signedOut = true;
      },
    );

    await expectLater(coordinator.run(), throwsA(isA<AuthFlowException>()));
    expect(signedOut, isFalse);
  });

  test('cleanup timeout stops sign-out without waiting indefinitely', () async {
    final cleanup = Completer<void>();
    var signedOut = false;
    final coordinator = AuthSignOutCoordinator(
      unregisterDeviceToken: () => cleanup.future,
      signOut: () async {
        signedOut = true;
      },
      cleanupTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(coordinator.run(), throwsA(isA<AuthFlowException>()));
    expect(signedOut, isFalse);
    cleanup.complete();
  });
}
