import 'package:drift/drift.dart';

import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/people_wire.dart';
import '../models/wire.dart' show Json;
import 'local_cascades.dart';
import 'outbox.dart';

/// The sync engine's hooks for the people and habit-enrichment entities
/// (`people`, `personCategories`, `personFields`, `personDates`, `habitFields`,
/// `habitEvents`; `docs/mobile-sync.md` → "People", "Habit enrichment"), kept
/// out of `sync_engine.dart`.
///
/// - Pulls are plain upserts; a pulled category / field def / habit field
///   whose `key` is held by a *different* local id (created offline) wins
///   over the local one, which is dropped with its queued upsert (the push
///   would have been answered `duplicate`). People reference categories and
///   defs by **key**, so nothing needs remapping.
/// - Tombstones apply the delete relations locally ([LocalCascades]); the
///   server did the same and the touched rows re-sync.
/// - `duplicate` / `rejected` pushes need no special handling beyond the
///   engine's generic one (drop the queued entry and the local row; a pull
///   brings the server's version).
class PeopleSync {
  PeopleSync(this._db, this._outbox, this._cascades);

  final AppDatabase _db;
  final Outbox _outbox;
  final LocalCascades _cascades;

  TableInfo<Table, dynamic>? table(String entity) => switch (entity) {
    SyncEntity.people => _db.people,
    SyncEntity.personCategories => _db.personCategories,
    SyncEntity.personFields => _db.personFields,
    SyncEntity.personDates => _db.personDates,
    SyncEntity.habitFields => _db.habitFields,
    SyncEntity.habitEvents => _db.habitEvents,
    _ => null,
  };

  /// Applies a pulled row of one of the six entities; false for others.
  /// Rows that can't be parsed (newer server) are skipped.
  Future<bool> upsertPulled(String entity, Json j) async {
    switch (entity) {
      case SyncEntity.people:
        final p = personFromWire(j);
        if (p != null) {
          await _db.into(_db.people).insertOnConflictUpdate(p.toCompanion());
        }
        return true;
      case SyncEntity.personCategories:
        final c = personCategoryFromWire(j);
        if (c == null) return true;
        final clash = await (_db.select(
          _db.personCategories,
        )..where((x) => x.key.equals(c.key) & x.id.equals(c.id).not())).get();
        for (final x in clash) {
          await _outbox.dropQueued(SyncEntity.personCategories, x.id);
          await (_db.delete(
            _db.personCategories,
          )..where((r) => r.id.equals(x.id))).go();
        }
        await _db
            .into(_db.personCategories)
            .insertOnConflictUpdate(c.toCompanion());
        return true;
      case SyncEntity.personFields:
        final d = personFieldFromWire(j);
        if (d == null) return true;
        final clash = await (_db.select(
          _db.personFields,
        )..where((x) => x.key.equals(d.key) & x.id.equals(d.id).not())).get();
        for (final x in clash) {
          await _outbox.dropQueued(SyncEntity.personFields, x.id);
          await (_db.delete(
            _db.personFields,
          )..where((r) => r.id.equals(x.id))).go();
        }
        await _db
            .into(_db.personFields)
            .insertOnConflictUpdate(d.toCompanion());
        return true;
      case SyncEntity.personDates:
        final d = personDateFromWire(j);
        if (d != null) {
          await _db
              .into(_db.personDates)
              .insertOnConflictUpdate(d.toCompanion());
        }
        return true;
      case SyncEntity.habitFields:
        final d = habitFieldFromWire(j);
        if (d == null) return true;
        final clash = await (_db.select(
          _db.habitFields,
        )..where((x) => x.key.equals(d.key) & x.id.equals(d.id).not())).get();
        for (final x in clash) {
          await _outbox.dropQueued(SyncEntity.habitFields, x.id);
          await (_db.delete(
            _db.habitFields,
          )..where((r) => r.id.equals(x.id))).go();
        }
        await _db.into(_db.habitFields).insertOnConflictUpdate(d.toCompanion());
        return true;
      case SyncEntity.habitEvents:
        final e = habitEventFromWire(j);
        if (e != null) {
          await _db
              .into(_db.habitEvents)
              .insertOnConflictUpdate(e.toCompanion());
        }
        return true;
      default:
        return false;
    }
  }

  /// Before a tombstone deletes the row: what the cascade needs afterwards
  /// (the `key` of a category / field def — a tombstone only carries the id).
  Future<String?> beforeTombstone(String entity, String id) async {
    switch (entity) {
      case SyncEntity.personCategories:
        return (await (_db.select(
          _db.personCategories,
        )..where((r) => r.id.equals(id))).getSingleOrNull())?.key;
      case SyncEntity.personFields:
        return (await (_db.select(
          _db.personFields,
        )..where((r) => r.id.equals(id))).getSingleOrNull())?.key;
      case SyncEntity.habitFields:
        return (await (_db.select(
          _db.habitFields,
        )..where((r) => r.id.equals(id))).getSingleOrNull())?.key;
      default:
        return null;
    }
  }

  /// After a tombstone deleted a local row.
  Future<void> onTombstone(String entity, String id, String? key) async {
    switch (entity) {
      case SyncEntity.people:
        await _cascades.personDeleted(id);
      case SyncEntity.personCategories:
        if (key != null) await _cascades.personCategoryDeleted(key);
      case SyncEntity.personFields:
        if (key != null) await _cascades.personFieldDeleted(key);
      case SyncEntity.habitFields:
        if (key != null) await _cascades.habitFieldDeleted(key);
    }
  }

  /// Keys added after v7 whose value a push may only carry once the local row
  /// is known to hold the server's data (see `SyncMeta.enrichmentSeen`).
  static const _enrichmentKeys = <String, List<String>>{
    SyncEntity.habits: ['tools'],
    SyncEntity.habitLogs: ['extra'],
    SyncEntity.food: ['caloriesMax', 'tags'],
  };

  /// [data] without the enrichment keys of [entity] ("absent = unchanged" on
  /// the server) — used until a pull from an enrichment-aware server has
  /// refreshed the rows, so an upgraded device never overwrites the server's
  /// `tools` / `extra` / `tags` / `caloriesMax` with v7 defaults.
  static Json? withoutEnrichment(String entity, Json? data) {
    final keys = _enrichmentKeys[entity];
    if (keys == null || data == null) return data;
    return {...data}..removeWhere((k, _) => keys.contains(k));
  }
}
