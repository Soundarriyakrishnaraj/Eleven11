// lib/features/calendar/services/event_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_config.dart';
import '../models/event_model.dart';
import 'google_calendar_service.dart';

class EventServiceException implements Exception {
  const EventServiceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class EventService {
  EventService({
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
    String? backendUrl,
    GoogleCalendarService? googleCalendarService,
  })  : _supabase = supabaseClient ?? Supabase.instance.client,
        _http = httpClient ?? http.Client(),
        _backendUrl = backendUrl ?? AppConfig.renderBackendUrl,
        _googleCalendarService = googleCalendarService ?? GoogleCalendarService();

  final SupabaseClient _supabase;
  final http.Client _http;
  final String _backendUrl;
  final GoogleCalendarService _googleCalendarService;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<Map<String, String>> _buildHeaders() async {
    final session = _supabase.auth.currentSession;
    var token = session?.accessToken;

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
        final res = await _supabase.auth.refreshSession();
        token = res.session?.accessToken;
      } catch (_) {
        token = null;
      }
    }

    if (token == null || token.isEmpty) {
      throw const EventServiceException(
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

  /// Fetches events within an optional date range.
  Future<List<CalendarEvent>> getEvents({
    DateTime? startTime,
    DateTime? endTime,
    bool includeCancelled = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const EventServiceException('User not authenticated.', statusCode: 401);
    }

    try {
      var query = _supabase
          .from('events')
          .select()
          .eq('user_id', userId);

      if (!includeCancelled) {
        query = query.neq('status', 'cancelled');
      }

      if (startTime != null) {
        query = query.gte('end_time', startTime.toUtc().toIso8601String());
      }

      if (endTime != null) {
        query = query.lte('start_time', endTime.toUtc().toIso8601String());
      }

      final response = await query.order('start_time', ascending: true);

      return (response as List)
          .map((item) => CalendarEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('EventService.getEvents error: $e');
      throw EventServiceException('Failed to load events: $e');
    }
  }

  /// Saves an event locally and/or syncs to Google Calendar.
  /// Guarantees that:
  /// 1. A valid UUID v4 and stable idempotency key are generated if missing.
  /// 2. If Google sync fails, the local event is safely preserved in Supabase with
  ///    `sync_status = 'failed'` so user changes are never lost.
  Future<CalendarEvent> saveEvent(CalendarEvent rawEvent) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const EventServiceException('User not authenticated.', statusCode: 401);
    }

    // Ensure valid identifiers (UUID v4 and stable idempotency key)
    final event = rawEvent.withValidIdentifiers();

    try {
      if (event.syncWithGoogle) {
        final headers = await _buildHeaders();
        final uri = Uri.parse('$_backendUrl/api/calendar/sync-event');
        final response = await _http.post(
          uri,
          headers: headers,
          body: jsonEncode(event.toBackendSyncPayload()),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return CalendarEvent.fromJson(data);
        } else {
          // Google sync failed on the backend.
          // Fallback: Preserve the event locally in Supabase with sync_status = 'failed'.
          final fallbackData = event
              .copyWith(syncStatus: 'failed')
              .toSupabaseMap();
          await _supabase.from('events').upsert(fallbackData);

          final errBody = jsonDecode(response.body);
          final msg = errBody['error'] ?? 'Failed to sync event with Google Calendar.';
          throw EventServiceException(
            '$msg (Event saved locally)',
            statusCode: response.statusCode,
          );
        }
      }

      // If not syncing with Google, save directly in Supabase
      final data = event.toSupabaseMap();
      final res = await _supabase
          .from('events')
          .upsert(data)
          .select()
          .single();

      return CalendarEvent.fromJson(res);
    } catch (e) {
      debugPrint('EventService.saveEvent error: $e');
      if (e is EventServiceException) rethrow;

      // Ensure local save attempt before failing
      try {
        final fallbackData = event
            .copyWith(syncStatus: 'failed')
            .toSupabaseMap();
        await _supabase.from('events').upsert(fallbackData);
      } catch (_) {}

      throw EventServiceException('Unable to save event: $e');
    }
  }

  /// Deletes an event from Supabase and Google Calendar if synced.
  Future<void> deleteEvent(CalendarEvent event) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const EventServiceException('User not authenticated.', statusCode: 401);
    }

    try {
      if (event.syncWithGoogle && event.googleEventId != null) {
        try {
          final headers = await _buildHeaders();
          final uri = Uri.parse('$_backendUrl/api/calendar/delete-event');
          await _http.post(
            uri,
            headers: headers,
            body: jsonEncode({'eventId': event.id}),
          );
        } catch (e) {
          debugPrint('Backend delete-event notice: $e');
        }
      }

      await _supabase
          .from('events')
          .delete()
          .eq('id', event.id)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('EventService.deleteEvent error: $e');
      if (e is EventServiceException) rethrow;
      throw EventServiceException('Unable to delete event: $e');
    }
  }

  /// Triggers full two-way pull sync from Google Calendar via backend POST /api/calendar/pull-sync.
  Future<Map<String, dynamic>> pullSyncFromGoogle() async {
    try {
      final headers = await _buildHeaders();
      final uri = Uri.parse('$_backendUrl/api/calendar/pull-sync');
      final response = await _http.post(uri, headers: headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final err = jsonDecode(response.body);
        final msg = err['error'] ?? 'Google Calendar pull sync failed.';
        throw EventServiceException(msg.toString(), statusCode: response.statusCode);
      }
    } catch (e) {
      debugPrint('EventService.pullSyncFromGoogle error: $e');
      if (e is EventServiceException) rethrow;
      throw EventServiceException('Sync failed: $e');
    }
  }

  /// Checks if Google Calendar is currently connected.
  Future<bool> isGoogleCalendarConnected() async {
    try {
      final status = await _googleCalendarService.getStatus();
      return status.connected;
    } catch (_) {
      return false;
    }
  }
}
