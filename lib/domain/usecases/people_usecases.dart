/// People ("Orang") use cases: offline-first metadata (through the synced
/// repositories) and the online-only notes. Mutations return `Result<T>` and
/// never throw; watch use cases are streams.
library;

import 'dart:async';

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'people_rules.dart';
import 'task_usecases.dart' show TickSource;

// ================================================================ reads

/// People + categories + field defs + dates, in one stream.
final class WatchPeopleOverview {
  const WatchPeopleOverview(
    this._people,
    this._categories,
    this._fields,
    this._dates,
  );
  final PersonRepository _people;
  final PersonCategoryRepository _categories;
  final PersonFieldRepository _fields;
  final PersonDateRepository _dates;

  Stream<PeopleOverview> call() => combineLatestList(
    [
      _people.watchAll(),
      _categories.watchAll(),
      _fields.watchAll(),
      _dates.watchAll(),
    ],
    (v) => PeopleOverview(
      people: v[0] as List<Person>,
      categories: v[1] as List<PersonCategory>,
      defs: v[2] as List<PersonFieldDef>,
      dates: v[3] as List<PersonDate>,
    ),
  );
}

/// One person with its category, applicable field defs and dates; null when
/// the person doesn't exist (any more).
final class WatchPersonDetail {
  const WatchPersonDetail(
    this._people,
    this._categories,
    this._fields,
    this._dates,
  );
  final PersonRepository _people;
  final PersonCategoryRepository _categories;
  final PersonFieldRepository _fields;
  final PersonDateRepository _dates;

  Stream<PersonDetail?> call(String id) => combineLatestList(
    [
      _people.watchById(id),
      _categories.watchAll(),
      _fields.watchAll(),
      _dates.watchForPerson(id),
    ],
    (v) {
      final p = v[0] as Person?;
      if (p == null) return null;
      final cats = v[1] as List<PersonCategory>;
      return PersonDetail(
        person: p,
        category: cats.where((c) => c.key == p.category).firstOrNull,
        defs: defsFor(v[2] as List<PersonFieldDef>, p.category),
        dates: v[3] as List<PersonDate>,
      );
    },
  );
}

final class WatchPersonCategories {
  const WatchPersonCategories(this._repo);
  final PersonCategoryRepository _repo;
  Stream<List<PersonCategory>> call() => _repo.watchAll();
}

final class WatchPersonFields {
  const WatchPersonFields(this._repo);
  final PersonFieldRepository _repo;
  Stream<List<PersonFieldDef>> call() => _repo.watchAll();
}

/// Birthdays and important dates in the next [days] days (default 60), soonest
/// first. "Today" is the device's local date, re-evaluated every minute.
final class WatchUpcomingPeople {
  const WatchUpcomingPeople(this._people, this._dates, this._ticks);
  final PersonRepository _people;
  final PersonDateRepository _dates;
  final TickSource _ticks;

  Stream<List<UpcomingEvent>> call({int days = upcomingPeopleDays}) =>
      combineLatestList(
        [_people.watchAll(), _dates.watchAll(), _ticks()],
        (v) => upcomingEvents(
          v[0] as List<Person>,
          v[1] as List<PersonDate>,
          peopleDateKey(v[2] as DateTime),
          days,
        ),
      ).distinct(_eq);

  static bool _eq(List<UpcomingEvent> a, List<UpcomingEvent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Birthdays / important dates landing in [fromKey]..[toKey] (read-only
/// overlay of the calendar; never stored as events).
final class WatchPeopleEventsInRange {
  const WatchPeopleEventsInRange(this._people, this._dates);
  final PersonRepository _people;
  final PersonDateRepository _dates;

  Stream<List<EventOccurrence>> call(String fromKey, String toKey) =>
      combineLatestList(
        [_people.watchAll(), _dates.watchAll()],
        (v) => eventsInRange(
          v[0] as List<Person>,
          v[1] as List<PersonDate>,
          fromKey,
          toKey,
        ),
      );
}

// ================================================================ person CRUD

Future<Person> _requirePerson(PersonRepository repo, String id) async {
  final p = await repo.getById(id);
  if (p == null) throw const NotFoundFailure('Orang tidak ditemukan');
  return p;
}

/// Creates or updates a person together with its important dates, all-or-
/// nothing. Notes are not part of this (online-only). Dates with an id are
/// updated, without one created, and the person's dates missing from [dates]
/// are deleted.
final class SavePerson {
  const SavePerson(
    this._people,
    this._categories,
    this._fields,
    this._dates,
    this._uow,
    this._clock,
  );
  final PersonRepository _people;
  final PersonCategoryRepository _categories;
  final PersonFieldRepository _fields;
  final PersonDateRepository _dates;
  final UnitOfWork _uow;
  final Clock _clock;

  /// `ValidationFailure(field:)`: name, fullName, category, relation, status,
  /// howMet, summary, birthday, phone, instagram, email, address,
  /// organization, tags, fields, label, date, remindDaysBefore.
  Future<Result<Person>> call({
    String? id,
    required PersonInput input,
    List<PersonDateInput> dates = const [],
  }) => guard(() async {
    final now = _clock.now();
    final old = id == null ? null : await _requirePerson(_people, id);
    final cats = await _categories.getAll();
    final defs = await _fields.getAll();
    final personId = old?.id ?? newId();
    final person = validatePerson(
      id: personId,
      input: input,
      categoryKeys: [for (final c in cats) c.key],
      defs: defs,
      currentYear: now.year,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      hasNotes: old?.hasNotes ?? false,
      notesLength: old?.notesLength ?? 0,
    );
    final existing = old == null
        ? const <PersonDate>[]
        : await _dates.getForPerson(personId);
    final byId = {for (final d in existing) d.id: d};
    final writes = <PersonDate>[];
    final keep = <String>{};
    for (final di in dates) {
      final prev = di.id == null ? null : byId[di.id];
      final d = validatePersonDate(
        id: prev?.id ?? newId(),
        personId: personId,
        input: di,
        currentYear: now.year,
        createdAt: prev?.createdAt ?? now,
        updatedAt: now,
      );
      keep.add(d.id);
      // Untouched dates are not re-pushed.
      if (prev != null && _sameDate(prev, d)) continue;
      writes.add(d);
    }
    await _uow.run(() async {
      await _people.save(person);
      for (final d in writes) {
        await _dates.save(d);
      }
      for (final d in existing) {
        if (!keep.contains(d.id)) await _dates.delete(d.id);
      }
    });
    return person;
  });

  static bool _sameDate(PersonDate a, PersonDate b) =>
      a.label == b.label &&
      a.kind == b.kind &&
      a.month == b.month &&
      a.day == b.day &&
      a.year == b.year &&
      a.remindDaysBefore == b.remindDaysBefore;
}

/// Deletes the person and its important dates (confirm in the UI). The notes
/// on the server go with it.
final class DeletePerson {
  const DeletePerson(this._people);
  final PersonRepository _people;

  Future<Result<void>> call(String id) => guard(() async {
    await _requirePerson(_people, id);
    await _people.delete(id);
  });
}

// ================================================================ categories + fields

/// Unique key for [label] among [taken]: the slug, then `slug_2`, `slug_3`…
String uniqueKey(
  String label,
  Iterable<String> taken, {
  String fallback = 'x',
}) {
  final base = slugifyKey(label) ?? fallback;
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  for (var i = 2; i < 1000; i++) {
    final suffix = '_$i';
    final cut = base.length + suffix.length > 40
        ? base.substring(0, 40 - suffix.length)
        : base;
    final k = '$cut$suffix';
    if (!used.contains(k)) return k;
  }
  return '${base}_${newId().substring(0, 6)}';
}

/// Adds a category at the end of the order; the `key` is a slug of the label
/// and never changes afterwards.
final class CreatePersonCategory {
  const CreatePersonCategory(this._repo, this._clock);
  final PersonCategoryRepository _repo;
  final Clock _clock;

  Future<Result<PersonCategory>> call({
    required String label,
    String emoji = '👤',
  }) => guard(() async {
    final v = validateCategoryText(label, emoji);
    final all = await _repo.getAll();
    final key = uniqueKey(v.label, [
      for (final c in all) c.key,
    ], fallback: 'kategori');
    final order = all.fold(-1, (m, c) => c.sortOrder > m ? c.sortOrder : m);
    final now = _clock.now();
    final c = PersonCategory(
      id: newId(),
      key: key,
      label: v.label,
      emoji: v.emoji,
      sortOrder: order + 1,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(c);
    return c;
  });
}

/// Renames a category (label and emoji only; the key never changes).
final class UpdatePersonCategory {
  const UpdatePersonCategory(this._repo, this._clock);
  final PersonCategoryRepository _repo;
  final Clock _clock;

  Future<Result<PersonCategory>> call(
    String id, {
    required String label,
    required String emoji,
  }) => guard(() async {
    final c = await _repo.getById(id);
    if (c == null) throw const NotFoundFailure('Kategori tidak ditemukan');
    final v = validateCategoryText(label, emoji);
    final next = c.copyWith(
      label: v.label,
      emoji: v.emoji,
      updatedAt: _clock.now(),
    );
    await _repo.save(next);
    return next;
  });
}

/// `sortOrder` = index of each id.
final class ReorderPersonCategories {
  const ReorderPersonCategories(this._repo, this._uow, this._clock);
  final PersonCategoryRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final c = await _repo.getById(id);
        if (c == null || c.sortOrder == i) continue;
        await _repo.save(c.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// The form of a new custom field.
final class PersonFieldInput {
  const PersonFieldInput({
    required this.label,
    this.type = PersonFieldType.text,
    this.options,
    this.appliesTo,
    this.showInList = false,
  });

  final String label;
  final PersonFieldType type;

  /// Required for [PersonFieldType.select].
  final List<String>? options;

  /// Category keys; null/empty = all.
  final List<String>? appliesTo;
  final bool showInList;
}

/// Adds a custom field ("Tambah kolom") at the end of the order.
final class CreatePersonField {
  const CreatePersonField(this._repo, this._clock);
  final PersonFieldRepository _repo;
  final Clock _clock;

  Future<Result<PersonFieldDef>> call(PersonFieldInput input) =>
      guard(() async {
        final label = validateFieldLabel(input.label);
        final options = input.type == PersonFieldType.select
            ? validateOptions(input.options ?? const [])
            : null;
        final all = await _repo.getAll();
        final key = uniqueKey(label, [
          for (final d in all) d.key,
        ], fallback: 'kolom');
        final order = all.fold(-1, (m, d) => d.sortOrder > m ? d.sortOrder : m);
        final now = _clock.now();
        final applies = input.appliesTo == null || input.appliesTo!.isEmpty
            ? null
            : input.appliesTo;
        final d = PersonFieldDef(
          id: newId(),
          key: key,
          label: label,
          type: input.type,
          options: options,
          appliesTo: applies,
          sortOrder: order + 1,
          showInList: input.showInList,
          createdAt: now,
          updatedAt: now,
        );
        await _repo.save(d);
        return d;
      });
}

/// Renames a field or changes where it shows (label, appliesTo, showInList).
/// The key, type and options never change here — no destructive retype.
final class UpdatePersonField {
  const UpdatePersonField(this._repo, this._clock);
  final PersonFieldRepository _repo;
  final Clock _clock;

  Future<Result<PersonFieldDef>> call(
    String id, {
    String? label,
    List<String>? appliesTo,
    bool? showInList,
  }) => guard(() async {
    final d = await _repo.getById(id);
    if (d == null) throw const NotFoundFailure('Kolom tidak ditemukan');
    final next = d.copyWith(
      label: label == null ? null : validateFieldLabel(label),
      appliesTo: appliesTo,
      showInList: showInList,
      updatedAt: _clock.now(),
    );
    await _repo.save(next);
    return next;
  });
}

/// `sortOrder` = index of each id.
final class ReorderPersonFields {
  const ReorderPersonFields(this._repo, this._uow, this._clock);
  final PersonFieldRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final d = await _repo.getById(id);
        if (d == null || d.sortOrder == i) continue;
        await _repo.save(d.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

// ================================================================ notes (online-only)

/// Fetches the notes (`GET /api/mobile/people/{id}`). Call it only when the
/// notes are about to be shown — for a `sensitive` person that is on tap.
final class GetPersonNotes {
  const GetPersonNotes(this._notes);
  final PeopleNotesRepository _notes;

  Future<Result<PersonNotes>> call(String personId) =>
      guard(() => _notes.fetch(personId));
}

/// Replaces the notes (`PUT …/notes`). Pass [expectedUpdatedAt] from the
/// [PersonNotes] you read: when the notes changed elsewhere meanwhile the
/// result is `Err(ConflictFailure)` with a clear message.
final class ReplacePersonNotes {
  const ReplacePersonNotes(this._notes, this._people, this._sync);
  final PeopleNotesRepository _notes;
  final PersonRepository _people;
  final SyncService _sync;

  Future<Result<PersonNotesWrite>> call(
    String personId,
    String notes, {
    DateTime? expectedUpdatedAt,
  }) => guard(() async {
    if (notes.length > personNotesMax) {
      throw ValidationFailure(
        'Catatan terlalu panjang (maks $personNotesMax karakter)',
        field: 'notes',
      );
    }
    final w = await _notes.replace(
      personId,
      notes,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    await _afterWrite(_people, _sync, personId);
    return w;
  });
}

/// Appends to the notes (`POST …/notes/append`), optionally under a heading.
final class AppendPersonNotes {
  const AppendPersonNotes(this._notes, this._people, this._sync);
  final PeopleNotesRepository _notes;
  final PersonRepository _people;
  final SyncService _sync;

  Future<Result<PersonNotesWrite>> call(
    String personId,
    String text, {
    String? heading,
  }) => guard(() async {
    final t = text.trim();
    if (t.isEmpty) {
      throw const ValidationFailure('Catatannya masih kosong', field: 'notes');
    }
    final w = await _notes.append(personId, t, heading: heading);
    await _afterWrite(_people, _sync, personId);
    return w;
  });
}

/// A notes write moves the server row's `updatedAt` forward: re-stamp a queued
/// metadata edit of the person (so it isn't `skipped` by last-write-wins) and
/// sync in the background so `hasNotes` / `notesLength` refresh.
Future<void> _afterWrite(
  PersonRepository people,
  SyncService sync,
  String personId,
) async {
  try {
    await people.refreshPending(personId);
  } catch (_) {}
  unawaited(sync.syncNow().catchError((Object _) {}));
}
