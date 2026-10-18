/// The on-device update: read Stockbit from the phone and push the rows to
/// Ghina (a port of the server's old ingest). Pure logic over injected ports,
/// so it runs the same in tests.
library;

import 'dart:math' as math;

import '../../core/clock.dart';
import '../entities/screener.dart';
import '../entities/stockbit.dart';
import '../repositories/screener_repository.dart';
import 'stockbit_session.dart';

const _profileConcurrency = 6;
const _priceConcurrency = 4;

/// Backfill only tickers with fewer closes than this…
const priceBackfillBelow = 100;

/// …and at most this many per run.
const priceBackfillPerRun = 150;

/// Today's date in WIB (UTC+7) as a calendar day.
DateTime todayWib(Clock clock) {
  final w = clock.now().toUtc().add(const Duration(hours: 7));
  return DateTime(w.year, w.month, w.day);
}

List<List<T>> chunked<T>(List<T> items, [int size = screenerPushChunk]) => [
  for (var i = 0; i < items.length; i += size)
    items.sublist(i, math.min(i + size, items.length)),
];

class ScreenerSync {
  ScreenerSync({
    required this.source,
    required this.repository,
    required this.clock,
  });

  final StockbitSource source;
  final ScreenerRepository repository;
  final Clock clock;

  /// Runs one update. [full] skips the "already current" shortcut. Throws a
  /// [StockbitException] (token / network) or a `ScreenerException` (push);
  /// a cancel returns the partial summary with `cancelled` set.
  Future<ScreenerSyncSummary> run({
    bool full = false,
    void Function(ScreenerProgress)? onProgress,
    ScreenerCancel? cancel,
  }) async {
    final started = DateTime.now();
    void report(ScreenerPhase p, [int done = 0, int total = 0]) =>
        onProgress?.call(ScreenerProgress(p, done: done, total: total));
    bool stop() => cancel?.isCancelled ?? false;
    ScreenerSyncSummary summary({
      DateTime? newest,
      int universe = 0,
      List<String> discovered = const [],
      int skipped = 0,
      int fetched = 0,
      int missing = 0,
      int reports = 0,
      int future = 0,
      int quotes = 0,
      int priceTickers = 0,
      int prices = 0,
    }) => ScreenerSyncSummary(
      newestReport: newest,
      universe: universe,
      discovered: discovered,
      skippedCurrent: skipped,
      fetched: fetched,
      missingProfiles: missing,
      reportsWritten: reports,
      rowsFutureDated: future,
      quotesWritten: quotes,
      pricesTickers: priceTickers,
      pricesWritten: prices,
      duration: DateTime.now().difference(started),
      cancelled: stop(),
    );

    report(ScreenerPhase.quotes);
    final known = (await repository.known()).toSet();
    final companies = await source.companies();
    final universe = {for (final c in companies) c.symbol};

    var quotesWritten = 0;
    report(ScreenerPhase.uploading);
    for (final part in chunked([for (final c in companies) c.toQuote()])) {
      quotesWritten += await repository.pushQuotes(part);
    }

    final discovered = (universe.difference(known)).toList()..sort();
    final tickers = ({...known, ...universe}).toList()..sort();
    final today = todayWib(clock);

    DateTime? newest;
    final skipped = <String>{};
    List<ShareholderPoint>? probed;
    String? probedTicker;
    var future = 0;

    if (!full && tickers.isNotEmpty && !stop()) {
      report(ScreenerPhase.probing);
      probedTicker = tickers.first;
      probed = await _safeProfile(probedTicker);
      final ok = _plausible(probed, today);
      if (ok.isNotEmpty) {
        newest = ok.map((p) => p.date).reduce((a, b) => a.isAfter(b) ? a : b);
        skipped.addAll(await repository.currentAt(newest));
        // The probe itself stays: it is current by definition, so it is
        // skipped like the others (its rows are already on the server).
      }
    }

    final todo = [
      for (final t in tickers)
        if (!skipped.contains(t)) t,
    ];
    final rows = <ScreenerReportRow>[];
    var fetched = 0;
    var missing = 0;
    report(ScreenerPhase.profiles, 0, todo.length);
    await _pool(todo, _profileConcurrency, stop, (t) async {
      final points = t == probedTicker && probed != null
          ? probed
          : await _safeProfile(t);
      fetched++;
      if (points == null || points.isEmpty) {
        missing++;
      } else {
        for (final p in points) {
          if (p.date.isAfter(today)) {
            future++;
            continue;
          }
          rows.add(ScreenerReportRow(ticker: t, date: p.date, count: p.count));
        }
      }
      report(ScreenerPhase.profiles, fetched, todo.length);
    });

    var reportsWritten = 0;
    if (rows.isNotEmpty) {
      report(ScreenerPhase.uploading);
      for (final part in chunked(rows)) {
        reportsWritten += await repository.pushReports(part);
      }
      newest ??= rows.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b);
    }

    // ---- daily closes of the current screener hits ----
    var priceTickers = 0;
    var pricesWritten = 0;
    if (!stop()) {
      final priority = await repository.priority();
      final coverage = await repository.priceCoverage();
      final targets = [
        for (final t in priority)
          if ((coverage[t]?.count ?? 0) < priceBackfillBelow) t,
      ].take(priceBackfillPerRun).toList();
      var done = 0;
      report(ScreenerPhase.prices, 0, targets.length);
      final pending = <ScreenerPriceRow>[];
      await _pool(targets, _priceConcurrency, stop, (t) async {
        try {
          final pts = await source.dailyPrices(t);
          if (pts.isNotEmpty) {
            priceTickers++;
            pending.addAll([
              for (final p in pts)
                ScreenerPriceRow(ticker: t, date: p.date, close: p.close),
            ]);
          }
        } on StockbitException catch (e) {
          if (!_skippable(e)) rethrow;
        }
        done++;
        report(ScreenerPhase.prices, done, targets.length);
        while (pending.length >= screenerPushChunk) {
          final part = pending.sublist(0, screenerPushChunk);
          pending.removeRange(0, screenerPushChunk);
          pricesWritten += await repository.pushPrices(part);
        }
      });
      for (final part in chunked(pending)) {
        pricesWritten += await repository.pushPrices(part);
      }
    }

    report(ScreenerPhase.done);
    return summary(
      newest: newest,
      universe: universe.length,
      discovered: discovered,
      skipped: skipped.length,
      fetched: fetched,
      missing: missing,
      reports: reportsWritten,
      future: future,
      quotes: quotesWritten,
      priceTickers: priceTickers,
      prices: pricesWritten,
    );
  }

  static bool _skippable(StockbitException e) =>
      e.kind == StockbitErrorKind.transient ||
      e.kind == StockbitErrorKind.notFound;

  /// A ticker that can't be read (404 / retries exhausted) is just missing;
  /// a rejected token or a blocked network stops the whole run.
  Future<List<ShareholderPoint>?> _safeProfile(String ticker) async {
    try {
      return await source.profile(ticker);
    } on StockbitException catch (e) {
      if (_skippable(e)) return null;
      rethrow;
    }
  }

  List<ShareholderPoint> _plausible(
    List<ShareholderPoint>? points,
    DateTime today,
  ) => [
    for (final p in points ?? const <ShareholderPoint>[])
      if (!p.date.isAfter(today)) p,
  ];
}

/// Runs [work] over [items] with at most [concurrency] in flight; stops
/// taking new items once [stop] says so. The first error aborts the pool.
Future<void> _pool<T>(
  List<T> items,
  int concurrency,
  bool Function() stop,
  Future<void> Function(T) work,
) async {
  var next = 0;
  Future<void> worker() async {
    while (!stop()) {
      final i = next++;
      if (i >= items.length) return;
      await work(items[i]);
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(concurrency, items.length); i++) worker(),
  ]);
}
