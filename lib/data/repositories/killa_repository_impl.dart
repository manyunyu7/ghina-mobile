import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/killa.dart';
import '../../domain/repositories/killa_repository.dart';
import '../datasources/remote/killa_api.dart';

/// [KillaRepository] straight over the API — Killa is online-only (no local
/// table, not part of sync).
class RemoteKillaRepository implements KillaRepository {
  RemoteKillaRepository(this._api);
  final KillaApi _api;

  @override
  Future<KillaMessagePage> chat({String? before, int limit = 50}) =>
      _api.chat(before: before, limit: limit);

  @override
  Future<KillaSendResult> send({
    required String text,
    required KillaModel model,
    List<KillaOutgoingMedia> media = const [],
  }) => _api.send(text: text, model: model, media: media);

  @override
  Future<KillaMessage> newSession() async {
    final divider = await _api.newSession();
    return divider ??
        KillaMessage(
          id: 'divider-${DateTime.now().millisecondsSinceEpoch}',
          role: KillaRole.system,
          body: 'Sesi baru',
          createdAt: DateTime.now(),
        );
  }

  /// Engine attachments are also written to the temporary directory (the
  /// photo viewer and "open file" need a file on disk).
  @override
  Future<KillaMediaFile> media(String path) async {
    final file = await _api.media(path);
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'killa_media'),
      );
      await dir.create(recursive: true);
      final name = p.basename(path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final key = path.hashCode.toUnsigned(32).toRadixString(16);
      final out = File(p.join(dir.path, '${key}_$name'));
      await out.writeAsBytes(file.bytes, flush: true);
      return KillaMediaFile(
        bytes: file.bytes,
        contentType: file.contentType,
        localPath: out.path,
      );
    } catch (_) {
      return file; // no cache (tests / storage full): bytes are enough
    }
  }

  @override
  Future<KillaDirListing> listFiles(String path) => _api.listFiles(path);

  @override
  Future<KillaFileContent> readFile(String path) => _api.readFile(path);

  @override
  Future<void> writeFile(String path, String content) =>
      _api.writeFile(path, content);

  @override
  Future<String?> commit({String? message}) => _api.commit(message: message);

  @override
  Future<List<KillaCommit>> commits({int limit = 50}) =>
      _api.commits(limit: limit);

  @override
  Future<List<KillaReminder>> reminders() => _api.reminders();

  @override
  Future<bool> cancelReminder(String id) => _api.cancelReminder(id);

  @override
  Future<KillaUsage> usage({int days = 30}) => _api.usage(days: days);
}
