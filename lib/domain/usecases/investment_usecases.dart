/// Portfolio use cases (`docs/investments.md`): assets, trades with their
/// cash effect (linked `investment` / dividend income transactions, created,
/// updated and deleted atomically through the transaction use cases), prices,
/// portfolio summary/history and net worth.
library;

import 'dart:async';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'investment_rules.dart';
import 'task_usecases.dart' show TickSource;
import 'transaction_usecases.dart';
import 'validation.dart';

// ---------------------------------------------------------------- inputs

/// Add/edit form of an asset.
final class AssetInput {
  const AssetInput({
    required this.kind,
    required this.symbol,
    this.name,
    this.currency = 'IDR',
    this.priceMode,
    this.manualPrice,
    this.manualPriceAt,
    this.unit,
    this.walletId,
  });

  final AssetKind kind;

  /// Stock ticker (`BBCA`, `.JK` stripped), crypto code (`BTC`), or a free
  /// code ≤ 20. Uppercased.
  final String symbol;
  final String? name;
  final String currency;

  /// Null = the kind's default (stock/crypto auto, others manual). Kinds
  /// without market prices are always manual.
  final PriceMode? priceMode;

  /// Per unit (manual assets).
  final double? manualPrice;

  /// Null = now when [manualPrice] is set.
  final DateTime? manualPriceAt;

  /// Null = the kind's default (`lembar`, `gram`, …).
  final String? unit;

  /// Investment wallet / RDN (default for the trades' cash effect).
  final String? walletId;
}

/// Add/edit form of a trade. Quantities are in **units** (shares) — convert
/// lots with `lotsToShares`.
final class TradeInput {
  const TradeInput({
    required this.assetId,
    required this.type,
    required this.date,
    this.quantity,
    this.price,
    this.fee = 0,
    this.amount,
    this.ratio,
    this.note,
    this.cashEffect,
    this.walletId,
  });

  final String assetId;
  final TradeType type;
  final DateTime date;

  /// buy/sell: > 0.
  final double? quantity;

  /// buy/sell: > 0, per unit.
  final double? price;

  /// buy/sell: ≥ 0 (use `FeePreset.feeFor` for the preset).
  final double fee;

  /// dividend / fee rows: > 0.
  final double? amount;

  /// split: new shares per old share (> 0).
  final double? ratio;
  final String? note;

  /// Move cash through the wallet (linked transaction). Null = default: on
  /// create ON when a wallet is known (input or the asset's); on edit keep
  /// the current state.
  final bool? cashEffect;

  /// Wallet of the cash effect (default: the linked transaction's wallet,
  /// else the asset's).
  final String? walletId;
}

// ---------------------------------------------------------------- helpers

Future<Asset> _requireAsset(AssetRepository repo, String id) async {
  final a = await repo.getById(id);
  if (a == null) throw const NotFoundFailure('Aset tidak ditemukan');
  return a;
}

Future<AssetTrade> _requireTrade(AssetTradeRepository repo, String id) async {
  final t = await repo.getById(id);
  if (t == null) throw const NotFoundFailure('Transaksi aset tidak ditemukan');
  return t;
}

/// Throws when replacing trade [id] by [next] (null = removed) makes a sell
/// exceed the holding where it didn't before (the server's sanity check,
/// same message).
void _guard(List<AssetTrade> current, String id, AssetTrade? next) {
  final e = tradeChangeError(current, id, next);
  if (e != null) throw ValidationFailure(e, field: 'quantity');
}

AssetTrade _buildTrade(
  String id,
  TradeInput input, {
  required DateTime createdAt,
  required DateTime now,
  String? cashTransactionId,
}) {
  double? q, p, amount, ratio;
  var fee = 0.0;
  switch (input.type) {
    case TradeType.buy:
    case TradeType.sell:
      q = requirePositive(
        input.quantity,
        'quantity',
        'Jumlah harus lebih dari 0',
      );
      p = requirePositive(input.price, 'price', 'Harga harus lebih dari 0');
      if (!input.fee.isFinite || input.fee < 0) {
        throw const ValidationFailure(
          'Biaya tidak boleh negatif',
          field: 'fee',
        );
      }
      fee = input.fee;
    case TradeType.dividend:
    case TradeType.fee:
      amount = requirePositive(
        input.amount,
        'amount',
        'Nominal harus lebih dari 0',
      );
    case TradeType.split:
      final r = input.ratio;
      if (r == null || !r.isFinite || r <= 0 || r == 1) {
        throw const ValidationFailure(
          'Rasio split harus lebih dari 0 dan bukan 1',
          field: 'ratio',
        );
      }
      ratio = r;
  }
  return AssetTrade(
    id: id,
    assetId: input.assetId,
    type: input.type,
    date: input.date,
    quantity: q,
    price: p,
    fee: fee,
    amount: amount,
    ratio: ratio,
    note: _tradeNote(input.note),
    cashTransactionId: cashTransactionId,
    createdAt: createdAt,
    updatedAt: now,
  );
}

String? _tradeNote(String? v) {
  final s = v?.replaceAll('\r\n', '\n').trim();
  if (s == null || s.isEmpty) return null;
  if (s.length > tradeNoteMax) {
    throw const ValidationFailure(
      'Catatan maksimal $tradeNoteMax karakter',
      field: 'note',
    );
  }
  return s;
}

/// The income category dividends go to (server `ensureDividendCategory`): an
/// income category named "Dividen" (case-insensitive), else
/// `category-dividen-<userId>` (the id the server seeds; a later push is an
/// upsert of the same id). [userId] null (signed-out tests) → a random id.
final class EnsureDividendCategory {
  const EnsureDividendCategory(this._categories, this._clock, {this.userId});
  final CategoryRepository _categories;
  final Clock _clock;
  final String? userId;

  Future<TxCategory> call() async {
    final all = await _categories.getAll(type: CategoryType.income);
    final found = all
        .where(
          (c) =>
              c.name.trim().toLowerCase() == dividendCategoryName.toLowerCase(),
        )
        .firstOrNull;
    if (found != null) return found;
    final uid = userId;
    final id = uid == null ? newId() : dividendCategoryId(uid);
    final existing = await _categories.getById(id);
    if (existing != null) return existing;
    final now = _clock.now();
    final c = TxCategory(
      id: id,
      name: dividendCategoryName,
      type: CategoryType.income,
      color: dividendCategoryColor,
      icon: dividendCategoryIcon,
      createdAt: now,
      updatedAt: now,
    );
    await _categories.save(c);
    return c;
  }
}

/// Creates/updates/deletes the cash transaction of a trade. Shared by the
/// trade use cases (always inside their unit of work).
final class TradeCashEffect {
  const TradeCashEffect(
    this._txRepo,
    this._createTx,
    this._updateTx,
    this._deleteTx,
    this._dividendCategory,
  );
  final TransactionRepository _txRepo;
  final CreateTransaction _createTx;
  final UpdateTransaction _updateTx;
  final DeleteTransaction _deleteTx;
  final EnsureDividendCategory _dividendCategory;

  /// Makes the linked transaction match [trade] (or removes it when
  /// [enabled] is false / the type has no cash effect). Returns its id.
  Future<Transaction?> apply(
    Asset asset,
    AssetTrade trade, {
    required bool enabled,
    String? walletId,
  }) async {
    final linkedId = trade.cashTransactionId;
    final linked = linkedId == null ? null : await _txRepo.getById(linkedId);
    final effect = tradeCashEffect(trade);
    if (!enabled || effect == null) {
      if (linked != null) (await _deleteTx(linked.id)).valueOrThrow;
      return null;
    }
    final (:type, :amount) = effect;
    // The server refuses a link with the wrong sign (e.g. a sell whose fee
    // eats the whole proceeds) — refuse it here instead of after the push.
    if (linkedTransactionError(trade.type, type, amount) case final e?) {
      throw ValidationFailure(
        trade.type == TradeType.sell
            ? 'Biaya tidak boleh sebesar atau melebihi nilai penjualan '
                  '(atau matikan catat arus kas)'
            : e,
        field: trade.type == TradeType.sell ? 'fee' : 'amount',
      );
    }
    final wallet = walletId ?? linked?.walletId ?? asset.walletId;
    if (wallet == null || wallet.isEmpty) {
      throw const ValidationFailure(
        'Pilih dompet untuk mencatat arus kas',
        field: 'walletId',
      );
    }
    final input = TransactionInput(
      type: type,
      amount: amount,
      walletId: wallet,
      categoryId: type == TxType.income
          ? (linked?.type == TxType.income && linked?.categoryId != null
                ? linked!.categoryId
                : (await _dividendCategory()).id)
          : null,
      note: tradeTransactionNote(trade, asset),
      date: trade.date,
    );
    return linked == null
        ? (await _createTx(input)).valueOrThrow
        : (await _updateTx(linked.id, input)).valueOrThrow;
  }
}

// ---------------------------------------------------------------- assets

Asset _buildAsset(
  String id,
  AssetInput input, {
  required DateTime createdAt,
  required DateTime now,
  bool archived = false,
  int sortOrder = 0,
}) {
  final symbol = requireAssetSymbol(input.kind, input.symbol);
  final mode = input.kind.supportsAutoPrice
      ? (input.priceMode ?? PriceMode.auto)
      : PriceMode.manual;
  final manual = input.manualPrice;
  if (manual != null && (!manual.isFinite || manual < 0)) {
    throw const ValidationFailure(
      'Harga tidak boleh negatif',
      field: 'manualPrice',
    );
  }
  return Asset(
    id: id,
    kind: input.kind,
    symbol: symbol,
    name: assetName(input.name),
    currency: assetCurrency(input.currency),
    priceMode: mode,
    manualPrice: manual,
    manualPriceAt: manual == null ? null : (input.manualPriceAt ?? now),
    unit: assetUnit(input.kind, input.unit),
    walletId: optionalId(input.walletId),
    archived: archived,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: now,
  );
}

Future<void> _checkAssetRefs(
  Asset a,
  AssetRepository assets,
  WalletRepository wallets,
) async {
  final clash = await assets.findBySymbol(a.kind, a.symbol);
  if (clash != null && clash.id != a.id) {
    throw ValidationFailure(
      '${a.symbol} sudah ada di portofolio'
      '${clash.archived ? ' (diarsipkan)' : ''}',
      field: 'symbol',
    );
  }
  if (a.walletId != null && await wallets.getById(a.walletId!) == null) {
    throw const NotFoundFailure('Dompet tidak ditemukan');
  }
}

/// Adds an asset (unique per kind + symbol → `ValidationFailure(field:
/// 'symbol')`). Validate stock/crypto tickers first with
/// [LookupSymbol] when online (name auto-fill).
final class CreateAsset {
  const CreateAsset(this._assets, this._wallets, this._clock);
  final AssetRepository _assets;
  final WalletRepository _wallets;
  final Clock _clock;

  Future<Result<Asset>> call(AssetInput input) => guard(() async {
    final now = _clock.now();
    final all = await _assets.getAll();
    final order = all.fold(-1, (m, a) => a.sortOrder > m ? a.sortOrder : m);
    final a = _buildAsset(
      newId(),
      input,
      createdAt: now,
      now: now,
      sortOrder: order + 1,
    );
    await _checkAssetRefs(a, _assets, _wallets);
    await _assets.save(a);
    return a;
  });
}

/// Full edit (keeps archived/sortOrder; a missing manual price keeps the
/// current one).
final class UpdateAsset {
  const UpdateAsset(this._assets, this._wallets, this._clock);
  final AssetRepository _assets;
  final WalletRepository _wallets;
  final Clock _clock;

  Future<Result<Asset>> call(String id, AssetInput input) => guard(() async {
    final e = await _requireAsset(_assets, id);
    var a = _buildAsset(
      id,
      input,
      createdAt: e.createdAt,
      now: _clock.now(),
      archived: e.archived,
      sortOrder: e.sortOrder,
    );
    if (input.manualPrice == null && e.manualPrice != null) {
      a = a.copyWith(
        manualPrice: e.manualPrice,
        manualPriceAt: e.manualPriceAt,
      );
    }
    await _checkAssetRefs(a, _assets, _wallets);
    await _assets.save(a);
    return a;
  });
}

/// "Update harga" of a manual asset (fund NAV, gold per gram): per unit,
/// [at] default now.
final class UpdateManualPrice {
  const UpdateManualPrice(this._assets, this._clock);
  final AssetRepository _assets;
  final Clock _clock;

  Future<Result<Asset>> call(String id, double price, {DateTime? at}) =>
      guard(() async {
        final a = await _requireAsset(_assets, id);
        final now = _clock.now();
        if (!price.isFinite || price < 0) {
          throw const ValidationFailure(
            'Harga tidak boleh negatif',
            field: 'manualPrice',
          );
        }
        final u = a.copyWith(
          manualPrice: price,
          manualPriceAt: at ?? now,
          updatedAt: now,
        );
        await _assets.save(u);
        return u;
      });
}

final class SetAssetArchived {
  const SetAssetArchived(this._assets, this._clock);
  final AssetRepository _assets;
  final Clock _clock;

  Future<Result<Asset>> call(String id, bool archived) => guard(() async {
    final a = await _requireAsset(_assets, id);
    if (a.archived == archived) return a;
    final u = a.copyWith(archived: archived, updatedAt: _clock.now());
    await _assets.save(u);
    return u;
  });
}

/// `sortOrder` = index of each id.
final class ReorderAssets {
  const ReorderAssets(this._assets, this._uow, this._clock);
  final AssetRepository _assets;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final a = await _assets.getById(id);
        if (a == null || a.sortOrder == i) continue;
        await _assets.save(a.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// Deletes an asset with all its trades and (like the server) their linked
/// wallet transactions — balances move back. Archive is the non-destructive
/// option (say so in the confirm dialog). [deleteCashTransactions] false
/// keeps the transactions locally (the server still deletes them — only for
/// tests/tools). All-or-nothing.
final class DeleteAsset {
  const DeleteAsset(
    this._assets,
    this._trades,
    this._deleteTx,
    this._txRepo,
    this._uow,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final DeleteTransaction _deleteTx;
  final TransactionRepository _txRepo;
  final UnitOfWork _uow;

  Future<Result<void>> call(String id, {bool deleteCashTransactions = true}) =>
      guard(
        () => _uow.run(() async {
          await _requireAsset(_assets, id);
          final txs = [
            if (deleteCashTransactions)
              for (final t in await _trades.getAll(assetId: id))
                ?t.cashTransactionId,
          ];
          // The asset's delete first (its trades go with it, locally and on
          // the server — which also removes their transactions); the queued
          // transaction deletes are then idempotent there but move the
          // balances here at once.
          await _assets.delete(id);
          for (final tx in txs) {
            if (await _txRepo.getById(tx) != null) {
              (await _deleteTx(tx)).valueOrThrow;
            }
          }
        }),
      );
}

/// Validates a ticker with the server's price service (online only): the
/// symbol's info (name, price) or null when unknown. `NetworkFailure`
/// offline — let the user add it anyway.
final class LookupSymbol {
  const LookupSymbol(this._prices);
  final PriceRepository _prices;

  Future<Result<SymbolInfo?>> call(AssetKind kind, String symbol) =>
      guard(() async {
        final s = requireAssetSymbol(kind, symbol);
        if (!kind.supportsAutoPrice) {
          return SymbolInfo(kind: kind, symbol: s);
        }
        return _prices.lookup(kind, s);
      });
}

// ---------------------------------------------------------------- trades

/// Records a trade. Cash effect (default ON when a wallet is known): buy →
/// `investment −(q·p + fee)`, sell → `investment +(q·p − fee)`, fee →
/// `investment −amount`, dividend → income in "Dividen"; the transaction is
/// created through `CreateTransaction` and linked (`cashTransactionId`).
/// Sells beyond the holding (at the trade's date, in date order) →
/// `ValidationFailure(field: 'quantity')`. All-or-nothing.
final class CreateTrade {
  const CreateTrade(
    this._assets,
    this._trades,
    this._cash,
    this._uow,
    this._clock,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final TradeCashEffect _cash;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<TradeView>> call(TradeInput input) => guard(
    () => _uow.run(() async {
      final a = await _requireAsset(_assets, input.assetId);
      final now = _clock.now();
      var t = _buildTrade(newId(), input, createdAt: now, now: now);
      _guard(await _trades.getAll(assetId: a.id), t.id, t);
      final wallet = optionalId(input.walletId) ?? a.walletId;
      final tx = await _cash.apply(
        a,
        t,
        enabled: input.cashEffect ?? wallet != null,
        walletId: wallet,
      );
      t = t.copyWith(cashTransactionId: tx?.id);
      await _trades.save(t);
      return TradeView(trade: t, transaction: tx);
    }),
  );
}

/// Edits a trade; its linked transaction is updated / created / deleted to
/// match (see [TradeInput.cashEffect]). The asset can't change.
final class UpdateTrade {
  const UpdateTrade(
    this._assets,
    this._trades,
    this._txRepo,
    this._cash,
    this._uow,
    this._clock,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final TransactionRepository _txRepo;
  final TradeCashEffect _cash;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<TradeView>> call(String id, TradeInput input) => guard(
    () => _uow.run(() async {
      final e = await _requireTrade(_trades, id);
      final a = await _requireAsset(_assets, e.assetId);
      if (input.assetId != e.assetId) {
        throw const ValidationFailure(
          'Aset transaksi tidak bisa diganti',
          field: 'assetId',
        );
      }
      final linked = e.cashTransactionId == null
          ? null
          : await _txRepo.getById(e.cashTransactionId!);
      var t = _buildTrade(
        id,
        input,
        createdAt: e.createdAt,
        now: _clock.now(),
        cashTransactionId: linked?.id,
      );
      _guard(await _trades.getAll(assetId: a.id), id, t);
      final wallet = optionalId(input.walletId);
      final tx = await _cash.apply(
        a,
        t,
        enabled: input.cashEffect ?? linked != null,
        walletId: wallet ?? linked?.walletId ?? a.walletId,
      );
      t = t.copyWith(cashTransactionId: tx?.id);
      await _trades.save(t);
      return TradeView(trade: t, transaction: tx);
    }),
  );
}

/// Deletes a trade and its linked transaction (balance moves back). Never
/// refused (like the server: a later oversell is clamped and reported in
/// `Holding.issues`). The trade's delete is queued before the transaction's
/// (docs/mobile-sync.md). All-or-nothing.
final class DeleteTrade {
  const DeleteTrade(this._trades, this._txRepo, this._deleteTx, this._uow);
  final AssetTradeRepository _trades;
  final TransactionRepository _txRepo;
  final DeleteTransaction _deleteTx;
  final UnitOfWork _uow;

  Future<Result<void>> call(String id) => guard(
    () => _uow.run(() async {
      final t = await _requireTrade(_trades, id);
      await _trades.delete(id);
      final tx = t.cashTransactionId;
      if (tx != null && await _txRepo.getById(tx) != null) {
        (await _deleteTx(tx)).valueOrThrow;
      }
    }),
  );
}

/// Builds the trade use cases' shared cash-effect helper.
({CreateTrade create, UpdateTrade update, DeleteTrade delete}) tradeUseCases({
  required AssetRepository assets,
  required AssetTradeRepository trades,
  required TransactionRepository transactions,
  required CreateTransaction createTx,
  required UpdateTransaction updateTx,
  required DeleteTransaction deleteTx,
  required EnsureDividendCategory dividendCategory,
  required UnitOfWork uow,
  required Clock clock,
}) {
  final cash = TradeCashEffect(
    transactions,
    createTx,
    updateTx,
    deleteTx,
    dividendCategory,
  );
  return (
    create: CreateTrade(assets, trades, cash, uow, clock),
    update: UpdateTrade(assets, trades, transactions, cash, uow, clock),
    delete: DeleteTrade(trades, transactions, deleteTx, uow),
  );
}

// ---------------------------------------------------------------- prices

/// Fetches the prices of every auto-priced, non-archived asset (online only)
/// and records today's portfolio snapshot. `NetworkFailure` offline (cached
/// prices stay).
final class RefreshPrices {
  const RefreshPrices(this._assets, this._prices, this._snapshot);
  final AssetRepository _assets;
  final PriceRepository _prices;
  final RecordPortfolioSnapshot _snapshot;

  Future<Result<PriceRefreshResult>> call() => guard(() async {
    final keys = autoPriceKeys(await _assets.getAll());
    final r = keys.isEmpty
        ? const PriceRefreshResult(updated: [])
        : await _prices.refresh(keys);
    await _snapshot();
    return r;
  });
}

/// Stores today's value/cost point of the portfolio (device-only history).
final class RecordPortfolioSnapshot {
  const RecordPortfolioSnapshot(
    this._assets,
    this._trades,
    this._prices,
    this._snapshots,
    this._clock,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final PriceRepository _prices;
  final PortfolioSnapshotRepository _snapshots;
  final Clock _clock;

  Future<void> call() async {
    final now = _clock.now();
    final p = buildPortfolio(
      assets: await _assets.getAll(),
      trades: await _trades.getAll(),
      prices: await _prices.getCached(),
      now: now,
    );
    if (p.isEmpty) return;
    await _snapshots.put(snapshotOf(p, now), now);
  }
}

/// Keeps prices fresh while a portfolio screen (or the home card) is shown:
/// refreshes on [start] and then — on each tick — every 15 min during IDX
/// hours (Mon–Fri 09:00–16:15 WIB). Crypto-only portfolios refresh every
/// 15 min around the clock. Failures (offline) are ignored; the next tick
/// retries after the interval.
final class PriceAutoRefresher {
  PriceAutoRefresher(this._refresh, this._assets, this._ticks, this._clock);
  final RefreshPrices _refresh;
  final AssetRepository _assets;
  final TickSource _ticks;
  final Clock _clock;

  StreamSubscription<DateTime>? _sub;
  DateTime? _last;
  bool _busy = false;

  /// Last attempt (success or not).
  DateTime? get lastAttempt => _last;

  void start() {
    if (_sub != null) return;
    unawaited(_run());
    _sub = _ticks().listen((_) => _maybe());
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _maybe() async {
    final now = _clock.now();
    final last = _last;
    if (last != null && now.difference(last) < priceTtl) return;
    final List<Asset> assets;
    try {
      assets = await _assets.getAll();
    } catch (_) {
      return; // database closing (sign-out) — the next tick retries
    }
    final crypto = assets.any(
      (a) => !a.archived && !a.isManual && a.kind == AssetKind.crypto,
    );
    if (!isIdxSessionOpen(now) && !crypto) return;
    await _run();
  }

  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    _last = _clock.now();
    try {
      await _refresh();
    } finally {
      _busy = false;
    }
  }
}

// ---------------------------------------------------------------- watch

/// Assets in order (archived only with [includeArchived]).
final class WatchAssets {
  const WatchAssets(this._assets);
  final AssetRepository _assets;

  Stream<List<Asset>> call({bool includeArchived = false}) =>
      _assets.watchAll().map(
        (all) => [
          for (final a in all)
            if (includeArchived || !a.archived) a,
        ],
      );
}

/// The portfolio: holdings valued at cached prices, totals, allocation,
/// staleness (re-evaluated every minute).
final class WatchPortfolio {
  const WatchPortfolio(
    this._assets,
    this._trades,
    this._prices,
    this._ticks,
    this._clock,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final PriceRepository _prices;
  final TickSource _ticks;
  final Clock _clock;

  Stream<PortfolioSummary> call() => combineLatest4(
    _assets.watchAll(),
    _trades.watch(),
    _prices.watchCached(),
    _ticks(),
    (List<Asset> a, List<AssetTrade> t, Map<String, SecurityPrice> p, _) =>
        buildPortfolio(assets: a, trades: t, prices: p, now: _clock.now()),
  ).distinct();
}

/// Asset detail: valued holding, trades newest first (each with its linked
/// transaction), cached price. Null when deleted.
final class WatchAssetDetail {
  const WatchAssetDetail(
    this._assets,
    this._trades,
    this._prices,
    this._txRepo,
    this._ticks,
    this._clock,
  );
  final AssetRepository _assets;
  final AssetTradeRepository _trades;
  final PriceRepository _prices;
  final TransactionRepository _txRepo;
  final TickSource _ticks;
  final Clock _clock;

  Stream<AssetDetail?> call(String id) => combineLatestList(
    [
      _assets.watchById(id),
      _trades.watch(assetId: id),
      _prices.watchCached(),
      _txRepo.watch(type: TxType.investment),
      _txRepo.watch(type: TxType.income),
      _ticks(),
    ],
    (v) {
      final a = v[0] as Asset?;
      if (a == null) return null;
      final trades = v[1] as List<AssetTrade>;
      final prices = v[2] as Map<String, SecurityPrice>;
      final txs = {
        for (final t in [
          ...v[3] as List<Transaction>,
          ...v[4] as List<Transaction>,
        ])
          t.id: t,
      };
      final price = prices[a.priceKey];
      return AssetDetail(
        view: holdingViewOf(a, trades, price, _clock.now()),
        trades: [
          for (final t in sortTrades(trades).reversed)
            TradeView(
              trade: t,
              transaction: t.cashTransactionId == null
                  ? null
                  : txs[t.cashTransactionId],
            ),
        ],
        price: a.isManual ? null : price,
      );
    },
  ).distinct();
}

/// Value history for the chart: stored daily snapshots in [from]…[to] with
/// today's point replaced by the live value.
final class WatchPortfolioHistory {
  const WatchPortfolioHistory(this._snapshots, this._portfolio, this._clock);
  final PortfolioSnapshotRepository _snapshots;
  final WatchPortfolio _portfolio;
  final Clock _clock;

  Stream<List<PortfolioPoint>> call(
    String from,
    String to,
  ) => combineLatest2(_snapshots.watchRange(from, to), _portfolio(), (
    List<PortfolioPoint> pts,
    PortfolioSummary p,
  ) {
    final today = dateKey(_clock.now());
    final out = [
      for (final x in pts)
        if (x.date != today) x,
    ];
    if (!p.isEmpty && today.compareTo(from) >= 0 && today.compareTo(to) <= 0) {
      out.add(PortfolioPoint(date: today, value: p.marketValue, cost: p.cost));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }).distinct(_listEq);
}

bool _listEq(List<PortfolioPoint> a, List<PortfolioPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Net worth = Σ non-archived wallet balances (pending included) + portfolio
/// market value.
final class WatchNetWorth {
  const WatchNetWorth(this._wallets, this._portfolio);
  final WalletRepository _wallets;
  final WatchPortfolio _portfolio;

  Stream<NetWorth> call() => combineLatest2(
    _wallets.watchAll(includeArchived: false),
    _portfolio(),
    (List<Wallet> w, PortfolioSummary p) => NetWorth(
      wallets: w.fold(0, (s, x) => s + x.balance),
      investments: p.marketValue,
    ),
  ).distinct();
}
