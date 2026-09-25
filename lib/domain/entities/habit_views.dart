/// Read models of the habits module (produced by `habit_rules.dart` and the
/// habit watch use cases). Shapes mirror the server's `src/lib/habits.ts`.
library;

import 'habit.dart';
import 'value_equality.dart';

/// What a streak counts: days (daily / weekdays / quit) or ISO weeks (perWeek).
enum HabitStreakUnit {
  day('day', 'hari'),
  week('week', 'minggu');

  const HabitStreakUnit(this.wire, this.label);
  final String wire;
  final String label;
}

/// One clean run of a quit habit (between start, relapses and today).
final class CleanSegment with ValueEquality {
  const CleanSegment({
    required this.start,
    required this.end,
    required this.days,
    required this.ongoing,
  });

  /// `YYYY-MM-DD`, inclusive.
  final String start;
  final String end;
  final int days;

  /// The current run (ends today).
  final bool ongoing;

  @override
  List<Object?> get props => [start, end, days, ongoing];
}

/// Current and longest streak of a habit (server `HabitStreak`).
///
/// Build: consecutive met days (skip / unscheduled days neutral, today unmet
/// doesn't break) or consecutive met ISO weeks (perWeek). Quit: clean days
/// ("hari bersih") since the last relapse / start, today included.
final class HabitStreak with ValueEquality {
  const HabitStreak({
    required this.kind,
    required this.current,
    required this.longest,
    required this.unit,
    this.periodMet = false,
    this.lastRelapse,
    this.relapsedToday = false,
    this.segments = const [],
  });

  static const zero = HabitStreak(
    kind: HabitKind.build,
    current: 0,
    longest: 0,
    unit: HabitStreakUnit.day,
  );

  final HabitKind kind;
  final int current;
  final int longest;
  final HabitStreakUnit unit;

  /// Build: today (perWeek: this week) is already met.
  final bool periodMet;

  /// Quit: last relapse day (`YYYY-MM-DD`) in start…today.
  final String? lastRelapse;

  /// Quit: the relapse is today (current = 0).
  final bool relapsedToday;

  /// Quit: clean runs, oldest first; the last one is ongoing unless the
  /// relapse is today.
  final List<CleanSegment> segments;

  /// Quit: first day of the current clean run (null when there is none).
  String? get cleanSince =>
      kind == HabitKind.quit && segments.isNotEmpty && segments.last.ongoing
      ? segments.last.start
      : null;

  /// `12 hari`, `3 minggu`.
  String get label => '$current ${unit.label}';

  @override
  List<Object?> get props => [
    kind,
    current,
    longest,
    unit,
    periodMet,
    lastRelapse,
    relapsedToday,
    segments,
  ];
}

/// State of one calendar day of a habit (server `BuildDayStatus` /
/// quit `clean | relapse`).
enum HabitDayState {
  /// Build: goal reached on a scheduled day.
  met('met'),

  /// Build: a past day with some progress below the goal (a miss for
  /// daily/weekdays; neutral for perWeek).
  partial('partial'),

  /// Build: scheduled, nothing done, day over (daily/weekdays only).
  missed('missed'),

  /// Build: intentional rest day (skip row).
  skip('skip'),

  /// Build: today, not met yet (doesn't break anything until the day ends).
  pending('pending'),

  /// Build: not a scheduled weekday (even if done — it doesn't count), or a
  /// perWeek day without progress.
  off('off'),

  /// Quit: no relapse that day.
  clean('clean'),

  /// Quit: relapse that day.
  relapse('relapse'),

  /// Before the habit's `startDate`.
  before('before'),

  /// After today.
  future('future');

  const HabitDayState(this.wire);
  final String wire;
}

/// One day of a habit (heatmap cell / today card).
final class HabitDayCell with ValueEquality {
  const HabitDayCell({
    required this.date,
    required this.state,
    this.value,
    this.goal,
    this.urges = 0,
    this.relapses = 0,
    this.cleanCheckIn = false,
    this.hasNote = false,
  });

  /// `YYYY-MM-DD`.
  final String date;
  final HabitDayState state;

  /// The day's `done` value (build progress; 1 for check / clean check-in),
  /// null without a `done` row.
  final double? value;

  /// Build count/duration: the goal (null for check and quit habits).
  final double? goal;

  /// Σ urge / relapse values that day.
  final int urges;
  final int relapses;

  /// Quit: "Hari ini bersih ✅" confirmed.
  final bool cleanCheckIn;

  /// Any row of the day carries a journal note.
  final bool hasNote;

  /// 0–1 progress toward the goal (heatmap intensity).
  double get fraction {
    if (state == HabitDayState.met) return 1;
    final g = goal, v = value;
    if (g == null || g <= 0 || v == null) return 0;
    final f = v / g;
    return f > 1 ? 1 : (f < 0 ? 0 : f);
  }

  @override
  List<Object?> get props => [
    date,
    state,
    value,
    goal,
    urges,
    relapses,
    cleanCheckIn,
    hasNote,
  ];
}

/// perWeek: one ISO week (server `WeekStatus`).
enum HabitWeekState { met, missed, pending, neutral }

final class HabitWeek with ValueEquality {
  const HabitWeek({
    required this.week,
    required this.met,
    required this.need,
    required this.state,
  });

  /// Monday, `YYYY-MM-DD`.
  final String week;

  /// Met days in the week.
  final int met;

  /// min(times, available days) — days on/after the start minus skips.
  final int need;
  final HabitWeekState state;

  @override
  List<Object?> get props => [week, met, need, state];
}

/// Build: met periods ÷ judged periods; quit: clean days ÷ days.
final class HabitCompletion with ValueEquality {
  const HabitCompletion({required this.met, required this.total});

  final int met;
  final int total;

  /// 0–1, null when nothing was judged yet.
  double? get rate => total == 0 ? null : met / total;

  @override
  List<Object?> get props => [met, total];
}

/// A habit with its state today — one row of the today board / home card
/// (server `habitToday` + the rows of the day).
final class HabitToday with ValueEquality {
  const HabitToday({
    required this.habit,
    required this.date,
    required this.cell,
    required this.streak,
    required this.scheduled,
    this.doneLog,
    this.skipLog,
    this.relapseLog,
    this.urgeLog,
    this.week,
    this.canSkip = false,
    this.skipsLeft = 0,
  });

  final Habit habit;

  /// Today, `YYYY-MM-DD`.
  final String date;
  final HabitDayCell cell;
  final HabitStreak streak;

  /// Build: something to do today — weekdays: a scheduled day; perWeek: the
  /// week isn't met yet (or today is met); daily/quit: always (from the
  /// start date on).
  final bool scheduled;

  /// Today's rows (null = none).
  final HabitLog? doneLog;
  final HabitLog? skipLog;
  final HabitLog? relapseLog;
  final HabitLog? urgeLog;

  /// perWeek: this week's status (met days / need).
  final HabitWeek? week;

  /// Build: a skip today keeps every 7-day window at ≤ 2 skips.
  final bool canSkip;

  /// Build: skips left in the 7 days ending today (not counting today's).
  final int skipsLeft;

  String get id => habit.id;
  HabitDayState get state => cell.state;

  /// The `done` value today (count/minutes; null without a row).
  double? get progress => doneLog?.value;

  /// Count/duration goal (null for check / quit).
  double? get goal => cell.goal;

  /// Build: goal reached today.
  bool get met => habit.isBuild && cell.state == HabitDayState.met;
  bool get skipped => skipLog != null;

  /// 0–1 toward today's goal.
  double get fraction => cell.fraction;

  /// Build: still to do today (scheduled, not met, not skipped).
  bool get isDue => habit.isBuild && scheduled && !met && !skipped;

  bool get relapsedToday => relapseLog != null;
  bool get cleanCheckIn => habit.isQuit && doneLog != null;
  int get urges => cell.urges;
  int get relapses => cell.relapses;

  /// [Habit.publicTitle] — use outside the Habits screen (home, widgets).
  String get publicTitle => habit.publicTitle;

  @override
  List<Object?> get props => [
    habit,
    date,
    cell,
    streak,
    scheduled,
    doneLog,
    skipLog,
    relapseLog,
    urgeLog,
    week,
    canSkip,
    skipsLeft,
  ];
}

/// Every active habit with its today state, in habit order.
final class HabitBoard with ValueEquality {
  const HabitBoard({required this.date, required this.items});

  /// Today, `YYYY-MM-DD`.
  final String date;
  final List<HabitToday> items;

  bool get isEmpty => items.isEmpty;
  Iterable<HabitToday> get build => items.where((h) => h.habit.isBuild);
  Iterable<HabitToday> get quit => items.where((h) => h.habit.isQuit);

  /// Build habits with something to do today (scheduled, not skipped).
  int get dueCount => build.where((h) => h.scheduled && !h.skipped).length;

  /// Build habits met today.
  int get metCount => build.where((h) => h.met).length;

  /// Every build habit due today is met (and there is at least one).
  bool get allMet => dueCount > 0 && build.every((h) => !h.isDue);

  @override
  List<Object?> get props => [date, items];
}

/// `(tag, count)` of a trigger (weighted by the rows' `value`).
typedef TriggerCount = ({String tag, int count});

/// Streak value at the end of a day (history chart).
typedef StreakPoint = ({String date, int streak});

/// Relapse or urge statistics of a range (server `HabitInsights.relapses`).
final class HabitEventStats with ValueEquality {
  const HabitEventStats({
    this.total = 0,
    this.days = 0,
    this.byWeekday = const [0, 0, 0, 0, 0, 0, 0],
    this.byHour = const [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ],
    this.unknownHour = 0,
  });

  /// Σ value.
  final int total;

  /// Days with a row (relapse days).
  final int days;

  /// Index 0 = Senin … 6 = Minggu (from the row's date), Σ value.
  final List<int> byWeekday;

  /// Local hour 0–23 of `at`, Σ value.
  final List<int> byHour;

  /// Σ value of rows without `at`.
  final int unknownHour;

  @override
  List<Object?> get props => [total, days, byWeekday, byHour, unknownHour];
}

/// A journal note of the range.
final class HabitJournalEntry with ValueEquality {
  const HabitJournalEntry({
    required this.date,
    required this.type,
    required this.note,
    required this.logId,
  });

  final String date;
  final HabitLogType type;
  final String note;
  final String logId;

  @override
  List<Object?> get props => [date, type, note, logId];
}

/// Insights of one habit over an inclusive date range (server
/// `habitInsights`) plus a per-day streak history for the chart.
final class HabitInsights with ValueEquality {
  const HabitInsights({
    required this.from,
    required this.to,
    required this.streak,
    required this.completion,
    required this.heatmap,
    required this.weeks,
    required this.relapses,
    required this.urges,
    required this.topTriggers,
    required this.journal,
    required this.segments,
    required this.streakHistory,
  });

  /// `YYYY-MM-DD`, inclusive.
  final String from;
  final String to;
  final HabitStreak streak;

  /// Build: met ÷ judged periods; quit: clean days ÷ days (start…today).
  final HabitCompletion completion;

  /// One cell per day of the range, oldest first.
  final List<HabitDayCell> heatmap;

  /// perWeek: every ISO week overlapping the range.
  final List<HabitWeek> weeks;
  final HabitEventStats relapses;

  /// Urges resisted (`urges.total`).
  final HabitEventStats urges;

  /// Most frequent first (case-insensitive merge, weighted by value).
  final List<TriggerCount> topTriggers;

  /// Notes of the range, newest first.
  final List<HabitJournalEntry> journal;

  /// Quit: clean runs overlapping the range.
  final List<CleanSegment> segments;

  /// Streak at the end of each day of the range (0 before the start / on a
  /// miss or relapse; today = the current streak).
  final List<StreakPoint> streakHistory;

  @override
  List<Object?> get props => [
    from,
    to,
    streak,
    completion,
    heatmap,
    weeks,
    relapses,
    urges,
    topTriggers.map((t) => [t.tag, t.count]).toList(),
    journal,
    segments,
    streakHistory.map((p) => [p.date, p.streak]).toList(),
  ];
}

/// Habit detail screen: the habit, today, insights of the range and the rows
/// of the range, newest first.
final class HabitDetail with ValueEquality {
  const HabitDetail({
    required this.today,
    required this.insights,
    required this.logs,
  });

  final HabitToday today;
  final HabitInsights insights;

  /// Rows in the range, newest day first.
  final List<HabitLog> logs;

  Habit get habit => today.habit;
  HabitStreak get streak => today.streak;

  @override
  List<Object?> get props => [today, insights, logs];
}
