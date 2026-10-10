// Dreams ("Mimpi") through the real drift database + outbox + sync engine
// against the in-memory server (docs/dreams.md, docs/mobile-sync.md "Dreams").
// All dreams, steps, metrics and categories are invented.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/models/dreams_wire.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/data/sync/outbox.dart';

import '../harness.dart';

void main() {
  late Harness h;
  final t0 = DateTime.utc(2026, 10, 10, 3).toLocal();

  setUp(() {
    h = Harness();
  });
  tearDown(() => h.close());

  Dream dream(
    String id, {
    String title = 'Mimpi contoh',
    String category = 'other',
    String? parentId,
    String? noteId,
    Map<String, Object> fields = const {},
  }) => Dream(
    id: id,
    title: title,
    category: category,
    parentId: parentId,
    noteId: noteId,
    fields: fields,
    createdAt: t0,
    updatedAt: t0,
  );

  DreamStep step(
    String id,
    String dreamId, {
    String? metricRef,
    double? atValue,
  }) => DreamStep(
    id: id,
    dreamId: dreamId,
    title: 'Langkah contoh $id',
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

  DreamCategory category(String id, String key) => DreamCategory(
    id: id,
    key: key,
    label: 'Kategori contoh $key',
    emoji: '🌟',
    createdAt: t0,
    updatedAt: t0,
  );

  DreamFieldDef field(String id, String key) => DreamFieldDef(
    id: id,
    key: key,
    label: 'Kolom contoh',
    createdAt: t0,
    updatedAt: t0,
  );

  /// Writes a row locally and queues it, like a repository would.
  Future<void> putDream(Dream d) async {
    await h.db.into(h.db.dreams).insertOnConflictUpdate(d.toCompanion());
    await h.outbox.enqueueUpsert(
      entity: SyncEntity.dreams,
      entityId: d.id,
      data: dreamToWire(d),
      clientUpdatedAt: h.clock.now(),
      isCreate: true,
    );
  }

  Future<void> putStep(DreamStep s) async {
    await h.db.into(h.db.dreamSteps).insertOnConflictUpdate(s.toCompanion());
    await h.outbox.enqueueUpsert(
      entity: SyncEntity.dreamSteps,
      entityId: s.id,
      data: dreamStepToWire(s),
      clientUpdatedAt: h.clock.now(),
      isCreate: true,
    );
  }

  Future<void> putMetric(DreamMetric m) async {
    await h.db.into(h.db.dreamMetrics).insertOnConflictUpdate(m.toCompanion());
    await h.outbox.enqueueUpsert(
      entity: SyncEntity.dreamMetrics,
      entityId: m.id,
      data: dreamMetricToWire(m),
      clientUpdatedAt: h.clock.now(),
      isCreate: true,
    );
  }

  Future<void> putCategory(DreamCategory c) async {
    await h.db
        .into(h.db.dreamCategories)
        .insertOnConflictUpdate(c.toCompanion());
    await h.outbox.enqueueUpsert(
      entity: SyncEntity.dreamCategories,
      entityId: c.id,
      data: dreamCategoryToWire(c),
      clientUpdatedAt: h.clock.now(),
      isCreate: true,
    );
  }

  Future<void> putField(DreamFieldDef d) async {
    await h.db.into(h.db.dreamFields).insertOnConflictUpdate(d.toCompanion());
    await h.outbox.enqueueUpsert(
      entity: SyncEntity.dreamFields,
      entityId: d.id,
      data: dreamFieldToWire(d),
      clientUpdatedAt: h.clock.now(),
      isCreate: true,
    );
  }

  /// The built-in `other` category (every dream needs it on the server).
  void seedOther() => h.server.web(SyncEntity.dreamCategories, 'dc_u1_other', {
    'key': 'other',
    'label': 'Lainnya',
    'emoji': '✨',
    'sortOrder': 11,
  });

  /// Built-in categories as the server seeds them on the first pull.
  void seedCategories() {
    seedOther();
    h.server.web(SyncEntity.dreamCategories, 'dc_u1_travel', {
      'key': 'travel',
      'label': 'Perjalanan',
      'emoji': '✈️',
      'sortOrder': 1,
    });
  }

  Iterable<String> pushedEntities() => h.server.pushed.map((m) => m.entity);

  group('wire', () {
    test('a dream goes out without id or stamps, links and fields as JSON', () {
      final d =
          dream(
            'd1',
            category: 'travel',
            fields: const {'sumber_contoh': 'daftar-1', 'skor': 3},
          ).copyWith(
            links: const DreamLinks(taskIds: ['t1']),
            tags: const ['liburan'],
          );
      final w = dreamToWire(d);
      expect(w.containsKey('id'), isFalse);
      expect(w.containsKey('createdAt'), isFalse);
      expect(w['category'], 'travel');
      expect(w['status'], 'idea');
      expect(w['targetPrecision'], 'day');
      expect(w['fields'], {'sumber_contoh': 'daftar-1', 'skor': 3});
      expect(w['links'], {
        'taskIds': ['t1'],
        'habitIds': <String>[],
      });
      expect(w['tags'], ['liburan']);
    });

    test('pulled dreams parse leniently; an unknown status reads as idea', () {
      final d = dreamFromWire({
        'id': 'd1',
        'title': 'Trip contoh ke Kota Sample',
        'status': 'sesuatu-baru',
        'targetDate': '2027-03-31',
        'targetPrecision': 'quarter',
        'tags': '["liburan"]',
        'fields': '{"sumber_contoh":"daftar-1","bukan_skalar":[1,2]}',
        'links': {
          'taskIds': ['t1'],
          'habitIds': 'bukan-daftar',
        },
        'createdAt': '2026-10-10T03:00:00.000Z',
        'updatedAt': '2026-10-10T03:00:00.000Z',
      });
      expect(d, isNotNull);
      expect(d!.status, DreamStatus.idea);
      expect(d.targetPrecision, TargetPrecision.quarter);
      expect(d.tags, ['liburan']);
      expect(d.fields, {
        'sumber_contoh': 'daftar-1',
      }, reason: 'non-scalars dropped');
      expect(d.links.taskIds, ['t1']);
      expect(d.links.habitIds, isEmpty);
    });

    test('a pulled row without an id is ignored; a metric of an unknown '
        'source is ignored', () {
      expect(
        dreamFromWire({'title': 'x', 'createdAt': '2026-10-10T00:00:00Z'}),
        isNull,
      );
      expect(
        dreamMetricFromWire({
          'id': 'm1',
          'dreamId': 'd1',
          'label': 'Entah apa',
          'source': 'sumber-baru',
          'targetValue': 5,
          'createdAt': '2026-10-10T00:00:00Z',
        }),
        isNull,
      );
    });
  });

  group('pull', () {
    test('categories, field defs, dreams, metrics and steps arrive', () async {
      seedCategories();
      h.server.web(SyncEntity.dreamFields, 'df1', {
        'key': 'sumber_contoh',
        'label': 'Sumber contoh',
        'type': 'text',
        'options': null,
        'appliesTo': null,
        'sortOrder': 0,
        'showInList': false,
      });
      h.server.web(
        SyncEntity.dreams,
        'd1',
        dreamToWire(
          dream(
            'd1',
            category: 'travel',
            fields: const {'sumber_contoh': 'daftar-1'},
          ),
        ),
      );
      h.server.web(
        SyncEntity.dreamMetrics,
        'm1',
        dreamMetricToWire(metric('m1', 'd1')),
      );
      h.server.web(
        SyncEntity.dreamSteps,
        's1',
        dreamStepToWire(step('s1', 'd1')),
      );
      await h.engine.syncNow();

      expect((await h.db.select(h.db.dreamCategories).get()).length, 2);
      expect(
        (await h.db.select(h.db.dreamFields).get()).single.key,
        'sumber_contoh',
      );
      final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(d.category, 'travel');
      expect(d.fields, {'sumber_contoh': 'daftar-1'});
      expect(
        (await h.db.select(h.db.dreamMetrics).getSingle()).source,
        'manual',
      );
      expect((await h.db.select(h.db.dreamSteps).getSingle()).dreamId, 'd1');
      expect(await h.outboxCount(), 0);
    });

    test(
      'a tombstone of a dream deletes its steps and metrics locally',
      () async {
        seedCategories();
        h.server.web(SyncEntity.dreams, 'd1', dreamToWire(dream('d1')));
        h.server.web(
          SyncEntity.dreamSteps,
          's1',
          dreamStepToWire(step('s1', 'd1')),
        );
        h.server.web(
          SyncEntity.dreamMetrics,
          'm1',
          dreamMetricToWire(metric('m1', 'd1')),
        );
        await h.engine.syncNow();
        expect(await h.db.select(h.db.dreamSteps).get(), hasLength(1));

        h.tick();
        h.server.webDelete(SyncEntity.dreams, 'd1');
        await h.engine.syncNow();
        expect(await h.db.select(h.db.dreams).get(), isEmpty);
        expect(await h.db.select(h.db.dreamSteps).get(), isEmpty);
        expect(await h.db.select(h.db.dreamMetrics).get(), isEmpty);
      },
    );

    test(
      'a tombstone of a parent dream clears the children\'s parentId',
      () async {
        seedCategories();
        h.server.web(SyncEntity.dreams, 'parent', dreamToWire(dream('parent')));
        h.server.web(
          SyncEntity.dreams,
          'child',
          dreamToWire(dream('child', parentId: 'parent')),
        );
        await h.engine.syncNow();

        h.tick();
        h.server.webDelete(SyncEntity.dreams, 'parent');
        await h.engine.syncNow();
        final child = (await h.db.select(h.db.dreams).getSingle()).toEntity();
        expect(child.id, 'child');
        expect(child.parentId, isNull);
      },
    );

    test(
      'deleting a metric on the server clears its steps\' metricRef',
      () async {
        seedCategories();
        h.server.web(SyncEntity.dreams, 'd1', dreamToWire(dream('d1')));
        h.server.web(
          SyncEntity.dreamMetrics,
          'm1',
          dreamMetricToWire(metric('m1', 'd1')),
        );
        h.server.web(
          SyncEntity.dreamSteps,
          's1',
          dreamStepToWire(step('s1', 'd1', metricRef: 'm1', atValue: 10)),
        );
        await h.engine.syncNow();

        h.tick();
        h.server.webDelete(SyncEntity.dreamMetrics, 'm1');
        await h.engine.syncNow();
        final s = (await h.db.select(h.db.dreamSteps).getSingle()).toEntity();
        expect(s.metricRef, isNull);
        expect(s.atValue, isNull);
      },
    );

    test(
      'deleting a category on the server moves its dreams to other',
      () async {
        seedCategories();
        h.server.web(
          SyncEntity.dreams,
          'd1',
          dreamToWire(dream('d1', category: 'travel')),
        );
        await h.engine.syncNow();

        h.tick();
        h.server.webDelete(SyncEntity.dreamCategories, 'dc_u1_travel');
        await h.engine.syncNow();
        final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
        expect(d.category, 'other');
        expect(
          h.server.rows[SyncEntity.dreams]!['d1']!['category'],
          'other',
          reason: 'the server moved it too',
        );
      },
    );

    test('deleting a field def strips its key from every dream', () async {
      seedCategories();
      h.server.web(SyncEntity.dreamFields, 'df1', {
        'key': 'sumber_contoh',
        'label': 'Sumber contoh',
        'type': 'text',
        'sortOrder': 0,
        'showInList': false,
      });
      h.server.web(
        SyncEntity.dreams,
        'd1',
        dreamToWire(dream('d1', fields: const {'sumber_contoh': 'daftar-1'})),
      );
      await h.engine.syncNow();

      h.tick();
      h.server.webDelete(SyncEntity.dreamFields, 'df1');
      await h.engine.syncNow();
      final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(d.fields, isEmpty);
    });

    test('deleting a note nulls the noteId of its dreams', () async {
      seedCategories();
      h.server.web(SyncEntity.notes, 'n1', {
        'title': 'Catatan contoh',
        'body': '',
        'checklist': [],
        'labels': [],
        'photos': [],
        'audio': [],
        'links': [],
        'pinned': false,
        'archived': false,
        'color': null,
      });
      h.server.web(
        SyncEntity.dreams,
        'd1',
        dreamToWire(dream('d1', noteId: 'n1')),
      );
      await h.engine.syncNow();

      h.tick();
      h.server.webDelete(SyncEntity.notes, 'n1');
      await h.engine.syncNow();
      final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(d.noteId, isNull);
    });

    test('a same category key under another id is a duplicate: the local '
        'row is dropped and the server one arrives', () async {
      seedOther();
      await putCategory(category('dc-local', 'travel'));
      h.server.web(SyncEntity.dreamCategories, 'dc-from-web', {
        'key': 'travel',
        'label': 'Perjalanan',
        'emoji': '✈️',
        'sortOrder': 1,
      });
      await h.engine.syncNow();
      final cats = await h.db.select(h.db.dreamCategories).get();
      expect(cats.where((c) => c.key == 'travel').map((c) => c.id), [
        'dc-from-web',
      ]);
      expect(h.server.rejected, isEmpty);
      expect(await h.outboxCount(), 0);
    });
  });

  group('push', () {
    test('categories and fields go first, then dreams (parents first), '
        'then metrics, then steps, whatever the queue order', () async {
      seedCategories();
      // Queued the wrong way round on purpose: steps first, the child dream
      // before its parent.
      await putStep(step('s1', 'parent'));
      await putMetric(metric('m1', 'parent'));
      await putDream(dream('child', parentId: 'parent'));
      await putDream(dream('parent', category: 'travel'));
      await putField(field('f1', 'sumber_contoh'));
      await putCategory(category('c1', 'kota'));
      await h.engine.syncNow();

      expect(h.server.rejected, isEmpty, reason: 'every reference existed');
      expect(pushedEntities().toList(), [
        SyncEntity.dreamCategories,
        SyncEntity.dreamFields,
        SyncEntity.dreams,
        SyncEntity.dreams,
        SyncEntity.dreamMetrics,
        SyncEntity.dreamSteps,
      ]);
      final order = h.server.pushed
          .where((m) => m.entity == SyncEntity.dreams)
          .map((m) => m.entityId)
          .toList();
      expect(order, ['parent', 'child'], reason: 'parent before child');
      expect(await h.outboxCount(), 0);
    });

    test(
      'a re-saved step keeps its place after the metrics and dreams',
      () async {
        seedCategories();
        await putStep(step('s1', 'd1'));
        await putDream(dream('d1'));
        // Re-saving the step moves its queue entry to the end; the rank holds.
        await putStep(step('s1', 'd1').copyWith(done: true, doneAt: t0));
        await putMetric(metric('m1', 'd1'));
        await h.engine.syncNow();
        expect(h.server.rejected, isEmpty);
        expect(pushedEntities().toList(), [
          SyncEntity.dreams,
          SyncEntity.dreamMetrics,
          SyncEntity.dreamSteps,
        ]);
      },
    );

    test('a dream with a category the server does not have is rejected, '
        'surfaced and reverted by the pull', () async {
      // No dreamCategories on the server yet.
      await putDream(dream('d1', category: 'kota-sample'));
      await h.engine.syncNow();
      expect(h.server.rejected, hasLength(1));
      expect(h.server.rejected.single.$2, contains('Unknown category'));
      expect(await h.outboxCount(), 0);
      expect(
        await h.db.select(h.db.dreams).get(),
        isEmpty,
        reason: 'reverted by the pull',
      );
      expect((await h.db.getMeta()).lastError, contains('Unknown category'));
    });

    test('a step of a dream the server does not know is rejected', () async {
      seedCategories();
      await putStep(step('s1', 'tidak-ada'));
      await h.engine.syncNow();
      expect(h.server.rejected, hasLength(1));
      expect(await h.outboxCount(), 0);
      expect(await h.db.select(h.db.dreamSteps).get(), isEmpty);
    });

    test('a field key without a def is rejected', () async {
      seedCategories();
      await putDream(dream('d1', fields: const {'belum_ada': 'x'}));
      await h.engine.syncNow();
      expect(h.server.rejected.single.$2, contains('Unknown field'));
    });

    test('a category the server already has under another id is a '
        'duplicate: the local row is dropped', () async {
      seedCategories();
      await putCategory(category('dc-local', 'travel'));
      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      expect(
        (await h.db.select(h.db.dreamCategories).get()).map((c) => c.id),
        isNot(contains('dc-local')),
      );
      expect(await h.outboxCount(), 0);
    });
  });

  group('local cascades (the same rules applied on this device)', () {
    test('a dream removed locally drops its steps and metrics and frees its '
        'children', () async {
      seedCategories();
      await putDream(dream('parent'));
      await putDream(dream('child', parentId: 'parent'));
      await putStep(step('s1', 'parent'));
      await putMetric(metric('m1', 'parent'));
      await h.engine.syncNow();
      expect(h.server.rows[SyncEntity.dreamSteps]!, hasLength(1));

      // Local delete: the row, then its cascades (what the repository does).
      h.tick();
      await (h.db.delete(
        h.db.dreams,
      )..where((r) => r.id.equals('parent'))).go();
      await h.store.cascades.dreamDeleted('parent');
      await h.outbox.enqueueDelete(
        entity: SyncEntity.dreams,
        entityId: 'parent',
        clientUpdatedAt: h.clock.now(),
      );
      expect(await h.db.select(h.db.dreamSteps).get(), isEmpty);
      expect(await h.db.select(h.db.dreamMetrics).get(), isEmpty);
      final child = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(child.parentId, isNull);

      await h.engine.syncNow();
      expect(h.server.rows[SyncEntity.dreams]!.keys, ['child']);
      expect(
        h.server.rows[SyncEntity.dreamSteps],
        isEmpty,
        reason: 'the server cascades too',
      );
      expect(h.server.rows[SyncEntity.dreams]!['child']!['parentId'], isNull);
      expect(await h.outboxCount(), 0);
    });

    test(
      'a field def removed locally strips its key from queued dreams',
      () async {
        seedCategories();
        await putField(field('f1', 'sumber_contoh'));
        await h.engine.syncNow();
        h.tick();
        await putDream(
          dream('d1', fields: const {'sumber_contoh': 'daftar-1'}),
        );
        // The field def goes away before the dream syncs.
        await h.store.cascades.dreamFieldDeleted('sumber_contoh');
        final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
        expect(d.fields, isEmpty);
        expect(
          (await h.outbox.all()).single.data,
          contains('"fields":{}'),
          reason: 'the queued upsert no longer carries the key',
        );
      },
    );

    test('a category removed locally moves its dreams to other', () async {
      seedCategories();
      await putDream(dream('d1', category: 'travel'));
      await h.store.cascades.dreamCategoryDeleted('travel');
      final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(d.category, 'other');
    });

    test(
      'a metric removed locally clears its steps\' metricRef and atValue',
      () async {
        await putDream(dream('d1'));
        await putStep(step('s1', 'd1', metricRef: 'm1', atValue: 5));
        await h.store.cascades.dreamMetricDeleted('m1');
        final s = (await h.db.select(h.db.dreamSteps).getSingle()).toEntity();
        expect(s.metricRef, isNull);
        expect(s.atValue, isNull);
      },
    );

    test('a note removed locally nulls dreams.noteId', () async {
      await putDream(dream('d1', noteId: 'n1'));
      await h.store.cascades.noteDeleted('n1');
      final d = (await h.db.select(h.db.dreams).getSingle()).toEntity();
      expect(d.noteId, isNull);
    });
  });

  group('outbox order helper', () {
    test(
      'a child dream queued before its parent in the same batch sorts after',
      () async {
        seedCategories();
        await putDream(dream('child', parentId: 'parent'));
        await putDream(dream('parent'));
        final batch = await h.outbox.takeBatch();
        final depth = dreamParentDepths(batch);
        final child = batch.singleWhere((r) => r.entityId == 'child');
        final parent = batch.singleWhere((r) => r.entityId == 'parent');
        expect(depth[parent.seq], 0);
        expect(depth[child.seq], 1);
      },
    );
  });
}
