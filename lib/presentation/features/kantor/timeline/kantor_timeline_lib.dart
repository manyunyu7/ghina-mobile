/// Kantor timeline: pure scheduling logic, a port of the web `gantt.js`.
/// Days are integers (days since the epoch, UTC) so arithmetic stays simple.
library;

import '../board/kantor_board_lib.dart';

const kDayMs = 86400000;

const kZooms = <String, double>{
  'day': 42,
  'week': 16,
  'month': 5,
  'quarter': 1.7,
};
const kZoomNames = [
  ('day', 'Hari'),
  ('week', 'Minggu'),
  ('month', 'Bulan'),
  ('quarter', 'Kuartal'),
];
const kMonLong = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember', //
];
const kDowShort = ['M', 'S', 'S', 'R', 'K', 'J', 'S'];

int? ganttParse(String? s) {
  final d = kParseDay(s);
  return d == null
      ? null
      : DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ kDayMs;
}

String ganttFormat(int n) => DateTime.fromMillisecondsSinceEpoch(
  n * kDayMs,
  isUtc: true,
).toIso8601String().substring(0, 10);

/// 0 = Sunday.
int ganttDow(int n) => (((n + 4) % 7) + 7) % 7;
bool ganttWeekend(int n) => ganttDow(n) == 0 || ganttDow(n) == 6;

int ganttToday() {
  final d = DateTime.now();
  return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ kDayMs;
}

(int y, int m, int d) ganttYmd(int n) {
  final d = DateTime.fromMillisecondsSinceEpoch(n * kDayMs, isUtc: true);
  return (d.year, d.month - 1, d.day);
}

String ganttFmt(int n, {bool year = false}) {
  final (y, m, d) = ganttYmd(n);
  final showYear = year || y != ganttYmd(ganttToday()).$1;
  return '$d ${kMonShort[m]}${showYear ? ' $y' : ''}';
}

/// Last day of an n working-day task that starts on [s].
int ganttEndFrom(int s, int n) {
  var e = s, c = ganttWeekend(s) ? 0 : 1;
  while (c < n) {
    e++;
    if (!ganttWeekend(e)) c++;
  }
  return e;
}

int ganttStartTo(int e, int n) {
  var s = e, c = ganttWeekend(e) ? 0 : 1;
  while (c < n) {
    s--;
    if (!ganttWeekend(s)) c++;
  }
  return s;
}

class GSpan {
  const GSpan(this.s, this.e, {this.derived = false, this.milestone = false});
  final int s;
  final int e;

  /// One end was guessed from the estimate.
  final bool derived;
  final bool milestone;
}

/// Where a card sits in time; null when it has no dates at all.
GSpan? ganttSpan(KCard c, {GSpan? override}) {
  if (c.epic) return null;
  if (override != null) return override;
  var s = ganttParse(c.start);
  var e = ganttParse(c.due);
  if (c.milestone) {
    final d = e ?? s;
    return d == null ? null : GSpan(d, d, milestone: true);
  }
  if (s == null && e == null) return null;
  final n = (c.estDays ?? 2).ceil().clamp(1, 100000);
  var der = false;
  if (e == null) {
    e = ganttEndFrom(s!, n);
    der = true;
  } else if (s == null) {
    s = ganttStartTo(e, n);
    der = true;
  }
  if (e < s) e = s;
  return GSpan(s, e, derived: der);
}

int ganttProgress(KCard c) {
  if (c.progress != null) return c.progress!;
  if (c.checksTotal > 0) return (100 * c.checksDone / c.checksTotal).round();
  return c.done ? 100 : 0;
}

/// Dependency pairs whose schedule overlaps: `to` starts before `from` ends.
List<({String from, String to})> ganttConflicts(
  List<KCard> cards,
  Map<String, GSpan?> spans,
) {
  final map = {for (final c in cards) c.id: c};
  final out = <({String from, String to})>[];
  for (final c in cards) {
    final sp = spans[c.id];
    if (c.epic || sp == null || c.done) continue;
    for (final d in c.deps) {
      final ps = spans[d];
      if (map[d] != null && ps != null && sp.s <= ps.e)
        out.add((from: d, to: c.id));
    }
  }
  return out;
}

/// The longest dependency chain ending last (ids and "from>to" edges).
({Set<String> ids, Set<String> edges}) ganttCritical(
  List<KCard> cards,
  Map<String, GSpan?> spans,
) {
  final live = [
    for (final c in cards)
      if (!c.epic && spans[c.id] != null && !c.done) c,
  ];
  const none = (ids: <String>{}, edges: <String>{});
  if (live.length < 2) return none;
  final ids = {for (final c in live) c.id};
  final map = {for (final c in live) c.id: c};
  var cur = live.reduce((a, b) => spans[b.id]!.e > spans[a.id]!.e ? b : a);
  final chain = [cur.id];
  final edges = <String>{};
  for (var guard = 0; guard < 200; guard++) {
    final preds = [
      for (final d in cur.deps)
        if (ids.contains(d)) map[d]!,
    ];
    if (preds.isEmpty) break;
    final p = preds.reduce((a, b) => spans[b.id]!.e > spans[a.id]!.e ? b : a);
    edges.add('${p.id}>${cur.id}');
    chain.add(p.id);
    cur = p;
  }
  return chain.length < 2 ? none : (ids: chain.toSet(), edges: edges);
}

/// Days to push each open card later so no card starts before its deps end.
Map<String, int> ganttPlanShift(List<KCard> cards, Map<String, GSpan?> spans) {
  final sc = [
    for (final c in cards)
      if (!c.epic && spans[c.id] != null) c,
  ];
  final ids = {for (final c in sc) c.id};
  final map = {for (final c in sc) c.id: c};
  final order = <KCard>[];
  final seen = <String>{};
  void visit(KCard c) {
    if (!seen.add(c.id)) return;
    for (final d in c.deps) {
      if (ids.contains(d)) visit(map[d]!);
    }
    order.add(c);
  }

  sc.forEach(visit);
  final sh = <String, int>{};
  for (final c in order) {
    if (c.done) continue;
    final sp = spans[c.id]!;
    var need = 0;
    for (final d in c.deps) {
      if (!ids.contains(d)) continue;
      final pe = spans[d]!.e + (sh[d] ?? 0);
      if (pe + 1 - sp.s > need) need = pe + 1 - sp.s;
    }
    if (need > 0) sh[c.id] = need;
  }
  return sh;
}

/// A tier of the header: consecutive days sharing a key.
class GSeg {
  GSeg(this.key, this.from, this.to);
  final int key;
  final int from;
  int to;
}

List<GSeg> ganttSegs(int lo, int days, int Function(int day) keyOf) {
  final out = <GSeg>[];
  for (var d = lo; d < lo + days; d++) {
    final k = keyOf(d);
    if (out.isEmpty || out.last.key != k) {
      out.add(GSeg(k, d, d));
    } else {
      out.last.to = d;
    }
  }
  return out;
}
