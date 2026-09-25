import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';
import 'package:ghina/domain/usecases/usecases.dart' show HabitXp;

final now = DateTime(2026, 9, 24, 21); // Thursday evening
final today = GameDate.fromDateTime(now);
GameDate day(int d) => GameDate(2026, 9, d);
DateTime at(int d, [int hour = 10, int minute = 0]) =>
    DateTime(2026, 9, d, hour, minute);

ActivityEvent met(String habit, {int d = 24, int minute = 0}) =>
    ActivityEvent.habitDayMet(
      habitId: habit,
      date: day(d),
      at: at(d, 10, minute),
    );

ActivityEvent clean(String habit, {int d = 24}) =>
    ActivityEvent.habitCleanCheckIn(habitId: habit, date: day(d), at: at(d));

ActivityEvent urges(String habit, int count, {int d = 24}) =>
    ActivityEvent.habitUrgeResisted(
      habitId: habit,
      date: day(d),
      at: at(d, 11),
      count: count,
    );

ActivityEvent milestone(
  String habit,
  int m, {
  String kind = 'quit',
  int d = 24,
  int runStart = 1,
  String unit = 'day',
}) => ActivityEvent.habitMilestone(
  habitId: habit,
  kind: kind,
  milestone: m,
  date: day(d),
  runStart: day(runStart),
  unit: unit,
);

GameSnapshot snap(List<ActivityEvent> events) => const ComputeGameSnapshot()(
  events: events,
  budgets: const [],
  local: const GameLocalState(lastSeenLevel: 1),
  now: now,
);

int xpOf(GameSnapshot s, XpSource src, [GameDate? d]) =>
    s.summary.xp.dayOf(d ?? today)?.breakdown[src] ?? 0;

AchievementProgress ach(GameSnapshot s, String id) => s.achievements.byId(id)!;

void main() {
  test('XpRules mirror HabitXp (server HABIT_XP)', () {
    expect(XpRules.habitBuildMet, HabitXp.buildMet);
    expect(XpRules.habitBuildDailyCap, HabitXp.buildMetDailyCap);
    expect(XpRules.habitCleanCheckIn, HabitXp.quitCleanCheckIn);
    expect(XpRules.habitUrgeResisted, HabitXp.urgeResisted);
    expect(XpRules.habitUrgeDailyCap, HabitXp.urgeResistedDailyCap);
    expect(XpRules.habitQuitMilestoneBonus, HabitXp.quitMilestoneBonus);
    expect(XpRules.habitBuildStreakBonus, HabitXp.buildStreakBonus);
  });

  group('Habit XP', () {
    test('build day met +5, at most 10 habits a day, counts toward goal', () {
      final s = snap([for (var i = 0; i < 12; i++) met('h$i', minute: i)]);
      expect(xpOf(s, XpSource.habitBuild), 50);
      expect(s.summary.xp.dayOf(today)!.activities, 10);
    });

    test('clean check-in +3 per habit per day', () {
      final s = snap([clean('q1'), clean('q2'), clean('q1', d: 23)]);
      expect(xpOf(s, XpSource.habitClean), 6);
      expect(xpOf(s, XpSource.habitClean, day(23)), 3);
    });

    test('urges +5 each, capped at 5 a day across habits', () {
      final s = snap([urges('q1', 3), urges('q2', 4), urges('q1', 2, d: 23)]);
      expect(xpOf(s, XpSource.habitUrge), 25);
      expect(xpOf(s, XpSource.habitUrge, day(23)), 10);
    });

    test('clean check-in and urges of the same habit/day both count', () {
      // Both events have the id `<habitId>:<date>`.
      final s = snap([clean('q1'), urges('q1', 1)]);
      expect(xpOf(s, XpSource.habitClean), 3);
      expect(xpOf(s, XpSource.habitUrge), 5);
    });

    test('milestone bonuses: quit 7/30/90/365, build 7/30/100', () {
      final s = snap([
        milestone('q1', 1, d: 1),
        milestone('q1', 3, d: 3),
        milestone('q1', 7, d: 7),
        milestone('b1', 7, kind: 'build', d: 20, runStart: 14),
      ]);
      expect(xpOf(s, XpSource.habitMilestone, day(1)), 0);
      expect(xpOf(s, XpSource.habitMilestone, day(3)), 0);
      expect(xpOf(s, XpSource.habitMilestone, day(7)), 20);
      expect(xpOf(s, XpSource.habitMilestone, day(20)), 20);
    });

    test('a milestone pays once per habit, even in a later run', () {
      final s = snap([
        milestone('q1', 7, d: 7, runStart: 1),
        milestone('q1', 7, d: 20, runStart: 14), // after a relapse
        milestone('q2', 7, d: 20, runStart: 14),
      ]);
      expect(xpOf(s, XpSource.habitMilestone, day(7)), 20);
      expect(xpOf(s, XpSource.habitMilestone, day(20)), 20); // q2 only
    });

    test('duplicate rows are counted once', () {
      final s = snap([met('h1'), met('h1'), urges('q', 2), urges('q', 2)]);
      expect(xpOf(s, XpSource.habitBuild), 5);
      expect(xpOf(s, XpSource.habitUrge), 10);
    });

    test('habits never touch the transaction streak', () {
      final s = snap([met('h1'), clean('q1')]);
      expect(s.summary.streak.current, 0);
    });
  });

  group('Habit achievements', () {
    test('first habit unlocks on any habit activity', () {
      expect(ach(snap(const []), 'first_habit').unlocked, isFalse);
      expect(ach(snap([met('h1')]), 'first_habit').unlocked, isTrue);
      expect(ach(snap([milestone('q', 1)]), 'first_habit').unlocked, isTrue);
    });

    test('7-day build streak (weeks count 7 days each)', () {
      expect(
        ach(
          snap([milestone('b', 7, kind: 'build')]),
          'habit_build_streak_7',
        ).unlocked,
        isTrue,
      );
      // Quit milestones don't count as build streaks.
      expect(
        ach(snap([milestone('q', 7)]), 'habit_build_streak_7').unlocked,
        isFalse,
      );
    });

    test('30 hari bersih from quit milestones', () {
      final a = ach(snap([milestone('q', 21)]), 'habit_clean_30');
      expect((a.current, a.unlocked), (21, false));
      expect(
        ach(snap([milestone('q', 30)]), 'habit_clean_30').unlocked,
        isTrue,
      );
    });

    test('100 urges resisted (uncapped count)', () {
      final events = [for (var d = 1; d <= 20; d++) urges('q', 5, d: d)];
      final a = ach(snap(events), 'habit_urges_100');
      expect((a.current, a.unlocked), (100, true));
    });

    test('3 habits all met for 7 consecutive days', () {
      List<ActivityEvent> days(Iterable<int> ds, int habits) => [
        for (final d in ds)
          for (var h = 0; h < habits; h++) met('h$h', d: d),
      ];
      expect(
        ach(
          snap(days([for (var d = 1; d <= 7; d++) d], 3)),
          'habit_trio_7',
        ).unlocked,
        isTrue,
      );
      // Only 2 habits → no; a gap breaks the run.
      expect(
        ach(
          snap(days([for (var d = 1; d <= 7; d++) d], 2)),
          'habit_trio_7',
        ).current,
        0,
      );
      final gap = ach(snap(days([1, 2, 3, 5, 6, 7, 8], 3)), 'habit_trio_7');
      expect((gap.current, gap.unlocked), (4, false));
    });
  });

  test('MarkCelebrated is idempotent', () {
    const s = GameLocalState();
    final a = const MarkCelebrated()(s, 'habit:2026-09-24:q1:7');
    expect(a.celebrated, {'habit:2026-09-24:q1:7'});
    expect(
      identical(const MarkCelebrated()(a, 'habit:2026-09-24:q1:7'), a),
      isTrue,
    );
  });
}
