/// Composition root, part 7: Dreams ("Mimpi", `docs/dreams.md`). The synced
/// tables (dreams, steps, metrics, categories, custom columns) are offline-first
/// through sync; the computed values (progress, readings, summary) are
/// online-only. Tests override the repository providers in `core_providers.dart`
/// and [dreamOnlineRepositoryProvider] (see `test/di/dreams_test_overrides.dart`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';

// ================================================================ reads (local)

/// Every dream, in list order (sort order, nearest target first, undated last).
final watchDreamsProvider = StreamProvider.autoDispose<List<Dream>>(
  (ref) => ref.watch(dreamRepositoryProvider).watchAll(),
);

final watchDreamCategoriesProvider =
    StreamProvider.autoDispose<List<DreamCategory>>(
      (ref) => ref.watch(dreamCategoryRepositoryProvider).watchAll(),
    );

final watchDreamFieldsProvider =
    StreamProvider.autoDispose<List<DreamFieldDef>>(
      (ref) => ref.watch(dreamFieldRepositoryProvider).watchAll(),
    );

/// One dream with its local steps and metrics (no computed values); null if gone.
final watchDreamLocalDetailProvider = StreamProvider.autoDispose
    .family<DreamLocalDetail?, String>(
      (ref, id) => WatchDreamLocalDetail(
        ref.watch(dreamRepositoryProvider),
        ref.watch(dreamStepRepositoryProvider),
        ref.watch(dreamMetricRepositoryProvider),
      )(id),
    );

// ================================================================ writes (local, through the outbox)

/// `(DreamInput)` → [Dream].
final createDreamProvider = Provider<CreateDream>(
  (ref) => CreateDream(
    ref.watch(dreamRepositoryProvider),
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(dreamFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, DreamInput)` → [Dream].
final updateDreamProvider = Provider<UpdateDream>(
  (ref) => UpdateDream(
    ref.watch(dreamRepositoryProvider),
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(dreamFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, DreamStatus)` — stamps `startedAt` / `completedAt`.
final setDreamStatusProvider = Provider<SetDreamStatus>(
  (ref) => SetDreamStatus(
    ref.watch(dreamRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, categoryKey)`.
final moveDreamCategoryProvider = Provider<MoveDreamCategory>(
  (ref) => MoveDreamCategory(
    ref.watch(dreamRepositoryProvider),
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — also deletes its steps and metrics.
final deleteDreamProvider = Provider<DeleteDream>(
  (ref) => DeleteDream(ref.watch(dreamRepositoryProvider)),
);

/// `(dreamId:, id:?, DreamStepInput)`.
final saveDreamStepProvider = Provider<SaveDreamStep>(
  (ref) => SaveDreamStep(
    ref.watch(dreamRepositoryProvider),
    ref.watch(dreamStepRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(stepId)` — ticks it off (stamps `doneAt`) or back on.
final toggleDreamStepProvider = Provider<ToggleDreamStep>(
  (ref) => ToggleDreamStep(
    ref.watch(dreamStepRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteDreamStepProvider = Provider<DeleteDreamStep>(
  (ref) => DeleteDreamStep(ref.watch(dreamStepRepositoryProvider)),
);

/// `(dreamId:, orderedIds:)`.
final reorderDreamStepsProvider = Provider<ReorderDreamSteps>(
  (ref) => ReorderDreamSteps(
    ref.watch(dreamStepRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(dreamId:, id:?, DreamMetricInput)`.
final saveDreamMetricProvider = Provider<SaveDreamMetric>(
  (ref) => SaveDreamMetric(
    ref.watch(dreamRepositoryProvider),
    ref.watch(dreamMetricRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(metricId:, value:, at:?)` — a manual reading offline (queued, synced).
final recordDreamManualValueProvider = Provider<RecordDreamManualValue>(
  (ref) => RecordDreamManualValue(
    ref.watch(dreamMetricRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteDreamMetricProvider = Provider<DeleteDreamMetric>(
  (ref) => DeleteDreamMetric(ref.watch(dreamMetricRepositoryProvider)),
);

/// `(label:, emoji:)`.
final createDreamCategoryProvider = Provider<CreateDreamCategory>(
  (ref) => CreateDreamCategory(
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id:, label:, emoji:)` — the key never changes.
final updateDreamCategoryProvider = Provider<UpdateDreamCategory>(
  (ref) => UpdateDreamCategory(
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — its dreams move to `other`.
final deleteDreamCategoryProvider = Provider<DeleteDreamCategory>(
  (ref) => DeleteDreamCategory(ref.watch(dreamCategoryRepositoryProvider)),
);

/// `(label:, type:, options:, appliesTo:, showInList:)`.
final createDreamFieldProvider = Provider<CreateDreamField>(
  (ref) => CreateDreamField(
    ref.watch(dreamFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id:, label:, appliesTo:, showInList:)` — key and type never change.
final updateDreamFieldProvider = Provider<UpdateDreamField>(
  (ref) => UpdateDreamField(
    ref.watch(dreamFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteDreamFieldProvider = Provider<DeleteDreamField>(
  (ref) => DeleteDreamField(ref.watch(dreamFieldRepositoryProvider)),
);

// ================================================================ online (computed, never stored)

/// `([tz:])` → [DreamSummary]. Needs the network.
final getDreamSummaryProvider = Provider<GetDreamSummary>(
  (ref) => GetDreamSummary(ref.watch(dreamOnlineRepositoryProvider)),
);

/// `(id, [tz:])` → [DreamDetail] with computed metric values.
final getDreamDetailProvider = Provider<GetDreamDetail>(
  (ref) => GetDreamDetail(ref.watch(dreamOnlineRepositoryProvider)),
);

/// `(dreamId:, metricId:, value:, at:?)` → [ManualValueResult], online.
final recordDreamManualValueOnlineProvider =
    Provider<RecordDreamManualValueOnline>(
      (ref) => RecordDreamManualValueOnline(
        ref.watch(dreamOnlineRepositoryProvider),
      ),
    );

/// Metrics of every dream by dream id (the local "last update" of a dream).
final watchDreamMetricsProvider =
    StreamProvider.autoDispose<Map<String, List<DreamMetric>>>(
      (ref) => WatchDreamMetrics(
        ref.watch(dreamRepositoryProvider),
        ref.watch(dreamMetricRepositoryProvider),
      )(),
    );

// ================================================================ screens (phase C2)

/// Steps of every dream by dream id (list cost and checklist progress).
final watchDreamStepsProvider =
    StreamProvider.autoDispose<Map<String, List<DreamStep>>>(
      (ref) => WatchDreamSteps(
        ref.watch(dreamRepositoryProvider),
        ref.watch(dreamStepRepositoryProvider),
      )(),
    );

/// `(ids)` — the category order of the manage screen.
final reorderDreamCategoriesProvider = Provider<ReorderDreamCategories>(
  (ref) => ReorderDreamCategories(
    ref.watch(dreamCategoryRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(ids)` — the custom-column order of the manage screen.
final reorderDreamFieldsProvider = Provider<ReorderDreamFields>(
  (ref) => ReorderDreamFields(
    ref.watch(dreamFieldRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` → the server detail with computed metric values. Online only: a
/// failure (offline, unauthorized) is the error state of the detail screen.
final dreamOnlineDetailProvider = FutureProvider.autoDispose
    .family<DreamDetail, String>(
      (ref, id) async =>
          (await ref.watch(getDreamDetailProvider)(id)).valueOrThrow,
    );
