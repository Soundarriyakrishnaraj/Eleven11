import 'package:material_ui/material_ui.dart';

import 'streak_service.dart';

class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  final service = StreakService();

  late Future<StreakData> streaks;
  late Future<List<Map<String, dynamic>>> weeklyActivity;

  Color get orange => Theme.of(context).colorScheme.primary;
  Color get cardColor => Theme.of(context).colorScheme.surface;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    streaks = service.getStreaks();
    weeklyActivity = service.getWeeklyActivity();
  }

  Future<void> _reload() async {
    setState(_refresh);
    await Future.wait([streaks, weeklyActivity]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Streaks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        color: orange,
        onRefresh: _reload,
        child: FutureBuilder<StreakData>(
          future: streaks,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: orange));
            }

            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 150),
                  Center(
                    child: Text(
                      'Could not load streaks:\n${snapshot.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton(
                      onPressed: _reload,
                      child: const Text('Try Again'),
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _header(data),
                const SizedBox(height: 24),

                streakCard(
                  'Overall Activity',
                  data.overall,
                  data.overallLongest,
                  Icons.local_fire_department,
                  'Complete a task or engage with your daily motivation.',
                ),

                streakCard(
                  'Motivation',
                  data.motivation,
                  data.motivationLongest,
                  Icons.favorite,
                  'Engage with your daily motivational quote.',
                ),

                streakCard(
                  'Daily To-do',
                  data.tasks,
                  data.tasksLongest,
                  Icons.task_alt,
                  'Complete at least one daily task.',
                ),

                const SizedBox(height: 12),
                _weeklyCard(),

                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'DISCIPLINE. FOCUS. ACHIEVE.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(StreakData data) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        border: Border.all(color: orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(Icons.local_fire_department, color: orange, size: 48),
          const SizedBox(height: 10),
          Text(
            '${data.overall}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'DAY ACTIVITY STREAK',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep showing up. Small actions create big results.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget streakCard(
    String title,
    int current,
    int longest,
    IconData icon,
    String description,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: orange, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _number('CURRENT', current)),
              Expanded(child: _number('LONGEST', longest)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _number(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value days',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _weeklyCard() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: weeklyActivity,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: orange));
        }

        if (snapshot.hasError) {
          return _weeklyContainer(
            Text(
              'Weekly activity unavailable.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final records = snapshot.data ?? [];

        final activityMap = <String, Map<String, dynamic>>{};

        for (final record in records) {
          activityMap[record['activity_date'].toString()] = record;
        }

        final today = DateTime.now();

        return _weeklyContainer(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly Activity',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your last seven days of consistency',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final date = DateTime(
                    today.year,
                    today.month,
                    today.day,
                  ).subtract(Duration(days: 6 - index));

                  final key =
                      '${date.year.toString().padLeft(4, '0')}-'
                      '${date.month.toString().padLeft(2, '0')}-'
                      '${date.day.toString().padLeft(2, '0')}';

                  final record = activityMap[key];

                  final motivation = record?['motivation_done'] == true;
                  final task = record?['task_done'] == true;

                  final active = motivation || task;

                  return Column(
                    children: [
                      Text(
                        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][date.weekday -
                            1],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? orange
                              : Theme.of(context).colorScheme.outline,
                        ),
                        child: Icon(
                          active ? Icons.check : Icons.remove,
                          size: 17,
                          color: active
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.circle, color: orange, size: 10),
                  SizedBox(width: 6),
                  Text(
                    'Active day',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  SizedBox(width: 18),
                  Icon(
                    Icons.circle,
                    color: Theme.of(context).colorScheme.outline,
                    size: 10,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'No activity',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _weeklyContainer(Widget child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: child,
    );
  }
}
