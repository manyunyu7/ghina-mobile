/// JSON wire format of `habits`, `habitLogs`, `assets` and `assetTrades`
/// (`docs/mobile-sync.md`, `docs/habits.md`, `docs/investments.md`) and of the
/// prices endpoint. JSON fields travel as JSON values.
///
/// `*ToWire` builds the push `data` (full row minus id/createdAt/updatedAt);
/// `*FromWire` parses a pulled row leniently (a missing/invalid value falls
/// back to the model default; unknown enum values → null = row ignored).
library;

import 'dart:convert';

import '../../domain/entities/entities.dart';
import 'wire.dart' show Json, isoUtc;

// ---------------------------------------------------------------- to wire

Object _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v;

Json habitToWire(Habit h) => {
  'name': h.name,
  'emoji': h.emoji,
  'color': h.color,
  'kind': h.kind.wire,
  'schedule': h.schedule.toJson(),
  'target': h.target.toJson(),
  'reminders': h.reminders,
  'private': h.isPrivate,
  'why': h.why,
  'startDate': h.startDate,
  'archived': h.archived,
  'sortOrder': h.sortOrder,
};

Json habitLogToWire(HabitLog l) => {
  'habitId': l.habitId,
  'date': l.date,
  'type': l.type.wire,
  'value': l.value == null ? null : _num(l.value!),
  'note': l.note,
  'triggers': l.triggers,
  'at': l.at == null ? null : isoUtc(l.at!),
};

Json assetToWire(Asset a) => {
  'kind': a.kind.wire,
  'symbol': a.symbol,
  'name': a.name,
  'currency': a.currency,
  'priceMode': a.priceMode.wire,
  'manualPrice': a.manualPrice,
  'manualPriceAt': a.manualPriceAt == null ? null : isoUtc(a.manualPriceAt!),
  'unit': a.unit,
  'walletId': a.walletId,
  'archived': a.archived,
  'sortOrder': a.sortOrder,
};

Json assetTradeToWire(AssetTrade t) => {
  'assetId': t.assetId,
  'type': t.type.wire,
  'date': isoUtc(t.date),
  'quantity': t.quantity,
  'price': t.price,
  'fee': t.fee,
  'amount': t.amount,
  'ratio': t.ratio,
  'note': t.note,
  'cashTransactionId': t.cashTransactionId,
};

// ---------------------------------------------------------------- from wire

Object? _jsonValue(Object? v) {
  if (v is String) {
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  return v;
}

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
double? _numN(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int? _intN(Object? v) => v is num && v.isFinite ? v.round() : null;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

DateTime _created(Json j) => _date(j['createdAt']);
DateTime _updated(Json j) =>
    j['updatedAt'] == null ? _created(j) : _date(j['updatedAt']);

List<String> _strings(Object? v) {
  final x = _jsonValue(v);
  if (x is! List) return const [];
  return List.unmodifiable([
    for (final e in x)
      if (e is String && e.isNotEmpty) e,
  ]);
}

Habit habitFromWire(Json j) => Habit(
  id: j['id'] as String,
  name: _str(j['name']),
  emoji: _strN(j['emoji']),
  color: _strN(j['color']) ?? defaultHabitColor,
  kind: HabitKind.fromWire(j['kind'] as String?),
  schedule:
      HabitSchedule.tryParse(_jsonValue(j['schedule'])) ?? HabitSchedule.daily,
  target: HabitTarget.tryParse(_jsonValue(j['target'])) ?? HabitTarget.check,
  reminders: _strings(j['reminders']),
  isPrivate: _bool(j['private']),
  why: _strN(j['why']),
  startDate: _strN(j['startDate']) ?? _str(j['createdAt']).split('T').first,
  archived: _bool(j['archived']),
  sortOrder: _intN(j['sortOrder']) ?? 0,
  createdAt: _created(j),
  updatedAt: _updated(j),
);

/// Null for an unknown `type` (a newer server).
HabitLog? habitLogFromWire(Json j) {
  final type = HabitLogType.tryFromWire(j['type'] as String?);
  if (type == null) return null;
  return HabitLog(
    id: j['id'] as String,
    habitId: _str(j['habitId']),
    date: _str(j['date']),
    type: type,
    value: _numN(j['value']),
    note: _strN(j['note']),
    triggers: _strings(j['triggers']),
    at: _dateN(j['at']),
    createdAt: _created(j),
    updatedAt: _updated(j),
  );
}

Asset assetFromWire(Json j) {
  final kind = AssetKind.fromWire(j['kind'] as String?);
  return Asset(
    id: j['id'] as String,
    kind: kind,
    symbol: _str(j['symbol']),
    name: _strN(j['name']),
    currency: _strN(j['currency']) ?? 'IDR',
    priceMode: PriceMode.fromWire(j['priceMode'] as String?),
    manualPrice: _numN(j['manualPrice']),
    manualPriceAt: _dateN(j['manualPriceAt']),
    unit: _strN(j['unit']) ?? kind.defaultUnit,
    walletId: _strN(j['walletId']),
    archived: _bool(j['archived']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: _created(j),
    updatedAt: _updated(j),
  );
}

/// Null for an unknown `type` (a newer server).
AssetTrade? assetTradeFromWire(Json j) {
  final type = TradeType.tryFromWire(j['type'] as String?);
  if (type == null) return null;
  return AssetTrade(
    id: j['id'] as String,
    assetId: _str(j['assetId']),
    type: type,
    date: _dateN(j['date']) ?? _created(j),
    quantity: _numN(j['quantity']),
    price: _numN(j['price']),
    fee: _numN(j['fee']) ?? 0,
    amount: _numN(j['amount']),
    ratio: _numN(j['ratio']),
    note: _strN(j['note']),
    cashTransactionId: _strN(j['cashTransactionId']),
    createdAt: _created(j),
    updatedAt: _updated(j),
  );
}

// ---------------------------------------------------------------- prices

/// One entry of `GET /api/mobile/prices`. Accepts `{symbol, kind, price, …}`
/// with an optional `key` (`stock:BBCA`); null when there is no usable price
/// (unknown symbol / never fetched).
SecurityPrice? securityPriceFromWire(
  Object? v, {
  String? key,
  required DateTime receivedAt,
}) {
  if (v is! Map) return null;
  final j = v.cast<String, dynamic>();
  final price = _numN(j['price']);
  if (price == null || price <= 0) return null;
  final k = _strN(j['key']) ?? key;
  final parts = k?.split(':');
  final kindRaw =
      _strN(j['kind']) ??
      (parts != null && parts.length == 2 ? parts[0] : null);
  final symbol =
      _strN(j['symbol']) ??
      (parts != null && parts.length == 2 ? parts[1] : null);
  if (kindRaw == null || symbol == null) return null;
  return SecurityPrice(
    kind: AssetKind.fromWire(kindRaw),
    symbol: symbol.toUpperCase(),
    price: price,
    prevClose: _numN(j['prevClose']),
    change: _numN(j['change']),
    changePct: _numN(j['changePct']),
    currency: _strN(j['currency']) ?? 'IDR',
    name: _strN(j['name']),
    asOf: _dateN(j['asOf']),
    source: _strN(j['source']),
    fetchedAt: _dateN(j['fetchedAt']),
    serverStale: _bool(j['stale']),
    cachedAt: receivedAt,
  );
}

/// The prices endpoint's response `{serverTime, prices: Quote[]}` → prices
/// by key, plus the keys the server reported `error: "not_found"`. Quotes
/// without a price (never fetched, `unavailable`, `rate_limited`) are left
/// out (the cache keeps its last price). Also tolerates a map keyed by
/// `kind:SYMBOL` and a bare list.
({Map<String, SecurityPrice> prices, List<String> notFound})
pricesResponseFromWire(Object? body, {required DateTime receivedAt}) {
  final prices = <String, SecurityPrice>{};
  final notFound = <String>[];
  Object? list = body;
  if (body is Map) list = body['prices'] ?? body['data'] ?? body;
  void one(Object? v, String? key) {
    final p = securityPriceFromWire(v, key: key, receivedAt: receivedAt);
    if (p != null) {
      prices[p.key] = p;
      return;
    }
    // No usable price: only `error: not_found` means the symbol is unknown
    // (`unavailable` / `rate_limited` / never fetched keep the cache).
    if (v is Map && v['error'] == 'not_found') {
      final k =
          _strN(v['key']) ??
          key ??
          (_strN(v['kind']) != null && _strN(v['symbol']) != null
              ? '${v['kind']}:${(v['symbol'] as String).toUpperCase()}'
              : null);
      if (k != null) notFound.add(k);
    }
  }

  if (list is List) {
    for (final e in list) {
      one(e, null);
    }
  } else if (list is Map) {
    for (final e in list.entries) {
      if (e.key is String && (e.key as String).contains(':')) {
        one(e.value, e.key as String);
      }
    }
  }
  final nf = body is Map ? body['notFound'] : null;
  if (nf is List) {
    for (final k in nf) {
      if (k is String && !notFound.contains(k)) notFound.add(k);
    }
  }
  return (prices: prices, notFound: notFound);
}
