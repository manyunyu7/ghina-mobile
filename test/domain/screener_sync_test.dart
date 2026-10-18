// The on-device update (probe / skip / discovered / future-dated / chunking /
// price backfill) and the Stockbit session service, over fakes. Invented data.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'stockbit_parser_test.dart' show fakeJwt;

// 18 Oct 2026 12:00 WIB-ish; "today" in WIB is 18 Oct 2026.
final _now = DateTime.utc(2026, 10, 18, 5);
final _today = DateTime(2026, 10, 18);

ShareholderPoint _p(int y, int m, int d, int c) =>
    ShareholderPoint(date: DateTime(y, m, d), count: c);

class _Source implements StockbitSource {
  List<StockbitCompany> list = [];
  final profiles = <String, List<ShareholderPoint>?>{};
  final prices = <String, List<PricePoint>>{};
  final errors = <String, StockbitException>{};
  final profileCalls = <String>[];
  final priceCalls = <String>[];
  var inFlight = 0;
  var maxInFlight = 0;

  @override
  Future<List<StockbitCompany>> companies() async => list;

  @override
  Future<List<ShareholderPoint>?> profile(String t) async {
    profileCalls.add(t);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(Duration.zero);
    inFlight--;
    final e = errors[t];
    if (e != null) throw e;
    return profiles[t];
  }

  @override
  Future<List<PricePoint>> dailyPrices(String t) async {
    priceCalls.add(t);
    final e = errors['price:$t'];
    if (e != null) throw e;
    return prices[t] ?? const [];
  }
}

class _Repo implements ScreenerRepository {
  List<String> knownList = [];
  Set<String> current = {};
  List<String> priorityList = [];
  Map<String, PriceCoverage> coverage = {};
  DateTime? currentAtAsked;
  final reportBatches = <List<ScreenerReportRow>>[];
  final quoteBatches = <List<ScreenerQuoteRow>>[];
  final priceBatches = <List<ScreenerPriceRow>>[];

  @override
  Future<List<String>> known() async => knownList;
  @override
  Future<List<String>> currentAt(DateTime date) async {
    currentAtAsked = date;
    return current.toList();
  }

  @override
  Future<int> pushReports(List<ScreenerReportRow> rows) async {
    reportBatches.add(rows);
    return rows.length;
  }

  @override
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes) async {
    quoteBatches.add(quotes);
    return quotes.length;
  }

  @override
  Future<int> pushPrices(List<ScreenerPriceRow> rows) async {
    priceBatches.add(rows);
    return rows.length;
  }

  @override
  Future<Map<String, PriceCoverage>> priceCoverage() async => coverage;
  @override
  Future<List<String>> priority() async => priorityList;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

StockbitCompany _co(String s) => StockbitCompany(symbol: s, lastPrice: 100);

ScreenerSync _sync(_Source src, _Repo repo) =>
    ScreenerSync(source: src, repository: repo, clock: FixedClock(_now));

void main() {
  test('todayWib rolls over at 17:00 UTC', () {
    expect(todayWib(FixedClock(DateTime.utc(2026, 10, 18, 16, 59))), _today);
    expect(
      todayWib(FixedClock(DateTime.utc(2026, 10, 18, 17))),
      DateTime(2026, 10, 19),
    );
  });

  test('chunked splits at 1500 rows', () {
    final c = chunked(List.generate(3200, (i) => i));
    expect(c.map((e) => e.length), [1500, 1500, 200]);
    expect(chunked(<int>[]), isEmpty);
  });

  group('ScreenerSync', () {
    test(
      'probe, skip current tickers, discovered, pushes quotes + reports',
      () async {
        final src = _Source()
          ..list = [_co('AAAA'), _co('BBBB'), _co('NEWW')]
          ..profiles['AAAA'] = [_p(2026, 6, 30, 100), _p(2026, 9, 30, 90)]
          ..profiles['BBBB'] = [_p(2026, 9, 30, 50)]
          ..profiles['NEWW'] = [_p(2026, 9, 30, 10), _p(2026, 8, 31, 12)];
        final repo = _Repo()
          ..knownList = ['AAAA', 'BBBB']
          ..current = {'AAAA'};
        final progress = <ScreenerProgress>[];
        final s = await _sync(src, repo).run(onProgress: progress.add);

        // The probe is the first ticker; "current" is asked for its newest date.
        expect(repo.currentAtAsked, DateTime(2026, 9, 30));
        expect(s.newestReport, DateTime(2026, 9, 30));
        expect(s.discovered, ['NEWW']);
        expect(s.skippedCurrent, 1);
        // AAAA was probed once and not fetched again; the others were fetched.
        expect(src.profileCalls.where((t) => t == 'AAAA'), hasLength(1));
        expect(s.fetched, 2);
        expect(s.reportsWritten, 3);
        final rows = repo.reportBatches.expand((b) => b).toList();
        expect({for (final r in rows) r.ticker}, {'BBBB', 'NEWW'});
        expect(s.quotesWritten, 3);
        expect(repo.quoteBatches.single.map((q) => q.ticker), [
          'AAAA',
          'BBBB',
          'NEWW',
        ]);
        expect(s.universe, 3);
        expect(
          progress.any(
            (p) => p.phase == ScreenerPhase.profiles && p.total == 2,
          ),
          isTrue,
        );
        expect(progress.last.phase, ScreenerPhase.done);
      },
    );

    test('tickers = known ∪ company list, sorted', () async {
      final src = _Source()
        ..list = [_co('CCCC')]
        ..profiles['CCCC'] = [_p(2026, 9, 30, 1)]
        ..profiles['AAAA'] = [_p(2026, 9, 30, 1)];
      final repo = _Repo()..knownList = ['AAAA'];
      await _sync(src, repo).run(full: true);
      expect(src.profileCalls..sort(), ['AAAA', 'CCCC']);
    });

    test('full mode skips the probe and fetches everything', () async {
      final src = _Source()
        ..list = [_co('AAAA'), _co('BBBB')]
        ..profiles['AAAA'] = [_p(2026, 9, 30, 1)]
        ..profiles['BBBB'] = [_p(2026, 9, 30, 2)];
      final repo = _Repo()
        ..knownList = ['AAAA', 'BBBB']
        ..current = {'AAAA', 'BBBB'};
      final s = await _sync(src, repo).run(full: true);
      expect(repo.currentAtAsked, isNull);
      expect(s.fetched, 2);
      expect(s.skippedCurrent, 0);
    });

    test('future-dated rows are dropped and counted', () async {
      final src = _Source()
        ..list = [_co('AAAA')]
        ..profiles['AAAA'] = [
          _p(2026, 9, 30, 90),
          _p(2026, 10, 18, 91), // today (WIB): kept
          _p(2026, 10, 19, 92), // tomorrow: dropped
          _p(2027, 1, 31, 93),
        ];
      final repo = _Repo();
      final s = await _sync(src, repo).run();
      final rows = repo.reportBatches.expand((b) => b).toList();
      expect(rows.map((r) => r.count), [90, 91]);
      expect(s.rowsFutureDated, 2);
      // The probe's newest plausible date ignores the future rows.
      expect(repo.currentAtAsked, DateTime(2026, 10, 18));
    });

    test('rows are pushed in chunks of at most 1500', () async {
      final tickers = [
        for (var i = 0; i < 4; i++) 'T${String.fromCharCode(65 + i)}XX',
      ];
      final src = _Source()..list = [for (final t in tickers) _co(t)];
      for (final t in tickers) {
        src.profiles[t] = [
          for (var i = 0; i < 1000; i++)
            ShareholderPoint(
              date: DateTime(2020).add(Duration(days: i)),
              count: i + 1,
            ),
        ];
      }
      final repo = _Repo();
      final s = await _sync(src, repo).run(full: true);
      expect(s.reportsWritten, 4000);
      expect(repo.reportBatches.map((b) => b.length), [1500, 1500, 1000]);
    });

    test(
      'missing profiles are counted; transient/404 do not stop the run',
      () async {
        final src = _Source()
          ..list = [_co('AAAA'), _co('BBBB'), _co('CCCC')]
          ..profiles['AAAA'] = [_p(2026, 9, 30, 1)]
          ..profiles['BBBB'] = null
          ..errors['CCCC'] = const StockbitException(
            StockbitErrorKind.transient,
            'sibuk',
          );
        final repo = _Repo();
        final s = await _sync(src, repo).run(full: true);
        expect(s.fetched, 3);
        expect(s.missingProfiles, 2);
        expect(s.reportsWritten, 1);
      },
    );

    test('a rejected token or a blocked network aborts the run', () async {
      final src = _Source()
        ..list = [_co('AAAA')]
        ..errors['AAAA'] = const StockbitException(
          StockbitErrorKind.blocked,
          'blok',
        );
      await expectLater(
        _sync(src, _Repo()).run(full: true),
        throwsA(isA<StockbitException>()),
      );
    });

    test('profiles are fetched with at most 6 in flight', () async {
      final src = _Source()
        ..list = [
          for (var i = 0; i < 30; i++)
            _co(
              'K${String.fromCharCode(65 + i % 26)}${String.fromCharCode(65 + i ~/ 26)}X',
            ),
        ];
      for (final c in src.list) {
        src.profiles[c.symbol] = [_p(2026, 9, 30, 1)];
      }
      await _sync(src, _Repo()).run(full: true);
      expect(src.maxInFlight, inInclusiveRange(2, 6));
    });

    test('price backfill: priority tickers under 100 closes, max 150', () async {
      final src = _Source()..list = [_co('AAAA')];
      src.profiles['AAAA'] = [_p(2026, 9, 30, 1)];
      final pts = [
        for (var i = 0; i < 3; i++)
          PricePoint(date: DateTime(2026, 10, 1 + i), close: 100.0 + i),
      ];
      final priority = [
        for (var i = 0; i < 200; i++)
          'P${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}X',
      ];
      for (final t in priority) {
        src.prices[t] = pts;
      }
      final repo = _Repo()
        ..priorityList = ['FULL', ...priority]
        ..coverage = {'FULL': const PriceCoverage(count: 750)};
      src.prices['FULL'] = pts;
      final s = await _sync(src, repo).run(full: true);
      expect(src.priceCalls.contains('FULL'), isFalse);
      expect(src.priceCalls, hasLength(150));
      expect(s.pricesTickers, 150);
      expect(s.pricesWritten, 450);
      expect(repo.priceBatches.every((b) => b.length <= 1500), isTrue);
      expect(repo.priceBatches.expand((b) => b), hasLength(450));
    });

    test('price backfill: a 404 on one ticker is skipped', () async {
      final src = _Source()..list = [];
      src.prices['GOOD'] = [PricePoint(date: DateTime(2026, 10, 1), close: 5)];
      src.errors['price:BAD'] = const StockbitException(
        StockbitErrorKind.notFound,
        'x',
      );
      final repo = _Repo()..priorityList = ['BAD', 'GOOD'];
      final s = await _sync(src, repo).run(full: true);
      expect(s.pricesTickers, 1);
    });

    test('cancel stops early and reports it', () async {
      final src = _Source()
        ..list = [
          for (var i = 0; i < 40; i++)
            _co(
              'Q${String.fromCharCode(65 + i % 26)}${String.fromCharCode(65 + i ~/ 26)}X',
            ),
        ];
      for (final c in src.list) {
        src.profiles[c.symbol] = [_p(2026, 9, 30, 1)];
      }
      final cancel = ScreenerCancel();
      final s = await _sync(src, _Repo()).run(
        full: true,
        cancel: cancel,
        onProgress: (p) {
          if (p.phase == ScreenerPhase.profiles && p.done >= 5) cancel.cancel();
        },
      );
      expect(s.cancelled, isTrue);
      expect(s.fetched, lessThan(40));
    });
  });

  group('ScreenerProgress', () {
    test('text and fraction', () {
      const p = ScreenerProgress(ScreenerPhase.profiles, done: 5, total: 20);
      expect(p.text, 'Mengambil laporan pemegang 5/20');
      expect(p.fraction, 0.25);
      expect(const ScreenerProgress(ScreenerPhase.quotes).fraction, isNull);
    });
  });

  group('StockbitSessionService', () {
    late _Store store;
    late _Gateway gw;
    late FixedClock clock;
    StockbitSessionService make() =>
        StockbitSessionService(store: store, gateway: gw, clock: clock);

    setUp(() {
      store = _Store();
      gw = _Gateway();
      clock = FixedClock(DateTime(2026, 10, 18, 12));
    });

    final goodAccess = fakeJwt(DateTime(2026, 10, 19), tag: 'good');

    test('connect saves only after the company list worked', () async {
      final s = make();
      final t = await s.connect('Bearer $goodAccess');
      expect(t.access, goodAccess);
      expect(store.value!.access, goodAccess);
      expect(gw.companiesCalls, 1);
    });

    test('a rejected token is not saved', () async {
      gw.companiesError = const StockbitException(
        StockbitErrorKind.tokenRejected,
        'x',
      );
      await expectLater(
        make().connect('Bearer $goodAccess'),
        throwsA(isA<StockbitException>()),
      );
      expect(store.value, isNull);
    });

    test(
      'pending verification and junk are refused without any call',
      () async {
        for (final (text, kind) in [
          (
            '{"data":{"new_device":true}}',
            StockbitErrorKind.pendingVerification,
          ),
          ('halo', StockbitErrorKind.unrecognized),
          ('{"a":1}', StockbitErrorKind.unrecognized),
        ]) {
          await expectLater(
            make().connect(text),
            throwsA(
              isA<StockbitException>().having((e) => e.kind, 'kind', kind),
            ),
          );
        }
        expect(gw.companiesCalls, 0);
        expect(store.value, isNull);
      },
    );

    test('a refresh-only paste is renewed and saved right away', () async {
      gw.refreshResult = StockbitTokens(access: goodAccess, refresh: 'next-r');
      final t = await make().connect(
        '{"data":{"refresh":{"token":"${fakeJwt(DateTime(2027))}"}}}',
      );
      expect(t.refresh, 'next-r');
      expect(gw.refreshCalls, 1);
      expect(store.value!.refresh, 'next-r');
    });

    test(
      'accessToken renews within 30 minutes of expiry and saves the new pair',
      () async {
        store.value = StockbitTokens(
          access: fakeJwt(
            clock.now().add(const Duration(minutes: 10)),
            tag: 'old',
          ),
          refresh: 'r1',
        );
        gw.refreshResult = StockbitTokens(access: goodAccess, refresh: 'r2');
        final tok = await make().accessToken();
        expect(tok, goodAccess);
        expect(store.value!.refresh, 'r2');
        expect(gw.refreshCalls, 1);
      },
    );

    test('a fresh token is used as is', () async {
      store.value = StockbitTokens(access: goodAccess, refresh: 'r1');
      expect(await make().accessToken(), goodAccess);
      expect(gw.refreshCalls, 0);
    });

    test('renewal is single-flight', () async {
      store.value = StockbitTokens(
        access: fakeJwt(clock.now().subtract(const Duration(hours: 1))),
        refresh: 'r1',
      );
      gw.refreshResult = StockbitTokens(access: goodAccess, refresh: 'r2');
      gw.refreshDelay = const Duration(milliseconds: 20);
      final s = make();
      final all = await Future.wait([
        for (var i = 0; i < 6; i++) s.accessToken(),
      ]);
      expect(all.toSet(), {goodAccess});
      expect(gw.refreshCalls, 1);
    });

    test('not connected', () async {
      await expectLater(
        make().accessToken(),
        throwsA(
          isA<StockbitException>().having(
            (e) => e.kind,
            'kind',
            StockbitErrorKind.notConnected,
          ),
        ),
      );
    });

    test('disconnect clears the device session', () async {
      store.value = StockbitTokens(access: goodAccess);
      final s = make();
      await s.disconnect();
      expect(await s.current(), isNull);
    });
  });
}

class _Store implements StockbitSessionStore {
  StockbitTokens? value;
  @override
  Future<StockbitTokens?> read() async => value;
  @override
  Future<void> write(StockbitTokens tokens) async => value = tokens;
  @override
  Future<void> clear() async => value = null;
}

class _Gateway implements StockbitGateway {
  var companiesCalls = 0;
  var refreshCalls = 0;
  StockbitException? companiesError;
  StockbitTokens refreshResult = const StockbitTokens();
  Duration refreshDelay = Duration.zero;

  @override
  Future<List<StockbitCompany>> companies(String access) async {
    companiesCalls++;
    if (companiesError != null) throw companiesError!;
    return const [];
  }

  @override
  Future<StockbitTokens> refresh(String refreshToken) async {
    refreshCalls++;
    await Future<void>.delayed(refreshDelay);
    return refreshResult;
  }

  @override
  Future<List<ShareholderPoint>?> profile(String access, String ticker) async =>
      null;
  @override
  Future<List<PricePoint>> dailyPrices(String access, String ticker) async =>
      const [];
}
