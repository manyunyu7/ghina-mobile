import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../domain/entities/screener.dart';
import '../../../domain/entities/stockbit.dart';
import '../../../domain/repositories/stockbit_gateway.dart';
import '../../../domain/usecases/stockbit_parser.dart';
import '../../models/stockbit_wire.dart';

/// Backoff before the retries of a 429 / 5xx answer.
const stockbitBackoff = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
];

/// Reads Stockbit from the phone. It uses its own [Dio] with the client's
/// default headers (no browser-imitating headers), and never carries the
/// Ghina token.
final class DioStockbitGateway implements StockbitGateway {
  DioStockbitGateway({
    Dio? dio,
    Future<void> Function(Duration)? sleep,
    this.backoff = stockbitBackoff,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               responseType: ResponseType.plain,
               validateStatus: (_) => true,
             ),
           ),
       _sleep = sleep ?? Future<void>.delayed;

  static const baseUrl = 'https://exodus.stockbit.com';

  final Dio _dio;
  final Future<void> Function(Duration) _sleep;
  final List<Duration> backoff;

  Future<Object?> _send(
    String method,
    String path,
    String bearer, {
    bool retry = true,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final Response<Object?> r;
      try {
        r = await _dio.request<Object?>(
          path,
          options: Options(
            method: method,
            headers: {'Authorization': 'Bearer $bearer'},
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.badResponse && e.response != null) {
          throw classifyStockbitResponse(
            e.response!.statusCode,
            e.response!.data,
          );
        }
        throw const StockbitException(
          StockbitErrorKind.network,
          'Lagi offline atau Stockbit nggak terjangkau. Cek koneksi, ya.',
        );
      }
      final status = r.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final raw = r.data;
        if (raw is String) {
          try {
            return jsonDecode(raw);
          } catch (_) {
            throw const StockbitException(
              StockbitErrorKind.unknown,
              'Jawaban Stockbit nggak bisa dibaca.',
            );
          }
        }
        return raw;
      }
      final transient = status == 429 || status >= 500;
      if (retry && transient && attempt < backoff.length) {
        await _sleep(backoff[attempt]);
        continue;
      }
      throw classifyStockbitResponse(status, r.data);
    }
  }

  @override
  Future<List<StockbitCompany>> companies(String access) async =>
      stockbitCompaniesFromWire(
        await _send(
          'GET',
          '/emitten/v3/sector/88/subsector/467/company',
          access,
        ),
      );

  @override
  Future<List<ShareholderPoint>?> profile(String access, String ticker) async {
    try {
      return stockbitProfileFromWire(
        await _send(
          'GET',
          '/emitten/${Uri.encodeComponent(ticker)}/profile',
          access,
        ),
      );
    } on StockbitException catch (e) {
      if (e.kind == StockbitErrorKind.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<List<PricePoint>> dailyPrices(String access, String ticker) async =>
      stockbitPricesFromWire(
        await _send(
          'GET',
          '/charts/${Uri.encodeComponent(ticker)}/daily?timeframe=3y',
          access,
        ),
      );

  @override
  Future<StockbitTokens> refresh(String refreshToken) async {
    final body = await _send(
      'POST',
      '/login/refresh',
      refreshToken,
      retry: false,
    );
    final parsed = parseStockbitInput(jsonEncode(body));
    if (parsed is StockbitParsed && parsed.tokens.access != null) {
      return parsed.tokens;
    }
    throw const StockbitException(
      StockbitErrorKind.tokenRejected,
      'Sesi Stockbit habis — tempel token baru.',
    );
  }
}
