import 'dart:convert';

enum NotificationCategory {
  alarm,
  task,
  goal,
  motivation,
  announcement,
  general;

  static NotificationCategory fromString(String? value) {
    if (value == null) return NotificationCategory.general;
    switch (value.toLowerCase().trim()) {
      case 'alarm':
      case 'alarm_reminder':
        return NotificationCategory.alarm;
      case 'task':
      case 'task_reminder':
      case 'today_task':
        return NotificationCategory.task;
      case 'goal':
      case 'goal_reminder':
        return NotificationCategory.goal;
      case 'motivation':
      case 'daily_quote':
      case 'quote':
        return NotificationCategory.motivation;
      case 'announcement':
      case 'update':
      case 'news':
        return NotificationCategory.announcement;
      default:
        return NotificationCategory.general;
    }
  }

  String toDbString() {
    switch (this) {
      case NotificationCategory.alarm:
        return 'alarm';
      case NotificationCategory.task:
        return 'task';
      case NotificationCategory.goal:
        return 'goal';
      case NotificationCategory.motivation:
        return 'motivation';
      case NotificationCategory.announcement:
        return 'announcement';
      case NotificationCategory.general:
        return 'general';
    }
  }

  String get displayName {
    switch (this) {
      case NotificationCategory.alarm:
        return 'Alarm';
      case NotificationCategory.task:
        return 'Task Reminder';
      case NotificationCategory.goal:
        return 'Goal Reminder';
      case NotificationCategory.motivation:
        return 'Daily Motivation';
      case NotificationCategory.announcement:
        return 'Announcement';
      case NotificationCategory.general:
        return 'Notification';
    }
  }
}

class AppNotification {
  final String id;
  final String userId;
  final String? sourceEventId;
  final NotificationCategory category;
  final String rawType;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.sourceEventId,
    required this.category,
    required this.rawType,
    required this.title,
    required this.body,
    this.data = const {},
    this.isRead = false,
    this.readAt,
    required this.createdAt,
  });

  AppNotification copyWith({
    String? id,
    String? userId,
    String? sourceEventId,
    NotificationCategory? category,
    String? rawType,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? readAt,
    bool clearReadAt = false,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      category: category ?? this.category,
      rawType: rawType ?? this.rawType,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString() ?? 'general';
    final category = NotificationCategory.fromString(rawType);

    Map<String, dynamic> parsedData = {};
    if (json['data'] != null) {
      if (json['data'] is Map) {
        parsedData = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json['data'] is String &&
          (json['data'] as String).isNotEmpty) {
        try {
          parsedData = Map<String, dynamic>.from(
            jsonDecode(json['data'] as String) as Map,
          );
        } catch (_) {}
      }
    }

    DateTime parsedCreatedAt = DateTime.now();
    if (json['created_at'] != null) {
      final parsed = DateTime.tryParse(json['created_at'].toString());
      if (parsed != null) parsedCreatedAt = parsed.toLocal();
    }

    DateTime? parsedReadAt;
    if (json['read_at'] != null) {
      parsedReadAt = DateTime.tryParse(json['read_at'].toString())?.toLocal();
    }

    return AppNotification(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      sourceEventId: json['source_event_id']?.toString(),
      category: category,
      rawType: rawType,
      title: json['title']?.toString() ?? 'Eleven11',
      body: json['body']?.toString() ?? '',
      data: parsedData,
      isRead: json['is_read'] == true,
      readAt: parsedReadAt,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'source_event_id': sourceEventId,
      'type': rawType,
      'title': title,
      'body': body,
      'data': data,
      'is_read': isRead,
      'read_at': readAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday, ${_formatClockTime(createdAt)}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
    }
  }

  static String _formatClockTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
