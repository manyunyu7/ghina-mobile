// Food log ⇄ transaction links through the real drift database + outbox +
// sync engine against the in-memory server (docs/food-transaction-link.md).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'harness.dart';

void main() {
  late Harness h;
  late LinkFoodToTransaction link;
  late CreateFoodWithExpense createWithExpense;
  late LogFoodForTransaction logForTx;
  late String walletId;
  late String foodCat;

  setUp(() async {
    h = Harness();
    link = LinkFoodToTransaction(h.food, h.transactions, h.clock);
    createWithExpense = CreateFoodWithExpense(
      h.createTx,
      h.createFood,
      h.transactions,
    );
    logForTx = LogFoodForTransaction(h.createFood);
    walletId = await h.newWallet('Tunai', 500000);
    foodCat = (await h.createCategory(
      const CategoryInput(name: 'Makanan', icon: 'utensils'),
    )).valueOrThrow.id;
  });
  tearDown(() => h.close());

  FoodInput meal(String name, {DateTime? at}) =>
      FoodInput(date: at ?? h.clock.now(), name: name, meal: MealType.lunch);

  Future<Transaction> expense(double amount, {String? category}) async {
    h.tick();
    return (await h.createTx(
      TransactionInput(
        type: TxType.expense,
        amount: amount,
        walletId: walletId,
        categoryId: category ?? foodCat,
        note: 'Warung contoh',
        date: h.clock.now(),
      ),
    )).valueOrThrow;
  }

  Future<List<Json?>> pushedFood(String id) async => [
    for (final m in h.server.pushed)
      if (m.entity == SyncEntity.food && m.entityId == id) m.data,
  ];

  group('use cases', () {
    test('"Catat juga sebagai pengeluaran" creates the expense and links '
        'it; the wallet moves; both reach the server linked', () async {
      final r = await createWithExpense(
        meal('Nasi goreng'),
        FoodExpenseInput(
          amount: 25000,
          walletId: walletId,
          categoryId: foodCat,
        ),
      );
      final (:food, :transaction) = r.valueOrThrow;
      expect(food.transactionId, transaction.id);
      expect(transaction.categoryId, foodCat);
      expect(transaction.note, 'Nasi goreng');
      expect(transaction.date, food.date);
      expect((await h.wallet(walletId)).balance, 475000);

      await h.engine.syncNow();
      final row = h.server.rows[SyncEntity.food]![food.id]!;
      expect(row['transactionId'], transaction.id);
      expect(
        h.server.rows[SyncEntity.transactions]![transaction.id],
        isNotNull,
      );
      // The transaction went before the food row (forward reference).
      final order = [for (final m in h.server.pushed) m.entity];
      expect(
        order.indexOf(SyncEntity.transactions),
        lessThan(order.indexOf(SyncEntity.food)),
      );
      expect((await h.db.getMeta()).foodLinksSeen, isTrue);
    });

    test(
      'a failing meal removes the expense again (nothing to push)',
      () async {
        final r = await createWithExpense(
          meal('   '),
          FoodExpenseInput(amount: 25000, walletId: walletId),
        );
        expect(r, isA<Err<Object>>());
        expect(await h.transactions.list(), isEmpty);
        expect((await h.wallet(walletId)).balance, 500000);
        final queued = await h.outbox.all();
        expect(
          queued.where((o) => o.entity == SyncEntity.transactions),
          isEmpty,
        );
      },
    );

    test('an invalid expense writes nothing', () async {
      final r = await createWithExpense(
        meal('Soto'),
        FoodExpenseInput(amount: 0, walletId: walletId),
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
      expect(await h.food.watchAll().first, isEmpty);
    });

    test(
      'link / unlink; many meals share one transaction; only expenses',
      () async {
        final t = await expense(60000);
        final a = (await h.createFood(meal('Mie ayam'))).valueOrThrow;
        final b = (await h.createFood(meal('Es teh'))).valueOrThrow;
        h.tick();
        expect((await link(a.id, t.id)).valueOrThrow.transactionId, t.id);
        h.tick();
        await link(b.id, t.id);
        expect([
          for (final f in await h.food.watchByTransaction(t.id).first) f.id,
        ], unorderedEquals([a.id, b.id]));

        h.tick();
        final income = (await h.createTx(
          TransactionInput(
            type: TxType.income,
            amount: 1000,
            walletId: walletId,
            date: h.clock.now(),
          ),
        )).valueOrThrow;
        expect(
          (await link(a.id, income.id)).failureOrNull,
          isA<ValidationFailure>(),
        );
        expect(
          (await link(a.id, 'nope')).failureOrNull,
          isA<NotFoundFailure>(),
        );
        expect(
          (await link('nope', t.id)).failureOrNull,
          isA<NotFoundFailure>(),
        );

        h.tick();
        expect((await link(a.id, null)).valueOrThrow.transactionId, isNull);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.food]![a.id]!['transactionId'], isNull);
        expect(h.server.rows[SyncEntity.food]![b.id]!['transactionId'], t.id);
      },
    );

    test('editing a meal keeps its link', () async {
      final t = await expense(30000);
      final f = (await h.createFood(meal('Bakso'))).valueOrThrow;
      await link(f.id, t.id);
      h.tick();
      final u = await UpdateFoodLog(h.food, h.clock)(
        f.id,
        FoodInput(date: f.date, name: 'Bakso urat', calories: 500),
      );
      expect(u.valueOrThrow.transactionId, t.id);
    });

    test('"Catat juga di Food log" from a transaction', () async {
      final t = await expense(18000);
      final f = (await logForTx(
        t,
        name: 'Ketoprak',
        meal: MealType.breakfast,
        calories: 450,
      )).valueOrThrow;
      expect(f.transactionId, t.id);
      expect(f.date, t.date);
      expect(f.calories, 450);
      // Photos stay on the transaction: the food row gets none of them.
      expect(f.photoUrl, isNull);

      h.tick();
      final income = (await h.createTx(
        TransactionInput(
          type: TxType.income,
          amount: 1000,
          walletId: walletId,
          date: h.clock.now(),
        ),
      )).valueOrThrow;
      expect(
        (await logForTx(income, name: 'x')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });
  });

  group('cascades', () {
    test('deleting the transaction keeps the meal and clears the link, '
        'also in a queued food upsert', () async {
      final t = await expense(40000);
      final f = (await h.createFood(
        meal('Ayam geprek'),
        transactionId: t.id,
      )).valueOrThrow;
      expect(f.transactionId, t.id);
      // The food upsert is still queued with the link.
      h.tick();
      await h.deleteTx(t.id);
      final local = (await h.food.getById(f.id))!;
      expect(local.transactionId, isNull);
      final queued = (await h.outbox.all()).where(
        (o) => o.entity == SyncEntity.food,
      );
      expect(Outbox.decode(queued.single.data)!['transactionId'], isNull);
    });

    test('a pulled transaction tombstone clears the link', () async {
      final t = await expense(40000);
      final f = (await h.createFood(meal('Pecel'))).valueOrThrow;
      await link(f.id, t.id);
      await h.engine.syncNow();
      h.server.webDelete(SyncEntity.transactions, t.id);
      // The server cascade nulls the link too (fresh updatedAt).
      expect(h.server.rows[SyncEntity.food]![f.id]!['transactionId'], isNull);
      await h.engine.syncNow();
      expect((await h.food.getById(f.id))!.transactionId, isNull);
      expect(await h.food.getById(f.id), isNotNull);
    });
  });

  group('sync contract', () {
    test('a link made on the web arrives with the pull', () async {
      final t = await expense(22000);
      final f = (await h.createFood(meal('Gado-gado'))).valueOrThrow;
      await h.engine.syncNow();
      final row =
          Map<String, dynamic>.from(h.server.rows[SyncEntity.food]![f.id]!)
            ..removeWhere(
              (k, _) => const ['id', 'createdAt', 'updatedAt'].contains(k),
            );
      h.server.web(SyncEntity.food, f.id, {...row, 'transactionId': t.id});
      await h.engine.syncNow();
      expect((await h.food.getById(f.id))!.transactionId, t.id);
    });

    test('before the server is known to store links, a null link is left '
        'out of pushes, so it cannot wipe a web link', () async {
      h.server.preFoodLinks = true;
      final f = (await h.createFood(meal('Rendang'))).valueOrThrow;
      await h.engine.syncNow();
      expect((await h.db.getMeta()).foodLinksSeen, isFalse);
      expect(
        (await pushedFood(f.id)).single!.containsKey('transactionId'),
        isFalse,
      );

      // The server is upgraded and the web links the meal; the phone hasn't
      // pulled it yet and edits the meal.
      h.server.preFoodLinks = false;
      final t = await expense(35000);
      await h.engine.syncNow(); // pushes the expense; the food row is unchanged
      final row =
          Map<String, dynamic>.from(h.server.rows[SyncEntity.food]![f.id]!)
            ..removeWhere(
              (k, _) => const ['id', 'createdAt', 'updatedAt'].contains(k),
            );
      h.server.web(SyncEntity.food, f.id, {...row, 'transactionId': t.id});
      await (h.db.update(h.db.food)..where((x) => x.id.equals(f.id))).write(
        const FoodCompanion(transactionId: Value(null)),
      );
      await h.db.updateMeta(
        const SyncMetaCompanion(foodLinksSeen: Value(false)),
      );
      h.tick();
      await UpdateFoodLog(h.food, h.clock)(
        f.id,
        FoodInput(date: f.date, name: 'Rendang sapi'),
      );
      await h.engine.syncNow();
      final pushes = await pushedFood(f.id);
      expect(pushes.last!.containsKey('transactionId'), isFalse);
      expect(h.server.rows[SyncEntity.food]![f.id]!['transactionId'], t.id);
      expect(h.server.rows[SyncEntity.food]![f.id]!['name'], 'Rendang sapi');
      // The pull brought the link and flipped the flag.
      expect((await h.food.getById(f.id))!.transactionId, t.id);
      expect((await h.db.getMeta()).foodLinksSeen, isTrue);
    });

    test('a set link is always pushed (an old server ignores it)', () async {
      h.server.preFoodLinks = true;
      final t = await expense(10000);
      final f = (await h.createFood(
        meal('Kopi'),
        transactionId: t.id,
      )).valueOrThrow;
      await h.engine.syncNow();
      expect((await pushedFood(f.id)).single!['transactionId'], t.id);
      // An old server's pull has no key: the local link stays.
      expect((await h.food.getById(f.id))!.transactionId, t.id);
    });

    test('a soft link the server refuses comes back as null', () async {
      final f = (await h.createFood(meal('Martabak'))).valueOrThrow;
      await h.engine.syncNow();
      // Point at a transaction the server doesn't know (e.g. deleted on the
      // web meanwhile): stored as null, never rejected.
      await (h.db.update(h.db.food)..where((x) => x.id.equals(f.id))).write(
        const FoodCompanion(transactionId: Value('gone-tx')),
      );
      h.tick();
      await UpdateFoodLog(h.food, h.clock)(
        f.id,
        FoodInput(date: f.date, name: 'Martabak manis'),
      );
      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      expect(h.server.rows[SyncEntity.food]![f.id]!['transactionId'], isNull);
      await h.engine.syncNow();
      expect((await h.food.getById(f.id))!.transactionId, isNull);
    });
  });
}
