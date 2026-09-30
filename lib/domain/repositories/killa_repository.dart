import '../entities/killa.dart';

/// Killa (`docs/killa.md` → "Mobile API"). Online-only; every method throws a
/// [KillaException] on failure.
abstract interface class KillaRepository {
  /// A page of the chat log (oldest first); [before] = a `nextBefore` cursor.
  Future<KillaMessagePage> chat({String? before, int limit = 50});

  /// Sends a message and waits for the reply (up to ~5.5 min).
  Future<KillaSendResult> send({
    required String text,
    required KillaModel model,
    List<KillaOutgoingMedia> media = const [],
  });

  /// "Sesi baru" → the divider message.
  Future<KillaMessage> newSession();

  /// Raw bytes of an `engine` attachment (Bearer media proxy).
  Future<KillaMediaFile> media(String path);

  Future<KillaDirListing> listFiles(String path);
  Future<KillaFileContent> readFile(String path);
  Future<void> writeFile(String path, String content);

  /// Commits the workspace; null = nothing to commit.
  Future<String?> commit({String? message});
  Future<List<KillaCommit>> commits({int limit = 50});

  /// Soonest first.
  Future<List<KillaReminder>> reminders();

  /// False when it already fired / was cancelled.
  Future<bool> cancelReminder(String id);
  Future<KillaUsage> usage({int days = 30});
}
