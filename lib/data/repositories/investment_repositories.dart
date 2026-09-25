import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/local/app_database.dart';
import '../datasources/remote/prices_api.dart';
import '../models/entity_names.dart';
import '../models/habits_investments_mappers.dart';
import '../models/habits_investments_wire.dart';
import 'local_store.dart';

class DriftAssetRepository implements AssetRepository {
  DriftAssetRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$AssetsTable, AssetRow> get _all =>
      _db.select(_db.assets)..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.symbol),
      ]);

  @override
  Stream<List<Asset>> watchAll() =>
      _all.watch().map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<List<Asset>> getAll() async => [
    for (final x in await _all.get()) x.toEntity(),
  ];

  @override
  Stream<Asset?> watchById(String id) =>
      (_db.select(_db.assets)..where((a) => a.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntity());

  @override
  Future<Asset?> getById(String id) async => (await (_db.select(
    _db.assets,
  )..where((a) => a.id.equals(id))).getSingleOrNull())?.toEntity();

  @override
  Future<Asset?> findBySymbol(AssetKind kind, String symbol) async =>
      (await (_db.select(_db.assets)
                ..where(
                  (a) =>
                      a.kind.equals(kind.wire) &
                      a.symbol.upper().equals(symbol.toUpperCase()),
                )
                ..limit(1))
              .getSingleOrNull())
          ?.toEntity();

  @override
  Future<void> save(Asset asset) => _s.write(() async {
    final exists = await getById(asset.id) != null;
    await _db.into(_db.assets).insertOnConflictUpdate(asset.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.assets,
      entityId: asset.id,
      data: assetToWire(asset),
      clientUpdatedAt: asset.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.assets,
    )..where((a) => a.id.equals(id))).go();
    if (n == 0) return;
    await _s.cascades.assetDeleted(id);
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.assets,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

class DriftAssetTradeRepository implements AssetTradeRepository {
  DriftAssetTradeRepository(this._s);
  final LocalStore _s;
  AppDatabase get _db => _s.db;

  SimpleSelectStatement<$AssetTradesTable, AssetTradeRow> _q({
    String? assetId,
  }) {
    final q = _db.select(_db.assetTrades)
      ..where((t) => t.type.isIn([for (final x in TradeType.values) x.wire]))
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    if (assetId != null) q.where((t) => t.assetId.equals(assetId));
    return q;
  }

  static List<AssetTrade> _map(List<AssetTradeRow> rows) => [
    for (final r in rows) ?r.toEntityOrNull(),
  ];

  @override
  Stream<List<AssetTrade>> watch({String? assetId}) =>
      _q(assetId: assetId).watch().map(_map);

  @override
  Future<List<AssetTrade>> getAll({String? assetId}) async =>
      _map(await _q(assetId: assetId).get());

  @override
  Stream<AssetTrade?> watchById(String id) =>
      (_db.select(_db.assetTrades)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toEntityOrNull());

  @override
  Future<AssetTrade?> getById(String id) async => (await (_db.select(
    _db.assetTrades,
  )..where((t) => t.id.equals(id))).getSingleOrNull())?.toEntityOrNull();

  @override
  Future<void> save(AssetTrade trade) => _s.write(() async {
    final exists = await getById(trade.id) != null;
    await _db.into(_db.assetTrades).insertOnConflictUpdate(trade.toCompanion());
    await _s.outbox.enqueueUpsert(
      entity: SyncEntity.assetTrades,
      entityId: trade.id,
      data: assetTradeToWire(trade),
      clientUpdatedAt: trade.updatedAt,
      isCreate: !exists,
    );
  });

  @override
  Future<void> delete(String id) => _s.write(() async {
    final n = await (_db.delete(
      _db.assetTrades,
    )..where((t) => t.id.equals(id))).go();
    if (n == 0) return;
    await _s.outbox.enqueueDelete(
      entity: SyncEntity.assetTrades,
      entityId: id,
      clientUpdatedAt: _s.clock.now(),
    );
  });
}

/// Prices from the server, cached in drift for offline display.
class DriftPriceRepository implements PriceRepository {
  DriftPriceRepository(
    this._db,
    this._api, [
    this._clock = const SystemClock(),
  ]);
  final AppDatabase _db;
  final PricesApi _api;
  final Clock _clock;

  static Map<String, SecurityPrice> _map(List<CachedPriceRow> rows) => {
    for (final r in rows) r.key: r.toEntity(),
  };

  @override
  Stream<Map<String, SecurityPrice>> watchCached() =>
      _db.select(_db.cachedPrices).watch().map(_map);

  @override
  Future<Map<String, SecurityPrice>> getCached() async =>
      _map(await _db.select(_db.cachedPrices).get());

  Future<void> _store(Iterable<SecurityPrice> prices) =>
      _db.transaction(() async {
        for (final p in prices) {
          await _db
              .into(_db.cachedPrices)
              .insertOnConflictUpdate(p.toCompanion());
        }
      });

  @override
  Future<PriceRefreshResult> refresh(List<String> keys) async {
    final wanted = keys.toSet().toList()..sort();
    if (wanted.isEmpty) return const PriceRefreshResult(updated: []);
    final r = await _api.fetch(wanted);
    await _store(r.prices.values);
    return PriceRefreshResult(
      updated: r.prices.keys.toList()..sort(),
      notFound: r.notFound,
      at: _clock.now(),
    );
  }

  @override
  Future<SymbolInfo?> lookup(AssetKind kind, String symbol) async {
    final key = priceKeyOf(kind, symbol);
    final r = await _api.fetch([key]);
    final p = r.prices[key];
    if (p == null) return null;
    await _store([p]);
    return SymbolInfo(kind: kind, symbol: symbol, name: p.name, price: p);
  }
}

class DriftPortfolioSnapshotRepository implements PortfolioSnapshotRepository {
  DriftPortfolioSnapshotRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<PortfolioPoint>> watchRange(String from, String to) =>
      (_db.select(_db.portfolioSnapshots)
            ..where((s) => s.date.isBetweenValues(from, to))
            ..orderBy([(s) => OrderingTerm.asc(s.date)]))
          .watch()
          .map((r) => [for (final x in r) x.toEntity()]);

  @override
  Future<void> put(PortfolioPoint point, DateTime at) => _db
      .into(_db.portfolioSnapshots)
      .insertOnConflictUpdate(
        PortfolioSnapshotsCompanion.insert(
          date: isDateKey(point.date) ? point.date : dateKey(at),
          value: point.value,
          cost: point.cost,
          updatedAt: at,
        ),
      );
}
