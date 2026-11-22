import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/settings_tile.dart';

class FocusSettingsScreen extends StatefulWidget {
  const FocusSettingsScreen({super.key});

  @override
  State<FocusSettingsScreen> createState() => _FocusSettingsScreenState();
}

class _FocusSettingsScreenState extends State<FocusSettingsScreen> {
  int _focusDuration = 25;
  int _shortBreak = 5;
  int _longBreak = 15;
  int _longBreakInterval = 4;
  bool _autoStartBreaks = false;
  bool _autoStartNextFocus = false;
  bool _sessionNotifications = true;
  bool _soundAlert = true;
  bool _loading = true;

  static const List<int> _focusOptions = [15, 20, 25, 30, 45, 60, 90];
  static const List<int> _shortBreakOptions = [3, 5, 10, 15];
  static const List<int> _longBreakOptions = [10, 15, 20, 30];
  static const List<int> _intervalOptions = [2, 3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
    _loadFocusSettings();
  }

  Future<void> _loadFocusSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _focusDuration = prefs.getInt('focus_duration_minutes') ?? 25;
      _shortBreak = prefs.getInt('focus_short_break_minutes') ?? 5;
      _longBreak = prefs.getInt('focus_long_break_minutes') ?? 15;
      _longBreakInterval = prefs.getInt('focus_long_break_interval') ?? 4;
      _autoStartBreaks = prefs.getBool('focus_auto_start_breaks') ?? false;
      _autoStartNextFocus =
          prefs.getBool('focus_auto_start_next_session') ?? false;
      _sessionNotifications =
          prefs.getBool('focus_session_notifications') ?? true;
      _soundAlert = prefs.getBool('focus_sound_alert') ?? true;
      _loading = false;
    });
  }

  Future<void> _setInt(String key, int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, val);
  }

  Future<void> _setBool(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
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
          'FOCUS & PRODUCTIVITY',
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
                // TIMER DURATIONS
                const SettingsSectionHeader('INTERVAL DURATIONS'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.timer_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Focus Duration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Standard deep work block',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: DropdownButton<int>(
                          value: _focusDuration,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _focusOptions.map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(
                                '$m min',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: m == _focusDuration ? accent : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _focusDuration = val);
                              _setInt('focus_duration_minutes', val);
                            }
                          },
                        ),
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
                            Icons.coffee_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Short Break Duration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Rest period between focus sessions',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: DropdownButton<int>(
                          value: _shortBreak,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _shortBreakOptions.map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(
                                '$m min',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: m == _shortBreak ? accent : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _shortBreak = val);
                              _setInt('focus_short_break_minutes', val);
                            }
                          },
                        ),
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
                            Icons.self_improvement_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Long Break Duration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Extended rest period',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: DropdownButton<int>(
                          value: _longBreak,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _longBreakOptions.map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(
                                '$m min',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: m == _longBreak ? accent : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _longBreak = val);
                              _setInt('focus_long_break_minutes', val);
                            }
                          },
                        ),
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
                            Icons.repeat_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Long Break Interval',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Sessions before trigger',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: DropdownButton<int>(
                          value: _longBreakInterval,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _intervalOptions.map((i) {
                            return DropdownMenuItem(
                              value: i,
                              child: Text(
                                '$i sessions',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: i == _longBreakInterval
                                      ? accent
                                      : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _longBreakInterval = val);
                              _setInt('focus_long_break_interval', val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // AUTOMATION
                const SettingsSectionHeader('AUTOMATION & FLOW'),
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
                            Icons.play_arrow_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Auto-start Breaks',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Immediately begin rest timer after focus completion',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _autoStartBreaks,
                        onChanged: (val) {
                          setState(() => _autoStartBreaks = val);
                          _setBool('focus_auto_start_breaks', val);
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
                            Icons.fast_forward_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Auto-start Next Session',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Seamlessly start next focus block after break finishes',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _autoStartNextFocus,
                        onChanged: (val) {
                          setState(() => _autoStartNextFocus = val);
                          _setBool('focus_auto_start_next_session', val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ALERTS
                const SettingsSectionHeader('ALERTS & NOTIFICATIONS'),
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
                            Icons.notifications_active_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Session Notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Show background notifications when intervals complete',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _sessionNotifications,
                        onChanged: (val) {
                          setState(() => _sessionNotifications = val);
                          _setBool('focus_session_notifications', val);
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
                            Icons.volume_up_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Chime on Completion',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Play audio alert when interval timer completes',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _soundAlert,
                        onChanged: (val) {
                          setState(() => _soundAlert = val);
                          _setBool('focus_sound_alert', val);
                        },
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
