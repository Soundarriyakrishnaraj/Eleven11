import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLockTimeout {
  immediately(0, 'Immediately'),
  oneMinute(1, 'After 1 minute'),
  fiveMinutes(5, 'After 5 minutes'),
  fifteenMinutes(15, 'After 15 minutes'),
  thirtyMinutes(30, 'After 30 minutes');

  const AppLockTimeout(this.minutes, this.label);
  final int minutes;
  final String label;
}

class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const String _keyEnabled = 'settings_app_lock_enabled';
  static const String _keyTimeout = 'settings_app_lock_timeout_minutes';
  static const String _keyBiometricsOnly = 'settings_app_lock_biometrics_only';

  final LocalAuthentication _auth = LocalAuthentication();

  bool _isLockEnabled = false;
  AppLockTimeout _timeout = AppLockTimeout.immediately;
  bool _biometricsOnly = false;

  bool _isLocked = false;
  DateTime? _pausedAt;
  DateTime? _lastUnlockedAt;
  bool _isAuthenticating = false;

  bool get isLockEnabled => _isLockEnabled;
  AppLockTimeout get timeout => _timeout;
  bool get biometricsOnly => _biometricsOnly;
  bool get isLocked => _isLocked;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    _isLockEnabled = prefs.getBool(_keyEnabled) ?? false;
    _biometricsOnly = prefs.getBool(_keyBiometricsOnly) ?? false;

    final timeoutMinutes = prefs.getInt(_keyTimeout) ?? 0;
    _timeout = AppLockTimeout.values.firstWhere(
      (t) => t.minutes == timeoutMinutes,
      orElse: () => AppLockTimeout.immediately,
    );

    // Initial launch lock if enabled
    if (_isLockEnabled) {
      _isLocked = true;
    }
    notifyListeners();
  }

  void disposeObserver() {
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> setLockEnabled(bool enabled) async {
    _isLockEnabled = enabled;
    if (!enabled) {
      _isLocked = false;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  Future<void> setTimeout(AppLockTimeout timeout) async {
    _timeout = timeout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTimeout, timeout.minutes);
  }

  Future<void> setBiometricsOnly(bool val) async {
    _biometricsOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricsOnly, val);
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticate() async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        // Fallback gracefully if hardware doesn't support biometrics
        _isLocked = false;
        notifyListeners();
        return true;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate to unlock Eleven11',
        options: AuthenticationOptions(
          biometricOnly: _biometricsOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        _isLocked = false;
        _pausedAt = null;
        _lastUnlockedAt = DateTime.now();
        notifyListeners();
      }
      return authenticated;
    } on PlatformException catch (_) {
      return false;
    } finally {
      _isAuthenticating = false;
    }
  }

  void unlockDirect() {
    _isLocked = false;
    _pausedAt = null;
    _lastUnlockedAt = DateTime.now();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLockEnabled) return;

    // While biometric system dialog is active, Android fires paused/resumed.
    // Ignore lifecycle transitions during authentication so we don't immediately re-lock.
    if (_isAuthenticating) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_isLocked) return;

      // Grace period: if unlocked very recently (within 5 seconds), don't re-lock
      if (_lastUnlockedAt != null &&
          DateTime.now().difference(_lastUnlockedAt!) < const Duration(seconds: 5)) {
        return;
      }

      if (_pausedAt != null) {
        final elapsed = DateTime.now().difference(_pausedAt!);
        if (elapsed.inMinutes >= _timeout.minutes) {
          _isLocked = true;
          notifyListeners();
        }
      } else if (_timeout == AppLockTimeout.immediately) {
        _isLocked = true;
        notifyListeners();
      }
    }
  }
}
