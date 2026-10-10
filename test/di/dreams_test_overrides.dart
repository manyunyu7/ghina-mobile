import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ghina/di/core_providers.dart';

import '../domain/dreams_fakes.dart';
import '../domain/fakes.dart' show FakeUnitOfWork;

/// In-memory Dreams repositories (+ the online-only reads) for tests that run
/// the app's providers on fakes (no drift). Add to any harness that shows
/// Dreams screens or the Mimpi summary.
List<Override> dreamsFakeOverrides({
  FakeDreamRepository? dreams,
  FakeDreamStepRepository? steps,
  FakeDreamMetricRepository? metrics,
  FakeDreamCategoryRepository? categories,
  FakeDreamFieldRepository? fields,
  FakeDreamOnlineRepository? online,
  FakeUnitOfWork? uow,
}) {
  final st = steps ?? FakeDreamStepRepository();
  final mt = metrics ?? FakeDreamMetricRepository();
  return [
    unitOfWorkProvider.overrideWithValue(uow ?? FakeUnitOfWork()),
    dreamRepositoryProvider.overrideWithValue(
      dreams ?? FakeDreamRepository(steps: st, metrics: mt),
    ),
    dreamStepRepositoryProvider.overrideWithValue(st),
    dreamMetricRepositoryProvider.overrideWithValue(mt),
    dreamCategoryRepositoryProvider.overrideWithValue(
      categories ?? FakeDreamCategoryRepository(),
    ),
    dreamFieldRepositoryProvider.overrideWithValue(
      fields ?? FakeDreamFieldRepository(),
    ),
    dreamOnlineRepositoryProvider.overrideWithValue(
      online ?? FakeDreamOnlineRepository(),
    ),
  ];
}
