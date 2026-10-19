import 'package:dio/dio.dart';

import '../../domain/entities/statement_import.dart';
import '../../domain/repositories/statement_repository.dart';
import '../datasources/remote/api_client.dart';
import '../models/statement_wire.dart';

/// Largest PDF the server takes (decoded).
const statementMaxBytes = 10 * 1024 * 1024;

/// [StatementRepository] over `/api/mobile/statements`. Nothing is cached:
/// every call answers from the server.
final class ApiStatementRepository implements StatementRepository {
  ApiStatementRepository(this._client);
  final ApiClient _client;

  Dio get _dio => _client.dio;

  static const _base = '/api/mobile/statements';

  static String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<List<StatementImport>> list() => _call(() async {
    final r = await _dio.get<Object?>(_base);
    return statementImportsFromWire(r.data);
  });

  @override
  Future<StatementDetail> detail(String id) => _call(() async {
    final r = await _dio.get<Object?>('$_base/${_id(id)}');
    final d = statementDetailFromWire(r.data);
    if (d == null) throw const FormatException('detail');
    return d;
  });

  @override
  Future<StatementImport> upload(StatementUpload upload) => _call(() async {
    if (upload.bytes.length > statementMaxBytes) {
      throw const StatementException(
        StatementErrorKind.tooLarge,
        'PDF-nya lebih dari 10 MB. Coba file yang lebih kecil, ya.',
      );
    }
    final r = await _dio.post<Object?>(
      _base,
      data: statementUploadToWire(upload),
      // Base64 of up to 10 MB, then text extraction on the server.
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return _importOf(r.data);
  });

  @override
  Future<StatementImport> retry(String id) => _call(() async {
    final r = await _dio.post<Object?>('$_base/${_id(id)}/retry');
    return _importOf(r.data);
  });

  @override
  Future<StatementRow> editRow(String rowId, StatementRowPatch patch) =>
      _call(() async {
        final r = await _dio.patch<Object?>(
          '$_base/rows/${_id(rowId)}',
          data: statementRowPatchToWire(patch),
        );
        final d = r.data;
        final row = statementRowFromWire(d is Map ? d['row'] : null);
        if (row == null) throw const FormatException('row');
        return row;
      });

  @override
  Future<int> approve(String id, List<String> rowIds) => _call(() async {
    final r = await _dio.post<Object?>(
      '$_base/${_id(id)}/approve',
      data: {'rowIds': rowIds},
      options: Options(receiveTimeout: const Duration(minutes: 1)),
    );
    final d = r.data;
    final n = d is Map ? d['created'] : null;
    if (n is! num) throw const FormatException('approve');
    return n.toInt();
  });

  @override
  Future<void> ignore(String id, List<String> rowIds) => _call(() async {
    await _dio.post<Object?>(
      '$_base/${_id(id)}/ignore',
      data: {'rowIds': rowIds},
    );
  });

  @override
  Future<void> delete(String id) => _call(() async {
    await _dio.delete<Object?>('$_base/${_id(id)}');
  });

  static StatementImport _importOf(Object? data) {
    final i = statementImportFromWire(data is Map ? data['import'] : null);
    if (i == null) throw const FormatException('import');
    return i;
  }

  static Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapStatementError(e);
    }
  }
}

/// Dio errors → [StatementException] with friendly Indonesian copy.
StatementException mapStatementError(Object error) {
  if (error is StatementException) return error;
  if (error is FormatException) {
    return const StatementException(
      StatementErrorKind.unknown,
      'Jawaban server nggak bisa dibaca. Coba lagi, ya.',
    );
  }
  if (error is! DioException) {
    return const StatementException(
      StatementErrorKind.unknown,
      'Ups, ada yang salah. Coba lagi, yuk.',
    );
  }
  const offline = StatementException(
    StatementErrorKind.network,
    'Lagi offline. Impor mutasi butuh internet, ya.',
  );
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return offline;
    case DioExceptionType.unknown when error.response == null:
      return offline;
    default:
      break;
  }
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final code = data is Map && data['error'] is String
      ? data['error'] as String
      : null;
  return switch (status) {
    403 => StatementException(
      StatementErrorKind.forbidden,
      'Impor mutasi belum aktif untuk akun kamu.',
      status: status,
    ),
    401 => StatementException(
      StatementErrorKind.unauthorized,
      'Sesi kamu sudah berakhir. Masuk lagi, ya.',
      status: status,
    ),
    422 when code == 'password_required' => StatementException(
      StatementErrorKind.passwordRequired,
      'PDF ini dikunci. Masukkan password-nya — tidak disimpan.',
      status: status,
    ),
    422 when code == 'password_wrong' => StatementException(
      StatementErrorKind.passwordWrong,
      'Password-nya belum cocok. Coba lagi, ya.',
      status: status,
    ),
    415 => StatementException(
      StatementErrorKind.invalid,
      'File ini bukan PDF. Pilih PDF mutasi, ya.',
      status: status,
    ),
    413 => StatementException(
      StatementErrorKind.tooLarge,
      'PDF-nya lebih dari 10 MB. Coba file yang lebih kecil, ya.',
      status: status,
    ),
    400 || 422 => StatementException(
      StatementErrorKind.invalid,
      code ?? 'Datanya belum valid.',
      status: status,
    ),
    404 => StatementException(
      StatementErrorKind.notFound,
      'Impor ini sudah nggak ada. Coba muat ulang.',
      status: status,
    ),
    409 => StatementException(
      StatementErrorKind.conflict,
      'Killa masih membaca, atau barisnya sudah diproses. Muat ulang dulu, ya.',
      status: status,
    ),
    _ => StatementException(
      StatementErrorKind.unknown,
      'Server bermasalah (${status ?? '?'}). Coba lagi, ya.',
      status: status,
    ),
  };
}
