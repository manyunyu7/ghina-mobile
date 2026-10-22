import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

enum UploadStatus { queued, uploading, done, failed }

/// One file on its way to an agent. Persisted (see `KantorUploads`) so the
/// queue survives the app being killed; [uploadId] is what lets the next run
/// continue from the server's offset instead of starting over.
class UploadJob {
  const UploadJob({
    required this.id,
    required this.sid,
    required this.agent,
    required this.path,
    required this.name,
    required this.size,
    required this.mime,
    this.caption = '',
    this.uploadId,
    this.sent = 0,
    this.status = UploadStatus.queued,
    this.error,
  });

  /// Local id, not the daemon's.
  final String id;
  final String sid;

  /// Display name of the agent, for notifications.
  final String agent;
  final String path;
  final String name;
  final int size;
  final String mime;
  final String caption;
  final String? uploadId;
  final int sent;
  final UploadStatus status;
  final String? error;

  double get fraction => size <= 0
      ? (status == UploadStatus.done ? 1 : 0)
      : (sent / size).clamp(0, 1);
  int get percent => (fraction * 100).floor();
  bool get isVideo => mime.startsWith('video/');
  bool get isImage => mime.startsWith('image/');
  bool get active =>
      status == UploadStatus.queued || status == UploadStatus.uploading;

  /// "gambar", "video" or "file" for "Mengunggah video ke Rara".
  String get noun => isImage ? 'gambar' : (isVideo ? 'video' : 'file');

  UploadJob copyWith({
    String? uploadId,
    int? sent,
    UploadStatus? status,
    String? error,
    bool clearError = false,
  }) => UploadJob(
    id: id,
    sid: sid,
    agent: agent,
    path: path,
    name: name,
    size: size,
    mime: mime,
    caption: caption,
    uploadId: uploadId ?? this.uploadId,
    sent: sent ?? this.sent,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sid': sid,
    'agent': agent,
    'path': path,
    'name': name,
    'size': size,
    'mime': mime,
    'caption': caption,
    'uploadId': uploadId,
    'sent': sent,
    'status': status.name,
    'error': error,
  };

  factory UploadJob.fromJson(Map<String, dynamic> j) => UploadJob(
    id: '${j['id']}',
    sid: '${j['sid']}',
    agent: '${j['agent'] ?? ''}',
    path: '${j['path']}',
    name: '${j['name']}',
    size: (j['size'] as num?)?.toInt() ?? 0,
    mime: '${j['mime'] ?? 'application/octet-stream'}',
    caption: '${j['caption'] ?? ''}',
    uploadId: j['uploadId'] as String?,
    sent: (j['sent'] as num?)?.toInt() ?? 0,
    status: UploadStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => UploadStatus.queued,
    ),
    error: j['error'] as String?,
  );
}

/// The upload gave up for good (the daemon said no, or the retries ran out).
class UploadFailure implements Exception {
  const UploadFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The upload was cancelled by the user.
class UploadCancelled implements Exception {
  const UploadCancelled();
}

/// Chunked, resumable upload to the daemon's `/api/sessions/:sid/uploads`
/// protocol: `POST` opens it (`{id, offset, chunk}`), `PUT /api/uploads/:id`
/// with an `Upload-Offset` header sends one piece (`{offset}`), `GET` reports
/// where the server is. A dropped connection waits, asks the server for its
/// offset and carries on from there.
class KantorUploader {
  KantorUploader(
    this.dio, {
    this.maxTries = 8,
    Duration Function(int attempt)? backoff,
  }) : backoff = backoff ?? _defaultBackoff;

  final Dio dio;
  final int maxTries;
  final Duration Function(int attempt) backoff;

  static Duration _defaultBackoff(int attempt) {
    final ms = 400 * (1 << attempt.clamp(0, 6));
    return Duration(milliseconds: ms > 8000 ? 8000 : ms);
  }

  /// Sends [job] and returns the daemon's upload id. [onOpened] fires once
  /// the id is known (persist it) and [onProgress] with the acknowledged
  /// byte count.
  Future<String> upload(
    UploadJob job, {
    void Function(String uploadId)? onOpened,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final file = File(job.path);
    if (!await file.exists()) {
      throw const UploadFailure('File sumber sudah tidak ada.');
    }
    final total = await file.length();
    var id = job.uploadId;
    var offset = 0;
    var chunk = 1 << 20;

    Future<void> open() async {
      final r = await _guard(
        () => dio.post<dynamic>(
          '/api/sessions/${Uri.encodeComponent(job.sid)}/uploads',
          data: {
            'name': job.name,
            'size': total,
            'mime': job.mime,
            if (job.caption.isNotEmpty) 'caption': job.caption,
          },
          cancelToken: cancel,
        ),
      );
      final d = _map(r.data);
      id = '${d['id']}';
      offset = (d['offset'] as num?)?.toInt() ?? 0;
      chunk = (d['chunk'] as num?)?.toInt() ?? chunk;
      onOpened?.call(id!);
    }

    if (id == null) {
      await _retrying(open);
    } else {
      try {
        final st = await _retrying(() => _status(id!, cancel));
        offset = st.offset;
        if (st.done) {
          onProgress?.call(total, total);
          return id!;
        }
      } on UploadFailure catch (e) {
        if (e.message != _notFound) rethrow;
        id = null;
        await _retrying(open);
      }
    }
    onProgress?.call(offset, total);

    var tries = 0;
    while (offset < total || total == 0) {
      final end = (offset + chunk) < total ? offset + chunk : total;
      final base = offset;
      try {
        final r = await _guard(
          () => dio.put<dynamic>(
            '/api/uploads/${Uri.encodeComponent(id!)}',
            data: file.openRead(offset, end),
            cancelToken: cancel,
            options: Options(
              contentType: 'application/octet-stream',
              headers: {
                'Upload-Offset': '$offset',
                Headers.contentLengthHeader: end - offset,
              },
            ),
            onSendProgress: (n, _) => onProgress?.call(base + n, total),
          ),
        );
        final d = _map(r.data);
        offset = (d['offset'] as num?)?.toInt() ?? end;
        tries = 0;
        onProgress?.call(offset, total);
        if (d['done'] == true || total == 0) break;
      } on UploadFailure catch (e) {
        // A 409 means our offset is stale: resync below like a network drop.
        if (!e.message.startsWith(_retryable)) rethrow;
        if (++tries > maxTries) {
          throw UploadFailure(e.message.substring(_retryable.length));
        }
        await Future<void>.delayed(backoff(tries));
        try {
          final st = await _status(id!, cancel);
          offset = st.offset;
          onProgress?.call(offset, total);
          if (st.done) break;
        } on UploadFailure catch (e2) {
          if (e2.message == _notFound) rethrow;
          // still offline: the next PUT attempt will tell
        }
      }
    }
    return id!;
  }

  /// Retries [run] on connection loss with the same backoff as the chunks.
  Future<T> _retrying<T>(Future<T> Function() run) async {
    for (var tries = 1; ; tries++) {
      try {
        return await run();
      } on UploadFailure catch (e) {
        if (!e.message.startsWith(_retryable) || tries > maxTries) rethrow;
        await Future<void>.delayed(backoff(tries));
      }
    }
  }

  static const _retryable = '\u0000retry:';
  static const _notFound = 'Unggahan tidak ditemukan di Kantor.';

  Future<({int offset, bool done})> _status(
    String id,
    CancelToken? cancel,
  ) async {
    final r = await _guard(
      () => dio.get<dynamic>(
        '/api/uploads/${Uri.encodeComponent(id)}',
        cancelToken: cancel,
      ),
      notFound: _notFound,
    );
    final d = _map(r.data);
    return (
      offset: (d['offset'] as num?)?.toInt() ?? 0,
      done: d['done'] == true,
    );
  }

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Maps dio errors: cancel -> [UploadCancelled]; connection loss, 5xx, 408,
  /// 409 and 429 -> an [UploadFailure] marked retryable; other 4xx -> a final
  /// [UploadFailure] with the daemon's message.
  Future<Response<dynamic>> _guard(
    Future<Response<dynamic>> Function() run, {
    String? notFound,
  }) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const UploadCancelled();
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : null;
      if (status == null) {
        throw const UploadFailure('${_retryable}Koneksi ke Kantor terputus.');
      }
      if (status == 404 && notFound != null) throw UploadFailure(notFound);
      if (status >= 500 || status == 408 || status == 409 || status == 429) {
        throw UploadFailure('$_retryable${msg ?? 'Kantor menolak ($status).'}');
      }
      if (status == 401 || status == 403) {
        throw UploadFailure(msg ?? 'Token Kantor salah atau belum diisi.');
      }
      throw UploadFailure(msg ?? 'Kantor menolak ($status).');
    }
  }
}

/// Error text without the internal retry marker.
String uploadErrorText(Object e) {
  if (e is UploadFailure) {
    return e.message.replaceFirst(KantorUploader._retryable, '');
  }
  return '$e';
}
