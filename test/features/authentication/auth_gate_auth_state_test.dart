import 'package:eleven11/features/authentication/auth_gate_auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'password recovery stays outside the authenticated app until sign-out',
    () {
      final gateState = AuthGateAuthState();
      final recovery = AuthState(AuthChangeEvent.passwordRecovery, null);

      gateState.update(recovery);
      expect(gateState.shouldShowLogin(recovery), isTrue);

      final tokenRefresh = AuthState(AuthChangeEvent.tokenRefreshed, null);
      gateState.update(tokenRefresh);
      expect(gateState.shouldShowLogin(tokenRefresh), isTrue);

      final signedOut = AuthState(AuthChangeEvent.signedOut, null);
      gateState.update(signedOut);
      expect(gateState.shouldShowLogin(signedOut), isTrue);

      final signedIn = AuthState(AuthChangeEvent.signedIn, null);
      gateState.update(signedIn);
      expect(gateState.shouldShowLogin(signedIn), isFalse);
    },
  );

  test('a signed-out event takes precedence over a stale current session', () {
    final gateState = AuthGateAuthState();
    final signedOut = AuthState(AuthChangeEvent.signedOut, null);

    expect(gateState.shouldShowLogin(signedOut), isTrue);
  });
}
