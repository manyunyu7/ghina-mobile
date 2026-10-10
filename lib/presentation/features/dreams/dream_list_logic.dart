/// Pure logic of the Mimpi list screens (no Flutter): one [DreamRow] per dream
/// with what the device can tell (cost, checklist progress, staleness, the
/// review tag), the filters and search, the sorts, the board columns, the table
/// order and the timeline groups. Everything here works offline; the computed
/// metric values (on track, metric progress) come from the detail screen.
library;

import '../../../core/dates.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';

/// Tag that asks for a look in "Segarkan" (the user's own convention; the web
/// has no such tag, the review also lists every stale dream).
const dreamReviewTag = 'perlu-ditinjau';

/// The three views of the list screen.
enum DreamView {
  board('Papan'),
  table('Tabel'),
  timeline('Garis waktu');

  const DreamView(this.label);
  final String label;
}

/// Sort of the table view.
enum DreamSort {
  list('Urutan daftar'),
  target('Target terdekat'),
  priority('Prioritas'),
  status('Status'),
  cost('Biaya terbesar'),
  progress('Progres'),
  title('Nama (A–Z)');

  const DreamSort(this.label);
  final String label;
}

/// One dream plus what the device computes for it.
final class DreamRow {
  const DreamRow({
    required this.dream,
    required this.steps,
    required this.metrics,
    required this.cost,
    required this.progressPct,
    required this.lastActivityMs,
    required this.stale,
    required this.overdue,
    required this.tagged,
  });

  final Dream dream;
  final List<DreamStep> steps;
  final List<DreamMetric> metrics;
  final DreamCost cost;

  /// Manual progress, else the checklist's done share (metrics need the
  /// server). Null when neither is known.
  final int? progressPct;

  /// Epoch ms of the newest update of the dream, its steps, metrics and readings.
  final int lastActivityMs;
  final bool stale;
  final bool overdue;

  /// Carries [dreamReviewTag].
  final bool tagged;

  String get id => dream.id;

  /// An open dream that is stale or tagged for review.
  bool get needsReview => dream.status.isOpen && (stale || tagged);

  /// Effective cost of the dream (the estimate, else the steps' sum).
  double? get effectiveCost => cost.effective;
}

/// Builds the row of [d] from its local children at [nowMs] (`today` is the
/// local day key, `YYYY-MM-DD`).
DreamRow buildDreamRow(
  Dream d, {
  required List<DreamStep> steps,
  required List<DreamMetric> metrics,
  required int nowMs,
  required String today,
}) {
  final last = lastActivityMs([
    d.updatedAt,
    for (final s in steps) ...[s.updatedAt, s.doneAt],
    for (final m in metrics) ...[m.updatedAt, m.manualAt],
  ]);
  return DreamRow(
    dream: d,
    steps: steps,
    metrics: metrics,
    cost: costTotals(d.costEstimate, steps),
    progressPct: dreamProgress(d, steps, const []).pct,
    lastActivityMs: last,
    stale: isStaleDream(d.status, last, nowMs),
    overdue: isOverdueDream(d.status, d.targetDate, today),
    tagged: d.tags.any((t) => t.toLowerCase() == dreamReviewTag),
  );
}

/// Rows of every dream, in the repository's list order.
List<DreamRow> buildDreamRows({
  required Iterable<Dream> dreams,
  required Map<String, List<DreamStep>> stepsByDream,
  required Map<String, List<DreamMetric>> metricsByDream,
  required DateTime now,
}) {
  final nowMs = now.millisecondsSinceEpoch;
  final today = dateKey(now);
  return [
    for (final d in dreams)
      buildDreamRow(
        d,
        steps: stepsByDream[d.id] ?? const [],
        metrics: metricsByDream[d.id] ?? const [],
        nowMs: nowMs,
        today: today,
      ),
  ];
}

/// Normalises free text for search: trimmed, lower case, single spaces.
String normalizeDreamQuery(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [q] (already normalised) occurs in the title, why, condition, tags
/// or step titles of the dream.
bool dreamMatchesQuery(DreamRow r, String q) {
  if (q.isEmpty) return true;
  bool has(String? s) => s != null && s.toLowerCase().contains(q);
  final d = r.dream;
  return has(d.title) ||
      has(d.why) ||
      has(d.condition) ||
      d.tags.any(has) ||
      r.steps.any((s) => has(s.title));
}

/// The filters of the list. Null fields mean "any".
final class DreamFilter {
  const DreamFilter({
    this.query = '',
    this.category,
    this.status,
    this.tag,
    this.priority,
    this.onlyStale = false,
    this.onlyOverdue = false,
  });

  final String query;
  final String? category;
  final DreamStatus? status;
  final String? tag;
  final int? priority;

  /// "Basi": open and no update for [dreamStaleDays] days.
  final bool onlyStale;

  /// "Lewat target": open and the target date has passed.
  final bool onlyOverdue;

  static const none = DreamFilter();

  bool get isActive =>
      normalizeDreamQuery(query).isNotEmpty ||
      category != null ||
      status != null ||
      tag != null ||
      priority != null ||
      onlyStale ||
      onlyOverdue;

  DreamFilter copyWith({
    String? query,
    String? category,
    DreamStatus? status,
    String? tag,
    int? priority,
    bool? onlyStale,
    bool? onlyOverdue,
    bool clearCategory = false,
    bool clearStatus = false,
    bool clearTag = false,
    bool clearPriority = false,
  }) => DreamFilter(
    query: query ?? this.query,
    category: clearCategory ? null : (category ?? this.category),
    status: clearStatus ? null : (status ?? this.status),
    tag: clearTag ? null : (tag ?? this.tag),
    priority: clearPriority ? null : (priority ?? this.priority),
    onlyStale: onlyStale ?? this.onlyStale,
    onlyOverdue: onlyOverdue ?? this.onlyOverdue,
  );

  bool matches(DreamRow r) {
    final d = r.dream;
    if (category != null && d.category != category) return false;
    if (status != null && d.status != status) return false;
    if (tag != null &&
        !d.tags.any((t) => t.toLowerCase() == tag!.toLowerCase())) {
      return false;
    }
    if (priority != null && d.priority != priority) return false;
    if (onlyStale && !r.stale) return false;
    if (onlyOverdue && !r.overdue) return false;
    return dreamMatchesQuery(r, normalizeDreamQuery(query));
  }
}

/// The rows that pass [filter], in their order.
List<DreamRow> applyDreamFilter(Iterable<DreamRow> rows, DreamFilter filter) =>
    [
      for (final r in rows)
        if (filter.matches(r)) r,
    ];

/// Every tag in use, once each, case-insensitively, sorted.
List<String> allDreamTags(Iterable<DreamRow> rows) {
  final byLower = <String, String>{};
  for (final r in rows) {
    for (final t in r.dream.tags) {
      byLower.putIfAbsent(t.toLowerCase(), () => t);
    }
  }
  return byLower.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

int _listOrder(DreamRow a, DreamRow b) =>
    compareDreamsForList(a.dream, b.dream);

int _nullsLast(Comparable<dynamic>? a, Comparable<dynamic>? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

/// Rows sorted by [sort]; ties keep the list order.
List<DreamRow> sortDreamRows(Iterable<DreamRow> rows, DreamSort sort) {
  final out = [...rows];
  int cmp(DreamRow a, DreamRow b) {
    final c = switch (sort) {
      DreamSort.list => 0,
      DreamSort.target => _nullsLast(a.dream.targetDate, b.dream.targetDate),
      DreamSort.priority => _nullsLast(a.dream.priority, b.dream.priority),
      DreamSort.status => a.dream.status.index.compareTo(b.dream.status.index),
      DreamSort.cost => _nullsLast(
        a.effectiveCost == null ? null : -a.effectiveCost!,
        b.effectiveCost == null ? null : -b.effectiveCost!,
      ),
      DreamSort.progress => _nullsLast(
        a.progressPct == null ? null : -a.progressPct!,
        b.progressPct == null ? null : -b.progressPct!,
      ),
      DreamSort.title => a.dream.title.toLowerCase().compareTo(
        b.dream.title.toLowerCase(),
      ),
    };
    return c != 0 ? c : _listOrder(a, b);
  }

  out.sort(cmp);
  return out;
}

/// One board column: every status in its declared order, empty ones included.
final class DreamBoardColumn {
  const DreamBoardColumn(this.status, this.rows);
  final DreamStatus status;
  final List<DreamRow> rows;
}

List<DreamBoardColumn> boardColumns(Iterable<DreamRow> rows) {
  final all = [...rows]..sort(_listOrder);
  return [
    for (final s in DreamStatus.values)
      DreamBoardColumn(s, [
        for (final r in all)
          if (r.dream.status == s) r,
      ]),
  ];
}

/// One timeline section: a year, a quarter, a horizon or "undated".
final class DreamTimelineGroup {
  const DreamTimelineGroup({
    required this.key,
    required this.label,
    required this.rows,
  });

  final String key;
  final String label;
  final List<DreamRow> rows;
}

final _datedKey = RegExp(r'^\d{4}');

/// Human label of a [timelineKey] bucket.
String timelineLabel(String key) {
  if (_datedKey.hasMatch(key)) {
    final q = RegExp(r'^(\d{4})-Q([1-4])$').firstMatch(key);
    if (q != null) return 'Kuartal ${q[2]} ${q[1]}';
    return 'Tahun $key';
  }
  if (key == 'undated') return 'Tanpa tanggal';
  for (final h in DreamHorizon.values) {
    if (h.wire == key) return h.label;
  }
  return key;
}

/// Timeline sections: dated years and quarters first (nearest first), then
/// the horizon-only buckets in their declared order, undated last. Inside a
/// section the nearest target comes first.
List<DreamTimelineGroup> timelineGroups(Iterable<DreamRow> rows) {
  final buckets = <String, List<DreamRow>>{};
  for (final r in rows) {
    final d = r.dream;
    final key = timelineKey(
      horizon: d.horizon,
      targetDate: d.targetDate,
      precision: d.targetPrecision,
    );
    buckets.putIfAbsent(key, () => []).add(r);
  }

  int rank(String key) {
    if (_datedKey.hasMatch(key)) return 0;
    if (key == 'undated') return 2;
    return 1;
  }

  final keys = buckets.keys.toList()
    ..sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      if (rank(a) == 1) {
        final ia = DreamHorizon.values.indexWhere((h) => h.wire == a);
        final ib = DreamHorizon.values.indexWhere((h) => h.wire == b);
        return ia.compareTo(ib);
      }
      return a.compareTo(b);
    });
  return [
    for (final k in keys)
      DreamTimelineGroup(
        key: k,
        label: timelineLabel(k),
        rows: sortDreamRows(buckets[k]!, DreamSort.target),
      ),
  ];
}

/// Counts for the summary strip.
final class DreamStats {
  const DreamStats({
    required this.total,
    required this.counts,
    required this.open,
    required this.estimatedCostOpen,
    required this.stale,
    required this.overdue,
    required this.review,
  });

  final int total;
  final Map<DreamStatus, int> counts;

  /// Open dreams (not done, not dropped).
  final int open;

  /// Sum of the effective costs of the open dreams; null when none has one.
  final double? estimatedCostOpen;
  final int stale;
  final int overdue;

  /// Dreams for the "Segarkan" queue.
  final int review;
}

DreamStats dreamStats(Iterable<DreamRow> rows) {
  final list = [...rows];
  final counts = {for (final s in DreamStatus.values) s: 0};
  for (final r in list) {
    counts[r.dream.status] = counts[r.dream.status]! + 1;
  }
  final open = list.where((r) => r.dream.status.isOpen).toList();
  final byId = {for (final r in list) r.id: r};
  final sum = estimatedCostOpen(
    open.map((r) => r.dream),
    (d) => byId[d.id]?.steps ?? const [],
  );
  final hasCost = open.any((r) => r.effectiveCost != null);
  return DreamStats(
    total: list.length,
    counts: counts,
    open: open.length,
    estimatedCostOpen: hasCost ? sum : null,
    stale: list.where((r) => r.stale).length,
    overdue: list.where((r) => r.overdue).length,
    review: list.where((r) => r.needsReview).length,
  );
}

/// The "Segarkan" queue: open dreams that are stale or tagged, in list order.
List<DreamRow> reviewQueue(Iterable<DreamRow> rows) => [
  for (final r in rows)
    if (r.needsReview) r,
];
