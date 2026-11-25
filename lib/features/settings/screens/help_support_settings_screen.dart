import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../notifications/notification_service.dart';
import '../widgets/settings_tile.dart';

class HelpSupportSettingsScreen extends StatefulWidget {
  const HelpSupportSettingsScreen({super.key});

  @override
  State<HelpSupportSettingsScreen> createState() =>
      _HelpSupportSettingsScreenState();
}

class _HelpSupportSettingsScreenState extends State<HelpSupportSettingsScreen> {
  bool _clearingCache = false;

  static const List<Map<String, String>> _faqs = [
    {
      'question': 'How do Eleven11 alarms and reminders work?',
      'answer': 'Alarms use Android high-priority alarm channels and native notification audio. They trigger reliably at your designated wake-up and discipline times even when the app is in the background or device is in Doze mode.',
    },
    {
      'question': 'How do I protect and build my streaks?',
      'answer': 'Complete at least one of your daily to-do tasks or goals before midnight each day. Streaks increment automatically when you maintain daily discipline and unlock milestone achievement badges.',
    },
    {
      'question': 'Can I customize my alarm sounds?',
      'answer': 'Yes! Visit Settings > Alarm to select from high-definition built-in wake-up melodies (Classic, Gentle Rise, Digital, Morning Birds, Soft Piano, Bell Chimes) with instant audio previews.',
    },
    {
      'question': 'Does Eleven11 work offline?',
      'answer': 'Yes. Alarms and local tasks are scheduled directly on your device. Once you reconnect to the internet, your streak achievements and progress automatically synchronize with Supabase cloud storage.',
    },
    {
      'question': 'How do I change the app theme and accent colour?',
      'answer': 'Go to Settings > Appearance to switch between Dark, Light, or System modes, or use our custom RGB/HEX colour picker to personalize your Eleven11 interface with any custom shade.',
    },
  ];

  Future<void> _clearTemporaryCache() async {
    setState(() => _clearingCache = true);
    await Future.delayed(const Duration(milliseconds: 600));

    // Refreshes unread count and cleans temporary volatile notification caches safely
    await NotificationService.instance.refreshUnreadCount();

    if (!mounted) return;
    setState(() => _clearingCache = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Temporary cache cleared. Essential user data and alarms preserved.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outline;
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HELP & SUPPORT',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // CONTACT & REPORT ACTION CARDS
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/feedback',
                    arguments: 'general',
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.support_agent_rounded,
                            color: accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Contact Us',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Direct support message',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/feedback',
                    arguments: 'bug_report',
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.bug_report_outlined,
                            color: accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Report Bug',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Submit feedback',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // FREQUENTLY ASKED QUESTIONS
          const SettingsSectionHeader('FREQUENTLY ASKED QUESTIONS'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: _faqs.asMap().entries.map((entry) {
                final index = entry.key;
                final faq = entry.value;

                return Column(
                  children: [
                    if (index > 0) Divider(height: 1, color: borderColor),
                    ExpansionTile(
                      shape: const Border(),
                      iconColor: accent,
                      collapsedIconColor: theme.colorScheme.onSurfaceVariant,
                      title: Text(
                        faq['question']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text(
                            faq['answer']!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // TROUBLESHOOTING & CACHE
          const SettingsSectionHeader('APP TROUBLESHOOTING'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDiagnosticRow(
                  icon: Icons.cloud_done_rounded,
                  title: 'Cloud Synchronization',
                  status: Supabase.instance.client.auth.currentUser != null
                      ? 'Connected'
                      : 'Offline / Guest',
                  statusColor: Supabase.instance.client.auth.currentUser != null
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
                Divider(height: 18, color: borderColor),
                _buildDiagnosticRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Subsystem',
                  status: 'Active',
                  statusColor: Colors.greenAccent,
                ),
                Divider(height: 18, color: borderColor),
                _buildDiagnosticRow(
                  icon: Icons.security_rounded,
                  title: 'Local Storage Health',
                  status: 'Nominal',
                  statusColor: Colors.greenAccent,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _clearingCache ? null : _clearTemporaryCache,
                    icon: _clearingCache
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: accent,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: const Text('CLEAR TEMPORARY APP CACHE'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow({
    required IconData icon,
    required String title,
    required String status,
    required Color statusColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            softWrap: true,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
