import 'package:material_ui/material_ui.dart';

import '../models/notification_preferences_model.dart';
import '../notification_service.dart';

class NotificationPreferencesSheet extends StatefulWidget {
  const NotificationPreferencesSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationPreferencesSheet(),
    );
  }

  @override
  State<NotificationPreferencesSheet> createState() =>
      _NotificationPreferencesSheetState();
}

class _NotificationPreferencesSheetState
    extends State<NotificationPreferencesSheet> {
  final NotificationService _service = NotificationService.instance;
  NotificationPreferences _prefs = const NotificationPreferences();
  bool _loading = true;
  bool _saving = false;

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _outline => Theme.of(context).colorScheme.outline;
  Color get _foreground => Theme.of(context).colorScheme.onSurface;
  Color get _muted => Theme.of(context).colorScheme.onSurfaceVariant;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await _service.fetchPreferences();

    if (!mounted) return;

    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  Future<void> _updatePreferences(NotificationPreferences updated) async {
    setState(() {
      _prefs = updated;
      _saving = true;
    });

    try {
      await _service.savePreferences(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickTime({
    required BuildContext context,
    required String currentTime,
    required ValueChanged<String> onSelected,
  }) async {
    final parts = currentTime.split(':');

    final initialHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 8) : 8;

    final initialMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

      onSelected(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: _outline),
          left: BorderSide(color: _outline),
          right: BorderSide(color: _outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Handle bar.
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 14),

            // Sheet Header.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune, color: _accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notification Preferences',
                          style: TextStyle(
                            color: _foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Customize what alerts you receive',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_saving)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(_accent),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.close, color: _muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),

            Divider(color: _outline, height: 24),

            // Content List.
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_accent),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      children: [
                        _sectionTitle('CHANNELS & CATEGORIES'),
                        const SizedBox(height: 8),

                        _toggleCard(
                          icon: Icons.alarm,
                          title: 'Alarm Notifications',
                          subtitle: 'Alerts, wake-up calls and custom sounds',
                          value: _prefs.alarmNotificationsEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(alarmNotificationsEnabled: val),
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _toggleCard(
                          icon: Icons.check_circle_outline,
                          title: 'Task Reminders',
                          subtitle: 'Daily to-dos and scheduled item reminders',
                          value: _prefs.taskRemindersEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(taskRemindersEnabled: val),
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _toggleCard(
                          icon: Icons.flag_outlined,
                          title: 'Goal Reminders',
                          subtitle:
                              'Milestones, progress checks and target dates',
                          value: _prefs.goalRemindersEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(goalRemindersEnabled: val),
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _toggleCard(
                          icon: Icons.lightbulb_outline,
                          title: 'Daily Motivation',
                          subtitle: 'Daily quotes to boost your mindset',
                          value: _prefs.motivationEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(motivationEnabled: val),
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _toggleCard(
                          icon: Icons.campaign_outlined,
                          title: 'App Announcements',
                          subtitle: 'Feature updates, tips and announcements',
                          value: _prefs.announcementsEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(announcementsEnabled: val),
                            );
                          },
                        ),

                        const SizedBox(height: 22),

                        _sectionTitle('SOUND & VIBRATION'),
                        const SizedBox(height: 8),

                        _toggleCard(
                          icon: Icons.volume_up_outlined,
                          title: 'Sound Alert',
                          subtitle:
                              'Play audio for notifications and reminders',
                          value: _prefs.soundEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(soundEnabled: val),
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _toggleCard(
                          icon: Icons.vibration,
                          title: 'Vibration Alert',
                          subtitle: 'Haptic feedback on incoming alerts',
                          value: _prefs.vibrationEnabled,
                          onChanged: (val) {
                            _updatePreferences(
                              _prefs.copyWith(vibrationEnabled: val),
                            );
                          },
                        ),

                        const SizedBox(height: 22),

                        _sectionTitle('TIMING PREFERENCES'),
                        const SizedBox(height: 8),

                        _timeTile(
                          icon: Icons.wb_sunny_outlined,
                          title: 'Daily Motivation Time',
                          subtitle: 'When your morning motivation arrives',
                          time: _prefs.motivationTime,
                          onTap: () {
                            _pickTime(
                              context: context,
                              currentTime: _prefs.motivationTime,
                              onSelected: (val) {
                                _updatePreferences(
                                  _prefs.copyWith(motivationTime: val),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        _timeTile(
                          icon: Icons.assignment_outlined,
                          title: 'Daily Task Review Time',
                          subtitle: 'Daily reminder to check your to-do list',
                          time: _prefs.taskReminderTime,
                          onTap: () {
                            _pickTime(
                              context: context,
                              currentTime: _prefs.taskReminderTime,
                              onSelected: (val) {
                                _updatePreferences(
                                  _prefs.copyWith(taskReminderTime: val),
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _toggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? _accent.withValues(alpha: 0.3) : _outline,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: value
                ? _accent.withValues(alpha: 0.15)
                : _muted.withValues(alpha: 0.1),
            child: Icon(
              icon,
              size: 20,
              color: value ? _accent : _muted.withValues(alpha: 0.7),
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
                    color: _foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),

          Switch.adaptive(
            value: value,
            activeThumbColor: _accent,
            activeTrackColor: _accent.withValues(alpha: 0.4),
            inactiveThumbColor: _muted,
            inactiveTrackColor: _muted.withValues(alpha: 0.1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _timeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _muted.withValues(alpha: 0.1),
              child: Icon(icon, size: 20, color: _muted),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                time,
                style: TextStyle(
                  color: _foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
