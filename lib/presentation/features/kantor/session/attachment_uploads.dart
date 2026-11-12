import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../di/di.dart';
import 'attach_picker.dart';
import 'attachment_model.dart';
import 'attachment_notifier.dart';
import 'attachment_uploader.dart';
import 'kantor_feed.dart';
import 'chat_context.dart';

/// Where the outbox (copies of the files + `queue.json`) lives. Tests override.
final kantorOutboxDirProvider = Provider<Future<Directory>>((ref) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'kantor_outbox'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
});

final kantorUploadNotifierProvider = Provider<UploadNotifier>(
  (ref) => kIsWeb || (!Platform.isAndroid && !Platform.isIOS)
      ? const NoUploadNotifier()
      : FlutterUploadNotifier(),
);

/// Builds the uploader for the saved Kantor config. Tests override it.
final kantorUploaderProvider = Provider<KantorUploader?>((ref) {
  final config = ref.watch(kantorConfigProvider).value;
  if (config == null || !config.ready) return null;
  return KantorUploader(
    Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Authorization': 'Bearer ${config.token}'},
      ),
    ),
  );
});

/// Chats that are on screen right now (sid -> count), so a new attachment
/// from that agent doesn't also raise a notification.
final kantorOpenChats = <String, int>{};

/// The outbox: files waiting for, or on their way to, an agent. One file at a
/// time, in order. Survives the app being killed: the queue is written to
/// `queue.json` and an interrupted upload continues from the offset the
/// daemon already has. While it runs, a foreground service notification keeps
/// the process alive with the screen off.
class KantorUploads extends Notifier<List<UploadJob>> {
  bool _running = false;
  bool _loaded = false;
  CancelToken? _cancel;
  String? _activeId;
  Timer? _sweep;

  /// Deferred uploads somebody waits for: completes with the attachment id,
  /// or null when the file failed or was cancelled.
  final _waiters = <String, Completer<String?>>{};

  @override
  List<UploadJob> build() {
    ref.onDispose(() {
      _sweep?.cancel();
      for (final w in _waiters.values) {
        if (!w.isCompleted) w.complete(null);
      }
      _waiters.clear();
    });
    // A saved token appearing (or changing) may unblock a waiting queue.
    ref.listen(kantorUploaderProvider, (_, next) {
      if (next != null) unawaited(_pump());
    });
    unawaited(_restore());
    return const [];
  }

  String? get _connection {
    // Using the uploader also keeps overridden uploaders testable.
    final uploader = ref.read(kantorUploaderProvider);
    if (uploader == null) return null;
    return kantorConnectionKey(
      KantorConfig(
        baseUrl: uploader.dio.options.baseUrl,
        token: '${uploader.dio.options.headers['Authorization'] ?? ''}'
            .replaceFirst(RegExp(r'^Bearer '), ''),
      ),
    );
  }

  UploadNotifier get _notify => ref.mounted
      ? ref.read(kantorUploadNotifierProvider)
      : const NoUploadNotifier();

  Future<File> _queueFile() async => File(
    p.join((await ref.read(kantorOutboxDirProvider)).path, 'queue.json'),
  );

  Future<void> _restore() async {
    try {
      final f = await _queueFile();
      if (!ref.mounted) return;
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString());
        if (!ref.mounted) return;
        final jobs = <UploadJob>[
          if (raw is List)
            for (final j in raw)
              if (j is Map) UploadJob.fromJson(Map<String, dynamic>.from(j)),
        ];
        // Legacy jobs lack an origin: bind once to the connection present at
        // migration, then persist it before any network request.
        final connection = _connection;
        // anything that was mid-flight when the process died goes back in line
        state = [
          ...state,
          for (final j in jobs)
            if (state.every((x) => x.id != j.id))
              j.copyWith(
                connection: j.connection.isEmpty ? connection : null,
                status: j.status == UploadStatus.uploading
                    ? UploadStatus.queued
                    : j.status,
              ),
        ];
      }
    } catch (e) {
      debugPrint('Kantor outbox restore: $e');
    }
    if (!ref.mounted) return;
    _loaded = true;
    await _save();
    await _pump();
  }

  Future<void> _save() async {
    if (!_loaded || !ref.mounted) return;
    try {
      final f = await _queueFile();
      if (!ref.mounted) return;
      final keep = [
        for (final j in state)
          if (j.status != UploadStatus.done) j.toJson(),
      ];
      await f.writeAsString(jsonEncode(keep));
    } catch (e) {
      debugPrint('Kantor outbox save: $e');
    }
  }

  void _set(String id, UploadJob Function(UploadJob) f, {bool save = false}) {
    if (!ref.mounted) return;
    state = [for (final j in state) j.id == id ? f(j) : j];
    if (save) unawaited(_save());
  }

  /// Copies [source] into the outbox (the picker's cache can be cleared) and
  /// queues it. Returns the job.
  Future<UploadJob> enqueue({
    required String sid,
    required String agent,
    required File source,
    required String name,
    required String mime,
    String caption = '',
    String? connection,
    String office = '',
    bool defer = false,
  }) async {
    final target = connection ?? _connection;
    if (target == null || target != _connection) {
      throw const UploadFailure(
        'Kompleks sudah berganti. Pilih file lagi di chat tujuan.',
      );
    }
    final dir = await ref.read(kantorOutboxDirProvider);
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final dest = p.join(dir.path, '$id${p.extension(name)}');
    await source.copy(dest);
    final job = UploadJob(
      id: id,
      sid: sid,
      connection: target,
      office: office,
      agent: agent,
      path: dest,
      name: name,
      size: await File(dest).length(),
      mime: mime,
      caption: caption,
      defer: defer,
    );
    if (defer) _waiters[id] = Completer<String?>();
    if (!ref.mounted) {
      _forget(job);
      throw const UploadFailure('Antrean sudah ditutup.');
    }
    state = [...state, job];
    await _save();
    unawaited(_pump());
    return job;
  }

  /// Sends [files] as one message: every file goes up held (`defer`), then the
  /// daemon is asked to hand them all to the agent together with [text].
  /// Files that fail are left out (their bubble keeps its retry button, and a
  /// retried file is delivered on its own). With no file arriving, nothing is
  /// delivered and the caller decides what to do with [text].
  Future<BatchResult> sendBatch({
    required String sid,
    required String agent,
    required List<PickedAttachment> files,
    required String text,
    String? connection,
    String office = '',
  }) async {
    final waits = <Future<String?>>[];
    for (final f in files) {
      final job = await enqueue(
        sid: sid,
        connection: connection,
        office: office,
        agent: agent,
        source: f.file,
        name: f.name,
        mime: f.mime,
        defer: true,
      );
      final w = _waiters[job.id];
      if (w != null) waits.add(w.future);
    }
    final ids = [
      for (final id in await Future.wait(waits))
        if (id != null && id.isNotEmpty) id,
    ];
    final failed = files.length - ids.length;
    final uploader = ref.mounted ? ref.read(kantorUploaderProvider) : null;
    if (ids.isEmpty || uploader == null) {
      return BatchResult(sent: 0, failed: failed, delivered: false);
    }
    final delivered = await uploader.deliver(sid, ids, text);
    return BatchResult(sent: ids.length, failed: failed, delivered: delivered);
  }

  void retry(String id) {
    _set(
      id,
      (j) => j.copyWith(status: UploadStatus.queued, clearError: true),
      save: true,
    );
    unawaited(_pump());
  }

  /// Cancels a queued or running upload and drops its copy of the file.
  void cancel(String id) {
    if (_activeId == id) _cancel?.cancel();
    final job = state.where((j) => j.id == id).firstOrNull;
    _waiters.remove(id)?.complete(null);
    state = [
      for (final j in state)
        if (j.id != id) j,
    ];
    unawaited(_save());
    if (job != null && _activeId != id) _forget(job);
  }

  void _forget(UploadJob job) {
    unawaited(File(job.path).delete().then((_) {}, onError: (_) {}));
  }

  UploadJob? _next(String connection) {
    for (final j in state) {
      if (j.status == UploadStatus.queued && j.connection == connection)
        return j;
    }
    return null;
  }

  Future<void> _pump() async {
    if (_running || !_loaded || !ref.mounted) return;
    if (ref.read(kantorUploaderProvider) == null) return;
    _running = true;
    try {
      while (ref.mounted) {
        // Capture the destination for each job, rather than letting a previous
        // pump send newly queued work using another complex's client.
        final uploader = ref.read(kantorUploaderProvider);
        final connection = _connection;
        if (uploader == null || connection == null) break;
        if (state.any((j) => j.connection.isEmpty)) {
          state = [
            for (final j in state)
              j.connection.isEmpty ? j.copyWith(connection: connection) : j,
          ];
          await _save();
          // The active connection may have changed while the queue was saved.
          continue;
        }
        final job = _next(connection);
        if (job == null) break;
        await _runOne(uploader, job);
      }
    } finally {
      _running = false;
      _activeId = null;
      _cancel = null;
      await _notify.idle();
    }
  }

  Future<void> _runOne(KantorUploader uploader, UploadJob job) async {
    final id = job.id;
    _activeId = id;
    _cancel = CancelToken();
    _set(
      id,
      (j) => j.copyWith(status: UploadStatus.uploading, clearError: true),
    );
    UploadJob cur() => !ref.mounted
        ? job
        : state.firstWhere((j) => j.id == id, orElse: () => job);
    int waiting() => !ref.mounted
        ? 0
        : state.where((j) => j.status == UploadStatus.queued).length;
    try {
      final upId = await uploader.upload(
        cur(),
        cancel: _cancel,
        onOpened: (uid) =>
            _set(id, (j) => j.copyWith(uploadId: uid), save: true),
        onProgress: (sent, total) {
          _set(id, (j) => j.copyWith(sent: sent));
          unawaited(_notify.progress(cur(), waiting: waiting()));
        },
      );
      _set(
        id,
        (j) => j.copyWith(status: UploadStatus.done, sent: j.size),
        save: true,
      );
      // a held file is delivered by id of its attachment, not of its upload
      final att = job.defer ? await uploader.attachmentIdOf(upId) : null;
      if (att != null) {
        _set(id, (j) => j.copyWith(attachmentId: att), save: true);
      }
      await _notify.finished(cur());
      final waiter = _waiters.remove(id);
      if (waiter != null) {
        waiter.complete(att);
      } else if (job.defer && att != null) {
        // nobody is waiting for it (retried after a failure, or restored after
        // the app was killed): deliver this file on its own
        try {
          await uploader.deliver(job.sid, [att], '');
        } catch (e) {
          debugPrint('Kantor outbox deliver: $e');
        }
      }
      _forget(job);
      if (!ref.mounted) return;
      _sweep?.cancel();
      _sweep = Timer(const Duration(seconds: 2), () {
        if (!ref.mounted) return;
        state = [
          for (final j in state)
            if (j.status != UploadStatus.done) j,
        ];
      });
    } on UploadCancelled {
      _waiters.remove(id)?.complete(null);
      _forget(job); // cancel() already removed it from the list
    } catch (e) {
      _waiters.remove(id)?.complete(null);
      _set(
        id,
        (j) =>
            j.copyWith(status: UploadStatus.failed, error: uploadErrorText(e)),
        save: true,
      );
      await _notify.failed(cur());
    }
  }
}

/// How a batch (files held in the tray plus the owner's text) went.
class BatchResult {
  const BatchResult({
    required this.sent,
    required this.failed,
    required this.delivered,
  });

  /// Files that arrived and were handed to the agent.
  final int sent;

  /// Files that failed or were cancelled; they are not part of the message.
  final int failed;

  /// False when the files are stored but the daemon could not type the
  /// message into the session.
  final bool delivered;
}

final kantorUploadsProvider = NotifierProvider<KantorUploads, List<UploadJob>>(
  KantorUploads.new,
);

/// Watched once from the app shell: wakes the outbox at app start (so an
/// interrupted upload resumes) and raises "Rara mengirim screenshot" for
/// attachments of chats that are not open.
final kantorAttachmentAlertsProvider = Provider<void>((ref) {
  ref.read(kantorUploadsProvider);
  final seen = <String>{};
  ref.listen(kantorEventsProvider, (_, next) {
    final msg = next.value;
    if (msg == null || msg['t'] != 'attachment') return;
    final item = KantorAttachment.fromJson(asJson(msg['item']));
    final sid = '${msg['sid']}';
    final config = ref.read(kantorConfigProvider).value;
    if (config == null) return;
    final connection = kantorConnectionKey(config);
    final office = '${msg['office'] ?? ''}';
    if (item.mine || item.id.isEmpty || !seen.add('$connection/${item.id}'))
      return;
    if ((kantorOpenChats[kantorOpenChatKey(connection, office, sid)] ?? 0) > 0)
      return;
    var who = item.agent;
    if (who.isEmpty) {
      final office = '${msg['office'] ?? ''}';
      final feed = office.isEmpty
          ? null
          : ref.read(kantorOfficeFeedProvider(office));
      final s = feed?.session(sid);
      who = s == null ? 'Agen' : sessionName(feed!, s);
    }
    unawaited(ref.read(kantorUploadNotifierProvider).agentSent(who, item));
  });
});
