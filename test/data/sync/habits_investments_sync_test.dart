// Habits and investments through the real drift database + outbox + sync
// engine against the in-memory server (docs/habits.md, docs/investments.md,
// docs/mobile-sync.md "Habits" / "Investments").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../fake_server.dart';
import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  String today() => dateKey(h.clock.now());

  // ================================================================ habits

  group('habits', () {
    test('create + check-in + skip sync with the JSON wire shape', () async {
      h.tick();
      final habit = (await h.createHabit(
        HabitInput(
          name: 'Minum air',
          emoji: '💧',
          target: HabitTarget.count(8, unit: 'gelas'),
          reminders: const ['21:30', '07:00'],
          isPrivate: true,
          startDate: DateTime(2026, 9, 1),
        ),
      )).valueOrThrow;
      h.tick();
      await h.checkIn(habit.id, value: 3);
      h.tick();
      final l = (await h.checkIn(habit.id, value: 2)).valueOrThrow!;
      expect(l.value, 5, reason: 'counts add up in one row');
      h.tick();
      await h.skipDay(habit.id, day: DateTime(2026, 9, 20), note: 'sakit');
      await h.engine.syncNow();

      final row = h.server.rows[SyncEntity.habits]![habit.id]!;
      expect(row['schedule'], {'type': 'daily'});
      expect(row['target'], {'type': 'count', 'goal': 8, 'unit': 'gelas'});
      expect(row['reminders'], ['07:00', '21:30']);
      expect(row['private'], isTrue);
      expect(row['startDate'], '2026-09-01');
      final logs = h.server.rows[SyncEntity.habitLogs]!.values.toList();
      expect(logs, hasLength(2));
      final done = logs.firstWhere((x) => x['type'] == 'done');
      expect(done['value'], 5);
      expect(done['date'], today());
      expect(done['triggers'], isEmpty);
      final skip = logs.firstWhere((x) => x['type'] == 'skip');
      expect(skip['value'], isNull);
      expect(skip['note'], 'sakit');
      expect(await h.outboxCount(), 0);
    });

    test('skip limit: at most 2 per rolling 7 days', () async {
      final habit = (await h.createHabit(
        HabitInput(name: 'Lari', startDate: DateTime(2026, 9, 1)),
      )).valueOrThrow;
      expect(
        (await h.skipDay(habit.id, day: DateTime(2026, 9, 18))).isOk,
        isTrue,
      );
      expect(
        (await h.skipDay(habit.id, day: DateTime(2026, 9, 20))).isOk,
        isTrue,
      );
      final third = await h.skipDay(habit.id, day: DateTime(2026, 9, 22));
      final f = third.failureOrNull as ValidationFailure;
      expect(f.field, 'skip');
      expect(f.message, 'Maksimal 2 hari libur dalam 7 hari');
      // Outside every window holding two skips: fine.
      expect(
        (await h.skipDay(habit.id, day: DateTime(2026, 9, 10))).isOk,
        isTrue,
      );
      // Quit habits can't skip; build habits can't relapse.
      final q = (await h.createHabit(
        HabitInput(name: 'Rokok', kind: HabitKind.quit),
      )).valueOrThrow;
      expect((await h.skipDay(q.id)).failureOrNull, isA<ValidationFailure>());
      expect(
        (await h.logRelapse(habit.id)).failureOrNull,
        isA<ValidationFailure>(),
      );
    });

    test('quit: urges add up, relapse reports the clean streak it ended, '
        'emergency "Aku kalah" converts an urge', () async {
      final q = (await h.createHabit(
        HabitInput(
          name: 'Rokok',
          kind: HabitKind.quit,
          startDate: addDays(h.clock.now(), -12),
        ),
      )).valueOrThrow;
      await h.logUrge(q.id, triggers: const ['stres']);
      final u = (await h.logUrge(
        q.id,
        triggers: const ['Stres', 'malam'],
      )).valueOrThrow;
      expect(u.value, 2);
      expect(u.triggers, ['stres', 'malam']);
      final convert = ConvertUrgeToRelapse(
        h.habits,
        h.habitLogs,
        h.uow,
        h.clock,
      );
      final r = (await convert(
        q.id,
        const RelapseInput(triggers: ['bosan']),
      )).valueOrThrow;
      expect(r.previousStreak, 12, reason: 'sempat bersih 12 hari');
      expect(r.log.value, 1);
      final logs = await h.habitLogs.getAll(habitId: q.id);
      expect(
        logs.firstWhere((l) => l.type == HabitLogType.urge).value,
        1,
        reason: 'the converted urge is taken back',
      );
      final t = habitToday(q, logs, today());
      expect(t.streak.current, 0);
      expect(t.relapsedToday, isTrue);
      // Clean check-in is refused on a relapse day.
      final clean = ConfirmCleanDay(h.habits, h.habitLogs, h.clock);
      expect((await clean(q.id)).failureOrNull, isA<ValidationFailure>());
    });

    test('duplicate (habitId, date, type): the local row is dropped and its '
        'count merged into the server row', () async {
      final habit = (await h.createHabit(
        HabitInput(
          name: 'Rokok',
          kind: HabitKind.quit,
          startDate: DateTime(2026, 9, 1),
        ),
      )).valueOrThrow;
      await h.engine.syncNow();
      // The web logged 2 urges today meanwhile; this device logs 1 offline.
      h.server.web(SyncEntity.habitLogs, 'web-urge', {
        'habitId': habit.id,
        'date': today(),
        'type': 'urge',
        'value': 2,
        'note': null,
        'triggers': ['bosan'],
        'at': null,
      });
      h.tick();
      await h.logUrge(habit.id, triggers: const ['malam']);
      await h.engine.syncNow(); // duplicate → merged + queued
      await h.engine.syncNow(); // merged row pushed
      final logs = await h.habitLogs.getAll(habitId: habit.id);
      expect(logs, hasLength(1));
      expect(logs.single.id, 'web-urge');
      expect(logs.single.value, 3);
      expect(logs.single.triggers, ['bosan', 'malam']);
      expect(h.server.rows[SyncEntity.habitLogs]!['web-urge']!['value'], 3);
      expect(h.server.rows[SyncEntity.habitLogs], hasLength(1));
    });

    test(
      'habit delete cascades its logs (local + server tombstones)',
      () async {
        final habit = (await h.createHabit(
          HabitInput(name: 'Baca', startDate: DateTime(2026, 9, 1)),
        )).valueOrThrow;
        await h.checkIn(habit.id);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.habitLogs], hasLength(1));

        // Deleted on the web → tombstones pulled.
        h.server.webDelete(SyncEntity.habits, habit.id);
        await h.engine.syncNow();
        expect(await h.habits.getAll(), isEmpty);
        expect(await h.habitLogs.getAll(), isEmpty);

        // Deleted here → logs go locally, the server cascades itself.
        final b = (await h.createHabit(
          HabitInput(name: 'Tulis', startDate: DateTime(2026, 9, 1)),
        )).valueOrThrow;
        await h.checkIn(b.id);
        await h.engine.syncNow();
        h.tick();
        await h.deleteHabit(b.id);
        expect(await h.habitLogs.getAll(), isEmpty);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.habits], isEmpty);
        expect(h.server.rows[SyncEntity.habitLogs], isEmpty);
      },
    );

    test('pulled habits/logs parse leniently', () async {
      h.server.web(SyncEntity.habits, 'hw', {
        'name': 'Olahraga',
        'emoji': null,
        'color': '#58CC02',
        'kind': 'build',
        'schedule': {
          'type': 'weekdays',
          'days': [1, 3, 5],
        },
        'target': {'type': 'duration', 'goal': 30},
        'reminders': ['06:00'],
        'private': false,
        'why': null,
        'startDate': '2026-09-01',
        'archived': false,
        'sortOrder': 0,
      });
      h.server.web(SyncEntity.habitLogs, 'lw', {
        'habitId': 'hw',
        'date': '2026-09-21',
        'type': 'done',
        'value': 30,
        'note': 'pagi',
        'triggers': [],
        'at': null,
      });
      h.server.web(SyncEntity.habitLogs, 'lx', {
        'habitId': 'hw',
        'date': '2026-09-22',
        'type': 'future-type',
        'value': 1,
        'note': null,
        'triggers': [],
        'at': null,
      });
      await h.engine.syncNow();
      final habit = (await h.habits.getById('hw'))!;
      expect(habit.schedule, HabitSchedule.weekdays(const [1, 3, 5]));
      expect(habit.target, HabitTarget.duration(30));
      final logs = await h.habitLogs.getAll(habitId: 'hw');
      expect(logs.single.note, 'pagi', reason: 'unknown types are skipped');
    });
  });

  // ================================================================ investments

  Future<({String wallet, Asset asset})> rdn({
    double balance = 10000000,
  }) async {
    final w = await h.newWallet('RDN', balance);
    h.tick();
    final a = (await h.createAsset(
      AssetInput(kind: AssetKind.stock, symbol: 'bbca.jk', walletId: w),
    )).valueOrThrow;
    return (wallet: w, asset: a);
  }

  TradeInput buy(String assetId, double q, double p, {DateTime? date}) =>
      TradeInput(
        assetId: assetId,
        type: TradeType.buy,
        date: date ?? h.clock.now(),
        quantity: q,
        price: p,
        fee: FeePreset.standard.feeFor(TradeType.buy, q * p),
      );

  group('investments: cash effect', () {
    test('buy → linked investment tx; edit/delete keep tx and balance in '
        'step; server matches', () async {
      final r = await rdn();
      expect(r.asset.symbol, 'BBCA');
      h.tick();
      final created = (await h.tradeUc.create(
        buy(r.asset.id, 1000, 9500),
      )).valueOrThrow;
      final tx = created.transaction!;
      expect(tx.type, TxType.investment);
      expect(tx.amount, -9514250);
      expect(tx.categoryId, isNull);
      expect(tx.note, 'Beli BBCA 10 lot @ 9.500');
      expect(created.trade.cashTransactionId, tx.id);
      expect((await h.wallet(r.wallet)).balance, 10000000 - 9514250);

      await h.engine.syncNow();
      final pushed = [
        for (final m in h.server.pushed) '${m.entity}:${m.op.name}',
      ];
      expect(
        pushed.indexOf('transactions:upsert'),
        lessThan(pushed.indexOf('assetTrades:upsert')),
        reason: 'the linked transaction goes before the trade',
      );
      expect(h.server.balanceOf(r.wallet), 10000000 - 9514250);
      final st = h.server.rows[SyncEntity.assetTrades]![created.trade.id]!;
      expect(st['cashTransactionId'], tx.id);
      expect(st['quantity'], 1000);

      // Edit: 500 shares → the same transaction follows.
      h.tick();
      final edited = (await h.tradeUc.update(
        created.trade.id,
        buy(r.asset.id, 500, 9500, date: created.trade.date),
      )).valueOrThrow;
      expect(edited.transaction!.id, tx.id);
      expect(edited.transaction!.amount, -(4750000 + 7125));
      expect((await h.wallet(r.wallet)).balance, 10000000 - 4757125);
      await h.engine.syncNow();
      expect(h.server.balanceOf(r.wallet), 10000000 - 4757125);

      // Cash effect off → the transaction goes, the trade stays.
      h.tick();
      final off = (await h.tradeUc.update(
        created.trade.id,
        TradeInput(
          assetId: r.asset.id,
          type: TradeType.buy,
          date: created.trade.date,
          quantity: 500,
          price: 9500,
          fee: 7125,
          cashEffect: false,
        ),
      )).valueOrThrow;
      expect(off.transaction, isNull);
      expect(off.trade.cashTransactionId, isNull);
      expect(await h.transactions.getById(tx.id), isNull);
      expect((await h.wallet(r.wallet)).balance, 10000000);

      // Back on, then delete the trade: trade delete queued before the tx's.
      h.tick();
      final on = (await h.tradeUc.update(
        created.trade.id,
        buy(r.asset.id, 500, 9500, date: created.trade.date),
      )).valueOrThrow;
      expect(on.transaction, isNull, reason: 'edits keep the cash state');
      h.tick();
      final on2 = (await h.tradeUc.update(
        created.trade.id,
        TradeInput(
          assetId: r.asset.id,
          type: TradeType.buy,
          date: created.trade.date,
          quantity: 500,
          price: 9500,
          fee: 7125,
          cashEffect: true,
        ),
      )).valueOrThrow;
      expect(on2.transaction!.amount, -4757125);
      await h.engine.syncNow();
      h.server.pushed.clear();
      h.tick();
      expect((await h.tradeUc.delete(created.trade.id)).isOk, isTrue);
      expect(await h.transactions.getById(on2.transaction!.id), isNull);
      expect((await h.wallet(r.wallet)).balance, 10000000);
      await h.engine.syncNow();
      expect(
        [for (final m in h.server.pushed) '${m.entity}:${m.op.name}'],
        ['assetTrades:delete', 'transactions:delete'],
      );
      expect(h.server.balanceOf(r.wallet), 10000000);
      expect(h.server.rows[SyncEntity.assetTrades], isEmpty);
      expect(h.server.rows[SyncEntity.transactions], isEmpty);
    });

    test('sell beyond the holding is refused with the server message and '
        'writes nothing', () async {
      final r = await rdn();
      h.tick();
      await h.tradeUc.create(buy(r.asset.id, 100, 1000));
      final before = await h.outboxCount();
      h.tick();
      final res = await h.tradeUc.create(
        TradeInput(
          assetId: r.asset.id,
          type: TradeType.sell,
          date: h.clock.now(),
          quantity: 150,
          price: 1000,
        ),
      );
      final f = res.failureOrNull as ValidationFailure;
      expect(f.field, 'quantity');
      expect(
        f.message,
        startsWith('Jumlah jual (150) melebihi kepemilikan (100) per '),
      );
      expect(await h.outboxCount(), before);
      expect(await h.trades.getAll(), hasLength(1));
      expect(await h.transactions.list(), hasLength(1));
    });

    test('a sell whose fee exceeds the proceeds can\'t carry a cash effect '
        '(the server would reject the link); without it, it saves', () async {
      final r = await rdn();
      h.tick();
      await h.tradeUc.create(buy(r.asset.id, 100, 1000));
      final before = await h.outboxCount();
      h.tick();
      TradeInput sell({bool? cash, double fee = 1500}) => TradeInput(
        assetId: r.asset.id,
        type: TradeType.sell,
        date: h.clock.now(),
        quantity: 1,
        price: 1000,
        fee: fee,
        cashEffect: cash,
      );
      final res = await h.tradeUc.create(sell());
      expect((res.failureOrNull as ValidationFailure).field, 'fee');
      expect(await h.outboxCount(), before);
      expect(await h.trades.getAll(), hasLength(1));
      h.tick();
      final ok = (await h.tradeUc.create(sell(cash: false))).valueOrThrow;
      expect(ok.transaction, isNull);
      // Exactly zero proceeds: no cash transaction at all (like the server).
      h.tick();
      final zero = (await h.tradeUc.create(sell(fee: 1000))).valueOrThrow;
      expect(zero.transaction, isNull);
      await h.engine.syncNow();
      expect(await h.outboxCount(), 0);
      expect(h.server.rows[SyncEntity.assetTrades], hasLength(3));
    });

    test(
      'atomic: a failing cash effect leaves no trade and no transaction',
      () async {
        final w = await h.newWallet('Tunai', 0);
        h.tick();
        final a = (await h.createAsset(
          const AssetInput(kind: AssetKind.stock, symbol: 'TLKM'),
        )).valueOrThrow;
        h.tick();
        final res = await h.tradeUc.create(
          TradeInput(
            assetId: a.id,
            type: TradeType.buy,
            date: h.clock.now(),
            quantity: 100,
            price: 3000,
            cashEffect: true,
          ),
        );
        expect((res.failureOrNull as ValidationFailure).field, 'walletId');
        expect(await h.trades.getAll(), isEmpty);
        expect(await h.transactions.list(), isEmpty);
        // Without a wallet the default is no cash effect.
        final ok = (await h.tradeUc.create(buy(a.id, 100, 3000))).valueOrThrow;
        expect(ok.transaction, isNull);
        expect((await h.wallet(w)).balance, 0);
      },
    );

    test('dividend → income in Dividen (category-dividen-<userId>), '
        'counted as income', () async {
      final r = await rdn();
      h.tick();
      await h.tradeUc.create(buy(r.asset.id, 100, 1000));
      h.tick();
      final d = (await h.tradeUc.create(
        TradeInput(
          assetId: r.asset.id,
          type: TradeType.dividend,
          date: h.clock.now(),
          amount: 25000,
        ),
      )).valueOrThrow;
      expect(d.transaction!.type, TxType.income);
      expect(d.transaction!.amount, 25000);
      expect(d.transaction!.categoryId, 'category-dividen-u1');
      expect(
        (await h.categories.getById('category-dividen-u1'))!.name,
        'Dividen',
      );
      await h.engine.syncNow();
      expect(
        h.server.rows[SyncEntity.categories]!['category-dividen-u1'],
        isNotNull,
      );
      final report = buildReport(
        period: ReportPeriod.thisMonth,
        now: h.clock.now(),
        transactions: await h.transactions.list(),
        categories: await h.categories.getAll(),
        wallets: await h.wallets.getAll(),
      );
      expect(report.totalIncome, 25000, reason: 'dividends are income');
      expect(report.totalExpense, 0, reason: 'investment rows are not expense');
    });

    test(
      'delete asset: trades and their transactions go (balance back)',
      () async {
        final r = await rdn();
        h.tick();
        await h.tradeUc.create(buy(r.asset.id, 100, 1000));
        await h.engine.syncNow();
        h.tick();
        expect((await h.deleteAsset(r.asset.id)).isOk, isTrue);
        expect(await h.trades.getAll(), isEmpty);
        expect(await h.transactions.list(), isEmpty);
        expect((await h.wallet(r.wallet)).balance, 10000000);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.assets], isEmpty);
        expect(h.server.rows[SyncEntity.transactions], isEmpty);
        expect(h.server.balanceOf(r.wallet), 10000000);
      },
    );

    test('a linked transaction deleted directly keeps the trade', () async {
      final r = await rdn();
      h.tick();
      final t = (await h.tradeUc.create(
        buy(r.asset.id, 100, 1000),
      )).valueOrThrow;
      h.tick();
      await h.deleteTx(t.transaction!.id);
      expect((await h.trades.getById(t.trade.id))!.cashTransactionId, isNull);
      await h.engine.syncNow();
      expect(
        h.server.rows[SyncEntity.assetTrades]![t
            .trade
            .id]!['cashTransactionId'],
        isNull,
      );
    });
  });

  group('investments: sync conflicts', () {
    test('rejected trade (oversell after another device\'s edit): reverted, '
        'its cash transaction removed, server message surfaced', () async {
      final r = await rdn();
      h.tick();
      final b = (await h.tradeUc.create(
        buy(r.asset.id, 100, 1000),
      )).valueOrThrow;
      await h.engine.syncNow();
      // The web shrinks the buy; this device sells 100 offline.
      h.server.web(SyncEntity.assetTrades, b.trade.id, {
        ...h.server.rows[SyncEntity.assetTrades]![b.trade.id]!,
        'quantity': 50,
      });
      h.tick();
      final s = (await h.tradeUc.create(
        TradeInput(
          assetId: r.asset.id,
          type: TradeType.sell,
          date: h.clock.now(),
          quantity: 100,
          price: 1200,
        ),
      )).valueOrThrow;
      expect((await h.wallet(r.wallet)).balance, 10000000 - 100150 + 120000);
      await h.engine.syncNow();
      final status = await h.engine.watchStatus().first;
      expect(status.lastError, contains('melebihi kepemilikan'));
      await h.engine.syncNow(); // pushes the reverting transaction delete
      expect(await h.trades.getById(s.trade.id), isNull);
      expect(await h.transactions.getById(s.transaction!.id), isNull);
      expect(
        h.server.rows[SyncEntity.transactions]![s.transaction!.id],
        isNull,
      );
      expect((await h.trades.getById(b.trade.id))!.quantity, 50);
      expect(h.server.balanceOf(r.wallet), 10000000 - 100150);
      expect((await h.wallet(r.wallet)).balance, 10000000 - 100150);
    });

    test('duplicate asset (same kind + symbol elsewhere): its trades move to '
        'the server asset', () async {
      final w = await h.newWallet('RDN', 1000000);
      await h.engine.syncNow();
      h.server.web(SyncEntity.assets, 'web-bbca', {
        'kind': 'stock',
        'symbol': 'BBCA',
        'name': 'Bank Central Asia',
        'currency': 'IDR',
        'priceMode': 'auto',
        'manualPrice': null,
        'manualPriceAt': null,
        'unit': 'lembar',
        'walletId': null,
        'archived': false,
        'sortOrder': 0,
      });
      h.tick();
      final mine = (await h.createAsset(
        AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w),
      )).valueOrThrow;
      h.tick();
      final t = (await h.tradeUc.create(buy(mine.id, 10, 1000))).valueOrThrow;
      await h.engine.syncNow();
      await h.engine.syncNow();
      expect(await h.assets.getById(mine.id), isNull);
      expect((await h.trades.getById(t.trade.id))!.assetId, 'web-bbca');
      expect(
        h.server.rows[SyncEntity.assetTrades]![t.trade.id]!['assetId'],
        'web-bbca',
      );
      expect(await h.outboxCount(), 0);
    });

    test(
      'a full pull from a pre-habits server leaves local habits alone',
      () async {
        final server = FakeServer()..preHabits = true;
        final old = Harness(server: server);
        addTearDown(old.close);
        final habit = (await old.createHabit(
          const HabitInput(name: 'Baca'),
        )).valueOrThrow;
        await old.engine.pullOnly();
        expect(await old.habits.getById(habit.id), isNotNull);
        expect(await old.outboxCount(), 1);
      },
    );
  });

  group('prices', () {
    test(
      'refresh caches prices; offline keeps the cache; not_found reported',
      () async {
        final r = await rdn();
        h.pricesApi.quote(
          'stock:BBCA',
          price: 9500,
          prevClose: 9400,
          name: 'BCA',
        );
        final res = await h.prices.refresh(['stock:BBCA', 'stock:ZZZZ']);
        expect(res.updated, ['stock:BBCA']);
        expect(res.notFound, ['stock:ZZZZ']);
        final cached = await h.prices.getCached();
        expect(cached['stock:BBCA']!.price, 9500);
        expect(cached['stock:BBCA']!.name, 'BCA');

        h.pricesApi.online = false;
        await expectLater(
          h.prices.refresh(['stock:BBCA']),
          throwsA(isA<NetworkFailure>()),
        );
        expect((await h.prices.getCached())['stock:BBCA']!.price, 9500);

        h.tick();
        await h.tradeUc.create(buy(r.asset.id, 100, 9000));
        final p = await h.portfolio().first;
        expect(p.marketValue, 950000);
        expect(p.dayChange, 10000);
      },
    );

    test('staleness follows the cache rules (session: 15 min)', () async {
      final a = (await h.createAsset(
        const AssetInput(kind: AssetKind.crypto, symbol: 'BTC'),
      )).valueOrThrow;
      h.pricesApi.quote('crypto:BTC', price: 1e9);
      await h.prices.refresh(['crypto:BTC']);
      h.tick();
      await h.tradeUc.create(buy(a.id, 0.01, 1e9));
      var p = await h.portfolio().first;
      expect(p.holding(a.id)!.quote.stale, isFalse);
      h.clock.advance(const Duration(minutes: 16));
      p = await h.portfolio().first;
      expect(p.holding(a.id)!.quote.stale, isTrue);
      expect(p.staleCount, 1);
      // Stale is still used for the value.
      expect(p.marketValue, 1e7);
    });

    test(
      'price refresh stores the day\'s snapshot for the history chart',
      () async {
        final r = await rdn();
        h.tick();
        await h.tradeUc.create(buy(r.asset.id, 100, 9000));
        h.pricesApi.quote('stock:BBCA', price: 9500);
        final refresh = RefreshPrices(
          h.assets,
          h.prices,
          RecordPortfolioSnapshot(
            h.assets,
            h.trades,
            h.prices,
            h.snapshots,
            h.clock,
          ),
        );
        final res = (await refresh()).valueOrThrow;
        expect(res.updated, ['stock:BBCA']);
        final pts = await h.snapshots
            .watchRange('2026-01-01', '2026-12-31')
            .first;
        expect(pts.single.value, 950000);
        expect(pts.single.cost, 900000 + 1350);
      },
    );
  });

  group('net worth, reminders', () {
    test(
      'net worth = wallets + portfolio value (dashboard and report)',
      () async {
        final r = await rdn(balance: 1000000);
        h.tick();
        await h.tradeUc.create(buy(r.asset.id, 100, 1000));
        h.pricesApi.quote('stock:BBCA', price: 1500);
        await h.prices.refresh(['stock:BBCA']);
        final nw = await WatchNetWorth(h.wallets, h.portfolio)().first;
        expect(nw.wallets, 1000000 - 100150);
        expect(nw.investments, 150000);
        expect(nw.total, 1000000 - 100150 + 150000);

        Stream<double> inv() => h.portfolio().map((p) => p.marketValue);
        final dash = await WatchDashboard(
          h.transactions,
          h.wallets,
          h.categories,
          h.budgets,
          h.clock,
          investments: inv,
        )().first;
        expect(
          dash.totalBalance,
          1000000 - 100150,
          reason: 'wallets unchanged',
        );
        expect(dash.investmentsValue, 150000);
        expect(dash.netWorth, nw.total);
        expect(dash.monthExpense, 0, reason: 'investment rows are no expense');
        final report = await WatchReport(
          h.transactions,
          h.categories,
          h.wallets,
          h.clock,
          investments: inv,
        )(ReportPeriod.thisMonth).first;
        expect(report.netWorth, nw.total);
        expect(report.walletsTotal, 1000000 - 100150);
      },
    );

    test('habit reminders merge with tasks (≤ 60, soonest first); private '
        'ones are masked', () async {
      final now = h.clock.now();
      String hm(DateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      final soon = now.add(const Duration(hours: 1));
      await h.createHabit(
        HabitInput(
          name: 'PMO',
          kind: HabitKind.quit,
          isPrivate: true,
          reminders: [hm(soon)],
          startDate: addDays(now, -5),
        ),
      );
      await h.createHabit(
        HabitInput(
          name: 'Minum air',
          emoji: '💧',
          target: HabitTarget.count(8, unit: 'gelas'),
          reminders: [hm(now.add(const Duration(hours: 2)))],
          startDate: addDays(now, -5),
        ),
      );
      final area = (await h.createArea(
        const TaskAreaInput(name: 'Kerja', code: 'KERJA'),
      )).valueOrThrow;
      for (var i = 0; i < 70; i++) {
        final due = now.add(Duration(days: 1, minutes: i * 10));
        await h.createTask(
          TaskInput(
            areaId: area.id,
            title: 'T$i',
            dueDate: startOfDay(due),
            dueTime: hm(due),
            remindBefore: 0,
          ),
        );
      }
      final reminders = await WatchReminders(
        h.tasks,
        h.taskAreas,
        h.ticks,
        habits: h.habits,
        habitLogs: h.habitLogs,
      )().first;
      expect(reminders, hasLength(60));
      for (var i = 1; i < reminders.length; i++) {
        expect(reminders[i].fireAt.isBefore(reminders[i - 1].fireAt), isFalse);
      }
      final first = reminders.first;
      expect(first.title, 'Waktunya cek kebiasaanmu ✨');
      expect(first.body, isNot(contains('PMO')));
      expect(reminders.any((r) => r.title.contains('PMO')), isFalse);
      expect(reminders[1].title, '💧 Minum air');
      expect(reminders[1].body, 'Target hari ini: 8 gelas');
      expect(first.route, startsWith('/habits/'));
      // Checking in removes today's reminder.
      final water = (await h.habits.getAll()).firstWhere((x) => x.isBuild);
      await h.checkIn(water.id, value: 8);
      final after = await WatchReminders(
        h.tasks,
        h.taskAreas,
        h.ticks,
        habits: h.habits,
        habitLogs: h.habitLogs,
      )().first;
      expect(
        after.any(
          (r) =>
              r.key ==
              habitReminderKey(
                water.id,
                today(),
                hm(now.add(const Duration(hours: 2))),
              ),
        ),
        isFalse,
      );
    });
  });
}
