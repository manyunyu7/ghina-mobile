/// Read models of the portfolio (produced by `investment_rules.dart` and the
/// investment watch use cases).
library;

import 'investment.dart';
import 'transaction.dart';
import 'value_equality.dart';

/// A sell beyond the held quantity (clamped in the lenient derivation).
final class HoldingIssue with ValueEquality {
  const HoldingIssue({
    required this.tradeId,
    required this.date,
    required this.message,
  });

  final String? tradeId;

  /// The trade's date (UTC ISO; `date.substring(0, 10)` is the server's day).
  final String date;

  /// `Jumlah jual (150) melebihi kepemilikan (100)`.
  final String message;

  /// The server's sanity-check message: `<message> per YYYY-MM-DD`.
  String get sequenceError => '$message per ${date.substring(0, 10)}';

  @override
  List<Object?> get props => [tradeId, date, message];
}

/// A holding derived from an asset's trades (average-cost method, server
/// `Holding`).
final class Holding with ValueEquality {
  const Holding({
    this.shares = 0,
    this.cost = 0,
    this.realized = 0,
    this.dividends = 0,
    this.fees = 0,
    this.invested = 0,
    this.proceeds = 0,
    this.tradeCount = 0,
    this.issues = const [],
  });

  static const empty = Holding();

  /// Units held (shares for stocks).
  final double shares;

  /// Remaining cost basis (buy fees included).
  final double cost;

  /// Realized P/L: sells net of fees minus their average cost, minus fee rows.
  final double realized;

  /// Σ dividends.
  final double dividends;

  /// Σ fees paid (buy/sell fees + fee rows).
  final double fees;

  /// Σ bought / sold value (q × p, without fees).
  final double invested;
  final double proceeds;
  final int tradeCount;

  /// Sells beyond the held quantity (clamped).
  final List<HoldingIssue> issues;

  /// `cost / shares`, null when nothing is held.
  double? get avgPrice => shares > 0 ? cost / shares : null;
  bool get isOpen => shares > 0;

  @override
  List<Object?> get props => [
    shares,
    cost,
    realized,
    dividends,
    fees,
    invested,
    proceeds,
    tradeCount,
    issues,
  ];
}

/// Market value and P/L of a holding at a price (server `Valuation`).
final class Valuation with ValueEquality {
  const Valuation({
    this.price,
    this.marketValue,
    this.unrealized,
    this.unrealizedPct,
    this.dayChange,
    this.dayChangePct,
    this.totalReturn = 0,
  });

  final double? price;

  /// `shares × price`; null without a price.
  final double? marketValue;
  final double? unrealized;

  /// Percent of the cost basis; null without a price or cost.
  final double? unrealizedPct;

  /// `shares × (price − prevClose)` (auto prices only).
  final double? dayChange;
  final double? dayChangePct;

  /// unrealized (0 without a price) + realized + dividends.
  final double totalReturn;

  @override
  List<Object?> get props => [
    price,
    marketValue,
    unrealized,
    unrealizedPct,
    dayChange,
    dayChangePct,
    totalReturn,
  ];
}

/// Where an asset's price comes from.
enum PriceSource { auto, manual }

/// The price used for an asset: the cached market quote (auto) or the
/// asset's manual price.
final class PriceQuote with ValueEquality {
  const PriceQuote({
    this.price,
    this.prevClose,
    this.asOf,
    this.updatedAt,
    this.stale = false,
    this.source,
  });

  static const none = PriceQuote();

  /// Per unit; null = unknown (never fetched, offline, no manual price).
  final double? price;

  /// Auto prices only.
  final double? prevClose;

  /// Market time (auto) / `manualPriceAt` (manual: "harga manual per …").
  final DateTime? asOf;

  /// When this device got it ("terakhir diperbarui …"); manual:
  /// `manualPriceAt`.
  final DateTime? updatedAt;

  /// Auto: old per the cache rules (`isPriceFresh`) or flagged by the server.
  final bool stale;

  /// null = no price.
  final PriceSource? source;

  bool get hasPrice => price != null;
  bool get isManual => source == PriceSource.manual;

  @override
  List<Object?> get props => [price, prevClose, asOf, updatedAt, stale, source];
}

/// One asset with its holding valued at its [quote] (server `HoldingRow`).
final class HoldingView with ValueEquality {
  const HoldingView({
    required this.asset,
    required this.holding,
    required this.quote,
    required this.valuation,
    this.weight = 0,
  });

  final Asset asset;
  final Holding holding;
  final PriceQuote quote;
  final Valuation valuation;

  /// 0–100 share of the portfolio's [value] total.
  final double weight;

  String get id => asset.id;
  double get shares => holding.shares;

  /// Stocks: lots held (`shares / 100`).
  double get lots => holding.shares / sharesPerLot;

  /// Market value; null without a price.
  double? get marketValue => valuation.marketValue;

  /// Value counted in totals: market value, or the cost basis without a price.
  double get value => valuation.marketValue ?? holding.cost;
  double? get unrealized => valuation.unrealized;
  double? get unrealizedPct => valuation.unrealizedPct;
  double? get dayChange => valuation.dayChange;
  double? get dayChangePct => valuation.dayChangePct;
  double get totalReturn => valuation.totalReturn;

  /// Held but valued at cost (no price known).
  bool get unpriced => holding.isOpen && valuation.price == null;

  HoldingView withWeight(double w) => HoldingView(
    asset: asset,
    holding: holding,
    quote: quote,
    valuation: valuation,
    weight: w,
  );

  @override
  List<Object?> get props => [asset, holding, quote, valuation, weight];
}

/// One slice of an allocation donut.
final class AllocationSlice with ValueEquality {
  const AllocationSlice({
    required this.key,
    required this.label,
    required this.value,
    required this.pct,
  });

  /// Asset id (by asset) or kind wire id (by kind).
  final String key;
  final String label;
  final double value;

  /// 0–100.
  final double pct;

  @override
  List<Object?> get props => [key, label, value, pct];
}

/// The whole portfolio of the non-archived assets (server `PortfolioSummary`
/// + holdings).
final class PortfolioSummary with ValueEquality {
  const PortfolioSummary({
    required this.holdings,
    required this.byAsset,
    required this.byKind,
    this.pricesAsOf,
  });

  static const empty = PortfolioSummary(holdings: [], byAsset: [], byKind: []);

  /// Every non-archived asset in asset order (`sortOrder`, `createdAt`),
  /// closed positions and watch-only assets included.
  final List<HoldingView> holdings;

  /// By [HoldingView.value], largest first.
  final List<AllocationSlice> byAsset;
  final List<AllocationSlice> byKind;

  /// Oldest `fetchedAt` of the cached quotes used ("terakhir diperbarui").
  final DateTime? pricesAsOf;

  Iterable<HoldingView> get open => holdings.where((h) => h.holding.isOpen);
  bool get isEmpty => holdings.isEmpty;

  /// Σ value (market value, or cost basis when no price is known).
  double get marketValue => holdings.fold(0, (s, h) => s + h.value);
  double get cost => holdings.fold(0, (s, h) => s + h.holding.cost);
  double get unrealized => holdings.fold(0, (s, h) => s + (h.unrealized ?? 0));
  double? get unrealizedPct => cost > 0 ? unrealized / cost * 100 : null;
  double get dayChange => holdings.fold(0, (s, h) => s + (h.dayChange ?? 0));

  /// Today's change relative to the value before it (null when unknown).
  double? get dayChangePct {
    final before = marketValue - dayChange;
    return dayChange == 0 || before <= 0 ? null : dayChange / before * 100;
  }

  double get realized => holdings.fold(0, (s, h) => s + h.holding.realized);
  double get dividends => holdings.fold(0, (s, h) => s + h.holding.dividends);
  double get totalReturn => unrealized + realized + dividends;

  /// Held assets valued at cost because no price is known.
  int get unpricedCount => holdings.where((h) => h.unpriced).length;

  /// Held auto-priced assets whose quote is stale.
  int get staleCount =>
      holdings.where((h) => h.holding.isOpen && h.quote.stale).length;
  bool get stale => staleCount > 0;

  HoldingView? holding(String assetId) =>
      holdings.where((h) => h.asset.id == assetId).firstOrNull;

  @override
  List<Object?> get props => [holdings, byAsset, byKind, pricesAsOf];
}

/// A trade with its linked cash transaction (if any).
final class TradeView with ValueEquality {
  const TradeView({required this.trade, this.transaction});

  final AssetTrade trade;
  final Transaction? transaction;

  String get id => trade.id;

  @override
  List<Object?> get props => [trade, transaction];
}

/// Asset detail: the valued holding, its trades (newest first) and the
/// cached price.
final class AssetDetail with ValueEquality {
  const AssetDetail({required this.view, required this.trades, this.price});

  final HoldingView view;
  final List<TradeView> trades;

  /// Cached market price (auto assets), null if never fetched / manual.
  final SecurityPrice? price;

  Asset get asset => view.asset;
  Holding get holding => view.holding;

  Iterable<TradeView> get dividends =>
      trades.where((t) => t.trade.type == TradeType.dividend);

  @override
  List<Object?> get props => [view, trades, price];
}

/// Net worth = Σ wallet balances + Σ asset values (server `NetWorth`:
/// `cash` + `investments`).
final class NetWorth with ValueEquality {
  const NetWorth({required this.wallets, required this.investments});

  /// Σ displayed balances of non-archived wallets (server `cash`).
  final double wallets;

  /// Portfolio value of the non-archived assets (market value, or cost basis
  /// when no price is known).
  final double investments;

  double get total => wallets + investments;

  @override
  List<Object?> get props => [wallets, investments];
}
