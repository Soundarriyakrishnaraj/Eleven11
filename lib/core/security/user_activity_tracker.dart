import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';

/// Tracks user login, logout, and session_expired events to the backend/database
/// and caches recent events locally for offline resilience.
class UserActivityTracker {
  UserActivityTracker._();
  static final UserActivityTracker instance = UserActivityTracker._();

  static const String _kLocalLogsKey = 'user_activity_event_logs';
  static const String _kAppVersion = '1.0.0+1';

  bool _explicitSignOutInProgress = false;

  void markExplicitSignOutStarted() {
    _explicitSignOutInProgress = true;
  }

  void clearExplicitSignOutFlag() {
    _explicitSignOutInProgress = false;
  }

  bool get isExplicitSignOutInProgress => _explicitSignOutInProgress;

  /// Records an auth event: strictly 'login', 'logout', or 'session_expired'.
  Future<void> recordEvent({
    required String userId,
    required String eventType,
    String? accessToken,
    http.Client? httpClient,
  }) async {
    if (eventType != 'login' &&
        eventType != 'logout' &&
        eventType != 'session_expired') {
      throw ArgumentError.value(
        eventType,
        'eventType',
        'Must be login, logout, or session_expired',
      );
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();

    // 1. Persist locally for offline resilience & diagnostics
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getStringList(_kLocalLogsKey) ?? [];
      final newRecord = jsonEncode({
        'user_id': userId,
        'event_type': eventType,
        'occurred_at': timestamp,
        'timestamp': timestamp,
        'app_version': _kAppVersion,
      });

      final updated = [newRecord, ...existingRaw];
      if (updated.length > 200) {
        updated.removeRange(200, updated.length);
      }
      await prefs.setStringList(_kLocalLogsKey, updated);
    } catch (e) {
      debugPrint('Local activity logging error: $e');
    }

    // 2. Send to backend API using the verified Supabase JWT (best-effort)
    final token = accessToken ?? _safeCurrentAccessToken();
    if (token != null && token.isNotEmpty) {
      final client = httpClient ?? http.Client();
      try {
        final uri = Uri.parse('${AppConfig.renderBackendUrl}/api/activity/auth-event');
        await client
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'event_type': eventType,
                'app_version': _kAppVersion,
              }),
            )
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('Backend activity logging skipped/failed: $e');
      } finally {
        if (httpClient == null) {
          client.close();
        }
      }
    }

    // 3. Also attempt Supabase RPC heartbeat for login if Migration 016 is applied
    if (eventType == 'login') {
      try {
        await Supabase.instance.client.rpc(
          'record_user_heartbeat',
          params: {'p_app_version': _kAppVersion},
        );
      } catch (_) {}
    }
  }

  /// Records a non-fabricated session_expired event when auth drops unexpectedly.
  Future<void> recordSessionExpired(String userId) async {
    await recordEvent(userId: userId, eventType: 'session_expired');
  }

  /// Sends a lightweight presence heartbeat for the currently signed-in user.
  Future<void> recordHeartbeat({http.Client? httpClient}) async {
    final token = _safeCurrentAccessToken();
    if (token == null || token.isEmpty) return;

    final client = httpClient ?? http.Client();
    try {
      final uri = Uri.parse('${AppConfig.renderBackendUrl}/api/activity/heartbeat');
      await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'app_version': _kAppVersion}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await Supabase.instance.client.rpc(
          'record_user_heartbeat',
          params: {'p_app_version': _kAppVersion},
        );
      } catch (_) {}
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  String? _safeCurrentAccessToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves locally cached activity events for a specific user (chronological DESC).
  Future<List<Map<String, dynamic>>> getEventsForUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getStringList(_kLocalLogsKey) ?? [];
      final userEvents = <Map<String, dynamic>>[];

      for (final raw in existingRaw) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          if (map['user_id'] == userId) {
            userEvents.add({
              'user_id': map['user_id'],
              'event_type': map['event_type'] ?? 'login',
              'occurred_at': map['occurred_at'] ?? map['timestamp'],
              'app_version': map['app_version'],
            });
          }
        } catch (_) {}
      }
      return userEvents;
    } catch (_) {
      return [];
    }
  }

  /// Retrieves all locally cached activity events.
  Future<List<Map<String, dynamic>>> getAllEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getStringList(_kLocalLogsKey) ?? [];
      return existingRaw
          .map((r) {
            try {
              return jsonDecode(r) as Map<String, dynamic>;
            } catch (_) {
              return <String, dynamic>{};
            }
          })
          .where((m) => m.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
