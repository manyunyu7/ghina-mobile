// Pure list logic of Mimpi: rows, filters, search, sorts, board, timeline and
// the summary counts. Invented data only ("Trip contoh ke Kota Sample").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dream_list_logic.dart';

final _now = DateTime(2026, 10, 10, 9);
const _today = '2026-10-10';

Dream _d(
  String id, {
  String title = 'Mimpi contoh',
  DreamStatus status = DreamStatus.idea,
  String? targetDate,
  TargetPrecision precision = TargetPrecision.day,
  DreamHorizon? horizon,
  String category = 'other',
  int? priority,
  List<String> tags = const [],
  String? why,
  String? condition,
  double? costEstimate,
  DateTime? updated,
}) => Dream(
  id: id,
  title: title,
  status: status,
  targetDate: targetDate,
  targetPrecision: precision,
  horizon: horizon,
  category: category,
  priority: priority,
  tags: tags,
  why: why,
  condition: condition,
  costEstimate: costEstimate,
  createdAt: _now,
  updatedAt: updated ?? _now,
);

DreamStep _s(
  String id,
  String dreamId,
  String title, {
  bool done = false,
  double? cost,
  DateTime? updated,
}) => DreamStep(
  id: id,
  dreamId: dreamId,
  title: title,
  done: done,
  doneAt: done ? _now : null,
  cost: cost,
  createdAt: _now,
  updatedAt: updated ?? _now,
);

DreamRow _row(
  Dream d, {
  List<DreamStep> steps = const [],
  DateTime? now,
}) => buildDreamRow(
  d,
  steps: steps,
  metrics: const [],
  nowMs: (now ?? _now).millisecondsSinceEpoch,
  today: _today,
);

void main() {
  group('buildDreamRow', () {
    test('an untouched open dream for more than 60 days is stale', () {
      final old = _now.subtract(const Duration(days: 61));
      final r = _row(_d('a', updated: old));
      expect(r.stale, isTrue);
      expect(r.needsReview, isTrue);
    });

    test('a recent step keeps the dream fresh', () {
      final old = _now.subtract(const Duration(days: 90));
      final step = DreamStep(
        id: 's1',
        dreamId: 'a',
        title: 'Langkah contoh',
        createdAt: _now,
        updatedAt: _now,
      );
      final r = _row(_d('a', updated: old), steps: [step]);
      expect(r.stale, isFalse);
    });

    test('done and dropped dreams are never stale or for review', () {
      final old = _now.subtract(const Duration(days: 200));
      for (final s in [DreamStatus.done, DreamStatus.dropped]) {
        final r = _row(_d('a', status: s, updated: old, tags: ['Perlu-Ditinjau']));
        expect(r.stale, isFalse, reason: s.wire);
        expect(r.needsReview, isFalse, reason: s.wire);
      }
    });

    test('the review tag is matched without case', () {
      final r = _row(_d('a', tags: ['Perlu-Ditinjau']));
      expect(r.tagged, isTrue);
      expect(r.needsReview, isTrue);
    });

    test('overdue: open and the target day has passed', () {
      expect(_row(_d('a', targetDate: '2026-10-09')).overdue, isTrue);
      expect(_row(_d('a', targetDate: '2026-10-10')).overdue, isFalse);
      expect(
        _row(_d('a', targetDate: '2026-01-01', status: DreamStatus.done))
            .overdue,
        isFalse,
      );
    });

    test('progress: manual wins, else the checklist share, else unknown', () {
      final steps = [
        _s('s1', 'a', 'Langkah contoh satu', done: true),
        _s('s2', 'a', 'Langkah contoh dua'),
      ];
      expect(_row(_d('a'), steps: steps).progressPct, 50);
      expect(_row(_d('a').copyWith(progressManual: 20), steps: steps)
          .progressPct, 20);
      expect(_row(_d('a')).progressPct, isNull);
    });

    test('effective cost: the estimate, else the steps sum', () {
      final steps = [
        _s('s1', 'a', 'Langkah contoh satu', cost: 100000),
        _s('s2', 'a', 'Langkah contoh dua', cost: 50000),
      ];
      expect(_row(_d('a'), steps: steps).effectiveCost, 150000);
      expect(
        _row(_d('a', costEstimate: 500000), steps: steps).effectiveCost,
        500000,
      );
      expect(_row(_d('a')).effectiveCost, isNull);
    });
  });

  group('filter and search', () {
    final rows = [
      _row(
        _d(
          'a',
          title: 'Trip contoh ke Kota Sample',
          category: 'travel',
          status: DreamStatus.planned,
          priority: 2,
          tags: const ['liburan'],
          why: 'Lihat laut',
          updated: _now.subtract(const Duration(days: 80)),
        ),
        steps: [
          _s('s1', 'a', 'Pesan tiket contoh', updated: _now.subtract(const Duration(days: 80))),
        ],
      ),
      _row(
        _d(
          'b',
          title: 'Tabungan contoh',
          category: 'money',
          status: DreamStatus.active,
          priority: 1,
          condition: 'Tiap bulan',
          targetDate: '2026-09-30',
        ),
      ),
      _row(_d('c', title: 'Buku contoh', status: DreamStatus.done)),
    ];

    List<String> ids(DreamFilter f) =>
        [for (final r in applyDreamFilter(rows, f)) r.id];

    test('an empty filter keeps every row', () {
      expect(ids(DreamFilter.none), ['a', 'b', 'c']);
      expect(DreamFilter.none.isActive, isFalse);
    });

    test('search covers title, why, condition, tags and step titles', () {
      expect(ids(const DreamFilter(query: 'KOTA')), ['a']);
      expect(ids(const DreamFilter(query: 'laut')), ['a']);
      expect(ids(const DreamFilter(query: 'tiap   bulan')), ['b']);
      expect(ids(const DreamFilter(query: 'liburan')), ['a']);
      expect(ids(const DreamFilter(query: 'tiket')), ['a']);
      expect(ids(const DreamFilter(query: 'xyzzy')), isEmpty);
    });

    test('category, status, tag and priority filters', () {
      expect(ids(const DreamFilter(category: 'money')), ['b']);
      expect(ids(const DreamFilter(status: DreamStatus.done)), ['c']);
      expect(ids(const DreamFilter(tag: 'Liburan')), ['a']);
      expect(ids(const DreamFilter(priority: 1)), ['b']);
    });

    test('basi (stale) and lewat target (overdue)', () {
      expect(ids(const DreamFilter(onlyStale: true)), ['a']);
      expect(ids(const DreamFilter(onlyOverdue: true)), ['b']);
    });

    test('filters combine', () {
      expect(
        ids(const DreamFilter(status: DreamStatus.planned, priority: 1)),
        isEmpty,
      );
      expect(
        ids(const DreamFilter(category: 'travel', query: 'contoh')),
        ['a'],
      );
    });

    test('allDreamTags is unique, case-insensitive and sorted', () {
      final tagged = [
        _row(_d('x', tags: const ['Zeta', 'alfa'])),
        _row(_d('y', tags: const ['ALFA', 'beta'])),
      ];
      expect(allDreamTags(tagged), ['alfa', 'beta', 'Zeta']);
    });
  });

  group('sorts', () {
    final rows = [
      _row(_d('a', title: 'Buku contoh', targetDate: '2028-01-31', priority: 3)),
      _row(_d('b', title: 'Apel contoh', targetDate: '2027-06-30', priority: 1)),
      _row(_d('c', title: 'Cermin contoh', priority: 2)),
    ];

    test('target: nearest first, undated last', () {
      expect([
        for (final r in sortDreamRows(rows, DreamSort.target)) r.id,
      ], ['b', 'a', 'c']);
    });

    test('priority: 1 first, unset last', () {
      expect([
        for (final r in sortDreamRows(rows, DreamSort.priority)) r.id,
      ], ['b', 'c', 'a']);
    });

    test('title: A to Z', () {
      expect([
        for (final r in sortDreamRows(rows, DreamSort.title)) r.id,
      ], ['b', 'a', 'c']);
    });

    test('cost: biggest effective cost first, unknown last', () {
      final costed = [
        _row(_d('p', costEstimate: 100000)),
        _row(_d('q')),
        _row(_d('r', costEstimate: 900000)),
      ];
      expect([
        for (final r in sortDreamRows(costed, DreamSort.cost)) r.id,
      ], ['r', 'p', 'q']);
    });
  });

  group('board and timeline', () {
    test('the board has every status, empty columns included', () {
      final cols = boardColumns([
        _row(_d('a', status: DreamStatus.active)),
        _row(_d('b', status: DreamStatus.active)),
      ]);
      expect(cols.map((c) => c.status), DreamStatus.values);
      expect(cols.firstWhere((c) => c.status == DreamStatus.active).rows.length,
          2);
      expect(cols.firstWhere((c) => c.status == DreamStatus.idea).rows, isEmpty);
    });

    test('timeline: years, quarters, horizons, then undated last', () {
      final groups = timelineGroups([
        _row(_d('u')),
        _row(_d('h', horizon: DreamHorizon.someday)),
        _row(_d('q', targetDate: '2027-03-31', precision: TargetPrecision.quarter)),
        _row(_d('y', targetDate: '2027-12-31', precision: TargetPrecision.year)),
        _row(_d('m', targetDate: '2026-11-30', precision: TargetPrecision.month)),
        _row(_d('q2', targetDate: '2027-02-28', precision: TargetPrecision.month)),
      ]);
      expect(groups.map((g) => g.key), [
        '2026-Q4',
        '2027',
        '2027-Q1',
        'someday',
        'undated',
      ]);
      expect(groups.first.label, 'Kuartal 4 2026');
      expect(groups[1].label, 'Tahun 2027');
      expect(groups.last.label, 'Tanpa tanggal');
    });

    test('a timeline section lists its nearest target first', () {
      final groups = timelineGroups([
        _row(_d('late', targetDate: '2027-03-31')),
        _row(_d('early', targetDate: '2027-01-31')),
      ]);
      expect(groups.single.rows.map((r) => r.id), ['early', 'late']);
    });
  });

  group('summary and review queue', () {
    final rows = [
      _row(_d('a', status: DreamStatus.active, costEstimate: 200000)),
      _row(_d('b', status: DreamStatus.done, costEstimate: 999999)),
      _row(
        _d(
          'c',
          status: DreamStatus.idea,
          updated: _now.subtract(const Duration(days: 70)),
        ),
      ),
      _row(_d('d', status: DreamStatus.planned, targetDate: '2026-10-01')),
      _row(_d('e', tags: const [dreamReviewTag])),
    ];

    test('counts per status, open, cost of open dreams, stale, overdue', () {
      final s = dreamStats(rows);
      expect(s.total, 5);
      expect(s.counts[DreamStatus.idea], 2);
      expect(s.counts[DreamStatus.done], 1);
      expect(s.open, 4);
      expect(s.estimatedCostOpen, 200000);
      expect(s.stale, 1);
      expect(s.overdue, 1);
      expect(s.review, 2);
    });

    test('no open cost means no total', () {
      expect(dreamStats([_row(_d('z'))]).estimatedCostOpen, isNull);
    });

    test('the review queue keeps list order', () {
      expect([for (final r in reviewQueue(rows)) r.id], ['c', 'e']);
    });
  });
}
