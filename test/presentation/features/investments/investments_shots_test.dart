// Visual self-review of the portfolio screens (and an overflow check at
// 360×640 @1.3). PNGs only when GHINA_SHOTS_DIR is set.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '_invest_harness.dart';

const _key = ValueKey('shot');

Future<({ProviderContainer c, Asset bbca, Wallet w})> _seed(
  WidgetTester tester,
) async {
  final prices = TestPrices()
    ..quote('BBCA', 10125, prevClose: 9975, name: 'Bank Central Asia Tbk')
    ..quote('BBRI', 4380, prevClose: 4450, name: 'Bank Rakyat Indonesia')
    ..quote('BTC', 1052000000, prevClose: 1040000000, kind: AssetKind.crypto);
  final c = investContainer(prices);
  final w = await seedWallet(tester, c, balance: 25000000);
  final bbca = await seedAsset(
    tester,
    c,
    AssetInput(
      kind: AssetKind.stock,
      symbol: 'BBCA',
      name: 'Bank Central Asia Tbk',
      walletId: w.id,
    ),
  );
  final bbri = await seedAsset(
    tester,
    c,
    AssetInput(
      kind: AssetKind.stock,
      symbol: 'BBRI',
      name: 'Bank Rakyat Indonesia',
      walletId: w.id,
    ),
  );
  final btc = await seedAsset(
    tester,
    c,
    const AssetInput(kind: AssetKind.crypto, symbol: 'BTC', name: 'Bitcoin'),
  );
  final gold = await seedAsset(
    tester,
    c,
    const AssetInput(
      kind: AssetKind.gold,
      symbol: 'ANTAM',
      name: 'Emas Antam',
      manualPrice: 1350000,
    ),
  );
  DateTime ago(int d) => testNow.subtract(Duration(days: d));
  for (final t in [
    TradeInput(
      assetId: bbca.id,
      type: TradeType.buy,
      date: ago(60),
      quantity: 1000,
      price: 9200,
      fee: 13800,
    ),
    TradeInput(
      assetId: bbca.id,
      type: TradeType.sell,
      date: ago(20),
      quantity: 300,
      price: 9900,
      fee: 7425,
    ),
    TradeInput(
      assetId: bbca.id,
      type: TradeType.dividend,
      date: ago(10),
      amount: 190000,
    ),
    TradeInput(
      assetId: bbri.id,
      type: TradeType.buy,
      date: ago(40),
      quantity: 2000,
      price: 4700,
      fee: 14100,
    ),
    TradeInput(
      assetId: btc.id,
      type: TradeType.buy,
      date: ago(30),
      quantity: 0.005,
      price: 980000000,
    ),
    TradeInput(
      assetId: gold.id,
      type: TradeType.buy,
      date: ago(90),
      quantity: 5,
      price: 1150000,
    ),
  ]) {
    await seedTrade(tester, c, t);
  }
  await real(tester, () async {
    final repo = c.read(portfolioSnapshotRepositoryProvider);
    var v = 26400000.0;
    for (var i = 30; i >= 1; i--) {
      v += ((i * 7919) % 900000) - 420000;
      await repo.put(
        PortfolioPoint(date: dateKey(ago(i)), value: v, cost: 24600000),
        ago(i),
      );
    }
  });
  return (c: c, bbca: bbca, w: w);
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<void> Function()? before,
}) async {
  await loadFonts();
  final s = await _seed(tester);
  final loc = location
      .replaceAll('{bbca}', s.bbca.id)
      .replaceAll('{w}', s.w.id);
  await pumpInvest(
    tester,
    s.c,
    loc,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: _key,
  );
  await settle(tester, 6);
  if (before != null) await before();
  await tester.pump(const Duration(seconds: 1));
  await saveShot(tester, _key, 'b3w2/investments_$name');
  await tearDownApp(tester, s.c);
}

void main() {
  for (final dark in [false, true]) {
    final m = dark ? 'dark' : 'light';
    testWidgets(
      'portfolio $m',
      (t) => _shot(t, 'portfolio_$m', '/investments', dark: dark),
    );
    testWidgets(
      'portfolio lower $m',
      (t) => _shot(
        t,
        'portfolio_lower_$m',
        '/investments',
        dark: dark,
        before: () async {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
          await settle(t, 3);
        },
      ),
    );
    testWidgets(
      'detail $m',
      (t) => _shot(t, 'detail_$m', '/investments/{bbca}', dark: dark),
    );
    testWidgets(
      'trade $m',
      (t) => _shot(
        t,
        'trade_$m',
        '/investments/{bbca}/trade?type=sell',
        dark: dark,
        before: () async {
          await typeInto(t, 'trade-qty', '3');
          await settle(t, 2);
          await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
          await settle(t, 3);
        },
      ),
    );
  }
  testWidgets(
    'add asset',
    (t) => _shot(
      t,
      'add_light',
      '/investments/new',
      before: () async {
        await typeInto(t, 'asset-symbol', 'BBRI');
        await t.pump(const Duration(milliseconds: 600));
        await settle(t, 3);
      },
    ),
  );
  testWidgets('transactions', (t) => _shot(t, 'tx_light', '/transactions'));
  // Small phone, large text: no overflow anywhere.
  for (final (name, loc) in [
    ('portfolio', '/investments'),
    ('detail', '/investments/{bbca}'),
    ('trade', '/investments/{bbca}/trade'),
    ('add', '/investments/new'),
  ]) {
    testWidgets(
      'small $name',
      (t) => _shot(
        t,
        'small_$name',
        loc,
        size: const Size(360, 640),
        textScale: 1.3,
      ),
    );
  }
}
