// Drift Dreams repositories (docs/dreams.md): the row write and its outbox
// entry share one transaction, deletes run the local cascades, lists come out
// in list order. Real in-memory drift + outbox via the harness; invented data.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/repositories/dreams_repositories.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/domain/entities/entities.dart';

import '../harness.dart';

void main() {
  late Harness h;
  late DriftDreamRepository dreams;
  late DriftDreamStepRepository steps;
  late DriftDreamMetricRepository metrics;
  late DriftDreamCategoryRepository categories;
  late DriftDreamFieldRepository fields;
  final t0 = DateTime.utc(2026, 10, 10, 3).toLocal();

  setUp(() {
    h = Harness();
    dreams = DriftDreamRepository(h.store);
    steps = DriftDreamStepRepository(h.store);
    metrics = DriftDreamMetricRepository(h.store);
    categories = DriftDreamCategoryRepository(h.store);
    fields = DriftDreamFieldRepository(h.store);
  });
  tearDown(() => h.close());

  Dream dream(
    String id, {
    String? target,
    String? parentId,
    String category = 'other',
    Map<String, Object> fieldValues = const {},
  }) => Dream(
    id: id,
    title: 'Mimpi contoh $id',
    targetDate: target,
    parentId: parentId,
    category: category,
    fields: fieldValues,
    createdAt: t0,
    updatedAt: t0,
  );

  DreamStep step(
    String id,
    String dreamId, {
    int order = 0,
    String? metricRef,
    double? atValue,
  }) => DreamStep(
    id: id,
    dreamId: dreamId,
    title: 'Langkah contoh $id',
    sortOrder: order,
    metricRef: metricRef,
    atValue: atValue,
    createdAt: t0,
    updatedAt: t0,
  );

  DreamMetric metric(String id, String dreamId) => DreamMetric(
    id: id,
    dreamId: dreamId,
    label: 'Tabungan contoh',
    source: MetricSource.manual,
    targetValue: 12000000,
    createdAt: t0,
    updatedAt: t0,
  );

  Future<List<String>> queuedFor(String entity) async => [
    for (final e in await h.outbox.all())
      if (e.entity == entity) e.entityId,
  ];

  group('dreams', () {
    test(
      'save writes the row and queues an upsert with the wire data',
      () async {
        await dreams.save(dream('d1', target: '2027-03-31'));
        final queued = (await h.outbox.all()).single;
        expect(queued.entity, SyncEntity.dreams);
        expect(queued.op, 'upsert');
        expect(queued.isCreate, isTrue, reason: 'a new row is a create');
        expect(Outbox.decode(queued.data)!['targetDate'], '2027-03-31');
        expect((await dreams.getById('d1'))!.targetDate, '2027-03-31');
      },
    );

    test('a second save of the same row is an update, not a create', () async {
      await dreams.save(dream('d1'));
      await dreams.save(dream('d1').copyWith(title: 'Mimpi contoh revisi'));
      final queued = (await h.outbox.all()).single;
      expect(queued.isCreate, isTrue, reason: 'still one pending create');
      expect(Outbox.decode(queued.data)!['title'], 'Mimpi contoh revisi');
    });

    test(
      'lists come out in list order: sort order, nearest target, undated last',
      () async {
        await dreams.save(dream('late', target: '2028-01-31'));
        await dreams.save(dream('none'));
        await dreams.save(dream('soon', target: '2026-12-31'));
        expect((await dreams.getAll()).map((d) => d.id), [
          'soon',
          'late',
          'none',
        ]);
      },
    );

    test(
      'deleting a dream removes its steps and metrics and frees its children',
      () async {
        await dreams.save(dream('parent'));
        await dreams.save(dream('child', parentId: 'parent'));
        await steps.save(step('s1', 'parent'));
        await metrics.save(metric('m1', 'parent'));
        await dreams.delete('parent');

        expect(await dreams.getById('parent'), isNull);
        expect(await steps.getForDream('parent'), isEmpty);
        expect(await metrics.getForDream('parent'), isEmpty);
        expect((await dreams.getById('child'))!.parentId, isNull);
        // The parent and its children were never pushed: nothing to delete on
        // the server, and the child's queued create now carries no parent.
        expect(await queuedFor(SyncEntity.dreams), ['child']);
        expect(
          (await h.outbox.all()).where(
            (e) =>
                e.entity == SyncEntity.dreamSteps ||
                e.entity == SyncEntity.dreamMetrics,
          ),
          isEmpty,
        );
        final child = (await h.outbox.all()).singleWhere(
          (e) => e.entityId == 'child',
        );
        expect(Outbox.decode(child.data)!['parentId'], isNull);
      },
    );

    test(
      'a dream removed before its first push leaves nothing to send',
      () async {
        await dreams.save(dream('d1'));
        await dreams.delete('d1');
        final rows = await h.outbox.all();
        expect(rows.where((r) => r.op == 'upsert'), isEmpty);
      },
    );
  });

  group('steps', () {
    test('a checklist lists by sort order and each save is queued', () async {
      await dreams.save(dream('d1'));
      await steps.save(step('s2', 'd1', order: 1));
      await steps.save(step('s1', 'd1', order: 0));
      expect((await steps.getForDream('d1')).map((s) => s.id), ['s1', 's2']);
      expect(await queuedFor(SyncEntity.dreamSteps), ['s2', 's1']);
    });

    test(
      'deleting a step that was never pushed leaves nothing to send',
      () async {
        await dreams.save(dream('d1'));
        await steps.save(step('s1', 'd1'));
        await steps.delete('s1');
        expect(await steps.getById('s1'), isNull);
        expect(
          (await h.outbox.all()).where(
            (e) => e.entity == SyncEntity.dreamSteps,
          ),
          isEmpty,
          reason: 'the create was dropped, the server never saw the step',
        );
      },
    );
  });

  group('metrics', () {
    test(
      'deleting a metric clears the threshold of the steps tied to it',
      () async {
        await dreams.save(dream('d1'));
        await metrics.save(metric('m1', 'd1'));
        await steps.save(step('s1', 'd1', metricRef: 'm1', atValue: 88));
        await metrics.delete('m1');
        final s = await steps.getById('s1');
        expect(s!.metricRef, isNull);
        expect(s.atValue, isNull);
        expect(
          (await h.outbox.all())
              .where(
                (e) => e.entity == SyncEntity.dreamSteps && e.op == 'upsert',
              )
              .single
              .data,
          contains('"metricRef":null'),
        );
      },
    );

    test('a metric of a source this app does not know is not listed', () async {
      await dreams.save(dream('d1'));
      await metrics.save(metric('m1', 'd1'));
      // A row written by a newer app version.
      await h.db
          .into(h.db.dreamMetrics)
          .insert(
            DreamMetricsCompanion.insert(
              id: 'm2',
              dreamId: 'd1',
              label: 'Sumber baru contoh',
              source: 'sumber_baru',
              targetValue: 5,
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      expect((await metrics.getForDream('d1')).map((m) => m.id), ['m1']);
    });
  });

  group('categories and custom columns', () {
    test(
      'deleting a category moves its dreams to other, locally and queued',
      () async {
        await categories.save(
          DreamCategory(
            id: 'dc1',
            key: 'travel',
            label: 'Perjalanan',
            emoji: '✈️',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
        await dreams.save(dream('d1', category: 'travel'));
        await categories.delete('dc1');
        expect((await dreams.getById('d1'))!.category, 'other');
        final queued = (await h.outbox.all())
            .where((e) => e.entity == SyncEntity.dreams && e.op == 'upsert')
            .single;
        expect(Outbox.decode(queued.data)!['category'], 'other');
      },
    );

    test('deleting a field def strips its key from every dream', () async {
      await fields.save(
        DreamFieldDef(
          id: 'df1',
          key: 'sumber_contoh',
          label: 'Sumber contoh',
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await dreams.save(
        dream(
          'd1',
          fieldValues: const {'sumber_contoh': 'daftar-1', 'skor': 3},
        ),
      );
      await fields.delete('df1');
      expect((await dreams.getById('d1'))!.fields, {'skor': 3});
    });

    test(
      'a field def whose type this app does not know is not listed',
      () async {
        await h.db
            .into(h.db.dreamFields)
            .insert(
              DreamFieldsCompanion.insert(
                id: 'df9',
                key: 'baru',
                label: 'Baru contoh',
                type: const Value('jenis_baru'),
                createdAt: t0,
                updatedAt: t0,
              ),
            );
        expect(await fields.getAll(), isEmpty);
      },
    );

    test('categories list by sort order, then label', () async {
      await categories.save(
        DreamCategory(
          id: 'b',
          key: 'b',
          label: 'Bbb',
          emoji: '✨',
          sortOrder: 1,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await categories.save(
        DreamCategory(
          id: 'a',
          key: 'a',
          label: 'Aaa',
          emoji: '✨',
          sortOrder: 1,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      await categories.save(
        DreamCategory(
          id: 'z',
          key: 'z',
          label: 'Zzz',
          emoji: '✨',
          sortOrder: 0,
          createdAt: t0,
          updatedAt: t0,
        ),
      );
      expect((await categories.getAll()).map((c) => c.key), ['z', 'a', 'b']);
    });
  });
}
