import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/api_dto.dart' show MutationOp;
import '../models/entity_names.dart';
import '../models/people_wire.dart';
import '../sync/outbox.dart';
import 'local_store.dart';

/// Drift repositories of People and the habit-enrichment entities. Same
/// pattern as the agenda repositories: row write + outbox entry in one local
/// transaction; the notes never touch the database.
class DriftPersonRepository implements PersonRepository {
  DriftPersonRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$PeopleTable, PersonRow> get _all =>
      _db.select(_db.people)..orderBy([
        (p) => OrderingTerm.asc(p.name.lower()),
        (p) => OrderingTerm.asc(p.id),
      ]);

  SimpleSelectStatement<$PeopleTable, PersonRow> _one(String id) =>
      _db.select(_db.people)..where((p) => p.id.equals(id));

  @override
  Stream<List<Person>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Person>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<Person?> watchById(String id) =>
      _one(id).watchSingleOrNull().map((r) => r?.toEntity());

  @override
  Future<Person?> getById(String id) async =>
      (await _one(id).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(Person person) => _s.write(() async {
    final exists = await _one(person.id).getSingleOrNull() != null;
    await _db.into(_db.people).insertOnConflictUpdate(person.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.people,
      entityId: person.id,
      data: personToWire(person),
      clientUpdatedAt: person.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.people,
    )..where((p) => p.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.personDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.people,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });

  @override
  Future<void> refreshPending(String id) => _s.write(() async {
    final e = await _s.outbox.pendingEntry(SyncEntity.people, id);
    if (e == null || e.op != MutationOp.upsert.name || e.data == null) return;
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.people,
      entityId: id,
      data: Outbox.decode(e.data)!,
      clientUpdatedAt: _s.clock.now(),
      isCreate: false, // a pending create keeps its flag (collapsing rules)
    );
  });
}

class DriftPersonCategoryRepository implements PersonCategoryRepository {
  DriftPersonCategoryRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$PersonCategoriesTable, PersonCategoryRow> get _all =>
      _db.select(_db.personCategories)..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.label.lower()),
        (c) => OrderingTerm.asc(c.id),
      ]);

  @override
  Stream<List<PersonCategory>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<PersonCategory>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Future<PersonCategory?> getById(String id) async => (await (_db.select(
    _db.personCategories,
  )..where((c) => c.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(PersonCategory category) => _s.write(() async {
    final exists = await getById(category.id) != null;
    await _db
        .into(_db.personCategories)
        .insertOnConflictUpdate(category.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.personCategories,
      entityId: category.id,
      data: personCategoryToWire(category),
      clientUpdatedAt: category.updatedAt,
      isCreate: !exists,
    );
  });
}

class DriftPersonFieldRepository implements PersonFieldRepository {
  DriftPersonFieldRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$PersonFieldsTable, PersonFieldRow> get _all =>
      _db.select(_db.personFields)..orderBy([
        (f) => OrderingTerm.asc(f.sortOrder),
        (f) => OrderingTerm.asc(f.label.lower()),
        (f) => OrderingTerm.asc(f.id),
      ]);

  static List<PersonFieldDef> _map(List<PersonFieldRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<PersonFieldDef>> watchAll() => _all.watch().map(_map);

  @override
  Future<List<PersonFieldDef>> getAll() async => _map(await _all.get());

  @override
  Future<PersonFieldDef?> getById(String id) async => (await (_db.select(
    _db.personFields,
  )..where((f) => f.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(PersonFieldDef def) => _s.write(() async {
    final exists = await getById(def.id) != null;
    await _db.into(_db.personFields).insertOnConflictUpdate(def.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.personFields,
      entityId: def.id,
      data: personFieldToWire(def),
      clientUpdatedAt: def.updatedAt,
      isCreate: !exists,
    );
  });
}

class DriftPersonDateRepository implements PersonDateRepository {
  DriftPersonDateRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$PersonDatesTable, PersonDateRow> _q([
    String? personId,
  ]) {
    final q = _db.select(_db.personDates)
      ..orderBy([
        (d) => OrderingTerm.asc(d.month),
        (d) => OrderingTerm.asc(d.day),
        (d) => OrderingTerm.asc(d.id),
      ]);
    if (personId != null) q.where((d) => d.personId.equals(personId));
    return q;
  }

  static List<PersonDate> _map(List<PersonDateRow> r) => [
    for (final x in r) x.toEntity(),
  ];

  @override
  Stream<List<PersonDate>> watchAll() => _q().watch().map(_map);

  @override
  Future<List<PersonDate>> getAll() async => _map(await _q().get());

  @override
  Stream<List<PersonDate>> watchForPerson(String personId) =>
      _q(personId).watch().map(_map);

  @override
  Future<List<PersonDate>> getForPerson(String personId) async =>
      _map(await _q(personId).get());

  @override
  Future<PersonDate?> getById(String id) async => (await (_db.select(
    _db.personDates,
  )..where((d) => d.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(PersonDate date) => _s.write(() async {
    final exists = await getById(date.id) != null;
    await _db.into(_db.personDates).insertOnConflictUpdate(date.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.personDates,
      entityId: date.id,
      data: personDateToWire(date),
      clientUpdatedAt: date.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.personDates,
    )..where((d) => d.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.personDates,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftHabitFieldRepository implements HabitFieldRepository {
  DriftHabitFieldRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$HabitFieldsTable, HabitFieldRow> get _all =>
      _db.select(_db.habitFields)..orderBy([
        (f) => OrderingTerm.asc(f.sortOrder),
        (f) => OrderingTerm.asc(f.label.lower()),
        (f) => OrderingTerm.asc(f.id),
      ]);

  static List<HabitFieldDef> _map(List<HabitFieldRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<HabitFieldDef>> watchAll() => _all.watch().map(_map);

  @override
  Future<List<HabitFieldDef>> getAll() async => _map(await _all.get());

  @override
  Future<HabitFieldDef?> getById(String id) async => (await (_db.select(
    _db.habitFields,
  )..where((f) => f.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(HabitFieldDef def) => _s.write(() async {
    final exists = await getById(def.id) != null;
    await _db.into(_db.habitFields).insertOnConflictUpdate(def.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.habitFields,
      entityId: def.id,
      data: habitFieldToWire(def),
      clientUpdatedAt: def.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final row = await (_db.select(
      _db.habitFields,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.habitFields)..where((f) => f.id.equals(id))).go();
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.habitFields,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
    // Strip the key from every log / event (the server does the same).
    await _s.cascades.habitFieldDeleted(row.key);
  });
}

class DriftHabitEventRepository implements HabitEventRepository {
  DriftHabitEventRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$HabitEventsTable, HabitEventRow> _q(String? habitId) {
    final q = _db.select(_db.habitEvents)
      ..orderBy([
        (e) => OrderingTerm.desc(e.date),
        (e) => OrderingTerm.desc(e.createdAt),
      ]);
    if (habitId != null) q.where((e) => e.habitId.equals(habitId));
    return q;
  }

  static List<HabitEvent> _map(List<HabitEventRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<HabitEvent>> watch({String? habitId}) =>
      _q(habitId).watch().map(_map);

  @override
  Future<List<HabitEvent>> getAll({String? habitId}) async =>
      _map(await _q(habitId).get());

  @override
  Future<HabitEvent?> getById(String id) async => (await (_db.select(
    _db.habitEvents,
  )..where((e) => e.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(HabitEvent event) => _s.write(() async {
    final exists = await getById(event.id) != null;
    await _db.into(_db.habitEvents).insertOnConflictUpdate(event.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.habitEvents,
      entityId: event.id,
      data: habitEventToWire(event),
      clientUpdatedAt: event.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.habitEvents,
    )..where((e) => e.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.habitEvents,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
