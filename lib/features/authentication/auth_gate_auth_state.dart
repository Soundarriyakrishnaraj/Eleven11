import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGateAuthState {
  bool _passwordRecoveryPending = false;

  void update(AuthState state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      _passwordRecoveryPending = true;
    } else if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.signedOut) {
      _passwordRecoveryPending = false;
    }
  }

  bool shouldShowLogin(AuthState? state) {
    return _passwordRecoveryPending ||
        state?.event == AuthChangeEvent.passwordRecovery ||
        state?.event == AuthChangeEvent.signedOut;
  }
}
