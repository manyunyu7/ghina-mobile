import 'package:dio/dio.dart';

import '../../core/failure.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/remote/api_client.dart';
import '../models/dreams_online_wire.dart';

/// [DreamOnlineRepository] over `/api/mobile/dreams` (`docs/dreams.md` → REST).
/// Nothing computed is cached: each call answers from the server. A response
/// without its core object is an `UnknownFailure`, never a crash.
final class ApiDreamOnlineRepository implements DreamOnlineRepository {
  ApiDreamOnlineRepository(this._client);
  final ApiClient _client;

  Dio get _dio => _client.dio;

  static const _base = '/api/mobile/dreams';

  @override
  Future<DreamSummary> summary({String? tz}) => apiCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/summary',
      queryParameters: {'tz': ?tz},
    );
    final d = r.data;
    final s = d is Map ? dreamSummaryFromWire(_asJson(d)) : null;
    if (s == null) {
      throw const UnknownFailure('Respons ringkasan mimpi tidak valid');
    }
    return s;
  });

  @override
  Future<DreamDetail> fetch(String id, {String? tz}) => apiCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/${Uri.encodeComponent(id)}',
      queryParameters: {'tz': ?tz},
    );
    final d = r.data;
    final detail = d is Map ? dreamDetailFromWire(_asJson(d)) : null;
    if (detail == null) throw const UnknownFailure('Respons mimpi tidak valid');
    return detail;
  });

  @override
  Future<ManualValueResult> recordManualValue(
    String dreamId,
    String metricId,
    double value, {
    DateTime? at,
  }) => apiCall(() async {
    final r = await _dio.post<Object?>(
      '$_base/${Uri.encodeComponent(dreamId)}/metrics/${Uri.encodeComponent(metricId)}/value',
      data: {'value': value, 'at': ?at?.toUtc().toIso8601String()},
    );
    final d = r.data;
    final res = d is Map ? manualValueResultFromWire(_asJson(d)) : null;
    if (res == null) {
      throw const UnknownFailure('Respons nilai manual tidak valid');
    }
    return res;
  });

  /// The decoded JSON object with string keys (what the parsers expect).
  static Map<String, dynamic> _asJson(Map<dynamic, dynamic> m) => {
    for (final e in m.entries) '${e.key}': e.value,
  };
}
