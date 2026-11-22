import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/alarm_schedule_service.dart';
import 'alarm_audio_service.dart';

class AlarmRemindersScreen extends StatefulWidget {
  const AlarmRemindersScreen({super.key});

  @override
  State<AlarmRemindersScreen> createState() => _AlarmRemindersScreenState();
}

class _AlarmRemindersScreenState extends State<AlarmRemindersScreen> {
  final _service = AlarmScheduleService.instance;
  final _audioService = AlarmAudioService.instance;

  List<AlarmSchedule> _alarms = [];
  bool _loading = true;
  String? _currentlyPreviewingUri;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  static const List<String> _dayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  @override
  void dispose() {
    _audioService.stopPreview();
    super.dispose();
  }

  Future<void> _loadAlarms() async {
    final userId = _userId;

    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await _service.initialize();
      await _service.restoreAlarms(userId);

      final alarms = await _service.getAlarms(userId);

      if (!mounted) return;

      setState(() {
        _alarms = alarms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load alarms: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _previewSound(String? uri) async {
    if (uri == null || uri.isEmpty) {
      _showMessage('Default sound uses your device alarm ringtone.');
      return;
    }

    if (_currentlyPreviewingUri == uri) {
      await _audioService.stopPreview();
      if (mounted) {
        setState(() => _currentlyPreviewingUri = null);
      }
      return;
    }

    try {
      setState(() => _currentlyPreviewingUri = uri);
      await _audioService.previewAudio(uri);
    } catch (e) {
      if (mounted) {
        setState(() => _currentlyPreviewingUri = null);
      }
      _showMessage('Could not preview audio: $e');
    }
  }

  Future<void> _stopPreview() async {
    await _audioService.stopPreview();
    if (mounted) {
      setState(() => _currentlyPreviewingUri = null);
    }
  }

  Future<void> _addAlarm() async {
    await _editAlarm();
  }

  Future<void> _editAlarm([AlarmSchedule? existing]) async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('Please sign in to manage alarms.');
      return;
    }

    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );

    TimeOfDay selectedTime = existing == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: existing.hour, minute: existing.minute);

    List<int> selectedDays = List<int>.from(
      existing?.weekdays ?? [1, 2, 3, 4, 5, 6, 7],
    );

    bool vibrationEnabled = existing?.vibrationEnabled ?? true;
    bool soundEnabled = existing?.soundEnabled ?? true;
    String? soundUri = existing?.soundUri;
    String soundName =
        existing?.soundName ?? AlarmAudioService.getSoundDisplayName(soundUri);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'New alarm' : 'Edit alarm',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Alarm title',
                        hintText: 'Morning routine',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Alarm time'),
                        subtitle: Text(selectedTime.format(context)),
                        trailing: const Icon(Icons.edit),
                        onTap: () async {
                          final result = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );

                          if (result != null) {
                            setSheetState(() => selectedTime = result);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Repeat',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        final selected = selectedDays.contains(day);

                        return FilterChip(
                          label: Text(_dayNames[index]),
                          selected: selected,
                          onSelected: (value) {
                            setSheetState(() {
                              if (value) {
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                              selectedDays.sort();
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sound'),
                      subtitle: const Text('Play an alarm sound'),
                      value: soundEnabled,
                      onChanged: (value) {
                        setSheetState(() {
                          soundEnabled = value;
                          if (!value) {
                            _stopPreview();
                          }
                        });
                      },
                    ),
                    if (soundEnabled) ...[
                      Card(
                        margin: const EdgeInsets.only(top: 4, bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.music_note),
                          title: const Text('Alarm sound'),
                          subtitle: Text(soundName),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _currentlyPreviewingUri == soundUri &&
                                          soundUri != null
                                      ? Icons.stop_circle_outlined
                                      : Icons.play_circle_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'Preview sound',
                                onPressed: soundUri == null
                                    ? null
                                    : () async {
                                        await _previewSound(soundUri);
                                        setSheetState(() {});
                                      },
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            await _showSoundPickerSheet(
                              currentUri: soundUri,
                              onSelected: (newUri, newName) {
                                setSheetState(() {
                                  soundUri = newUri;
                                  soundName = newName;
                                });
                              },
                            );
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vibration'),
                      subtitle: const Text('Vibrate when the alarm rings'),
                      value: vibrationEnabled,
                      onChanged: (value) {
                        setSheetState(() => vibrationEnabled = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final title = titleController.text.trim();

                          if (title.isEmpty) {
                            _showMessage('Enter an alarm title.');
                            return;
                          }

                          if (selectedDays.isEmpty) {
                            _showMessage('Select at least one repeat day.');
                            return;
                          }

                          await _stopPreview();

                          try {
                            if (existing == null) {
                              await _service.createAlarm(
                                userId: userId,
                                title: title,
                                description: descriptionController.text.trim(),
                                hour: selectedTime.hour,
                                minute: selectedTime.minute,
                                weekdays: selectedDays,
                                vibrationEnabled: vibrationEnabled,
                                soundEnabled: soundEnabled,
                                soundUri: soundUri,
                                soundName: soundName,
                              );
                            } else {
                              await _service.updateAlarm(
                                existing.copyWith(
                                  title: title,
                                  description: descriptionController.text
                                      .trim(),
                                  hour: selectedTime.hour,
                                  minute: selectedTime.minute,
                                  weekdays: selectedDays,
                                  vibrationEnabled: vibrationEnabled,
                                  soundEnabled: soundEnabled,
                                  soundUri: soundUri,
                                  soundName: soundName,
                                ),
                              );
                            }

                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);

                            await _loadAlarms();
                            _showMessage('Alarm saved.');
                          } catch (e) {
                            _showMessage('Could not save alarm: $e');
                          }
                        },
                        child: const Text('Save alarm'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await _stopPreview();
    titleController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showSoundPickerSheet({
    required String? currentUri,
    required void Function(String? uri, String name) onSelected,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (pickerContext) {
        String? activeUri = currentUri;

        return StatefulBuilder(
          builder: (context, setPickerState) {
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  children: [
                    Text(
                      'Select alarm sound',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.phone_android),
                      title: const Text('Choose audio from phone'),
                      subtitle: const Text('Pick any audio file from your device'),
                      trailing: const Icon(Icons.folder_open),
                      onTap: () async {
                        try {
                          final result = await _audioService.pickAudio();
                          if (result != null && result['uri'] != null) {
                            final uri = result['uri']!;
                            final name = result['name'] ?? 'Custom audio';
                            await _stopPreview();
                            onSelected(uri, name);
                            if (pickerContext.mounted) {
                              Navigator.pop(pickerContext);
                            }
                          }
                        } catch (e) {
                          _showMessage('Error selecting audio: $e');
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.notifications_active),
                      title: const Text('Default system sound'),
                      subtitle: const Text('Use standard alarm ringtone'),
                      trailing: activeUri == null
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () async {
                        await _stopPreview();
                        onSelected(null, 'Default alarm sound');
                        if (pickerContext.mounted) {
                          Navigator.pop(pickerContext);
                        }
                      },
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                      child: Text(
                        'BUILT-IN ALARM SOUNDS',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                      ),
                    ),
                    ...AlarmAudioService.builtInSounds.map((sound) {
                      final soundUriString = 'builtin:${sound.id}';
                      final isSelected = activeUri == soundUriString;
                      final isPlaying =
                          _currentlyPreviewingUri == soundUriString;

                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.music_note,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(sound.name),
                        subtitle: Text(sound.description),
                        trailing: IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          tooltip: isPlaying ? 'Stop preview' : 'Play preview',
                          onPressed: () async {
                            await _previewSound(soundUriString);
                            setPickerState(() {});
                          },
                        ),
                        onTap: () async {
                          await _stopPreview();
                          setPickerState(() => activeUri = soundUriString);
                          onSelected(soundUriString, sound.name);
                          if (pickerContext.mounted) {
                            Navigator.pop(pickerContext);
                          }
                        },
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await _stopPreview();
  }

  Future<void> _toggleAlarm(AlarmSchedule alarm, bool enabled) async {
    try {
      await _service.setAlarmEnabled(alarm, enabled);
      await _loadAlarms();
    } catch (e) {
      _showMessage('Could not update alarm: $e');
    }
  }

  Future<void> _deleteAlarm(AlarmSchedule alarm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text('Delete "${alarm.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteAlarm(alarm);
      await _loadAlarms();
      _showMessage('Alarm deleted.');
    } catch (e) {
      _showMessage('Could not delete alarm: $e');
    }
  }

  String _formatDays(List<int> days) {
    if (days.length == 7) return 'Every day';

    if (days.length == 5 &&
        days.contains(1) &&
        days.contains(2) &&
        days.contains(3) &&
        days.contains(4) &&
        days.contains(5)) {
      return 'Weekdays';
    }

    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return 'Weekends';
    }

    return days.map((day) => _dayNames[day - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarms & Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAlarm,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add alarm'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userId == null
          ? const Center(child: Text('Please sign in to manage your alarms.'))
          : _alarms.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _loadAlarms,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: _alarms.length,
                itemBuilder: (context, index) {
                  final alarm = _alarms[index];
                  final soundDisplay = alarm.soundEnabled
                      ? (alarm.soundName ??
                          AlarmAudioService.getSoundDisplayName(alarm.soundUri))
                      : 'Muted';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                child: Icon(
                                  alarm.taskId == null
                                      ? Icons.alarm
                                      : Icons.task_alt,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alarm.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      _formatDays(alarm.weekdays),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: alarm.enabled,
                                onChanged: (value) =>
                                    _toggleAlarm(alarm, value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                TimeOfDay(
                                  hour: alarm.hour,
                                  minute: alarm.minute,
                                ).format(context),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Edit alarm',
                                onPressed: () => _editAlarm(alarm),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete alarm',
                                onPressed: () => _deleteAlarm(alarm),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                alarm.soundEnabled
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                size: 18,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  soundDisplay,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                alarm.vibrationEnabled
                                    ? Icons.vibration
                                    : Icons.mobile_off,
                                size: 18,
                              ),
                              const SizedBox(width: 5),
                              const Text('Vibration'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alarm, size: 64),
            const SizedBox(height: 16),
            Text(
              'No alarms yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create reminders for your routines and daily tasks.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addAlarm,
              icon: const Icon(Icons.add),
              label: const Text('Create your first alarm'),
            ),
          ],
        ),
      ),
    );
  }
}
