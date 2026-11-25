/// Pure, side-effect-free badge unlock logic (unit-testable).
library;

enum BadgeId {
  firstGoal,
  goalSetter,
  goalCrusher,
  taskMaster,
  earlyBird,
  nightOwl,
  noteTaker,
  planner,
}

class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.requirement,
    required this.target,
  });

  final BadgeId id;
  final String title;
  final String requirement;
  final int target;
}

const List<BadgeDefinition> kBadgeDefinitions = [
  BadgeDefinition(
    id: BadgeId.firstGoal,
    title: 'First Goal',
    requirement: 'Create 1 goal',
    target: 1,
  ),
  BadgeDefinition(
    id: BadgeId.goalSetter,
    title: 'Goal Setter',
    requirement: 'Create 5 goals',
    target: 5,
  ),
  BadgeDefinition(
    id: BadgeId.goalCrusher,
    title: 'Goal Crusher',
    requirement: 'Complete 10 goals',
    target: 10,
  ),
  BadgeDefinition(
    id: BadgeId.taskMaster,
    title: 'Task Master',
    requirement: 'Complete 50 tasks',
    target: 50,
  ),
  BadgeDefinition(
    id: BadgeId.earlyBird,
    title: 'Early Bird',
    requirement: 'Complete tasks before 8:00 AM on 5 different days',
    target: 5,
  ),
  BadgeDefinition(
    id: BadgeId.nightOwl,
    title: 'Night Owl',
    requirement: 'Complete tasks after 8:00 PM on 5 different days',
    target: 5,
  ),
  BadgeDefinition(
    id: BadgeId.noteTaker,
    title: 'Note Taker',
    requirement: 'Create 10 notes',
    target: 10,
  ),
  BadgeDefinition(
    id: BadgeId.planner,
    title: 'Planner',
    requirement: 'Create 10 calendar events',
    target: 10,
  ),
];

/// Raw activity timestamps gathered from the user's real data.
class BadgeActivity {
  const BadgeActivity({
    this.goalCreatedAt = const [],
    this.goalCompletedAt = const [],
    this.taskCompletedAt = const [],
    this.noteCreatedAt = const [],
    this.eventCreatedAt = const [],
  });

  final List<DateTime> goalCreatedAt;
  final List<DateTime> goalCompletedAt;
  final List<DateTime> taskCompletedAt;
  final List<DateTime> noteCreatedAt;
  final List<DateTime> eventCreatedAt;
}

class BadgeResult {
  const BadgeResult({
    required this.definition,
    required this.progress,
    required this.earnedAt,
  });

  final BadgeDefinition definition;
  final int progress;

  /// Date the unlock condition was first satisfied; null when locked.
  final DateTime? earnedAt;

  bool get earned => earnedAt != null;
  int get shownProgress =>
      progress > definition.target ? definition.target : progress;
}

/// Date when the Nth item (sorted ascending) occurred, or null.
DateTime? _nthDate(List<DateTime> dates, int n) {
  if (dates.length < n) return null;
  final sorted = [...dates]..sort();
  return sorted[n - 1];
}

/// For "N different days" badges: returns (distinctDayCount, dateReachingN).
/// All times are converted to the device's local timezone first.
(int, DateTime?) _distinctDays(
  List<DateTime> times,
  bool Function(DateTime local) matches,
  int n,
) {
  final local = times.map((t) => t.toLocal()).where(matches).toList()..sort();
  final seen = <String>{};
  DateTime? reached;
  for (final t in local) {
    final key = '${t.year}-${t.month}-${t.day}';
    if (seen.add(key) && seen.length == n) reached = t;
  }
  return (seen.length, reached);
}

List<BadgeResult> evaluateBadges(BadgeActivity a) {
  BadgeResult count(BadgeDefinition d, List<DateTime> dates) => BadgeResult(
        definition: d,
        progress: dates.length,
        earnedAt: _nthDate(dates, d.target),
      );

  BadgeResult days(BadgeDefinition d, bool Function(DateTime) m) {
    final (n, reached) = _distinctDays(a.taskCompletedAt, m, d.target);
    return BadgeResult(definition: d, progress: n, earnedAt: reached);
  }

  return [
    for (final d in kBadgeDefinitions)
      switch (d.id) {
        BadgeId.firstGoal || BadgeId.goalSetter => count(d, a.goalCreatedAt),
        BadgeId.goalCrusher => count(d, a.goalCompletedAt),
        BadgeId.taskMaster => count(d, a.taskCompletedAt),
        BadgeId.earlyBird => days(d, (t) => t.hour < 8),
        BadgeId.nightOwl => days(d, (t) => t.hour >= 20),
        BadgeId.noteTaker => count(d, a.noteCreatedAt),
        BadgeId.planner => count(d, a.eventCreatedAt),
      },
  ];
}
