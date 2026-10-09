import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ghina/di/core_providers.dart';

import '../domain/fakes.dart' show FakeUnitOfWork;
import '../domain/people_fakes.dart';

/// In-memory People repositories (+ the online-only notes) for tests that run
/// the app's providers on fakes (no drift). Add to any harness that watches
/// the calendar (birthday overlay) or the reminders (birthday notifications).
List<Override> peopleFakeOverrides({
  FakePersonRepository? people,
  FakePersonCategoryRepository? categories,
  FakePersonFieldRepository? fields,
  FakePersonDateRepository? dates,
  FakePeopleNotes? notes,
  FakeUnitOfWork? uow,
}) => [
  unitOfWorkProvider.overrideWithValue(uow ?? FakeUnitOfWork()),
  personRepositoryProvider.overrideWithValue(people ?? FakePersonRepository()),
  personCategoryRepositoryProvider.overrideWithValue(
    categories ?? FakePersonCategoryRepository(),
  ),
  personFieldRepositoryProvider.overrideWithValue(
    fields ?? FakePersonFieldRepository(),
  ),
  personDateRepositoryProvider.overrideWithValue(
    dates ?? FakePersonDateRepository(),
  ),
  peopleNotesRepositoryProvider.overrideWithValue(notes ?? FakePeopleNotes()),
];
