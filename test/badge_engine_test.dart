import 'package:eleven11/features/badges/badge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

List<DateTime> _n(int n) =>
    List.generate(n, (i) => DateTime.utc(2026, 1, 1 + i, 12));

BadgeResult _r(List<BadgeResult> l, BadgeId id) =>
    l.firstWhere((r) => r.definition.id == id);

void main() {
  test('no activity locks everything', () {
    final r = evaluateBadges(const BadgeActivity());
    expect(r.length, 8);
    expect(r.every((b) => !b.earned), isTrue);
  });

  test('goal creation thresholds and earned date', () {
    final r = evaluateBadges(BadgeActivity(goalCreatedAt: _n(5)));
    expect(_r(r, BadgeId.firstGoal).earnedAt, DateTime.utc(2026, 1, 1, 12));
    expect(_r(r, BadgeId.goalSetter).earnedAt, DateTime.utc(2026, 1, 5, 12));
    final four = evaluateBadges(BadgeActivity(goalCreatedAt: _n(4)));
    expect(_r(four, BadgeId.goalSetter).earned, isFalse);
    expect(_r(four, BadgeId.goalSetter).progress, 4);
  });

  test('crusher, task master, notes, planner thresholds', () {
    final r = evaluateBadges(BadgeActivity(
      goalCompletedAt: _n(10),
      taskCompletedAt: _n(50),
      noteCreatedAt: _n(10),
      eventCreatedAt: _n(9),
    ));
    expect(_r(r, BadgeId.goalCrusher).earned, isTrue);
    expect(_r(r, BadgeId.taskMaster).earned, isTrue);
    expect(_r(r, BadgeId.noteTaker).earned, isTrue);
    expect(_r(r, BadgeId.planner).earned, isFalse);
  });

  test('early bird / night owl count distinct local days', () {
    // Local-time constructors => independent of machine timezone.
    final early = [
      for (var d = 1; d <= 4; d++) DateTime(2026, 2, d, 7, 30),
      DateTime(2026, 2, 4, 6, 0), // same day as another: not a new day
    ];
    var r = evaluateBadges(BadgeActivity(taskCompletedAt: early));
    expect(_r(r, BadgeId.earlyBird).progress, 4);
    expect(_r(r, BadgeId.earlyBird).earned, isFalse);

    r = evaluateBadges(BadgeActivity(
      taskCompletedAt: [...early, DateTime(2026, 2, 5, 7, 59)],
    ));
    expect(_r(r, BadgeId.earlyBird).earned, isTrue);

    // 8:00 exactly is not "before 8:00 AM".
    r = evaluateBadges(BadgeActivity(taskCompletedAt: [
      for (var d = 1; d <= 5; d++) DateTime(2026, 3, d, 8, 0),
    ]));
    expect(_r(r, BadgeId.earlyBird).earned, isFalse);

    r = evaluateBadges(BadgeActivity(taskCompletedAt: [
      for (var d = 1; d <= 5; d++) DateTime(2026, 3, d, 20, 30),
    ]));
    expect(_r(r, BadgeId.nightOwl).earned, isTrue);
    expect(_r(r, BadgeId.earlyBird).earned, isFalse);
  });
}
