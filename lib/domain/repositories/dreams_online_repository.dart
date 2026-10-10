import '../entities/entities.dart';

/// The server-computed side of Dreams (`docs/dreams.md` → REST): summary,
/// full detail with computed metric values, and manual metric readings.
/// **Online-only**: every method throws a `Failure` (`NetworkFailure` offline).
/// Nothing computed is stored locally.
abstract interface class DreamOnlineRepository {
  /// `GET /api/mobile/dreams/summary` — the "start here" overview.
  Future<DreamSummary> summary({String? tz});

  /// `GET /api/mobile/dreams/{id}` — the full dream with computed values.
  Future<DreamDetail> fetch(String id, {String? tz});

  /// `POST /api/mobile/dreams/{id}/metrics/{mid}/value` — a manual reading.
  /// [at] defaults to now on the server and must not be in the future.
  Future<ManualValueResult> recordManualValue(
    String dreamId,
    String metricId,
    double value, {
    DateTime? at,
  });
}
