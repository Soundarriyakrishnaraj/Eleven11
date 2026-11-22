import 'package:supabase_flutter/supabase_flutter.dart';

class GoalService {
  GoalService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Please log in to manage your goals.');
    }
    return user.id;
  }

  Future<List<Map<String, dynamic>>> getGoals() async {
    final response = await _client
        .from('goals')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await _client
        .from('goal_categories')
        .select()
        .order('name');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> createGoal({
    required String title,
    String? description,
    String? categoryId,
    DateTime? startDate,
    DateTime? targetDate,
  }) async {
    await _client.from('goals').insert({
      'user_id': _userId,
      'title': title.trim(),
      'description': description?.trim(),
      'category_id': categoryId,
      'start_date': startDate?.toIso8601String().split('T').first,
      'target_date': targetDate?.toIso8601String().split('T').first,
      'progress': 0,
      'status': 'active',
    });
  }

  Future<void> updateGoal({
    required String goalId,
    required Map<String, dynamic> updates,
  }) async {
    await _client
        .from('goals')
        .update({
          ...updates,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', goalId)
        .eq('user_id', _userId);
  }

  // Automatically calculate goal progress from its checklist.
  Future<void> syncProgressFromTasks(String goalId) async {
    final tasks = await _client
        .from('tasks')
        .select('is_completed')
        .eq('user_id', _userId)
        .eq('goal_id', goalId);

    final total = tasks.length;
    final completed = tasks
        .where((task) => task['is_completed'] == true)
        .length;

    final progress = total == 0 ? 0 : ((completed / total) * 100).round();

    final goal = await _client
        .from('goals')
        .select('status')
        .eq('id', goalId)
        .eq('user_id', _userId)
        .maybeSingle();

    if (goal == null) return;

    final currentStatus = goal['status']?.toString() ?? 'active';

    String newStatus = currentStatus;

    if (total > 0 && completed == total) {
      newStatus = 'completed';
    } else if (currentStatus == 'completed') {
      newStatus = 'active';
    }

    await updateGoal(
      goalId: goalId,
      updates: {'progress': progress, 'status': newStatus},
    );
  }

  Future<void> updateProgress({
    required String goalId,
    required int progress,
  }) async {
    final value = progress.clamp(0, 100);

    await updateGoal(
      goalId: goalId,
      updates: {
        'progress': value,
        'status': value == 100 ? 'completed' : 'active',
      },
    );
  }

  Future<void> pauseGoal(String goalId) async {
    await updateGoal(goalId: goalId, updates: {'status': 'paused'});
  }

  Future<void> resumeGoal(String goalId) async {
    await updateGoal(goalId: goalId, updates: {'status': 'active'});
  }

  Future<void> completeGoal(String goalId) async {
    await updateGoal(
      goalId: goalId,
      updates: {'progress': 100, 'status': 'completed'},
    );
  }

  Future<void> deleteGoal(String goalId) async {
    await _client
        .from('goals')
        .delete()
        .eq('id', goalId)
        .eq('user_id', _userId);
  }
}
