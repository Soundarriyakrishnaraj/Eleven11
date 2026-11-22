import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../alarms/screens/alarm_audio_service.dart';
import '../widgets/settings_tile.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  final AlarmAudioService _audioService = AlarmAudioService.instance;

  String _selectedSoundId = 'classic';
  int _snoozeMinutes = 5;
  bool _vibrationEnabled = true;
  bool _gradualVolume = false;
  double _volume = 0.8;

  String? _currentlyPlayingId;
  bool _loading = true;

  static const List<int> _snoozeOptions = [5, 10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    _loadAlarmSettings();
  }

  @override
  void dispose() {
    _audioService.stopPreview();
    super.dispose();
  }

  Future<void> _loadAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedUri =
        prefs.getString('alarm_default_audio_uri') ??
        prefs.getString('alarm_daily_audio_uri') ??
        'builtin:classic';

    String soundId = 'classic';
    if (savedUri.startsWith('builtin:')) {
      soundId = savedUri.substring('builtin:'.length).toLowerCase();
    }

    final snooze = prefs.getInt('alarm_snooze_interval_minutes') ?? 5;
    final vibration = prefs.getBool('alarm_vibration_enabled') ?? true;
    final gradual = prefs.getBool('alarm_gradual_volume') ?? false;
    final vol = prefs.getDouble('alarm_volume') ?? 0.8;

    if (!mounted) return;
    setState(() {
      _selectedSoundId = soundId;
      _snoozeMinutes = snooze;
      _vibrationEnabled = vibration;
      _gradualVolume = gradual;
      _volume = vol;
      _loading = false;
    });
  }

  Future<void> _selectSound(String id) async {
    await _audioService.stopPreview();
    setState(() {
      _selectedSoundId = id;
      _currentlyPlayingId = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final sound = AlarmAudioService.builtInSounds.firstWhere(
      (s) => s.id == id,
      orElse: () => AlarmAudioService.builtInSounds.first,
    );

    final uri = 'builtin:${sound.id}';
    await prefs.setString('alarm_default_audio_uri', uri);
    await prefs.setString('alarm_default_audio_name', sound.name);
    await prefs.setString('alarm_daily_audio_uri', uri);
    await prefs.setString('alarm_daily_audio_name', sound.name);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Default alarm sound set to ${sound.name}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _togglePreview(String soundId) async {
    if (_currentlyPlayingId == soundId) {
      await _audioService.stopPreview();
      if (!mounted) return;
      setState(() => _currentlyPlayingId = null);
    } else {
      setState(() => _currentlyPlayingId = soundId);
      try {
        await _audioService.previewAudio('builtin:$soundId');
      } catch (_) {
        if (!mounted) return;
        setState(() => _currentlyPlayingId = null);
      }
    }
  }

  Future<void> _setSnooze(int minutes) async {
    setState(() => _snoozeMinutes = minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarm_snooze_interval_minutes', minutes);
  }

  Future<void> _setVibration(bool value) async {
    setState(() => _vibrationEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_vibration_enabled', value);
  }

  Future<void> _setGradualVolume(bool value) async {
    setState(() => _gradualVolume = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_gradual_volume', value);
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('alarm_volume', value);
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
          'ALARM SETTINGS',
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
                // DEFAULT ALARM SOUND
                const SettingsSectionHeader('DEFAULT ALARM SOUND'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: AlarmAudioService.builtInSounds
                        .asMap()
                        .entries
                        .map((entry) {
                          final index = entry.key;
                          final sound = entry.value;
                          final isSelected = _selectedSoundId == sound.id;
                          final isPlaying = _currentlyPlayingId == sound.id;

                          return Column(
                            children: [
                              if (index > 0)
                                Divider(height: 1, color: borderColor),
                              ListTile(
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accent.withValues(alpha: 0.2)
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isSelected
                                        ? Icons.alarm_on_rounded
                                        : Icons.music_note_rounded,
                                    color: isSelected
                                        ? accent
                                        : theme.colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  sound.name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 14,
                                    color: isSelected ? accent : null,
                                  ),
                                ),
                                subtitle: Text(
                                  sound.description,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isPlaying
                                            ? Icons.stop_circle_rounded
                                            : Icons.play_circle_fill_rounded,
                                        color: isPlaying
                                            ? accent
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        size: 26,
                                      ),
                                      onPressed: () => _togglePreview(sound.id),
                                      tooltip: isPlaying
                                          ? 'Stop'
                                          : 'Preview sound',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        isSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: isSelected
                                            ? accent
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                      onPressed: () => _selectSound(sound.id),
                                    ),
                                  ],
                                ),
                                onTap: () => _selectSound(sound.id),
                              ),
                            ],
                          );
                        })
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // SNOOZE DURATION
                const SettingsSectionHeader('SNOOZE CONFIGURATION'),
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
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.snooze_rounded,
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
                              'Default Snooze Time',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Pause duration before repeating',
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
                      DropdownButton<int>(
                        value: _snoozeMinutes,
                        dropdownColor: cardColor,
                        underline: const SizedBox(),
                        icon: Icon(Icons.arrow_drop_down, color: accent),
                        items: _snoozeOptions.map((mins) {
                          return DropdownMenuItem<int>(
                            value: mins,
                            child: Text(
                              '$mins min',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mins == _snoozeMinutes ? accent : null,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _setSnooze(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // VOLUME & VIBRATION
                const SettingsSectionHeader('VOLUME & FEEDBACK'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      // Volume Slider
                      Row(
                        children: [
                          Icon(
                            _volume > 0
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: accent,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Alarm Volume',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_volume * 100).round()}%',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _volume,
                        activeColor: accent,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: _setVolume,
                      ),
                      Divider(height: 16, color: borderColor),

                      // Gradual Volume
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeTrackColor: accent,
                        title: const Text(
                          'Gradual Volume Increase',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Fade audio in over 30 seconds for a peaceful awakening',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _gradualVolume,
                        onChanged: _setGradualVolume,
                      ),
                      Divider(height: 16, color: borderColor),

                      // Vibration
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeTrackColor: accent,
                        title: const Text(
                          'Vibration Feedback',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Pulse device motor alongside audio alarm',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _vibrationEnabled,
                        onChanged: _setVibration,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
