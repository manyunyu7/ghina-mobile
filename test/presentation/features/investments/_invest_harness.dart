// Harness for the portfolio screens: the real data layer on an in-memory
// drift DB (see ../transactions/_feature_harness.dart) with a fake price
// service.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/investments/controllers/fee_preset_controller.dart';
import 'package:ghina/presentation/features/investments/pages/asset_detail_page.dart';
import 'package:ghina/presentation/features/investments/pages/asset_form_page.dart';
import 'package:ghina/presentation/features/investments/pages/investment_cash_page.dart';
import 'package:ghina/presentation/features/investments/pages/portfolio_page.dart';
import 'package:ghina/presentation/features/investments/pages/trade_form_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transaction_form_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transactions_page.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';
import '../transactions/_feature_harness.dart';

export '../transactions/_feature_harness.dart'
    show settle, tearDownApp, real, testNow, loadFonts, saveShot, shotsDir;

/// Price service fake whose offline mode throws [NetworkFailure] (like the
/// real one).
class TestPrices extends FakePriceRepository {
  bool lookupOffline = false;

  @override
  Future<PriceRefreshResult> refresh(List<String> keys) async {
    if (!online) throw const NetworkFailure();
    return super.refresh(keys);
  }

  @override
  Future<SymbolInfo?> lookup(AssetKind kind, String symbol) async {
    if (lookupOffline) throw const NetworkFailure();
    return super.lookup(kind, symbol);
  }

  /// A server quote (served on refresh / lookup) that is also cached.
  void quote(
    String symbol,
    double price, {
    AssetKind kind = AssetKind.stock,
    double? prevClose,
    String? name,
    DateTime? fetchedAt,
    bool serverStale = false,
    bool cache = true,
  }) {
    final at = fetchedAt ?? testNow;
    final p = SecurityPrice(
      kind: kind,
      symbol: symbol,
      price: price,
      prevClose: prevClose,
      change: prevClose == null ? null : price - prevClose,
      changePct: prevClose == null
          ? null
          : (price - prevClose) / prevClose * 100,
      name: name,
      fetchedAt: at,
      serverStale: serverStale,
      cachedAt: at,
    );
    server[p.key] = p;
    if (cache) s.put(p);
  }
}

ProviderContainer investContainer(TestPrices prices) => makeContainer(
  overrides: <Override>[
    priceRepositoryProvider.overrideWithValue(prices),
    feePresetStoreProvider.overrideWithValue(InMemoryFeePresetStore()),
    tickSourceProvider.overrideWithValue(() => Stream.value(testNow)),
  ],
);

GoRouter investRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/transactions', builder: (_, _) => const TransactionsPage()),
    GoRoute(
      path: '/transactions/:id',
      builder: (_, s) => TransactionFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(path: '/investments', builder: (_, _) => const PortfolioPage()),
    GoRoute(path: '/investments/new', builder: (_, _) => const AssetFormPage()),
    GoRoute(
      path: '/investments/cash/:txId',
      builder: (_, s) =>
          InvestmentCashPage(transactionId: s.pathParameters['txId']!),
    ),
    GoRoute(
      path: '/investments/:id',
      builder: (_, s) => AssetDetailPage(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/investments/:id/edit',
      builder: (_, s) => AssetFormPage(id: s.pathParameters['id']),
    ),
    GoRoute(
      path: '/investments/:id/trade',
      builder: (_, s) => TradeFormPage(
        assetId: s.pathParameters['id']!,
        initialType: s.uri.queryParameters['type'],
      ),
    ),
    GoRoute(
      path: '/investments/:id/trade/:tradeId',
      builder: (_, s) => TradeFormPage(
        assetId: s.pathParameters['id']!,
        tradeId: s.pathParameters['tradeId'],
      ),
    ),
    GoRoute(
      path: '/wallets',
      builder: (_, _) => const Scaffold(body: Text('WALLETS')),
    ),
  ],
);

Future<GoRouter> pumpInvest(
  WidgetTester tester,
  ProviderContainer c,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final router = investRouter(location);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await settle(tester);
  return router;
}

/// Seeds an RDN wallet with [balance] and returns it.
Future<Wallet> seedWallet(
  WidgetTester tester,
  ProviderContainer c, {
  double balance = 20000000,
  String name = 'RDN BCA',
}) => real(
  tester,
  () async => (await c.read(createWalletProvider)(
    WalletInput(
      name: name,
      type: WalletType.investment,
      initialBalance: balance,
    ),
  )).valueOrThrow,
);

Future<Asset> seedAsset(
  WidgetTester tester,
  ProviderContainer c,
  AssetInput input,
) => real(
  tester,
  () async => (await c.read(createAssetProvider)(input)).valueOrThrow,
);

Future<TradeView> seedTrade(
  WidgetTester tester,
  ProviderContainer c,
  TradeInput input,
) => real(
  tester,
  () async => (await c.read(createTradeProvider)(input)).valueOrThrow,
);

Future<double> walletBalance(
  WidgetTester tester,
  ProviderContainer c,
  String id,
) => real(
  tester,
  () async => (await c.read(walletRepositoryProvider).getById(id))!.balance,
);

/// Types into the field with [key] (the inner EditableText).
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await tester.pump();
}

/// Scrolls the page's main list until [finder] is visible.
Future<void> scrollToFinder(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}
