import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notifications/models/notification_preferences_model.dart';
import '../../notifications/notification_service.dart';
import '../widgets/settings_tile.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _service = NotificationService.instance;

  NotificationPreferences _prefs = const NotificationPreferences();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await _service.fetchPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save(NotificationPreferences updated) async {
    setState(() {
      _prefs = updated;
      _saving = true;
    });

    try {
      await _service.savePreferences(updated);

      // Also persist to SharedPreferences for fast synchronous checks in alarm/notification channels
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('notifications_master_enabled', updated.pushEnabled);
      await sp.setBool('alarm_sound_enabled', updated.soundEnabled);
      await sp.setBool('alarm_vibration_enabled', updated.vibrationEnabled);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification preferences saved.'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save preferences: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          'NOTIFICATIONS',
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
                // MASTER NOTIFICATIONS SWITCH
                _buildMasterSwitchCard(cardColor, borderColor, accent),
                const SizedBox(height: 24),

                // NOTIFICATION CATEGORIES
                const SettingsSectionHeader('CHANNELS & CATEGORIES'),
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
                            Icons.alarm_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Alarm Notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Full-screen alarms and scheduled alerts',
                          style: TextStyle(fontSize: 12),
                        ),
                        value:
                            _prefs.pushEnabled &&
                            _prefs.alarmNotificationsEnabled,
                        onChanged: _prefs.pushEnabled
                            ? (val) => _save(
                                _prefs.copyWith(alarmNotificationsEnabled: val),
                              )
                            : null,
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
                            Icons.checklist_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Task Reminders',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Scheduled to-do and daily checklist nudges',
                          style: TextStyle(fontSize: 12),
                        ),
                        value:
                            _prefs.pushEnabled && _prefs.taskRemindersEnabled,
                        onChanged: _prefs.pushEnabled
                            ? (val) => _save(
                                _prefs.copyWith(taskRemindersEnabled: val),
                              )
                            : null,
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
                            Icons.flag_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Goal Milestones',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Progress updates and milestone check-ins',
                          style: TextStyle(fontSize: 12),
                        ),
                        value:
                            _prefs.pushEnabled && _prefs.goalRemindersEnabled,
                        onChanged: _prefs.pushEnabled
                            ? (val) => _save(
                                _prefs.copyWith(goalRemindersEnabled: val),
                              )
                            : null,
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
                            Icons.format_quote_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Daily Motivation',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Morning quotes and discipline reminders',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _prefs.pushEnabled && _prefs.motivationEnabled,
                        onChanged: _prefs.pushEnabled
                            ? (val) =>
                                  _save(_prefs.copyWith(motivationEnabled: val))
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // SOUND & VIBRATION
                const SettingsSectionHeader('SOUND & FEEDBACK'),
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
                            Icons.volume_up_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Sound',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Play audio for alarms and incoming notifications',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _prefs.soundEnabled,
                        onChanged: (val) =>
                            _save(_prefs.copyWith(soundEnabled: val)),
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
                            Icons.vibration_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Vibration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Vibrate device when alarms or reminders trigger',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _prefs.vibrationEnabled,
                        onChanged: (val) =>
                            _save(_prefs.copyWith(vibrationEnabled: val)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_saving)
                  Center(
                    child: CircularProgressIndicator(
                      color: accent,
                      strokeWidth: 2,
                    ),
                  ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _buildMasterSwitchCard(
    Color cardColor,
    Color borderColor,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _prefs.pushEnabled
              ? accent.withValues(alpha: 0.45)
              : borderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _prefs.pushEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Master Notifications',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  _prefs.pushEnabled
                      ? 'All notifications are active'
                      : 'All notifications are silenced',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _prefs.pushEnabled,
            activeTrackColor: accent,
            onChanged: (val) => _save(_prefs.copyWith(pushEnabled: val)),
          ),
        ],
      ),
    );
  }
}
