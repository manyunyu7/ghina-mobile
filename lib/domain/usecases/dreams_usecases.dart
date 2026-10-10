/// Dreams ("Mimpi") use cases: offline-first writes through the synced
/// repositories (`Result<T>`, never throws), the status stamps of
/// `docs/dreams.md`, and the online-only reads (summary, detail, manual value).
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'dreams_rules.dart';
import 'people_usecases.dart' show uniqueKey;

// ================================================================ rules of the use cases

/// Applies the status stamps of `docs/dreams.md` to [next] (the dream after
/// the change, [prev] the stored one): `completedAt` is set when it becomes
/// `done` and cleared when it leaves it; `startedAt` is set when it becomes
/// `active` and was empty. [today] is the local `YYYY-MM-DD`.
Dream stampDreamStatus(Dream prev, Dream next, String today) {
  final becameDone =
      next.status == DreamStatus.done && prev.status != DreamStatus.done;
  final String? completed;
  if (next.status != DreamStatus.done) {
    completed = null;
  } else if (becameDone) {
    completed = next.completedAt ?? today;
  } else {
    completed = next.completedAt ?? prev.completedAt ?? today;
  }
  final String? started = next.status == DreamStatus.active
      ? (next.startedAt ?? prev.startedAt ?? today)
      : next.startedAt ?? prev.startedAt;
  return next.copyWith(
    completedAt: completed,
    clearCompletedAt: completed == null,
    startedAt: started,
    clearStartedAt: started == null,
  );
}

Future<void> _requireParent(
  DreamRepository dreams,
  String id,
  String? parentId,
) async {
  if (parentId == null) return;
  if (parentId == id) {
    throw const ValidationFailure(
      'Mimpi tidak boleh jadi induk dirinya sendiri',
      field: 'parentId',
    );
  }
  if (await dreams.getById(parentId) == null) {
    throw const ValidationFailure(
      'Mimpi induk tidak ditemukan',
      field: 'parentId',
    );
  }
  final parentOf = {for (final d in await dreams.getAll()) d.id: d.parentId};
  if (wouldCreateDreamCycle(id, parentId, parentOf)) {
    throw const ValidationFailure(
      'Induk tidak boleh membentuk lingkaran',
      field: 'parentId',
    );
  }
}

Future<Set<String>> _categoryKeys(DreamCategoryRepository categories) async => {
  for (final c in await categories.getAll()) c.key,
  'other',
};

// ================================================================ dreams

/// Creates a dream from [DreamInput] (validated against the user's categories
/// and custom columns).
final class CreateDream {
  const CreateDream(this._dreams, this._categories, this._fields, this._clock);
  final DreamRepository _dreams;
  final DreamCategoryRepository _categories;
  final DreamFieldRepository _fields;
  final Clock _clock;

  Future<Result<Dream>> call(DreamInput input) => guard(() async {
    final now = _clock.now();
    final id = newId();
    final dream = validateDream(
      id: id,
      input: input,
      categoryKeys: await _categoryKeys(_categories),
      defs: await _fields.getAll(),
      createdAt: now,
      updatedAt: now,
    );
    await _requireParent(_dreams, id, dream.parentId);
    final stamped = stampDreamStatus(dream, dream, dateKey(now));
    await _dreams.save(stamped);
    return stamped;
  });
}

/// Replaces the editable fields of a dream (validated like [CreateDream]).
final class UpdateDream {
  const UpdateDream(this._dreams, this._categories, this._fields, this._clock);
  final DreamRepository _dreams;
  final DreamCategoryRepository _categories;
  final DreamFieldRepository _fields;
  final Clock _clock;

  Future<Result<Dream>> call(String id, DreamInput input) => guard(() async {
    final prev = await _dreams.getById(id);
    if (prev == null) throw const NotFoundFailure();
    final now = _clock.now();
    final next = validateDream(
      id: id,
      input: input,
      categoryKeys: await _categoryKeys(_categories),
      defs: await _fields.getAll(),
      createdAt: prev.createdAt,
      updatedAt: now,
    );
    await _requireParent(_dreams, id, next.parentId);
    final stamped = stampDreamStatus(prev, next, dateKey(now));
    await _dreams.save(stamped);
    return stamped;
  });
}

/// Moves a dream to another status (stamps `completedAt` / `startedAt`).
final class SetDreamStatus {
  const SetDreamStatus(this._dreams, this._clock);
  final DreamRepository _dreams;
  final Clock _clock;

  Future<Result<Dream>> call(String id, DreamStatus status) => guard(() async {
    final prev = await _dreams.getById(id);
    if (prev == null) throw const NotFoundFailure();
    final now = _clock.now();
    final next = stampDreamStatus(
      prev,
      prev.copyWith(status: status, updatedAt: now),
      dateKey(now),
    );
    await _dreams.save(next);
    return next;
  });
}

/// Moves a dream to another category (`other` or a key of the user's).
final class MoveDreamCategory {
  const MoveDreamCategory(this._dreams, this._categories, this._clock);
  final DreamRepository _dreams;
  final DreamCategoryRepository _categories;
  final Clock _clock;

  Future<Result<Dream>> call(String id, String categoryKey) => guard(() async {
    final prev = await _dreams.getById(id);
    if (prev == null) throw const NotFoundFailure();
    if (!(await _categoryKeys(_categories)).contains(categoryKey)) {
      throw ValidationFailure(
        'Kategori "$categoryKey" belum ada',
        field: 'category',
      );
    }
    final next = prev.copyWith(category: categoryKey, updatedAt: _clock.now());
    await _dreams.save(next);
    return next;
  });
}

/// Deletes a dream with its steps and metrics; children lose their parent.
final class DeleteDream {
  const DeleteDream(this._dreams);
  final DreamRepository _dreams;

  Future<Result<void>> call(String id) => guard(() async {
    await _dreams.delete(id);
  });
}

// ================================================================ steps

/// Creates or edits a step of [dreamId] (at most [stepsPerDreamMax] per dream).
/// A new step goes to the end of the checklist; an edit keeps its place.
final class SaveDreamStep {
  const SaveDreamStep(this._dreams, this._steps, this._clock);
  final DreamRepository _dreams;
  final DreamStepRepository _steps;
  final Clock _clock;

  Future<Result<DreamStep>> call({
    required String dreamId,
    String? id,
    required DreamStepInput input,
  }) => guard(() async {
    if (await _dreams.getById(dreamId) == null) throw const NotFoundFailure();
    final existing = id == null ? null : await _steps.getById(id);
    if (existing != null && existing.dreamId != dreamId) {
      throw const NotFoundFailure();
    }
    final all = await _steps.getForDream(dreamId);
    if (existing == null && all.length >= stepsPerDreamMax) {
      throw ValidationFailure(
        'Maksimal $stepsPerDreamMax langkah per mimpi',
        field: 'steps',
      );
    }
    final order =
        existing?.sortOrder ??
        (all.isEmpty
            ? 0
            : all.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
    final step = validateDreamStep(
      id: id ?? newId(),
      dreamId: dreamId,
      input: DreamStepInput(
        title: input.title,
        notes: input.notes,
        done: input.done,
        dueDate: input.dueDate,
        cost: input.cost,
        reward: input.reward,
        metricRef: input.metricRef,
        atValue: input.atValue,
        sortOrder: order,
      ),
      now: _clock.now(),
      previousDoneAt: existing?.doneAt,
      createdAt: existing?.createdAt,
    );
    await _steps.save(step);
    return step;
  });
}

/// Ticks a step off (stamps `doneAt`) or back on.
final class ToggleDreamStep {
  const ToggleDreamStep(this._steps, this._clock);
  final DreamStepRepository _steps;
  final Clock _clock;

  Future<Result<DreamStep>> call(String stepId) => guard(() async {
    final s = await _steps.getById(stepId);
    if (s == null) throw const NotFoundFailure();
    final now = _clock.now();
    final next = s.copyWith(
      done: !s.done,
      doneAt: s.done ? null : now,
      clearDoneAt: s.done,
      updatedAt: now,
    );
    await _steps.save(next);
    return next;
  });
}

/// Deletes a step.
final class DeleteDreamStep {
  const DeleteDreamStep(this._steps);
  final DreamStepRepository _steps;

  Future<Result<void>> call(String stepId) => guard(() async {
    await _steps.delete(stepId);
  });
}

/// Puts the steps of [dreamId] in [orderedIds] order (sort order = position).
final class ReorderDreamSteps {
  const ReorderDreamSteps(this._steps, this._uow, this._clock);
  final DreamStepRepository _steps;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call({
    required String dreamId,
    required List<String> orderedIds,
  }) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      final current = {
        for (final s in await _steps.getForDream(dreamId)) s.id: s,
      };
      if (orderedIds.length != current.length ||
          orderedIds.any((id) => !current.containsKey(id))) {
        throw const ValidationFailure(
          'Urutan langkah tidak sesuai',
          field: 'steps',
        );
      }
      for (var i = 0; i < orderedIds.length; i++) {
        final s = current[orderedIds[i]]!;
        if (s.sortOrder == i) continue;
        await _steps.save(s.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

// ================================================================ metrics

/// Creates or edits a metric of [dreamId] (at most [metricsPerDreamMax]).
final class SaveDreamMetric {
  const SaveDreamMetric(this._dreams, this._metrics, this._clock);
  final DreamRepository _dreams;
  final DreamMetricRepository _metrics;
  final Clock _clock;

  Future<Result<DreamMetric>> call({
    required String dreamId,
    String? id,
    required DreamMetricInput input,
  }) => guard(() async {
    if (await _dreams.getById(dreamId) == null) throw const NotFoundFailure();
    final existing = id == null ? null : await _metrics.getById(id);
    if (existing != null && existing.dreamId != dreamId) {
      throw const NotFoundFailure();
    }
    final all = await _metrics.getForDream(dreamId);
    if (existing == null && all.length >= metricsPerDreamMax) {
      throw ValidationFailure(
        'Maksimal $metricsPerDreamMax metrik per mimpi',
        field: 'metrics',
      );
    }
    final order =
        existing?.sortOrder ??
        (all.isEmpty
            ? 0
            : all.map((m) => m.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
    final metric = validateDreamMetric(
      id: id ?? newId(),
      dreamId: dreamId,
      input: DreamMetricInput(
        label: input.label,
        source: input.source,
        sourceRef: input.sourceRef,
        direction: input.direction,
        unit: input.unit,
        startValue: input.startValue,
        startDate: input.startDate,
        targetValue: input.targetValue,
        targetDate: input.targetDate,
        manualValue: input.manualValue,
        manualAt: input.manualAt,
        sortOrder: order,
      ),
      now: _clock.now(),
      createdAt: existing?.createdAt,
    );
    await _metrics.save(metric);
    return metric;
  });
}

/// Records a manual reading offline: the value and its time are stored and
/// queued, so the server adds the reading to its history on sync. A reading
/// older than the stored one is refused (the server keeps only the newest
/// value on the row).
final class RecordDreamManualValue {
  const RecordDreamManualValue(this._metrics, this._clock);
  final DreamMetricRepository _metrics;
  final Clock _clock;

  Future<Result<DreamMetric>> call({
    required String metricId,
    required double value,
    DateTime? at,
  }) => guard(() async {
    final m = await _metrics.getById(metricId);
    if (m == null) throw const NotFoundFailure();
    if (!m.source.isManual) {
      throw const ValidationFailure(
        'Hanya metrik manual yang bisa dicatat langsung',
        field: 'source',
      );
    }
    if (!value.isFinite) {
      throw const ValidationFailure('Nilai harus berupa angka', field: 'value');
    }
    final now = _clock.now();
    final when = at ?? now;
    if (when.isAfter(now)) {
      throw const ValidationFailure(
        'Waktu pencatatan tidak boleh di masa depan',
        field: 'at',
      );
    }
    if (m.manualAt != null && when.isBefore(m.manualAt!)) {
      throw const ValidationFailure(
        'Pencatatan lebih lama dari nilai terakhir',
        field: 'at',
      );
    }
    final next = m.copyWith(manualValue: value, manualAt: when, updatedAt: now);
    await _metrics.save(next);
    return next;
  });
}

/// Deletes a metric; the steps tied to it lose their threshold.
final class DeleteDreamMetric {
  const DeleteDreamMetric(this._metrics);
  final DreamMetricRepository _metrics;

  Future<Result<void>> call(String metricId) => guard(() async {
    await _metrics.delete(metricId);
  });
}

// ================================================================ categories & custom columns

/// Creates a user category; its key is derived from the label.
final class CreateDreamCategory {
  const CreateDreamCategory(this._categories, this._clock);
  final DreamCategoryRepository _categories;
  final Clock _clock;

  Future<Result<DreamCategory>> call({
    required String label,
    String emoji = '✨',
  }) => guard(() async {
    final all = await _categories.getAll();
    final key = uniqueKey(label, [
      for (final c in all) c.key,
    ], fallback: 'kategori');
    final v = validateDreamCategoryFields(key: key, label: label, emoji: emoji);
    final now = _clock.now();
    final c = DreamCategory(
      id: newId(),
      key: v.key,
      label: v.label,
      emoji: v.emoji,
      sortOrder: all.fold(-1, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1,
      createdAt: now,
      updatedAt: now,
    );
    await _categories.save(c);
    return c;
  });
}

/// Renames a category or changes its emoji (the key never changes).
final class UpdateDreamCategory {
  const UpdateDreamCategory(this._categories, this._clock);
  final DreamCategoryRepository _categories;
  final Clock _clock;

  Future<Result<DreamCategory>> call({
    required String id,
    required String label,
    required String emoji,
  }) => guard(() async {
    final prev = await _categories.getById(id);
    if (prev == null) throw const NotFoundFailure();
    final v = validateDreamCategoryFields(
      key: prev.key,
      label: label,
      emoji: emoji,
    );
    final next = prev.copyWith(
      label: v.label,
      emoji: v.emoji,
      updatedAt: _clock.now(),
    );
    await _categories.save(next);
    return next;
  });
}

/// Deletes a category; its dreams move to `other`. `other` cannot be deleted.
final class DeleteDreamCategory {
  const DeleteDreamCategory(this._categories);
  final DreamCategoryRepository _categories;

  Future<Result<void>> call(String id) => guard(() async {
    final c = await _categories.getById(id);
    if (c == null) throw const NotFoundFailure();
    if (c.key == 'other') {
      throw const ValidationFailure('Kategori "Lainnya" tidak bisa dihapus');
    }
    await _categories.delete(id);
  });
}

/// Creates a custom column; its key is derived from the label and never changes.
final class CreateDreamField {
  const CreateDreamField(this._fields, this._clock);
  final DreamFieldRepository _fields;
  final Clock _clock;

  Future<Result<DreamFieldDef>> call({
    required String label,
    DreamFieldType type = DreamFieldType.text,
    List<String>? options,
    List<String>? appliesTo,
    bool showInList = false,
  }) => guard(() async {
    final all = await _fields.getAll();
    final key = uniqueKey(label, [
      for (final f in all) f.key,
    ], fallback: 'kolom');
    final v = validateDreamFieldFields(
      key: key,
      label: label,
      type: type,
      options: options,
      appliesTo: appliesTo,
    );
    final now = _clock.now();
    final d = DreamFieldDef(
      id: newId(),
      key: v.key,
      label: v.label,
      type: type,
      options: v.options,
      appliesTo: v.appliesTo,
      sortOrder: all.fold(-1, (m, f) => f.sortOrder > m ? f.sortOrder : m) + 1,
      showInList: showInList,
      createdAt: now,
      updatedAt: now,
    );
    await _fields.save(d);
    return d;
  });
}

/// Changes a column's label, categories and list visibility (key and type stay).
final class UpdateDreamField {
  const UpdateDreamField(this._fields, this._clock);
  final DreamFieldRepository _fields;
  final Clock _clock;

  Future<Result<DreamFieldDef>> call({
    required String id,
    required String label,
    List<String>? appliesTo,
    bool? showInList,
  }) => guard(() async {
    final prev = await _fields.getById(id);
    if (prev == null) throw const NotFoundFailure();
    final v = validateDreamFieldFields(
      key: prev.key,
      label: label,
      type: prev.type,
      options: prev.options,
      appliesTo: appliesTo,
    );
    final next = prev.copyWith(
      label: v.label,
      appliesTo: v.appliesTo,
      showInList: showInList,
      updatedAt: _clock.now(),
    );
    await _fields.save(next);
    return next;
  });
}

/// Deletes a column; its key leaves every dream's `fields`.
final class DeleteDreamField {
  const DeleteDreamField(this._fields);
  final DreamFieldRepository _fields;

  Future<Result<void>> call(String id) => guard(() async {
    await _fields.delete(id);
  });
}

// ================================================================ reads

/// The dream with its local steps and metrics (no computed values: those come
/// from [GetDreamDetail] when online). Null when the dream is gone.
final class DreamLocalDetail with ValueEquality {
  const DreamLocalDetail({
    required this.dream,
    required this.steps,
    required this.metrics,
  });
  final Dream dream;
  final List<DreamStep> steps;
  final List<DreamMetric> metrics;

  @override
  List<Object?> get props => [dream, steps, metrics];
}

final class WatchDreamLocalDetail {
  const WatchDreamLocalDetail(this._dreams, this._steps, this._metrics);
  final DreamRepository _dreams;
  final DreamStepRepository _steps;
  final DreamMetricRepository _metrics;

  Stream<DreamLocalDetail?> call(String id) => combineLatestList(
    [
      _dreams.watchById(id),
      _steps.watchForDream(id),
      _metrics.watchForDream(id),
    ],
    (v) {
      final d = v[0] as Dream?;
      if (d == null) return null;
      return DreamLocalDetail(
        dream: d,
        steps: v[1] as List<DreamStep>,
        metrics: v[2] as List<DreamMetric>,
      );
    },
  );
}

// ================================================================ online (computed, never stored)

/// `GET /dreams/summary`.
final class GetDreamSummary {
  const GetDreamSummary(this._online);
  final DreamOnlineRepository _online;

  Future<Result<DreamSummary>> call({String? tz}) =>
      guard(() => _online.summary(tz: tz));
}

/// `GET /dreams/{id}` — the detail with computed metric values.
final class GetDreamDetail {
  const GetDreamDetail(this._online);
  final DreamOnlineRepository _online;

  Future<Result<DreamDetail>> call(String id, {String? tz}) =>
      guard(() => _online.fetch(id, tz: tz));
}

/// `POST …/metrics/{mid}/value` — a manual reading straight on the server
/// (returns the recomputed metric and the steps it completed).
final class RecordDreamManualValueOnline {
  const RecordDreamManualValueOnline(this._online);
  final DreamOnlineRepository _online;

  Future<Result<ManualValueResult>> call({
    required String dreamId,
    required String metricId,
    required double value,
    DateTime? at,
  }) =>
      guard(() => _online.recordManualValue(dreamId, metricId, value, at: at));
}
