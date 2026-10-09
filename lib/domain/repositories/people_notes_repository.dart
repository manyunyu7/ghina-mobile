import '../entities/people.dart';

/// The markdown notes of a person (`docs/people.md` → Endpoints).
///
/// **Online-only**: notes never enter the local database or sync. Every method
/// throws a `Failure` (`NetworkFailure` offline, `ConflictFailure` when the
/// notes changed elsewhere since [PersonNotes.updatedAt]).
abstract interface class PeopleNotesRepository {
  /// `GET /api/mobile/people/{id}` — the notes plus the row's `updatedAt`.
  Future<PersonNotes> fetch(String personId);

  /// `PUT /api/mobile/people/{id}/notes` — replaces everything. Pass the
  /// [PersonNotes.updatedAt] you read as [expectedUpdatedAt]: a stale one is a
  /// `ConflictFailure`.
  Future<PersonNotesWrite> replace(
    String personId,
    String notes, {
    DateTime? expectedUpdatedAt,
  });

  /// `POST /api/mobile/people/{id}/notes/append` — atomic append.
  Future<PersonNotesWrite> append(
    String personId,
    String text, {
    String? heading,
  });
}
