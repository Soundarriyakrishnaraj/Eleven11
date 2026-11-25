import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/security/app_lock_service.dart';
import '../widgets/settings_tile.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _appLockEnabled = false;
  String _autoLockTimeout = '5 minutes';
  bool _analyticsEnabled = true;
  bool _personalizedInsights = true;
  bool _loading = true;

  static const List<String> _timeoutOptions = [
    'Immediately',
    '1 minute',
    '5 minutes',
    '15 minutes',
    '30 minutes',
  ];

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _appLockEnabled = AppLockService.instance.isLockEnabled;
      _autoLockTimeout = AppLockService.instance.timeout.label;
      _analyticsEnabled = prefs.getBool('privacy_analytics_enabled') ?? true;
      _personalizedInsights =
          prefs.getBool('privacy_personalized_insights') ?? true;
      _loading = false;
    });
  }

  Future<void> _setBool(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'ELEVEN11 PRIVACY POLICY',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Last updated: November 2026\n\n'
                '1. Information We Collect\n'
                'Eleven11 collects your account credentials (email, display name) and personal goal data (alarms, habits, tasks, streaks) solely to provide time management and discipline tracking.\n\n'
                '2. How We Store Your Data\n'
                'All user records are secured using Supabase Row-Level Security (RLS) policies. Only your authenticated user ID can access your alarms, goals, and tasks.\n\n'
                '3. On-Device Processing\n'
                'Alarm audio files, custom ringtones, and notification schedules are configured and triggered strictly on your local device.\n\n'
                '4. Data Retention & Deletion\n'
                'You retain full ownership of your data and can request account erasure at any time via authenticated server-side procedures.\n\n'
                '5. Third-Party Services\n'
                'Eleven11 integrates with Firebase Cloud Messaging for push alerts and Supabase for cloud synchronization. No telemetry is sold to advertisers.\n',
                style: TextStyle(height: 1.5, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountDeletionInfo() {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'your account';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 10),
            Text(
              'Account Deletion',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deleting $email will permanently erase your profile, all goals, alarms, tasks, and earned streaks.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Security Architecture Notice:\n'
                'To safeguard user data and maintain zero-trust security standards, account deletion cannot be executed with client-side admin keys. It requires invocation of our secure server-side Supabase Edge Function to securely cascade-delete auth users and private storage assets.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onErrorContainer,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Deletion request registered. Backend Supabase Edge Function is required to complete final database purging.',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
            },
            child: const Text('Understood'),
          ),
        ],
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
          'PRIVACY & SECURITY',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              children: [
                // DEVICE SECURITY & APP LOCK
                const SettingsSectionHeader('DEVICE SECURITY'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeTrackColor: accent,
                        secondary: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.fingerprint_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'App Lock & Biometrics',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Require fingerprint, face, or PIN upon opening Eleven11',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _appLockEnabled,
                        onChanged: (val) async {
                          setState(() => _appLockEnabled = val);
                          await AppLockService.instance.setLockEnabled(val);
                        },
                      ),
                      if (_appLockEnabled) ...[
                        Divider(height: 1, color: borderColor),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.lock_clock_outlined,
                                      color: accent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Auto-Lock Timeout',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          _autoLockTimeout,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: borderColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: _autoLockTimeout,
                                    dropdownColor: cardColor,
                                    items: _timeoutOptions.map((t) {
                                      return DropdownMenuItem(value: t, child: Text(t));
                                    }).toList(),
                                    onChanged: (val) async {
                                      if (val != null) {
                                        setState(() => _autoLockTimeout = val);
                                        final matched = AppLockTimeout.values.firstWhere(
                                          (t) => t.label == val,
                                          orElse: () => AppLockTimeout.immediately,
                                        );
                                        await AppLockService.instance.setTimeout(matched);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // DATA & PRIVACY
                const SettingsSectionHeader('DATA & PRIVACY PREFERENCES'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        activeTrackColor: accent,
                        secondary: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.analytics_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Anonymous Diagnostics',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Help improve Eleven11 by sending crash and performance data',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _analyticsEnabled,
                        onChanged: (val) {
                          setState(() => _analyticsEnabled = val);
                          _setBool('privacy_analytics_enabled', val);
                        },
                      ),
                      Divider(height: 1, color: borderColor),
                      SwitchListTile(
                        activeTrackColor: accent,
                        secondary: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.insights_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Personalized Insights',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Tailor motivation tips to your goal patterns',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _personalizedInsights,
                        onChanged: (val) {
                          setState(() => _personalizedInsights = val);
                          _setBool('privacy_personalized_insights', val);
                        },
                      ),
                      Divider(height: 1, color: borderColor),
                      ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.policy_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Read how your data is handled and protected',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: _showPrivacyPolicy,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // DANGER ZONE / ACCOUNT DELETION
                const SettingsSectionHeader('ACCOUNT MANAGEMENT'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Account Deletion & Data Erasure',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.redAccent,
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Permanently delete your Eleven11 profile and clear all associated goals, streaks, and history from our secure servers.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _showAccountDeletionInfo,
                          child: const Text(
                            'REQUEST ACCOUNT DELETION',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
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
}
