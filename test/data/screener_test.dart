// Screener mobile API: DTO mapping (nulls, int/double, new fields), error
// mapping and the repository over a fake Dio adapter. Data is invented.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/screener_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/screener_wire.dart';
import 'package:ghina/data/repositories/screener_repository_impl.dart';
import 'package:ghina/domain/entities/entities.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readToken() async => 'tok';
  @override
  Future<void> writeToken(String? token) async {}
  @override
  Future<String?> readUser() async => null;
  @override
  Future<void> writeUser(String? userJson) async {}
  @override
  Future<void> clear() async {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);
  final Map<String, (int, Object?)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final (status, body) =
        routes['${o.method} ${o.path}'] ?? (404, {'error': 'nope'});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({RemoteScreenerRepository repo, _Adapter adapter}) _rig(
  Map<String, (int, Object?)> routes,
) {
  final adapter = _Adapter(routes);
  final client = ApiClient(baseUrl: 'https://x.test', tokens: _Tokens());
  client.dio.httpClientAdapter = adapter;
  return (
    repo: RemoteScreenerRepository(DioScreenerApi(client)),
    adapter: adapter,
  );
}

const _row = {
  'ticker': 'ABCD',
  'firstDate': '2026-04-30',
  'lastDate': '2026-09-30',
  'firstCount': 1000,
  'lastCount': 900.0,
  'change': -100,
  'changePercent': -10,
  'declineStreak': 3,
  'declineRatio': 0.75,
  'points': 5,
  'price': 1250,
  'priceChangePercent': -1.5,
  'volume': 12345.0,
  'marketCap': 2500000000000,
  'spark': [1000, 980.5, 950, 900],
};

void main() {
  group('wire', () {
    test('row: int and double numbers, spark', () {
      final r = screenerRowFromWire(_row)!;
      expect(r.ticker, 'ABCD');
      expect(r.firstDate, DateTime(2026, 4, 30));
      expect(r.lastCount, 900);
      expect(r.changePercent, -10.0);
      expect(r.price, 1250.0);
      expect(r.marketCap, 2.5e12);
      expect(r.spark, [1000.0, 980.5, 950.0, 900.0]);
    });

    test('row: nulls, missing spark, junk ratio', () {
      final r = screenerRowFromWire({
        'ticker': 'WXYZ',
        'firstCount': 10,
        'lastCount': 9,
        'change': -1,
        'changePercent': -10.0,
        'declineStreak': 1,
        'declineRatio': 4,
        'points': 2,
        'price': null,
        'marketCap': null,
        'spark': 'x',
      })!;
      expect(r.price, isNull);
      expect(r.priceChangePercent, isNull);
      expect(r.volume, isNull);
      expect(r.marketCap, isNull);
      expect(r.spark, isEmpty);
      expect(r.declineRatio, 1.0);
      expect(screenerRowFromWire({'firstCount': 1}), isNull);
    });

    test('result: params, rows, window', () {
      final r = screenerResultFromWire({
        'params': {
          'months': 12,
          'mode': 'strict',
          'threshold': 0.7,
          'minPoints': 3,
        },
        'results': [_row, 'junk'],
        'from': '2025-10-01',
        'to': '2026-10-01',
        'scanned': 800,
      }, const ScreenerQuery());
      expect(r.query.mode, ScreenerMode.strict);
      expect(r.query.months, 12);
      expect(r.query.threshold, 0.7);
      expect(r.rows, hasLength(1));
      expect(r.scanned, 800);
      expect(r.to, DateTime(2026, 10, 1));
    });

    test('status and session', () {
      final s = screenerStatusFromWire({
        'stats': {'rows': 5000, 'tickers': 800, 'oldest': '2026-04-01'},
        'anchor': '2026-09-30',
        'reportsUpdatedAt': '2026-10-17T03:00:00.000Z',
        'quotesFetchedAt': null,
        'session': {'autoRenew': true},
      });
      expect(s.stats.tickers, 800);
      expect(s.anchor, DateTime(2026, 9, 30));
      expect(s.quotesFetchedAt, isNull);
      expect(s.reportsUpdatedAt!.toUtc().hour, 3);
      expect(screenerStatusFromWire(null).stats.rows, 0);
    });

    Map<String, Object?> tickerBody(Object? prices) => {
      'ticker': 'ABCD',
      'history': [
        {'date': '2026-09-30', 'count': 900},
        {'date': '2026-03-31', 'count': 1000.0},
        {'date': 'bad', 'count': 1},
      ],
      'quote': {
        'lastPrice': 1250,
        'changeValue': -20,
        'changePercent': -1.5,
        'volume': 1000,
        'marketCap': null,
        'fetchedAt': '2026-10-17T08:00:00.000Z',
      },
      'prices': ?prices,
    };

    test('ticker: history sorted oldest first, quote with nulls', () {
      final t = screenerTickerFromWire(tickerBody(null), 'ABCD');
      expect(t.history.map((p) => p.count), [1000, 900]);
      expect(t.quote!.lastPrice, 1250);
      expect(t.quote!.marketCap, isNull);
      expect(t.prices.status, ScreenerPricesStatus.error);
      expect(t.prices.hasData, isFalse);
      expect(
        screenerTickerFromWire({'history': [], 'quote': null}, 'ZZZZ').quote,
        isNull,
      );
    });

    test('ticker prices: ok', () {
      final t = screenerTickerFromWire(
        tickerBody({
          'status': 'ok',
          'points': [
            {'date': '2026-10-02', 'close': 1260},
            {'date': '2026-10-01', 'close': 1250.5},
            {'date': '2026-10-03', 'close': null},
          ],
        }),
        'ABCD',
      );
      expect(t.prices.status, ScreenerPricesStatus.ok);
      expect(t.prices.points.map((p) => p.close), [1250.5, 1260.0]);
      expect(t.prices.hasData, isTrue);
    });

    test('ticker prices: not_connected and error keep the message', () {
      final nc = screenerPricesFromWire({
        'status': 'not_connected',
        'points': [
          {'date': '2026-10-01', 'close': 1},
        ],
        'message': 'Hubungkan Stockbit dulu.',
      });
      expect(nc.status, ScreenerPricesStatus.notConnected);
      expect(nc.points, isEmpty);
      expect(nc.message, 'Hubungkan Stockbit dulu.');
      final er = screenerPricesFromWire({'status': 'error', 'points': []});
      expect(er.status, ScreenerPricesStatus.error);
      expect(er.message, isNull);
      expect(screenerPricesFromWire('?').status, ScreenerPricesStatus.error);
    });

    test('breadth: oldest first, bad months skipped', () {
      final b = screenerBreadthFromWire({
        'months': [
          {'month': '2026-09', 'declining': 300, 'rising': 200.0, 'flat': 10},
          {'month': '2026-08', 'declining': 100, 'rising': 400, 'flat': 0},
          {'month': 'oops', 'declining': 1},
        ],
      });
      expect(b.map((m) => m.month), [DateTime(2026, 8), DateTime(2026, 9)]);
      expect(b.last.total, 510);
      expect(b.last.decliningPercent, closeTo(300 / 510 * 100, 1e-9));
      expect(
        BreadthMonth(
          month: _m,
          declining: 0,
          rising: 0,
          flat: 0,
        ).decliningPercent,
        isNull,
      );
    });

    test('price coverage', () {
      final c = screenerCoverageFromWire({
        'coverage': {
          'ABCD': {'first': '2023-10-02', 'last': '2026-10-16', 'count': 750},
          'WXYZ': {'first': null, 'last': null, 'count': 0},
        },
      });
      expect(c['ABCD']!.count, 750);
      expect(c['ABCD']!.last, DateTime(2026, 10, 16));
      expect(c['WXYZ']!.first, isNull);
      expect(screenerCoverageFromWire(null), isEmpty);
    });
  });

  group('error mapping', () {
    DioException http(int status, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

    test('403 forbidden, 401 unauthorized', () {
      expect(
        mapScreenerError(http(403, {'error': 'forbidden'})).kind,
        ScreenerErrorKind.forbidden,
      );
      expect(
        mapScreenerError(http(401, null)).kind,
        ScreenerErrorKind.unauthorized,
      );
    });

    test('400 / 422 keep the server text and code', () {
      final e = mapScreenerError(
        http(422, {'error': 'Token sudah kedaluwarsa.', 'code': 'expired'}),
      );
      expect(e.kind, ScreenerErrorKind.invalid);
      expect(e.message, 'Token sudah kedaluwarsa.');
      expect(e.code, 'expired');
    });

    test('404, 500, offline, timeout, bad JSON', () {
      expect(
        mapScreenerError(http(404, {'error': 'x', 'code': 'not_found'})).kind,
        ScreenerErrorKind.notFound,
      );
      expect(mapScreenerError(http(500, null)).kind, ScreenerErrorKind.unknown);
      expect(
        mapScreenerError(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        ).kind,
        ScreenerErrorKind.network,
      );
      expect(
        mapScreenerError(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.receiveTimeout,
          ),
        ).kind,
        ScreenerErrorKind.timeout,
      );
      expect(
        mapScreenerError(const FormatException('x')).kind,
        ScreenerErrorKind.unknown,
      );
    });
  });

  group('repository', () {
    test('screen sends the query and parses; ticker is encoded', () async {
      final rig = _rig({
        'GET /api/mobile/screener': (
          200,
          {
            'params': {'months': 12, 'mode': 'endpoint'},
            'results': [_row],
            'from': '2025-10-01',
            'to': '2026-10-01',
            'scanned': 10,
          },
        ),
        'GET /api/mobile/screener/ticker/ABCD': (
          200,
          {'ticker': 'ABCD', 'history': [], 'quote': null},
        ),
        'GET /api/mobile/screener/breadth': (
          200,
          {
            'months': [
              {'month': '2026-09', 'declining': 1, 'rising': 2, 'flat': 0},
            ],
          },
        ),
      });
      final res = await rig.repo.screen(
        const ScreenerQuery(months: 12, mode: ScreenerMode.endpoint),
      );
      expect(res.rows.single.ticker, 'ABCD');
      final q = rig.adapter.requests.single.queryParameters;
      expect(q, {
        'mode': 'endpoint',
        'months': 12,
        'threshold': 0.6,
        'minPoints': 2,
      });
      expect((await rig.repo.ticker('ABCD')).ticker, 'ABCD');
      expect(await rig.repo.breadth(months: 12), hasLength(1));
      expect(rig.adapter.requests.last.queryParameters, {'months': 12});
    });

    test('sync ops post the documented bodies', () async {
      final rig = _rig({
        'POST /api/mobile/screener/sync': (
          200,
          {
            'tickers': ['ABCD', 3],
            'written': 2,
          },
        ),
      });
      expect(await rig.repo.known(), ['ABCD']);
      expect(await rig.repo.currentAt(DateTime(2026, 9, 30)), ['ABCD']);
      expect(
        await rig.repo.pushReports([
          ScreenerReportRow(
            ticker: 'ABCD',
            date: DateTime(2026, 9, 30),
            count: 900,
          ),
        ]),
        2,
      );
      expect(
        await rig.repo.pushQuotes(const [
          ScreenerQuoteRow(ticker: 'ABCD', lastPrice: 1250),
        ]),
        2,
      );
      expect(
        await rig.repo.pushPrices([
          ScreenerPriceRow(
            ticker: 'ABCD',
            date: DateTime(2026, 10, 1),
            close: 1250.5,
          ),
        ]),
        2,
      );
      await rig.repo.priceCoverage();
      await rig.repo.priority();
      final bodies = [for (final r in rig.adapter.requests) r.data];
      expect(bodies[0], {'op': 'known'});
      expect(bodies[1], {'op': 'currentAt', 'date': '2026-09-30'});
      expect(bodies[2], {
        'op': 'reports',
        'rows': [
          {'ticker': 'ABCD', 'date': '2026-09-30', 'count': 900},
        ],
      });
      expect((bodies[3] as Map)['quotes'], [
        {
          'ticker': 'ABCD',
          'lastPrice': 1250.0,
          'changeValue': null,
          'changePercent': null,
          'volume': null,
          'marketCap': null,
        },
      ]);
      expect((bodies[4] as Map)['rows'], [
        {'ticker': 'ABCD', 'date': '2026-10-01', 'close': 1250.5},
      ]);
      expect(bodies[5], {'op': 'priceCoverage'});
      expect(bodies[6], {'op': 'priority'});
    });

    test('a 403 on sync is forbidden', () async {
      final rig = _rig({
        'POST /api/mobile/screener/sync': (403, {'error': 'forbidden'}),
      });
      await expectLater(
        rig.repo.known(),
        throwsA(
          isA<ScreenerException>().having(
            (e) => e.kind,
            'kind',
            ScreenerErrorKind.forbidden,
          ),
        ),
      );
    });
  });
}

final _m = DateTime(2026, 9);
