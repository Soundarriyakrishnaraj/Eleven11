import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../authentication/logout_icon_button.dart';
import '../alarms/screens/alarm_reminders_screen.dart';

import '../goals/screens/goals_screen.dart';
import '../tasks/screens/tasks_screen.dart';
import '../notes/screens/notes_screen.dart';
import '../motivation/screens/motivation_screen.dart';
import '../calendar/screens/calendar_screen.dart';
import '../streaks/streak_screen.dart';
import '../streaks/streak_service.dart';
import '../achievements/achievements_screen.dart';
import '../badges/badge_shelf.dart';
import 'daily_quotes.dart';
import 'home_quick_todo.dart';
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
  const DashboardScreen({super.key, this.initialLandingScreen});

  final String? initialLandingScreen;

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
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadAchievementData();
    _loadStreakData();
    _openInitialLandingIfNeeded();
    _unreadNotificationsCount = NotificationService.instance.currentUnreadCount;
    _unreadSub = NotificationService.instance.unreadCountStream.listen((count) {
      if (mounted) setState(() => _unreadNotificationsCount = count);
    });
    NotificationService.instance.refreshUnreadCount();
    // Proactively request notification and alarm permissions on dashboard launch
    unawaited(NotificationService.instance.requestAlarmPermissions());
  }

  static bool _didOpenInitialLanding = false;

  void _openInitialLandingIfNeeded() {
    if (_didOpenInitialLanding) return;
    _didOpenInitialLanding = true;
    final target = widget.initialLandingScreen;
    if (target == null || target == 'Dashboard') return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Widget? page;
      switch (target) {
        case 'Motivation':
          page = const MotivationScreen();
          break;
        case 'Daily To-do':
          page = const TasksScreen();
          break;
        case 'Goals':
          page = const GoalsScreen();
          break;
      }
      if (page != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
      }
    });
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
        child: SingleChildScrollView(
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
              const SizedBox(height: 12),
              _optionTile(
                icon: Icons.note_alt_outlined,
                title: 'Notes',
                subtitle: 'Write formatted notes',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(context, const NotesScreen());
                },
              ),
              const SizedBox(height: 12),
              _optionTile(
                icon: Icons.event_outlined,
                title: 'Event',
                subtitle: 'Schedule on your calendar',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _open(context, const CalendarScreen());
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
          constraints: const BoxConstraints(minHeight: 110),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: orange, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
    bool isSelected = false,
  }) {
    final itemColor = isSelected
        ? orange
        : Theme.of(context).colorScheme.onSurfaceVariant;
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
                  color: itemColor,
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
                color: itemColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
      appBar: _selectedTab == 0
          ? AppBar(
              elevation: 0,
              title: Text(
                'ELEVEN11',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              centerTitle: true,
              actions: [
                if (Supabase.instance.client.auth.currentUser?.id ==
                    '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a')
                  IconButton(
                    icon: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 26,
                    ),
                    tooltip: 'Admin Panel',
                    onPressed: () {
                      Navigator.pushNamed(context, '/admin');
                    },
                  ),
                const LogoutIconButton(),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildHomeBody(context),
          const AlarmRemindersScreen(),
          const NotificationScreen(),
          const AppSettingsScreen(),
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
              _bottomItem(
                icon: Icons.home_filled,
                label: 'Home',
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              _bottomItem(
                icon: Icons.alarm_outlined,
                label: 'Alarms',
                isSelected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
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
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                badgeCount: _unreadNotificationsCount,
                isSelected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
              _bottomItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                isSelected: _selectedTab == 3,
                onTap: () => setState(() => _selectedTab = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBody(BuildContext context) {
    final currentStreak = streakData?.overall ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [
        // 1. TODAY'S MOTIVATION
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                Theme.of(context).colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: orange.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_quote, color: orange, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    "TODAY'S MOTIVATION",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                quoteForDate(DateTime.now()),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 2. GENERAL TO-DO LIST
        const HomeQuickTodo(),

        const SizedBox(height: 24),

        // 3. YOUR WORKSPACE (Goals, Daily To-do, Calendar, Notes)
        _sectionTitle('YOUR WORKSPACE'),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Row(
          children: [
            _workspaceTile(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar',
              subtitle: 'Schedule & events',
              onTap: () => _open(context, const CalendarScreen()),
            ),
            const SizedBox(width: 12),
            _workspaceTile(
              icon: Icons.note_alt_outlined,
              title: 'Notes',
              subtitle: 'Rich text notes',
              onTap: () => _open(context, const NotesScreen()),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // 3. STREAKS & ACHIEVEMENTS IN PARALLEL, BADGES ON NEXT LINE
        _sectionTitle('PROGRESS'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _compactStatCard(
                icon: Icons.local_fire_department_rounded,
                label: 'Streaks',
                value: streakLoading ? '—' : '$currentStreak d',
                onTap: () => _open(context, const StreakScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _compactStatCard(
                icon: Icons.emoji_events_outlined,
                label: 'Achievements',
                value: statsLoading ? '—' : '$unlockedCount/$totalAchievements',
                onTap: () => _open(context, const AchievementsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _staticBadgeShelf(),
      ],
    );
  }

  Widget _staticBadgeShelf() => BadgeShelf(cardColor: cardColor, accent: orange);

  Widget _compactStatCard({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: orange, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// SETTINGS
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
          const SizedBox(height: 32),
          // SIGN OUT ACTION AT THE END OF SETTINGS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirm Sign Out'),
                    content: const Text('Are you sure you want to sign out of Eleven11?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                          foregroundColor: Theme.of(ctx).colorScheme.onError,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text(
                'SIGN OUT',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
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

