import 'package:drift/drift.dart';

import '../datasources/local/app_database.dart';
import '../models/agenda_wire.dart';
import '../models/entity_names.dart';
import '../models/wire.dart' show Json;

/// The sync engine's hooks for `reminders` and `calendarEvents`
/// (`docs/mobile-sync.md`), kept out of `sync_engine.dart`. Both have no
/// links and no unique keys: a pull is a plain upsert, a tombstone a plain
/// delete, nothing cascades.
class AgendaSync {
  AgendaSync(this._db);

  final AppDatabase _db;

  TableInfo<Table, dynamic>? table(String entity) => switch (entity) {
    SyncEntity.reminders => _db.reminderItems,
    SyncEntity.calendarEvents => _db.calendarEvents,
    _ => null,
  };

  /// Applies a pulled row of one of the two entities; false for others.
  /// Rows that can't be parsed (newer server) are skipped.
  Future<bool> upsertPulled(String entity, Json j) async {
    switch (entity) {
      case SyncEntity.reminders:
        final r = reminderFromWire(j);
        if (r != null) {
          await _db
              .into(_db.reminderItems)
              .insertOnConflictUpdate(r.toCompanion());
        }
        return true;
      case SyncEntity.calendarEvents:
        final e = calendarEventFromWire(j);
        if (e != null) {
          await _db
              .into(_db.calendarEvents)
              .insertOnConflictUpdate(e.toCompanion());
        }
        return true;
      default:
        return false;
    }
  }
}
