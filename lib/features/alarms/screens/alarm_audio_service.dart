import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BuiltinAlarmSound {
  final String id;
  final String name;
  final String description;
  final List<double> notes;

  const BuiltinAlarmSound({
    required this.id,
    required this.name,
    required this.description,
    required this.notes,
  });
}

class AlarmAudioService {
  AlarmAudioService._();

  static final AlarmAudioService instance = AlarmAudioService._();

  static const MethodChannel _channel = MethodChannel(
    'com.eleven11/audio_picker',
  );

  final AudioPlayer _player = AudioPlayer();

  // Built-in alarm sounds
  static const List<BuiltinAlarmSound> builtInSounds = [
    BuiltinAlarmSound(
      id: 'classic',
      name: 'Classic Alarm',
      description: 'A clear repeating alarm melody',
      notes: [880, 0, 880, 0, 1046, 0, 880, 0],
    ),
    BuiltinAlarmSound(
      id: 'gentle',
      name: 'Gentle Rise',
      description: 'A soft peaceful wake-up melody',
      notes: [523, 659, 784, 659, 523, 659, 784, 1046],
    ),
    BuiltinAlarmSound(
      id: 'digital',
      name: 'Digital Beep',
      description: 'A sharp electronic alarm tone',
      notes: [1200, 0, 1200, 0, 1500, 0, 1200, 0],
    ),
    BuiltinAlarmSound(
      id: 'birds',
      name: 'Morning Birds',
      description: 'A nature-inspired melody',
      notes: [1568, 1760, 0, 1396, 1568, 0, 1760, 1976],
    ),
    BuiltinAlarmSound(
      id: 'piano',
      name: 'Soft Piano',
      description: 'A gentle musical sequence',
      notes: [523, 659, 784, 1046, 784, 659, 523, 659],
    ),
    BuiltinAlarmSound(
      id: 'chimes',
      name: 'Bell Chimes',
      description: 'A bright ringing melody',
      notes: [1046, 1318, 1568, 1318, 1046, 1568, 1760, 1568],
    ),
  ];

  // SharedPreferences keys
  static const String _dailyUriKey = 'alarm_daily_audio_uri';
  static const String _taskUriKey = 'alarm_task_audio_uri';
  static const String _goalUriKey = 'alarm_goal_audio_uri';

  static const String _dailyNameKey = 'alarm_daily_audio_name';
  static const String _taskNameKey = 'alarm_task_audio_name';
  static const String _goalNameKey = 'alarm_goal_audio_name';

  String _uriKey(String type) {
    switch (type) {
      case 'daily':
        return _dailyUriKey;
      case 'task':
        return _taskUriKey;
      case 'goal':
        return _goalUriKey;
      default:
        throw ArgumentError('Unknown alarm type: $type');
    }
  }

  String _nameKey(String type) {
    switch (type) {
      case 'daily':
        return _dailyNameKey;
      case 'task':
        return _taskNameKey;
      case 'goal':
        return _goalNameKey;
      default:
        throw ArgumentError('Unknown alarm type: $type');
    }
  }

  /// Resolves the proper Android NotificationSound object and a stable key
  /// for channel identification. Built-in sounds map to native raw resources
  /// while external songs map to persistable content URIs.
  static (AndroidNotificationSound?, String) resolveAndroidSound(
    String? soundUri,
    bool soundEnabled,
  ) {
    if (!soundEnabled || soundUri == null || soundUri.isEmpty) {
      return (null, 'default');
    }

    if (soundUri.startsWith('builtin:')) {
      final soundId = soundUri
          .substring('builtin:'.length)
          .toLowerCase()
          .trim();
      return (RawResourceAndroidNotificationSound(soundId), soundId);
    }

    if (soundUri.startsWith('content://') || soundUri.startsWith('file://')) {
      final key = 'custom_${soundUri.hashCode.toUnsigned(32)}';
      return (UriAndroidNotificationSound(soundUri), key);
    }

    return (null, 'default');
  }

  /// Returns a clean display name for any given sound URI.
  static String getSoundDisplayName(String? soundUri, [String? fallbackName]) {
    if (fallbackName != null && fallbackName.isNotEmpty) {
      return fallbackName;
    }

    if (soundUri == null || soundUri.isEmpty) {
      return 'Default alarm sound';
    }

    if (soundUri.startsWith('builtin:')) {
      final id = soundUri.substring('builtin:'.length).toLowerCase();
      final match = builtInSounds.where((s) => s.id == id).firstOrNull;
      if (match != null) return match.name;
    }

    return 'Selected audio';
  }

  // Pick audio from phone
  Future<Map<String, String>?> pickAudio() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Custom local song selection is currently supported on Android only.',
      );
    }

    final result = await _channel.invokeMapMethod<String, dynamic>('pickAudio');

    if (result == null) return null;

    return {
      'uri': result['uri']?.toString() ?? '',
      'name': result['name']?.toString() ?? 'Selected audio',
    };
  }

  // Save selected audio
  Future<void> saveAudio({
    required String type,
    required String uri,
    required String name,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_uriKey(type), uri);
    await preferences.setString(_nameKey(type), name);
  }

  // Select built-in sound
  Future<void> selectBuiltinSound({
    required String type,
    required String soundId,
  }) async {
    final sound = builtInSounds.firstWhere(
      (item) => item.id == soundId,
      orElse: () => throw ArgumentError('Unknown built-in sound: $soundId'),
    );

    await saveAudio(type: type, uri: 'builtin:${sound.id}', name: sound.name);
  }

  // Get saved audio URI
  Future<String?> getAudioUri(String type) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_uriKey(type));
  }

  // Get saved audio name
  Future<String?> getAudioName(String type) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_nameKey(type));
  }

  // Remove saved audio
  Future<void> removeAudio(String type) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_uriKey(type));
    await preferences.remove(_nameKey(type));
  }

  // Preview selected audio
  Future<void> previewAudio(String uri) async {
    await stopPreview();

    await _player.setReleaseMode(ReleaseMode.stop);

    try {
      if (uri.startsWith('builtin:')) {
        final soundId = uri.substring('builtin:'.length);

        final sound = builtInSounds.firstWhere(
          (item) => item.id == soundId,
          orElse: () => throw ArgumentError('Unknown built-in sound: $soundId'),
        );

        await _player.play(BytesSource(_createWav(sound.notes)));
        return;
      }

      await _player.play(UrlSource(uri));
    } catch (e) {
      debugPrint('Alarm audio preview error: $e');
      rethrow;
    }
  }

  // Generate WAV audio for built-in sounds
  Uint8List _createWav(List<double> notes) {
    const sampleRate = 22050;
    const bitsPerSample = 16;
    const channels = 1;
    const noteDuration = 0.32;
    const silenceDuration = 0.10;

    final samples = <int>[];

    for (final frequency in notes) {
      final duration = frequency == 0 ? silenceDuration : noteDuration;

      final count = (sampleRate * duration).round();

      for (int i = 0; i < count; i++) {
        double sample = 0;

        if (frequency != 0) {
          final time = i / sampleRate;

          final fadeIn = min(1.0, time / 0.025);
          final fadeOut = min(1.0, (duration - time) / 0.07);
          final envelope = min(fadeIn, fadeOut);

          sample = sin(2 * pi * frequency * time) * envelope * 0.42;
        }

        samples.add((sample * 32767).round());
      }
    }

    final dataLength = samples.length * 2;
    final fileLength = 44 + dataLength;

    final bytes = ByteData(fileLength);

    void writeText(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeText(0, 'RIFF');
    bytes.setUint32(4, fileLength - 8, Endian.little);

    writeText(8, 'WAVE');
    writeText(12, 'fmt ');

    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);

    bytes.setUint32(24, sampleRate, Endian.little);

    bytes.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );

    bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);

    bytes.setUint16(34, bitsPerSample, Endian.little);

    writeText(36, 'data');

    bytes.setUint32(40, dataLength, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return bytes.buffer.asUint8List();
  }

  // Stop preview
  Future<void> stopPreview() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  // Dispose audio player
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
