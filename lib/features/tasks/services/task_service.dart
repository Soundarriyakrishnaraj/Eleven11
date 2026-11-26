import 'package:supabase_flutter/supabase_flutter.dart';

import '../../badges/badge_service.dart';
import '../../calendar/services/google_calendar_service.dart';
import '../../goals/services/goal_service.dart';

abstract interface class TaskReader {
  Future<List<Map<String, dynamic>>> getDailyTasks();

  Future<Map<String, dynamic>?> getTaskById(String taskId);
}

class TaskService implements TaskReader {
  final SupabaseClient _client = Supabase.instance.client;
  final GoalService _goalService = GoalService();
  final GoogleCalendarService _googleCalendarService = GoogleCalendarService();

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Please sign in to manage tasks.');
    }
    return user.id;
  }

  @override
  Future<List<Map<String, dynamic>>> getDailyTasks() async {
    final response = await _client
        .from('tasks')
        .select()
        .eq('user_id', _userId)
        .isFilter('goal_id', null)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> getTaskById(String taskId) async {
    final response = await _client
        .from('tasks')
        .select()
        .eq('id', taskId)
        .eq('user_id', _userId)
        .maybeSingle();
    return response;
  }

  Future<List<Map<String, dynamic>>> getGoalTasks(String goalId) async {
    final response = await _client
        .from('tasks')
        .select()
        .eq('user_id', _userId)
        .eq('goal_id', goalId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> createTask({
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
    String? dueTime,
    String? endTime,
    String timezone = 'Asia/Kolkata',
    int? reminderMinutes,
    String? goalId,
  }) async {
    final payload = <String, dynamic>{
      'user_id': _userId,
      'goal_id': goalId,
      'title': title.trim(),
      'description': description?.trim(),
      'priority': priority,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'due_time': ?dueTime,
      'end_time': ?endTime,
      'timezone': timezone,
      'reminder_minutes': ?reminderMinutes,
      'is_completed': false,
    };

    final inserted = await _client
        .from('tasks')
        .insert(payload)
        .select()
        .maybeSingle();

    if (goalId != null) {
      await _goalService.syncProgressFromTasks(goalId);
    }

    if (inserted != null && dueDate != null && dueTime != null) {
      await _googleCalendarService.syncTask(Map<String, dynamic>.from(inserted));
    }
  }

  Future<void> toggleTask({
    required String taskId,
    required bool completed,
    bool countForStreak = false,
  }) async {
    final now = DateTime.now();

    final task = await _client
        .from('tasks')
        .select('goal_id')
        .eq('id', taskId)
        .eq('user_id', _userId)
        .maybeSingle();

    final updated = await _client
        .from('tasks')
        .update({
          'is_completed': completed,
          'completed_at': completed ? now.toUtc().toIso8601String() : null,
          'updated_at': now.toUtc().toIso8601String(),
        })
        .eq('id', taskId)
        .eq('user_id', _userId)
        .select()
        .maybeSingle();

    if (updated != null &&
        updated['due_date'] != null &&
        updated['due_time'] != null) {
      await _googleCalendarService.syncTask(Map<String, dynamic>.from(updated));
    }

    final goalId = task?['goal_id']?.toString();

    if (goalId != null) {
      await _goalService.syncProgressFromTasks(goalId);
    }
    BadgeService.notifyChanged();

    if (completed && countForStreak) {
      final localDate =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      await _client.rpc(
        'record_task_activity',
        params: {'p_local_date': localDate},
      );
    }
  }

  Future<void> deleteTask(String taskId) async {
    final task = await _client
        .from('tasks')
        .select('goal_id, google_calendar_id, google_event_id')
        .eq('id', taskId)
        .eq('user_id', _userId)
        .maybeSingle();

    await _client
        .from('tasks')
        .delete()
        .eq('id', taskId)
        .eq('user_id', _userId);

    if (task != null && task['google_event_id'] != null) {
      await _googleCalendarService.deleteTaskEvent(Map<String, dynamic>.from(task));
    }

    final goalId = task?['goal_id']?.toString();

    if (goalId != null) {
      await _goalService.syncProgressFromTasks(goalId);
    }
  }
}
