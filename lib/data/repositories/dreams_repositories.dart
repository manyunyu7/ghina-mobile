import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/dreams_rules.dart' show compareDreamsForList;
import '../datasources/local/app_database.dart';
import '../models/dreams_wire.dart';
import '../models/entity_names.dart';
import 'local_store.dart';

/// Drift repositories of Dreams ("Mimpi", `docs/dreams.md`). Same pattern as
/// People: the row write and its outbox entry share one local transaction;
/// deletes run the local cascades of the contract before queuing the delete.
class DriftDreamRepository implements DreamRepository {
  DriftDreamRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  List<Dream> _sorted(List<DreamRow> rows) =>
      [for (final r in rows) r.toEntity()]..sort(compareDreamsForList);

  @override
  Stream<List<Dream>> watchAll() => _db.select(_db.dreams).watch().map(_sorted);

  @override
  Future<List<Dream>> getAll() async =>
      _sorted(await _db.select(_db.dreams).get());

  @override
  Stream<Dream?> watchById(String id) =>
      (_db.select(_db.dreams)..where((d) => d.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Dream?> getById(String id) async => (await (_db.select(
    _db.dreams,
  )..where((d) => d.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Dream dream) => _s.write(() async {
    final exists = await getById(dream.id) != null;
    await _db.into(_db.dreams).insertOnConflictUpdate(dream.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.dreams,
      entityId: dream.id,
      data: dreamToWire(dream),
      clientUpdatedAt: dream.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.dreams,
    )..where((d) => d.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.dreamDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.dreams,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftDreamStepRepository implements DreamStepRepository {
  DriftDreamStepRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$DreamStepsTable, DreamStepRow> _forDream(
    String dreamId,
  ) => _db.select(_db.dreamSteps)
    ..where((s) => s.dreamId.equals(dreamId))
    ..orderBy([
      (s) => OrderingTerm.asc(s.sortOrder),
      (s) => OrderingTerm.asc(s.id),
    ]);

  @override
  Stream<List<DreamStep>> watchForDream(String dreamId) =>
      _forDream(dreamId).watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<DreamStep>> getForDream(String dreamId) async => [
    for (final x in await _forDream(dreamId).get()) x.toEntity(),
  ];

  @override
  Future<DreamStep?> getById(String id) async => (await (_db.select(
    _db.dreamSteps,
  )..where((s) => s.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(DreamStep step) => _s.write(() async {
    final exists = await getById(step.id) != null;
    await _db.into(_db.dreamSteps).insertOnConflictUpdate(step.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.dreamSteps,
      entityId: step.id,
      data: dreamStepToWire(step),
      clientUpdatedAt: step.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.dreamSteps,
    )..where((s) => s.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.dreamSteps,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftDreamMetricRepository implements DreamMetricRepository {
  DriftDreamMetricRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  /// Rows the app doesn't know (a newer `source`) are left out of the entity list.
  List<DreamMetric> _entities(List<DreamMetricRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  SimpleSelectStatement<$DreamMetricsTable, DreamMetricRow> _forDream(
    String dreamId,
  ) => _db.select(_db.dreamMetrics)
    ..where((m) => m.dreamId.equals(dreamId))
    ..orderBy([
      (m) => OrderingTerm.asc(m.sortOrder),
      (m) => OrderingTerm.asc(m.id),
    ]);

  @override
  Stream<List<DreamMetric>> watchForDream(String dreamId) =>
      _forDream(dreamId).watch().map(_entities);

  @override
  Future<List<DreamMetric>> getForDream(String dreamId) async =>
      _entities(await _forDream(dreamId).get());

  @override
  Future<DreamMetric?> getById(String id) async => (await (_db.select(
    _db.dreamMetrics,
  )..where((m) => m.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(DreamMetric metric) => _s.write(() async {
    final exists = await getById(metric.id) != null;
    await _db
        .into(_db.dreamMetrics)
        .insertOnConflictUpdate(metric.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.dreamMetrics,
      entityId: metric.id,
      data: dreamMetricToWire(metric),
      clientUpdatedAt: metric.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.dreamMetrics,
    )..where((m) => m.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.dreamMetricDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.dreamMetrics,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftDreamCategoryRepository implements DreamCategoryRepository {
  DriftDreamCategoryRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$DreamCategoriesTable, DreamCategoryRow> get _all =>
      _db.select(_db.dreamCategories)..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.label.lower()),
        (c) => OrderingTerm.asc(c.id),
      ]);

  @override
  Stream<List<DreamCategory>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<DreamCategory>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Future<DreamCategory?> getById(String id) async => (await (_db.select(
    _db.dreamCategories,
  )..where((c) => c.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(DreamCategory category) => _s.write(() async {
    final exists = await getById(category.id) != null;
    await _db
        .into(_db.dreamCategories)
        .insertOnConflictUpdate(category.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.dreamCategories,
      entityId: category.id,
      data: dreamCategoryToWire(category),
      clientUpdatedAt: category.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final row = await (_db.select(
      _db.dreamCategories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.dreamCategories)..where((c) => c.id.equals(id))).go();
    await _s.cascades.dreamCategoryDeleted(row.key);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.dreamCategories,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftDreamFieldRepository implements DreamFieldRepository {
  DriftDreamFieldRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$DreamFieldsTable, DreamFieldRow> get _all =>
      _db.select(_db.dreamFields)..orderBy([
        (f) => OrderingTerm.asc(f.sortOrder),
        (f) => OrderingTerm.asc(f.label.lower()),
        (f) => OrderingTerm.asc(f.id),
      ]);

  List<DreamFieldDef> _entities(List<DreamFieldRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<DreamFieldDef>> watchAll() => _all.watch().map(_entities);

  @override
  Future<List<DreamFieldDef>> getAll() async => _entities(await _all.get());

  @override
  Future<DreamFieldDef?> getById(String id) async => (await (_db.select(
    _db.dreamFields,
  )..where((f) => f.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(DreamFieldDef def) => _s.write(() async {
    final exists = await getById(def.id) != null;
    await _db.into(_db.dreamFields).insertOnConflictUpdate(def.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.dreamFields,
      entityId: def.id,
      data: dreamFieldToWire(def),
      clientUpdatedAt: def.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final row = await (_db.select(
      _db.dreamFields,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.dreamFields)..where((f) => f.id.equals(id))).go();
    await _s.cascades.dreamFieldDeleted(row.key);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.dreamFields,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
