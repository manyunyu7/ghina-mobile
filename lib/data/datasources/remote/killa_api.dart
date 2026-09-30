import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../domain/entities/killa.dart';
import '../../models/killa_wire.dart';
import 'api_client.dart';

/// `/api/mobile/killa/*` (`docs/killa.md` → "Mobile API"). Every call throws
/// a [KillaException].
abstract interface class KillaApi {
  Future<KillaMessagePage> chat({String? before, int limit});
  Future<KillaSendResult> send({
    required String text,
    required List<KillaOutgoingMedia> media,
  });

  /// The persisted model (engine-side, shared with the WA chat).
  Future<KillaModelSetting> model();

  /// Persists [model] (`"default"` clears it) → the stored value.
  Future<String?> setModel(String model);
  Future<KillaMessage?> newSession();
  Future<KillaMediaFile> media(String path);
  Future<KillaDirListing> listFiles(String path);
  Future<KillaFileContent> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<String?> commit({String? message});
  Future<List<KillaCommit>> commits({int limit});
  Future<List<KillaReminder>> reminders();
  Future<bool> cancelReminder(String id);
  Future<KillaUsage> usage({int days});
}

final class DioKillaApi implements KillaApi {
  DioKillaApi(this._client);
  final ApiClient _client;

  static const _base = '/api/mobile/killa';

  /// A reply can take ~5.5 min server-side; wait longer than that.
  static const chatTimeout = Duration(minutes: 7);

  Dio get _dio => _client.dio;

  @override
  Future<KillaMessagePage> chat({String? before, int limit = 50}) =>
      killaCall(() async {
        final r = await _dio.get<Object?>(
          '$_base/chat',
          queryParameters: {'limit': limit, 'before': ?before},
        );
        return killaChatPageFromWire(r.data);
      });

  @override
  Future<KillaSendResult> send({
    required String text,
    required List<KillaOutgoingMedia> media,
  }) => killaCall(() async {
    final r = await _dio.post<Object?>(
      '$_base/chat',
      data: {
        'text': text,
        if (media.isNotEmpty)
          'media': [for (final m in media) killaMediaToWire(m)],
      },
      options: Options(
        receiveTimeout: chatTimeout,
        sendTimeout: const Duration(minutes: 3),
      ),
    );
    return killaSendResultFromWire(r.data);
  });

  @override
  Future<KillaModelSetting> model() => killaCall(() async {
    final r = await _dio.get<Object?>('$_base/model');
    return killaModelFromWire(r.data);
  });

  @override
  Future<String?> setModel(String model) => killaCall(() async {
    final r = await _dio.post<Object?>('$_base/model', data: {'model': model});
    final d = r.data;
    if (d is Map && d['ok'] == false) {
      throw KillaException(
        KillaErrorKind.invalid,
        d['error'] is String ? d['error'] as String : 'Model belum tersimpan.',
      );
    }
    return killaModelFromWire(d).model;
  });

  @override
  Future<KillaMessage?> newSession() => killaCall(() async {
    final r = await _dio.post<Object?>('$_base/chat/new');
    return killaDividerFromWire(r.data);
  });

  @override
  Future<KillaMediaFile> media(String path) => killaCall(() async {
    final r = await _dio.get<List<int>>(
      '$_base/media',
      queryParameters: {'path': path},
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return KillaMediaFile(
      bytes: Uint8List.fromList(r.data ?? const []),
      contentType: r.headers.value(Headers.contentTypeHeader),
    );
  });

  @override
  Future<KillaDirListing> listFiles(String path) => killaCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/files',
      queryParameters: {'path': path},
    );
    return killaDirFromWire(r.data, requested: path);
  });

  @override
  Future<KillaFileContent> readFile(String path) => killaCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/file',
      queryParameters: {'path': path},
    );
    return killaFileFromWire(r.data, requested: path);
  });

  @override
  Future<void> writeFile(String path, String content) => killaCall(() async {
    await _dio.put<Object?>(
      '$_base/file',
      data: {'path': path, 'content': content},
      options: Options(sendTimeout: const Duration(minutes: 2)),
    );
  });

  @override
  Future<String?> commit({String? message}) => killaCall(() async {
    final r = await _dio.post<Object?>(
      '$_base/commit',
      data: {'message': ?message},
    );
    final d = r.data;
    final hash = d is Map ? d['hash'] : null;
    return hash is String && hash.isNotEmpty ? hash : null;
  });

  @override
  Future<List<KillaCommit>> commits({int limit = 50}) => killaCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/commits',
      queryParameters: {'limit': limit},
    );
    return killaCommitsFromWire(r.data);
  });

  @override
  Future<List<KillaReminder>> reminders() => killaCall(() async {
    final r = await _dio.get<Object?>('$_base/reminders');
    return killaRemindersFromWire(r.data);
  });

  @override
  Future<bool> cancelReminder(String id) => killaCall(() async {
    final r = await _dio.post<Object?>(
      '$_base/reminders/cancel',
      data: {'id': int.tryParse(id) ?? id},
    );
    final d = r.data;
    return d is Map && d['ok'] == true;
  });

  @override
  Future<KillaUsage> usage({int days = 30}) => killaCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/usage',
      queryParameters: {'days': days},
    );
    return killaUsageFromWire(r.data);
  });
}

/// Runs a Killa request, rethrowing any error as a [KillaException].
Future<T> killaCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on KillaException {
    rethrow;
  } catch (e) {
    throw mapKillaError(e);
  }
}

/// Dio errors → [KillaException] with friendly Indonesian copy.
KillaException mapKillaError(Object error) {
  if (error is KillaException) return error;
  if (error is FormatException) {
    return const KillaException(
      KillaErrorKind.unknown,
      'Jawaban server nggak bisa dibaca. Coba lagi, ya.',
    );
  }
  if (error is! DioException) {
    return const KillaException(
      KillaErrorKind.unknown,
      'Ups, ada yang salah. Coba lagi, yuk.',
    );
  }
  switch (error.type) {
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return const KillaException(
        KillaErrorKind.timeout,
        'Killa kelamaan menjawab. Balasannya mungkin tetap tersimpan — cek lagi sebentar.',
      );
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.connectionError:
      return const KillaException(
        KillaErrorKind.network,
        'Lagi offline. Killa butuh internet, ya.',
      );
    case DioExceptionType.unknown when error.response == null:
      return const KillaException(
        KillaErrorKind.network,
        'Lagi offline. Killa butuh internet, ya.',
      );
    default:
      break;
  }
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final msg = data is Map && data['error'] is String
      ? data['error'] as String
      : null;
  return switch (status) {
    403 => KillaException(
      KillaErrorKind.forbidden,
      'Killa khusus untuk akun tertentu. Akun kamu belum punya akses.',
      status: status,
    ),
    401 => KillaException(
      KillaErrorKind.unauthorized,
      'Sesi kamu sudah berakhir. Masuk lagi, ya.',
      status: status,
    ),
    503 => KillaException(
      KillaErrorKind.engineOff,
      'Killa lagi nggak aktif (engine mati). Coba lagi nanti.',
      status: status,
    ),
    504 => KillaException(
      KillaErrorKind.timeout,
      'Killa kelamaan menjawab. Balasannya mungkin tetap tersimpan — cek lagi sebentar.',
      status: status,
    ),
    502 => KillaException(
      KillaErrorKind.engineError,
      'Killa lagi bermasalah. Coba lagi sebentar lagi, ya.',
      status: status,
    ),
    413 => KillaException(
      KillaErrorKind.tooLarge,
      'Filenya terlalu besar untuk dibuka di sini.',
      status: status,
    ),
    415 => KillaException(
      KillaErrorKind.unsupported,
      'Jenis file ini nggak didukung (bukan teks / format tidak dikenal).',
      status: status,
    ),
    404 => KillaException(
      KillaErrorKind.notFound,
      msg ?? 'Nggak ketemu.',
      status: status,
    ),
    400 || 422 => KillaException(
      KillaErrorKind.invalid,
      msg ?? 'Datanya belum valid.',
      status: status,
    ),
    _ => KillaException(
      KillaErrorKind.unknown,
      'Server bermasalah (${status ?? '?'}). Coba lagi, ya.',
      status: status,
    ),
  };
}
