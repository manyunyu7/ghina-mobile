import '../../domain/entities/entities.dart';

/// Defensive parser of `GET /api/mobile/habits/{id}/insights`: a missing or
/// mistyped key becomes an empty value, never an exception. Returns null when
/// [json] isn't an object at all.
HabitAnalysis? habitAnalysisFromWire(String habitId, Object? json) {
  if (json is! Map) return null;
  final window = _map(json['window']);
  final runs = _map(json['runs']);
  final relapses = _map(json['relapses']);
  return HabitAnalysis(
    habitId: _str(json['habitId']) ?? habitId,
    kind: _str(json['kind']) ?? 'build',
    from: _str(window['from']) ?? '',
    to: _str(window['to']) ?? '',
    days: _int(window['days']),
    current: _int(json['current']),
    longest: _int(json['longest']),
    unit: _str(json['unit']) ?? 'day',
    lastRelapse: _str(json['lastRelapse']),
    runCount: _int(runs['count']),
    longestRun: _run(runs['longest']),
    recentRuns: [for (final r in _list(runs['recent'])) ?_run(r)],
    relapseTotal: _int(relapses['total']),
    relapseDays: _int(relapses['days']),
    perMonth: _counts(relapses['perMonth'], sorted: true),
    weekday: _counts(relapses['weekday']),
    timeOfDay: _counts(relapses['timeOfDay']),
    riskWindows: [
      for (final w in _list(relapses['riskWindows']))
        if (w is Map && _str(w['from']) != null && _str(w['to']) != null)
          HabitRiskWindow(
            from: _str(w['from'])!,
            to: _str(w['to'])!,
            count: _int(w['count']),
            share: _dbl(w['share']) ?? 0,
          ),
    ],
    triggers: [
      for (final t in _list(json['triggers']))
        if (t is Map && _str(t['tag']) != null)
          HabitTriggerStat(
            tag: _str(t['tag'])!,
            count: _int(t['count']),
            share: _dbl(t['share']) ?? 0,
          ),
    ],
    dimensions: [
      for (final d in _list(json['dimensions']))
        if (d is Map && _str(d['key']) != null)
          HabitDimensionStat(
            key: _str(d['key'])!,
            label: _str(d['label']) ?? _str(d['key'])!,
            type: _str(d['type']) ?? 'number',
            lapse: _agg(d['lapse']),
            ok: _agg(d['ok']),
            comparable: d['comparable'] == true,
          ),
    ],
    lastEvents: [
      for (final e in _list(json['lastEvents']))
        if (e is Map && _str(e['label']) != null)
          HabitEventBrief(
            date: _str(e['date']) ?? '',
            kind: _str(e['kind']) ?? 'event',
            label: _str(e['label'])!,
            note: _str(e['note']),
          ),
    ],
  );
}

HabitRun? _run(Object? v) {
  if (v is! Map) return null;
  final start = _str(v['start']);
  final end = _str(v['end']);
  if (start == null || end == null) return null;
  return HabitRun(
    start: start,
    end: end,
    days: _int(v['days']),
    ongoing: v['ongoing'] == true,
  );
}

HabitDimensionAgg? _agg(Object? v) {
  if (v is! Map) return null;
  final opts = v['options'];
  return HabitDimensionAgg(
    n: _int(v['n']),
    avg: _dbl(v['avg']),
    trueShare: _dbl(v['trueShare']),
    options: opts is Map ? _counts(opts) : null,
  );
}

Map<String, Object?> _map(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': e.value} : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int _int(Object? v) => v is num && v.isFinite ? v.toInt() : 0;

double? _dbl(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

Map<String, int> _counts(Object? v, {bool sorted = false}) {
  if (v is! Map) return const {};
  final keys = [for (final k in v.keys) '$k'];
  if (sorted) keys.sort();
  return {for (final k in keys) k: _int(v[k])};
}
