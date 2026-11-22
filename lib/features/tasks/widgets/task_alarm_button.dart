import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../alarms/services/alarm_schedule_service.dart';

class TaskAlarmButton extends StatefulWidget {
  const TaskAlarmButton({
    super.key,
    required this.taskId,
    required this.taskTitle,
  });

  final String taskId;
  final String taskTitle;

  /// Cancels and removes all reminders belonging to a deleted task.
  static Future<void> cancelTaskAlarm(String taskId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final service = AlarmScheduleService.instance;
    final alarms = await service.getAlarms(userId);

    final taskAlarms = alarms.where((alarm) => alarm.taskId == taskId).toList();

    for (final alarm in taskAlarms) {
      await service.deleteAlarm(alarm);
    }
  }

  @override
  State<TaskAlarmButton> createState() => _TaskAlarmButtonState();
}

class _TaskAlarmButtonState extends State<TaskAlarmButton> {
  final AlarmScheduleService _service = AlarmScheduleService.instance;

  bool _hasAlarm = false;
  bool _loading = true;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  static const List<String> _days = [
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
    _checkAlarm();
  }

  Future<void> _checkAlarm() async {
    final userId = _userId;

    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final alarms = await _service.getAlarms(userId);
      final found = alarms.any((alarm) => alarm.taskId == widget.taskId);

      if (!mounted) return;

      setState(() {
        _hasAlarm = found;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAlarmEditor() async {
    final userId = _userId;

    if (userId == null) {
      _message('Please sign in to set task reminders.');
      return;
    }

    try {
      await _service.initialize();

      if (!mounted) return;

      final alarms = await _service.getAlarms(userId);

      if (!mounted) return;

      AlarmSchedule? existing;
      for (final alarm in alarms) {
        if (alarm.taskId == widget.taskId) {
          existing = alarm;
          break;
        }
      }

      TimeOfDay selectedTime = existing == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: existing.hour, minute: existing.minute);

      List<int> selectedDays = List<int>.from(
        existing?.weekdays ?? [1, 2, 3, 4, 5, 6, 7],
      );

      bool vibration = existing?.vibrationEnabled ?? true;
      bool sound = existing?.soundEnabled ?? true;

      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(
                  existing == null ? 'Set task reminder' : 'Edit reminder',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.taskTitle),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time),
                        title: const Text('Reminder time'),
                        subtitle: Text(selectedTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );

                          if (picked != null) {
                            setDialogState(() {
                              selectedTime = picked;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Repeat on',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        children: List.generate(7, (index) {
                          final day = index + 1;

                          return FilterChip(
                            label: Text(_days[index]),
                            selected: selectedDays.contains(day),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
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
                        value: sound,
                        onChanged: (value) {
                          setDialogState(() => sound = value);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vibration'),
                        value: vibration,
                        onChanged: (value) {
                          setDialogState(() => vibration = value);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  if (existing != null)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: selectedDays.isEmpty
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted || result != true) return;

      final permitted = await _service.requestPermissions();

      if (!mounted) return;

      if (!permitted) {
        _message(
          'Please allow notifications and exact alarms in Android settings.',
        );
        return;
      }

      if (existing == null) {
        await _service.createAlarm(
          userId: userId,
          title: widget.taskTitle,
          description: 'Your scheduled task reminder',
          hour: selectedTime.hour,
          minute: selectedTime.minute,
          weekdays: selectedDays,
          vibrationEnabled: vibration,
          soundEnabled: sound,
          taskId: widget.taskId,
        );
      } else {
        await _service.updateAlarm(
          existing.copyWith(
            title: widget.taskTitle,
            hour: selectedTime.hour,
            minute: selectedTime.minute,
            weekdays: selectedDays,
            vibrationEnabled: vibration,
            soundEnabled: sound,
          ),
        );
      }

      if (!mounted) return;

      await _checkAlarm();

      if (!mounted) return;

      _message('Task reminder saved.');
    } catch (e) {
      if (!mounted) return;
      _message('Could not save task reminder: $e');
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _hasAlarm ? 'Edit task reminder' : 'Add task reminder',
      onPressed: _loading ? null : _openAlarmEditor,
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _hasAlarm ? Icons.alarm_on : Icons.alarm_add_outlined,
              color: _hasAlarm ? Theme.of(context).colorScheme.primary : null,
            ),
    );
  }
}
