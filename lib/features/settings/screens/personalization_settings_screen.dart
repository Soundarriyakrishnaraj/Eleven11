import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/settings_tile.dart';

class PersonalizationSettingsScreen extends StatefulWidget {
  const PersonalizationSettingsScreen({super.key});

  @override
  State<PersonalizationSettingsScreen> createState() =>
      _PersonalizationSettingsScreenState();
}

class _PersonalizationSettingsScreenState
    extends State<PersonalizationSettingsScreen> {
  String _startScreen = 'Dashboard';
  String _dateFormat = 'DD/MM/YYYY';
  bool _use24HourTime = false;
  String _startOfWeek = 'Monday';
  String _quoteCategory = 'Discipline';
  bool _hapticFeedback = true;
  bool _loading = true;

  static const List<String> _startScreenOptions = [
    'Dashboard',
    'Motivation',
    'Daily To-do',
    'Goals',
  ];

  static const List<String> _dateFormatOptions = [
    'DD/MM/YYYY',
    'MM/DD/YYYY',
    'YYYY-MM-DD',
  ];

  static const List<String> _startOfWeekOptions = ['Monday', 'Sunday'];

  static const List<String> _quoteCategoryOptions = [
    'Discipline',
    'Mindset',
    'Focus',
    'Resilience',
    'All Categories',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _startScreen = prefs.getString('pref_start_screen') ?? 'Dashboard';
      _dateFormat = prefs.getString('pref_date_format') ?? 'DD/MM/YYYY';
      _use24HourTime = prefs.getBool('pref_24_hour_time') ?? false;
      _startOfWeek = prefs.getString('pref_start_of_week') ?? 'Monday';
      _quoteCategory = prefs.getString('pref_quote_category') ?? 'Discipline';
      _hapticFeedback = prefs.getBool('pref_haptic_feedback') ?? true;
      _loading = false;
    });
  }

  Future<void> _updateString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _updateBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pref_start_screen');
    await prefs.remove('pref_date_format');
    await prefs.remove('pref_24_hour_time');
    await prefs.remove('pref_start_of_week');
    await prefs.remove('pref_quote_category');
    await prefs.remove('pref_haptic_feedback');

    if (!mounted) return;
    setState(() {
      _startScreen = 'Dashboard';
      _dateFormat = 'DD/MM/YYYY';
      _use24HourTime = false;
      _startOfWeek = 'Monday';
      _quoteCategory = 'Discipline';
      _hapticFeedback = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Personalization reset to defaults.'),
        duration: Duration(seconds: 1),
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
          'PERSONALIZATION',
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
                // APP BEHAVIOR
                const SettingsSectionHeader('APP BEHAVIOUR'),
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
                            Icons.home_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Default Landing Screen',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _startScreen,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: DropdownButton<String>(
                          value: _startScreen,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _startScreenOptions.map((s) {
                            return DropdownMenuItem(value: s, child: Text(s));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _startScreen = val);
                              _updateString('pref_start_screen', val);
                            }
                          },
                        ),
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
                            Icons.touch_app_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Haptic Feedback',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Vibration response on button taps and sliders',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _hapticFeedback,
                        onChanged: (val) {
                          setState(() => _hapticFeedback = val);
                          _updateBool('pref_haptic_feedback', val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // DATE & TIME
                const SettingsSectionHeader('DATE & TIME FORMAT'),
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
                            Icons.calendar_month_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Date Format',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _dateFormat,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: DropdownButton<String>(
                          value: _dateFormat,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _dateFormatOptions.map((f) {
                            return DropdownMenuItem(value: f, child: Text(f));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _dateFormat = val);
                              _updateString('pref_date_format', val);
                            }
                          },
                        ),
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
                            Icons.access_time_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          '24-Hour Time Format',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _use24HourTime
                              ? 'Example: 23:11'
                              : 'Example: 11:11 PM',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: _use24HourTime,
                        onChanged: (val) {
                          setState(() => _use24HourTime = val);
                          _updateBool('pref_24_hour_time', val);
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
                            Icons.view_week_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'First Day of the Week',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _startOfWeek,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: DropdownButton<String>(
                          value: _startOfWeek,
                          underline: const SizedBox(),
                          dropdownColor: cardColor,
                          items: _startOfWeekOptions.map((w) {
                            return DropdownMenuItem(value: w, child: Text(w));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _startOfWeek = val);
                              _updateString('pref_start_of_week', val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // MOTIVATION CONTENT
                const SettingsSectionHeader('MOTIVATION PREFERENCES'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
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
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preferred Focus Theme',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Primary topic for morning quotes',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<String>(
                        value: _quoteCategory,
                        underline: const SizedBox(),
                        dropdownColor: cardColor,
                        items: _quoteCategoryOptions.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: c == _quoteCategory ? accent : null,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _quoteCategory = val);
                            _updateString('pref_quote_category', val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // RESET BUTTON
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _resetToDefaults,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text(
                      'RESET PERSONALIZATION',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}
