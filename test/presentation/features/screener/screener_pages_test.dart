// Screener screens over a fake repository. All data is invented.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/screener_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/screener/pages/screener_page.dart';
import 'package:ghina/presentation/features/screener/pages/screener_ticker_page.dart';
import 'package:ghina/presentation/state/screener_access_provider.dart';
import 'package:ghina/presentation/state/session_controller.dart';

import '../../../domain/stockbit_parser_test.dart' show fakeJwt;

final _now = DateTime(2026, 10, 18, 12);

final _tokenExp = DateTime(2026, 10, 19, 12);
StockbitTokens _tokens({bool auto = false}) => StockbitTokens(
  access: fakeJwt(_tokenExp, tag: 'acc'),
  refresh: auto ? fakeJwt(DateTime(2026, 12, 1), tag: 'ref') : null,
);

ScreenerStatus _status({DateTime? updated}) => ScreenerStatus(
  stats: const ScreenerArchiveStats(rows: 12345, tickers: 800),
  anchor: DateTime(2026, 9, 30),
  reportsUpdatedAt: updated ?? _now.subtract(const Duration(hours: 5)),
  quotesFetchedAt: DateTime(2026, 10, 18, 9, 5),
);

class _Store implements StockbitSessionStore {
  _Store([this.value]);
  StockbitTokens? value;
  @override
  Future<StockbitTokens?> read() async => value;
  @override
  Future<void> write(StockbitTokens tokens) async => value = tokens;
  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements StockbitGateway {
  StockbitException? companiesError;
  Completer<void>? hold;
  List<PricePoint> prices = [];
  final calls = <String>[];

  @override
  Future<List<StockbitCompany>> companies(String access) async {
    calls.add('companies');
    if (companiesError != null) throw companiesError!;
    return const [StockbitCompany(symbol: 'BUDI', lastPrice: 1250)];
  }

  @override
  Future<List<ShareholderPoint>?> profile(String access, String ticker) async {
    calls.add('profile:$ticker');
    if (hold != null) await hold!.future;
    return [ShareholderPoint(date: DateTime(2026, 9, 30), count: 850)];
  }

  @override
  Future<List<PricePoint>> dailyPrices(String access, String ticker) async {
    calls.add('prices:$ticker');
    return prices;
  }

  @override
  Future<StockbitTokens> refresh(String refreshToken) async =>
      throw UnimplementedError();
}

ScreenerRow _row(String t, double pct, {List<double>? spark}) => ScreenerRow(
  ticker: t,
  firstDate: DateTime(2026, 4, 30),
  lastDate: DateTime(2026, 9, 30),
  firstCount: 1000,
  lastCount: 900,
  change: -100,
  changePercent: pct,
  declineStreak: 3,
  declineRatio: 0.75,
  points: 5,
  price: 1250,
  priceChangePercent: -1.5,
  marketCap: 2.5e12,
  spark: spark ?? const [1000, 980, 950, 900],
);

class _Repo implements ScreenerRepository {
  ScreenerStatus statusValue = _status();
  final pushedPrices = <ScreenerPriceRow>[];
  final pushedReports = <ScreenerReportRow>[];
  List<ScreenerRow> rows = [_row('BUDI', -10), _row('CONT', -25)];
  Object? screenError;
  Object? statusError;
  ScreenerTicker tickerValue = _ticker();
  var screenCalls = 0;

  @override
  Future<ScreenerResult> screen(ScreenerQuery query) async {
    screenCalls++;
    if (screenError != null) throw screenError!;
    return ScreenerResult(
      query: query,
      rows: rows,
      from: DateTime(2026, 4, 1),
      to: DateTime(2026, 10, 1),
      scanned: 800,
    );
  }

  @override
  Future<ScreenerStatus> status() async {
    if (statusError != null) throw statusError!;
    return statusValue;
  }

  @override
  Future<List<BreadthMonth>> breadth({int months = 24}) async {
    if (statusError != null) throw statusError!;
    return [
      BreadthMonth(
        month: DateTime(2026, 8),
        declining: 100,
        rising: 300,
        flat: 0,
      ),
      BreadthMonth(
        month: DateTime(2026, 9),
        declining: 300,
        rising: 200,
        flat: 0,
      ),
    ];
  }

  @override
  Future<ScreenerTicker> ticker(String ticker) async => tickerValue;

  @override
  Future<List<String>> known() async => ['BUDI'];

  @override
  Future<List<String>> currentAt(DateTime date) async => const [];

  @override
  Future<int> pushReports(List<ScreenerReportRow> rows) async {
    pushedReports.addAll(rows);
    return rows.length;
  }

  @override
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes) async => quotes.length;

  @override
  Future<int> pushPrices(List<ScreenerPriceRow> rows) async {
    pushedPrices.addAll(rows);
    return rows.length;
  }

  @override
  Future<Map<String, PriceCoverage>> priceCoverage() async => const {};

  @override
  Future<List<String>> priority() async => const [];
}

ScreenerTicker _ticker({ScreenerPrices prices = const ScreenerPrices()}) =>
    ScreenerTicker(
      ticker: 'BUDI',
      history: [
        for (var i = 0; i < 8; i++)
          ShareholderPoint(
            date: DateTime(2026, 3 + i ~/ 2 * 1, i.isEven ? 1 : 15),
            count: 1000 - i * 20,
          ),
      ],
      quote: ScreenerQuote(
        lastPrice: 1250,
        changePercent: 2.5,
        marketCap: 2.5e12,
        fetchedAt: DateTime(2026, 10, 18, 9, 5),
      ),
      prices: prices,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  _Repo repo, {
  _Store? store,
  _Gateway? gateway,
}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(_now)),
        currentUserProvider.overrideWithValue(null),
        screenerAccessStoreProvider.overrideWithValue(
          InMemoryScreenerAccessStore(),
        ),
        screenerRepositoryProvider.overrideWithValue(repo),
        stockbitSessionStoreProvider.overrideWithValue(
          store ?? _Store(_tokens()),
        ),
        stockbitGatewayProvider.overrideWithValue(gateway ?? _Gateway()),
      ],
      child: MaterialApp(
        theme: GhinaTheme.light(),
        darkTheme: GhinaTheme.dark(),
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('ScreenerPage', () {
    testWidgets('loaded: status card, summary, rows, charts', (t) async {
      await _pump(t, const ScreenerPage(), _Repo());
      expect(find.text('Data Stockbit'), findsOneWidget);
      expect(find.text('Terhubung'), findsOneWidget);
      expect(find.text('Laporan terbaru 30 Sep 2026'), findsOneWidget);
      expect(find.text('Terakhir diambil 5 jam lalu'), findsOneWidget);
      expect(
        find.textContaining('Arsip 12.345 laporan · 800 emiten'),
        findsOneWidget,
      );
      expect(find.text('Perbarui data'), findsOneWidget);
      expect(find.text('Hubungkan Stockbit'), findsNothing);
      expect(
        find.byKey(const ValueKey('screener-stale-warning')),
        findsNothing,
      );
      expect(find.text('Lolos'), findsOneWidget);
      expect(find.text('Dipindai'), findsOneWidget);
      expect(find.text('Jendela'), findsWidgets);
      expect(find.text('BUDI'), findsOneWidget);
      expect(find.text('CONT'), findsOneWidget);
      // Most negative first, signed with a real minus.
      expect(find.text('−25,0%'), findsOneWidget);
      expect(find.text('5 laporan'), findsNWidgets(2));
      expect(find.text('1.000 → 900'), findsNWidgets(2));
      expect(find.text('3×'), findsNWidgets(2));
      expect(find.text('-1,50%'), findsNothing);
      expect(find.text('−1,50%'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('screener-sparkline')),
        findsNWidgets(2),
      );
      expect(find.byKey(const ValueKey('breadth-chart')), findsOneWidget);
      expect(find.text('60% emiten pemegangnya turun'), findsOneWidget);
    });

    testWidgets('a short spark hides the sparkline', (t) async {
      final repo = _Repo()
        ..rows = [
          _row('BUDI', -10, spark: const [5]),
        ];
      await _pump(t, const ScreenerPage(), repo);
      expect(find.byKey(const ValueKey('screener-sparkline')), findsNothing);
    });

    testWidgets('search filters locally', (t) async {
      final repo = _Repo();
      await _pump(t, const ScreenerPage(), repo);
      final calls = repo.screenCalls;
      await t.enterText(find.byType(TextField).first, 'bud');
      await t.pump();
      expect(find.text('BUDI'), findsOneWidget);
      expect(find.text('CONT'), findsNothing);
      expect(repo.screenCalls, calls);
    });

    testWidgets('changing a control refetches', (t) async {
      final repo = _Repo();
      await _pump(t, const ScreenerPage(), repo);
      final calls = repo.screenCalls;
      await t.tap(find.text('12 bulan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(repo.screenCalls, calls + 1);
    });

    testWidgets('empty state', (t) async {
      await _pump(t, const ScreenerPage(), _Repo()..rows = []);
      expect(find.text('Belum ada yang lolos'), findsOneWidget);
    });

    testWidgets('error then retry', (t) async {
      final repo = _Repo()
        ..screenError = const ScreenerException(
          ScreenerErrorKind.network,
          'Lagi offline. Screener butuh internet, ya.',
        );
      await _pump(t, const ScreenerPage(), repo);
      expect(
        find.text('Lagi offline. Screener butuh internet, ya.'),
        findsOneWidget,
      );
      repo.screenError = null;
      await t.tap(find.text('COBA LAGI'));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('BUDI'), findsOneWidget);
    });

    testWidgets('403 shows the locked state and marks access', (t) async {
      const denied = ScreenerException(
        ScreenerErrorKind.forbidden,
        'Screener khusus untuk akun tertentu.',
      );
      final repo = _Repo()
        ..screenError = denied
        ..statusError = denied;
      await _pump(t, const ScreenerPage(), repo);
      expect(find.text('Screener belum terbuka'), findsOneWidget);
      final c = ProviderScope.containerOf(t.element(find.byType(ScreenerPage)));
      expect(c.read(screenerAccessProvider), ScreenerAccess.forbidden);
    });

    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.text('Hubungkan Stockbit'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('not connected: Hubungkan Stockbit opens a paste-only sheet', (
      t,
    ) async {
      await _pump(t, const ScreenerPage(), _Repo(), store: _Store());
      expect(find.text('Belum terhubung'), findsOneWidget);
      expect(find.text('Stockbit di HP ini: belum terhubung'), findsOneWidget);
      expect(find.text('Perbarui data'), findsNothing);
      await openSheet(t);
      expect(find.text('Buka di Ghina web'), findsNothing);
      expect(find.text('Tempel token'), findsNothing);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Hubungkan'), findsOneWidget);
    });

    testWidgets('paste: preview, unrecognized, pending, then success', (
      t,
    ) async {
      final store = _Store();
      final gw = _Gateway();
      await _pump(t, const ScreenerPage(), _Repo(), store: store, gateway: gw);
      await openSheet(t);
      final field = find.byType(TextField).last;

      await t.enterText(field, 'halo dunia');
      await t.pump();
      expect(
        find.text('Belum ada token yang bisa dikenali di teks ini.'),
        findsOneWidget,
      );
      await t.tap(find.text('Hubungkan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('nggak berisi token Stockbit'),
        findsOneWidget,
      );
      expect(store.value, isNull);

      await t.enterText(field, '{"data":{"new_device":true}}');
      await t.pump();
      expect(find.textContaining('Selesaikan OTP'), findsOneWidget);
      await t.tap(find.text('Hubungkan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Selesaikan OTP'), findsWidgets);
      expect(store.value, isNull);
      expect(gw.calls, isEmpty);

      await t.enterText(
        field,
        'Authorization: Bearer ${fakeJwt(_tokenExp, tag: 'paste')}',
      );
      await t.pump();
      expect(
        find.textContaining('Token akses terbaca, berlaku s/d'),
        findsOneWidget,
      );
      await t.tap(find.text('Hubungkan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(gw.calls, ['companies']);
      expect(store.value!.access, isNotNull);
      expect(find.text('Mantap! Stockbit sudah terhubung.'), findsOneWidget);
      expect(find.textContaining('Aktif di HP ini s/d'), findsOneWidget);
    });

    testWidgets('a token Stockbit rejects is not saved', (t) async {
      final store = _Store();
      final gw = _Gateway()
        ..companiesError = const StockbitException(
          StockbitErrorKind.tokenRejected,
          'Sesi Stockbit habis — tempel token baru.',
        );
      await _pump(t, const ScreenerPage(), _Repo(), store: store, gateway: gw);
      await openSheet(t);
      await t.enterText(
        find.byType(TextField).last,
        'Bearer ${fakeJwt(_tokenExp, tag: 'bad')}',
      );
      await t.pump();
      await t.tap(find.text('Hubungkan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(
        find.text('Sesi Stockbit habis — tempel token baru.'),
        findsOneWidget,
      );
      expect(store.value, isNull);
    });

    testWidgets('stale reports show the amber warning', (t) async {
      final repo = _Repo()
        ..statusValue = _status(
          updated: _now.subtract(const Duration(days: 20)),
        );
      await _pump(t, const ScreenerPage(), repo);
      expect(
        find.byKey(const ValueKey('screener-stale-warning')),
        findsOneWidget,
      );
      expect(
        find.textContaining('hanya menyimpan 6 bulan terakhir'),
        findsOneWidget,
      );
    });

    testWidgets('health pill and device line', (t) async {
      await _pump(
        t,
        const ScreenerPage(),
        _Repo(),
        store: _Store(_tokens(auto: true)),
      );
      expect(find.text('Terhubung · diperpanjang otomatis'), findsOneWidget);
      expect(
        find.textContaining('Stockbit di HP ini: diperpanjang otomatis s/d'),
        findsOneWidget,
      );
    });

    testWidgets('active session shows its expiry', (t) async {
      await _pump(t, const ScreenerPage(), _Repo());
      expect(find.text('Terhubung'), findsOneWidget);
      expect(
        find.textContaining('Stockbit di HP ini: aktif s/d 19 Okt 2026'),
        findsOneWidget,
      );
    });

    testWidgets('sync: live progress, cancel button, then the summary', (
      t,
    ) async {
      final repo = _Repo();
      final gw = _Gateway()..hold = Completer<void>();
      await _pump(t, const ScreenerPage(), repo, gateway: gw);
      final calls = repo.screenCalls;
      await t.tap(find.text('Perbarui data'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      // Held while fetching the (only) profile: progress is on screen.
      expect(find.byKey(const ValueKey('screener-sync-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('screener-sync-bar')), findsOneWidget);
      expect(find.text('Mengecek laporan terbaru…'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      // The main button is disabled while running.
      expect(find.text('Perbarui data'), findsNothing);
      gw.hold!.complete();
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Batal'), findsNothing);
      expect(find.textContaining('Selesai dalam'), findsOneWidget);
      expect(
        find.textContaining('1 laporan dikirim dari 1 emiten'),
        findsOneWidget,
      );
      expect(repo.pushedReports.single.count, 850);
      expect(repo.screenCalls, greaterThan(calls));
    });

    testWidgets('sync: a rejected token offers Hubungkan', (t) async {
      final gw = _Gateway()
        ..companiesError = const StockbitException(
          StockbitErrorKind.tokenRejected,
          'Sesi Stockbit habis — tempel token baru.',
        );
      await _pump(t, const ScreenerPage(), _Repo(), gateway: gw);
      await t.tap(find.text('Perbarui data'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text('Sesi Stockbit habis — tempel token baru.'),
        findsOneWidget,
      );
      expect(find.text('Hubungkan'), findsOneWidget);
    });

    testWidgets('sync: a blocked network is not called a token problem', (
      t,
    ) async {
      final gw = _Gateway()
        ..companiesError = const StockbitException(
          StockbitErrorKind.blocked,
          'Stockbit memblokir jaringan ini.',
        );
      await _pump(t, const ScreenerPage(), _Repo(), gateway: gw);
      await t.tap(find.text('Perbarui data'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Stockbit memblokir jaringan ini.'), findsOneWidget);
      expect(find.text('Hubungkan'), findsNothing);
    });

    testWidgets('overflow menu: full check and disconnect', (t) async {
      final store = _Store(_tokens());
      await _pump(t, const ScreenerPage(), _Repo(), store: store);
      await t.tap(find.byKey(const ValueKey('screener-menu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Periksa semua emiten'), findsOneWidget);
      await t.tap(find.text('Putuskan Stockbit'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('PUTUSKAN'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(store.value, isNull);
      expect(find.text('Hubungkan Stockbit'), findsOneWidget);
    });
  });

  group('ScreenerTickerPage', () {
    final okPrices = ScreenerPrices(
      status: ScreenerPricesStatus.ok,
      points: [
        for (var i = 0; i < 30; i++)
          PricePoint(
            date: DateTime(2026, 3, 1).add(Duration(days: i * 7)),
            close: 1000 + i * 10.0,
          ),
      ],
    );

    testWidgets('prices ok: combined chart, tiles, bars, history', (t) async {
      final repo = _Repo()..tickerValue = _ticker(prices: okPrices);
      await _pump(t, const ScreenerTickerPage(ticker: 'budi'), repo);
      expect(find.text('BUDI'), findsWidgets);
      expect(find.text('1.250'), findsOneWidget);
      expect(find.text('+2,50%'), findsOneWidget);
      expect(find.text('Pemegang · 3 bulan'), findsOneWidget);
      expect(find.text('Pemegang · 6 bulan'), findsOneWidget);
      expect(find.text('Pemegang · 1 tahun'), findsOneWidget);
      expect(find.text('Pemegang · 3 tahun'), findsOneWidget);
      expect(find.text('Harga vs jumlah pemegang'), findsOneWidget);
      expect(find.byKey(const ValueKey('holders-price-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('prices-note')), findsNothing);
      expect(find.text('Perubahan per laporan'), findsOneWidget);
      expect(find.byKey(const ValueKey('change-bars-chart')), findsOneWidget);
      expect(find.text('Riwayat laporan'), findsOneWidget);
      expect(find.text('Buka di Stockbit'), findsOneWidget);
      // Newest report first: 860 is the last count of the fixture.
      expect(find.text('860'), findsOneWidget);
    });

    testWidgets('prices not connected: holders alone + note + Hubungkan', (
      t,
    ) async {
      final repo = _Repo()
        ..tickerValue = _ticker(
          prices: const ScreenerPrices(
            status: ScreenerPricesStatus.notConnected,
            message: 'Hubungkan Stockbit untuk melihat grafik harga.',
          ),
        );
      await _pump(
        t,
        const ScreenerTickerPage(ticker: 'BUDI'),
        repo,
        store: _Store(),
      );
      expect(find.text('Jumlah pemegang'), findsOneWidget);
      expect(find.text('Harga vs jumlah pemegang'), findsNothing);
      expect(find.byKey(const ValueKey('holders-price-chart')), findsOneWidget);
      expect(
        find.text('Hubungkan Stockbit untuk melihat grafik harga.'),
        findsOneWidget,
      );
      expect(find.text('Hubungkan'), findsOneWidget);
      await t.tap(find.text('Hubungkan'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Tempel di sini'), findsOneWidget);
      expect(find.text('Buka di Ghina web'), findsNothing);
    });

    testWidgets(
      'server prices missing + local session: read on the phone and push',
      (t) async {
        final repo = _Repo()
          ..tickerValue = _ticker(
            prices: const ScreenerPrices(
              status: ScreenerPricesStatus.notConnected,
              message: 'Hubungkan Stockbit untuk melihat grafik harga.',
            ),
          );
        final gw = _Gateway()..prices = okPrices.points;
        await _pump(
          t,
          const ScreenerTickerPage(ticker: 'BUDI'),
          repo,
          gateway: gw,
        );
        expect(gw.calls, ['prices:BUDI']);
        expect(find.text('Harga vs jumlah pemegang'), findsOneWidget);
        expect(find.byKey(const ValueKey('prices-note')), findsNothing);
        expect(repo.pushedPrices, hasLength(30));
        expect(repo.pushedPrices.first.ticker, 'BUDI');
      },
    );

    testWidgets('server prices ok: nothing is read from Stockbit', (t) async {
      final repo = _Repo()..tickerValue = _ticker(prices: okPrices);
      final gw = _Gateway();
      await _pump(
        t,
        const ScreenerTickerPage(ticker: 'BUDI'),
        repo,
        gateway: gw,
      );
      expect(gw.calls, isEmpty);
      expect(repo.pushedPrices, isEmpty);
    });

    testWidgets('local fetch fails: note without the connect action', (
      t,
    ) async {
      final repo = _Repo()
        ..tickerValue = _ticker(
          prices: const ScreenerPrices(status: ScreenerPricesStatus.error),
        );
      await _pump(t, const ScreenerTickerPage(ticker: 'BUDI'), repo);
      expect(
        find.textContaining('belum bisa dimuat dari Stockbit'),
        findsOneWidget,
      );
      expect(find.text('Hubungkan'), findsNothing);
    });

    testWidgets('range selector switches without errors', (t) async {
      final repo = _Repo()..tickerValue = _ticker(prices: okPrices);
      await _pump(t, const ScreenerTickerPage(ticker: 'BUDI'), repo);
      await t.tap(find.text('Semua'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('3 thn'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('holders-price-chart')), findsOneWidget);
    });

    testWidgets('404 shows a retry state', (t) async {
      await _pump(t, const ScreenerTickerPage(ticker: 'NOPE'), _NotFound());
      expect(find.text('Emiten ini nggak ketemu.'), findsOneWidget);
    });
  });
}

class _NotFound extends _Repo {
  @override
  Future<ScreenerTicker> ticker(String ticker) async =>
      throw const ScreenerException(
        ScreenerErrorKind.notFound,
        'Emiten ini nggak ketemu.',
        code: 'not_found',
      );
}
