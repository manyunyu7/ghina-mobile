/// Online-only habit data (`docs/habits-food-enrichment.md`): the markdown
/// notes of a habit and the server-computed analysis (`/insights`). Neither is
/// stored on the device or synced.
library;

import 'value_equality.dart';

/// The markdown notes of a habit (`GET /api/mobile/habits/{id}`).
final class HabitNotes with ValueEquality {
  const HabitNotes({required this.notes, required this.updatedAt});

  /// Markdown, ≤ 100 000 characters.
  final String notes;

  /// Server `updatedAt` of the habit when read — the `expectedUpdatedAt` of a
  /// following replace.
  final DateTime updatedAt;

  @override
  List<Object?> get props => [notes, updatedAt];
}

/// Result of a notes write.
final class HabitNotesWrite with ValueEquality {
  const HabitNotesWrite({required this.updatedAt, required this.notesLength});
  final DateTime updatedAt;
  final int notesLength;

  @override
  List<Object?> get props => [updatedAt, notesLength];
}

/// One clean run (`runs.recent[]` / `runs.longest`).
final class HabitRun with ValueEquality {
  const HabitRun({
    required this.start,
    required this.end,
    required this.days,
    this.ongoing = false,
  });

  final String start;
  final String end;
  final int days;
  final bool ongoing;

  @override
  List<Object?> get props => [start, end, days, ongoing];
}

/// A risky time window (`relapses.riskWindows[]`), e.g. 21:00–23:59.
final class HabitRiskWindow with ValueEquality {
  const HabitRiskWindow({
    required this.from,
    required this.to,
    required this.count,
    required this.share,
  });

  final String from;
  final String to;
  final int count;

  /// 0–1 of all relapses.
  final double share;

  @override
  List<Object?> get props => [from, to, count, share];
}

/// A trigger tag's tally (`triggers[]`). Shares can sum past 1 (tags overlap).
final class HabitTriggerStat with ValueEquality {
  const HabitTriggerStat({
    required this.tag,
    required this.count,
    required this.share,
  });

  final String tag;
  final int count;
  final double share;

  @override
  List<Object?> get props => [tag, count, share];
}

/// One side of a dimension comparison (`lapse` / `ok`): number and scale carry
/// [avg], boolean [trueShare], select [options].
final class HabitDimensionAgg with ValueEquality {
  const HabitDimensionAgg({
    required this.n,
    this.avg,
    this.trueShare,
    this.options,
  });

  final int n;
  final double? avg;
  final double? trueShare;
  final Map<String, int>? options;

  @override
  List<Object?> get props => [n, avg, trueShare, options];
}

/// A dimension compared between relapse (or missed) days and clean (or met)
/// days (`dimensions[]`).
final class HabitDimensionStat with ValueEquality {
  const HabitDimensionStat({
    required this.key,
    required this.label,
    required this.type,
    this.lapse,
    this.ok,
    this.comparable = false,
  });

  final String key;
  final String label;
  final String type;
  final HabitDimensionAgg? lapse;
  final HabitDimensionAgg? ok;
  final bool comparable;

  @override
  List<Object?> get props => [key, label, type, lapse, ok, comparable];
}

/// A recent event in the analysis (`lastEvents[]`, note cut to 80 chars).
final class HabitEventBrief with ValueEquality {
  const HabitEventBrief({
    required this.date,
    required this.kind,
    required this.label,
    this.note,
  });

  final String date;
  final String kind;
  final String label;
  final String? note;

  @override
  List<Object?> get props => [date, kind, label, note];
}

/// The server's analysis of one habit (`GET /habits/{id}/insights`). Every
/// list may be empty and every counter 0; the parser never throws.
final class HabitAnalysis {
  const HabitAnalysis({
    required this.habitId,
    this.kind = 'build',
    this.from = '',
    this.to = '',
    this.days = 0,
    this.current = 0,
    this.longest = 0,
    this.unit = 'day',
    this.lastRelapse,
    this.runCount = 0,
    this.longestRun,
    this.recentRuns = const [],
    this.relapseTotal = 0,
    this.relapseDays = 0,
    this.perMonth = const {},
    this.weekday = const {},
    this.timeOfDay = const {},
    this.riskWindows = const [],
    this.triggers = const [],
    this.dimensions = const [],
    this.lastEvents = const [],
  });

  final String habitId;
  final String kind;
  final String from;
  final String to;
  final int days;
  final int current;
  final int longest;

  /// `day` | `week`.
  final String unit;
  final String? lastRelapse;
  final int runCount;
  final HabitRun? longestRun;
  final List<HabitRun> recentRuns;
  final int relapseTotal;
  final int relapseDays;

  /// `YYYY-MM` → relapses, oldest first.
  final Map<String, int> perMonth;

  /// `mon`…`sun` → relapses.
  final Map<String, int> weekday;

  /// `night | morning | afternoon | evening | unknown` → relapses.
  final Map<String, int> timeOfDay;
  final List<HabitRiskWindow> riskWindows;
  final List<HabitTriggerStat> triggers;
  final List<HabitDimensionStat> dimensions;
  final List<HabitEventBrief> lastEvents;

  bool get isQuit => kind == 'quit';

  /// Nothing worth charting yet.
  bool get isEmpty =>
      relapseTotal == 0 &&
      runCount == 0 &&
      triggers.isEmpty &&
      dimensions.isEmpty &&
      lastEvents.isEmpty;
}
