import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/usecases/investment_rules.dart' show tradeCashEffect;
import '../datasources/local/app_database.dart';
import '../models/entity_names.dart';
import '../models/habits_investments_mappers.dart';
import '../models/habits_investments_wire.dart';
import '../models/mappers.dart';
import '../models/wire.dart';
import 'local_cascades.dart';
import 'outbox.dart';

/// The sync engine's hooks for `habits`, `habitLogs`, `assets` and
/// `assetTrades` (`docs/mobile-sync.md`), kept out of `sync_engine.dart`:
///
/// - habit logs: a `duplicate` push or a pulled row holding the unique key
///   (habitId, date, type) of a local pending row → the local row is dropped
///   and its value merged into the server's (counts add up, triggers are
///   united) and pushed; an asset with
///   the same (kind, symbol) as a local one → the local one is dropped and
///   its trades move to the pulled asset);
/// - `duplicate` asset pushes → the asset's trades move to the server's
///   asset after the pull (their push, rejected meanwhile for the unknown
///   asset, is re-queued);
/// - `rejected` trade pushes (e.g. a sell beyond the holding after another
///   device's edit) → after the pull restored the server's version, the
///   linked cash transaction is made to match it again (deleted when the
///   server never had the trade). The server's message reaches the user via
///   the sync status like every rejection.
class HabitsInvestmentsSync {
  HabitsInvestmentsSync(this._db, this._outbox, this._cascades, this._clock);

  final AppDatabase _db;
  final Outbox _outbox;
  final LocalCascades _cascades;
  final Clock _clock;

  /// Local asset id → (kind, symbol), for assets that lost a clash.
  final _assetRemaps = <String, ({String kind, String symbol})>{};

  /// Trades whose push was rejected: id → linked transaction id (before).
  final _rejectedTrades = <String, String?>{};

  /// Local habit logs that lost their unique key to a server row: merged
  /// into it after the pull.
  final _logMerges = <HabitLog>[];

  TableInfo<Table, dynamic>? table(String entity) => switch (entity) {
    SyncEntity.habits => _db.habits,
    SyncEntity.habitLogs => _db.habitLogs,
    SyncEntity.assets => _db.assets,
    SyncEntity.assetTrades => _db.assetTrades,
    _ => null,
  };

  // ---------------------------------------------------------------- push

  /// A `duplicate` answer (before the engine deletes the local row).
  Future<void> onDuplicate(OutboxRow entry) async {
    if (entry.entity == SyncEntity.habitLogs) {
      final l = await (_db.select(
        _db.habitLogs,
      )..where((x) => x.id.equals(entry.entityId))).getSingleOrNull();
      if (l?.toEntityOrNull() case final log?) _logMerges.add(log);
      return;
    }
    if (entry.entity != SyncEntity.assets) return;
    final a = await (_db.select(
      _db.assets,
    )..where((x) => x.id.equals(entry.entityId))).getSingleOrNull();
    if (a != null) _assetRemaps[a.id] = (kind: a.kind, symbol: a.symbol);
  }

  /// A rejected trade of an asset that lost a clash: it moves to the
  /// server's asset after the pull (kept locally, not reverted).
  Future<bool> isRemappedTrade(OutboxRow entry) async {
    if (entry.entity != SyncEntity.assetTrades || _assetRemaps.isEmpty) {
      return false;
    }
    final t = await (_db.select(
      _db.assetTrades,
    )..where((x) => x.id.equals(entry.entityId))).getSingleOrNull();
    return t != null && _assetRemaps.containsKey(t.assetId);
  }

  /// A `rejected` answer (before the engine deletes the local row).
  Future<void> onRejected(OutboxRow entry) async {
    if (entry.entity != SyncEntity.assetTrades) return;
    final t = await (_db.select(
      _db.assetTrades,
    )..where((x) => x.id.equals(entry.entityId))).getSingleOrNull();
    final data = Outbox.decode(entry.data);
    _rejectedTrades[entry.entityId] =
        t?.cashTransactionId ?? data?['cashTransactionId'] as String?;
  }

  // ---------------------------------------------------------------- pull

  /// Local ids a full pull must not delete (trades waiting to move).
  Future<Set<String>> keepOnFullPull(String entity) async {
    if (entity != SyncEntity.assetTrades || _assetRemaps.isEmpty) {
      return const {};
    }
    return {
      for (final t in await (_db.select(
        _db.assetTrades,
      )..where((t) => t.assetId.isIn(_assetRemaps.keys))).get())
        t.id,
    };
  }

  /// Tombstone cascades.
  Future<void> onTombstone(String entity, String id) async {
    if (entity == SyncEntity.habits) await _cascades.habitDeleted(id);
    if (entity == SyncEntity.assets) await _cascades.assetDeleted(id);
  }

  /// Applies a pulled row of one of the four entities; false for others.
  Future<bool> upsertPulled(String entity, Json j) async {
    final id = j['id'] as String;
    switch (entity) {
      case SyncEntity.habits:
        await _db
            .into(_db.habits)
            .insertOnConflictUpdate(habitFromWire(j).toCompanion());
        return true;
      case SyncEntity.habitLogs:
        final log = habitLogFromWire(j);
        if (log == null) return true; // unknown type (newer server)
        final clash =
            await (_db.select(_db.habitLogs)..where(
                  (l) =>
                      l.habitId.equals(log.habitId) &
                      l.date.equals(log.date) &
                      l.type.equals(log.type.wire) &
                      l.id.equals(id).not(),
                ))
                .get();
        for (final c in clash) {
          if (await _outbox.hasAny(SyncEntity.habitLogs, c.id)) {
            if (c.toEntityOrNull() case final local?) _logMerges.add(local);
          }
          await _outbox.dropQueued(SyncEntity.habitLogs, c.id);
          await _delete(_db.habitLogs, c.id);
        }
        await _db.into(_db.habitLogs).insertOnConflictUpdate(log.toCompanion());
        return true;
      case SyncEntity.assets:
        final asset = assetFromWire(j);
        final clash =
            await (_db.select(_db.assets)..where(
                  (a) =>
                      a.kind.equals(asset.kind.wire) &
                      a.symbol.upper().equals(asset.symbol.toUpperCase()) &
                      a.id.equals(id).not(),
                ))
                .get();
        for (final c in clash) {
          _assetRemaps[c.id] = (kind: c.kind, symbol: c.symbol);
          await _outbox.dropQueued(SyncEntity.assets, c.id);
          await _delete(_db.assets, c.id);
        }
        await _db.into(_db.assets).insertOnConflictUpdate(asset.toCompanion());
        return true;
      case SyncEntity.assetTrades:
        final trade = assetTradeFromWire(j);
        if (trade != null) {
          await _db
              .into(_db.assetTrades)
              .insertOnConflictUpdate(trade.toCompanion());
        }
        return true;
      default:
        return false;
    }
  }

  /// After a pull: move trades of clashed assets, reconcile rejected trades.
  Future<void> afterPull() async {
    var wrote = false;
    if (_logMerges.isNotEmpty) wrote |= await _applyLogMerges();
    if (_assetRemaps.isNotEmpty) wrote |= await _applyAssetRemaps();
    if (_rejectedTrades.isNotEmpty) wrote |= await _reconcileRejected();
    if (wrote) _outbox.notifyLocalWrite();
  }

  /// Merges each lost local log into the row now holding its key: relapse /
  /// urge counts and count/duration progress add up (check / clean check-in
  /// stay 1), triggers are united, the server's note wins (else ours), the
  /// latest `at` wins.
  Future<bool> _applyLogMerges() async {
    final merges = List.of(_logMerges);
    _logMerges.clear();
    var wrote = false;
    await _db.transaction(() async {
      for (final local in merges) {
        final row =
            await (_db.select(_db.habitLogs)..where(
                  (l) =>
                      l.habitId.equals(local.habitId) &
                      l.date.equals(local.date) &
                      l.type.equals(local.type.wire) &
                      l.id.equals(local.id).not(),
                ))
                .getSingleOrNull();
        final server = row?.toEntityOrNull();
        if (server == null) continue;
        final habit =
            (await (_db.select(
                  _db.habits,
                )..where((h) => h.id.equals(local.habitId))).getSingleOrNull())
                ?.toEntity();
        final adds =
            local.type == HabitLogType.relapse ||
            local.type == HabitLogType.urge ||
            (local.type == HabitLogType.done &&
                habit != null &&
                habit.isBuild &&
                !habit.target.isCheck);
        final value = adds
            ? (server.value ?? (local.type == HabitLogType.done ? 0 : 1)) +
                  (local.value ?? (local.type == HabitLogType.done ? 0 : 1))
            : server.value;
        final at = server.at == null
            ? local.at
            : (local.at != null && local.at!.isAfter(server.at!)
                  ? local.at
                  : server.at);
        final merged = server.copyWith(
          value: value,
          triggers: [
            ...server.triggers,
            for (final t in local.triggers)
              if (!server.triggers.any(
                (x) => x.toLowerCase() == t.toLowerCase(),
              ))
                t,
          ].take(10).toList(),
          note: server.note ?? local.note,
          at: at,
          updatedAt: _clock.now(),
        );
        if (merged == server) continue;
        await _db
            .into(_db.habitLogs)
            .insertOnConflictUpdate(merged.toCompanion());
        await _outbox.enqueueUpsert(
          entity: SyncEntity.habitLogs,
          entityId: merged.id,
          data: habitLogToWire(merged),
          clientUpdatedAt: merged.updatedAt,
          isCreate: false,
        );
        wrote = true;
      }
    });
    return wrote;
  }

  Future<bool> _applyAssetRemaps() async {
    final remaps = Map.of(_assetRemaps);
    _assetRemaps.clear();
    var moved = false;
    await _db.transaction(() async {
      for (final MapEntry(key: oldId, value: k) in remaps.entries) {
        final target =
            await (_db.select(_db.assets)
                  ..where(
                    (a) =>
                        a.kind.equals(k.kind) &
                        a.symbol.upper().equals(k.symbol.toUpperCase()) &
                        a.id.equals(oldId).not(),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (target == null) continue;
        final rows = await (_db.select(
          _db.assetTrades,
        )..where((t) => t.assetId.equals(oldId))).get();
        for (final r in rows) {
          final t = r.toEntityOrNull()?.copyWith(
            assetId: target.id,
            updatedAt: _clock.now(),
          );
          if (t == null) continue;
          await _db
              .into(_db.assetTrades)
              .insertOnConflictUpdate(t.toCompanion());
          await _outbox.enqueueUpsert(
            entity: SyncEntity.assetTrades,
            entityId: t.id,
            data: assetTradeToWire(t),
            clientUpdatedAt: t.updatedAt,
            isCreate: false,
          );
          moved = true;
        }
      }
    });
    return moved;
  }

  Future<bool> _reconcileRejected() async {
    final rejected = Map.of(_rejectedTrades);
    _rejectedTrades.clear();
    var wrote = false;
    await _db.transaction(() async {
      for (final MapEntry(key: tradeId, value: txId) in rejected.entries) {
        if (await _outbox.hasAny(SyncEntity.assetTrades, tradeId)) continue;
        final row = await (_db.select(
          _db.assetTrades,
        )..where((t) => t.id.equals(tradeId))).getSingleOrNull();
        final trade = row?.toEntityOrNull();
        if (trade == null || trade.cashTransactionId != txId) {
          // The server never had this trade (or links another transaction):
          // our cash transaction has nothing behind it any more.
          if (txId != null) wrote |= await _deleteTx(txId);
          if (trade?.cashTransactionId case final other?) {
            wrote |= await _matchTx(trade!, other);
          }
          continue;
        }
        if (txId != null) wrote |= await _matchTx(trade, txId);
      }
    });
    return wrote;
  }

  /// Makes transaction [txId] carry [trade]'s cash effect again.
  Future<bool> _matchTx(AssetTrade trade, String txId) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(txId))).getSingleOrNull();
    final tx = row?.toEntityOrNull();
    final effect = tradeCashEffect(trade);
    if (tx == null || effect == null) return false;
    final (:type, :amount) = effect;
    if (tx.type == type && tx.amount == amount && tx.date == trade.date) {
      return false;
    }
    final before = transactionToWire(tx);
    final fixed = Transaction(
      id: tx.id,
      walletId: tx.walletId,
      categoryId: type == TxType.income ? tx.categoryId : null,
      type: type,
      amount: amount,
      note: tx.note,
      date: trade.date,
      createdAt: tx.createdAt,
      updatedAt: _clock.now(),
      photos: tx.photos,
    );
    await _db
        .into(_db.transactions)
        .insertOnConflictUpdate(fixed.toCompanion());
    await _outbox.enqueueUpsert(
      entity: SyncEntity.transactions,
      entityId: tx.id,
      data: transactionToWire(fixed),
      clientUpdatedAt: fixed.updatedAt,
      isCreate: false,
      base: before,
    );
    return true;
  }

  Future<bool> _deleteTx(String txId) async {
    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(txId))).getSingleOrNull();
    final tx = row?.toEntityOrNull();
    if (row == null || tx == null) return false;
    await _delete(_db.transactions, txId);
    await _cascades.transactionDeleted(txId);
    await _outbox.enqueueDelete(
      entity: SyncEntity.transactions,
      entityId: txId,
      clientUpdatedAt: _clock.now(),
      base: transactionToWire(tx),
    );
    return true;
  }

  Future<void> _delete(TableInfo<Table, dynamic> table, String id) =>
      _db.customUpdate(
        'DELETE FROM ${table.actualTableName} WHERE id = ?',
        variables: [Variable.withString(id)],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
}
