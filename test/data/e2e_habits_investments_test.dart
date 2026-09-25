// End-to-end: habits and investments through the real mobile data layer
// (drift in memory, outbox, sync engine, repositories, use cases) on two
// simulated devices against the REAL server (docs/habits.md,
// docs/investments.md, docs/mobile-sync.md "Habits" / "Assets").
// Skipped unless GHINA_E2E_BASE_URL is set:
//   (cd .. && npx next dev -p 3100)
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_habits_investments_test.dart
// Throwaway users `mobile-test-dart-hi-*@example.test` and the seeded
// `ZZE2E*` price cache rows are removed at the end (e2e-helper cleanup). The
// prices endpoint is only asked for seeded, fresh (or backing-off) symbols,
// so the server never calls Yahoo.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/prices_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/repositories/auth_repository_impl.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/habit_repositories.dart';
import 'package:ghina/data/repositories/investment_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

const _password = 'rahasia123';
const emailPrefix = 'mobile-test-dart-hi-';

/// The repo root (this test runs from `mobile/`).
final repoRoot = Directory.current.parent.path;

Future<Json> helper(String cmd, String arg) async {
  final r = await Process.run('node', [
    'scripts/e2e-helper.mjs',
    cmd,
    arg,
  ], workingDirectory: repoRoot);
  if (r.exitCode != 0) throw StateError('helper $cmd failed: ${r.stderr}');
  return (jsonDecode((r.stdout as String).trim().split('\n').last) as Map)
      .cast<String, dynamic>();
}

/// One simulated phone: its own in-memory database + the real data layer.
class Device {
  Device(String baseUrl, this.name) {
    api = ApiClient(baseUrl: baseUrl, tokens: tokens);
    syncApi = DioSyncApi(api);
    auth = AuthRepositoryImpl(api: AuthApi(api), tokens: tokens, db: db);
    engine = SyncEngine(
      db: db,
      outbox: outbox,
      api: syncApi,
      photos: photos,
      clock: clock,
    );
  }

  final String name;
  final tokens = MemoryTokenStore();
  late final ApiClient api;
  late final DioSyncApi syncApi;
  late final AuthRepositoryImpl auth;
  late final SyncEngine engine;
  final db = AppDatabase.memory();
  late final outbox = Outbox(db);
  final clock = const SystemClock();
  final photos = InMemoryPhotoStore();
  late final store = LocalStore(db, outbox, clock);
  late final wallets = DriftWalletRepository(store);
  late final categories = DriftCategoryRepository(store);
  late final txs = DriftTransactionRepository(store, photos);
  late final uow = DriftUnitOfWork(store);
  late final habits = DriftHabitRepository(store);
  late final habitLogs = DriftHabitLogRepository(store);
  late final assets = DriftAssetRepository(store);
  late final trades = DriftAssetTradeRepository(store);
  late final pricesApi = DioPricesApi(api, clock);
  late final prices = DriftPriceRepository(db, pricesApi, clock);

  late final createWallet = CreateWallet(wallets, clock);
  late final createTx = CreateTransaction(txs, wallets, categories, clock);
  late final updateTx = UpdateTransaction(txs, wallets, categories, clock);
  late final deleteTx = DeleteTransaction(txs);
  late final createHabit = CreateHabit(habits, clock);
  late final deleteHabit = DeleteHabit(habits);
  late final checkIn = CheckInHabit(habits, habitLogs, clock);
  late final skipDay = SkipHabitDay(habits, habitLogs, clock);
  late final logUrge = LogUrge(habits, habitLogs, clock);
  late final logRelapse = LogRelapse(habits, habitLogs, clock);
  late final createAsset = CreateAsset(assets, wallets, clock);

  /// Needs the signed-in user (the Dividen category id).
  Future<({CreateTrade create, UpdateTrade update, DeleteTrade delete})>
  tradeUc() async => tradeUseCases(
    assets: assets,
    trades: trades,
    transactions: txs,
    createTx: createTx,
    updateTx: updateTx,
    deleteTx: deleteTx,
    dividendCategory: EnsureDividendCategory(
      categories,
      clock,
      userId: (await db.getMeta()).userId,
    ),
    uow: uow,
    clock: clock,
  );

  Future<void> sync() async {
    await engine.syncNow();
    expect((await db.getMeta()).lastError, isNull, reason: '$name sync error');
  }

  /// Syncs until the outbox is empty (re-queued work, e.g. asset remaps).
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await sync();
      if ((await outbox.all()).isEmpty) return;
    }
    fail('$name outbox never drained: ${await outbox.all()}');
  }

  Future<PullResponse> server() => syncApi.pull(0);

  Future<double> balance(String walletId) async =>
      (await wallets.getById(walletId))!.balance;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

Map<String, Json> byId(List<Json>? rows) => {
  for (final r in rows ?? const <Json>[]) r['id'] as String: r,
};

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final skip = base == null ? 'set GHINA_E2E_BASE_URL to run' : false;
  final devices = <Device>[];
  var n = 0;

  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });
  tearDownAll(() async {
    if (base != null) await helper('cleanup', emailPrefix);
  });

  /// A fresh account with two signed-in devices (both synced once).
  Future<(Device, Device)> pair() async {
    final email =
        '$emailPrefix${DateTime.now().millisecondsSinceEpoch}-${n++}@example.test';
    final a = Device(base!, 'A');
    final b = Device(base, 'B');
    devices.addAll([a, b]);
    await a.auth.register(name: 'E2E', email: email, password: _password);
    await b.auth.signIn(email: email, password: _password);
    await a.sync();
    await b.sync();
    return (a, b);
  }

  String today() => dateKey(DateTime.now());
  DateTime daysAgo(int d) => addDays(DateTime.now(), -d);

  test(
    'habits: two devices, same-day counts merge, skips, urges, relapse, '
    'delete cascades',
    () async {
      final (a, b) = await pair();

      // ---- A creates a build (count) and a quit habit; B receives them.
      final water = (await a.createHabit(
        HabitInput(
          name: 'Minum air',
          emoji: '💧',
          target: HabitTarget.count(8, unit: 'gelas'),
          reminders: const ['21:30', '07:00'],
          startDate: daysAgo(20),
        ),
      )).valueOrThrow;
      final smoke = (await a.createHabit(
        HabitInput(
          name: 'Rokok',
          kind: HabitKind.quit,
          isPrivate: true,
          why: 'Biar napas lega',
          startDate: daysAgo(12),
        ),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      final bWater = (await b.habits.getById(water.id))!;
      expect(bWater.target, HabitTarget.count(8, unit: 'gelas'));
      expect(bWater.reminders, ['07:00', '21:30']);
      expect((await b.habits.getById(smoke.id))!.isPrivate, isTrue);

      // ---- Both check in offline on the same day: one row, counts add up.
      await a.checkIn(water.id, value: 3);
      await b.checkIn(water.id, value: 2);
      await a.settle();
      await b.settle(); // B's row is a duplicate → merged into A's and pushed
      await a.sync();
      final serverLogs = (await a.server()).changes[SyncEntity.habitLogs]!;
      final done = serverLogs
          .where((l) => l['habitId'] == water.id && l['type'] == 'done')
          .toList();
      expect(done, hasLength(1));
      expect(done.single['value'], 5);
      expect(done.single['date'], today());
      for (final d in [a, b]) {
        final l = (await d.habitLogs.findByKey(
          water.id,
          today(),
          HabitLogType.done,
        ))!;
        expect(l.value, 5, reason: d.name);
        expect(
          (await d.habitLogs.getAll(habitId: water.id)),
          hasLength(1),
          reason: '${d.name}: no second row',
        );
      }

      // ---- Skips: 2 per rolling 7 days is enforced on the device; sync
      // stores what it gets.
      expect((await a.skipDay(water.id, day: daysAgo(3))).isOk, isTrue);
      expect((await a.skipDay(water.id, day: daysAgo(2))).isOk, isTrue);
      final third = await a.skipDay(water.id, day: daysAgo(1));
      expect((third.failureOrNull as ValidationFailure).field, 'skip');
      // B didn't see A's skips yet: its own is allowed locally, and kept.
      expect((await b.skipDay(water.id, day: daysAgo(1))).isOk, isTrue);
      await a.settle();
      await b.settle();
      await a.sync();
      for (final d in [a, b]) {
        final skips = (await d.habitLogs.getAll(
          habitId: water.id,
        )).where((l) => l.type == HabitLogType.skip);
        expect(skips, hasLength(3), reason: d.name);
      }
      // Now A knows three skips in the window: a fourth is refused.
      expect(
        (await a.skipDay(water.id, day: daysAgo(4))).failureOrNull,
        isA<ValidationFailure>(),
      );

      // ---- Quit: urges on both devices add up; B relapses; A sees streak 0.
      await a.logUrge(smoke.id, triggers: const ['stres']);
      await a.logUrge(smoke.id, triggers: const ['Stres', 'malam']);
      await b.logUrge(smoke.id, triggers: const ['bosan']);
      await a.settle();
      await b.settle();
      await a.sync();
      final urge = (await a.habitLogs.findByKey(
        smoke.id,
        today(),
        HabitLogType.urge,
      ))!;
      expect(urge.value, 3);
      expect(urge.triggers.map((t) => t.toLowerCase()).toSet(), {
        'stres',
        'malam',
        'bosan',
      });
      final relapse = (await b.logRelapse(
        smoke.id,
        RelapseInput(
          day: daysAgo(1),
          triggers: const ['capek'],
          note: 'lembur',
        ),
      )).valueOrThrow;
      expect(relapse.previousStreak, 11, reason: 'clean from day −12 to −2');
      await b.settle();
      await a.sync();
      final aLogs = await a.habitLogs.getAll(habitId: smoke.id);
      final r = aLogs.firstWhere((l) => l.type == HabitLogType.relapse);
      expect(r.note, 'lembur');
      expect(r.date, dateKey(daysAgo(1)));
      final t = habitToday((await a.habits.getById(smoke.id))!, aLogs, today());
      expect(t.streak.current, 1, reason: 'today is the first clean day again');
      // Build habits can't relapse; quit habits can't skip.
      expect(
        (await a.logRelapse(water.id)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await a.skipDay(smoke.id)).failureOrNull,
        isA<ValidationFailure>(),
      );

      // ---- Deleting a habit on A removes its logs everywhere.
      expect((await a.deleteHabit(water.id)).isOk, isTrue);
      await a.settle();
      await b.sync();
      expect(await b.habits.getById(water.id), isNull);
      expect(await b.habitLogs.getAll(habitId: water.id), isEmpty);
      final after = await b.server();
      expect(byId(after.changes[SyncEntity.habits]).keys, [smoke.id]);
      expect(
        after.changes[SyncEntity.habitLogs]!.where(
          (l) => l['habitId'] == water.id,
        ),
        isEmpty,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'investments: duplicate asset merge, cash effects across devices, '
    'oversell rejection, delete reverses cash, dividend, prices',
    () async {
      final (a, b) = await pair();
      final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
      final stock = 'ZZE2E$stamp';
      final coin = 'ZZE2EC$stamp';

      // ---- A's RDN wallet reaches B.
      final rdn = (await a.createWallet(
        const WalletInput(
          name: 'RDN',
          type: WalletType.bank,
          initialBalance: 10000000,
        ),
      )).valueOrThrow.id;
      await a.settle();
      await b.sync();
      expect(await b.balance(rdn), 10000000);

      // ---- Both add the same stock offline, each with a buy (cash effect).
      final aAsset = (await a.createAsset(
        AssetInput(kind: AssetKind.stock, symbol: stock, walletId: rdn),
      )).valueOrThrow;
      final bAsset = (await b.createAsset(
        AssetInput(
          kind: AssetKind.stock,
          symbol: stock.toLowerCase(),
          walletId: rdn,
        ),
      )).valueOrThrow;
      expect(bAsset.symbol, stock);
      final aUc = await a.tradeUc();
      final bUc = await b.tradeUc();
      TradeInput buy(String assetId, double q, double p) => TradeInput(
        assetId: assetId,
        type: TradeType.buy,
        date: DateTime.now(),
        quantity: q,
        price: p,
        fee: 150,
      );
      final aBuy = (await aUc.create(buy(aAsset.id, 100, 1000))).valueOrThrow;
      final bBuy = (await bUc.create(buy(bAsset.id, 20, 1000))).valueOrThrow;
      expect(aBuy.transaction!.type, TxType.investment);
      expect(aBuy.transaction!.amount, -100150);
      expect(await a.balance(rdn), 10000000 - 100150);
      await a.settle();
      await b.settle(); // duplicate asset → B's trade moves to A's asset
      await a.sync();
      var server = await a.server();
      final serverAssets = byId(server.changes[SyncEntity.assets]);
      expect(serverAssets.keys, [aAsset.id], reason: 'one asset per symbol');
      final serverTrades = byId(server.changes[SyncEntity.assetTrades]);
      expect(serverTrades.keys.toSet(), {aBuy.trade.id, bBuy.trade.id});
      expect(serverTrades[bBuy.trade.id]!['assetId'], aAsset.id);
      expect(
        serverTrades[bBuy.trade.id]!['cashTransactionId'],
        bBuy.transaction!.id,
      );
      expect(await b.assets.getById(bAsset.id), isNull);
      expect((await b.trades.getById(bBuy.trade.id))!.assetId, aAsset.id);
      final serverBal =
          (byId(server.changes[SyncEntity.wallets])[rdn]!['balance'] as num)
              .toDouble();
      expect(serverBal, 10000000 - 100150 - 20150);
      expect(await a.balance(rdn), serverBal);
      expect(await b.balance(rdn), serverBal);

      // ---- Oversell on the device itself: refused, nothing written.
      final before = (await b.outbox.all()).length;
      final over = await bUc.create(
        TradeInput(
          assetId: aAsset.id,
          type: TradeType.sell,
          date: DateTime.now(),
          quantity: 121,
          price: 1000,
        ),
      );
      expect((over.failureOrNull as ValidationFailure).field, 'quantity');
      expect((await b.outbox.all()).length, before);

      // ---- Cross-device oversell: A shrinks its buy to 10 (and syncs first);
      // B, still seeing 120, sells 50 offline → the server rejects the sell,
      // B drops it and its cash transaction.
      await aUc
          .update(aBuy.trade.id, buy(aAsset.id, 10, 1000))
          .then((r) => r.valueOrThrow);
      final bSell = (await bUc.create(
        TradeInput(
          assetId: aAsset.id,
          type: TradeType.sell,
          date: DateTime.now(),
          quantity: 50,
          price: 1100,
          fee: 200,
        ),
      )).valueOrThrow;
      expect(bSell.transaction!.amount, 54800);
      await a.settle();
      await b.engine.syncNow();
      expect(
        (await b.engine.watchStatus().first).lastError,
        contains('melebihi kepemilikan'),
      );
      await b.settle(); // pushes the reverting transaction delete
      await a.sync();
      server = await a.server();
      expect(
        byId(
          server.changes[SyncEntity.assetTrades],
        ).containsKey(bSell.trade.id),
        isFalse,
      );
      expect(
        byId(
          server.changes[SyncEntity.transactions],
        ).containsKey(bSell.transaction!.id),
        isFalse,
      );
      expect(await b.trades.getById(bSell.trade.id), isNull);
      expect(await b.txs.getById(bSell.transaction!.id), isNull);
      expect((await b.trades.getById(aBuy.trade.id))!.quantity, 10);
      final bal2 =
          (byId(server.changes[SyncEntity.wallets])[rdn]!['balance'] as num)
              .toDouble();
      expect(bal2, 10000000 - 10150 - 20150);
      expect(await a.balance(rdn), bal2);
      expect(await b.balance(rdn), bal2);

      // ---- Deleting a trade (on B) moves the cash back everywhere.
      expect((await bUc.delete(bBuy.trade.id)).isOk, isTrue);
      expect(await b.balance(rdn), 10000000 - 10150);
      await b.settle();
      await a.sync();
      server = await a.server();
      expect(
        byId(
          server.changes[SyncEntity.transactions],
        ).containsKey(bBuy.transaction!.id),
        isFalse,
      );
      expect(
        (byId(server.changes[SyncEntity.wallets])[rdn]!['balance'] as num)
            .toDouble(),
        10000000 - 10150,
      );
      expect(await a.balance(rdn), 10000000 - 10150);
      expect(await a.trades.getById(bBuy.trade.id), isNull);

      // ---- Dividend → income in "Dividen" (server-known id), both devices.
      final div = (await aUc.create(
        TradeInput(
          assetId: aAsset.id,
          type: TradeType.dividend,
          date: DateTime.now(),
          amount: 25000,
        ),
      )).valueOrThrow;
      expect(div.transaction!.type, TxType.income);
      final uid = (await a.db.getMeta()).userId!;
      expect(div.transaction!.categoryId, 'category-dividen-$uid');
      await a.settle();
      await b.sync();
      final bDiv = (await b.txs.getById(div.transaction!.id))!;
      expect(bDiv.type, TxType.income);
      expect(bDiv.amount, 25000);
      expect(
        (await b.categories.getById('category-dividen-$uid'))!.name,
        'Dividen',
      );
      expect(await b.balance(rdn), 10000000 - 10150 + 25000);
      server = await a.server();
      expect(
        byId(
          server.changes[SyncEntity.categories],
        ).values.where((c) => (c['name'] as String).toLowerCase() == 'dividen'),
        hasLength(1),
        reason: 'no duplicate Dividen category',
      );

      // ---- Investment rows never count as spending/income in reports.
      final expenseOnly = await a.txs.list(type: TxType.expense);
      expect(expenseOnly, isEmpty);

      // ---- Prices: served from the seeded cache (no Yahoo call).
      await helper(
        'seed-prices',
        jsonEncode([
          {'kind': 'stock', 'symbol': stock, 'price': 1250, 'prevClose': 1200},
          {
            'kind': 'crypto',
            'symbol': coin,
            'price': 1500000000,
            'fetchedAgoMin': 120,
            'error': 'unavailable',
          },
        ]),
      );
      final res = await a.pricesApi.fetch(['stock:$stock', 'crypto:$coin']);
      final sp = res.prices['stock:$stock']!;
      expect(sp.price, 1250);
      expect(sp.prevClose, 1200);
      expect(sp.change, 50);
      expect(sp.serverStale, isFalse);
      final cp = res.prices['crypto:$coin']!;
      expect(cp.price, 1500000000);
      expect(cp.serverStale, isTrue, reason: 'old + backing off');
      expect(res.notFound, isEmpty);
      // The device's refresh stores them for offline display.
      final refreshed = await a.prices.refresh(['stock:$stock']);
      expect(refreshed.updated, ['stock:$stock']);
      expect((await a.prices.getCached())['stock:$stock']!.price, 1250);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
