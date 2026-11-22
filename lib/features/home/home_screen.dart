import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/theme_provider.dart';
import '../authentication/logout_icon_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;

  String userName = 'Achiever';
  bool isLiked = false;
  bool isLoading = true;

  int completedTasks = 0;
  int totalTasks = 0;
  int activeGoals = 0;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      final name = profile?['full_name'] as String?;

      if (mounted && name != null && name.trim().isNotEmpty) {
        setState(() => userName = name);
      }
    } catch (e) {
      debugPrint('Dashboard profile error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget summaryCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 25),
            const SizedBox(height: 15),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final surface = theme.colorScheme.surface;

    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: accent))
            : RefreshIndicator(
                color: accent,
                onRefresh: loadDashboard,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ELEVEN11',
                              style: TextStyle(
                                color: kSignatureOrange,
                                fontSize: 14,
                                letterSpacing: 3,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Hello, $userName ðŸ‘‹',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const LogoutIconButton(),
                      ],
                    ),

                    const SizedBox(height: 30),

                    sectionTitle('Daily Motivation'),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color.alphaBlend(
                              accent.withValues(alpha: 0.12),
                              surface,
                            ),
                            surface,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.format_quote, color: accent, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            'Discipline is choosing what you want most over what you want now.',
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 18,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'YOUR DAILY REMINDER',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                  letterSpacing: 1,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() => isLiked = !isLiked);
                                },
                                icon: Icon(
                                  isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    sectionTitle('Your Progress'),

                    Row(
                      children: [
                        summaryCard(
                          'Active Goals',
                          '$activeGoals',
                          Icons.flag_outlined,
                        ),
                        const SizedBox(width: 12),
                        summaryCard(
                          'Tasks Done',
                          '$completedTasks/$totalTasks',
                          Icons.task_alt,
                        ),
                        const SizedBox(width: 12),
                        summaryCard(
                          'Day Streak',
                          '0',
                          Icons.local_fire_department,
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    sectionTitle('Today\'s Tasks'),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: accent,
                            size: 35,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Your tasks will appear here.',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    sectionTitle('Your Achievements'),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            color: accent,
                            size: 35,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Your achievements will appear here.',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    Center(
                      child: Text(
                        'DISCIPLINE. FOCUS. ACHIEVE.',
                        style: TextStyle(
                          color: muted.withValues(alpha: 0.65),
                          fontSize: 11,
                          letterSpacing: 2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
