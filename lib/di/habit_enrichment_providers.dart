/// Composition root, habit enrichment (`docs/habits-food-enrichment.md`):
/// coping tools, events, dimensions and `extra`, plus the online-only notes and
/// analysis. See `lib/di/README.md` → "Habit enrichment API".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';

// ---------------------------------------------------------------- reads

/// Every dimension definition (global + per habit), by `sortOrder`.
final watchHabitFieldsProvider =
    StreamProvider.autoDispose<List<HabitFieldDef>>(
      (ref) => WatchHabitFields(ref.watch(habitFieldRepositoryProvider))(),
    );

/// The events of one habit, newest first.
final watchHabitEventsProvider = StreamProvider.autoDispose
    .family<List<HabitEvent>, String>(
      (ref, habitId) =>
          WatchHabitEvents(ref.watch(habitEventRepositoryProvider))(habitId),
    );

// ---------------------------------------------------------------- tools & events

/// `(habitId, [HabitTool])` — replaces the coping tools.
final setHabitToolsProvider = Provider<SetHabitTools>(
  (ref) => SetHabitTools(
    ref.watch(habitRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(HabitEventInput(...))` → [HabitEvent] (create or edit).
final saveHabitEventProvider = Provider<SaveHabitEvent>(
  (ref) => SaveHabitEvent(
    ref.watch(habitEventRepositoryProvider),
    ref.watch(habitRepositoryProvider),
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(eventId)`.
final deleteHabitEventProvider = Provider<DeleteHabitEvent>(
  (ref) => DeleteHabitEvent(ref.watch(habitEventRepositoryProvider)),
);

// ---------------------------------------------------------------- dimensions

/// `(HabitFieldInput(...))` → [HabitFieldDef].
final createHabitFieldProvider = Provider<CreateHabitField>(
  (ref) => CreateHabitField(
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(habitRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, label:, appliesTo:, clearAppliesTo:)`.
final updateHabitFieldProvider = Provider<UpdateHabitField>(
  (ref) => UpdateHabitField(
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `([ids in new order])`.
final reorderHabitFieldsProvider = Provider<ReorderHabitFields>(
  (ref) => ReorderHabitFields(
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` → `(logs:, events:)` carrying the key — show it before a delete.
final countHabitFieldUsageProvider = Provider<CountHabitFieldUsage>(
  (ref) => CountHabitFieldUsage(
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(habitEventRepositoryProvider),
  ),
);

/// `(id)` — also strips the key from every log and event.
final deleteHabitFieldProvider = Provider<DeleteHabitField>(
  (ref) => DeleteHabitField(ref.watch(habitFieldRepositoryProvider)),
);

/// `(habitId, day, type, {key: value|null})` — sets dimension values on the
/// day's existing row ("tambah detail", the urge the emergency screen logged).
final setHabitLogExtraProvider = Provider<SetHabitLogExtra>(
  (ref) => SetHabitLogExtra(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(habitFieldRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

// ---------------------------------------------------------------- online-only

/// `(habitId)` → [HabitNotes]. Call on tap for `private` habits.
final getHabitNotesProvider = Provider<GetHabitNotes>(
  (ref) => GetHabitNotes(ref.watch(habitOnlineRepositoryProvider)),
);

/// `(habitId, notes, expectedUpdatedAt:)` — a stale one is `ConflictFailure`.
final replaceHabitNotesProvider = Provider<ReplaceHabitNotes>(
  (ref) => ReplaceHabitNotes(
    ref.watch(habitOnlineRepositoryProvider),
    ref.watch(habitRepositoryProvider),
    ref.watch(syncServiceProvider),
  ),
);

/// `(habitId, text, heading:)` — "tambah catatan".
final appendHabitNotesProvider = Provider<AppendHabitNotes>(
  (ref) => AppendHabitNotes(
    ref.watch(habitOnlineRepositoryProvider),
    ref.watch(habitRepositoryProvider),
    ref.watch(syncServiceProvider),
  ),
);

/// `(habitId, days: 90)` → [HabitAnalysis]; `NetworkFailure` offline.
final fetchHabitAnalysisProvider = Provider<FetchHabitAnalysis>(
  (ref) => FetchHabitAnalysis(
    ref.watch(habitOnlineRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
