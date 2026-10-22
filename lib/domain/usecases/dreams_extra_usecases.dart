// Dreams use cases added in phase C2 (screens): reorder of the user's
// categories and custom columns (the same shape as People's reorder), and live
// "children of every dream" reads (steps, metrics) for the list views. Cost,
// checklist progress and staleness are local, so the list never needs the
// network.
import 'dart:async';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';

/// Writes `sortOrder = index` for the given category ids (unknown ids skipped).
final class ReorderDreamCategories {
  const ReorderDreamCategories(this._repo, this._uow, this._clock);
  final DreamCategoryRepository _repo;
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

/// Writes `sortOrder = index` for the given custom-column ids.
final class ReorderDreamFields {
  const ReorderDreamFields(this._repo, this._uow, this._clock);
  final DreamFieldRepository _repo;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final f = await _repo.getById(id);
        if (f == null || f.sortOrder == i) continue;
        await _repo.save(f.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// Re-emits a map `dream id → children` whenever the dream list changes or
/// any dream's children change. [watchFor] is one dream's live children.
Stream<Map<String, List<T>>> _watchPerDream<T>(
  Stream<List<Dream>> dreams,
  Stream<List<T>> Function(String dreamId) watchFor,
) => Stream.multi((out) {
  StreamSubscription<Object?>? inner;
  final outer = dreams.listen((list) {
    inner?.cancel();
    inner = null;
    final ids = [for (final d in list) d.id];
    if (ids.isEmpty) {
      out.add(const {});
      return;
    }
    inner = combineLatestList<Map<String, List<T>>>(
      [for (final id in ids) watchFor(id)],
      (v) => {for (final (i, id) in ids.indexed) id: v[i] as List<T>},
    ).listen(out.add, onError: out.addError);
  }, onError: out.addError);
  out.onCancel = () {
    inner?.cancel();
    outer.cancel();
  };
});

/// Steps of every dream, keyed by dream id.
final class WatchDreamSteps {
  const WatchDreamSteps(this._dreams, this._steps);
  final DreamRepository _dreams;
  final DreamStepRepository _steps;

  Stream<Map<String, List<DreamStep>>> call() =>
      _watchPerDream(_dreams.watchAll(), _steps.watchForDream);
}

/// Metrics of every dream, keyed by dream id (their stored readings feed the
/// local "last update" of a dream).
final class WatchDreamMetrics {
  const WatchDreamMetrics(this._dreams, this._metrics);
  final DreamRepository _dreams;
  final DreamMetricRepository _metrics;

  Stream<Map<String, List<DreamMetric>>> call() =>
      _watchPerDream(_dreams.watchAll(), _metrics.watchForDream);
}
