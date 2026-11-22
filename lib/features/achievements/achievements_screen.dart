import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  Color get orange => Theme.of(context).colorScheme.primary;
  Color get cardColor => Theme.of(context).colorScheme.surface;

  bool loading = true;
  String? errorMessage;

  List<Map<String, dynamic>> achievements = [];
  Set<String> unlockedIds = {};
  Map<String, String> earnedDates = {};

  @override
  void initState() {
    super.initState();
    loadAchievements();
  }

  Future<void> loadAchievements() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in to view your achievements.');
      }

      final achievementResult = await supabase
          .from('achievements')
          .select('id, name, description, icon_url, points')
          .eq('is_active', true)
          .order('points');

      final unlockedResult = await supabase
          .from('user_achievements')
          .select('achievement_id, earned_at')
          .eq('user_id', user.id);

      achievements = List<Map<String, dynamic>>.from(achievementResult);

      unlockedIds = {};
      earnedDates = {};

      for (final item in unlockedResult) {
        final id = item['achievement_id'].toString();
        unlockedIds.add(id);

        if (item['earned_at'] != null) {
          earnedDates[id] = item['earned_at'].toString();
        }
      }
    } catch (e) {
      errorMessage = e.toString();
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlockedCount = achievements
        .where((item) => unlockedIds.contains(item['id'].toString()))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Achievements & Badges',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loadAchievements,
            icon: Icon(Icons.refresh, color: orange),
          ),
        ],
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: orange))
          : errorMessage != null
          ? _errorView()
          : RefreshIndicator(
              color: orange,
              onRefresh: loadAchievements,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _summaryCard(unlockedCount),
                  const SizedBox(height: 25),
                  Text(
                    'YOUR BADGES',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (achievements.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(25),
                      child: Text(
                        'Your first achievement is waiting. '
                        'Start completing your goals!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ...achievements.map(_achievementCard),
                  const SizedBox(height: 25),
                  Center(
                    child: Text(
                      'KEEP SHOWING UP. KEEP ACHIEVING.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(int unlockedCount) {
    final progress = achievements.isEmpty
        ? 0.0
        : unlockedCount / achievements.length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 43)),
          const SizedBox(height: 10),
          Text(
            'YOUR ACHIEVEMENTS',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            '$unlockedCount / ${achievements.length}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Badges unlocked',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 17),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.12),
              color: orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _achievementCard(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final unlocked = unlockedIds.contains(id);

    final icon = item['icon_url']?.toString() ?? '🏅';
    final title = item['name']?.toString() ?? 'Achievement';
    final description =
        item['description']?.toString() ?? 'Keep working towards this badge.';
    final points = item['points'] ?? 0;

    String? earnedDate;
    if (earnedDates[id] != null) {
      final parsed = DateTime.tryParse(earnedDates[id]!);
      if (parsed != null) {
        earnedDate = '${parsed.day}/${parsed.month}/${parsed.year}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? orange.withValues(alpha: 0.6)
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 57,
            width: 57,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: unlocked
                  ? orange.withValues(alpha: 0.18)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              unlocked ? icon : '🔒',
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: unlocked
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  unlocked && earnedDate != null
                      ? 'Earned $earnedDate • $points points'
                      : '$points points',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            unlocked ? Icons.check_circle : Icons.lock_outline,
            color: unlocked
                ? orange
                : Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
            size: 23,
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: orange, size: 45),
            const SizedBox(height: 15),
            Text(
              'Could not load achievements',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: loadAchievements,
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
