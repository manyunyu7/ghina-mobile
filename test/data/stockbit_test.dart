// Stockbit on the phone: formatted-number / date parsing, error
// classification and the gateway over a fake Dio adapter. Invented data.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/stockbit_api.dart';
import 'package:ghina/data/models/stockbit_wire.dart';
import 'package:ghina/domain/entities/entities.dart';

import '../domain/stockbit_parser_test.dart' show fakeJwt;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final (int, String) Function(RequestOptions o, int attempt) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final (status, body) = handler(o, requests.length);
    return ResponseBody.fromString(body, status);
  }

  @override
  void close({bool force = false}) {}
}

({DioStockbitGateway gw, _Adapter adapter, List<Duration> slept}) _rig(
  (int, String) Function(RequestOptions o, int attempt) handler,
) {
  final adapter = _Adapter(handler);
  final dio = Dio(BaseOptions(baseUrl: DioStockbitGateway.baseUrl))
    ..httpClientAdapter = adapter;
  final slept = <Duration>[];
  return (
    gw: DioStockbitGateway(dio: dio, sleep: (d) async => slept.add(d)),
    adapter: adapter,
    slept: slept,
  );
}

void main() {
  group('numbers and dates', () {
    test('formatted numbers', () {
      expect(stockbitNumber('1,250'), 1250);
      expect(stockbitNumber('+25'), 25);
      expect(stockbitNumber('-0.27'), -0.27);
      expect(stockbitNumber('1.5%'), 1.5);
      expect(stockbitNumber(12), 12);
      expect(stockbitNumber(''), isNull);
      expect(stockbitNumber('n/a'), isNull);
      expect(stockbitNumber(null), isNull);
    });

    test('English and Indonesian month names', () {
      expect(stockbitDate('31 Jul 2026'), DateTime(2026, 7, 31));
      expect(stockbitDate('1 Mei 2026'), DateTime(2026, 5, 1));
      expect(stockbitDate('15 Agu 2026'), DateTime(2026, 8, 15));
      expect(stockbitDate('15 Ags 2026'), DateTime(2026, 8, 15));
      expect(stockbitDate('3 Okt 2026'), DateTime(2026, 10, 3));
      expect(stockbitDate('25 Des 2026'), DateTime(2026, 12, 25));
      expect(stockbitDate('25 Dec 2026'), DateTime(2026, 12, 25));
      expect(stockbitDate('30 September 2026'), DateTime(2026, 9, 30));
    });

    test('impossible dates are rejected', () {
      expect(stockbitDate('31 Feb 2026'), isNull);
      expect(stockbitDate('32 Jan 2026'), isNull);
      expect(stockbitDate('29 Feb 2027'), isNull);
      expect(stockbitDate('1 Foo 2026'), isNull);
      expect(stockbitDate('2026-01-01'), isNull);
      expect(stockbitDate(null), isNull);
    });
  });

  group('responses', () {
    test('companies: formatted strings, bad symbols, suspended', () {
      final c = stockbitCompaniesFromWire({
        'data': [
          {
            'symbol': 'ABCD',
            'last': '1,250',
            'change': '+25',
            'percent': '2.04',
            'volume': '12,345,600',
            'marketcap': '2,500,000,000,000',
          },
          {'symbol': 'SUSP', 'last': '0', 'change': '0', 'percent': '0'},
          {'symbol': 'abcd', 'last': '1'},
          {'symbol': 'A', 'last': '1'},
          {'symbol': 'TOOLONGSYMBOL', 'last': '1'},
          {'symbol': 'ABCD', 'last': '9'},
          {'symbol': 'NONE', 'last': null},
          'junk',
        ],
      });
      expect([for (final x in c) x.symbol], ['ABCD', 'SUSP', 'NONE']);
      expect(c[0].lastPrice, 1250);
      expect(c[0].changeValue, 25);
      expect(c[0].changePercent, 2.04);
      expect(c[0].volume, 12345600);
      expect(c[0].marketCap, 2.5e12);
      expect(c[1].lastPrice, isNull);
      expect(c[2].lastPrice, isNull);
      expect(c[0].toQuote().ticker, 'ABCD');
      expect(stockbitCompaniesFromWire(null), isEmpty);
    });

    test('profile: shareholder numbers', () {
      final p = stockbitProfileFromWire({
        'data': {
          'shareholder_numbers': [
            {'shareholder_date': '31 Jul 2026', 'total_share': '61,711'},
            {'shareholder_date': '31 Mei 2026', 'total_share': '60,000'},
            {'shareholder_date': '31 Feb 2026', 'total_share': '1'},
            {'shareholder_date': '30 Jun 2026', 'total_share': 'x'},
          ],
        },
      });
      expect(p.map((e) => e.count), [61711, 60000]);
      expect(p.first.date, DateTime(2026, 7, 31));
      expect(stockbitProfileFromWire({'data': {}}), isEmpty);
    });

    test('prices: sorted, suspended dropped', () {
      final p = stockbitPricesFromWire({
        'data': {
          'prices': [
            {'formatted_date': '2026-10-02', 'value': '9,150'},
            {'formatted_date': '2026-10-01', 'value': '9,100'},
            {'formatted_date': '2026-09-30', 'value': ''},
            {'formatted_date': '2026-02-31', 'value': '1'},
            {'formatted_date': 'x', 'value': '1'},
          ],
        },
      });
      expect(p.map((e) => e.close), [9100, 9150]);
      expect(p.first.date, DateTime(2026, 10, 1));
    });
  });

  group('error classification', () {
    test('401 and a JSON 403 are a rejected token', () {
      expect(
        classifyStockbitResponse(401, '').kind,
        StockbitErrorKind.tokenRejected,
      );
      expect(
        classifyStockbitResponse(403, '{"message":"forbidden"}').kind,
        StockbitErrorKind.tokenRejected,
      );
      expect(
        classifyStockbitResponse(403, {'message': 'x'}).kind,
        StockbitErrorKind.tokenRejected,
      );
      expect(
        classifyStockbitResponse(401, '').message,
        'Sesi Stockbit habis — tempel token baru.',
      );
    });

    test('a 403 with HTML is the network being blocked', () {
      final e = classifyStockbitResponse(
        403,
        '<!DOCTYPE html><html><title>Just a moment...</title></html>',
      );
      expect(e.kind, StockbitErrorKind.blocked);
      expect(e.message, contains('memblokir'));
      expect(e.message, isNot(contains('token')));
      expect(classifyStockbitResponse(403, '').kind, StockbitErrorKind.blocked);
    });

    test('404, 429, 5xx, other', () {
      expect(
        classifyStockbitResponse(404, '').kind,
        StockbitErrorKind.notFound,
      );
      expect(
        classifyStockbitResponse(429, '').kind,
        StockbitErrorKind.transient,
      );
      expect(
        classifyStockbitResponse(503, '').kind,
        StockbitErrorKind.transient,
      );
      expect(classifyStockbitResponse(418, '').kind, StockbitErrorKind.unknown);
    });
  });

  group('gateway', () {
    test('sends the bearer token and no browser-imitating headers', () async {
      final rig = _rig(
        (o, _) => (
          200,
          jsonEncode({
            'data': [
              {'symbol': 'ABCD', 'last': '100'},
            ],
          }),
        ),
      );
      final c = await rig.gw.companies('acc-token');
      expect(c.single.symbol, 'ABCD');
      final o = rig.adapter.requests.single;
      expect(
        o.uri.toString(),
        'https://exodus.stockbit.com/emitten/v3/sector/88/subsector/467/company',
      );
      expect(o.headers['Authorization'], 'Bearer acc-token');
      final names = o.headers.keys.map((k) => k.toLowerCase()).toSet();
      for (final h in ['user-agent', 'origin', 'referer', 'sec-fetch-mode']) {
        expect(names, isNot(contains(h)));
      }
    });

    test('profile: 404 means no profile', () async {
      final rig = _rig((o, _) => (404, '{"message":"nope"}'));
      expect(await rig.gw.profile('t', 'ABCD'), isNull);
    });

    test('429 then success retries with 0.5s / 1s / 2s backoff', () async {
      final rig = _rig(
        (o, attempt) => attempt < 4
            ? (429, 'slow down')
            : (
                200,
                jsonEncode({
                  'data': {
                    'shareholder_numbers': [
                      {'shareholder_date': '31 Jul 2026', 'total_share': '5'},
                    ],
                  },
                }),
              ),
      );
      final p = await rig.gw.profile('t', 'ABCD');
      expect(p!.single.count, 5);
      expect(rig.slept, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(rig.adapter.requests, hasLength(4));
    });

    test('gives up after the retries', () async {
      final rig = _rig((o, _) => (503, 'down'));
      await expectLater(
        rig.gw.profile('t', 'ABCD'),
        throwsA(
          isA<StockbitException>().having(
            (e) => e.kind,
            'kind',
            StockbitErrorKind.transient,
          ),
        ),
      );
      expect(rig.adapter.requests, hasLength(4));
    });

    test('401 and 403 are not retried', () async {
      final rig = _rig((o, _) => (403, '<html>blocked</html>'));
      await expectLater(
        rig.gw.dailyPrices('t', 'ABCD'),
        throwsA(
          isA<StockbitException>().having(
            (e) => e.kind,
            'kind',
            StockbitErrorKind.blocked,
          ),
        ),
      );
      expect(rig.adapter.requests, hasLength(1));
      expect(rig.slept, isEmpty);
    });

    test('daily prices ask for 3 years', () async {
      final rig = _rig(
        (o, _) => (
          200,
          jsonEncode({
            'data': {
              'prices': [
                {'formatted_date': '2026-10-01', 'value': '9,100'},
              ],
            },
          }),
        ),
      );
      final p = await rig.gw.dailyPrices('t', 'ABCD');
      expect(p.single.close, 9100);
      expect(rig.adapter.requests.single.uri.path, '/charts/ABCD/daily');
      expect(rig.adapter.requests.single.uri.queryParameters, {
        'timeframe': '3y',
      });
    });

    test(
      'refresh: POST with the refresh token as bearer, returns the pair',
      () async {
        final access = fakeJwt(DateTime(2027));
        final rig = _rig(
          (o, _) => (
            200,
            jsonEncode({
              'data': {
                'access': {'token': access},
                'refresh': {'token': 'next-refresh-token'},
              },
            }),
          ),
        );
        final t = await rig.gw.refresh('old-refresh');
        expect(t.access, access);
        expect(t.refresh, 'next-refresh-token');
        final o = rig.adapter.requests.single;
        expect(o.method, 'POST');
        expect(o.path, '/login/refresh');
        expect(o.headers['Authorization'], 'Bearer old-refresh');
      },
    );

    test('refresh without a usable pair is a rejected token', () async {
      final rig = _rig((o, _) => (200, '{"data":{}}'));
      await expectLater(
        rig.gw.refresh('r'),
        throwsA(
          isA<StockbitException>().having(
            (e) => e.kind,
            'kind',
            StockbitErrorKind.tokenRejected,
          ),
        ),
      );
    });

    test('offline', () async {
      final adapter = _Adapter(
        (o, _) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      final dio = Dio(BaseOptions(baseUrl: DioStockbitGateway.baseUrl))
        ..httpClientAdapter = adapter;
      final gw = DioStockbitGateway(dio: dio, sleep: (_) async {});
      await expectLater(
        gw.companies('t'),
        throwsA(
          isA<StockbitException>().having(
            (e) => e.kind,
            'kind',
            StockbitErrorKind.network,
          ),
        ),
      );
    });
  });
}
