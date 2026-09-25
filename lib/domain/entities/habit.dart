/// Habits ("Teman Streak", `docs/habits.md`): habits to build and to quit, and
/// their daily log rows.
library;

import 'dart:convert';

import 'value_equality.dart';

const _unset = Object();

/// `build` (olahraga, baca buku…) or `quit` (rokok, begadang…).
enum HabitKind {
  build('build', 'Bangun kebiasaan'),
  quit('quit', 'Berhenti kebiasaan');

  const HabitKind(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown → build (server default).
  static HabitKind fromWire(String? v) => v == 'quit' ? quit : build;
}

/// `daily | weekdays | perWeek`.
enum HabitScheduleType {
  daily('daily', 'Setiap hari'),
  weekdays('weekdays', 'Hari tertentu'),
  perWeek('perWeek', 'X kali seminggu');

  const HabitScheduleType(this.wire, this.label);
  final String wire;
  final String label;

  static HabitScheduleType? tryFromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

/// When a build habit is due. JSON `{"type":"daily"}` |
/// `{"type":"weekdays","days":[1..7]}` (ISO weekdays, 1 = Senin) |
/// `{"type":"perWeek","times":1..7}`. Quit habits are always daily.
final class HabitSchedule with ValueEquality {
  const HabitSchedule._(this.type, {this.days = const [], this.times});

  static const daily = HabitSchedule._(HabitScheduleType.daily);

  /// [days] ISO weekdays (deduplicated + sorted on save).
  factory HabitSchedule.weekdays(List<int> days) => HabitSchedule._(
    HabitScheduleType.weekdays,
    days: List.unmodifiable({...days}.toList()..sort()),
  );

  factory HabitSchedule.perWeek(int times) =>
      HabitSchedule._(HabitScheduleType.perWeek, times: times);

  final HabitScheduleType type;

  /// [HabitScheduleType.weekdays] only.
  final List<int> days;

  /// [HabitScheduleType.perWeek] only (1–7).
  final int? times;

  bool get isDaily => type == HabitScheduleType.daily;
  bool get isWeekdays => type == HabitScheduleType.weekdays;
  bool get isPerWeek => type == HabitScheduleType.perWeek;

  /// Streaks of a perWeek habit count ISO weeks; the others count days.
  bool get countsWeeks => isPerWeek;

  Map<String, Object?> toJson() => switch (type) {
    HabitScheduleType.daily => {'type': 'daily'},
    HabitScheduleType.weekdays => {'type': 'weekdays', 'days': days},
    HabitScheduleType.perWeek => {'type': 'perWeek', 'times': times},
  };

  /// Lenient parse (JSON value or JSON string); invalid → null.
  static HabitSchedule? tryParse(Object? v) {
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is! Map) return null;
    switch (HabitScheduleType.tryFromWire(v['type'] as String?)) {
      case HabitScheduleType.daily:
        return daily;
      case HabitScheduleType.weekdays:
        final raw = v['days'];
        if (raw is! List) return null;
        final days = <int>{
          for (final d in raw)
            if (d is num && d == d.roundToDouble() && d >= 1 && d <= 7)
              d.toInt(),
        };
        if (days.isEmpty) return null;
        return HabitSchedule.weekdays(days.toList());
      case HabitScheduleType.perWeek:
        final t = v['times'];
        if (t is! num || t != t.roundToDouble() || t < 1 || t > 7) return null;
        return HabitSchedule.perWeek(t.toInt());
      case null:
        return null;
    }
  }

  /// `Setiap hari`, `Sen, Rab, Jum`, `3× seminggu`.
  String get label => switch (type) {
    HabitScheduleType.daily => 'Setiap hari',
    HabitScheduleType.weekdays =>
      days.length == 7
          ? 'Setiap hari'
          : days.map((d) => _weekdayShort[d - 1]).join(', '),
    HabitScheduleType.perWeek => '$times× seminggu',
  };

  @override
  List<Object?> get props => [type, days, times];

  @override
  String toString() => 'HabitSchedule(${jsonEncode(toJson())})';
}

const _weekdayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// `check | count | duration`.
enum HabitTargetType {
  check('check', 'Centang'),
  count('count', 'Jumlah'),
  duration('duration', 'Durasi');

  const HabitTargetType(this.wire, this.label);
  final String wire;
  final String label;

  static HabitTargetType? tryFromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

/// What "met" means for a build habit's day. JSON `{"type":"check"}` |
/// `{"type":"count","goal":1..10000,"unit":"gelas"}` |
/// `{"type":"duration","goal":1..1440}` (whole minutes). Count goals are
/// > 0 (fractions allowed), unit default [defaultCountUnit].
final class HabitTarget with ValueEquality {
  const HabitTarget._(this.type, {this.goal = 1, this.unit});

  static const check = HabitTarget._(HabitTargetType.check);

  factory HabitTarget.count(double goal, {String? unit}) => HabitTarget._(
    HabitTargetType.count,
    goal: goal,
    unit: unit == null || unit.trim().isEmpty ? defaultCountUnit : unit.trim(),
  );

  /// [minutes] per day.
  factory HabitTarget.duration(double minutes) =>
      HabitTarget._(HabitTargetType.duration, goal: minutes);

  final HabitTargetType type;

  /// Count / minutes needed per day (1 for check).
  final double goal;

  /// Count only, e.g. `gelas`, `halaman` (default `kali`).
  final String? unit;

  bool get isCheck => type == HabitTargetType.check;
  bool get isCount => type == HabitTargetType.count;
  bool get isDuration => type == HabitTargetType.duration;

  Map<String, Object?> toJson() => switch (type) {
    HabitTargetType.check => {'type': 'check'},
    HabitTargetType.count => {
      'type': 'count',
      'goal': _jsonNum(goal),
      'unit': unit ?? defaultCountUnit,
    },
    HabitTargetType.duration => {'type': 'duration', 'goal': _jsonNum(goal)},
  };

  static Object _jsonNum(double v) => v == v.roundToDouble() ? v.toInt() : v;

  static HabitTarget? tryParse(Object? v) {
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is! Map) return null;
    switch (HabitTargetType.tryFromWire(v['type'] as String?)) {
      case HabitTargetType.check:
        return check;
      case HabitTargetType.count:
        final g = v['goal'];
        if (g is! num || !g.isFinite || g <= 0 || g > 10000) return null;
        final u = v['unit'];
        if (u != null && (u is! String || u.trim().length > 20)) return null;
        return HabitTarget.count(g.toDouble(), unit: u as String?);
      case HabitTargetType.duration:
        final g = v['goal'];
        if (g is! num || g != g.roundToDouble() || g < 1 || g > 1440) {
          return null;
        }
        return HabitTarget.duration(g.toDouble());
      case null:
        return null;
    }
  }

  /// `8 gelas`, `30 menit`, `` (check).
  String get label => switch (type) {
    HabitTargetType.check => '',
    HabitTargetType.count => '${_fmt(goal)}${unit == null ? '' : ' $unit'}',
    HabitTargetType.duration => '${_fmt(goal)} menit',
  };

  @override
  List<Object?> get props => [type, goal, unit];
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// A habit (spec "Model").
final class Habit with ValueEquality {
  const Habit({
    required this.id,
    required this.name,
    this.emoji,
    this.color = defaultHabitColor,
    this.kind = HabitKind.build,
    this.schedule = HabitSchedule.daily,
    this.target = HabitTarget.check,
    this.reminders = const [],
    this.isPrivate = false,
    this.why,
    required this.startDate,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 1–60.
  final String name;

  /// One emoji or null.
  final String? emoji;

  /// `#rrggbb`.
  final String color;
  final HabitKind kind;

  /// Build habits; quit habits are always treated as daily.
  final HabitSchedule schedule;

  /// Build habits only (quit habits keep `check`).
  final HabitTarget target;

  /// Local `HH:mm`, ≤ 5, sorted.
  final List<String> reminders;

  /// Masked outside the Habits screen (wire `private`): see [publicTitle].
  final bool isPrivate;

  /// "Alasan berhenti" shown on the emergency screen (≤ 500).
  final String? why;

  /// `YYYY-MM-DD`: streak counting starts here (quit: "bersih sejak").
  final String startDate;
  final bool archived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isBuild => kind == HabitKind.build;
  bool get isQuit => kind == HabitKind.quit;

  /// `💧 Minum air` (name only without emoji).
  String get title => emoji == null ? name : '$emoji $name';

  /// What home cards, widgets and notifications show: [title], or
  /// [privateHabitTitle] for private habits (server `maskedHabitName`).
  String get publicTitle => isPrivate ? privateHabitTitle : title;

  Habit copyWith({
    String? name,
    Object? emoji = _unset,
    String? color,
    HabitKind? kind,
    HabitSchedule? schedule,
    HabitTarget? target,
    List<String>? reminders,
    bool? isPrivate,
    Object? why = _unset,
    String? startDate,
    bool? archived,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Habit(
    id: id,
    name: name ?? this.name,
    emoji: identical(emoji, _unset) ? this.emoji : emoji as String?,
    color: color ?? this.color,
    kind: kind ?? this.kind,
    schedule: schedule ?? this.schedule,
    target: target ?? this.target,
    reminders: reminders ?? this.reminders,
    isPrivate: isPrivate ?? this.isPrivate,
    why: identical(why, _unset) ? this.why : why as String?,
    startDate: startDate ?? this.startDate,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    emoji,
    color,
    kind,
    schedule,
    target,
    reminders,
    isPrivate,
    why,
    startDate,
    archived,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Habit($id, $name, ${kind.wire})';
}

const defaultHabitColor = '#58CC02';

/// Title of a private habit outside the Habits screen (server
/// `PRIVATE_HABIT_MASK`).
const privateHabitTitle = 'Kebiasaan pribadi';

/// Unit of a count target when none is given (server `DEFAULT_COUNT_UNIT`).
const defaultCountUnit = 'kali';

/// Notification title of a private habit's reminder (spec).
const privateHabitReminderTitle = 'Waktunya cek kebiasaanmu ✨';

/// `done | skip | relapse | urge`.
enum HabitLogType {
  /// Build: progress of the day (`value`); quit: the explicit clean check-in
  /// ("Hari ini bersih ✅", value 1 — streak math ignores it).
  done('done', 'Selesai'),

  /// Build: intentional rest day (neutral), ≤ 2 per rolling 7 days.
  skip('skip', 'Libur'),

  /// Quit: it happened that day (`value` = how many times).
  relapse('relapse', 'Kambuh'),

  /// Quit: cravings resisted that day (`value` = count).
  urge('urge', 'Godaan ditahan');

  const HabitLogType(this.wire, this.label);
  final String wire;
  final String label;

  static HabitLogType? tryFromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

/// One row per habit/day/type (`@@unique([habitId, date, type])`).
final class HabitLog with ValueEquality {
  const HabitLog({
    required this.id,
    required this.habitId,
    required this.date,
    required this.type,
    this.value,
    this.note,
    this.triggers = const [],
    this.at,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String habitId;

  /// Local `YYYY-MM-DD`.
  final String date;
  final HabitLogType type;

  /// done: progress (count/minutes; 1 for check / clean check-in);
  /// relapse: times (default 1); urge: count; skip: null.
  final double? value;

  /// Journal (≤ 1000).
  final String? note;

  /// Relapse/urge tags (≤ 10), e.g. `bosan`, `stres`.
  final List<String> triggers;

  /// When it happened (relapse/urge time of day).
  final DateTime? at;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// [value] with the type's default (1 for relapse/urge/done, 0 for skip).
  double get amount => value ?? (type == HabitLogType.skip ? 0 : 1);

  bool get hasNote => note != null && note!.isNotEmpty;

  HabitLog copyWith({
    Object? value = _unset,
    Object? note = _unset,
    List<String>? triggers,
    Object? at = _unset,
    DateTime? updatedAt,
  }) => HabitLog(
    id: id,
    habitId: habitId,
    date: date,
    type: type,
    value: identical(value, _unset) ? this.value : (value as num?)?.toDouble(),
    note: identical(note, _unset) ? this.note : note as String?,
    triggers: triggers ?? this.triggers,
    at: identical(at, _unset) ? this.at : at as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    habitId,
    date,
    type,
    value,
    note,
    triggers,
    at,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'HabitLog($habitId $date ${type.wire} $value)';
}

/// Suggested trigger tags (spec); users may add their own.
const habitTriggerSuggestions = [
  'bosan',
  'stres',
  'sendirian',
  'malam',
  'medsos',
  'capek',
];
