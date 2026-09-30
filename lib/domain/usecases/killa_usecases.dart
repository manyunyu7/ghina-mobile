/// Killa use cases (`docs/killa.md`). Online-only: they throw
/// [KillaException] (the presentation layer shows its friendly message; a
/// `forbidden` locks the whole feature).
library;

import '../entities/killa.dart';
import '../repositories/killa_repository.dart';

const killaTextMax = 20000;
const killaMaxMedia = 3;
const killaMediaMaxBytes = 8 * 1024 * 1024;
const killaFileMax = 1000000;
const killaCommitMessageMax = 500;

/// Merges [incoming] into [current] by id (incoming wins), oldest first
/// (ties by id), so polling / paging never duplicates a message.
List<KillaMessage> mergeKillaMessages(
  List<KillaMessage> current,
  List<KillaMessage> incoming,
) {
  final byId = <String, KillaMessage>{
    for (final m in current) m.id: m,
    for (final m in incoming) m.id: m,
  };
  return byId.values.toList()..sort((a, b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
}

KillaException _invalid(String message) =>
    KillaException(KillaErrorKind.invalid, message);

final class LoadKillaChat {
  const LoadKillaChat(this._repo);
  final KillaRepository _repo;

  Future<KillaMessagePage> call({String? before, int limit = 50}) =>
      _repo.chat(before: before, limit: limit);
}

final class SendKillaMessage {
  const SendKillaMessage(this._repo);
  final KillaRepository _repo;

  Future<KillaSendResult> call({
    required String text,
    List<KillaOutgoingMedia> media = const [],
  }) {
    final t = text.trim();
    if (t.isEmpty && media.isEmpty) {
      throw _invalid('Tulis pesan atau lampirkan file dulu, ya');
    }
    if (t.length > killaTextMax) {
      throw _invalid('Pesannya kepanjangan (maks $killaTextMax karakter)');
    }
    if (media.length > killaMaxMedia) {
      throw _invalid('Maksimal $killaMaxMedia lampiran per pesan');
    }
    for (final m in media) {
      if (m.bytes.length > killaMediaMaxBytes) {
        throw KillaException(
          KillaErrorKind.tooLarge,
          '${m.name} terlalu besar (maks 8 MB)',
        );
      }
    }
    return _repo.send(text: t, media: media);
  }
}

final class LoadKillaModel {
  const LoadKillaModel(this._repo);
  final KillaRepository _repo;

  Future<KillaModelSetting> call() => _repo.model();
}

/// Persists the model (engine-side, also used by the WA chat); null or
/// `"default"` clears it → the stored value (null = default).
final class SetKillaModel {
  const SetKillaModel(this._repo);
  final KillaRepository _repo;

  Future<String?> call(String? model) {
    final m = model?.trim();
    return _repo.setModel(m == null || m.isEmpty ? killaDefaultModel : m);
  }
}

final class StartKillaSession {
  const StartKillaSession(this._repo);
  final KillaRepository _repo;

  Future<KillaMessage> call() => _repo.newSession();
}

final class FetchKillaMedia {
  const FetchKillaMedia(this._repo);
  final KillaRepository _repo;

  Future<KillaMediaFile> call(String path) => _repo.media(path);
}

final class BrowseKillaFiles {
  const BrowseKillaFiles(this._repo);
  final KillaRepository _repo;

  Future<KillaDirListing> call(String path) => _repo.listFiles(path);
}

final class ReadKillaFile {
  const ReadKillaFile(this._repo);
  final KillaRepository _repo;

  Future<KillaFileContent> call(String path) => _repo.readFile(path);
}

final class SaveKillaFile {
  const SaveKillaFile(this._repo);
  final KillaRepository _repo;

  Future<void> call(String path, String content) {
    if (path.trim().isEmpty) throw _invalid('Path wajib diisi');
    if (content.length > killaFileMax) {
      throw const KillaException(
        KillaErrorKind.tooLarge,
        'Isi berkas terlalu besar (maks 1 MB)',
      );
    }
    return _repo.writeFile(path, content);
  }
}

/// Commits the workspace → the new hash, or null when nothing changed.
final class CommitKillaWorkspace {
  const CommitKillaWorkspace(this._repo);
  final KillaRepository _repo;

  Future<String?> call({String? message}) {
    final m = message?.trim();
    if (m != null && m.length > killaCommitMessageMax) {
      throw _invalid(
        'Pesan commit terlalu panjang (maks $killaCommitMessageMax)',
      );
    }
    return _repo.commit(message: m == null || m.isEmpty ? null : m);
  }
}

final class LoadKillaCommits {
  const LoadKillaCommits(this._repo);
  final KillaRepository _repo;

  Future<List<KillaCommit>> call({int limit = 100}) =>
      _repo.commits(limit: limit);
}

final class LoadKillaReminders {
  const LoadKillaReminders(this._repo);
  final KillaRepository _repo;

  Future<List<KillaReminder>> call() => _repo.reminders();
}

final class CancelKillaReminder {
  const CancelKillaReminder(this._repo);
  final KillaRepository _repo;

  /// False = it had already fired or been cancelled.
  Future<bool> call(String id) => _repo.cancelReminder(id);
}

final class LoadKillaUsage {
  const LoadKillaUsage(this._repo);
  final KillaRepository _repo;

  Future<KillaUsage> call({int days = 30}) => _repo.usage(days: days);
}
