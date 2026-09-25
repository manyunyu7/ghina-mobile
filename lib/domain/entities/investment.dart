/// Investments / portfolio (`docs/investments.md`): assets, trades (the source
/// of truth for holdings) and cached market prices.
library;

import 'value_equality.dart';

const _unset = Object();

/// `stock | fund | gold | crypto | bond | other`.
enum AssetKind {
  stock('stock', 'Saham', 'lembar', PriceMode.auto),
  fund('fund', 'Reksa dana', 'unit', PriceMode.manual),
  gold('gold', 'Emas', 'gram', PriceMode.manual),
  crypto('crypto', 'Kripto', 'koin', PriceMode.auto),
  bond('bond', 'Obligasi', 'unit', PriceMode.manual),
  other('other', 'Lainnya', 'unit', PriceMode.manual);

  const AssetKind(
    this.wire,
    this.label,
    this.defaultUnit,
    this.defaultPriceMode,
  );
  final String wire;
  final String label;

  /// Unit shown next to quantities (`lembar`, `gram`, …).
  final String defaultUnit;
  final PriceMode defaultPriceMode;

  /// Only these can follow market prices (server price service).
  bool get supportsAutoPrice => this == stock || this == crypto;

  /// Stocks trade in lots of [sharesPerLot] (UI lot ↔ lembar toggle).
  bool get usesLots => this == stock;

  /// Unknown → other.
  static AssetKind fromWire(String? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return other;
  }
}

/// `auto` (market price from the server) or `manual` (the asset's
/// `manualPrice`, e.g. fund NAV, gold per gram).
enum PriceMode {
  auto('auto', 'Harga pasar otomatis'),
  manual('manual', 'Harga manual');

  const PriceMode(this.wire, this.label);
  final String wire;
  final String label;

  static PriceMode fromWire(String? v) => v == 'manual' ? manual : auto;
}

/// IDX: 1 lot = 100 lembar.
const sharesPerLot = 100;

/// Key of a price in the prices endpoint and the local cache: `stock:BBCA`.
String priceKeyOf(AssetKind kind, String symbol) => '${kind.wire}:$symbol';

/// An instrument the user holds or watches (`@@unique([userId, kind, symbol])`).
final class Asset with ValueEquality {
  const Asset({
    required this.id,
    required this.kind,
    required this.symbol,
    this.name,
    this.currency = 'IDR',
    this.priceMode = PriceMode.auto,
    this.manualPrice,
    this.manualPriceAt,
    this.unit = 'lembar',
    this.walletId,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final AssetKind kind;

  /// Stock: IDX ticker `BBCA`; crypto: `BTC`; others: free code ≤ 20.
  final String symbol;

  /// Display name (auto-filled for stocks when known).
  final String? name;
  final String currency;
  final PriceMode priceMode;

  /// Per unit, used when [priceMode] is manual.
  final double? manualPrice;
  final DateTime? manualPriceAt;

  /// `lembar | unit | gram | koin | …`
  final String unit;

  /// Investment wallet / RDN this asset lives in (cash effect default).
  final String? walletId;
  final bool archived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isManual => priceMode == PriceMode.manual;

  /// `stock:BBCA` — see [priceKeyOf].
  String get priceKey => priceKeyOf(kind, symbol);

  /// `BBCA` or `BBCA · Bank Central Asia`.
  String get displayName =>
      name == null || name!.isEmpty ? symbol : '$symbol · $name';

  Asset copyWith({
    AssetKind? kind,
    String? symbol,
    Object? name = _unset,
    String? currency,
    PriceMode? priceMode,
    Object? manualPrice = _unset,
    Object? manualPriceAt = _unset,
    String? unit,
    Object? walletId = _unset,
    bool? archived,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Asset(
    id: id,
    kind: kind ?? this.kind,
    symbol: symbol ?? this.symbol,
    name: identical(name, _unset) ? this.name : name as String?,
    currency: currency ?? this.currency,
    priceMode: priceMode ?? this.priceMode,
    manualPrice: identical(manualPrice, _unset)
        ? this.manualPrice
        : (manualPrice as num?)?.toDouble(),
    manualPriceAt: identical(manualPriceAt, _unset)
        ? this.manualPriceAt
        : manualPriceAt as DateTime?,
    unit: unit ?? this.unit,
    walletId: identical(walletId, _unset) ? this.walletId : walletId as String?,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    symbol,
    name,
    currency,
    priceMode,
    manualPrice,
    manualPriceAt,
    unit,
    walletId,
    archived,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Asset($id, $priceKey)';
}

/// `buy | sell | dividend | split | fee`.
enum TradeType {
  buy('buy', 'Beli'),
  sell('sell', 'Jual'),
  dividend('dividend', 'Dividen'),
  split('split', 'Stock split'),
  fee('fee', 'Biaya');

  const TradeType(this.wire, this.label);
  final String wire;
  final String label;

  bool get needsQuantityAndPrice => this == buy || this == sell;

  /// Unknown → null (a newer server's type; such rows are ignored).
  static TradeType? tryFromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

/// One trade of an asset. Holdings are derived from these (average-cost).
final class AssetTrade with ValueEquality {
  const AssetTrade({
    required this.id,
    required this.assetId,
    required this.type,
    required this.date,
    this.quantity,
    this.price,
    this.fee = 0,
    this.amount,
    this.ratio,
    this.note,
    this.cashTransactionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String assetId;
  final TradeType type;
  final DateTime date;

  /// Units — shares for stocks (never lots).
  final double? quantity;

  /// Per unit.
  final double? price;

  /// Broker fee + tax in currency (buy/sell).
  final double fee;

  /// Dividend cash, or the amount of a fee-only row.
  final double? amount;

  /// Split: new shares per old share (2 for 1:2).
  final double? ratio;
  final String? note;

  /// The linked wallet transaction (cash effect), if any.
  final String? cashTransactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `quantity × price` (0 when either is missing).
  double get gross => (quantity ?? 0) * (price ?? 0);

  bool get hasCashEffect => cashTransactionId != null;

  AssetTrade copyWith({
    String? assetId,
    TradeType? type,
    DateTime? date,
    Object? quantity = _unset,
    Object? price = _unset,
    double? fee,
    Object? amount = _unset,
    Object? ratio = _unset,
    Object? note = _unset,
    Object? cashTransactionId = _unset,
    DateTime? updatedAt,
  }) => AssetTrade(
    id: id,
    assetId: assetId ?? this.assetId,
    type: type ?? this.type,
    date: date ?? this.date,
    quantity: identical(quantity, _unset)
        ? this.quantity
        : (quantity as num?)?.toDouble(),
    price: identical(price, _unset) ? this.price : (price as num?)?.toDouble(),
    fee: fee ?? this.fee,
    amount: identical(amount, _unset)
        ? this.amount
        : (amount as num?)?.toDouble(),
    ratio: identical(ratio, _unset) ? this.ratio : (ratio as num?)?.toDouble(),
    note: identical(note, _unset) ? this.note : note as String?,
    cashTransactionId: identical(cashTransactionId, _unset)
        ? this.cashTransactionId
        : cashTransactionId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    assetId,
    type,
    date,
    quantity,
    price,
    fee,
    amount,
    ratio,
    note,
    cashTransactionId,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'AssetTrade($id ${type.wire} $quantity@$price)';
}

/// A market price from `GET /api/mobile/prices`, cached on the device for
/// offline display.
final class SecurityPrice with ValueEquality {
  const SecurityPrice({
    required this.kind,
    required this.symbol,
    required this.price,
    this.prevClose,
    this.change,
    this.changePct,
    this.currency = 'IDR',
    this.name,
    this.asOf,
    this.source,
    this.fetchedAt,
    this.serverStale = false,
    required this.cachedAt,
  });

  final AssetKind kind;
  final String symbol;
  final double price;
  final double? prevClose;

  /// `price − prevClose` (per unit).
  final double? change;

  /// Percent (e.g. `1.25` = +1.25 %).
  final double? changePct;
  final String currency;

  /// Instrument name as the price source knows it.
  final String? name;

  /// Market time of the price.
  final DateTime? asOf;
  final String? source;

  /// When the server fetched it from the source.
  final DateTime? fetchedAt;

  /// The server couldn't refresh it (kept its last price).
  final bool serverStale;

  /// When this device received it ("terakhir diperbarui …").
  final DateTime cachedAt;

  String get key => priceKeyOf(kind, symbol);

  /// When the price is from: the server's `fetchedAt`, else when this
  /// device got it.
  DateTime get freshAt => fetchedAt ?? cachedAt;

  @override
  List<Object?> get props => [
    kind,
    symbol,
    price,
    prevClose,
    change,
    changePct,
    currency,
    name,
    asOf,
    source,
    fetchedAt,
    serverStale,
    cachedAt,
  ];
}

/// Result of a price refresh.
final class PriceRefreshResult {
  const PriceRefreshResult({
    required this.updated,
    this.notFound = const [],
    this.at,
  });

  /// Keys (`stock:BBCA`) that got a price.
  final List<String> updated;

  /// Keys the server doesn't know (bad ticker).
  final List<String> notFound;
  final DateTime? at;
}

/// A symbol lookup for "add asset" (validate the ticker, auto-fill the name).
final class SymbolInfo {
  const SymbolInfo({
    required this.kind,
    required this.symbol,
    this.name,
    this.price,
  });

  final AssetKind kind;
  final String symbol;
  final String? name;
  final SecurityPrice? price;
}

/// One stored point of the portfolio value history (local snapshot per day).
final class PortfolioPoint with ValueEquality {
  const PortfolioPoint({
    required this.date,
    required this.value,
    required this.cost,
  });

  /// `YYYY-MM-DD`.
  final String date;

  /// Market value that day.
  final double value;

  /// Cost basis that day.
  final double cost;

  double get pnl => value - cost;

  @override
  List<Object?> get props => [date, value, cost];
}
