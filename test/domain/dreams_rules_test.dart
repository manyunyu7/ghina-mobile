// Pure rules of Dreams ("Mimpi"): the port of src/lib/dreams.ts (docs/dreams.md).
// All dreams, steps and metrics are invented ("Trip contoh ke Kota Sample").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/dreams_rules.dart';

final _t0 = DateTime.utc(2026, 10, 10, 3);
int _ms(DateTime d) => d.millisecondsSinceEpoch;
const _day = 86400000;

Dream _dream({
  String id = 'd1',
  String title = 'Trip contoh ke Kota Sample',
  DreamStatus status = DreamStatus.idea,
  String? targetDate,
  TargetPrecision precision = TargetPrecision.day,
  DateTime? updated,
  String category = 'other',
  double? costEstimate,
  int? progressManual,
}) => Dream(
  id: id,
  title: title,
  status: status,
  targetDate: targetDate,
  targetPrecision: precision,
  category: category,
  costEstimate: costEstimate,
  progressManual: progressManual,
  createdAt: _t0,
  updatedAt: updated ?? _t0,
);

DreamStep _step(
  String id, {
  bool done = false,
  double? cost,
  String? metricRef,
  double? atValue,
}) => DreamStep(
  id: id,
  dreamId: 'd1',
  title: 'Langkah contoh $id',
  done: done,
  cost: cost,
  metricRef: metricRef,
  atValue: atValue,
  createdAt: _t0,
  updatedAt: _t0,
);

void main() {
  group('flexible target dates', () {
    test('quarters in every spelling snap to the last day of the quarter', () {
      for (final (text, date) in [
        ('Q1 2027', '2027-03-31'),
        ('q4 2026', '2026-12-31'),
        ('kuartal 2 2027', '2027-06-30'),
        ('triwulan 3 2027', '2027-09-30'),
        ('Q2 27', '2027-06-30'),
        ('2027 Q3', '2027-09-30'),
      ]) {
        final r = parseFlexibleTarget(text);
        expect(r, isNotNull, reason: text);
        expect(r!.date, date, reason: text);
        expect(r.precision, TargetPrecision.quarter, reason: text);
      }
    });

    test('months, with leap years and both word orders', () {
      expect(parseFlexibleTarget('Januari 2027')!.date, '2027-01-31');
      expect(parseFlexibleTarget('Jan 2027')!.date, '2027-01-31');
      expect(parseFlexibleTarget('2027-01')!.date, '2027-01-31');
      expect(parseFlexibleTarget('Februari 2027')!.date, '2027-02-28');
      expect(parseFlexibleTarget('Februari 2028')!.date, '2028-02-29');
      expect(parseFlexibleTarget('2027 Mei')!.date, '2027-05-31');
      expect(
        parseFlexibleTarget('Januari 2027')!.precision,
        TargetPrecision.month,
      );
    });

    test('a bare year is the last day of that year', () {
      final r = parseFlexibleTarget('2027')!;
      expect(r.date, '2027-12-31');
      expect(r.precision, TargetPrecision.year);
    });

    test('a day in words or ISO keeps the day precision', () {
      final a = parseFlexibleTarget('15 Maret 2027')!;
      expect(a.date, '2027-03-15');
      expect(a.precision, TargetPrecision.day);
      expect(parseFlexibleTarget('2027-03-15')!.date, '2027-03-15');
      expect(
        parseFlexibleTarget('31 Februari 2027'),
        isNull,
        reason: 'not a real day',
      );
    });

    test('text that is not understood is null', () {
      for (final text in [
        '',
        '   ',
        'Q5 2027',
        'Foo 2027',
        '1899',
        '2027-13',
        'kemarin',
      ]) {
        expect(parseFlexibleTarget(text), isNull, reason: '"$text"');
      }
    });

    test(
      'formatting: quarter, month, year, day, and nothing without a date',
      () {
        expect(formatTarget('2027-03-31', TargetPrecision.quarter), 'Q1 2027');
        expect(
          formatTarget('2027-01-31', TargetPrecision.month),
          'Januari 2027',
        );
        expect(formatTarget('2027-12-31', TargetPrecision.year), '2027');
        expect(formatTarget('2027-03-15', TargetPrecision.day), '15 Mar 2027');
        expect(formatTarget(null), '');
        expect(formatTarget('bukan-tanggal'), '');
      },
    );

    test('snapping and period starts', () {
      expect(
        snapToPeriodEnd('2027-02-10', TargetPrecision.month),
        '2027-02-28',
      );
      expect(
        snapToPeriodEnd('2027-05-02', TargetPrecision.quarter),
        '2027-06-30',
      );
      expect(snapToPeriodEnd('2027-05-02', TargetPrecision.year), '2027-12-31');
      expect(periodStart('2027-05-02', TargetPrecision.quarter), '2027-04-01');
      expect(periodStart('2027-05-02', TargetPrecision.month), '2027-05-01');
      expect(periodStart('2027-05-02', TargetPrecision.year), '2027-01-01');
    });

    test('normalising a target: snapped full dates, text, none and errors', () {
      final q = normalizeDreamTarget('2027-02-10', TargetPrecision.quarter);
      expect(q.targetDate, '2027-03-31');
      expect(q.targetPrecision, TargetPrecision.quarter);
      final text = normalizeDreamTarget('Q1 2027', null);
      expect(text.targetDate, '2027-03-31');
      expect(text.targetPrecision, TargetPrecision.quarter);
      final none = normalizeDreamTarget('  ', TargetPrecision.month);
      expect(none.targetDate, isNull);
      expect(none.targetPrecision, TargetPrecision.day);
      expect(
        () => normalizeDreamTarget('bukan tanggal'),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.field,
            'field',
            'targetDate',
          ),
        ),
      );
    });

    test('days until a target, negative once passed', () {
      expect(daysUntilTarget('2026-12-31', '2026-10-10'), 82);
      expect(daysUntilTarget('2026-10-01', '2026-10-10'), -9);
      expect(daysUntilTarget(null, '2026-10-10'), isNull);
    });

    test('day arithmetic crosses months and leap days', () {
      expect(daysBetweenKeys('2026-10-10', '2026-12-31'), 82);
      expect(addDreamDays('2027-12-31', 1), '2028-01-01');
      expect(addDreamDays('2028-02-28', 1), '2028-02-29');
      expect(isDreamDateKey('2027-02-29'), isFalse);
      expect(isDreamDateKey('2028-02-29'), isTrue);
    });
  });

  group('statuses and terminal states', () {
    test('done and dropped are closed, everything else is open', () {
      for (final s in DreamStatus.values) {
        expect(
          s.isOpen,
          s != DreamStatus.done && s != DreamStatus.dropped,
          reason: s.wire,
        );
      }
    });

    test('unknown wire values read as idea', () {
      expect(DreamStatus.fromWire('entah'), DreamStatus.idea);
      expect(DreamStatus.fromWire('watching'), DreamStatus.watching);
    });
  });

  group('metric progress', () {
    test('the server example: weight 90 → 80 at 86.4 is 36%', () {
      expect(
        metricProgressPct(
          start: 90,
          target: 80,
          direction: MetricDirection.down,
          current: 86.4,
        ),
        36,
      );
    });

    test('reached is 100; no current value is null; no start is null', () {
      expect(
        metricProgressPct(
          start: 90,
          target: 80,
          direction: MetricDirection.down,
          current: 79,
        ),
        100,
      );
      expect(
        metricProgressPct(
          start: 0,
          target: 12000000,
          direction: MetricDirection.up,
          current: 12000000,
        ),
        100,
      );
      expect(
        metricProgressPct(
          start: 90,
          target: 80,
          direction: MetricDirection.down,
          current: null,
        ),
        isNull,
      );
      expect(
        metricProgressPct(
          start: null,
          target: 80,
          direction: MetricDirection.down,
          current: 85,
        ),
        isNull,
      );
    });

    test('start equal to target is 0 until reached; wrong side is 0', () {
      expect(
        metricProgressPct(
          start: 80,
          target: 80,
          direction: MetricDirection.down,
          current: 85,
        ),
        0,
      );
      // Counting up but the start is above the target: no travel is possible.
      expect(
        metricProgressPct(
          start: 90,
          target: 80,
          direction: MetricDirection.up,
          current: 75,
        ),
        0,
      );
    });

    test('progress is clamped to 0–100 and rounded', () {
      expect(
        metricProgressPct(
          start: 0,
          target: 3000000,
          direction: MetricDirection.up,
          current: 1000000,
        ),
        33,
      );
      expect(
        metricProgressPct(
          start: 0,
          target: 100,
          direction: MetricDirection.up,
          current: -20,
        ),
        0,
      );
    });

    test('a metric without startValue takes the default start', () {
      final r = computeMetric(
        const DreamMetricSpec(
          direction: MetricDirection.up,
          startValue: null,
          targetValue: 100,
        ),
        const DreamMetricSample(currentValue: 50, defaultStart: 0),
        _ms(_t0),
        '2026-10-10',
      );
      expect(r.progressPct, 50);
    });
  });

  group('trend and projection', () {
    test('a trend needs three readings spanning at least seven days', () {
      final now = _ms(_t0);
      expect(
        fitTrend([
          DreamTrendPoint(at: now - 9 * _day, value: 90),
          DreamTrendPoint(at: now - 8 * _day, value: 89),
        ], now),
        isNull,
        reason: 'two points',
      );
      expect(
        fitTrend([
          DreamTrendPoint(at: now - 3 * _day, value: 90),
          DreamTrendPoint(at: now - 2 * _day, value: 89),
          DreamTrendPoint(at: now - 1 * _day, value: 88),
        ], now),
        isNull,
        reason: 'three points but only three days',
      );
    });

    test('a steady drop projects the date the line reaches the target', () {
      final now = _ms(_t0);
      // 1 kg less per week; now at 86 → 80 is 6 weeks away.
      final points = [
        for (var w = 3; w >= 0; w--)
          DreamTrendPoint(at: now - w * 7 * _day, value: 86.0 + w),
      ];
      final date = projectDate(points, 80, MetricDirection.down, now);
      expect(date, '2026-11-21');
    });

    test('a trend moving away from the target has no projection', () {
      final now = _ms(_t0);
      final points = [
        for (var w = 3; w >= 0; w--)
          DreamTrendPoint(at: now - w * 7 * _day, value: 80.0 - w),
      ];
      expect(projectDate(points, 90, MetricDirection.down, now), isNull);
    });

    test(
      'a linear projection for a streak adds remaining days at the rate',
      () {
        expect(projectLinear(10, 30, 1, '2026-10-10'), '2026-10-30');
        expect(projectLinear(10, 30, 1 / 7, '2026-10-10'), '2027-02-27');
        expect(
          projectLinear(30, 30, 1, '2026-10-10'),
          isNull,
          reason: 'already there',
        );
        expect(projectLinear(10, 30, 0, '2026-10-10'), isNull);
      },
    );
  });

  group('computeMetric (on track, projection, unavailable)', () {
    final spec = DreamMetricSpec(
      direction: MetricDirection.down,
      startValue: 90,
      targetValue: 80,
      targetDate: '2027-06-30',
    );
    final now = _ms(_t0);

    test('no reading is unavailable no_data, nothing else', () {
      final r = computeMetric(
        spec,
        const DreamMetricSample(),
        now,
        '2026-10-10',
      );
      expect(r.unavailable, MetricUnavailable.noData);
      expect(r.currentValue, isNull);
      expect(r.onTrack, isNull);
    });

    test('a missing reference keeps its reason', () {
      final r = computeMetric(
        spec,
        const DreamMetricSample(unavailable: MetricUnavailable.missingRef),
        now,
        '2026-10-10',
      );
      expect(r.unavailable, MetricUnavailable.missingRef);
    });

    test('reached is on track', () {
      final r = computeMetric(
        spec,
        DreamMetricSample(currentValue: 79, currentAt: now),
        now,
        '2026-10-10',
      );
      expect(r.onTrack, isTrue);
      expect(r.progressPct, 100);
    });

    test('projected after the target date is off track', () {
      final points = [
        for (var w = 3; w >= 0; w--)
          DreamTrendPoint(at: now - w * 7 * _day, value: 86.0 + w * 0.1),
      ];
      final r = computeMetric(
        spec,
        DreamMetricSample(currentValue: 86, currentAt: now, points: points),
        now,
        '2026-10-10',
      );
      expect(r.projectedDate, isNotNull);
      expect(r.projectedDate!.compareTo('2027-06-30') > 0, isTrue);
      expect(r.onTrack, isFalse);
    });

    test('projected before the target date is on track', () {
      final points = [
        for (var w = 3; w >= 0; w--)
          DreamTrendPoint(at: now - w * 7 * _day, value: 86.0 + w),
      ];
      final r = computeMetric(
        spec,
        DreamMetricSample(currentValue: 86, currentAt: now, points: points),
        now,
        '2026-10-10',
      );
      expect(r.onTrack, isTrue);
    });

    test(
      'a passed target date unreached is off track, even without a trend',
      () {
        final r = computeMetric(
          DreamMetricSpec(
            direction: MetricDirection.down,
            startValue: 90,
            targetValue: 80,
            targetDate: '2026-09-30',
          ),
          DreamMetricSample(currentValue: 86, currentAt: now),
          now,
          '2026-10-10',
        );
        expect(r.onTrack, isFalse);
      },
    );

    test('the dream date is the fallback when the metric has none', () {
      final r = computeMetric(
        DreamMetricSpec(
          direction: MetricDirection.down,
          startValue: 90,
          targetValue: 80,
        ),
        DreamMetricSample(currentValue: 86, currentAt: now),
        now,
        '2026-10-10',
        fallbackTargetDate: '2026-09-30',
      );
      expect(r.onTrack, isFalse);
    });
  });

  group('steps', () {
    test('a step auto-completes when its metric crossed the threshold', () {
      final steps = [
        _step('crossed', metricRef: 'm1', atValue: 88),
        _step('not-yet', metricRef: 'm1', atValue: 80),
        _step('already', done: true, metricRef: 'm1', atValue: 88),
        _step('plain'),
      ];
      final ids = stepsToAutoComplete(steps, {
        'm1': (direction: MetricDirection.down, currentValue: 86.4),
      });
      expect(ids, ['crossed']);
    });

    test('progress counts done over total', () {
      final p = stepProgress([_step('a', done: true), _step('b'), _step('c')]);
      expect(p.done, 1);
      expect(p.total, 3);
    });
  });

  group('costs', () {
    test(
      'estimate versus the steps, the effective figure and the difference',
      () {
        final c = costTotals(3000000, [
          _step('a', cost: 100000, done: true),
          _step('b', cost: 500000),
          _step('c'),
        ]);
        expect(c.stepsTotal, 600000);
        expect(c.stepsDone, 100000);
        expect(c.stepsRemaining, 500000);
        expect(c.stepsWithCost, 2);
        expect(c.diff, 2400000);
        expect(c.effective, 3000000, reason: 'the estimate wins');
      },
    );

    test('without an estimate the effective cost is the steps sum', () {
      final c = costTotals(null, [
        _step('a', cost: 250000),
        _step('b', cost: 0.1),
      ]);
      expect(c.effective, 250000.1);
      expect(c.diff, isNull);
    });

    test('no cost at all is null everywhere', () {
      final c = costTotals(null, [_step('a')]);
      expect(c.effective, isNull);
      expect(c.stepsWithCost, 0);
    });

    test('open dreams add up; done and dropped are left out', () {
      final dreams = [
        _dream(id: 'a', costEstimate: 1000000),
        _dream(id: 'b', status: DreamStatus.done, costEstimate: 999),
        _dream(id: 'c', status: DreamStatus.dropped, costEstimate: 888),
        _dream(id: 'd'),
      ];
      final sum = estimatedCostOpen(
        dreams,
        (d) => d.id == 'd' ? [_step('x', cost: 250000)] : const [],
      );
      expect(sum, 1250000);
    });
  });

  group('dream progress', () {
    test('done is 100; a manual figure beats metrics and steps', () {
      final steps = [_step('a', done: true), _step('b')];
      final metric = const DreamMetricReading(progressPct: 40, onTrack: true);
      expect(
        dreamProgress(_dream(status: DreamStatus.done), steps, [metric]).pct,
        100,
      );
      expect(
        dreamProgress(_dream(progressManual: 70), steps, [metric]).pct,
        70,
      );
    });

    test(
      'otherwise the mean of the metrics, then done/total steps, then null',
      () {
        final steps = [
          _step('a', done: true),
          _step('b'),
          _step('c'),
          _step('d'),
        ];
        expect(
          dreamProgress(_dream(), steps, [
            const DreamMetricReading(progressPct: 30),
            const DreamMetricReading(progressPct: 60),
            const DreamMetricReading(),
          ]).pct,
          45,
        );
        expect(dreamProgress(_dream(), steps, const []).pct, 25);
        expect(dreamProgress(_dream(), const [], const []).pct, isNull);
      },
    );

    test(
      'on track is false if any metric is off track, true if some are on',
      () {
        expect(
          dreamProgress(_dream(), const [], [
            const DreamMetricReading(onTrack: true),
            const DreamMetricReading(onTrack: false),
          ]).onTrack,
          isFalse,
        );
        expect(
          dreamProgress(_dream(), const [], [
            const DreamMetricReading(onTrack: true),
            const DreamMetricReading(),
          ]).onTrack,
          isTrue,
        );
        expect(
          dreamProgress(_dream(), const [], [
            const DreamMetricReading(),
          ]).onTrack,
          isNull,
        );
      },
    );

    test('the projection is the latest unreached one', () {
      final p = dreamProgress(_dream(), const [], [
        const DreamMetricReading(projectedDate: '2027-01-10'),
        const DreamMetricReading(projectedDate: '2027-03-02'),
      ]);
      expect(p.projectedDate, '2027-03-02');
    });
  });

  group('staleness, overdue and review', () {
    final now = _ms(DateTime.utc(2026, 10, 10));

    test('stale after more than 60 days: exactly 60 is not yet stale', () {
      final last60 = now - 60 * _day;
      final last61 = now - 61 * _day;
      expect(isStaleDream(DreamStatus.active, last60, now), isFalse);
      expect(isStaleDream(DreamStatus.active, last61, now), isTrue);
    });

    test('closed dreams are never stale', () {
      final old = now - 400 * _day;
      expect(isStaleDream(DreamStatus.done, old, now), isFalse);
      expect(isStaleDream(DreamStatus.dropped, old, now), isFalse);
    });

    test(
      'overdue only when the target is before today and the dream is open',
      () {
        expect(
          isOverdueDream(DreamStatus.active, '2026-10-09', '2026-10-10'),
          isTrue,
        );
        expect(
          isOverdueDream(DreamStatus.active, '2026-10-10', '2026-10-10'),
          isFalse,
          reason: 'due today is not overdue',
        );
        expect(
          isOverdueDream(DreamStatus.done, '2026-10-01', '2026-10-10'),
          isFalse,
        );
        expect(isOverdueDream(DreamStatus.idea, null, '2026-10-10'), isFalse);
      },
    );

    test(
      'review reasons collect stale, overdue and off track for open dreams',
      () {
        expect(
          reviewReasons(
            status: DreamStatus.waiting,
            targetDate: '2026-09-01',
            stale: true,
            onTrack: false,
            today: '2026-10-10',
          ).map((r) => r.wire),
          ['stale', 'overdue', 'off_track'],
        );
        expect(
          reviewReasons(
            status: DreamStatus.done,
            targetDate: '2026-09-01',
            stale: true,
            onTrack: false,
            today: '2026-10-10',
          ),
          isEmpty,
        );
      },
    );

    test('last activity is the latest timestamp, zero when none', () {
      expect(
        lastActivityMs([
          null,
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 5, 1),
        ]),
        _ms(DateTime.utc(2026, 5, 1)),
      );
      expect(lastActivityMs([null, null]), 0);
    });
  });

  group('due filter', () {
    final dreams = [
      _dream(id: 'late', status: DreamStatus.active, targetDate: '2026-09-30'),
      _dream(id: 'soon', status: DreamStatus.planned, targetDate: '2026-12-31'),
      _dream(id: 'far', status: DreamStatus.planned, targetDate: '2028-01-31'),
      _dream(id: 'closed', status: DreamStatus.done, targetDate: '2026-09-01'),
      _dream(id: 'undated'),
    ];
    List<String> run(String due) {
      final f = dreamDueFilter(due);
      return [
        for (final d in dreams)
          if (f(d, '2026-10-10')) d.id,
      ];
    }

    test('overdue, soon, a year and a month range', () {
      expect(run('overdue'), ['late']);
      expect(run('soon'), ['soon'], reason: 'within 90 days, open');
      expect(run('2027'), isEmpty);
      expect(run('2028'), ['far']);
      expect(run('2026-12'), ['soon']);
      expect(run('2026-12..2028-01'), ['soon', 'far']);
    });

    test('anything else is a validation failure', () {
      expect(
        () => dreamDueFilter('bulan lalu'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('hierarchy', () {
    test('a parent loop is detected, a plain chain is not', () {
      final parentOf = <String, String?>{'a': 'b', 'b': null};
      expect(
        wouldCreateDreamCycle('b', 'a', parentOf),
        isTrue,
        reason: 'a is b\'s child already',
      );
      expect(wouldCreateDreamCycle('c', 'a', parentOf), isFalse);
      expect(wouldCreateDreamCycle('c', null, parentOf), isFalse);
    });
  });

  group('validation (mirrors the server limits)', () {
    DreamInput input({
      String title = 'Trip contoh ke Kota Sample',
      String? why,
      String? condition,
      String? summary,
      int? priority,
      int? progress,
      double? cost,
      List<String> tags = const [],
      String category = 'other',
      Map<String, Object?> fields = const {},
      String? targetDate,
      TargetPrecision? precision,
      String? startedAt,
    }) => DreamInput(
      title: title,
      why: why,
      condition: condition,
      summary: summary,
      priority: priority,
      progressManual: progress,
      costEstimate: cost,
      tags: tags,
      category: category,
      fields: fields,
      targetDate: targetDate,
      targetPrecision: precision,
      startedAt: startedAt,
    );

    Dream build(DreamInput i, {List<DreamFieldDef> defs = const []}) =>
        validateDream(
          id: 'd1',
          input: i,
          categoryKeys: const ['travel'],
          defs: defs,
          createdAt: _t0,
          updatedAt: _t0,
        );

    void rejects(DreamInput i, {String? field}) {
      expect(
        () => build(i),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.field,
            'field',
            field ?? isNotNull,
          ),
        ),
      );
    }

    test('a valid dream keeps its values and gets the snapped target', () {
      final d = build(
        input(
          targetDate: 'Q2 2027',
          priority: 2,
          cost: 3000000,
          tags: const ['sehat', 'SEHAT', ' rutin '],
          category: 'travel',
        ),
      );
      expect(d.targetDate, '2027-06-30');
      expect(d.targetPrecision, TargetPrecision.quarter);
      expect(d.tags, ['sehat', 'rutin'], reason: 'deduped, trimmed');
      expect(d.category, 'travel');
    });

    test('title: 1 to 160 characters', () {
      expect(build(input(title: 'x' * 160)).title.length, 160);
      rejects(input(title: '   '), field: 'title');
      rejects(input(title: 'x' * 161), field: 'title');
    });

    test('why and summary up to 1000, condition up to 300', () {
      build(input(why: 'x' * 1000, summary: 'y' * 1000, condition: 'z' * 300));
      rejects(input(why: 'x' * 1001), field: 'why');
      rejects(input(summary: 'x' * 1001), field: 'summary');
      rejects(input(condition: 'x' * 301), field: 'condition');
    });

    test('priority 1 to 5 only', () {
      build(input(priority: 1));
      build(input(priority: 5));
      rejects(input(priority: 0), field: 'priority');
      rejects(input(priority: 6), field: 'priority');
    });

    test('manual progress 0 to 100 only', () {
      build(input(progress: 100));
      rejects(input(progress: 101), field: 'progressManual');
      rejects(input(progress: -1), field: 'progressManual');
    });

    test('costs are never negative', () {
      rejects(input(cost: -1), field: 'costEstimate');
      build(input(cost: 0));
    });

    test('tags: at most 20, each at most 40 characters', () {
      build(input(tags: [for (var i = 0; i < 20; i++) 'tag$i']));
      rejects(
        input(tags: [for (var i = 0; i < 21; i++) 'tag$i']),
        field: 'tags',
      );
      rejects(input(tags: ['x' * 41]), field: 'tags');
    });

    test('an unknown category is rejected, other always passes', () {
      rejects(input(category: 'kota-sample'), field: 'category');
      build(input(category: 'other'));
    });

    test('started and completed dates must be real day keys', () {
      build(input(startedAt: '2026-10-10'));
      rejects(input(startedAt: '2026-02-30'), field: 'startedAt');
    });

    test('custom fields must have a def and fit its type', () {
      final defs = [
        DreamFieldDef(
          id: 'df1',
          key: 'sumber_contoh',
          label: 'Sumber contoh',
          createdAt: _t0,
          updatedAt: _t0,
        ),
        DreamFieldDef(
          id: 'df2',
          key: 'skor',
          label: 'Skor',
          type: DreamFieldType.number,
          createdAt: _t0,
          updatedAt: _t0,
        ),
        DreamFieldDef(
          id: 'df3',
          key: 'pilihan',
          label: 'Pilihan',
          type: DreamFieldType.select,
          options: const ['A', 'B'],
          createdAt: _t0,
          updatedAt: _t0,
        ),
      ];
      final d = build(
        input(
          fields: {'sumber_contoh': 'daftar-1', 'skor': 4, 'pilihan': null},
        ),
        defs: defs,
      );
      expect(d.fields, {'sumber_contoh': 'daftar-1', 'skor': 4});
      expect(
        () => build(input(fields: {'skor': 'empat'}), defs: defs),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => build(input(fields: {'tidak_ada': 1}), defs: defs),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => build(input(fields: {'pilihan': 'C'}), defs: defs),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a step: metric and threshold go together, title up to 200', () {
      final s = validateDreamStep(
        id: 's1',
        dreamId: 'd1',
        input: const DreamStepInput(
          title: 'Capai 88 kg contoh',
          metricRef: 'm1',
          atValue: 88,
        ),
        now: _t0,
      );
      expect(s.atValue, 88);
      expect(
        () => validateDreamStep(
          id: 's1',
          dreamId: 'd1',
          input: const DreamStepInput(title: 'x', metricRef: 'm1'),
          now: _t0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateDreamStep(
          id: 's1',
          dreamId: 'd1',
          input: DreamStepInput(title: 'x' * 201),
          now: _t0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'a done step is stamped now; an earlier stamp is kept; undone has none',
      () {
        final now = DateTime.utc(2026, 10, 10, 9);
        final earlier = DateTime.utc(2026, 10, 1);
        expect(
          validateDreamStep(
            id: 's1',
            dreamId: 'd1',
            input: const DreamStepInput(title: 'a', done: true),
            now: now,
          ).doneAt,
          now,
        );
        expect(
          validateDreamStep(
            id: 's1',
            dreamId: 'd1',
            input: const DreamStepInput(title: 'a', done: true),
            now: now,
            previousDoneAt: earlier,
          ).doneAt,
          earlier,
        );
        expect(
          validateDreamStep(
            id: 's1',
            dreamId: 'd1',
            input: const DreamStepInput(title: 'a'),
            now: now,
          ).doneAt,
          isNull,
        );
      },
    );

    test('a metric: the source needs its id; spend defaults to month', () {
      expect(
        () => validateDreamMetric(
          id: 'm1',
          dreamId: 'd1',
          input: const DreamMetricInput(
            label: 'Kebiasaan contoh',
            source: MetricSource.habitCleanDays,
            targetValue: 30,
          ),
          now: _t0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      final m = validateDreamMetric(
        id: 'm2',
        dreamId: 'd1',
        input: const DreamMetricInput(
          label: 'Pengeluaran contoh',
          source: MetricSource.spendCategory,
          sourceRef: {'categoryId': 'c1'},
          targetValue: 1000000,
        ),
        now: _t0,
      );
      expect(m.sourceRef, {'categoryId': 'c1', 'period': 'month'});
      expect(m.effectiveDirection, MetricDirection.up);
    });

    test('manual readings only for manual metrics; the reading is stamped', () {
      final now = DateTime.utc(2026, 10, 10, 9);
      final m = validateDreamMetric(
        id: 'm3',
        dreamId: 'd1',
        input: const DreamMetricInput(
          label: 'Dana darurat contoh',
          source: MetricSource.manual,
          targetValue: 12000000,
          manualValue: 4800000,
        ),
        now: now,
      );
      expect(m.manualAt, now);
      expect(
        () => validateDreamMetric(
          id: 'm4',
          dreamId: 'd1',
          input: const DreamMetricInput(
            label: 'Berat contoh',
            source: MetricSource.weight,
            targetValue: 80,
            manualValue: 86,
          ),
          now: now,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a metric without a start derives its direction from the target', () {
      final down = validateDreamMetric(
        id: 'm5',
        dreamId: 'd1',
        input: const DreamMetricInput(
          label: 'Berat contoh',
          source: MetricSource.weight,
          startValue: 90,
          targetValue: 80,
        ),
        now: _t0,
      );
      expect(down.effectiveDirection, MetricDirection.down);
      final up = validateDreamMetric(
        id: 'm6',
        dreamId: 'd1',
        input: const DreamMetricInput(
          label: 'Tabungan contoh',
          source: MetricSource.manual,
          startValue: 0,
          targetValue: 100,
        ),
        now: _t0,
      );
      expect(up.effectiveDirection, MetricDirection.up);
    });

    test(
      'a category key must match the slug rule and the labels stay short',
      () {
        final c = validateDreamCategoryFields(
          key: 'kota_contoh',
          label: 'Kota contoh',
          emoji: '🏙️',
        );
        expect(c.key, 'kota_contoh');
        expect(
          () => validateDreamCategoryFields(
            key: 'Kota',
            label: 'x',
            emoji: '🏙️',
          ),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test('a select field needs options', () {
      expect(
        () => validateDreamFieldFields(
          key: 'pilihan',
          label: 'Pilihan',
          type: DreamFieldType.select,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      final f = validateDreamFieldFields(
        key: 'pilihan',
        label: 'Pilihan',
        type: DreamFieldType.select,
        options: const ['A', ' ', 'B'],
      );
      expect(f.options, ['A', 'B']);
    });
  });

  group('lists', () {
    test('the list order is sortOrder, nearest target first, undated last', () {
      final a = _dream(id: 'a', targetDate: '2027-03-31');
      final b = _dream(id: 'b', targetDate: '2026-12-31');
      final c = _dream(id: 'c');
      final sorted = [c, a, b]..sort(compareDreamsForList);
      expect(sorted.map((d) => d.id), ['b', 'a', 'c']);
    });

    test('the board groups every status in declared order', () {
      final board = groupDreamsByStatus([
        _dream(id: 'a', status: DreamStatus.active),
        _dream(id: 'b'),
      ]);
      expect(board.keys, DreamStatus.values);
      expect(board[DreamStatus.active]!.map((d) => d.id), ['a']);
      expect(board[DreamStatus.done], isEmpty);
    });

    test(
      'categories follow their sort order; unknown keys fall back to other',
      () {
        final groups = groupDreamsByCategory(
          [
            _dream(id: 'a', category: 'travel'),
            _dream(id: 'b', category: 'hilang'),
            _dream(id: 'c', category: 'other'),
          ],
          [
            DreamCategory(
              id: 'x',
              key: 'other',
              label: 'Lainnya',
              emoji: '✨',
              sortOrder: 11,
              createdAt: _t0,
              updatedAt: _t0,
            ),
            DreamCategory(
              id: 'y',
              key: 'travel',
              label: 'Perjalanan',
              emoji: '✈️',
              sortOrder: 1,
              createdAt: _t0,
              updatedAt: _t0,
            ),
          ],
        );
        expect(groups.map((g) => g.key), ['travel', 'other']);
        expect(
          groups.last.dreams.map((d) => d.id),
          unorderedEquals(['b', 'c']),
        );
      },
    );

    test('timeline buckets: horizon, quarter, year, undated', () {
      expect(
        timelineKey(
          horizon: null,
          targetDate: '2027-03-31',
          precision: TargetPrecision.quarter,
        ),
        '2027-Q1',
      );
      expect(
        timelineKey(
          horizon: null,
          targetDate: '2027-12-31',
          precision: TargetPrecision.year,
        ),
        '2027',
      );
      expect(
        timelineKey(
          horizon: DreamHorizon.someday,
          targetDate: null,
          precision: TargetPrecision.day,
        ),
        'someday',
      );
      expect(
        timelineKey(
          horizon: null,
          targetDate: null,
          precision: TargetPrecision.day,
        ),
        'undated',
      );
    });
  });
}
