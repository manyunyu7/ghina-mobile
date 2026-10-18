import 'package:dio/dio.dart';

import '../../../domain/entities/screener.dart';
import '../../models/screener_wire.dart';
import 'api_client.dart';

/// `/api/mobile/screener/*`. Every call throws a [ScreenerException].
abstract interface class ScreenerApi {
  Future<ScreenerResult> screen(ScreenerQuery query);
  Future<ScreenerStatus> status();
  Future<List<BreadthMonth>> breadth({int months});
  Future<ScreenerTicker> ticker(String ticker);
  Future<List<String>> known();
  Future<List<String>> currentAt(DateTime date);
  Future<int> pushReports(List<ScreenerReportRow> rows);
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes);
  Future<int> pushPrices(List<ScreenerPriceRow> rows);
  Future<Map<String, PriceCoverage>> priceCoverage();
  Future<List<String>> priority();
}

final class DioScreenerApi implements ScreenerApi {
  DioScreenerApi(this._client);
  final ApiClient _client;

  static const _base = '/api/mobile/screener';

  Dio get _dio => _client.dio;

  @override
  Future<ScreenerResult> screen(ScreenerQuery query) => screenerCall(() async {
    final r = await _dio.get<Object?>(
      _base,
      queryParameters: {
        'mode': query.mode.wire,
        'months': query.months,
        'threshold': query.threshold,
        'minPoints': query.minPoints,
      },
    );
    return screenerResultFromWire(r.data, query);
  });

  @override
  Future<ScreenerStatus> status() => screenerCall(() async {
    final r = await _dio.get<Object?>('$_base/status');
    return screenerStatusFromWire(r.data);
  });

  @override
  Future<List<BreadthMonth>> breadth({int months = 24}) =>
      screenerCall(() async {
        final r = await _dio.get<Object?>(
          '$_base/breadth',
          queryParameters: {'months': months},
        );
        return screenerBreadthFromWire(r.data);
      });

  @override
  Future<ScreenerTicker> ticker(String ticker) => screenerCall(() async {
    final r = await _dio.get<Object?>(
      '$_base/ticker/${Uri.encodeComponent(ticker)}',
    );
    return screenerTickerFromWire(r.data, ticker);
  });

  Future<Object?> _sync(Map<String, Object?> body) async {
    final r = await _dio.post<Object?>('$_base/sync', data: body);
    return r.data;
  }

  List<String> _tickers(Object? data) {
    final t = data is Map ? data['tickers'] : null;
    return [
      if (t is List)
        for (final x in t)
          if (x is String) x,
    ];
  }

  int _written(Object? data) {
    final w = data is Map ? data['written'] : null;
    return w is num ? w.toInt() : 0;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<String>> known() =>
      screenerCall(() async => _tickers(await _sync({'op': 'known'})));

  @override
  Future<List<String>> currentAt(DateTime date) => screenerCall(
    () async => _tickers(await _sync({'op': 'currentAt', 'date': _day(date)})),
  );

  @override
  Future<int> pushReports(List<ScreenerReportRow> rows) =>
      screenerCall(() async {
        return _written(
          await _sync({
            'op': 'reports',
            'rows': [
              for (final r in rows)
                {'ticker': r.ticker, 'date': _day(r.date), 'count': r.count},
            ],
          }),
        );
      });

  @override
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes) =>
      screenerCall(() async {
        return _written(
          await _sync({
            'op': 'quotes',
            'quotes': [
              for (final q in quotes)
                {
                  'ticker': q.ticker,
                  'lastPrice': q.lastPrice,
                  'changeValue': q.changeValue,
                  'changePercent': q.changePercent,
                  'volume': q.volume,
                  'marketCap': q.marketCap,
                },
            ],
          }),
        );
      });

  @override
  Future<int> pushPrices(List<ScreenerPriceRow> rows) => screenerCall(() async {
    return _written(
      await _sync({
        'op': 'prices',
        'rows': [
          for (final r in rows)
            {'ticker': r.ticker, 'date': _day(r.date), 'close': r.close},
        ],
      }),
    );
  });

  @override
  Future<Map<String, PriceCoverage>> priceCoverage() => screenerCall(
    () async => screenerCoverageFromWire(await _sync({'op': 'priceCoverage'})),
  );

  @override
  Future<List<String>> priority() =>
      screenerCall(() async => _tickers(await _sync({'op': 'priority'})));
}

/// Runs a Screener request, rethrowing any error as a [ScreenerException].
Future<T> screenerCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ScreenerException {
    rethrow;
  } catch (e) {
    throw mapScreenerError(e);
  }
}

const _offline = 'Lagi offline. Screener butuh internet, ya.';
const _slow = 'Servernya kelamaan menjawab. Cek lagi sebentar, ya.';

/// Dio errors → [ScreenerException]. The server's own `error` text (already
/// Indonesian) wins for 4xx answers.
ScreenerException mapScreenerError(Object error) {
  if (error is ScreenerException) return error;
  if (error is FormatException) {
    return const ScreenerException(
      ScreenerErrorKind.unknown,
      'Jawaban server nggak bisa dibaca. Coba lagi, ya.',
    );
  }
  if (error is! DioException) {
    return const ScreenerException(
      ScreenerErrorKind.unknown,
      'Ups, ada yang salah. Coba lagi, yuk.',
    );
  }
  switch (error.type) {
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return const ScreenerException(ScreenerErrorKind.timeout, _slow);
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.connectionError:
      return const ScreenerException(ScreenerErrorKind.network, _offline);
    case DioExceptionType.unknown when error.response == null:
      return const ScreenerException(ScreenerErrorKind.network, _offline);
    default:
      break;
  }
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final msg = data is Map && data['error'] is String
      ? data['error'] as String
      : null;
  final code = data is Map && data['code'] is String
      ? data['code'] as String
      : null;
  ScreenerException make(ScreenerErrorKind kind, String fallback) =>
      ScreenerException(kind, msg ?? fallback, status: status, code: code);
  return switch (status) {
    403 => const ScreenerException(
      ScreenerErrorKind.forbidden,
      'Screener khusus untuk akun tertentu. Akun kamu belum punya akses.',
      status: 403,
    ),
    401 => const ScreenerException(
      ScreenerErrorKind.unauthorized,
      'Sesi kamu sudah berakhir. Masuk lagi, ya.',
      status: 401,
    ),
    404 => make(ScreenerErrorKind.notFound, 'Emiten ini nggak ketemu.'),
    400 || 422 => make(ScreenerErrorKind.invalid, 'Datanya belum valid.'),
    502 || 503 || 504 => make(ScreenerErrorKind.timeout, _slow),
    _ => make(
      ScreenerErrorKind.unknown,
      'Server bermasalah (${status ?? '?'}). Coba lagi, ya.',
    ),
  };
}
