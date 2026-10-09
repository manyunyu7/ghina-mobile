/// Habit enrichment (`docs/habits-food-enrichment.md`): the coping playbook
/// ([HabitTool]), user-defined per-event dimensions ([HabitFieldDef]) and
/// neutral events ([HabitEvent]). Phase A only syncs them; the screens come
/// later.
library;

import 'value_equality.dart';

const Object _unset = Object();

/// Kind of a coping tool.
enum HabitToolKind {
  distraction('distraction', 'Pengalih'),
  physical('physical', 'Fisik'),
  mindset('mindset', 'Pola pikir'),
  social('social', 'Sosial'),
  reward('reward', 'Hadiah'),
  other('other', 'Lainnya');

  const HabitToolKind(this.wire, this.label);
  final String wire;
  final String label;

  static HabitToolKind fromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return other;
  }
}

/// One entry of `habits.tools` (≤ 30 per habit).
final class HabitTool with ValueEquality {
  const HabitTool({
    required this.title,
    this.detail = '',
    this.kind = HabitToolKind.other,
  });

  /// 1–80.
  final String title;

  /// ≤ 500.
  final String detail;
  final HabitToolKind kind;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'kind': kind.wire,
  };

  /// Null when [v] isn't a tool with a title.
  static HabitTool? tryParse(Object? v) {
    if (v is! Map) return null;
    final title = v['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final detail = v['detail'];
    return HabitTool(
      title: title,
      detail: detail is String ? detail : '',
      kind: HabitToolKind.fromWire(v['kind'] as String?),
    );
  }

  @override
  List<Object?> get props => [title, detail, kind];
}

/// Type of a habit dimension.
enum HabitFieldType {
  text('text', 'Teks'),
  number('number', 'Angka'),
  scale('scale', 'Skala'),
  select('select', 'Pilihan'),
  boolean('boolean', 'Ya/Tidak');

  const HabitFieldType(this.wire, this.label);
  final String wire;
  final String label;

  /// Null for a type this app doesn't know (a newer server).
  static HabitFieldType? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// What a dimension can be attached to (`appliesTo`): the four log types plus
/// the three event kinds.
const habitFieldScopes = [
  'done',
  'skip',
  'relapse',
  'urge',
  'journal',
  'milestone',
  'event',
];

/// A per-event column (`habitFields`), e.g. "Tingkat stres" scale 1–10.
final class HabitFieldDef with ValueEquality {
  const HabitFieldDef({
    required this.id,
    this.habitId,
    required this.key,
    required this.label,
    this.type = HabitFieldType.text,
    this.options,
    this.min,
    this.max,
    this.appliesTo,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// null = every habit.
  final String? habitId;

  /// Slug `^[a-z][a-z0-9_]{0,39}$`, unique per user, immutable.
  final String key;
  final String label;
  final HabitFieldType type;

  /// `select` only.
  final List<String>? options;

  /// `scale` only (default 1/10).
  final int? min;
  final int? max;

  /// Subset of [habitFieldScopes]; null/empty = all.
  final List<String>? appliesTo;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  HabitFieldDef copyWith({
    Object? habitId = _unset,
    String? label,
    List<String>? appliesTo,
    int? sortOrder,
    DateTime? updatedAt,
  }) => HabitFieldDef(
    id: id,
    habitId: identical(habitId, _unset) ? this.habitId : habitId as String?,
    key: key,
    label: label ?? this.label,
    type: type,
    options: options,
    min: min,
    max: max,
    appliesTo: appliesTo ?? this.appliesTo,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    habitId,
    key,
    label,
    type,
    options,
    min,
    max,
    appliesTo,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'HabitFieldDef($key, ${type.wire})';
}

/// Kind of a [HabitEvent]. Events never affect streaks.
enum HabitEventKind {
  journal('journal', 'Jurnal'),
  milestone('milestone', 'Pencapaian'),
  event('event', 'Kejadian');

  const HabitEventKind(this.wire, this.label);
  final String wire;
  final String label;

  /// Null for a kind this app doesn't know (a newer server).
  static HabitEventKind? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// A journal day, milestone or neutral event of a habit (`habitEvents`).
final class HabitEvent with ValueEquality {
  const HabitEvent({
    required this.id,
    required this.habitId,
    required this.date,
    required this.kind,
    required this.label,
    this.note,
    this.at,
    this.extra = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String habitId;

  /// Local `YYYY-MM-DD`.
  final String date;
  final HabitEventKind kind;

  /// 1–60.
  final String label;

  /// ≤ 2000.
  final String? note;
  final DateTime? at;
  final Map<String, Object> extra;
  final DateTime createdAt;
  final DateTime updatedAt;

  HabitEvent copyWith({
    String? date,
    HabitEventKind? kind,
    String? label,
    Object? note = _unset,
    Object? at = _unset,
    Map<String, Object>? extra,
    DateTime? updatedAt,
  }) => HabitEvent(
    id: id,
    habitId: habitId,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    note: identical(note, _unset) ? this.note : note as String?,
    at: identical(at, _unset) ? this.at : at as DateTime?,
    extra: extra ?? this.extra,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    habitId,
    date,
    kind,
    label,
    note,
    at,
    extra,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'HabitEvent($habitId $date ${kind.wire} $label)';
}
