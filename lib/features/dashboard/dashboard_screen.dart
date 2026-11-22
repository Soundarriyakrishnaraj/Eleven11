import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/theme_provider.dart';
import '../authentication/logout_icon_button.dart';
import '../alarms/screens/alarm_reminders_screen.dart';

import '../goals/screens/goals_screen.dart';
import '../tasks/screens/tasks_screen.dart';
import '../streaks/streak_screen.dart';
import '../streaks/streak_service.dart';
import '../achievements/achievements_screen.dart';
import '../notifications/notification_screen.dart';
import '../notifications/notification_service.dart';
import '../settings/screens/account_settings_screen.dart';
import '../settings/screens/notification_settings_screen.dart';
import '../settings/screens/alarm_settings_screen.dart';
import '../settings/screens/appearance_settings_screen.dart';
import '../settings/screens/personalization_settings_screen.dart';
import '../settings/screens/focus_settings_screen.dart';
import '../settings/screens/privacy_settings_screen.dart';
import '../settings/screens/help_support_settings_screen.dart';
import '../settings/screens/about_settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Color get orange => Theme.of(context).colorScheme.primary;

  Color get cardColor => Theme.of(context).colorScheme.surface;

  final StreakService _streakService = StreakService();

  bool statsLoading = true;
  bool streakLoading = true;

  int totalAchievements = 0;
  int unlockedCount = 0;
  int totalPoints = 0;

  StreakData? streakData;

  List<Map<String, dynamic>> earnedBadges = [];

  int _unreadNotificationsCount = 0;
  StreamSubscription<int>? _unreadSub;

  @override
  void initState() {
    super.initState();
    _loadAchievementData();
    _loadStreakData();
    _unreadNotificationsCount = NotificationService.instance.currentUnreadCount;
    _unreadSub = NotificationService.instance.unreadCountStream.listen((count) {
      if (mounted) setState(() => _unreadNotificationsCount = count);
    });
    NotificationService.instance.refreshUnreadCount();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStreakData() async {
    try {
      final result = await _streakService.getStreaks();

      if (!mounted) return;

      setState(() {
        streakData = result;
        streakLoading = false;
      });
    } catch (e) {
      debugPrint('Dashboard streak loading error: $e');

      if (mounted) {
        setState(() {
          streakLoading = false;
        });
      }
    }
  }

  Future<void> _loadAchievementData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) {
          setState(() {
            statsLoading = false;
          });
        }
        return;
      }

      final allResult = await supabase
          .from('achievements')
          .select('id, name, icon_url, points')
          .eq('is_active', true);

      final earnedResult = await supabase
          .from('user_achievements')
          .select('achievement_id, earned_at')
          .eq('user_id', user.id)
          .order('earned_at', ascending: false);

      final allAchievements = List<Map<String, dynamic>>.from(allResult);
      final earned = List<Map<String, dynamic>>.from(earnedResult);

      final achievementMap = {
        for (final item in allAchievements) item['id'].toString(): item,
      };

      final badges = <Map<String, dynamic>>[];
      int points = 0;

      for (final item in earned) {
        final achievement = achievementMap[item['achievement_id'].toString()];

        if (achievement != null) {
          badges.add(achievement);
          points += (achievement['points'] as num?)?.toInt() ?? 0;
        }
      }

      if (!mounted) return;

      setState(() {
        totalAchievements = allAchievements.length;
        unlockedCount = badges.length;
        totalPoints = points;
        earnedBadges = badges;
        statsLoading = false;
      });
    } catch (e) {
      debugPrint('Dashboard achievement loading error: $e');

      if (mounted) {
        setState(() {
          statsLoading = false;
        });
      }
    }
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    if (mounted) {
      _loadAchievementData();
      _loadStreakData();
    }
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'WHAT WOULD YOU LIKE TO ADD?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              _optionTile(
                icon: Icons.flag_outlined,
                title: 'Set a Goal',
                subtitle: 'Create a goal and track your progress',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(context, const GoalsScreen());
                },
              ),
              const SizedBox(height: 12),
              _optionTile(
                icon: Icons.checklist,
                title: 'Daily To-do List',
                subtitle: 'Add tasks for today',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(context, const TasksScreen());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: orange, size: 30),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: orange, size: 16),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        fontSize: 12,
      ),
    );
  }

  // CURRENT STREAK: STATIC CARD
  Widget _currentStreakCard() {
    return Expanded(
      flex: 1,
      child: Container(
        height: 158,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(Icons.local_fire_department_rounded, color: orange, size: 27),
            if (streakLoading)
              SizedBox(
                height: 30,
                width: 30,
                child: CircularProgressIndicator(color: orange, strokeWidth: 2),
              )
            else
              Text(
                '${streakData?.overall ?? 0}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Streak',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // LONGEST STREAK: WIDE CLICKABLE CARD
  Widget _longestStreakCard() {
    return Expanded(
      flex: 2,
      child: InkWell(
        onTap: () => _open(context, const StreakScreen()),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 158,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: orange.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: orange, size: 26),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 14,
                  ),
                ],
              ),
              if (streakLoading)
                SizedBox(
                  height: 30,
                  width: 30,
                  child: CircularProgressIndicator(
                    color: orange,
                    strokeWidth: 2,
                  ),
                )
              else
                Text(
                  '${streakData?.overallLongest ?? 0}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 35,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LONGEST STREAK',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Your personal best',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _streakSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _currentStreakCard(),
        const SizedBox(width: 12),
        _longestStreakCard(),
      ],
    );
  }

  // ACHIEVEMENTS
  Widget _achievementSection() {
    final double progress = totalAchievements == 0
        ? 0.0
        : (unlockedCount / totalAchievements).clamp(0.0, 1.0).toDouble();

    return InkWell(
      onTap: () => _open(context, const AchievementsScreen()),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: orange.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: orange.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: 0.17),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: orange,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR ACHIEVEMENTS',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Every milestone tells your story.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: orange, size: 16),
              ],
            ),
            const SizedBox(height: 24),
            if (statsLoading)
              Center(
                child: CircularProgressIndicator(color: orange, strokeWidth: 2),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$unlockedCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 39,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      ' / $totalAchievements unlocked',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 9,
                  backgroundColor: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.12),
                  color: orange,
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    color: kSignatureGold,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$totalPoints POINTS EARNED',
                    style: const TextStyle(
                      color: kSignatureGold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'VIEW ALL',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // BADGE COLLECTION
  Widget _badgeSection() {
    return InkWell(
      onTap: () => _open(context, const AchievementsScreen()),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(17, 18, 17, 17),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.military_tech_rounded, color: orange, size: 25),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'BADGE COLLECTION',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  'SEE ALL →',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (statsLoading)
              Center(
                child: CircularProgressIndicator(color: orange, strokeWidth: 2),
              )
            else if (earnedBadges.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  children: [
                    Text('🔒', style: TextStyle(fontSize: 34)),
                    SizedBox(height: 9),
                    Text(
                      'Your first badge is waiting!',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Complete a goal to earn your first reward.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: earnedBadges.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 13),
                  itemBuilder: (context, index) {
                    final badge = earnedBadges[index];
                    final icon = badge['icon_url']?.toString() ?? '🏅';
                    final name = badge['name']?.toString() ?? 'Badge';

                    return SizedBox(
                      width: 82,
                      child: Column(
                        children: [
                          Container(
                            height: 65,
                            width: 65,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.5),
                                  Theme.of(context).colorScheme.surface,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: orange.withValues(alpha: 0.7),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 29),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.workspace_premium, color: orange, size: 17),
                const SizedBox(width: 7),
                Text(
                  '$unlockedCount badges collected',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Text(
                  '$totalPoints PTS',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 125,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: orange, size: 32),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 23,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -5,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'ELEVEN11',
          style: TextStyle(
            color: kSignatureOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        actions: [const LogoutIconButton(), const SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        children: [
          Text(
            'YOUR DASHBOARD',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make today count.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Stay disciplined. Keep moving forward.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),

          // MOTIVATION
          Container(
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  Theme.of(context).colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: orange.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_quote, color: orange, size: 25),
                    SizedBox(width: 7),
                    Text(
                      "TODAY'S MOTIVATION",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 13),
                Text(
                  'Your only limit is the one you refuse to challenge.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'DISCIPLINE. FOCUS. ACHIEVE.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          _sectionTitle('YOUR STREAKS'),
          const SizedBox(height: 13),
          _streakSection(),

          const SizedBox(height: 27),

          _sectionTitle('YOUR ACHIEVEMENTS'),
          const SizedBox(height: 13),
          _achievementSection(),

          const SizedBox(height: 17),

          _badgeSection(),

          const SizedBox(height: 27),

          _sectionTitle('YOUR WORKSPACE'),
          const SizedBox(height: 13),
          Row(
            children: [
              _workspaceTile(
                icon: Icons.flag_outlined,
                title: 'My Goals',
                subtitle: 'Plan your future',
                onTap: () => _open(context, const GoalsScreen()),
              ),
              const SizedBox(width: 12),
              _workspaceTile(
                icon: Icons.checklist_rounded,
                title: 'Daily To-do',
                subtitle: 'Win your day',
                onTap: () => _open(context, const TasksScreen()),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Center(
            child: Text(
              'DISCIPLINE. FOCUS. ACHIEVE.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              _bottomItem(icon: Icons.home_filled, label: 'Home', onTap: () {}),
              _bottomItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                badgeCount: _unreadNotificationsCount,
                onTap: () => _open(context, const NotificationScreen()),
              ),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -10),
                    child: FloatingActionButton(
                      heroTag: 'dashboard_add_button',
                      backgroundColor: orange,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      elevation: 5,
                      onPressed: () => _showAddOptions(context),
                      child: const Icon(Icons.add, size: 30),
                    ),
                  ),
                ),
              ),
              _bottomItem(
                icon: Icons.alarm_outlined,
                label: 'Alarms',
                onTap: () => _open(context, const AlarmRemindersScreen()),
              ),
              _bottomItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => _open(context, const AppSettingsScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// TEMPORARY ALARM CENTRE
class AlarmCentreScreen extends StatelessWidget {
  const AlarmCentreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ALARM & REMINDERS')),
      body: Center(
        child: Text(
          'Your alarms and reminders will appear here.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// TEMPORARY SETTINGS
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          // ACCOUNT
          const _SectionHeader('ACCOUNT'),
          _Tile(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Manage your profile and credentials',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          // NOTIFICATIONS
          const _SectionHeader('NOTIFICATIONS'),
          _Tile(
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Control alerts and reminders',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ALARM
          const _SectionHeader('ALARM'),
          _Tile(
            icon: Icons.alarm,
            title: 'Alarm',
            subtitle: 'Default sounds, snooze and volume',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlarmSettingsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          // APPEARANCE
          const _SectionHeader('APPEARANCE'),
          _Tile(
            icon: Icons.color_lens_outlined,
            title: 'Appearance',
            subtitle: 'Theme, accent color and display',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppearanceSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // PERSONALIZATION
          const _SectionHeader('PERSONALIZATION'),
          _Tile(
            icon: Icons.tune,
            title: 'Personalization',
            subtitle: 'Language, date and home screen',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PersonalizationSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // FOCUS & PRODUCTIVITY
          const _SectionHeader('FOCUS & PRODUCTIVITY'),
          _Tile(
            icon: Icons.access_time_filled_outlined,
            title: 'Focus & Productivity',
            subtitle: 'Pomodoro, Do Not Disturb and habits',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FocusSettingsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          // PRIVACY & SECURITY
          const _SectionHeader('PRIVACY & SECURITY'),
          _Tile(
            icon: Icons.lock_outline,
            title: 'Privacy & Security',
            subtitle: 'Data, biometrics and security options',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          // HELP & SUPPORT
          const _SectionHeader('HELP & SUPPORT'),
          _Tile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'FAQs, feedback and contact us',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HelpSupportSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ABOUT
          const _SectionHeader('ABOUT'),
          _Tile(
            icon: Icons.info_outline,
            title: 'About Eleven11',
            subtitle: 'Version, licenses and credits',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutSettingsScreen()),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
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
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
