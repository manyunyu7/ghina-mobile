import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

import '_invest_harness.dart';

void main() {
  group('add asset', () {
    testWidgets('ticker validation: invalid, found (name filled), not found', (
      tester,
    ) async {
      final prices = TestPrices()
        ..quote('BBCA', 9500, name: 'Bank Central Asia Tbk', cache: false);
      final c = investContainer(prices);
      await pumpInvest(tester, c, '/investments/new');

      expect(find.byKey(const ValueKey('lookup-idle')), findsOneWidget);

      await typeInto(tester, 'asset-symbol', 'BB C');
      expect(find.byKey(const ValueKey('lookup-invalid')), findsOneWidget);

      await typeInto(tester, 'asset-symbol', 'ZZZZ');
      expect(find.byKey(const ValueKey('lookup-checking')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byKey(const ValueKey('lookup-missing')), findsOneWidget);
      expect(find.textContaining('ZZZZ nggak ketemu di BEI'), findsOneWidget);
      // Save is blocked while the ticker is unknown.
      await tester.tap(find.byKey(const ValueKey('asset-save')));
      await settle(tester);
      expect(
        await real(tester, () => c.read(assetRepositoryProvider).getAll()),
        isEmpty,
      );

      await typeInto(tester, 'asset-symbol', 'bbca');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byKey(const ValueKey('lookup-ok')), findsOneWidget);
      expect(find.textContaining('Rp 9.500'), findsOneWidget);
      expect(find.text('Bank Central Asia Tbk'), findsOneWidget); // name field

      await tester.tap(find.byKey(const ValueKey('asset-save')));
      await settle(tester, 8);
      final assets = await real(
        tester,
        () => c.read(assetRepositoryProvider).getAll(),
      );
      expect(assets.single.symbol, 'BBCA');
      expect(assets.single.name, 'Bank Central Asia Tbk');
      // Lands on the new asset's page.
      expect(find.byKey(const ValueKey('asset-buy')), findsOneWidget);
      await tearDownApp(tester, c);
    });

    testWidgets('offline: unvalidated ticker can still be saved', (
      tester,
    ) async {
      final prices = TestPrices()..lookupOffline = true;
      final c = investContainer(prices);
      await pumpInvest(tester, c, '/investments/new');
      await typeInto(tester, 'asset-symbol', 'TLKM');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byKey(const ValueKey('lookup-offline')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asset-save')));
      await settle(tester, 8);
      final assets = await real(
        tester,
        () => c.read(assetRepositoryProvider).getAll(),
      );
      expect(assets.single.symbol, 'TLKM');
      await tearDownApp(tester, c);
    });

    testWidgets('manual kind (Emas) saves its manual price', (tester) async {
      final c = investContainer(TestPrices());
      await pumpInvest(tester, c, '/investments/new');
      await tester.tap(find.text('Emas'));
      await tester.pump();
      expect(find.byKey(const ValueKey('asset-manual')), findsNothing);
      await typeInto(tester, 'asset-symbol', 'ANTAM');
      await typeInto(tester, 'asset-price', '1250000');
      await tester.tap(find.byKey(const ValueKey('asset-save')));
      await settle(tester, 8);
      final a = (await real(
        tester,
        () => c.read(assetRepositoryProvider).getAll(),
      )).single;
      expect(a.kind, AssetKind.gold);
      expect(a.isManual, isTrue);
      expect(a.manualPrice, 1250000);
      expect(a.unit, 'gram');
      await tearDownApp(tester, c);
    });
  });

  group('trade form', () {
    testWidgets('buy in lots: fee preset + cash/holding preview, saves', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBCA', 9500, prevClose: 9400);
      final c = investContainer(prices);
      final w = await seedWallet(tester, c);
      final a = await seedAsset(
        tester,
        c,
        AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w.id),
      );
      await pumpInvest(tester, c, '/investments/${a.id}/trade?type=buy');

      await typeInto(tester, 'trade-qty', '10');
      await settle(tester, 2);
      expect(find.text('= 1.000 lembar'), findsOneWidget);
      // Price prefilled with the last price; fee 0,15 % of 9.500.000.
      expect(find.text('9.500'), findsOneWidget);
      expect(find.text('14.250'), findsOneWidget);
      await scrollToFinder(tester, find.byKey(const ValueKey('trade-preview')));
      expect(find.text('-Rp 9.514.250'), findsOneWidget);
      expect(find.text('10 lot'), findsOneWidget);
      expect(find.text('Rp 9.514'), findsOneWidget); // avg incl. fee

      await tester.tap(find.byKey(const ValueKey('trade-save')));
      await settle(tester, 8);
      expect(await walletBalance(tester, c, w.id), 20000000 - 9514250);
      final trades = await real(
        tester,
        () => c.read(assetTradeRepositoryProvider).getAll(),
      );
      expect(trades.single.quantity, 1000);
      expect(trades.single.fee, 14250);
      await tearDownApp(tester, c);
    });

    testWidgets('lembar toggle converts and the fee can be switched off', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBCA', 9500);
      final c = investContainer(prices);
      final a = await seedAsset(
        tester,
        c,
        const AssetInput(kind: AssetKind.stock, symbol: 'BBCA'),
      );
      await pumpInvest(tester, c, '/investments/${a.id}/trade');
      await typeInto(tester, 'trade-qty', '2');
      await tester.tap(find.text('Lembar'));
      await settle(tester, 2);
      expect(find.text('200'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fee-none')));
      await settle(tester, 2);
      // No wallet on the asset: cash effect is off by default.
      await tester.tap(find.byKey(const ValueKey('trade-save')));
      await settle(tester, 8);
      final t = (await real(
        tester,
        () => c.read(assetTradeRepositoryProvider).getAll(),
      )).single;
      expect(t.quantity, 200);
      expect(t.fee, 0);
      expect(t.cashTransactionId, isNull);
      await tearDownApp(tester, c);
    });

    testWidgets('sell shows realized P/L; overselling is blocked', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBCA', 10000);
      final c = investContainer(prices);
      final w = await seedWallet(tester, c);
      final a = await seedAsset(
        tester,
        c,
        AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w.id),
      );
      await seedTrade(
        tester,
        c,
        TradeInput(
          assetId: a.id,
          type: TradeType.buy,
          date: testNow.subtract(const Duration(days: 5)),
          quantity: 1000,
          price: 9000,
        ),
      );
      await pumpInvest(tester, c, '/investments/${a.id}/trade?type=sell');

      await typeInto(tester, 'trade-qty', '20');
      await settle(tester, 2);
      await scrollToFinder(
        tester,
        find.byKey(const ValueKey('trade-oversell')),
      );
      expect(find.textContaining('melebihi kepemilikan'), findsOneWidget);
      expect(find.textContaining('Maks jual 10 lot'), findsOneWidget);
      final save = tester.widget<ChunkyButton>(
        find.byKey(const ValueKey('trade-save')),
      );
      expect(save.onPressed, isNull);

      await tester.dragUntilVisible(
        find.byKey(const ValueKey('trade-qty')),
        find.byType(Scrollable).first,
        const Offset(0, 250),
      );
      await typeInto(tester, 'trade-qty', '5');
      await settle(tester, 2);
      await scrollToFinder(tester, find.byKey(const ValueKey('trade-preview')));
      // 500 × 10.000 − 0,25 % fee (12.500) − 500 × 9.000 = 487.500
      expect(find.text('+Rp 487.500'), findsOneWidget);
      expect(find.text('5 lot'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trade-save')));
      await settle(tester, 8);
      expect(
        await walletBalance(tester, c, w.id),
        20000000 - 9000000 + 4987500,
      );
      await tearDownApp(tester, c);
    });

    testWidgets('dividend → income in "Dividen", shown on the asset', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBRI', 4500);
      final c = investContainer(prices);
      final w = await seedWallet(tester, c);
      final a = await seedAsset(
        tester,
        c,
        AssetInput(kind: AssetKind.stock, symbol: 'BBRI', walletId: w.id),
      );
      await pumpInvest(tester, c, '/investments/${a.id}/trade?type=dividend');
      await typeInto(tester, 'trade-amount', '50000');
      await tester.tap(find.byKey(const ValueKey('trade-save')));
      await settle(tester, 8);
      expect(await walletBalance(tester, c, w.id), 20050000);
      final txs = await real(
        tester,
        () => c.read(transactionRepositoryProvider).list(),
      );
      final div = txs.firstWhere((t) => t.type == TxType.income);
      expect(div.amount, 50000);
      final cat = await real(
        tester,
        () => c.read(categoryRepositoryProvider).getById(div.categoryId!),
      );
      expect(cat!.name, 'Dividen');
      // Back on the asset page (pushed below the form in this test: open it).
      await pumpInvest(tester, c, '/investments/${a.id}');
      await scrollToFinder(
        tester,
        find.byKey(const ValueKey('dividend-total')),
      );
      expect(find.byKey(const ValueKey('dividend-total')), findsOneWidget);
      await tearDownApp(tester, c);
    });
  });

  testWidgets('deleting a trade warns and reverses its cash', (tester) async {
    final prices = TestPrices()..quote('BBCA', 9500);
    final c = investContainer(prices);
    final w = await seedWallet(tester, c);
    final a = await seedAsset(
      tester,
      c,
      AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w.id),
    );
    final v = await seedTrade(
      tester,
      c,
      TradeInput(
        assetId: a.id,
        type: TradeType.buy,
        date: testNow.subtract(const Duration(days: 1)),
        quantity: 100,
        price: 9000,
      ),
    );
    expect(await walletBalance(tester, c, w.id), 20000000 - 900000);
    await pumpInvest(tester, c, '/investments/${a.id}');
    await scrollToFinder(tester, find.byKey(ValueKey('trade-${v.id}')));
    await tester.longPress(find.byKey(ValueKey('trade-${v.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trade-delete')));
    await settle(tester);
    expect(
      find.textContaining('ikut dihapus, jadi saldonya balik'),
      findsOneWidget,
    );
    expect(find.textContaining('-Rp 900.000'), findsWidgets);
    await tester.tap(find.text('HAPUS'));
    await settle(tester, 8);
    expect(await walletBalance(tester, c, w.id), 20000000);
    expect(
      await real(tester, () => c.read(assetTradeRepositoryProvider).getAll()),
      isEmpty,
    );
    await tearDownApp(tester, c);
  });

  group('portfolio page', () {
    testWidgets('shows value, P/L math and holdings', (tester) async {
      final prices = TestPrices()
        ..quote('BBCA', 10000, prevClose: 9800)
        ..quote('BTC', 1000000000, kind: AssetKind.crypto);
      final c = investContainer(prices);
      final a = await seedAsset(
        tester,
        c,
        const AssetInput(
          kind: AssetKind.stock,
          symbol: 'BBCA',
          name: 'Bank Central Asia',
        ),
      );
      await seedTrade(
        tester,
        c,
        TradeInput(
          assetId: a.id,
          type: TradeType.buy,
          date: testNow.subtract(const Duration(days: 3)),
          quantity: 1000,
          price: 9000,
        ),
      );
      await pumpInvest(tester, c, '/investments');
      // 1.000 × 10.000
      expect(find.text('Rp 10.000.000'), findsWidgets);
      // unrealized +1.000.000 (+11,11 %), today +200.000
      expect(find.text('+Rp 1.000.000'), findsWidgets);
      expect(find.text('(+11,11%)'), findsOneWidget);
      expect(find.text('+Rp 200.000'), findsOneWidget);
      expect(find.text('BBCA'), findsWidgets);
      expect(find.textContaining('10 lot'), findsOneWidget);
      expect(find.byKey(const ValueKey('stale-badge')), findsNothing);
      // History builds up: one day only → explanation.
      await scrollToFinder(tester, find.byKey(const ValueKey('history-empty')));
      expect(find.text('Grafiknya lagi tumbuh 🌱'), findsOneWidget);

      await tester.ensureVisible(find.byKey(ValueKey('holding-${a.id}')));
      await settle(tester, 2);
      await tester.tap(find.byKey(ValueKey('holding-${a.id}')));
      await settle(tester);
      expect(find.byKey(const ValueKey('asset-buy')), findsOneWidget);
      await tearDownApp(tester, c);
    });

    testWidgets('stale prices get a badge', (tester) async {
      final prices = TestPrices()
        ..online = false
        ..quote(
          'BBCA',
          9500,
          fetchedAt: testNow.subtract(const Duration(days: 4)),
          serverStale: true,
        );
      final c = investContainer(prices);
      final a = await seedAsset(
        tester,
        c,
        const AssetInput(kind: AssetKind.stock, symbol: 'BBCA'),
      );
      await seedTrade(
        tester,
        c,
        TradeInput(
          assetId: a.id,
          type: TradeType.buy,
          date: testNow.subtract(const Duration(days: 10)),
          quantity: 100,
          price: 9000,
        ),
      );
      await pumpInvest(tester, c, '/investments');
      expect(find.byKey(const ValueKey('stale-badge')), findsOneWidget);
      expect(find.text('HARGA LAMA'), findsOneWidget);
      await tearDownApp(tester, c);
    });

    testWidgets('empty portfolio invites to add an asset', (tester) async {
      final c = investContainer(TestPrices());
      await pumpInvest(tester, c, '/investments');
      expect(find.text('Pantau investasimu di sini'), findsOneWidget);
      await tester.tap(find.text('TAMBAH ASET'));
      await settle(tester);
      expect(find.byKey(const ValueKey('asset-symbol')), findsOneWidget);
      await tearDownApp(tester, c);
    });
  });

  group('transactions list', () {
    testWidgets('investment rows open the trade, not the transaction form', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBCA', 9500);
      final c = investContainer(prices);
      final w = await seedWallet(tester, c);
      final a = await seedAsset(
        tester,
        c,
        AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w.id),
      );
      final v = await seedTrade(
        tester,
        c,
        TradeInput(
          assetId: a.id,
          type: TradeType.buy,
          date: testNow,
          quantity: 1000,
          price: 9500,
        ),
      );
      final router = await pumpInvest(tester, c, '/transactions');
      final row = find.text('Beli BBCA 10 lot @ 9.500');
      expect(row, findsOneWidget);
      expect(find.textContaining('Investasi · RDN BCA'), findsOneWidget);
      await tester.ensureVisible(row);
      await settle(tester, 3);
      await tester.tap(row);
      await settle(tester, 8);
      expect(find.text('Edit transaksi BBCA'), findsOneWidget);
      expect(find.byKey(const ValueKey('trade-qty')), findsOneWidget);
      expect(v.id, isNotEmpty);

      // Long-press offers only "open in portfolio".
      router.go('/transactions');
      await settle(tester);
      await tester.longPress(find.text('Beli BBCA 10 lot @ 9.500'));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-open-investment')), findsOneWidget);
      expect(find.text('EDIT'), findsNothing);
      await tearDownApp(tester, c);
    });

    testWidgets('/transactions/:id of an investment row redirects', (
      tester,
    ) async {
      final prices = TestPrices()..quote('BBCA', 9500);
      final c = investContainer(prices);
      final w = await seedWallet(tester, c);
      final a = await seedAsset(
        tester,
        c,
        AssetInput(kind: AssetKind.stock, symbol: 'BBCA', walletId: w.id),
      );
      final v = await seedTrade(
        tester,
        c,
        TradeInput(
          assetId: a.id,
          type: TradeType.buy,
          date: testNow,
          quantity: 100,
          price: 9500,
        ),
      );
      final router = await pumpInvest(
        tester,
        c,
        '/transactions/${v.transaction!.id}',
      );
      await settle(tester, 8);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/investments/${a.id}/trade/${v.id}',
      );
      await tearDownApp(tester, c);
    });
  });
}
