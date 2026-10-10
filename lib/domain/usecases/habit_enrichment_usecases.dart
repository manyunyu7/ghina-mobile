/// Habit enrichment use cases (`docs/habits-food-enrichment.md`): coping tools,
/// neutral events, user-defined dimensions (`habitFields`) and `extra` values
/// on logs — all offline through the synced repositories — plus the
/// online-only notes and analysis. Mutations return `Result<T>` and never
/// throw.
library;

import 'dart:async';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'habit_enrichment_rules.dart';
import 'habit_rules.dart' show cleanHabitLine, requireHabitDate;
import 'people_usecases.dart' show uniqueKey;

Future<Habit> _requireHabit(HabitRepository repo, String id) async {
  final h = await repo.getById(id);
  if (h == null) throw const NotFoundFailure('Kebiasaan tidak ditemukan');
  return h;
}

// ================================================================ reads

/// Every dimension definition (global and per habit), by `sortOrder`.
final class WatchHabitFields {
  const WatchHabitFields(this._fields);
  final HabitFieldRepository _fields;

  Stream<List<HabitFieldDef>> call() => _fields.watchAll();
}

/// The events of one habit, newest first.
final class WatchHabitEvents {
  const WatchHabitEvents(this._events);
  final HabitEventRepository _events;

  Stream<List<HabitEvent>> call(String habitId) =>
      _events.watch(habitId: habitId);
}

// ================================================================ tools

/// Replaces the coping tools of a habit (the whole list, ≤ 30).
final class SetHabitTools {
  const SetHabitTools(this._habits, this._clock);
  final HabitRepository _habits;
  final Clock _clock;

  Future<Result<Habit>> call(String habitId, List<HabitTool> tools) =>
      guard(() async {
        final h = await _requireHabit(_habits, habitId);
        final next = h.copyWith(
          tools: validateHabitTools(tools),
          updatedAt: _clock.now(),
        );
        await _habits.save(next);
        return next;
      });
}

// ================================================================ events

/// The form of an event. A null [id] creates; an id of a stored event edits.
final class HabitEventInput {
  const HabitEventInput({
    this.id,
    required this.habitId,
    required this.date,
    this.kind = HabitEventKind.event,
    required this.label,
    this.note,
    this.at,
    this.extra = const {},
  });

  final String? id;
  final String habitId;

  /// The day (its time part is ignored).
  final DateTime date;
  final HabitEventKind kind;

  /// 1–60.
  final String label;

  /// ≤ 2000.
  final String? note;
  final DateTime? at;

  /// Dimension values, key → `String | num | bool` (null = leave out).
  final Map<String, Object?> extra;
}

/// Adds or edits a journal day, milestone or neutral event. Events never
/// affect streaks.
final class SaveHabitEvent {
  const SaveHabitEvent(this._events, this._habits, this._fields, this._clock);
  final HabitEventRepository _events;
  final HabitRepository _habits;
  final HabitFieldRepository _fields;
  final Clock _clock;

  Future<Result<HabitEvent>> call(HabitEventInput input) => guard(() async {
    final h = await _requireHabit(_habits, input.habitId);
    final now = _clock.now();
    final old = input.id == null ? null : await _events.getById(input.id!);
    if (old != null && old.habitId != h.id) {
      throw const NotFoundFailure('Kejadian tidak ditemukan');
    }
    final extra = validateExtra(
      input.extra,
      fieldsForScope(await _fields.getAll(), h.id, input.kind.wire),
    );
    final e = HabitEvent(
      id: old?.id ?? input.id ?? newId(),
      habitId: h.id,
      date: requireHabitDate(dateKey(input.date)),
      kind: input.kind,
      label: validateEventLabel(input.label),
      note: validateEventNote(input.note),
      at: input.at,
      extra: extra,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await _events.save(e);
    return e;
  });
}

final class DeleteHabitEvent {
  const DeleteHabitEvent(this._events);
  final HabitEventRepository _events;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _events.getById(id) == null) {
      throw const NotFoundFailure('Kejadian tidak ditemukan');
    }
    await _events.delete(id);
  });
}

// ================================================================ dimensions

/// The form of a new dimension.
final class HabitFieldInput {
  const HabitFieldInput({
    required this.label,
    this.type = HabitFieldType.text,
    this.habitId,
    this.options,
    this.min,
    this.max,
    this.appliesTo,
  });

  final String label;
  final HabitFieldType type;

  /// null = every habit.
  final String? habitId;

  /// Required for [HabitFieldType.select] (1–50 × ≤ 80).
  final List<String>? options;

  /// [HabitFieldType.scale] only (default 1 / 10, min < max).
  final int? min;
  final int? max;

  /// Subset of [habitFieldScopes]; null/empty = all.
  final List<String>? appliesTo;
}

String _fieldLabel(String? raw) {
  final s = cleanHabitLine(raw);
  if (s.isEmpty) {
    throw const ValidationFailure('Nama dimensi wajib diisi', field: 'label');
  }
  if (s.length > 80) {
    throw const ValidationFailure(
      'Nama dimensi maksimal 80 karakter',
      field: 'label',
    );
  }
  return s;
}

List<String>? _appliesTo(List<String>? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final v in raw) {
    if (!habitFieldScopes.contains(v)) {
      throw const ValidationFailure(
        'Berlaku untuk tidak valid',
        field: 'appliesTo',
      );
    }
  }
  final out = <String>[
    for (final s in habitFieldScopes)
      if (raw.contains(s)) s,
  ];
  return out.length == habitFieldScopes.length ? null : out;
}

List<String> _options(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final o in raw) {
    final v = cleanHabitLine(o);
    if (v.isEmpty || !seen.add(v)) continue;
    if (v.length > 80) {
      throw const ValidationFailure(
        'Opsi maksimal 80 karakter',
        field: 'options',
      );
    }
    out.add(v);
  }
  if (out.isEmpty) {
    throw const ValidationFailure(
      'Pilihan butuh minimal satu opsi',
      field: 'options',
    );
  }
  if (out.length > 50) {
    throw const ValidationFailure('Maksimal 50 opsi', field: 'options');
  }
  return out;
}

/// Adds a dimension at the end of the order. Its `key` is a slug of the label
/// (unique among dimension keys) and never changes afterwards.
final class CreateHabitField {
  const CreateHabitField(this._fields, this._habits, this._clock);
  final HabitFieldRepository _fields;
  final HabitRepository _habits;
  final Clock _clock;

  Future<Result<HabitFieldDef>> call(HabitFieldInput input) => guard(() async {
    final label = _fieldLabel(input.label);
    if (input.habitId != null) await _requireHabit(_habits, input.habitId!);
    final isScale = input.type == HabitFieldType.scale;
    final lo = isScale ? (input.min ?? habitScaleDefaultMin) : null;
    final hi = isScale ? (input.max ?? habitScaleDefaultMax) : null;
    if (isScale && lo! >= hi!) {
      throw const ValidationFailure(
        'Skala: angka awal harus lebih kecil dari angka akhir',
        field: 'min',
      );
    }
    final all = await _fields.getAll();
    final key = uniqueKey(label, [
      for (final d in all) d.key,
    ], fallback: 'dimensi');
    final order = all.fold(-1, (m, d) => d.sortOrder > m ? d.sortOrder : m);
    final now = _clock.now();
    final d = HabitFieldDef(
      id: newId(),
      habitId: input.habitId,
      key: key,
      label: label,
      type: input.type,
      options: input.type == HabitFieldType.select
          ? _options(input.options ?? const [])
          : null,
      min: lo,
      max: hi,
      appliesTo: _appliesTo(input.appliesTo),
      sortOrder: order + 1,
      createdAt: now,
      updatedAt: now,
    );
    await _fields.save(d);
    return d;
  });
}

/// Renames a dimension or changes where it shows. The key, type, options and
/// scope never change — no destructive retype.
final class UpdateHabitField {
  const UpdateHabitField(this._fields, this._clock);
  final HabitFieldRepository _fields;
  final Clock _clock;

  Future<Result<HabitFieldDef>> call(
    String id, {
    String? label,
    List<String>? appliesTo,
    bool clearAppliesTo = false,
  }) => guard(() async {
    final d = await _fields.getById(id);
    if (d == null) throw const NotFoundFailure('Dimensi tidak ditemukan');
    final next = HabitFieldDef(
      id: d.id,
      habitId: d.habitId,
      key: d.key,
      label: label == null ? d.label : _fieldLabel(label),
      type: d.type,
      options: d.options,
      min: d.min,
      max: d.max,
      appliesTo: clearAppliesTo
          ? null
          : (appliesTo == null ? d.appliesTo : _appliesTo(appliesTo)),
      sortOrder: d.sortOrder,
      createdAt: d.createdAt,
      updatedAt: _clock.now(),
    );
    await _fields.save(next);
    return next;
  });
}

/// `sortOrder` = index of each id.
final class ReorderHabitFields {
  const ReorderHabitFields(this._fields, this._uow, this._clock);
  final HabitFieldRepository _fields;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final d = await _fields.getById(id);
        if (d == null || d.sortOrder == i) continue;
        await _fields.save(d.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// How many logs and events carry the dimension's key — shown before a
/// delete, because deleting strips the key from all of them.
final class CountHabitFieldUsage {
  const CountHabitFieldUsage(this._fields, this._logs, this._events);
  final HabitFieldRepository _fields;
  final HabitLogRepository _logs;
  final HabitEventRepository _events;

  Future<Result<({int logs, int events})>> call(String id) => guard(() async {
    final d = await _fields.getById(id);
    if (d == null) throw const NotFoundFailure('Dimensi tidak ditemukan');
    return fieldUsage(d.key, await _logs.getAll(), await _events.getAll());
  });
}

/// Deletes a dimension and strips its key from every log and event.
final class DeleteHabitField {
  const DeleteHabitField(this._fields);
  final HabitFieldRepository _fields;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _fields.getById(id) == null) {
      throw const NotFoundFailure('Dimensi tidak ditemukan');
    }
    await _fields.delete(id);
  });
}

// ================================================================ extra on logs

/// Sets dimension values on the day's row of [type] ("tambah detail" after a
/// check-in, or on the urge the emergency screen logged). [patch] is merged
/// per key; a null value removes the key.
final class SetHabitLogExtra {
  const SetHabitLogExtra(this._habits, this._logs, this._fields, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final HabitFieldRepository _fields;
  final Clock _clock;

  Future<Result<HabitLog>> call(
    String habitId,
    DateTime day,
    HabitLogType type,
    Map<String, Object?> patch,
  ) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    final row = await _logs.findByKey(h.id, dateKey(day), type);
    if (row == null) {
      throw const ValidationFailure(
        'Catat kebiasaan hari itu dulu, baru tambah detail',
        field: 'extra',
      );
    }
    final defs = fieldsForScope(await _fields.getAll(), h.id, type.wire);
    final valid = validateExtra({
      for (final e in patch.entries)
        if (e.value != null) e.key: e.value,
    }, defs);
    final merged = mergeExtra(row.extra, {
      ...valid,
      for (final e in patch.entries)
        if (e.value == null) e.key: null,
    });
    if (merged.length > habitExtraMaxKeys) {
      throw const ValidationFailure(
        'Maksimal $habitExtraMaxKeys dimensi per catatan',
        field: 'extra',
      );
    }
    final next = row.copyWith(extra: merged, updatedAt: _clock.now());
    await _logs.save(next);
    return next;
  });
}

// ================================================================ notes (online-only)

/// Fetches the notes (`GET /api/mobile/habits/{id}`). Call it only when the
/// notes are about to be shown — for a `private` habit that is on tap.
final class GetHabitNotes {
  const GetHabitNotes(this._online);
  final HabitOnlineRepository _online;

  Future<Result<HabitNotes>> call(String habitId) =>
      guard(() => _online.fetchNotes(habitId));
}

/// Replaces the notes (`PUT …/notes`). Pass [expectedUpdatedAt] from the
/// [HabitNotes] you read: when the notes changed elsewhere meanwhile the
/// result is `Err(ConflictFailure)`.
final class ReplaceHabitNotes {
  const ReplaceHabitNotes(this._online, this._habits, this._sync);
  final HabitOnlineRepository _online;
  final HabitRepository _habits;
  final SyncService _sync;

  Future<Result<HabitNotesWrite>> call(
    String habitId,
    String notes, {
    DateTime? expectedUpdatedAt,
  }) => guard(() async {
    if (notes.length > habitNotesMarkdownMax) {
      throw const ValidationFailure(
        'Catatan terlalu panjang (maks $habitNotesMarkdownMax karakter)',
        field: 'notes',
      );
    }
    final w = await _online.replaceNotes(
      habitId,
      notes,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    await _afterWrite(_habits, _sync, habitId);
    return w;
  });
}

/// Appends to the notes (`POST …/notes/append`), optionally under a heading.
final class AppendHabitNotes {
  const AppendHabitNotes(this._online, this._habits, this._sync);
  final HabitOnlineRepository _online;
  final HabitRepository _habits;
  final SyncService _sync;

  Future<Result<HabitNotesWrite>> call(
    String habitId,
    String text, {
    String? heading,
  }) => guard(() async {
    final t = text.trim();
    if (t.isEmpty) {
      throw const ValidationFailure('Catatannya masih kosong', field: 'notes');
    }
    final w = await _online.appendNotes(habitId, t, heading: heading);
    await _afterWrite(_habits, _sync, habitId);
    return w;
  });
}

/// A notes write moves the server habit's `updatedAt` forward: re-stamp a
/// queued edit of the habit (so it isn't `skipped` by last-write-wins) and sync
/// in the background so `hasNotes` / `notesLength` refresh.
Future<void> _afterWrite(
  HabitRepository habits,
  SyncService sync,
  String habitId,
) async {
  try {
    await habits.refreshPending(habitId);
  } catch (_) {}
  unawaited(sync.syncNow().catchError((Object _) {}));
}

// ================================================================ analysis (online-only)

/// The server's analysis of one habit over the last [days] days
/// (`GET …/insights`). `Err(NetworkFailure)` offline.
final class FetchHabitAnalysis {
  const FetchHabitAnalysis(this._online, this._clock);
  final HabitOnlineRepository _online;
  final Clock _clock;

  Future<Result<HabitAnalysis>> call(String habitId, {int days = 90}) =>
      guard(() {
        if (days < 1 || days > 730) {
          throw const ValidationFailure('Rentang 1–730 hari', field: 'days');
        }
        return _online.fetchAnalysis(
          habitId,
          days: days,
          today: dateKey(_clock.now()),
        );
      });
}
