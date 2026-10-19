import '../entities/statement_import.dart';

/// Statement import (`/api/mobile/statements`, `docs/statement-import.md`).
/// **Online-only**: every method throws a [StatementException].
abstract interface class StatementRepository {
  /// `GET statements` — latest 30, newest first.
  Future<List<StatementImport>> list();

  /// `GET statements/{id}`.
  Future<StatementDetail> detail(String id);

  /// `POST statements` — `passwordRequired` / `passwordWrong` when the PDF is
  /// locked; nothing is stored then.
  Future<StatementImport> upload(StatementUpload upload);

  /// `POST statements/{id}/retry` — `conflict` while a fresh run is going.
  Future<StatementImport> retry(String id);

  /// `PATCH statements/rows/{rowId}` — `conflict` when it is no longer pending.
  Future<StatementRow> editRow(String rowId, StatementRowPatch patch);

  /// `POST statements/{id}/approve` → how many transactions were created.
  Future<int> approve(String id, List<String> rowIds);

  /// `POST statements/{id}/ignore`.
  Future<void> ignore(String id, List<String> rowIds);

  /// `DELETE statements/{id}` — transactions already created stay.
  Future<void> delete(String id);
}
