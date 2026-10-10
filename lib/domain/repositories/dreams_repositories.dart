import '../entities/entities.dart';

/// Synced Dreams ("Mimpi", `docs/dreams.md`). Every write goes to the local
/// database and the outbox in one transaction; the UI updates from the watch
/// streams and sync runs in the background. Computed values never come from
/// here: see [DreamOnlineRepository].
abstract interface class DreamRepository {
  /// Sorted like the list (sort order, nearest target first, undated last).
  Stream<List<Dream>> watchAll();
  Future<List<Dream>> getAll();
  Stream<Dream?> watchById(String id);
  Future<Dream?> getById(String id);

  /// Insert or update, queued as an upsert.
  Future<void> save(Dream dream);

  /// Deletes the dream and its steps and metrics (queued as deletes of the
  /// dream only; the server tombstones the children). Children lose
  /// `parentId`, the cascade of `docs/dreams.md`.
  Future<void> delete(String id);
}

/// Checklist steps of a dream (`dreamSteps`).
abstract interface class DreamStepRepository {
  /// By `sortOrder`, then id.
  Stream<List<DreamStep>> watchForDream(String dreamId);
  Future<List<DreamStep>> getForDream(String dreamId);
  Future<DreamStep?> getById(String id);
  Future<void> save(DreamStep step);
  Future<void> delete(String id);
}

/// Metrics of a dream (`dreamMetrics`).
abstract interface class DreamMetricRepository {
  /// By `sortOrder`, then id.
  Stream<List<DreamMetric>> watchForDream(String dreamId);
  Future<List<DreamMetric>> getForDream(String dreamId);
  Future<DreamMetric?> getById(String id);
  Future<void> save(DreamMetric metric);

  /// Deletes the metric; steps tied to it lose `metricRef` / `atValue`.
  Future<void> delete(String id);
}

/// User categories of dreams (`dreamCategories`).
abstract interface class DreamCategoryRepository {
  /// By `sortOrder`, then label.
  Stream<List<DreamCategory>> watchAll();
  Future<List<DreamCategory>> getAll();
  Future<DreamCategory?> getById(String id);
  Future<void> save(DreamCategory category);

  /// Deletes the category; its dreams move to `other` (the cascade).
  Future<void> delete(String id);
}

/// Custom-column definitions of dreams (`dreamFields`).
abstract interface class DreamFieldRepository {
  /// By `sortOrder`, then label.
  Stream<List<DreamFieldDef>> watchAll();
  Future<List<DreamFieldDef>> getAll();
  Future<DreamFieldDef?> getById(String id);
  Future<void> save(DreamFieldDef def);

  /// Deletes the def; its key leaves every dream's `fields`.
  Future<void> delete(String id);
}
