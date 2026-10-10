import 'package:drift/drift.dart';

import '../datasources/local/app_database.dart';
import '../models/dreams_wire.dart';
import '../models/entity_names.dart';
import '../models/wire.dart' show Json;
import 'local_cascades.dart';
import 'outbox.dart';

/// The sync engine's hooks for the Dreams entities (`dreams`, `dreamSteps`,
/// `dreamMetrics`, `dreamCategories`, `dreamFields`; `docs/dreams.md`,
/// `docs/mobile-sync.md` → "Dreams"), kept out of `sync_engine.dart`.
///
/// - Pulls are plain upserts. A pulled category / field def whose `key` is held
///   by a *different* local id (created offline) wins over the local one, which
///   is dropped with its queued upsert (the push would be answered `duplicate`).
///   Dreams reference categories and fields by **key**, so nothing is remapped.
/// - Tombstones apply the delete relations locally ([LocalCascades]); the server
///   did the same and the touched rows re-sync.
/// - `duplicate` / `rejected` pushes need nothing beyond the engine's generic
///   handling (drop the queued entry and the local row; a pull brings the
///   server's version).
class DreamsSync {
  DreamsSync(this._db, this._outbox, this._cascades);

  final AppDatabase _db;
  final Outbox _outbox;
  final LocalCascades _cascades;

  TableInfo<Table, dynamic>? table(String entity) => switch (entity) {
    SyncEntity.dreams => _db.dreams,
    SyncEntity.dreamSteps => _db.dreamSteps,
    SyncEntity.dreamMetrics => _db.dreamMetrics,
    SyncEntity.dreamCategories => _db.dreamCategories,
    SyncEntity.dreamFields => _db.dreamFields,
    _ => null,
  };

  /// Applies a pulled row of one of the five entities; false for others.
  /// Rows that can't be parsed (newer server) are skipped.
  Future<bool> upsertPulled(String entity, Json j) async {
    switch (entity) {
      case SyncEntity.dreams:
        final d = dreamFromWire(j);
        if (d != null) {
          await _db.into(_db.dreams).insertOnConflictUpdate(d.toCompanion());
        }
        return true;
      case SyncEntity.dreamSteps:
        final s = dreamStepFromWire(j);
        if (s != null) {
          await _db
              .into(_db.dreamSteps)
              .insertOnConflictUpdate(s.toCompanion());
        }
        return true;
      case SyncEntity.dreamMetrics:
        final m = dreamMetricFromWire(j);
        if (m != null) {
          await _db
              .into(_db.dreamMetrics)
              .insertOnConflictUpdate(m.toCompanion());
        }
        return true;
      case SyncEntity.dreamCategories:
        final c = dreamCategoryFromWire(j);
        if (c == null) return true;
        final clash = await (_db.select(
          _db.dreamCategories,
        )..where((x) => x.key.equals(c.key) & x.id.equals(c.id).not())).get();
        for (final x in clash) {
          await _outbox.dropQueued(SyncEntity.dreamCategories, x.id);
          await (_db.delete(
            _db.dreamCategories,
          )..where((r) => r.id.equals(x.id))).go();
        }
        await _db
            .into(_db.dreamCategories)
            .insertOnConflictUpdate(c.toCompanion());
        return true;
      case SyncEntity.dreamFields:
        final d = dreamFieldFromWire(j);
        if (d == null) return true;
        final clash = await (_db.select(
          _db.dreamFields,
        )..where((x) => x.key.equals(d.key) & x.id.equals(d.id).not())).get();
        for (final x in clash) {
          await _outbox.dropQueued(SyncEntity.dreamFields, x.id);
          await (_db.delete(
            _db.dreamFields,
          )..where((r) => r.id.equals(x.id))).go();
        }
        await _db.into(_db.dreamFields).insertOnConflictUpdate(d.toCompanion());
        return true;
      default:
        return false;
    }
  }

  /// Before a tombstone deletes the row: the `key` of a category / field def
  /// (a tombstone only carries the id, and the cascade needs the key).
  Future<String?> beforeTombstone(String entity, String id) async {
    switch (entity) {
      case SyncEntity.dreamCategories:
        return (await (_db.select(
          _db.dreamCategories,
        )..where((r) => r.id.equals(id))).getSingleOrNull())?.key;
      case SyncEntity.dreamFields:
        return (await (_db.select(
          _db.dreamFields,
        )..where((r) => r.id.equals(id))).getSingleOrNull())?.key;
      default:
        return null;
    }
  }

  /// After a tombstone deleted a local row.
  Future<void> onTombstone(String entity, String id, String? key) async {
    switch (entity) {
      case SyncEntity.dreams:
        await _cascades.dreamDeleted(id);
      case SyncEntity.dreamMetrics:
        await _cascades.dreamMetricDeleted(id);
      case SyncEntity.dreamCategories:
        if (key != null) await _cascades.dreamCategoryDeleted(key);
      case SyncEntity.dreamFields:
        if (key != null) await _cascades.dreamFieldDeleted(key);
    }
  }
}
