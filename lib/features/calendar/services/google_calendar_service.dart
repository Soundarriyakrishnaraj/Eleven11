import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';

class GoogleCalendarStatus {
  const GoogleCalendarStatus({
    required this.connected,
    this.email,
    this.lastSyncedAt,
    this.syncStatus,
  });

  final bool connected;
  final String? email;
  final DateTime? lastSyncedAt;
  final String? syncStatus;

  factory GoogleCalendarStatus.fromJson(Map<String, dynamic> json) {
    DateTime? lastSync;

    if (json['lastSyncedAt'] != null) {
      lastSync = DateTime.tryParse(json['lastSyncedAt'].toString());
    }

    return GoogleCalendarStatus(
      connected: json['connected'] == true,
      email: json['email'] as String?,
      lastSyncedAt: lastSync,
      syncStatus: json['syncStatus'] as String?,
    );
  }

  static const disconnected = GoogleCalendarStatus(connected: false);
}

class GoogleCalendarException implements Exception {
  const GoogleCalendarException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GoogleCalendarService {
  GoogleCalendarService({
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
    AppLinks? appLinks,
    String? backendUrl,
    this.accessTokenProvider,
  }) : _supabase = supabaseClient,
       _http = httpClient ?? http.Client(),
       _appLinks = appLinks ?? AppLinks(),
       _backendUrl = backendUrl ?? AppConfig.renderBackendUrl;

  final SupabaseClient? _supabase;
  final http.Client _http;
  final AppLinks _appLinks;
  final String _backendUrl;
  final String? Function()? accessTokenProvider;

  StreamSubscription<Uri>? _linkSubscription;

  Future<String?> _getValidAccessToken() async {
    if (accessTokenProvider != null) {
      return accessTokenProvider!();
    }

    final client = _supabase ?? Supabase.instance.client;
    var session = client.auth.currentSession;

    // Check if missing, expired, or expires within the next 60 seconds
    final shouldRefresh =
        session == null ||
        session.isExpired ||
        session.expiresAt == null ||
        session.expiresAt! <=
            DateTime.now()
                    .add(const Duration(seconds: 60))
                    .millisecondsSinceEpoch ~/
                1000;

    if (shouldRefresh) {
      try {
        final res = await client.auth.refreshSession();
        session = res.session;
      } catch (_) {
        return null;
      }
    }

    return session?.accessToken;
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await _getValidAccessToken();

    if (token == null || token.isEmpty) {
      throw const GoogleCalendarException(
        'Your session has expired. Please sign in.',
        statusCode: 401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// Checks the current Google Calendar connection status.
  Future<GoogleCalendarStatus> getStatus() async {
    final uri = Uri.parse('$_backendUrl/api/calendar/status');

    try {
      final headers = await _buildHeaders();
      final response = await _http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map<String, dynamic>) {
          return GoogleCalendarStatus.fromJson(data);
        }

        return GoogleCalendarStatus.disconnected;
      }

      if (response.statusCode == 401) {
        throw const GoogleCalendarException(
          'Your session has expired. Please sign in.',
          statusCode: 401,
        );
      }

      throw GoogleCalendarException(
        _parseError(response.body) ?? 'Failed to fetch calendar status.',
        statusCode: response.statusCode,
      );
    } on GoogleCalendarException {
      rethrow;
    } catch (e) {
      throw GoogleCalendarException('Network error connecting to backend: $e');
    }
  }

  /// Starts Google OAuth authorization.
  Future<void> startAuthorization({
    void Function(GoogleCalendarStatus status)? onCompleted,
    void Function(String error)? onError,
  }) async {
    final uri = Uri.parse('$_backendUrl/api/calendar/auth-url');

    String authUrl;

    try {
      final headers = await _buildHeaders();
      final response = await _http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        authUrl = data['authUrl'] as String? ?? '';

        if (authUrl.isEmpty) {
          throw const GoogleCalendarException(
            'Invalid authorization URL returned.',
          );
        }
      } else {
        throw GoogleCalendarException(
          _parseError(response.body) ??
              'Unable to start Google Calendar authorization.',
          statusCode: response.statusCode,
        );
      }
    } on GoogleCalendarException {
      rethrow;
    } catch (e) {
      throw GoogleCalendarException('Error requesting authorization URL: $e');
    }

    _listenForCallback(onCompleted: onCompleted, onError: onError);

    final launchUri = Uri.parse(authUrl);

    final launched = await launchUrl(
      launchUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      _cancelSubscription();

      throw const GoogleCalendarException(
        'Could not launch browser for Google sign in.',
      );
    }
  }

  /// Listens for the Google Calendar OAuth deep-link callback.
  void _listenForCallback({
    void Function(GoogleCalendarStatus status)? onCompleted,
    void Function(String error)? onError,
  }) {
    _cancelSubscription();

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        if (uri.scheme == 'com.eleven11.eleven11' &&
            uri.host == 'google-calendar-callback') {
          _cancelSubscription();

          final statusParam = uri.queryParameters['status'];

          if (statusParam == 'cancelled' || statusParam == 'error') {
            onError?.call(
              'Google Calendar authorization was cancelled or denied.',
            );
            return;
          }

          // Verify the connection with the backend.
          // Do not trust the callback query parameters as proof.
          try {
            final verifiedStatus = await getStatus();

            if (verifiedStatus.connected) {
              onCompleted?.call(verifiedStatus);
            } else {
              onError?.call(
                'Google Calendar connection could not be verified.',
              );
            }
          } catch (e) {
            onError?.call('Verification failed: $e');
          }
        }
      },
      onError: (err) {
        _cancelSubscription();
        onError?.call('Deep link error: $err');
      },
    );
  }

  /// Disconnects Google Calendar.
  Future<void> disconnect() async {
    final uri = Uri.parse('$_backendUrl/api/calendar/disconnect');

    try {
      final headers = await _buildHeaders();
      final response = await _http.post(uri, headers: headers);

      if (response.statusCode == 200) {
        return;
      }

      if (response.statusCode == 401) {
        throw const GoogleCalendarException(
          'Your session has expired. Please sign in.',
          statusCode: 401,
        );
      }

      throw GoogleCalendarException(
        _parseError(response.body) ?? 'Failed to disconnect calendar.',
        statusCode: response.statusCode,
      );
    } on GoogleCalendarException {
      rethrow;
    } catch (e) {
      throw GoogleCalendarException('Error disconnecting calendar: $e');
    }
  }

  void _cancelSubscription() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }

  void dispose() {
    _cancelSubscription();
    _http.close();
  }

  String? _parseError(String body) {
    try {
      final parsed = jsonDecode(body);

      if (parsed is Map && parsed['error'] != null) {
        return parsed['error'].toString();
      }
    } catch (_) {
      // Ignore invalid JSON error bodies.
    }

    return null;
  }
}
