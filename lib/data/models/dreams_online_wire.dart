/// Parsers of the online Dreams responses (`docs/dreams.md` → REST):
/// `GET /api/mobile/dreams/summary`, `GET /api/mobile/dreams/{id}` and
/// `POST …/metrics/{mid}/value`. The embedded rows reuse the sync parsers
/// (`dreams_wire.dart`); the computed values (progress, metric readings,
/// on-track, projections, cost, review reasons) are read here.
///
/// Parsing is defensive: unknown keys are ignored, missing optional values
/// become null / zero / empty, and a response without its core object is
/// `null` (the repository turns that into an `UnknownFailure`).
library;

import '../../domain/entities/entities.dart';
import 'dreams_wire.dart';
import 'wire.dart' show Json;

Object? _get(Object? m, String k) => m is Map ? m[k] : null;

String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int? _i(Object? v) => v is num && v.isFinite ? v.round() : null;
bool? _b(Object? v) => v is bool ? v : null;
DateTime? _t(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, Object?>? _map(Object? v) => v is Map
    ? {
        for (final e in v.entries)
          if (e.key is String) e.key as String: e.value,
      }
    : null;

List<Map<String, Object?>> _rows(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) _map(e)!,
      ]
    : const [];

// ---------------------------------------------------------------- summary

DreamSummaryItem? _summaryItem(Map<String, Object?> j) {
  final id = _s(j['id']);
  if (id == null) return null;
  return DreamSummaryItem(
    id: id,
    title: _s(j['title']) ?? '',
    pct: _i(j['pct']),
    onTrack: _b(j['onTrack']),
    target: _s(j['target']),
    precision: _s(j['precision']),
    inDays: _i(j['in']),
    metric: _s(j['metric']),
  );
}

DreamSummaryList _summaryList(Object? raw) {
  final m = _map(raw);
  if (m == null) return const DreamSummaryList();
  return DreamSummaryList(
    n: _i(m['n']) ?? 0,
    items: [for (final r in _rows(m['items'])) ?_summaryItem(r)],
    more: _i(m['more']) ?? 0,
  );
}

/// `GET /dreams/summary` → [DreamSummary]; null when there is no `date`.
DreamSummary? dreamSummaryFromWire(Json root) {
  final date = _s(root['date']);
  if (date == null) return null;
  final counts = _map(root['counts']) ?? const {};
  return DreamSummary(
    date: date,
    total: _i(root['total']) ?? 0,
    counts: {for (final e in counts.entries) e.key: ?_i(e.value)},
    open: _i(root['open']) ?? 0,
    estimatedCostOpen: _d(root['estimatedCostOpen']),
    stale: _i(root['stale']) ?? 0,
    overdue: _i(root['overdue']) ?? 0,
    active: _summaryList(root['active']),
    nearest: _summaryList(root['nearest']),
    offTrack: _summaryList(root['offTrack']),
  );
}

// ---------------------------------------------------------------- computed metric

/// The computed part of a metric object (`currentValue`, `progressPct`, …,
/// `history`).
DreamMetricReading _readingFromWire(Map<String, Object?> j) =>
    DreamMetricReading(
      currentValue: _d(j['currentValue']),
      currentAt: _t(j['currentAt']),
      progressPct: _i(j['progressPct']),
      onTrack: _b(j['onTrack']),
      projectedDate: _s(j['projectedDate']),
      unavailable: MetricUnavailable.tryFromWire(_s(j['unavailable'])),
      history: [
        for (final h in _rows(j['history']))
          if (_d(h['value']) case final v? when _t(h['at']) != null)
            MetricHistoryPoint(at: _t(h['at'])!, value: v),
      ],
    );

/// A metric row with its computed reading; null for an unknown source or a
/// row without an id.
DreamMetricView? dreamMetricViewFromWire(Map<String, Object?> j) {
  final metric = dreamMetricFromWire(j);
  if (metric == null) return null;
  return DreamMetricView(metric: metric, reading: _readingFromWire(j));
}

// ---------------------------------------------------------------- detail

DreamProgressView _progressFromWire(Object? raw) {
  final m = _map(raw);
  if (m == null) return const DreamProgressView();
  return DreamProgressView(
    pct: _i(m['pct']),
    onTrack: _b(m['onTrack']),
    projectedDate: _s(m['projectedDate']),
    metricCount: _i(m['metricCount']) ?? 0,
    stepsDone: _i(m['stepsDone']) ?? 0,
    stepsTotal: _i(m['stepsTotal']) ?? 0,
  );
}

DreamCost _costFromWire(Object? raw) {
  final m = _map(raw);
  if (m == null) return const DreamCost();
  return DreamCost(
    estimate: _d(m['estimate']),
    stepsTotal: _d(m['stepsTotal']) ?? 0,
    stepsDone: _d(m['stepsDone']) ?? 0,
    stepsRemaining: _d(m['stepsRemaining']) ?? 0,
    stepsWithCost: _i(m['stepsWithCost']) ?? 0,
    diff: _d(m['diff']),
    effective: _d(m['effective']),
  );
}

/// `GET /dreams/{id}` → `{dream}` → [DreamDetail]; null when there is no dream.
DreamDetail? dreamDetailFromWire(Json root) {
  final raw = _map(root['dream']);
  if (raw == null) return null;
  final dream = dreamFromWire(raw);
  if (dream == null) return null;
  return DreamDetail(
    dream: dream,
    steps: [for (final s in _rows(raw['steps'])) ?dreamStepFromWire(s)],
    metrics: [
      for (final m in _rows(raw['metrics'])) ?dreamMetricViewFromWire(m),
    ],
    progress: _progressFromWire(raw['progress']),
    cost: _costFromWire(raw['cost']),
    stale: _b(raw['stale']) ?? false,
    overdue: _b(raw['overdue']) ?? false,
    reviewReasons: [
      for (final r
          in (raw['reviewReasons'] is List
              ? raw['reviewReasons'] as List
              : const []))
        if (r is String) r,
    ],
    lastActivityAt: _t(raw['lastActivityAt']),
  );
}

// ---------------------------------------------------------------- manual value

/// `POST …/metrics/{mid}/value` → `{metric, progress, stepsCompleted}`; null
/// when the metric is missing or unreadable.
ManualValueResult? manualValueResultFromWire(Json root) {
  final metric = _map(_get(root, 'metric'));
  if (metric == null) return null;
  final view = dreamMetricViewFromWire(metric);
  if (view == null) return null;
  return ManualValueResult(
    metric: view,
    stepsCompleted: [
      for (final s
          in (root['stepsCompleted'] is List
              ? root['stepsCompleted'] as List
              : const []))
        if (s is String) s,
    ],
  );
}
