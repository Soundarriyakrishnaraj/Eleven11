// lib/features/calendar/models/event_model.dart

import '../services/uuid_util.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.timezone = 'UTC',
    this.isAllDay = false,
    this.syncWithGoogle = false,
    this.googleEventId,
    this.googleHtmlLink,
    this.googleEtag,
    this.recurrenceRules,
    this.googleRecurringEventId,
    this.originalStartTime,
    this.originalStartTimezone,
    this.reminderMinutes = 15,
    this.attendees = const [],
    this.status = 'confirmed',
    this.syncStatus = 'synced',
    this.idempotencyKey,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final String timezone;
  final bool isAllDay;
  final bool syncWithGoogle;
  final String? googleEventId;
  final String? googleHtmlLink;
  final String? googleEtag;
  final List<String>? recurrenceRules;
  final String? googleRecurringEventId;
  final DateTime? originalStartTime;
  final String? originalStartTimezone;
  final int reminderMinutes;
  final List<Map<String, dynamic>> attendees;
  final String status; // 'confirmed', 'tentative', 'cancelled'
  final String syncStatus; // 'pending', 'syncing', 'synced', 'failed'
  final String? idempotencyKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCancelled => status == 'cancelled';
  bool get isSynced => syncWithGoogle && googleEventId != null && syncStatus == 'synced';

  /// Ensures a valid UUID v4 and a stable idempotency key exist on the event.
  CalendarEvent withValidIdentifiers() {
    final validId = UuidUtil.isValidUuid(id) ? id : UuidUtil.generateV4();
    final validKey = (idempotencyKey != null &&
            idempotencyKey!.length >= 8 &&
            idempotencyKey!.length <= 200)
        ? idempotencyKey!
        : validId;

    return copyWith(
      id: validId,
      idempotencyKey: validKey,
    );
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(dynamic value) {
      if (value is DateTime) return value;
      return DateTime.parse(value.toString());
    }

    List<Map<String, dynamic>> parseAttendees(dynamic value) {
      if (value == null) return const [];
      if (value is List) {
        return value.map((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          if (item is String) {
            return {'email': item};
          }
          return <String, dynamic>{};
        }).toList();
      }
      return const [];
    }

    List<String>? parseRecurrence(dynamic value) {
      if (value == null) return null;
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return null;
    }

    return CalendarEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      location: json['location'] as String?,
      startTime: parseDateTime(json['start_time']),
      endTime: parseDateTime(json['end_time']),
      timezone: (json['timezone'] as String?) ?? 'UTC',
      isAllDay: json['is_all_day'] == true,
      syncWithGoogle: json['sync_with_google'] == true,
      googleEventId: json['google_event_id'] as String?,
      googleHtmlLink: json['google_html_link'] as String?,
      googleEtag: json['google_etag'] as String?,
      recurrenceRules: parseRecurrence(json['recurrence_rules']),
      googleRecurringEventId: json['google_recurring_event_id'] as String?,
      originalStartTime: json['original_start_time'] != null
          ? parseDateTime(json['original_start_time'])
          : null,
      originalStartTimezone: json['original_start_timezone'] as String?,
      reminderMinutes: (json['reminder_minutes'] as num?)?.toInt() ?? 15,
      attendees: parseAttendees(json['attendees']),
      status: (json['status'] as String?) ?? 'confirmed',
      syncStatus: (json['sync_status'] as String?) ?? 'synced',
      idempotencyKey: json['idempotency_key'] as String?,
      createdAt: json['created_at'] != null
          ? parseDateTime(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? parseDateTime(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'location': location,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime.toUtc().toIso8601String(),
      'timezone': timezone,
      'is_all_day': isAllDay,
      'sync_with_google': syncWithGoogle,
      'google_event_id': googleEventId,
      'google_html_link': googleHtmlLink,
      'google_etag': googleEtag,
      if (recurrenceRules != null) 'recurrence_rules': recurrenceRules,
      if (googleRecurringEventId != null)
        'google_recurring_event_id': googleRecurringEventId,
      if (originalStartTime != null)
        'original_start_time': originalStartTime!.toUtc().toIso8601String(),
      if (originalStartTimezone != null)
        'original_start_timezone': originalStartTimezone,
      'reminder_minutes': reminderMinutes,
      'attendees': attendees,
      'status': status,
      'sync_status': syncStatus,
      'idempotency_key': idempotencyKey,
    };
  }

  Map<String, dynamic> toBackendSyncPayload() {
    return {
      'id': id,
      'idempotencyKey': idempotencyKey ?? id,
      'title': title,
      'description': description,
      'location': location,
      'startTime': isAllDay
          ? '${startTime.year.toString().padLeft(4, '0')}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}'
          : startTime.toUtc().toIso8601String(),
      'endTime': isAllDay
          ? '${endTime.year.toString().padLeft(4, '0')}-${endTime.month.toString().padLeft(2, '0')}-${endTime.day.toString().padLeft(2, '0')}'
          : endTime.toUtc().toIso8601String(),
      'timezone': timezone,
      'isAllDay': isAllDay,
      'reminderMinutes': reminderMinutes,
      'attendees': attendees,
      if (recurrenceRules != null) 'recurrenceRules': recurrenceRules,
    };
  }

  CalendarEvent copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? location,
    DateTime? startTime,
    DateTime? endTime,
    String? timezone,
    bool? isAllDay,
    bool? syncWithGoogle,
    String? googleEventId,
    String? googleHtmlLink,
    String? googleEtag,
    List<String>? recurrenceRules,
    String? googleRecurringEventId,
    DateTime? originalStartTime,
    String? originalStartTimezone,
    int? reminderMinutes,
    List<Map<String, dynamic>>? attendees,
    String? status,
    String? syncStatus,
    String? idempotencyKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      timezone: timezone ?? this.timezone,
      isAllDay: isAllDay ?? this.isAllDay,
      syncWithGoogle: syncWithGoogle ?? this.syncWithGoogle,
      googleEventId: googleEventId ?? this.googleEventId,
      googleHtmlLink: googleHtmlLink ?? this.googleHtmlLink,
      googleEtag: googleEtag ?? this.googleEtag,
      recurrenceRules: recurrenceRules ?? this.recurrenceRules,
      googleRecurringEventId:
          googleRecurringEventId ?? this.googleRecurringEventId,
      originalStartTime: originalStartTime ?? this.originalStartTime,
      originalStartTimezone:
          originalStartTimezone ?? this.originalStartTimezone,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      attendees: attendees ?? this.attendees,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
