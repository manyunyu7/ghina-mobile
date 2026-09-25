/// Pure rules of the portfolio (`docs/investments.md`) — a port of the
/// server's `src/lib/investments.ts` and the cache rules of
/// `src/lib/prices.ts` (same constants, algorithms and Indonesian messages;
/// parity cases in `test/domain/investment_rules_test.dart` mirror
/// `scripts/test-investments.mjs`).
library;

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../entities/entities.dart';

// ---------------------------------------------------------------- constants

/// Stock: IDX ticker (`.JK` stripped).
final stockSymbolRe = RegExp(r'^[A-Z0-9][A-Z0-9-]{0,11}$');

/// Crypto code (`-IDR` stripped).
final cryptoSymbolRe = RegExp(r'^[A-Z0-9]{1,15}$');
const assetSymbolMax = 20;
const assetNameMax = 100;
const assetUnitMax = 20;
const tradeNoteMax = 500;
final _currencyRe = RegExp(r'^[A-Z]{3}$');

/// Float tolerance for share counts (fractional crypto / fund units).
const shareEpsilon = 1e-9;

/// Round to 2 decimals (server `roundMoney`, `Math.round` semantics).
double roundMoney(double n) => (n * 100 + 0.5).floorToDouble() / 100;

/// Income category of dividend cash (server `DIVIDEND_CATEGORY`).
const dividendCategoryName = 'Dividen';
const dividendCategoryColor = '#10b981';
const dividendCategoryIcon = 'circle-dollar-sign';

/// Deterministic id of the Dividen category (the server seeds the same one).
String dividendCategoryId(String userId) => 'category-dividen-$userId';

// ---------------------------------------------------------------- lots

/// Lots → shares (`1 lot = 100 lembar`). Quantities are stored in shares.
double lotsToShares(num lots) => lots * sharesPerLot.toDouble();

/// Shares → lots (fractional for odd lots).
double sharesToLots(num shares) => shares / sharesPerLot;

/// Whether a share count is a whole number of lots.
bool isWholeLots(num shares) =>
    (shares / sharesPerLot - (shares / sharesPerLot).round()).abs() <
    shareEpsilon;

// ---------------------------------------------------------------- fees

/// Broker fee presets as fractions of the gross value (incl. levies/tax;
/// server `FEE_PRESETS`: buy 0.15 %, sell 0.25 %). Users may override them
/// (a client preference).
final class FeePreset {
  const FeePreset({this.buy = 0.0015, this.sell = 0.0025});

  static const standard = FeePreset();

  final double buy;
  final double sell;

  /// Server `estimateFee`: `roundMoney(gross × rate)` for a buy/sell of
  /// [gross] (= q × p); 0 for other trade types or gross ≤ 0.
  double feeFor(TradeType type, double gross) {
    if (!(gross > 0)) return 0;
    return switch (type) {
      TradeType.buy => roundMoney(gross * buy),
      TradeType.sell => roundMoney(gross * sell),
      _ => 0,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FeePreset && other.buy == buy && other.sell == sell;

  @override
  int get hashCode => Object.hash(buy, sell);
}

// ---------------------------------------------------------------- symbols

String _cleanLine(String? v) => (v ?? '')
    .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
    .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
    .replaceAll(RegExp(r' {2,}'), ' ')
    .trim();

/// Normalized symbol (server `normalizeSymbol`): stock/crypto uppercased
/// (`.JK` / `-IDR` stripped) and validated; other kinds trimmed, case kept,
/// ≤ 20. Throws `ValidationFailure(field: 'symbol')`.
String requireAssetSymbol(AssetKind kind, String? raw) {
  final v = _cleanLine(raw);
  if (v.isEmpty) {
    throw const ValidationFailure('Kode wajib diisi', field: 'symbol');
  }
  switch (kind) {
    case AssetKind.stock:
      final s = v.toUpperCase().replaceFirst(RegExp(r'\.JK$'), '');
      if (!stockSymbolRe.hasMatch(s)) {
        throw const ValidationFailure(
          'Kode saham tidak valid (contoh: BBCA)',
          field: 'symbol',
        );
      }
      return s;
    case AssetKind.crypto:
      final s = v.toUpperCase().replaceFirst(RegExp(r'-IDR$'), '');
      if (!cryptoSymbolRe.hasMatch(s)) {
        throw const ValidationFailure(
          'Kode kripto tidak valid (contoh: BTC)',
          field: 'symbol',
        );
      }
      return s;
    default:
      if (v.length > assetSymbolMax) {
        throw const ValidationFailure(
          'Kode maksimal $assetSymbolMax karakter',
          field: 'symbol',
        );
      }
      return v;
  }
}

/// Case-insensitive key of (kind, symbol) uniqueness (server `assetKey`).
String assetKeyOf(AssetKind kind, String symbol) =>
    '${kind.wire}:${symbol.toUpperCase()}';

/// Name: one line ≤ 100 or null.
String? assetName(String? v) {
  final s = _cleanLine(v);
  if (s.isEmpty) return null;
  if (s.length > assetNameMax) {
    throw const ValidationFailure(
      'Nama maksimal $assetNameMax karakter',
      field: 'name',
    );
  }
  return s;
}

/// Unit: one line ≤ 20, default per kind.
String assetUnit(AssetKind kind, String? v) {
  final s = _cleanLine(v);
  if (s.isEmpty) return kind.defaultUnit;
  if (s.length > assetUnitMax) {
    throw const ValidationFailure(
      'Satuan maksimal $assetUnitMax karakter',
      field: 'unit',
    );
  }
  return s;
}

/// Currency: 3 letters, uppercased (default IDR).
String assetCurrency(String? v) {
  final s = (v ?? '').trim().toUpperCase();
  if (s.isEmpty) return 'IDR';
  if (!_currencyRe.hasMatch(s)) {
    throw const ValidationFailure(
      'Mata uang harus 3 huruf (IDR)',
      field: 'currency',
    );
  }
  return s;
}

// ---------------------------------------------------------------- holding

/// Processing order: `date`, then `createdAt`, then id (server
/// `compareTrades`).
int compareTrades(AssetTrade a, AssetTrade b) {
  var c = a.date.compareTo(b.date);
  if (c != 0) return c;
  c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

List<AssetTrade> sortTrades(Iterable<AssetTrade> trades) =>
    trades.toList()..sort(compareTrades);

/// `150`, `0.3` (JS `String(Math.round(n * 1e6) / 1e6)`).
String _fmtQty(double n) {
  final r = (n * 1e6).roundToDouble() / 1e6;
  if (r == r.roundToDouble()) return r.toInt().toString();
  return r.toString();
}

/// Average-cost derivation (server `deriveHolding`), trades in
/// [compareTrades] order:
/// - buy: `cost += q·p + fee; shares += q`
/// - sell: `realized += q·p − fee − q·avg; cost −= q·avg; shares −= q` — a
///   sell of more than held is reported in [Holding.issues] and clamped
/// - split: `shares *= ratio` (cost unchanged)
/// - dividend: `dividends += amount`
/// - fee: `realized −= amount`
Holding deriveHolding(Iterable<AssetTrade> trades) {
  var shares = 0.0, cost = 0.0, realized = 0.0, dividends = 0.0;
  var fees = 0.0, invested = 0.0, proceeds = 0.0;
  final issues = <HoldingIssue>[];
  final list = sortTrades(trades);
  for (final t in list) {
    final q = t.quantity ?? 0, p = t.price ?? 0;
    switch (t.type) {
      case TradeType.buy:
        cost += q * p + t.fee;
        shares += q;
        fees += t.fee;
        invested += q * p;
      case TradeType.sell:
        var qty = q;
        if (qty > shares + shareEpsilon * (shares > 1 ? shares : 1)) {
          issues.add(
            HoldingIssue(
              tradeId: t.id,
              date: t.date.toUtc().toIso8601String(),
              message:
                  'Jumlah jual (${_fmtQty(q)}) melebihi kepemilikan '
                  '(${_fmtQty(shares)})',
            ),
          );
          qty = shares;
        }
        final avg = shares > 0 ? cost / shares : 0.0;
        realized += qty * p - t.fee - qty * avg;
        cost -= qty * avg;
        shares -= qty;
        fees += t.fee;
        proceeds += qty * p;
        if (shares <= shareEpsilon) {
          shares = 0;
          cost = 0;
        }
      case TradeType.split:
        final r = t.ratio;
        if (r != null && r > 0) shares *= r;
      case TradeType.dividend:
        dividends += t.amount ?? 0;
      case TradeType.fee:
        realized -= t.amount ?? 0;
        fees += t.amount ?? 0;
    }
  }
  return Holding(
    shares: shares,
    cost: cost,
    realized: realized,
    dividends: dividends,
    fees: fees,
    invested: invested,
    proceeds: proceeds,
    tradeCount: list.length,
    issues: List.unmodifiable(issues),
  );
}

/// The first problem of a trade list (holdings must never go negative in
/// date order) as the server's Indonesian message, or null (server
/// `tradeSequenceError`).
String? tradeSequenceError(Iterable<AssetTrade> trades) =>
    deriveHolding(trades).issues.firstOrNull?.sequenceError;

/// The server's sanity check of a save: with trade [id] replaced by [next]
/// (null = removed), holdings must not go negative where they didn't before.
/// Returns the error message or null (server `assertTradeSequence`).
String? tradeChangeError(
  List<AssetTrade> current,
  String id,
  AssetTrade? next,
) {
  final before = deriveHolding(current);
  final after = deriveHolding([
    for (final t in current)
      if (t.id != id) t,
    ?next,
  ]);
  final introduced =
      after.issues.length > before.issues.length ||
      after.issues.any((i) => i.tradeId == id);
  if (after.issues.isEmpty || !introduced) return null;
  final i =
      after.issues.where((x) => x.tradeId == id).firstOrNull ??
      after.issues.first;
  return i.sequenceError;
}

/// Shares held just before [at] (the "maks jual" hint of a sell form).
double sharesHeldAt(Iterable<AssetTrade> trades, DateTime at) =>
    deriveHolding(trades.where((t) => !t.date.isAfter(at))).shares;

// ---------------------------------------------------------------- valuation

/// Market value and P/L of [h] at [price] (null = unknown), with the day
/// change from [prevClose] (server `valueHolding`).
Valuation valueHolding(Holding h, double? price, [double? prevClose]) {
  final mv = price == null ? null : h.shares * price;
  final u = mv == null ? null : mv - h.cost;
  return Valuation(
    price: price,
    marketValue: mv,
    unrealized: u,
    unrealizedPct: u == null || h.cost <= 0 ? null : u / h.cost * 100,
    dayChange: price == null || prevClose == null || h.shares == 0
        ? null
        : h.shares * (price - prevClose),
    dayChangePct: price == null || prevClose == null || prevClose == 0
        ? null
        : (price - prevClose) / prevClose * 100,
    totalReturn: (u ?? 0) + h.realized + h.dividends,
  );
}

/// Allocation by any key, largest first (null / non-positive values left
/// out; same keys merged), server `allocation`.
List<AllocationSlice> allocation(
  Iterable<({String key, String label, double? value})> items,
) {
  final sums = <String, ({String label, double value})>{};
  for (final it in items) {
    final v = it.value;
    if (v == null || !(v > 0)) continue;
    final e = sums[it.key];
    sums[it.key] = (label: e?.label ?? it.label, value: (e?.value ?? 0) + v);
  }
  final total = sums.values.fold(0.0, (s, e) => s + e.value);
  return [
    for (final e in sums.entries)
      AllocationSlice(
        key: e.key,
        label: e.value.label,
        value: e.value.value,
        pct: total > 0 ? e.value.value / total * 100 : 0,
      ),
  ]..sort((a, b) => b.value.compareTo(a.value));
}

// ---------------------------------------------------------------- cash effect

/// The wallet transaction a trade creates (server `tradeCashEffect`): buy →
/// investment −(q·p + fee) · sell → investment +(q·p − fee) · fee →
/// investment −amount · dividend → income +amount · split → none. Rounded to
/// 2 decimals; a zero amount (or a negative dividend) → none.
({TxType type, double amount})? tradeCashEffect(AssetTrade t) {
  final q = t.quantity ?? 0, p = t.price ?? 0;
  final ({TxType type, double amount})? e = switch (t.type) {
    TradeType.buy => (
      type: TxType.investment,
      amount: -roundMoney(q * p + t.fee),
    ),
    TradeType.sell => (
      type: TxType.investment,
      amount: roundMoney(q * p - t.fee),
    ),
    TradeType.fee => (
      type: TxType.investment,
      amount: -roundMoney(t.amount ?? 0),
    ),
    TradeType.dividend => (
      type: TxType.income,
      amount: roundMoney(t.amount ?? 0),
    ),
    TradeType.split => null,
  };
  if (e == null || e.amount == 0) return null;
  if (e.type == TxType.income && e.amount < 0) return null;
  return e;
}

/// Expected type of a trade's linked transaction (null for split).
TxType? linkedTransactionType(TradeType type) => switch (type) {
  TradeType.dividend => TxType.income,
  TradeType.buy || TradeType.sell || TradeType.fee => TxType.investment,
  TradeType.split => null,
};

/// Whether a linked transaction fits a trade — right type and sign (server
/// `linkedTransactionError`); null = ok.
String? linkedTransactionError(TradeType type, TxType txType, double amount) {
  final want = linkedTransactionType(type);
  if (want == null) return 'Stock split tidak punya transaksi kas';
  if (txType != want) {
    return want == TxType.income
        ? 'Transaksi dividen harus berupa pemasukan'
        : 'Transaksi kas harus bertipe investasi';
  }
  if (type == TradeType.sell && !(amount > 0)) {
    return 'Transaksi kas penjualan harus bernilai positif';
  }
  if ((type == TradeType.buy || type == TradeType.fee) && !(amount < 0)) {
    return 'Transaksi kas pembelian/biaya harus bernilai negatif';
  }
  return null;
}

/// `9.500`, `0,5`, `1.000.000.000` (id-ID, ≤ 8 decimals).
String _fmtNum(double v) {
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(8);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return '${neg ? '-' : ''}$whole${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// Note of a trade's wallet transaction (server `tradeTransactionNote`):
/// `Beli BBCA 10 lot @ 9.500`, `Jual BTC 0,5 koin @ 1.000.000.000`,
/// `Dividen BBRI`.
String tradeTransactionNote(AssetTrade t, Asset a) {
  final label = t.type.label;
  if (t.type == TradeType.buy || t.type == TradeType.sell) {
    final q = t.quantity ?? 0;
    final qty = a.kind == AssetKind.stock && isWholeLots(q)
        ? '${_fmtNum(sharesToLots(q))} lot'
        : '${_fmtNum(q)} ${a.unit}'.trim();
    return '$label ${a.symbol} $qty @ ${_fmtNum(t.price ?? 0)}';
  }
  return '$label ${a.symbol}';
}

// ---------------------------------------------------------------- prices

/// Price cache TTL (server `PRICE_TTL_MS`).
const priceTtl = Duration(minutes: 15);

const _wib = Duration(hours: 7);
const _openMin = 9 * 60;
const _closeMin = 16 * 60 + 15;

/// IDX session: Mon–Fri 09:00–16:15 WIB (UTC+7), holidays not modelled
/// (server `idxMarketOpen`).
bool isIdxSessionOpen(DateTime now) {
  final w = now.toUtc().add(_wib);
  if (w.weekday > DateTime.friday) return false;
  final m = w.hour * 60 + w.minute;
  return m >= _openMin && m < _closeMin;
}

/// The most recent session close (Mon–Fri 16:15 WIB) at or before [now]
/// (server `lastIdxClose`), UTC.
DateTime lastIdxClose(DateTime now) {
  final nowUtc = now.toUtc();
  final w = nowUtc.add(_wib);
  for (var k = 0; k < 8; k++) {
    final d = DateTime.utc(w.year, w.month, w.day - k);
    if (d.weekday > DateTime.friday) continue;
    final close = d.add(const Duration(minutes: _closeMin)).subtract(_wib);
    if (!close.isAfter(nowUtc)) return close;
  }
  return nowUtc.subtract(const Duration(days: 7));
}

/// Cache rule (server `isPriceFresh`): crypto — or stocks while the session
/// is open — are fresh for 15 min; stocks outside the session stay fresh
/// when fetched after the last close.
bool isPriceFresh(AssetKind kind, DateTime fetchedAt, DateTime now) {
  final age = now.difference(fetchedAt);
  if (age.isNegative) return true;
  if (kind == AssetKind.crypto || isIdxSessionOpen(now)) return age < priceTtl;
  return !fetchedAt.toUtc().isBefore(lastIdxClose(now));
}

/// A cached quote is stale when the server flagged it or it is no longer
/// fresh by [isPriceFresh] (from its `fetchedAt`).
bool isPriceStale(SecurityPrice p, DateTime now) =>
    p.serverStale || !isPriceFresh(p.kind, p.freshAt, now);

/// Price keys (`stock:BBCA`) the portfolio needs from the server: auto-priced
/// stock/crypto assets that aren't archived.
List<String> autoPriceKeys(Iterable<Asset> assets) => {
  for (final a in assets)
    if (!a.archived && !a.isManual && a.kind.supportsAutoPrice) a.priceKey,
}.toList()..sort();

/// The price used for [a] (server `getPortfolio`): an auto asset's cached
/// quote (stale still used, flagged); a manual asset's `manualPrice`.
PriceQuote quoteFor(Asset a, SecurityPrice? p, DateTime now) {
  final auto = !a.isManual && a.kind.supportsAutoPrice;
  if (auto) {
    if (p == null) return PriceQuote.none;
    return PriceQuote(
      price: p.price,
      prevClose: p.prevClose,
      asOf: p.asOf,
      updatedAt: p.fetchedAt ?? p.cachedAt,
      stale: isPriceStale(p, now),
      source: PriceSource.auto,
    );
  }
  if (a.manualPrice == null) return PriceQuote.none;
  return PriceQuote(
    price: a.manualPrice,
    asOf: a.manualPriceAt,
    updatedAt: a.manualPriceAt,
    source: PriceSource.manual,
  );
}

// ---------------------------------------------------------------- portfolio

/// Holding of [a] valued at [price].
HoldingView holdingViewOf(
  Asset a,
  Iterable<AssetTrade> trades,
  SecurityPrice? price,
  DateTime now,
) {
  final h = deriveHolding(trades);
  final q = quoteFor(a, price, now);
  return HoldingView(
    asset: a,
    holding: h,
    quote: q,
    valuation: valueHolding(
      h,
      q.price,
      q.source == PriceSource.auto ? q.prevClose : null,
    ),
  );
}

/// Asset order (`sortOrder`, `createdAt`).
int compareAssets(Asset a, Asset b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
}

/// The portfolio of the non-archived [assets] valued at [prices] (keyed by
/// `priceKey`), server `getPortfolio`.
PortfolioSummary buildPortfolio({
  required List<Asset> assets,
  required List<AssetTrade> trades,
  required Map<String, SecurityPrice> prices,
  required DateTime now,
}) {
  final byAsset = <String, List<AssetTrade>>{};
  for (final t in trades) {
    byAsset.putIfAbsent(t.assetId, () => []).add(t);
  }
  final active = assets.where((a) => !a.archived).toList()..sort(compareAssets);
  final views = [
    for (final a in active)
      holdingViewOf(a, byAsset[a.id] ?? const [], prices[a.priceKey], now),
  ];
  final total = views.fold(0.0, (s, v) => s + v.value);
  DateTime? asOf;
  for (final a in active) {
    if (a.isManual || !a.kind.supportsAutoPrice) continue;
    final f = prices[a.priceKey]?.fetchedAt;
    if (f != null && (asOf == null || f.isBefore(asOf))) asOf = f;
  }
  return PortfolioSummary(
    holdings: List.unmodifiable([
      for (final v in views)
        v.withWeight(total > 0 && v.value > 0 ? v.value / total * 100 : 0),
    ]),
    byAsset: allocation([
      for (final v in views)
        (key: v.asset.id, label: v.asset.symbol, value: v.value),
    ]),
    byKind: allocation([
      for (final v in views)
        (key: v.asset.kind.wire, label: v.asset.kind.label, value: v.value),
    ]),
    pricesAsOf: asOf,
  );
}

/// The value-history snapshot of [p] for [day].
PortfolioPoint snapshotOf(PortfolioSummary p, DateTime day) =>
    PortfolioPoint(date: dateKey(day), value: p.marketValue, cost: p.cost);

// ---------------------------------------------------------------- validation

/// Finite and > 0 (throws with [field]).
double requirePositive(double? v, String field, String message) {
  if (v == null || !v.isFinite || v <= 0) {
    throw ValidationFailure(message, field: field);
  }
  return v;
}
