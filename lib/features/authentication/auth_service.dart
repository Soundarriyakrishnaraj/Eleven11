import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import '../../core/security/user_activity_tracker.dart';
import '../notifications/notification_service.dart';

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthSignOutCoordinator {
  const AuthSignOutCoordinator({
    required this.unregisterDeviceToken,
    required this.signOut,
    this.cleanupTimeout = const Duration(seconds: 10),
  });

  final Future<void> Function() unregisterDeviceToken;
  final Future<void> Function() signOut;
  final Duration cleanupTimeout;

  Future<void> run() async {
    try {
      await unregisterDeviceToken().timeout(cleanupTimeout);
    } catch (error) {
      throw AuthFlowException(
        'Could not securely unregister this device for notifications. '
        'You were not signed out. Please try again. ($error)',
      );
    }
    await signOut();
  }
}

class PasswordPolicy {
  const PasswordPolicy._();

  static String? validate(String password) {
    if (password.length < 8) {
      return 'Use at least 8 characters.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Use uppercase and lowercase letters, a number, and a symbol.';
    }

    return null;
  }
}

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _normalizeUsername(String username) => username.trim();

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required DateTime dateOfBirth,
  }) async {
    final normalizedUsername = _normalizeUsername(username);
    final normalizedEmail = _normalizeEmail(email);

    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) {
      throw AuthFlowException(passwordError);
    }

    if (normalizedUsername.isEmpty || normalizedEmail.isEmpty) {
      throw const AuthFlowException('Please enter your username and email.');
    }

    if (dateOfBirth.isAfter(DateTime.now())) {
      throw const AuthFlowException('Date of birth cannot be in the future.');
    }

    final availability = await _checkRegistration(
      username: normalizedUsername,
      email: normalizedEmail,
    );

    if (availability['usernameAvailable'] != true) {
      throw const AuthFlowException('This username is already taken.');
    }

    if (availability['emailAvailable'] != true) {
      throw const AuthFlowException(
        'An account with this email already exists.',
      );
    }

    try {
      final response = await _client.auth.signUp(
        email: normalizedEmail,
        password: password,
        emailRedirectTo: 'com.eleven11.eleven11://login-callback/',
        data: {
          'username': normalizedUsername,
          'full_name': normalizedUsername,
          'date_of_birth': _dateOnly(dateOfBirth),
          'tz': 'Asia/Kolkata',
        },
      );

      return response.session != null;
    } on AuthException {
      // Recheck availability to identify a possible concurrent
      // registration using the same username or email.
      final latestAvailability = await _checkRegistration(
        username: normalizedUsername,
        email: normalizedEmail,
      );

      if (latestAvailability['usernameAvailable'] != true) {
        throw const AuthFlowException('This username is already taken.');
      }

      if (latestAvailability['emailAvailable'] != true) {
        throw const AuthFlowException(
          'An account with this email already exists.',
        );
      }

      rethrow;
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'username-login',
        body: {'username': _normalizeUsername(username), 'password': password},
      );

      final data = response.data;

      if (data is! Map || data['refresh_token'] is! String) {
        throw const AuthFlowException('Unable to sign in. Please try again.');
      }

      if (_client.auth.currentUser != null) {
        await signOut();
      }
      await _client.auth.setSession(data['refresh_token'] as String);
      final loggedInUser = _client.auth.currentUser;
      if (loggedInUser != null) {
        await UserActivityTracker.instance.recordEvent(
          userId: loggedInUser.id,
          eventType: 'login',
        );
      }
    } on FunctionException catch (error) {
      if (error.status == 401) {
        throw const AuthFlowException('Invalid username or password.');
      }

      if (error.status == 429) {
        throw const AuthFlowException(
          'Too many attempts. Please wait and try again.',
        );
      }

      rethrow;
    }
  }

  Future<void> startPasswordRecovery({
    required String username,
    required String email,
    required DateTime dateOfBirth,
  }) async {
    final uri = Uri.parse('${AppConfig.renderBackendUrl}/api/auth/verify-recovery');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': _normalizeUsername(username),
            'email': _normalizeEmail(email),
            'dateOfBirth': _dateOnly(dateOfBirth),
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) return;

    String message = 'Unable to verify account details. Please try again.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        message = body['error'] as String;
      }
    } catch (_) {}
    throw AuthFlowException(message);
  }

  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: _normalizeEmail(email),
      token: code.trim(),
      type: OtpType.recovery,
    );
  }

  Future<void> resetPassword(String password) async {
    final passwordError = PasswordPolicy.validate(password);

    if (passwordError != null) {
      throw AuthFlowException(passwordError);
    }

    await _client.auth.updateUser(UserAttributes(password: password));

    await signOut();
  }

  Future<void> resetPasswordWithDetails({
    required String username,
    required String email,
    required DateTime dateOfBirth,
    required String password,
  }) async {
    final passwordError = PasswordPolicy.validate(password);
    if (passwordError != null) {
      throw AuthFlowException(passwordError);
    }

    final uri = Uri.parse('${AppConfig.renderBackendUrl}/api/auth/reset-password');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': _normalizeUsername(username),
            'email': _normalizeEmail(email),
            'dateOfBirth': _dateOnly(dateOfBirth),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) return;

    String message = 'Unable to reset password. Please try again.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        message = body['error'] as String;
      }
    } catch (_) {}
    throw AuthFlowException(message);
  }

  Future<Map<String, dynamic>> _checkRegistration({
    required String username,
    required String email,
  }) async {
    final response = await _client.functions.invoke(
      'registration-check',
      body: {
        'username': _normalizeUsername(username),
        'email': _normalizeEmail(email),
      },
    );

    final data = response.data;

    if (data is! Map ||
        data['usernameAvailable'] is! bool ||
        data['emailAvailable'] is! bool) {
      throw const AuthFlowException(
        'Unable to validate your account details. Please try again.',
      );
    }

    return Map<String, dynamic>.from(data);
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signOut() async {
    final user = _client.auth.currentUser;
    final token = _client.auth.currentSession?.accessToken;
    UserActivityTracker.instance.markExplicitSignOutStarted();
    try {
      if (user != null) {
        await UserActivityTracker.instance.recordEvent(
          userId: user.id,
          eventType: 'logout',
          accessToken: token,
        );
      }
      await AuthSignOutCoordinator(
        unregisterDeviceToken: NotificationService.instance.unregisterDeviceToken,
        signOut: _client.auth.signOut,
      ).run();
    } finally {
      // Clear flag slightly after auth state stream processes signedOut
      Future.delayed(
        const Duration(seconds: 2),
        UserActivityTracker.instance.clearExplicitSignOutFlag,
      );
    }
  }

  Future<void> logout() => signOut();
}
