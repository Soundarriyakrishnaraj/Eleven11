import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:eleven11/features/alarms/screens/alarm_audio_service.dart';
import 'package:eleven11/features/notifications/notification_service.dart';

import '../../core/providers/theme_provider.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Color get orange => Theme.of(context).colorScheme.primary;
  Color get background => Theme.of(context).scaffoldBackgroundColor;
  Color get card => Theme.of(context).colorScheme.surface;

  int currentStep = 0;

  bool saving = false;
  bool loadingPreferences = true;
  bool loadingAudio = false;

  String? loadingError;

  String dailyAlarmSoundName = 'Default alarm sound';

  final Map<int, Set<String>> selected = {0: {}, 1: {}, 2: {}, 3: {}};

  final Set<String> selectedCategoryIds = {};
  final Set<String> selectedAuthorIds = {};

  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> authors = [];

  final Map<int, TextEditingController> otherAnswers = {
    0: TextEditingController(),
    1: TextEditingController(),
    2: TextEditingController(),
    3: TextEditingController(),
  };

  TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);

  bool todayTaskReminderEnabled = false;

  TimeOfDay todayTaskReminderTime = const TimeOfDay(hour: 13, minute: 0);

  final List<String> questions = [
    'What brings you to Eleven11?',
    'What motivates you the most?',
    'What are your biggest challenges?',
    'How would you describe your daily routine?',
    'Choose your motivation categories',
    'Choose your favourite authors',
    'When should your daily Eleven11 alarm ring?',
    'Would you like a task reminder today?',
    'Choose your alarm sound',
  ];

  final List<String> descriptions = [
    'Choose what you want to improve.',
    'Select the things that inspire you.',
    'Tell us what holds you back.',
    'Help us understand your daily habits.',
    'Select the topics you want daily quotes about.',
    'Choose authors whose words inspire you. This step is optional.',
    'Choose your compulsory daily alarm time. You can change it later.',
    'This reminder is optional and will run only today.',
    'Choose a sound that motivates you to start your day.',
  ];

  final List<List<String>> options = [
    [
      '🎯 Achieve my goals',
      '🔥 Build discipline',
      '⏰ Manage my time',
      '🌱 Personal growth',
    ],
    [
      '🏆 Success and achievement',
      '👨‍👩‍👧 Family and loved ones',
      '💪 Self-improvement',
      '✨ A better future',
    ],
    [
      '📱 Distractions',
      '😴 Lack of consistency',
      '🤔 Procrastination',
      '⚡ Lack of motivation',
    ],
    [
      '🌅 Early morning person',
      '☀️ Productive in the afternoon',
      '🌙 Night owl',
      '🔄 My routine changes daily',
    ],
  ];

  final List<TimeOfDay> suggestedTimes = [
    const TimeOfDay(hour: 7, minute: 0),
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 20, minute: 0),
  ];

  @override
  void initState() {
    super.initState();
    loadPreferences();
  }

  @override
  void dispose() {
    for (final controller in otherAnswers.values) {
      controller.dispose();
    }

    AlarmAudioService.instance.stopPreview();

    super.dispose();
  }

  Future<void> loadPreferences() async {
    try {
      final client = Supabase.instance.client;

      final categoryRows = await client
          .from('motivation_categories')
          .select('id, name')
          .eq('is_active', true)
          .order('name');

      final authorRows = await client
          .from('authors')
          .select('id, name')
          .order('name');

      categories = List<Map<String, dynamic>>.from(categoryRows);
      authors = List<Map<String, dynamic>>.from(authorRows);

      final user = client.auth.currentUser;

      if (user != null) {
        final savedCategories = await client
            .from('user_selected_categories')
            .select('category_id')
            .eq('user_id', user.id);

        final savedAuthors = await client
            .from('user_selected_authors')
            .select('author_id')
            .eq('user_id', user.id);

        selectedCategoryIds.addAll(
          savedCategories.map((e) => e['category_id'].toString()),
        );

        selectedAuthorIds.addAll(
          savedAuthors.map((e) => e['author_id'].toString()),
        );
      }

      try {
        final savedSound = await AlarmAudioService.instance.getAudioName(
          'daily',
        );

        if (savedSound != null && savedSound.isNotEmpty) {
          dailyAlarmSoundName = savedSound;
        }
      } catch (_) {
        // Keep the default sound name.
      }
    } catch (e) {
      loadingError = e.toString();
      debugPrint('ONBOARDING LOAD ERROR: $e');
    } finally {
      if (mounted) {
        setState(() => loadingPreferences = false);
      }
    }
  }

  Future<void> chooseCustomTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );

    if (time != null && mounted) {
      setState(() => selectedTime = time);
    }
  }

  Future<void> chooseTaskReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: todayTaskReminderTime,
    );

    if (time != null && mounted) {
      setState(() => todayTaskReminderTime = time);
    }
  }

  Future<void> chooseAlarmSound() async {
    if (loadingAudio) return;

    setState(() => loadingAudio = true);

    try {
      final result = await AlarmAudioService.instance.pickAudio();

      if (result == null) return;

      final uri = result['uri'] ?? '';

      if (uri.isEmpty) return;

      final name = result['name'] ?? 'Selected audio';

      await AlarmAudioService.instance.saveAudio(
        type: 'daily',
        uri: uri,
        name: name,
      );

      if (!mounted) return;

      setState(() => dailyAlarmSoundName = name);

      _message('Alarm sound saved successfully.');
    } catch (e) {
      _message('Could not select alarm sound: $e');
    } finally {
      if (mounted) {
        setState(() => loadingAudio = false);
      }
    }
  }

  Future<void> selectBuiltinAlarmSound(String soundId) async {
    try {
      await AlarmAudioService.instance.selectBuiltinSound(
        type: 'daily',
        soundId: soundId,
      );

      final name = await AlarmAudioService.instance.getAudioName('daily');

      if (!mounted) return;

      setState(() {
        dailyAlarmSoundName = name ?? 'Default alarm sound';
      });

      _message('Alarm sound selected: $dailyAlarmSoundName');
    } catch (e) {
      _message('Could not select alarm sound: $e');
    }
  }

  Future<void> previewAlarmSound() async {
    try {
      final uri = await AlarmAudioService.instance.getAudioUri('daily');

      if (uri == null || uri.isEmpty) {
        _message('Please select an alarm sound first.');
        return;
      }

      await AlarmAudioService.instance.previewAudio(uri);
    } catch (e) {
      _message('Could not play preview: $e');
    }
  }

  Future<void> stopAlarmPreview() async {
    try {
      await AlarmAudioService.instance.stopPreview();
    } catch (_) {}
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime _todayAt(TimeOfDay time) {
    final now = DateTime.now();

    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  // ============================================================
  // SAVE ONBOARDING
  // ============================================================

  Future<void> finishOnboarding() async {
    if (selectedCategoryIds.isEmpty) {
      _message('Please select at least one motivation category.');
      return;
    }

    final taskReminderDate = _todayAt(todayTaskReminderTime);

    if (todayTaskReminderEnabled && !taskReminderDate.isAfter(DateTime.now())) {
      _message('Please choose a task reminder time later than now.');
      return;
    }

    setState(() => saving = true);

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      debugPrint('========== ONBOARDING SAVE START ==========');
      debugPrint('ONBOARDING DEBUG: user ID = ${user.id}');
      debugPrint('ONBOARDING DEBUG: email = ${user.email}');

      final answers = <String, dynamic>{};

      for (int i = 0; i < 4; i++) {
        answers['question_${i + 1}'] = {
          'selected': selected[i]!.toList(),
          'other': otherAnswers[i]!.text.trim(),
        };
      }

      answers['today_task_reminder'] = {
        'enabled': todayTaskReminderEnabled,
        'scheduled_at': todayTaskReminderEnabled
            ? taskReminderDate.toIso8601String()
            : null,
        'repeat': 'none',
      };

      answers['daily_alarm_sound'] = dailyAlarmSoundName;

      final now = DateTime.now().toUtc().toIso8601String();

      // STEP 1: Save onboarding answers.
      debugPrint('ONBOARDING DEBUG: saving user_onboarding');

      await client.from('user_onboarding').upsert({
        'user_id': user.id,
        'answers': answers,
        'notification_time':
            '${selectedTime.hour.toString().padLeft(2, '0')}:'
            '${selectedTime.minute.toString().padLeft(2, '0')}:00',
        'completed_at': now,
        'updated_at': now,
      });

      debugPrint('ONBOARDING DEBUG: user_onboarding saved successfully');

      // STEP 2: Delete previous category selections.
      debugPrint('ONBOARDING DEBUG: deleting previous categories');

      await client
          .from('user_selected_categories')
          .delete()
          .eq('user_id', user.id);

      debugPrint('ONBOARDING DEBUG: previous categories deleted');

      // STEP 3: Insert selected categories.
      debugPrint('ONBOARDING DEBUG: inserting categories');

      await client
          .from('user_selected_categories')
          .insert(
            selectedCategoryIds
                .map((id) => {'user_id': user.id, 'category_id': id})
                .toList(),
          );

      debugPrint('ONBOARDING DEBUG: categories saved successfully');

      // STEP 4: Delete previous author selections.
      debugPrint('ONBOARDING DEBUG: deleting previous authors');

      await client
          .from('user_selected_authors')
          .delete()
          .eq('user_id', user.id);

      debugPrint('ONBOARDING DEBUG: previous authors deleted');

      // STEP 5: Insert selected authors.
      if (selectedAuthorIds.isNotEmpty) {
        debugPrint('ONBOARDING DEBUG: inserting authors');

        await client
            .from('user_selected_authors')
            .insert(
              selectedAuthorIds
                  .map((id) => {'user_id': user.id, 'author_id': id})
                  .toList(),
            );

        debugPrint('ONBOARDING DEBUG: authors saved successfully');
      } else {
        debugPrint('ONBOARDING DEBUG: no authors selected');
      }

      // STEP 6: Schedule daily alarm and optional today task reminder.
      debugPrint(
        'ONBOARDING DEBUG: scheduling daily alarm via NotificationService',
      );

      final alarmTimeString =
          '${selectedTime.hour.toString().padLeft(2, '0')}:'
          '${selectedTime.minute.toString().padLeft(2, '0')}';

      final taskReminderAtString = todayTaskReminderEnabled
          ? taskReminderDate.toIso8601String()
          : null;

      try {
        final scheduled = await NotificationService.instance
            .scheduleOnboardingAlarms(
              dailyAlarmTime: alarmTimeString,
              todayTaskReminderEnabled: todayTaskReminderEnabled,
              todayTaskReminderAt: taskReminderAtString,
            );

        if (!scheduled) {
          debugPrint(
            'ONBOARDING WARNING: Notification/exact alarm permission was not granted.',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Alarm permission not granted. You can enable Alarms & Reminders anytime in Android settings.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 6),
              ),
            );
          }
        } else {
          debugPrint('ONBOARDING DEBUG: daily alarm scheduled successfully');
        }
      } catch (alarmError) {
        debugPrint('ONBOARDING ALARM SCHEDULING ERROR: $alarmError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not schedule alarm: $alarmError. You can set it in Alarms & Reminders.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      debugPrint('========== ONBOARDING SAVE COMPLETE ==========');

      if (!mounted) return;

      await stopAlarmPreview();

      if (!mounted) return;

      widget.onCompleted();
    } catch (error, stackTrace) {
      debugPrint('========== ONBOARDING SAVE FAILED ==========');
      debugPrint('ONBOARDING ERROR: $error');
      debugPrint('ONBOARDING STACK TRACE: $stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save your answers: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  void continueStep() {
    if (currentStep == 4 && selectedCategoryIds.isEmpty) {
      _message('Please select at least one category.');
      return;
    }

    if (currentStep < 8) {
      setState(() => currentStep++);
    } else {
      finishOnboarding();
    }
  }

  void previousStep() {
    if (currentStep > 0) {
      setState(() => currentStep--);
    }
  }

  Widget choiceCard(String value) {
    final isSelected = selected[currentStep]!.contains(value);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          if (isSelected) {
            selected[currentStep]!.remove(value);
          } else {
            selected[currentStep]!.add(value);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? orange.withValues(alpha: 0.18) : card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? orange : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: orange, size: 20),
          ],
        ),
      ),
    );
  }

  Widget preferenceChips({
    required List<Map<String, dynamic>> items,
    required Set<String> selectedIds,
    required String idKey,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: items.map((item) {
        final id = item[idKey].toString();
        final name = item['name'].toString();
        final active = selectedIds.contains(id);

        return FilterChip(
          label: Text(name),
          selected: active,
          showCheckmark: true,
          selectedColor: orange.withValues(alpha: 0.18),
          backgroundColor: card,
          checkmarkColor: orange,
          labelStyle: TextStyle(
            color: active ? orange : Theme.of(context).colorScheme.onSurface,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: active ? orange : Theme.of(context).colorScheme.outline,
          ),
          onSelected: (value) {
            setState(() {
              if (value) {
                selectedIds.add(id);
              } else {
                selectedIds.remove(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget timeCard(TimeOfDay time) {
    final active =
        selectedTime.hour == time.hour && selectedTime.minute == time.minute;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => selectedTime = time),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: active ? orange.withValues(alpha: 0.18) : card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? orange : Theme.of(context).colorScheme.outline,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.alarm, color: orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                time.format(context),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
            ),
            if (active) Icon(Icons.check_circle, color: orange),
          ],
        ),
      ),
    );
  }

  Widget buildAlarmSoundStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: orange.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(Icons.music_note, color: orange, size: 48),
              const SizedBox(height: 12),
              const Text(
                'CHOOSE YOUR DAILY ALARM',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a built-in sound or use your own music.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.audiotrack, color: orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dailyAlarmSoundName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(Icons.check_circle, color: orange),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'BUILT-IN ALARM SOUNDS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        ...AlarmAudioService.builtInSounds.map((sound) {
          final isSelected = dailyAlarmSoundName == sound.name;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isSelected ? orange.withValues(alpha: 0.18) : card,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: isSelected
                    ? orange
                    : Theme.of(context).colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              onTap: () => selectBuiltinAlarmSound(sound.id),
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.music_note,
                color: orange,
              ),
              title: Text(
                sound.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                sound.description,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: isSelected
                  ? const Text(
                      'SELECTED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ),
          );
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: loadingAudio ? null : chooseAlarmSound,
            icon: loadingAudio
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.folder_open),
            label: Text(loadingAudio ? 'PLEASE WAIT...' : 'CHOOSE FROM PHONE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: previewAlarmSound,
                icon: const Icon(Icons.play_arrow),
                label: const Text('PREVIEW'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(color: orange),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: stopAlarmPreview,
                icon: const Icon(Icons.stop),
                label: const Text('STOP'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'You can change your alarm sound later in Alarm & Reminders settings.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget buildStepContent() {
    if (loadingPreferences) {
      return Center(child: CircularProgressIndicator(color: orange));
    }

    if (loadingError != null) {
      return Column(
        children: [
          Text(
            'Unable to load categories and authors:\n$loadingError',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                loadingError = null;
                loadingPreferences = true;
              });

              loadPreferences();
            },
            child: const Text('Retry'),
          ),
        ],
      );
    }

    if (currentStep < 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...options[currentStep].map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: choiceCard(option),
            ),
          ),
          const SizedBox(height: 10),
          const Text('OTHER', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: otherAnswers[currentStep],
            maxLines: 3,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Tell us in your own words...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      );
    }

    if (currentStep == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${selectedCategoryIds.length} categories selected'),
          const SizedBox(height: 16),
          preferenceChips(
            items: categories,
            selectedIds: selectedCategoryIds,
            idKey: 'id',
          ),
        ],
      );
    }

    if (currentStep == 5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${selectedAuthorIds.length} authors selected'),
          const SizedBox(height: 8),
          Text(
            'You can skip this step.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          preferenceChips(
            items: authors,
            selectedIds: selectedAuthorIds,
            idKey: 'id',
          ),
        ],
      );
    }

    if (currentStep == 6) {
      return Column(
        children: [
          ...suggestedTimes.map(
            (time) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: timeCard(time),
            ),
          ),
          OutlinedButton.icon(
            onPressed: chooseCustomTime,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Choose another time'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size(double.infinity, 52),
              side: BorderSide(color: orange),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Your daily alarm: ${selectedTime.format(context)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This alarm is part of your daily Eleven11 routine.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (currentStep == 7) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Enable today’s task reminder',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Optional · One time only · No daily repeat',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              activeThumbColor: orange,
              value: todayTaskReminderEnabled,
              onChanged: (value) {
                setState(() {
                  todayTaskReminderEnabled = value;
                });
              },
            ),
          ),
          if (todayTaskReminderEnabled) ...[
            const SizedBox(height: 20),
            const Text(
              'REMINDER TIME',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: chooseTaskReminderTime,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: orange, width: 2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, color: orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        todayTaskReminderTime.format(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(Icons.edit, color: orange),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'You can also set separate alarms for individual checklist tasks later.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You can skip this step and continue without a reminder.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return buildAlarmSoundStep();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ELEVEN11',
                    style: TextStyle(
                      color: kSignatureOrange,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    '${currentStep + 1} / 9',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: (currentStep + 1) / 9,
                  minHeight: 6,
                  backgroundColor: Theme.of(context).colorScheme.outline,
                  color: orange,
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STEP ${currentStep + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        questions[currentStep],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        descriptions[currentStep],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 26),
                      buildStepContent(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (currentStep > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : previousStep,
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          saving ||
                              loadingPreferences ||
                              loadingError != null ||
                              loadingAudio
                          ? null
                          : continueStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: orange,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                        minimumSize: const Size(0, 54),
                      ),
                      child: saving
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : Text(
                              currentStep == 8 ? 'Finish' : 'Continue',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'DISCIPLINE. FOCUS. ACHIEVE.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
