/// JSON of the Screener mobile API, parsed leniently: numbers may be int or
/// double, nullable fields may be null or missing, an unusable item is
/// skipped.
library;

import '../../domain/entities/screener.dart';
import 'wire.dart' show Json;

Json _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Object?> _list(Object? v) => v is List ? v : const [];
int _int(Object? v) => v is num && v.isFinite ? v.round() : 0;
double _double(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;
double? _doubleN(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;

/// `yyyy-mm-dd` (or a full ISO instant) → a local calendar day.
DateTime? _day(Object? v) {
  if (v is! String || v.length < 10) return null;
  final d = DateTime.tryParse(v.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime? _instant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

ScreenerQuery screenerParamsFromWire(Object? v, ScreenerQuery fallback) {
  final j = _map(v);
  return ScreenerQuery(
    months: j['months'] is num ? _int(j['months']) : fallback.months,
    mode: j['mode'] == null ? fallback.mode : ScreenerMode.fromWire(j['mode']),
    threshold: j['threshold'] is num
        ? _double(j['threshold'])
        : fallback.threshold,
    minPoints: j['minPoints'] is num
        ? _int(j['minPoints'])
        : fallback.minPoints,
  );
}

ScreenerRow? screenerRowFromWire(Object? v) {
  final j = _map(v);
  final ticker = _strN(j['ticker']);
  if (ticker == null) return null;
  return ScreenerRow(
    ticker: ticker,
    firstDate: _day(j['firstDate']),
    lastDate: _day(j['lastDate']),
    firstCount: _int(j['firstCount']),
    lastCount: _int(j['lastCount']),
    change: _int(j['change']),
    changePercent: _double(j['changePercent']),
    declineStreak: _int(j['declineStreak']),
    declineRatio: _double(j['declineRatio']).clamp(0.0, 1.0),
    points: _int(j['points']),
    price: _doubleN(j['price']),
    priceChangePercent: _doubleN(j['priceChangePercent']),
    volume: _doubleN(j['volume']),
    marketCap: _doubleN(j['marketCap']),
    spark: [
      for (final s in _list(j['spark']))
        if (s is num && s.isFinite) s.toDouble(),
    ],
  );
}

ScreenerResult screenerResultFromWire(Object? v, ScreenerQuery asked) {
  final j = _map(v);
  return ScreenerResult(
    query: screenerParamsFromWire(j['params'], asked),
    rows: [for (final r in _list(j['results'])) ?screenerRowFromWire(r)],
    from: _day(j['from']),
    to: _day(j['to']),
    scanned: _int(j['scanned']),
  );
}

ScreenerStatus screenerStatusFromWire(Object? v) {
  final j = _map(v);
  final s = _map(j['stats']);
  return ScreenerStatus(
    stats: ScreenerArchiveStats(
      rows: _int(s['rows']),
      tickers: _int(s['tickers']),
      oldest: _day(s['oldest']),
    ),
    anchor: _day(j['anchor']),
    reportsUpdatedAt: _instant(j['reportsUpdatedAt']),
    quotesFetchedAt: _instant(j['quotesFetchedAt']),
  );
}

ScreenerQuote? screenerQuoteFromWire(Object? v) {
  if (v is! Map) return null;
  final j = _map(v);
  return ScreenerQuote(
    lastPrice: _doubleN(j['lastPrice']),
    changeValue: _doubleN(j['changeValue']),
    changePercent: _doubleN(j['changePercent']),
    volume: _doubleN(j['volume']),
    marketCap: _doubleN(j['marketCap']),
    fetchedAt: _instant(j['fetchedAt']),
  );
}

ScreenerTicker screenerTickerFromWire(Object? v, String requested) {
  final j = _map(v);
  final points = <ShareholderPoint>[];
  for (final h in _list(j['history'])) {
    final m = _map(h);
    final date = _day(m['date']);
    if (date == null || m['count'] is! num) continue;
    points.add(ShareholderPoint(date: date, count: _int(m['count'])));
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return ScreenerTicker(
    prices: screenerPricesFromWire(j['prices']),
    ticker: _strN(j['ticker']) ?? requested,
    history: points,
    quote: screenerQuoteFromWire(j['quote']),
  );
}

/// `prices` of the ticker answer; a missing / unknown block is an `error`
/// state without data.
ScreenerPrices screenerPricesFromWire(Object? v) {
  if (v is! Map) return const ScreenerPrices();
  final j = _map(v);
  final status = switch (j['status']) {
    'ok' => ScreenerPricesStatus.ok,
    'not_connected' => ScreenerPricesStatus.notConnected,
    _ => ScreenerPricesStatus.error,
  };
  final points = <PricePoint>[];
  if (status == ScreenerPricesStatus.ok) {
    for (final p in _list(j['points'])) {
      final m = _map(p);
      final date = _day(m['date']);
      final close = _doubleN(m['close']);
      if (date != null && close != null) {
        points.add(PricePoint(date: date, close: close));
      }
    }
    points.sort((a, b) => a.date.compareTo(b.date));
  }
  return ScreenerPrices(
    status: status,
    points: points,
    message: _strN(j['message']),
  );
}

/// `{months:[{month:"yyyy-mm", declining, rising, flat}]}`, oldest first.
List<BreadthMonth> screenerBreadthFromWire(Object? v) {
  final out = <BreadthMonth>[];
  for (final m in _list(_map(v)['months'])) {
    final j = _map(m);
    final s = j['month'];
    final d = s is String && s.length >= 7
        ? DateTime.tryParse('${s.substring(0, 7)}-01')
        : null;
    if (d == null) continue;
    out.add(
      BreadthMonth(
        month: DateTime(d.year, d.month),
        declining: _int(j['declining']),
        rising: _int(j['rising']),
        flat: _int(j['flat']),
      ),
    );
  }
  out.sort((a, b) => a.month.compareTo(b.month));
  return out;
}

/// `{coverage: {T: {first, last, count}}}`.
Map<String, PriceCoverage> screenerCoverageFromWire(Object? v) {
  final out = <String, PriceCoverage>{};
  _map(_map(v)['coverage']).forEach((t, c) {
    final j = _map(c);
    out[t] = PriceCoverage(
      first: _day(j['first']),
      last: _day(j['last']),
      count: _int(j['count']),
    );
  });
  return out;
}
