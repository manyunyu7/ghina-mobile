import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../models/agenda_wire.dart';
import '../models/entity_names.dart';
import 'local_store.dart';

class DriftReminderItemRepository implements ReminderItemRepository {
  DriftReminderItemRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$ReminderItemsTable, ReminderRow> get _all =>
      _db.select(_db.reminderItems)..orderBy([
        (r) => OrderingTerm.asc(r.dueAt),
        (r) => OrderingTerm.asc(r.id),
      ]);

  SimpleSelectStatement<$ReminderItemsTable, ReminderRow> _one(String id) =>
      _db.select(_db.reminderItems)..where((r) => r.id.equals(id));

  @override
  Stream<List<ReminderItem>> watchAll() =>
      _all.watch().map((rows) => [for (final r in rows) r.toEntity()]);

  @override
  Future<List<ReminderItem>> getAll() async => [
    for (final r in await _all.get()) r.toEntity(),
  ];

  @override
  Stream<ReminderItem?> watchById(String id) =>
      _one(id).watchSingleOrNull().map((r) => r?.toEntity());

  @override
  Future<ReminderItem?> getById(String id) async =>
      (await _one(id).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(ReminderItem reminder) => _s.write(() async {
    final exists = await _one(reminder.id).getSingleOrNull() != null;
    await _db
        .into(_db.reminderItems)
        .insertOnConflictUpdate(reminder.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.reminders,
      entityId: reminder.id,
      data: reminderToWire(reminder),
      clientUpdatedAt: reminder.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.reminderItems,
    )..where((r) => r.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.reminders,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftCalendarEventRepository implements CalendarEventRepository {
  DriftCalendarEventRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$CalendarEventsTable, CalendarEventRow> get _all =>
      _db.select(_db.calendarEvents)..orderBy([
        (e) => OrderingTerm.asc(e.startAt),
        (e) => OrderingTerm.asc(e.id),
      ]);

  SimpleSelectStatement<$CalendarEventsTable, CalendarEventRow> _one(
    String id,
  ) => _db.select(_db.calendarEvents)..where((e) => e.id.equals(id));

  @override
  Stream<List<CalendarEvent>> watchAll() =>
      _all.watch().map((rows) => [for (final r in rows) r.toEntity()]);

  @override
  Future<List<CalendarEvent>> getAll() async => [
    for (final r in await _all.get()) r.toEntity(),
  ];

  @override
  Stream<CalendarEvent?> watchById(String id) =>
      _one(id).watchSingleOrNull().map((r) => r?.toEntity());

  @override
  Future<CalendarEvent?> getById(String id) async =>
      (await _one(id).getSingleOrNull())?.toEntity();

  @override
  Future<void> save(CalendarEvent event) => _s.write(() async {
    final exists = await _one(event.id).getSingleOrNull() != null;
    await _db
        .into(_db.calendarEvents)
        .insertOnConflictUpdate(event.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.calendarEvents,
      entityId: event.id,
      data: calendarEventToWire(event),
      clientUpdatedAt: event.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.calendarEvents,
    )..where((e) => e.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.calendarEvents,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}
