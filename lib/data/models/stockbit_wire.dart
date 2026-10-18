/// JSON of Stockbit (`exodus.stockbit.com`), parsed leniently. Stockbit sends
/// numbers as formatted strings ("1,250", "+25", "-0.27").
library;

import 'dart:convert';

import '../../domain/entities/screener.dart';
import '../../domain/entities/stockbit.dart';
import 'wire.dart' show Json;

Json _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Object?> _list(Object? v) => v is List ? v : const [];

/// "1,250" / "+25" / "-0.27%" / 1250 → number; null when unreadable.
double? stockbitNumber(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is! String) return null;
  final s = v
      .trim()
      .replaceAll(',', '')
      .replaceAll('%', '')
      .replaceAll('+', '');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

final _symbol = RegExp(r'^[A-Z]{2,10}$');

/// `data: [{symbol, last, change, percent, volume, marketcap}]`. Symbols that
/// aren't 2–10 capital letters are dropped; a price of 0 (suspended) → null.
List<StockbitCompany> stockbitCompaniesFromWire(Object? body) {
  final out = <StockbitCompany>[];
  final seen = <String>{};
  for (final c in _list(_map(body)['data'])) {
    final j = _map(c);
    final symbol = j['symbol'];
    if (symbol is! String || !_symbol.hasMatch(symbol) || !seen.add(symbol)) {
      continue;
    }
    final last = stockbitNumber(j['last']);
    out.add(
      StockbitCompany(
        symbol: symbol,
        lastPrice: last == null || last == 0 ? null : last,
        changeValue: stockbitNumber(j['change']),
        changePercent: stockbitNumber(j['percent']),
        volume: stockbitNumber(j['volume']),
        marketCap: stockbitNumber(j['marketcap']),
      ),
    );
  }
  return out;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'mei': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'agu': 8,
  'ags': 8,
  'sep': 9,
  'oct': 10,
  'okt': 10,
  'nov': 11,
  'dec': 12,
  'des': 12,
};

/// "31 Jul 2026" (English or Indonesian month names) → a calendar day;
/// impossible dates ("31 Feb 2026") → null.
DateTime? stockbitDate(Object? v) {
  if (v is! String) return null;
  final m = RegExp(
    r'^\s*(\d{1,2})\s+([A-Za-z]{3,})\.?\s+(\d{4})\s*$',
  ).firstMatch(v);
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = _months[m.group(2)!.toLowerCase().substring(0, 3)];
  final year = int.parse(m.group(3)!);
  if (month == null || year < 1990 || year > 2200) return null;
  final d = DateTime(year, month, day);
  return d.month == month && d.day == day ? d : null;
}

/// `data.shareholder_numbers: [{shareholder_date, total_share}]`.
List<ShareholderPoint> stockbitProfileFromWire(Object? body) {
  final out = <ShareholderPoint>[];
  for (final r in _list(_map(_map(body)['data'])['shareholder_numbers'])) {
    final j = _map(r);
    final date = stockbitDate(j['shareholder_date']);
    final count = stockbitNumber(j['total_share']);
    if (date == null || count == null || count < 0) continue;
    out.add(ShareholderPoint(date: date, count: count.round()));
  }
  return out;
}

/// `data.prices: [{formatted_date: "yyyy-mm-dd", value: "9,100"}]`, oldest
/// first; an empty value (suspended) is dropped.
List<PricePoint> stockbitPricesFromWire(Object? body) {
  final out = <PricePoint>[];
  for (final r in _list(_map(_map(body)['data'])['prices'])) {
    final j = _map(r);
    final ds = j['formatted_date'];
    final close = stockbitNumber(j['value']);
    if (ds is! String || close == null || close <= 0) continue;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ds.trim());
    if (m == null) continue;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final date = DateTime(y, mo, d);
    if (date.month != mo || date.day != d) continue;
    out.add(PricePoint(date: date, close: close));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Classifies a non-success answer of Stockbit. A 403 with a JSON body is a
/// refused token; a 403 with HTML is the network being blocked.
StockbitException classifyStockbitResponse(int? status, Object? body) {
  switch (status) {
    case 401:
      return const StockbitException(
        StockbitErrorKind.tokenRejected,
        'Sesi Stockbit habis — tempel token baru.',
        status: 401,
      );
    case 403:
      if (_isJson(body)) {
        return const StockbitException(
          StockbitErrorKind.tokenRejected,
          'Sesi Stockbit habis — tempel token baru.',
          status: 403,
        );
      }
      return const StockbitException(
        StockbitErrorKind.blocked,
        'Stockbit memblokir jaringan ini. Coba pindah jaringan (Wi-Fi atau '
        'data seluler), lalu ulangi.',
        status: 403,
      );
    case 404:
      return const StockbitException(
        StockbitErrorKind.notFound,
        'Data ini nggak ada di Stockbit.',
        status: 404,
      );
  }
  if (status == 429 || (status != null && status >= 500)) {
    return StockbitException(
      StockbitErrorKind.transient,
      'Stockbit lagi sibuk ($status). Coba lagi sebentar lagi.',
      status: status,
    );
  }
  return StockbitException(
    StockbitErrorKind.unknown,
    'Stockbit menjawab dengan kode ${status ?? '?'}.',
    status: status,
  );
}

bool _isJson(Object? body) {
  if (body is Map || body is List) return true;
  if (body is! String) return false;
  final t = body.trimLeft();
  if (!(t.startsWith('{') || t.startsWith('['))) return false;
  try {
    jsonDecode(t);
    return true;
  } catch (_) {
    return false;
  }
}
