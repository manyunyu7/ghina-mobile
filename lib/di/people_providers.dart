/// Composition root, part 6: People ("Orang", `docs/people.md`) — offline-first
/// metadata through sync, plus the online-only notes. Tests override the
/// repository providers in `core_providers.dart` and
/// [peopleNotesRepositoryProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';

// ================================================================ reads

/// People + categories + field defs + dates (the list screen).
final watchPeopleOverviewProvider = StreamProvider.autoDispose<PeopleOverview>(
  (ref) => WatchPeopleOverview(
    ref.watch(personRepositoryProvider),
    ref.watch(personCategoryRepositoryProvider),
    ref.watch(personFieldRepositoryProvider),
    ref.watch(personDateRepositoryProvider),
  )(),
);

/// One person with its category, applicable defs and dates; null if gone.
final watchPersonDetailProvider = StreamProvider.autoDispose
    .family<PersonDetail?, String>(
      (ref, id) => WatchPersonDetail(
        ref.watch(personRepositoryProvider),
        ref.watch(personCategoryRepositoryProvider),
        ref.watch(personFieldRepositoryProvider),
        ref.watch(personDateRepositoryProvider),
      )(id),
    );

final watchPersonCategoriesProvider =
    StreamProvider.autoDispose<List<PersonCategory>>(
      (ref) =>
          WatchPersonCategories(ref.watch(personCategoryRepositoryProvider))(),
    );

final watchPersonFieldsProvider =
    StreamProvider.autoDispose<List<PersonFieldDef>>(
      (ref) => WatchPersonFields(ref.watch(personFieldRepositoryProvider))(),
    );

/// Birthdays + important dates in the next 60 days (the list's top card).
final watchUpcomingPeopleProvider =
    StreamProvider.autoDispose<List<UpcomingEvent>>(
      (ref) => WatchUpcomingPeople(
        ref.watch(personRepositoryProvider),
        ref.watch(personDateRepositoryProvider),
        ref.watch(tickSourceProvider),
      )(),
    );

/// Birthdays / important dates in `(fromKey, toKey)` (`YYYY-MM-DD`): the
/// read-only calendar overlay.
final watchPeopleEventsInRangeProvider = StreamProvider.autoDispose
    .family<List<EventOccurrence>, ({String from, String to})>(
      (ref, r) => WatchPeopleEventsInRange(
        ref.watch(personRepositoryProvider),
        ref.watch(personDateRepositoryProvider),
      )(r.from, r.to),
    );

// ================================================================ writes

/// `({id?, input: PersonInput, dates: [PersonDateInput]})` → [Person].
final savePersonProvider = Provider<SavePerson>(
  (ref) => SavePerson(
    ref.watch(personRepositoryProvider),
    ref.watch(personCategoryRepositoryProvider),
    ref.watch(personFieldRepositoryProvider),
    ref.watch(personDateRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — also deletes its important dates.
final deletePersonProvider = Provider<DeletePerson>(
  (ref) => DeletePerson(ref.watch(personRepositoryProvider)),
);

/// `(label:, emoji:)` → [PersonCategory].
final createPersonCategoryProvider = Provider<CreatePersonCategory>(
  (ref) => CreatePersonCategory(
    ref.watch(personCategoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, label:, emoji:)`.
final updatePersonCategoryProvider = Provider<UpdatePersonCategory>(
  (ref) => UpdatePersonCategory(
    ref.watch(personCategoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `([ids in new order])`.
final reorderPersonCategoriesProvider = Provider<ReorderPersonCategories>(
  (ref) => ReorderPersonCategories(
    ref.watch(personCategoryRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(PersonFieldInput(label, type, options, appliesTo, showInList))`.
final createPersonFieldProvider = Provider<CreatePersonField>(
  (ref) => CreatePersonField(
    ref.watch(personFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, label:, appliesTo:, showInList:)` — key/type/options never change.
final updatePersonFieldProvider = Provider<UpdatePersonField>(
  (ref) => UpdatePersonField(
    ref.watch(personFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final reorderPersonFieldsProvider = Provider<ReorderPersonFields>(
  (ref) => ReorderPersonFields(
    ref.watch(personFieldRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

// ================================================================ notes (online-only)

/// `(personId)` → [PersonNotes]. Call on tap for `sensitive` people.
final getPersonNotesProvider = Provider<GetPersonNotes>(
  (ref) => GetPersonNotes(ref.watch(peopleNotesRepositoryProvider)),
);

/// `(personId, notes, expectedUpdatedAt:)` — a stale one is `ConflictFailure`.
final replacePersonNotesProvider = Provider<ReplacePersonNotes>(
  (ref) => ReplacePersonNotes(
    ref.watch(peopleNotesRepositoryProvider),
    ref.watch(personRepositoryProvider),
    ref.watch(syncServiceProvider),
  ),
);

/// `(personId, text, heading:)` — "tambah catatan".
final appendPersonNotesProvider = Provider<AppendPersonNotes>(
  (ref) => AppendPersonNotes(
    ref.watch(peopleNotesRepositoryProvider),
    ref.watch(personRepositoryProvider),
    ref.watch(syncServiceProvider),
  ),
);
