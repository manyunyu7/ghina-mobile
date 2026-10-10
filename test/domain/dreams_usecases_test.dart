// Dreams use cases on in-memory repositories (test/domain/dreams_fakes.dart).
// Invented data only: "Trip contoh ke Kota Sample", "Mimpi contoh".
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'dreams_fakes.dart';
import 'fakes.dart' show FakeUnitOfWork;

void main() {
  // Local time on purpose: the status stamps use the local calendar day.
  late FixedClock clock;
  late FakeDreamRepository dreams;
  late FakeDreamStepRepository steps;
  late FakeDreamMetricRepository metrics;
  late FakeDreamCategoryRepository categories;
  late FakeDreamFieldRepository fields;
  late FakeDreamOnlineRepository online;
  late FakeUnitOfWork uow;

  setUp(() {
    clock = FixedClock(DateTime(2026, 10, 10, 9));
    steps = FakeDreamStepRepository();
    metrics = FakeDreamMetricRepository();
    dreams = FakeDreamRepository(steps: steps, metrics: metrics);
    categories = FakeDreamCategoryRepository();
    fields = FakeDreamFieldRepository();
    online = FakeDreamOnlineRepository();
    uow = FakeUnitOfWork();
  });

  DreamCategory category(String key, {String label = 'Kategori contoh'}) =>
      DreamCategory(
        id: 'dc-$key',
        key: key,
        label: label,
        emoji: '🌟',
        createdAt: clock.now(),
        updatedAt: clock.now(),
      );

  Future<void> seedCategories() async {
    await categories.save(category('other', label: 'Lainnya'));
    await categories.save(category('travel', label: 'Perjalanan'));
  }

  Future<Dream> seedDream(
    String id, {
    String title = 'Trip contoh ke Kota Sample',
    DreamStatus status = DreamStatus.idea,
    String? targetDate,
    String? parentId,
    DateTime? createdAt,
  }) async {
    final d = Dream(
      id: id,
      title: title,
      status: status,
      targetDate: targetDate,
      parentId: parentId,
      createdAt: createdAt ?? clock.now(),
      updatedAt: clock.now(),
    );
    await dreams.save(d);
    return d;
  }

  DreamInput input({
    String title = 'Trip contoh ke Kota Sample',
    String category = 'other',
    DreamStatus status = DreamStatus.idea,
    String? targetDate,
    String? parentId,
    Map<String, Object?> fields = const {},
  }) => DreamInput(
    title: title,
    category: category,
    status: status,
    targetDate: targetDate,
    parentId: parentId,
    fields: fields,
  );

  DreamStepInput stepInput(
    String title, {
    bool done = false,
    String? metricRef,
    double? atValue,
  }) => DreamStepInput(
    title: title,
    done: done,
    metricRef: metricRef,
    atValue: atValue,
  );

  group('creating and updating dreams', () {
    test('a new dream gets an id, the stamps and is stored', () async {
      await seedCategories();
      final r = await CreateDream(dreams, categories, fields, clock)(
        input(category: 'travel', targetDate: 'Q2 2027'),
      );
      expect(r.isOk, isTrue);
      final d = r.valueOrThrow;
      expect(d.id, isNotEmpty);
      expect(d.targetDate, '2027-06-30');
      expect(d.targetPrecision, TargetPrecision.quarter);
      expect(await dreams.getById(d.id), d);
    });

    test(
      'creating a done dream stamps completedAt; an active one startedAt',
      () async {
        await seedCategories();
        final done = (await CreateDream(dreams, categories, fields, clock)(
          input(status: DreamStatus.done),
        )).valueOrThrow;
        expect(done.completedAt, '2026-10-10');
        final active = (await CreateDream(dreams, categories, fields, clock)(
          input(status: DreamStatus.active),
        )).valueOrThrow;
        expect(active.startedAt, '2026-10-10');
        expect(active.completedAt, isNull);
      },
    );

    test('invalid input is a failure and nothing is stored', () async {
      await seedCategories();
      final r = await CreateDream(dreams, categories, fields, clock)(
        input(title: '   '),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
      expect(await dreams.getAll(), isEmpty);
    });

    test('an unknown category is refused; other always passes', () async {
      await seedCategories();
      final bad = await CreateDream(dreams, categories, fields, clock)(
        input(category: 'kota-sample'),
      );
      expect(bad.failureOrNull, isA<ValidationFailure>());
      final ok = await CreateDream(dreams, categories, fields, clock)(input());
      expect(ok.isOk, isTrue);
    });

    test('a parent must exist', () async {
      await seedCategories();
      final r = await CreateDream(dreams, categories, fields, clock)(
        input(parentId: 'tidak-ada'),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test('custom columns are checked against the defs', () async {
      await seedCategories();
      await fields.save(
        DreamFieldDef(
          id: 'df1',
          key: 'sumber_contoh',
          label: 'Sumber contoh',
          createdAt: clock.now(),
          updatedAt: clock.now(),
        ),
      );
      final ok = await CreateDream(dreams, categories, fields, clock)(
        input(fields: {'sumber_contoh': 'daftar-1'}),
      );
      expect(ok.valueOrThrow.fields, {'sumber_contoh': 'daftar-1'});
      final bad = await CreateDream(dreams, categories, fields, clock)(
        input(fields: {'belum_ada': 'x'}),
      );
      expect(bad.failureOrNull, isA<ValidationFailure>());
    });

    test('an update keeps createdAt and refuses a missing dream', () async {
      await seedCategories();
      final created = DateTime(2026, 1, 2);
      await seedDream('d1', createdAt: created);
      final r = await UpdateDream(dreams, categories, fields, clock)(
        'd1',
        input(title: 'Trip contoh ke Kota Sample (revisi)'),
      );
      expect(r.valueOrThrow.createdAt, created);
      expect(r.valueOrThrow.title, 'Trip contoh ke Kota Sample (revisi)');
      final missing = await UpdateDream(dreams, categories, fields, clock)(
        'tidak-ada',
        input(),
      );
      expect(missing.failureOrNull, isA<NotFoundFailure>());
    });

    test(
      'a parent loop is refused: a dream cannot be its own ancestor',
      () async {
        await seedCategories();
        await seedDream('a');
        await seedDream('b', parentId: 'a');
        final loop = await UpdateDream(dreams, categories, fields, clock)(
          'a',
          input(parentId: 'b'),
        );
        expect(loop.failureOrNull, isA<ValidationFailure>());
        final self = await UpdateDream(dreams, categories, fields, clock)(
          'a',
          input(parentId: 'a'),
        );
        expect(self.failureOrNull, isA<ValidationFailure>());
      },
    );
  });

  group('status stamps', () {
    test('becoming done stamps completedAt; leaving done clears it', () async {
      await seedCategories();
      await seedDream('d1', status: DreamStatus.active);
      final done = (await SetDreamStatus(dreams, clock)(
        'd1',
        DreamStatus.done,
      )).valueOrThrow;
      expect(done.completedAt, '2026-10-10');
      final back = (await SetDreamStatus(dreams, clock)(
        'd1',
        DreamStatus.waiting,
      )).valueOrThrow;
      expect(back.completedAt, isNull);
    });

    test(
      'becoming active sets startedAt once; it is kept afterwards',
      () async {
        await seedDream('d1', status: DreamStatus.idea);
        final active = (await SetDreamStatus(dreams, clock)(
          'd1',
          DreamStatus.active,
        )).valueOrThrow;
        expect(active.startedAt, '2026-10-10');
        clock.advance(const Duration(days: 5));
        final paused = (await SetDreamStatus(dreams, clock)(
          'd1',
          DreamStatus.paused,
        )).valueOrThrow;
        final again = (await SetDreamStatus(dreams, clock)(
          'd1',
          DreamStatus.active,
        )).valueOrThrow;
        expect(paused.startedAt, '2026-10-10');
        expect(
          again.startedAt,
          '2026-10-10',
          reason: 'the first start is kept',
        );
      },
    );

    test(
      'moving a dream to another category checks the category exists',
      () async {
        await seedCategories();
        await seedDream('d1');
        final ok = await MoveDreamCategory(dreams, categories, clock)(
          'd1',
          'travel',
        );
        expect(ok.valueOrThrow.category, 'travel');
        final bad = await MoveDreamCategory(dreams, categories, clock)(
          'd1',
          'kota-sample',
        );
        expect(bad.failureOrNull, isA<ValidationFailure>());
      },
    );

    test('deleting a dream removes its steps and metrics too', () async {
      await seedCategories();
      await seedDream('d1');
      await steps.save(
        DreamStep(
          id: 's1',
          dreamId: 'd1',
          title: 'Langkah contoh',
          createdAt: clock.now(),
          updatedAt: clock.now(),
        ),
      );
      await metrics.save(
        DreamMetric(
          id: 'm1',
          dreamId: 'd1',
          label: 'Tabungan contoh',
          source: MetricSource.manual,
          targetValue: 12000000,
          createdAt: clock.now(),
          updatedAt: clock.now(),
        ),
      );
      expect((await DeleteDream(dreams)('d1')).isOk, isTrue);
      expect(await steps.getForDream('d1'), isEmpty);
      expect(await metrics.getForDream('d1'), isEmpty);
    });
  });

  group('steps', () {
    setUp(() async {
      await seedCategories();
      await seedDream('d1');
    });

    test('a new step goes to the end of the checklist', () async {
      final a = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah pertama'),
      )).valueOrThrow;
      final b = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah kedua'),
      )).valueOrThrow;
      expect(a.sortOrder, 0);
      expect(b.sortOrder, 1);
    });

    test('an edit keeps the step\'s place and creation time', () async {
      final created = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah pertama'),
      )).valueOrThrow;
      clock.advance(const Duration(hours: 1));
      final edited = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        id: created.id,
        input: stepInput('Langkah pertama (revisi)'),
      )).valueOrThrow;
      expect(edited.sortOrder, created.sortOrder);
      expect(edited.createdAt, created.createdAt);
      expect(edited.title, 'Langkah pertama (revisi)');
    });

    test('at most 200 steps per dream', () async {
      for (var i = 0; i < 200; i++) {
        await steps.save(
          DreamStep(
            id: 's$i',
            dreamId: 'd1',
            title: 'Langkah $i',
            sortOrder: i,
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
      }
      final r = await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah ke-201'),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test('a step of another dream is not found', () async {
      await seedDream('d2');
      final mine = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah contoh'),
      )).valueOrThrow;
      final r = await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd2',
        id: mine.id,
        input: stepInput('Langkah contoh'),
      );
      expect(r.failureOrNull, isA<NotFoundFailure>());
    });

    test('a metric threshold needs its metric, both or neither', () async {
      final r = await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Capai 88 kg contoh', metricRef: 'm1'),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test('toggling stamps doneAt; toggling back clears it', () async {
      final s = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('Langkah contoh'),
      )).valueOrThrow;
      clock.advance(const Duration(minutes: 3));
      final done = (await ToggleDreamStep(steps, clock)(s.id)).valueOrThrow;
      expect(done.done, isTrue);
      expect(done.doneAt, clock.now());
      final undone = (await ToggleDreamStep(steps, clock)(s.id)).valueOrThrow;
      expect(undone.done, isFalse);
      expect(undone.doneAt, isNull);
    });

    test('a missing step cannot be toggled', () async {
      final r = await ToggleDreamStep(steps, clock)('tidak-ada');
      expect(r.failureOrNull, isA<NotFoundFailure>());
    });

    test('reordering sets the position of every step', () async {
      final a = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('A'),
      )).valueOrThrow;
      final b = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('B'),
      )).valueOrThrow;
      final r = await ReorderDreamSteps(steps, uow, clock)(
        dreamId: 'd1',
        orderedIds: [b.id, a.id],
      );
      expect(r.isOk, isTrue);
      expect(uow.runs, 1, reason: 'one transaction');
      expect((await steps.getById(b.id))!.sortOrder, 0);
      expect((await steps.getById(a.id))!.sortOrder, 1);
    });

    test('a reorder with a wrong set of ids changes nothing', () async {
      final a = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('A'),
      )).valueOrThrow;
      final r = await ReorderDreamSteps(steps, uow, clock)(
        dreamId: 'd1',
        orderedIds: [a.id, 'asing'],
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
      expect((await steps.getById(a.id))!.sortOrder, 0);
    });

    test('deleting a step removes it', () async {
      final a = (await SaveDreamStep(dreams, steps, clock)(
        dreamId: 'd1',
        input: stepInput('A'),
      )).valueOrThrow;
      expect((await DeleteDreamStep(steps)(a.id)).isOk, isTrue);
      expect(await steps.getById(a.id), isNull);
    });
  });

  group('metrics', () {
    setUp(() => seedDream('d1'));

    DreamMetricInput manual({double? value, DateTime? at}) => DreamMetricInput(
      label: 'Dana darurat contoh',
      source: MetricSource.manual,
      targetValue: 12000000,
      manualValue: value,
      manualAt: at,
    );

    test(
      'a metric is saved with its direction derived from start and target',
      () async {
        final m = (await SaveDreamMetric(dreams, metrics, clock)(
          dreamId: 'd1',
          input: const DreamMetricInput(
            label: 'Berat contoh',
            source: MetricSource.weight,
            startValue: 90,
            targetValue: 80,
          ),
        )).valueOrThrow;
        expect(m.effectiveDirection, MetricDirection.down);
      },
    );

    test('at most 20 metrics per dream', () async {
      for (var i = 0; i < 20; i++) {
        await metrics.save(
          DreamMetric(
            id: 'm$i',
            dreamId: 'd1',
            label: 'Metrik $i',
            source: MetricSource.manual,
            targetValue: 1,
            sortOrder: i,
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
      }
      final r = await SaveDreamMetric(dreams, metrics, clock)(
        dreamId: 'd1',
        input: manual(),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test('a manual reading is stored with its time, offline', () async {
      final m = (await SaveDreamMetric(dreams, metrics, clock)(
        dreamId: 'd1',
        input: manual(),
      )).valueOrThrow;
      final r = await RecordDreamManualValue(metrics, clock)(
        metricId: m.id,
        value: 4800000,
      );
      expect(r.valueOrThrow.manualValue, 4800000);
      expect(r.valueOrThrow.manualAt, clock.now());
    });

    test(
      'only manual metrics take a reading, not in the future or older than the last',
      () async {
        await metrics.save(
          DreamMetric(
            id: 'mw',
            dreamId: 'd1',
            label: 'Berat contoh',
            source: MetricSource.weight,
            targetValue: 80,
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
        final weight = await RecordDreamManualValue(metrics, clock)(
          metricId: 'mw',
          value: 86,
        );
        expect(weight.failureOrNull, isA<ValidationFailure>());

        final m = (await SaveDreamMetric(dreams, metrics, clock)(
          dreamId: 'd1',
          input: manual(value: 1000000, at: clock.now()),
        )).valueOrThrow;
        final future = await RecordDreamManualValue(metrics, clock)(
          metricId: m.id,
          value: 2000000,
          at: clock.now().add(const Duration(days: 1)),
        );
        expect(future.failureOrNull, isA<ValidationFailure>());
        final older = await RecordDreamManualValue(metrics, clock)(
          metricId: m.id,
          value: 2000000,
          at: clock.now().subtract(const Duration(days: 1)),
        );
        expect(older.failureOrNull, isA<ValidationFailure>());
      },
    );

    test('deleting a metric removes it', () async {
      final m = (await SaveDreamMetric(dreams, metrics, clock)(
        dreamId: 'd1',
        input: manual(),
      )).valueOrThrow;
      expect((await DeleteDreamMetric(metrics)(m.id)).isOk, isTrue);
      expect(await metrics.getById(m.id), isNull);
    });
  });

  group('categories and custom columns', () {
    test('a category key comes from its label and is unique', () async {
      final a = (await CreateDreamCategory(categories, clock)(
        label: 'Kota Contoh',
      )).valueOrThrow;
      final b = (await CreateDreamCategory(categories, clock)(
        label: 'Kota Contoh',
      )).valueOrThrow;
      expect(a.key, isNot(b.key));
      expect(a.key, startsWith('kota'));
      expect(b.sortOrder, greaterThan(a.sortOrder));
    });

    test(
      'renaming keeps the key; the other category cannot be deleted',
      () async {
        final other = category('other', label: 'Lainnya');
        await categories.save(other);
        final travel = category('travel', label: 'Perjalanan');
        await categories.save(travel);
        final renamed = (await UpdateDreamCategory(categories, clock)(
          id: travel.id,
          label: 'Jalan-jalan',
          emoji: '✈️',
        )).valueOrThrow;
        expect(renamed.key, 'travel');
        expect(renamed.label, 'Jalan-jalan');
        final cannot = await DeleteDreamCategory(categories)(other.id);
        expect(cannot.failureOrNull, isA<ValidationFailure>());
        expect((await DeleteDreamCategory(categories)(travel.id)).isOk, isTrue);
      },
    );

    test('a select column needs options; its key and type stay', () async {
      final bad = await CreateDreamField(fields, clock)(
        label: 'Pilihan contoh',
        type: DreamFieldType.select,
      );
      expect(bad.failureOrNull, isA<ValidationFailure>());
      final ok = (await CreateDreamField(fields, clock)(
        label: 'Pilihan contoh',
        type: DreamFieldType.select,
        options: const ['A', 'B'],
      )).valueOrThrow;
      expect(ok.options, ['A', 'B']);
      final renamed = (await UpdateDreamField(fields, clock)(
        id: ok.id,
        label: 'Pilihan contoh baru',
      )).valueOrThrow;
      expect(renamed.key, ok.key);
      expect(renamed.type, DreamFieldType.select);
      expect(renamed.options, ['A', 'B']);
    });
  });

  group('reads', () {
    test(
      'the local detail shows the dream with its steps and metrics',
      () async {
        await seedDream('d1');
        await steps.save(
          DreamStep(
            id: 's1',
            dreamId: 'd1',
            title: 'Langkah contoh',
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
        );
        final detail = await WatchDreamLocalDetail(dreams, steps, metrics)(
          'd1',
        ).first;
        expect(detail!.dream.id, 'd1');
        expect(detail.steps.map((s) => s.id), ['s1']);
        expect(detail.metrics, isEmpty);
        expect(
          await WatchDreamLocalDetail(dreams, steps, metrics)('nope').first,
          isNull,
        );
      },
    );

    test(
      'the summary and the detail come from the server, as they are',
      () async {
        final summary = DreamSummary(date: '2026-10-10', total: 6, open: 6);
        online.summaryValue = summary;
        final r = await GetDreamSummary(online)(tz: 'Asia/Jakarta');
        expect(r.valueOrThrow, summary);
        expect(online.calls, ['summary:Asia/Jakarta']);
      },
    );

    test('offline the online reads fail with a network failure', () async {
      online.failure = const NetworkFailure();
      expect(
        (await GetDreamSummary(online)()).failureOrNull,
        isA<NetworkFailure>(),
      );
      expect(
        (await GetDreamDetail(online)('d1')).failureOrNull,
        isA<NetworkFailure>(),
      );
      expect(
        (await RecordDreamManualValueOnline(online)(
          dreamId: 'd1',
          metricId: 'm1',
          value: 1,
        )).failureOrNull,
        isA<NetworkFailure>(),
      );
    });

    test(
      'a manual reading online returns the recomputed metric and steps',
      () async {
        final view = DreamMetricView(
          metric: DreamMetric(
            id: 'm1',
            dreamId: 'd1',
            label: 'Dana darurat contoh',
            source: MetricSource.manual,
            targetValue: 12000000,
            createdAt: clock.now(),
            updatedAt: clock.now(),
          ),
          reading: const DreamMetricReading(progressPct: 40),
        );
        online.manualValue = ManualValueResult(
          metric: view,
          stepsCompleted: const ['s1'],
        );
        final r = await RecordDreamManualValueOnline(online)(
          dreamId: 'd1',
          metricId: 'm1',
          value: 4800000,
        );
        expect(r.valueOrThrow.stepsCompleted, ['s1']);
        expect(r.valueOrThrow.metric.reading.progressPct, 40);
        expect(online.calls, ['value:d1/m1=4800000.0']);
      },
    );
  });

  test('a Result carries the failure type callers switch on', () {
    const Result<Dream> r = Err(NotFoundFailure());
    expect(r.failureOrNull, isA<NotFoundFailure>());
  });
}
