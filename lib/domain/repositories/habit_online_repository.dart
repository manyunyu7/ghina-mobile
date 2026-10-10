import '../entities/habit_online.dart';

/// Online-only habit data: the markdown notes and the server analysis.
///
/// Nothing here is cached or stored. Every method throws a `Failure`
/// (`NetworkFailure` offline, `ConflictFailure` when the notes changed
/// elsewhere since [HabitNotes.updatedAt]).
abstract interface class HabitOnlineRepository {
  /// `GET /api/mobile/habits/{id}` — the notes plus the row's `updatedAt`.
  Future<HabitNotes> fetchNotes(String habitId);

  /// `PUT /api/mobile/habits/{id}/notes`. Pass the [HabitNotes.updatedAt] you
  /// read as [expectedUpdatedAt]: a stale one is a `ConflictFailure`.
  Future<HabitNotesWrite> replaceNotes(
    String habitId,
    String notes, {
    DateTime? expectedUpdatedAt,
  });

  /// `POST /api/mobile/habits/{id}/notes/append` — atomic append.
  Future<HabitNotesWrite> appendNotes(
    String habitId,
    String text, {
    String? heading,
  });

  /// `GET /api/mobile/habits/{id}/insights?days=&today=&tz=`. [today] is the
  /// device's local `YYYY-MM-DD`; the device time zone is sent when known.
  Future<HabitAnalysis> fetchAnalysis(
    String habitId, {
    int days = 90,
    required String today,
  });
}
