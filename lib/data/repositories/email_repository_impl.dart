import 'package:dio/dio.dart';

import '../../domain/entities/email.dart';
import '../../domain/repositories/email_repository.dart';
import '../datasources/remote/api_client.dart';
import '../models/email_wire.dart';

/// [EmailRepository] over `/api/mobile/email`. Nothing is cached: every call
/// answers from the server.
final class ApiEmailRepository implements EmailRepository {
  ApiEmailRepository(this._client);
  final ApiClient _client;

  Dio get _dio => _client.dio;

  static const _base = '/api/mobile/email';

  static String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<EmailOverview> overview() => _call(() async {
    final r = await _dio.get<Object?>('$_base/accounts');
    return emailOverviewFromWire(r.data);
  });

  @override
  Future<EmailAccount> connect(String serverAuthCode) => _call(() async {
    final r = await _dio.post<Object?>(
      '$_base/accounts/connect',
      data: {'serverAuthCode': serverAuthCode},
    );
    final d = r.data;
    final a = emailAccountFromWire(d is Map ? d['account'] : null);
    if (a == null) throw const FormatException('account');
    return a;
  });

  @override
  Future<void> disconnect(String accountId) => _call(() async {
    await _dio.delete<Object?>('$_base/accounts/${_id(accountId)}');
  });

  @override
  Future<List<EmailSyncResult>> sync({
    String? accountId,
    bool background = false,
  }) => _call(() async {
    final r = await _dio.post<Object?>(
      '$_base/sync',
      data: {'accountId': ?accountId, if (background) 'background': true},
      // Synchronous on the server (≤ 200 messages per account) unless
      // [background], which answers at once.
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    return background ? const [] : emailSyncResultsFromWire(r.data);
  });

  @override
  Future<EmailSuggestionPage> suggestions(
    EmailSuggestionStatus status, {
    int limit = 50,
    int offset = 0,
  }) => _call(() async {
    final r = await _dio.get<Object?>(
      '$_base/suggestions',
      queryParameters: {
        'status': status.wire,
        'limit': limit,
        'offset': offset,
      },
    );
    return emailSuggestionPageFromWire(r.data);
  });

  @override
  Future<String> approve(String id, EmailApproval approval) => _call(() async {
    final r = await _dio.post<Object?>(
      '$_base/suggestions/${_id(id)}/approve',
      data: emailApprovalToWire(approval),
    );
    final d = r.data;
    final tx = d is Map ? d['transactionId'] : null;
    if (tx is! String || tx.isEmpty) throw const FormatException('approve');
    return tx;
  });

  @override
  Future<void> ignore(String id) => _call(() async {
    await _dio.post<Object?>('$_base/suggestions/${_id(id)}/ignore');
  });

  @override
  Future<void> restore(String id) => _call(() async {
    await _dio.post<Object?>('$_base/suggestions/${_id(id)}/restore');
  });

  @override
  Future<EmailAccount> setTriage(String accountId, bool on) => _call(() async {
    final r = await _dio.patch<Object?>(
      '$_base/accounts/${_id(accountId)}',
      data: {'triage': on},
    );
    final d = r.data;
    final a = emailAccountFromWire(d is Map ? d['account'] : null);
    if (a == null) throw const FormatException('account');
    return a;
  });

  @override
  Future<EmailInboxPage> inbox({
    Set<EmailImportance> importance = const {},
    int limit = 50,
    int offset = 0,
  }) => _call(() async {
    final levels = importance.isEmpty
        ? EmailImportance.shown
        : [
            for (final i in EmailImportance.values)
              if (importance.contains(i)) i,
          ];
    final r = await _dio.get<Object?>(
      '$_base/inbox',
      queryParameters: {
        'importance': levels.map((i) => i.wire).join(','),
        'limit': limit,
        'offset': offset,
      },
    );
    return emailInboxPageFromWire(r.data);
  });

  @override
  Future<void> markRead(String id) => _call(() async {
    await _dio.post<Object?>('$_base/inbox/${_id(id)}/read');
  });

  @override
  Future<List<EmailTriageRule>> rules() => _call(() async {
    final r = await _dio.get<Object?>('$_base/inbox/rules');
    return emailTriageRulesFromWire(r.data);
  });

  @override
  Future<EmailTriageRule> addRule(EmailRuleInput input) => _call(() async {
    final r = await _dio.post<Object?>(
      '$_base/inbox/rules',
      data: emailRuleInputToWire(input),
    );
    final rule = emailTriageRuleFromWire(r.data);
    if (rule == null) throw const FormatException('rule');
    return rule;
  });

  @override
  Future<void> deleteRule(String id) => _call(() async {
    await _dio.delete<Object?>('$_base/inbox/rules/${_id(id)}');
  });

  static Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapEmailError(e);
    }
  }
}

/// Dio errors → [EmailException] with friendly Indonesian copy.
EmailException mapEmailError(Object error) {
  if (error is EmailException) return error;
  if (error is FormatException) {
    return const EmailException(
      EmailErrorKind.unknown,
      'Jawaban server nggak bisa dibaca. Coba lagi, ya.',
    );
  }
  if (error is! DioException) {
    return const EmailException(
      EmailErrorKind.unknown,
      'Ups, ada yang salah. Coba lagi, yuk.',
    );
  }
  const offline = EmailException(
    EmailErrorKind.network,
    'Lagi offline. Fitur email butuh internet, ya.',
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
    403 when code == 'email_not_enabled' => EmailException(
      EmailErrorKind.notEnabled,
      'Fitur email belum aktif untuk akun kamu.',
      status: status,
    ),
    401 => EmailException(
      EmailErrorKind.unauthorized,
      'Sesi kamu sudah berakhir. Masuk lagi, ya.',
      status: status,
    ),
    400 || 422 => EmailException(
      EmailErrorKind.invalid,
      code ?? 'Datanya belum valid.',
      status: status,
    ),
    404 => EmailException(
      EmailErrorKind.notFound,
      'Datanya sudah nggak ada. Coba muat ulang.',
      status: status,
    ),
    409 => EmailException(
      EmailErrorKind.conflict,
      'Saran ini sudah diproses sebelumnya.',
      status: status,
    ),
    502 => EmailException(
      EmailErrorKind.google,
      'Google lagi nggak bisa dihubungi. Coba lagi sebentar, ya.',
      status: status,
    ),
    _ => EmailException(
      EmailErrorKind.unknown,
      'Server bermasalah (${status ?? '?'}). Coba lagi, ya.',
      status: status,
    ),
  };
}
