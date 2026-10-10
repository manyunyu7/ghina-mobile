/// Dreams ("Mimpi", `docs/dreams.md`): mimpi, cita-cita and bucket-list items
/// with metrics, steps (checklist + rewards) and costs.
///
/// Date-only values (`targetDate`, `startedAt`, `completedAt`, step `dueDate`,
/// metric `startDate` / `targetDate`) are `YYYY-MM-DD` strings, exactly as the
/// server and the sync wire carry them; the pure rules in
/// `usecases/dreams_rules.dart` work on those keys. Timestamps are `DateTime`.
///
/// The synced entities hold **no computed values**. Progress, the current value
/// of a metric, on-track and projections come from the server only and are the
/// read models [DreamMetricReading] / [DreamDetail] / [DreamSummary] below.
library;

import 'value_equality.dart';

/// Lifecycle of a dream. Unknown wire values read as [idea] (a newer server).
enum DreamStatus {
  idea('idea', 'Ide', '💭'),
  planned('planned', 'Direncanakan', '🗓️'),
  active('active', 'Berjalan', '🔄'),
  waiting('waiting', 'Menunggu', '⏳'),
  done('done', 'Tercapai', '✅'),
  paused('paused', 'Dijeda', '⏸️'),
  dropped('dropped', 'Dilepas', '🗑️'),
  watching('watching', 'Dipantau', '⚠️');

  const DreamStatus(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  /// Terminal statuses: not "open", never stale or overdue, left out of the
  /// open-dream cost totals.
  bool get isOpen => this != done && this != dropped;

  static DreamStatus fromWire(String? v) => tryFromWire(v) ?? idea;

  /// Null for a value this app doesn't know.
  static DreamStatus? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// Coarse horizon of a dream without a precise date.
enum DreamHorizon {
  someday('someday', 'Suatu hari'),
  thisYear('this_year', 'Tahun ini'),
  nextYear('next_year', 'Tahun depan'),
  multiYear('multi_year', 'Beberapa tahun'),
  ongoing('ongoing', 'Berkelanjutan');

  const DreamHorizon(this.wire, this.label);
  final String wire;
  final String label;

  static DreamHorizon? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// How precise a target date is. The stored date is always the last day of
/// its period (`Q1 2027` → `2027-03-31`).
enum TargetPrecision {
  day('day', 'Tanggal'),
  month('month', 'Bulan'),
  quarter('quarter', 'Kuartal'),
  year('year', 'Tahun');

  const TargetPrecision(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown or missing values read as [day] (the server default).
  static TargetPrecision fromWire(String? v) => tryFromWire(v) ?? day;

  static TargetPrecision? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// Type of a custom column (`dreamFields`); same set as People's fields.
enum DreamFieldType {
  text('text', 'Teks'),
  longtext('longtext', 'Teks panjang'),
  number('number', 'Angka'),
  date('date', 'Tanggal'),
  url('url', 'Tautan'),
  phone('phone', 'Telepon'),
  email('email', 'Email'),
  select('select', 'Pilihan'),
  boolean('boolean', 'Ya/Tidak');

  const DreamFieldType(this.wire, this.label);
  final String wire;
  final String label;

  /// Null for a type this app doesn't know (a newer server).
  static DreamFieldType? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// Where a metric's values come from. Computed sources are read by the server.
enum MetricSource {
  weight('weight', 'Berat badan', 'kg', MetricRefKind.none),
  systolic('systolic', 'Tekanan sistolik', 'mmHg', MetricRefKind.none),
  diastolic('diastolic', 'Tekanan diastolik', 'mmHg', MetricRefKind.none),
  pulse('pulse', 'Denyut nadi', 'bpm', MetricRefKind.none),
  habitCleanDays(
    'habit_clean_days',
    'Hari bersih (kebiasaan berhenti)',
    'hari',
    MetricRefKind.habit,
  ),
  habitCurrentStreak(
    'habit_current_streak',
    'Streak kebiasaan saat ini',
    '',
    MetricRefKind.habit,
  ),
  habitLongestStreak(
    'habit_longest_streak',
    'Streak kebiasaan terpanjang',
    '',
    MetricRefKind.habit,
  ),
  walletBalance('wallet_balance', 'Saldo dompet', 'Rp', MetricRefKind.wallet),
  netWorth('net_worth', 'Kekayaan bersih', 'Rp', MetricRefKind.none),
  spendCategory(
    'spend_category',
    'Pengeluaran kategori',
    'Rp',
    MetricRefKind.category,
  ),
  manual('manual', 'Manual', '', MetricRefKind.none);

  const MetricSource(this.wire, this.label, this.defaultUnit, this.refKind);
  final String wire;
  final String label;
  final String defaultUnit;

  /// Which id the `sourceRef` object must carry.
  final MetricRefKind refKind;

  /// Only [manual] metrics take readings through `POST …/value`.
  bool get isManual => this == manual;

  static MetricSource? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// The id a metric source points at (`sourceRef`).
enum MetricRefKind { none, habit, wallet, category }

enum MetricDirection {
  down('down'),
  up('up');

  const MetricDirection(this.wire);
  final String wire;

  static MetricDirection? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// Period of a `spend_category` metric.
enum SpendPeriod {
  week('week', 'Minggu ini'),
  month('month', 'Bulan ini'),
  quarter('quarter', 'Kuartal ini'),
  year('year', 'Tahun ini'),
  all('all', 'Sepanjang waktu');

  const SpendPeriod(this.wire, this.label);
  final String wire;
  final String label;

  static SpendPeriod fromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return month;
  }
}

/// `dreamCategories` row: a user category (the 12 built-ins are seeded by the
/// server). [key] is an immutable slug.
final class DreamCategory with ValueEquality {
  const DreamCategory({
    required this.id,
    required this.key,
    required this.label,
    required this.emoji,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String key;
  final String label;
  final String emoji;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  DreamCategory copyWith({
    String? label,
    String? emoji,
    int? sortOrder,
    DateTime? updatedAt,
  }) => DreamCategory(
    id: id,
    key: key,
    label: label ?? this.label,
    emoji: emoji ?? this.emoji,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    label,
    emoji,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'DreamCategory($key)';
}

/// `dreamFields` row: a custom column definition. [key] is immutable.
final class DreamFieldDef with ValueEquality {
  const DreamFieldDef({
    required this.id,
    required this.key,
    required this.label,
    this.type = DreamFieldType.text,
    this.options,
    this.appliesTo,
    this.sortOrder = 0,
    this.showInList = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Slug `^[a-z][a-z0-9_]{0,39}$`, immutable.
  final String key;
  final String label;
  final DreamFieldType type;

  /// `select` only.
  final List<String>? options;

  /// Dream category keys; null or empty = every category.
  final List<String>? appliesTo;
  final int sortOrder;
  final bool showInList;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the column is shown for a dream of [category].
  bool appliesToCategory(String category) =>
      appliesTo == null || appliesTo!.isEmpty || appliesTo!.contains(category);

  DreamFieldDef copyWith({
    String? label,
    List<String>? appliesTo,
    int? sortOrder,
    bool? showInList,
    DateTime? updatedAt,
  }) => DreamFieldDef(
    id: id,
    key: key,
    label: label ?? this.label,
    type: type,
    options: options,
    appliesTo: appliesTo ?? this.appliesTo,
    sortOrder: sortOrder ?? this.sortOrder,
    showInList: showInList ?? this.showInList,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    label,
    type,
    options,
    appliesTo,
    sortOrder,
    showInList,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'DreamFieldDef($key, ${type.wire})';
}

/// Soft links of a dream (`links`): not foreign keys, dead ids are not resolved.
final class DreamLinks with ValueEquality {
  const DreamLinks({this.taskIds = const [], this.habitIds = const []});

  static const empty = DreamLinks();

  final List<String> taskIds;
  final List<String> habitIds;

  @override
  List<Object?> get props => [taskIds, habitIds];
}

/// `dreams` row. The long narrative lives in a note ([noteId]); [why] and
/// [summary] are short texts.
final class Dream with ValueEquality {
  const Dream({
    required this.id,
    required this.title,
    this.emoji,
    this.category = 'other',
    this.status = DreamStatus.idea,
    this.priority,
    this.horizon,
    this.targetDate,
    this.targetPrecision = TargetPrecision.day,
    this.condition,
    this.why,
    this.summary,
    this.costEstimate,
    this.costNote,
    this.progressManual,
    this.startedAt,
    this.completedAt,
    this.noteId,
    this.parentId,
    this.tags = const [],
    this.fields = const {},
    this.links = DreamLinks.empty,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? emoji;

  /// A [DreamCategory.key] of the user.
  final String category;
  final DreamStatus status;

  /// 1 (highest) … 5.
  final int? priority;
  final DreamHorizon? horizon;

  /// `YYYY-MM-DD`, the last day of [targetPrecision]'s period.
  final String? targetDate;
  final TargetPrecision targetPrecision;
  final String? condition;
  final String? why;
  final String? summary;

  /// Rupiah estimate.
  final double? costEstimate;
  final String? costNote;

  /// 0–100, overrides the computed progress when set.
  final int? progressManual;

  /// `YYYY-MM-DD`.
  final String? startedAt;

  /// `YYYY-MM-DD`.
  final String? completedAt;
  final String? noteId;
  final String? parentId;
  final List<String> tags;

  /// Custom-column values: key → string | number | bool.
  final Map<String, Object> fields;
  final DreamLinks links;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Dream copyWith({
    String? title,
    String? emoji,
    String? category,
    DreamStatus? status,
    int? priority,
    DreamHorizon? horizon,
    String? targetDate,
    TargetPrecision? targetPrecision,
    String? condition,
    String? why,
    String? summary,
    double? costEstimate,
    String? costNote,
    int? progressManual,
    String? startedAt,
    bool clearStartedAt = false,
    String? completedAt,
    bool clearCompletedAt = false,
    String? noteId,
    bool clearNoteId = false,
    String? parentId,
    bool clearParentId = false,
    List<String>? tags,
    Map<String, Object>? fields,
    DreamLinks? links,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Dream(
    id: id,
    title: title ?? this.title,
    emoji: emoji ?? this.emoji,
    category: category ?? this.category,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    horizon: horizon ?? this.horizon,
    targetDate: targetDate ?? this.targetDate,
    targetPrecision: targetPrecision ?? this.targetPrecision,
    condition: condition ?? this.condition,
    why: why ?? this.why,
    summary: summary ?? this.summary,
    costEstimate: costEstimate ?? this.costEstimate,
    costNote: costNote ?? this.costNote,
    progressManual: progressManual ?? this.progressManual,
    startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    noteId: clearNoteId ? null : (noteId ?? this.noteId),
    parentId: clearParentId ? null : (parentId ?? this.parentId),
    tags: tags ?? this.tags,
    fields: fields ?? this.fields,
    links: links ?? this.links,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    emoji,
    category,
    status,
    priority,
    horizon,
    targetDate,
    targetPrecision,
    condition,
    why,
    summary,
    costEstimate,
    costNote,
    progressManual,
    startedAt,
    completedAt,
    noteId,
    parentId,
    tags,
    fields,
    links,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Dream($id, ${status.wire})';
}

/// `dreamSteps` row: a checklist item of a dream. A step may carry a reward
/// ([reward]) and may complete itself when a metric of the same dream crosses
/// [atValue] (both [metricRef] and [atValue], or neither).
final class DreamStep with ValueEquality {
  const DreamStep({
    required this.id,
    required this.dreamId,
    required this.title,
    this.notes,
    this.done = false,
    this.doneAt,
    this.dueDate,
    this.cost,
    this.reward,
    this.metricRef,
    this.atValue,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String dreamId;
  final String title;
  final String? notes;
  final bool done;

  /// Stamped when [done] becomes true, cleared when it leaves it.
  final DateTime? doneAt;

  /// `YYYY-MM-DD`.
  final String? dueDate;

  /// Rupiah.
  final double? cost;

  /// "Hadiah" that unlocks when the step is done.
  final String? reward;
  final String? metricRef;
  final double? atValue;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  DreamStep copyWith({
    String? title,
    String? notes,
    bool? done,
    DateTime? doneAt,
    bool clearDoneAt = false,
    String? dueDate,
    double? cost,
    String? reward,
    String? metricRef,
    double? atValue,
    bool clearMetric = false,
    int? sortOrder,
    DateTime? updatedAt,
  }) => DreamStep(
    id: id,
    dreamId: dreamId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    done: done ?? this.done,
    doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
    dueDate: dueDate ?? this.dueDate,
    cost: cost ?? this.cost,
    reward: reward ?? this.reward,
    metricRef: clearMetric ? null : (metricRef ?? this.metricRef),
    atValue: clearMetric ? null : (atValue ?? this.atValue),
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    dreamId,
    title,
    notes,
    done,
    doneAt,
    dueDate,
    cost,
    reward,
    metricRef,
    atValue,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'DreamStep($id, done: $done)';
}

/// `dreamMetrics` row: a number that tracks a dream. The current value is
/// computed by the server (see [DreamMetricReading]); only [manualValue] /
/// [manualAt] are stored, and only for [MetricSource.manual].
final class DreamMetric with ValueEquality {
  const DreamMetric({
    required this.id,
    required this.dreamId,
    required this.label,
    required this.source,
    this.sourceRef,
    this.direction,
    this.unit,
    this.startValue,
    this.startDate,
    required this.targetValue,
    this.targetDate,
    this.manualValue,
    this.manualAt,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String dreamId;
  final String label;
  final MetricSource source;

  /// `{habitId}` / `{walletId}` / `{categoryId, period}` by [source]; null otherwise.
  final Map<String, Object?>? sourceRef;

  /// Null when omitted: see [effectiveDirection].
  final MetricDirection? direction;
  final String? unit;
  final double? startValue;

  /// `YYYY-MM-DD`.
  final String? startDate;
  final double targetValue;

  /// `YYYY-MM-DD`. Null falls back to the dream's target date.
  final String? targetDate;
  final double? manualValue;
  final DateTime? manualAt;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// [direction], or the server's rule when omitted: `down` when the target is
  /// below the start, else `up`.
  MetricDirection get effectiveDirection =>
      direction ??
      (startValue != null && targetValue < startValue!
          ? MetricDirection.down
          : MetricDirection.up);

  DreamMetric copyWith({
    String? label,
    MetricSource? source,
    Map<String, Object?>? sourceRef,
    MetricDirection? direction,
    String? unit,
    double? startValue,
    String? startDate,
    double? targetValue,
    String? targetDate,
    double? manualValue,
    DateTime? manualAt,
    int? sortOrder,
    DateTime? updatedAt,
  }) => DreamMetric(
    id: id,
    dreamId: dreamId,
    label: label ?? this.label,
    source: source ?? this.source,
    sourceRef: sourceRef ?? this.sourceRef,
    direction: direction ?? this.direction,
    unit: unit ?? this.unit,
    startValue: startValue ?? this.startValue,
    startDate: startDate ?? this.startDate,
    targetValue: targetValue ?? this.targetValue,
    targetDate: targetDate ?? this.targetDate,
    manualValue: manualValue ?? this.manualValue,
    manualAt: manualAt ?? this.manualAt,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    dreamId,
    label,
    source,
    sourceRef,
    direction,
    unit,
    startValue,
    startDate,
    targetValue,
    targetDate,
    manualValue,
    manualAt,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'DreamMetric($id, ${source.wire})';
}

// ---------------------------------------------------------------- read models (server-computed)

/// Why a computed metric value is missing.
enum MetricUnavailable {
  noData('no_data'),
  missingRef('missing_ref'),
  wrongKind('wrong_kind');

  const MetricUnavailable(this.wire);
  final String wire;

  static MetricUnavailable? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// One point of a metric's history.
final class MetricHistoryPoint with ValueEquality {
  const MetricHistoryPoint({required this.at, required this.value});
  final DateTime at;
  final double value;

  @override
  List<Object?> get props => [at, value];
}

/// Server-computed values of one metric (`GET /dreams/{id}`, the metric write
/// responses). Never stored locally.
final class DreamMetricReading with ValueEquality {
  const DreamMetricReading({
    this.currentValue,
    this.currentAt,
    this.progressPct,
    this.onTrack,
    this.projectedDate,
    this.unavailable,
    this.history = const [],
  });

  final double? currentValue;
  final DateTime? currentAt;

  /// 0–100, null when it can't be known.
  final int? progressPct;

  /// null when unknown (no target date, or no projection).
  final bool? onTrack;

  /// `YYYY-MM-DD`.
  final String? projectedDate;
  final MetricUnavailable? unavailable;
  final List<MetricHistoryPoint> history;

  static const none = DreamMetricReading();

  @override
  List<Object?> get props => [
    currentValue,
    currentAt,
    progressPct,
    onTrack,
    projectedDate,
    unavailable,
    history,
  ];
}

/// A metric with its server-computed reading.
final class DreamMetricView with ValueEquality {
  const DreamMetricView({
    required this.metric,
    this.reading = DreamMetricReading.none,
  });
  final DreamMetric metric;
  final DreamMetricReading reading;

  @override
  List<Object?> get props => [metric, reading];
}

/// Cost totals of a dream (`cost` on the detail).
final class DreamCost with ValueEquality {
  const DreamCost({
    this.estimate,
    this.stepsTotal = 0,
    this.stepsDone = 0,
    this.stepsRemaining = 0,
    this.stepsWithCost = 0,
    this.diff,
    this.effective,
  });

  final double? estimate;
  final double stepsTotal;
  final double stepsDone;
  final double stepsRemaining;
  final int stepsWithCost;

  /// estimate − stepsTotal.
  final double? diff;

  /// The estimate, else the steps' sum, else null.
  final double? effective;

  @override
  List<Object?> get props => [
    estimate,
    stepsTotal,
    stepsDone,
    stepsRemaining,
    stepsWithCost,
    diff,
    effective,
  ];
}

/// Overall progress of a dream (`progress` on list rows and the detail).
final class DreamProgressView with ValueEquality {
  const DreamProgressView({
    this.pct,
    this.onTrack,
    this.projectedDate,
    this.metricCount = 0,
    this.stepsDone = 0,
    this.stepsTotal = 0,
  });

  final int? pct;
  final bool? onTrack;
  final String? projectedDate;
  final int metricCount;
  final int stepsDone;
  final int stepsTotal;

  @override
  List<Object?> get props => [
    pct,
    onTrack,
    projectedDate,
    metricCount,
    stepsDone,
    stepsTotal,
  ];
}

/// `GET /api/mobile/dreams/{id}` → `dream` (full). Steps are the synced rows;
/// metrics carry their computed readings.
final class DreamDetail with ValueEquality {
  const DreamDetail({
    required this.dream,
    this.steps = const [],
    this.metrics = const [],
    this.progress = const DreamProgressView(),
    this.cost = const DreamCost(),
    this.stale = false,
    this.overdue = false,
    this.reviewReasons = const [],
    this.lastActivityAt,
  });

  final Dream dream;
  final List<DreamStep> steps;
  final List<DreamMetricView> metrics;
  final DreamProgressView progress;
  final DreamCost cost;
  final bool stale;
  final bool overdue;

  /// `stale`, `overdue` and `off_track` (open dreams only).
  final List<String> reviewReasons;
  final DateTime? lastActivityAt;

  @override
  List<Object?> get props => [
    dream,
    steps,
    metrics,
    progress,
    cost,
    stale,
    overdue,
    reviewReasons,
    lastActivityAt,
  ];
}

/// One row of a summary list (`active`, `nearest`, `offTrack`). Every field is
/// optional: the server sends the subset that applies.
final class DreamSummaryItem with ValueEquality {
  const DreamSummaryItem({
    required this.id,
    required this.title,
    this.pct,
    this.onTrack,
    this.target,
    this.precision,
    this.inDays,
    this.metric,
  });

  final String id;
  final String title;
  final int? pct;
  final bool? onTrack;
  final String? target;
  final String? precision;

  /// Days until the target date (negative = passed).
  final int? inDays;

  /// Metric label (off-track rows).
  final String? metric;

  @override
  List<Object?> get props => [
    id,
    title,
    pct,
    onTrack,
    target,
    precision,
    inDays,
    metric,
  ];
}

/// `{n, items, more}` list of the summary.
final class DreamSummaryList with ValueEquality {
  const DreamSummaryList({this.n = 0, this.items = const [], this.more = 0});
  final int n;
  final List<DreamSummaryItem> items;
  final int more;

  @override
  List<Object?> get props => [n, items, more];
}

/// `GET /api/mobile/dreams/summary` — the "start here" overview.
final class DreamSummary with ValueEquality {
  const DreamSummary({
    required this.date,
    this.total = 0,
    this.counts = const {},
    this.open = 0,
    this.estimatedCostOpen,
    this.stale = 0,
    this.overdue = 0,
    this.active = const DreamSummaryList(),
    this.nearest = const DreamSummaryList(),
    this.offTrack = const DreamSummaryList(),
  });

  /// Today in the requested time zone, `YYYY-MM-DD`.
  final String date;
  final int total;

  /// Dreams per status wire value.
  final Map<String, int> counts;
  final int open;
  final double? estimatedCostOpen;
  final int stale;
  final int overdue;
  final DreamSummaryList active;
  final DreamSummaryList nearest;
  final DreamSummaryList offTrack;

  @override
  List<Object?> get props => [
    date,
    total,
    counts,
    open,
    estimatedCostOpen,
    stale,
    overdue,
    active,
    nearest,
    offTrack,
  ];
}

/// Result of `POST …/metrics/{mid}/value`.
final class ManualValueResult with ValueEquality {
  const ManualValueResult({
    required this.metric,
    this.stepsCompleted = const [],
  });
  final DreamMetricView metric;

  /// Ids of the steps the reading completed.
  final List<String> stepsCompleted;

  @override
  List<Object?> get props => [metric, stepsCompleted];
}
