import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/habits_investments_mappers.dart';
import '../models/habits_investments_wire.dart';
import 'local_store.dart';

class DriftHabitRepository implements HabitRepository {
  DriftHabitRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$HabitsTable, HabitRow> get _all =>
      _db.select(_db.habits)..orderBy([
        (h) => OrderingTerm.asc(h.sortOrder),
        (h) => OrderingTerm.asc(h.createdAt),
      ]);

  @override
  Stream<List<Habit>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Habit>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<Habit?> watchById(String id) =>
      (_db.select(_db.habits)..where((h) => h.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Habit?> getById(String id) async => (await (_db.select(
    _db.habits,
  )..where((h) => h.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Habit habit) => _s.write(() async {
    final exists = await getById(habit.id) != null;
    await _db.into(_db.habits).insertOnConflictUpdate(habit.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.habits,
      entityId: habit.id,
      data: habitToWire(habit),
      clientUpdatedAt: habit.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.habits,
    )..where((h) => h.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.habitDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.habits,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftHabitLogRepository implements HabitLogRepository {
  DriftHabitLogRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$HabitLogsTable, HabitLogRow> _q({
    String? habitId,
    String? from,
    String? to,
  }) {
    final q = _db.select(_db.habitLogs)
      ..where((l) => l.type.isIn([for (final t in HabitLogType.values) t.wire]))
      ..orderBy([
        (l) => OrderingTerm.asc(l.date),
        (l) => OrderingTerm.asc(l.createdAt),
      ]);
    if (habitId != null) q.where((l) => l.habitId.equals(habitId));
    if (from != null) q.where((l) => l.date.isBiggerOrEqualValue(from));
    if (to != null) q.where((l) => l.date.isSmallerOrEqualValue(to));
    return q;
  }

  static List<HabitLog> _map(List<HabitLogRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<HabitLog>> watch({String? habitId, String? from, String? to}) =>
      _q(habitId: habitId, from: from, to: to).watch().map(_map);

  @override
  Future<List<HabitLog>> getAll({
    String? habitId,
    String? from,
    String? to,
  }) async => _map(await _q(habitId: habitId, from: from, to: to).get());

  @override
  Future<HabitLog?> getById(String id) async => (await (_db.select(
    _db.habitLogs,
  )..where((l) => l.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<HabitLog?> findByKey(
    String habitId,
    String date,
    HabitLogType type,
  ) async =>
      (await (_db.select(_db.habitLogs)..where(
                (l) =>
                    l.habitId.equals(habitId) &
                    l.date.equals(date) &
                    l.type.equals(type.wire),
              ))
              .getSingleOrNull())
          ?.toEntityOrNull();

  @override
  Future<void> save(HabitLog log) => _s.write(() async {
    final exists =
        await (_db.select(
          _db.habitLogs,
        )..where((l) => l.id.equals(log.id))).getSingleOrNull() !=
        null;
    await _db.into(_db.habitLogs).insertOnConflictUpdate(log.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.habitLogs,
      entityId: log.id,
      data: habitLogToWire(log),
      clientUpdatedAt: log.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.habitLogs,
    )..where((l) => l.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.habitLogs,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
