import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/theme_provider.dart';
import '../services/alarm_schedule_service.dart';
import 'alarm_audio_service.dart';

class AlarmRingingScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const AlarmRingingScreen({super.key, required this.payload});

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> with SingleTickerProviderStateMixin {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  int _snoozeMinutes = 5;
  bool _isDismissing = false;
  late AnimationController _pulseController;

  String get _title => widget.payload['title']?.toString() ?? 'ALARM';
  String get _description => widget.payload['description']?.toString() ?? '';
  String? get _soundUri => widget.payload['soundUri']?.toString();
  int get _alarmId {
    final raw = widget.payload['alarmId'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultSnooze();
    _startClock();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Loop alarm sound continuously until user snoozes or dismisses
    AlarmAudioService.instance.playAlarmLoop(_soundUri);
  }

  Future<void> _loadDefaultSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _snoozeMinutes = prefs.getInt('alarm_snooze_interval_minutes') ?? 5;
      });
    }
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pulseController.dispose();
    AlarmAudioService.instance.stopPreview();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;
    await AlarmAudioService.instance.stopPreview();
    await AlarmScheduleService.instance.cancelSnoozeAlarm(_alarmId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _snooze() async {
    if (_isDismissing) return;
    _isDismissing = true;
    await AlarmAudioService.instance.stopPreview();
    await AlarmScheduleService.instance.scheduleSnoozeAlarm(
      alarmId: _alarmId,
      title: _title,
      description: _description,
      soundUri: _soundUri,
      snoozeMinutes: _snoozeMinutes,
      originalPayload: widget.payload,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _adjustSnooze(int delta) {
    setState(() {
      _snoozeMinutes = (_snoozeMinutes + delta).clamp(1, 60);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111111) : const Color(0xFFFBF9F5);
    final textColor = isDark ? Colors.white : const Color(0xFF1B1B1B);
    final hourStr = _currentTime.hour.toString().padLeft(2, '0');
    final minuteStr = _currentTime.minute.toString().padLeft(2, '0');
    final secondStr = _currentTime.second.toString().padLeft(2, '0');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top header
                Column(
                  children: [
                    Text(
                      'ELEVEN11',
                      style: TextStyle(
                        color: kSignatureOrange,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.92, end: 1.08).animate(_pulseController),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kSignatureOrange.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.alarm_on_rounded,
                          color: kSignatureOrange,
                          size: 56,
                        ),
                      ),
                    ),
                  ],
                ),

                // Center: Time display & Title
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$hourStr:$minuteStr',
                          style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -2,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          secondStr,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: kSignatureOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: textColor,
                      ),
                    ),
                    if (_description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),

                // Snooze adjustment (- and + options)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SNOOZE DURATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 26),
                            color: textColor,
                            onPressed: () => _adjustSnooze(-5),
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 48),
                            alignment: Alignment.center,
                            child: Text(
                              '$_snoozeMinutes M',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kSignatureOrange,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 26),
                            color: textColor,
                            onPressed: () => _adjustSnooze(5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bottom Action buttons: Snooze & Dismiss
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          side: BorderSide(color: theme.colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _snooze,
                        child: Text(
                          'SNOOZE ($_snoozeMinutes M)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kSignatureOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _dismiss,
                        child: const Text(
                          'DISMISS',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
