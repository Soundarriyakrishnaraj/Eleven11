import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'badge_engine.dart';

/// Loads real user activity, evaluates badges and persists earned dates.
///
/// Earned badges are stored per user id in SharedPreferences so they are
/// never revoked (e.g. if a goal is later deleted) and survive restarts and
/// logins. No database changes are required.
class BadgeService {
  BadgeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Bumped whenever goals/tasks/notes/events change; UI listens to refresh.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void notifyChanged() => changes.value++;

  static const String _notesKey = 'eleven11_user_notes';

  static DateTime? _parse(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static List<DateTime> _dates(List rows, String col) => [
        for (final r in rows)
          if (_parse((r as Map)[col]) != null) _parse(r[col])!,
      ];

  /// Records that a note was created, so deleting it never loses progress.
  static Future<void> recordNoteCreated(String noteId, DateTime when) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final log = _readMap(prefs, 'badge_notes_$uid');
    log.putIfAbsent(noteId, () => when.toUtc().toIso8601String());
    await prefs.setString('badge_notes_$uid', jsonEncode(log));
    notifyChanged();
  }

  static Map<String, String> _readMap(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<List<BadgeResult>> load() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return evaluateBadges(const BadgeActivity());

    final prefs = await SharedPreferences.getInstance();

    final results = await Future.wait([
      _client
          .from('goals')
          .select('created_at, status, updated_at')
          .eq('user_id', uid),
      _client
          .from('tasks')
          .select('completed_at')
          .eq('user_id', uid)
          .eq('is_completed', true)
          .not('completed_at', 'is', null),
      _client.from('events').select('created_at').eq('user_id', uid),
    ]);
    final goals = results[0] as List;
    final tasks = results[1] as List;
    final events = results[2] as List;

    final goalCompleted = <DateTime>[
      for (final g in goals)
        if ((g as Map)['status'] == 'completed')
          _parse(g['updated_at']) ?? _parse(g['created_at']) ?? DateTime.now(),
    ];

    // Notes: union of currently stored notes and the persisted creation log.
    final noteLog = _readMap(prefs, 'badge_notes_$uid');
    for (final item in prefs.getStringList(_notesKey) ?? const <String>[]) {
      try {
        final id = (jsonDecode(item) as Map)['id']?.toString();
        final ms = int.tryParse(id ?? '');
        if (id != null && ms != null) {
          noteLog.putIfAbsent(
            id,
            () => DateTime.fromMillisecondsSinceEpoch(ms)
                .toUtc()
                .toIso8601String(),
          );
        }
      } catch (_) {}
    }
    await prefs.setString('badge_notes_$uid', jsonEncode(noteLog));

    final activity = BadgeActivity(
      goalCreatedAt: _dates(goals, 'created_at'),
      goalCompletedAt: goalCompleted,
      taskCompletedAt: _dates(tasks, 'completed_at'),
      noteCreatedAt: [
        for (final v in noteLog.values)
          if (DateTime.tryParse(v) != null) DateTime.parse(v),
      ],
      eventCreatedAt: _dates(events, 'created_at'),
    );

    final computed = evaluateBadges(activity);

    // Merge with persisted earned dates: earned badges are never revoked and
    // keep their earliest known date.
    final earnedKey = 'badge_earned_$uid';
    final stored = _readMap(prefs, earnedKey);
    final merged = <BadgeResult>[];
    var changed = false;
    for (final r in computed) {
      final key = r.definition.id.name;
      final storedDate = DateTime.tryParse(stored[key] ?? '');
      DateTime? date = r.earnedAt;
      if (storedDate != null) {
        date = (date == null || storedDate.isBefore(date)) ? storedDate : date;
      }
      if (date != null && stored[key] != date.toUtc().toIso8601String()) {
        stored[key] = date.toUtc().toIso8601String();
        changed = true;
      }
      merged.add(BadgeResult(
        definition: r.definition,
        progress: r.progress,
        earnedAt: date?.toLocal(),
      ));
    }
    if (changed) await prefs.setString(earnedKey, jsonEncode(stored));
    return merged;
  }
}
