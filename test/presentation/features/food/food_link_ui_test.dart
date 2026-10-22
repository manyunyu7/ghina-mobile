// Food ⇄ transaction links on screen (docs/food-transaction-link.md), on the
// real in-memory data layer: food form price → expense, transaction form →
// food log, detail cards both ways, the suggestion card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/food/pages/food_form_page.dart';
import 'package:ghina/presentation/features/food/pages/food_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transaction_form_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transactions_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transactions/_feature_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c,
  String location,
) async {
  tester.view.physicalSize = const Size(390, 1600) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(path: '/food', builder: (_, _) => const FoodPage()),
      GoRoute(path: '/food/new', builder: (_, _) => const FoodFormPage()),
      GoRoute(
        path: '/food/:id',
        builder: (_, s) => FoodFormPage(id: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/transactions',
        builder: (_, _) => const TransactionsPage(),
      ),
      GoRoute(
        path: '/transactions/new',
        builder: (_, _) => const TransactionFormPage(),
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (_, s) => TransactionFormPage(id: s.pathParameters['id']),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: GhinaTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  router.push(location);
  await settle(tester);
}

typedef _Seed = ({String cash, String food, String other});

Future<_Seed> _seed(WidgetTester tester, ProviderContainer c) =>
    real(tester, () async {
      final clock = c.read(clockProvider) as FixedClock;
      final cash = (await c.read(createWalletProvider)(
        const WalletInput(name: 'Tunai', initialBalance: 500000),
      )).valueOrThrow;
      clock.advance(const Duration(seconds: 1));
      final food = (await c.read(createCategoryProvider)(
        const CategoryInput(name: 'Makanan', icon: 'utensils'),
      )).valueOrThrow;
      final other = (await c.read(createCategoryProvider)(
        const CategoryInput(name: 'Transport', icon: 'car'),
      )).valueOrThrow;
      return (cash: cash.id, food: food.id, other: other.id);
    });

Future<List<Transaction>> _txs(WidgetTester tester, ProviderContainer c) =>
    real(tester, () => c.read(transactionRepositoryProvider).list());

Future<List<FoodLog>> _foods(WidgetTester tester, ProviderContainer c) =>
    real(tester, () => c.read(foodRepositoryProvider).watchAll().first);

Future<void> _saveAndWait(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  for (var i = 0; i < 10; i++) {
    await settle(tester, 2);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('food form: a price records the expense too (on by default), '
      'linked, in the food category', (tester) async {
    final c = makeContainer();
    final ids = await _seed(tester, c);
    await _pump(tester, c, '/food/new');
    await tester.enterText(find.byKey(const ValueKey('name')), 'Nasi goreng');
    await tester.ensureVisible(find.byKey(const ValueKey('food-price')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('food-price')),
        matching: find.byType(TextField),
      ),
      '25000',
    );
    await settle(tester);
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('food-also-expense')),
    );
    expect(sw.value, isTrue);
    expect(find.text('Tunai'), findsOneWidget); // default wallet
    expect(find.text('Makanan'), findsOneWidget); // default category
    await _saveAndWait(tester, find.text('SIMPAN'));

    final txs = await _txs(tester, c);
    final foods = await _foods(tester, c);
    expect(txs, hasLength(1));
    expect(txs.single.amount, 25000);
    expect(txs.single.categoryId, ids.food);
    expect(txs.single.walletId, ids.cash);
    expect(txs.single.note, 'Nasi goreng');
    expect(foods.single.transactionId, txs.single.id);
    await tearDownApp(tester, c);
  });

  testWidgets('food form: switching the expense off saves only the meal', (
    tester,
  ) async {
    final c = makeContainer();
    await _seed(tester, c);
    await _pump(tester, c, '/food/new');
    await tester.enterText(find.byKey(const ValueKey('name')), 'Soto');
    await tester.ensureVisible(find.byKey(const ValueKey('food-price')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('food-price')),
        matching: find.byType(TextField),
      ),
      '15000',
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('food-also-expense')));
    await settle(tester);
    await _saveAndWait(tester, find.text('SIMPAN'));
    expect(await _txs(tester, c), isEmpty);
    expect((await _foods(tester, c)).single.transactionId, isNull);
    await tearDownApp(tester, c);
  });

  testWidgets('transaction form: "Catat juga di Food log" for a food '
      'category only; creates the linked meal at the transaction time', (
    tester,
  ) async {
    final c = makeContainer();
    await _seed(tester, c);
    await _pump(tester, c, '/transactions/new');
    await tapKeysOn(tester, ['1', '8', '000']);
    await tester.tap(find.text('Transport'));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-also-food')), findsNothing);
    await tester.tap(find.text('Makanan').last);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('tx-also-food')));
    await tester.tap(find.byKey(const ValueKey('tx-also-food')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tx-food-name')),
        matching: find.byType(TextField),
      ),
      'Ketoprak',
    );
    await tester.tap(find.byKey(const ValueKey('tx-food-meal-breakfast')));
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await _saveAndWait(tester, find.text('SIMPAN'));

    final tx = (await _txs(tester, c)).single;
    final food = (await _foods(tester, c)).single;
    expect(food.name, 'Ketoprak');
    expect(food.meal, MealType.breakfast);
    expect(food.transactionId, tx.id);
    expect(food.date, tx.date);
    await tearDownApp(tester, c);
  });

  testWidgets('details show each other; unlink from the transaction', (
    tester,
  ) async {
    final c = makeContainer();
    final ids = await _seed(tester, c);
    final (txId, foodId) = await real(tester, () async {
      final t = (await c.read(createTransactionProvider)(
        TransactionInput(
          type: TxType.expense,
          amount: 42000,
          walletId: ids.cash,
          categoryId: ids.food,
          note: 'Warung contoh',
          date: testNow,
        ),
      )).valueOrThrow;
      final f = (await c.read(createFoodLogProvider)(
        FoodInput(date: testNow, name: 'Ayam bakar', calories: 650),
        transactionId: t.id,
      )).valueOrThrow;
      return (t.id, f.id);
    });

    // Food detail → the expense card.
    await _pump(tester, c, '/food/$foodId');
    await tester.ensureVisible(find.byKey(const ValueKey('food-linked-tx')));
    expect(find.text('Warung contoh'), findsOneWidget);
    expect(find.text('Rp 42.000'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    // Transaction detail → the food card, then unlink.
    final c2 = c; // same data, new screen
    await _pump(tester, c2, '/transactions/$txId');
    final card = find.byKey(ValueKey('tx-linked-food-$foodId'));
    await tester.ensureVisible(card);
    expect(find.text('Ayam bakar'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('tx-unlink-food-$foodId')));
    await settle(tester);
    expect((await _foods(tester, c2)).single.transactionId, isNull);
    expect(card, findsNothing);
    await tearDownApp(tester, c2);
  });

  testWidgets('Food page: "Ini makanan yang sama?" links with one tap; '
      '"Bukan" hides the pair', (tester) async {
    final c = makeContainer();
    final ids = await _seed(tester, c);
    final (txA, foodA, foodB) = await real(tester, () async {
      Future<String> tx(DateTime at) async =>
          (await c.read(createTransactionProvider)(
            TransactionInput(
              type: TxType.expense,
              amount: 30000,
              walletId: ids.cash,
              categoryId: ids.food,
              date: at,
            ),
          )).valueOrThrow.id;
      Future<String> food(String name, DateTime at) async => (await c.read(
        createFoodLogProvider,
      )(FoodInput(date: at, name: name))).valueOrThrow.id;
      final a = await tx(testNow.subtract(const Duration(minutes: 20)));
      final fa = await food('Mie ayam', testNow);
      await tx(testNow.subtract(const Duration(hours: 4)));
      final fb = await food(
        'Roti',
        testNow.subtract(const Duration(hours: 4, minutes: 10)),
      );
      return (a, fa, fb);
    });
    await _pump(tester, c, '/food');
    expect(find.text('Ini makanan yang sama?'), findsNWidgets(2));

    await tester.tap(
      find.byKey(ValueKey('food-link-yes-${foodLinkKey(foodA, txA)}')),
    );
    await settle(tester);
    final foods = await _foods(tester, c);
    expect(foods.firstWhere((f) => f.id == foodA).transactionId, txA);
    expect(find.text('Ini makanan yang sama?'), findsOneWidget);

    await tester.tap(find.textContaining('BUKAN'));
    await settle(tester);
    expect(find.text('Ini makanan yang sama?'), findsNothing);
    expect(
      (await _foods(tester, c)).firstWhere((f) => f.id == foodB).transactionId,
      isNull,
    );
    // The month card counts the linked meal.
    await tester.ensureVisible(find.byKey(const ValueKey('food-spend')));
    expect(find.text('Rp 30.000 per makan'), findsOneWidget);
    await tearDownApp(tester, c);
  });

  testWidgets('transaction-first: the list marks a transaction that has food '
      'logs; the detail adds a new one at its time and links an existing one', (
    tester,
  ) async {
    final c = makeContainer();
    final ids = await _seed(tester, c);
    final (txId, otherFood) = await real(tester, () async {
      final t = (await c.read(createTransactionProvider)(
        TransactionInput(
          type: TxType.expense,
          amount: 64000,
          walletId: ids.cash,
          categoryId: ids.food,
          note: 'Warung contoh',
          date: testNow.subtract(const Duration(hours: 1)),
          photos: const [TransactionPhoto.remote('/uploads/struk-contoh.jpg')],
        ),
      )).valueOrThrow;
      final f = (await c.read(createFoodLogProvider)(
        FoodInput(date: testNow, name: 'Es jeruk'),
      )).valueOrThrow;
      return (t.id, f.id);
    });

    // Detail → "Tambah food log".
    await _pump(tester, c, '/transactions/$txId');
    await tester.ensureVisible(find.byKey(const ValueKey('tx-food-add')));
    await tester.tap(find.byKey(const ValueKey('tx-food-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('add-food-tx-info')), findsOneWidget);
    expect(
      find.text('Foto transaksi dipakai sebagai foto food log ini.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('add-food-name')),
        matching: find.byType(TextField),
      ),
      'Nasi campur',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('add-food-kcal')),
        matching: find.byType(TextField),
      ),
      '700',
    );
    await tester.tap(find.byKey(const ValueKey('add-food-save')));
    for (var i = 0; i < 4; i++) {
      await settle(tester, 2);
    }
    var foods = await _foods(tester, c);
    final added = foods.firstWhere((f) => f.name == 'Nasi campur');
    expect(added.transactionId, txId);
    expect(added.calories, 700);
    expect(added.date, testNow.subtract(const Duration(hours: 1)));
    // The photo is the transaction's, referenced — not copied to the meal.
    expect(added.photoUrl, isNull);
    expect(added.localPhotoPath, isNull);

    // "Tautkan yang ada" → the other meal.
    await tester.ensureVisible(
      find.byKey(const ValueKey('tx-food-link-existing')),
    );
    await tester.tap(find.byKey(const ValueKey('tx-food-link-existing')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('link-food-$otherFood')));
    await settle(tester);
    foods = await _foods(tester, c);
    expect(foods.firstWhere((f) => f.id == otherFood).transactionId, txId);
    expect(find.text('FOOD LOG · 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    // The list row shows the marker with the first menu and the count.
    await _pump(tester, c, '/transactions');
    expect(find.byKey(ValueKey('tx-food-$txId')), findsOneWidget);
    expect(
      find.textContaining('Nasi campur +1', findRichText: true),
      findsOneWidget,
    );
    await tearDownApp(tester, c);
  });
}

Future<void> tapKeysOn(WidgetTester tester, List<String> keys) async {
  for (final k in keys) {
    await tester.tap(
      find.descendant(of: find.byType(AmountKeypad), matching: find.text(k)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
