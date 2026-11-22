import 'package:supabase_flutter/supabase_flutter.dart';

class StreakData {
  final int motivation;
  final int motivationLongest;
  final int tasks;
  final int tasksLongest;
  final int overall;
  final int overallLongest;

  const StreakData({
    required this.motivation,
    required this.motivationLongest,
    required this.tasks,
    required this.tasksLongest,
    required this.overall,
    required this.overallLongest,
  });

  factory StreakData.fromJson(Map<String, dynamic> json) {
    return StreakData(
      motivation: (json['motivation_current'] as num? ?? 0).toInt(),
      motivationLongest: (json['motivation_longest'] as num? ?? 0).toInt(),
      tasks: (json['task_current'] as num? ?? 0).toInt(),
      tasksLongest: (json['task_longest'] as num? ?? 0).toInt(),
      overall: (json['overall_current'] as num? ?? 0).toInt(),
      overallLongest: (json['overall_longest'] as num? ?? 0).toInt(),
    );
  }
}

class StreakService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<StreakData> getStreaks() async {
    final result = await _client.rpc('get_user_streaks');

    if (result is! List || result.isEmpty) {
      throw Exception('Unable to load streaks.');
    }

    return StreakData.fromJson(Map<String, dynamic>.from(result.first));
  }

  Future<void> recordTaskCompletion() async {
    final now = DateTime.now();

    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    await _client.rpc('record_task_activity', params: {'p_local_date': date});
  }

  Future<List<Map<String, dynamic>>> getWeeklyActivity() async {
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw Exception('Please sign in.');
    }

    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));

    final startDate =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';

    final response = await _client
        .from('user_daily_activity')
        .select('activity_date, motivation_done, task_done')
        .eq('user_id', userId)
        .gte('activity_date', startDate)
        .order('activity_date');

    return List<Map<String, dynamic>>.from(response);
  }
}
