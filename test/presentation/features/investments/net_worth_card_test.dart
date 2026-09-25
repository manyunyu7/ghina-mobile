import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/home/widgets/balance_card.dart';
import 'package:go_router/go_router.dart';

final _now = DateTime(2026, 9, 23, 12);

DashboardSummary _dash({double investments = 0}) => DashboardSummary(
  month: const YearMonth(2026, 9),
  totalBalance: 4550000,
  wallets: const [],
  monthIncome: 0,
  monthExpense: 0,
  todayExpense: 0,
  todayIncome: 0,
  monthBudgeted: 0,
  spendingByCategory: const [],
  trend: const [],
  recent: const [],
  investmentsValue: investments,
);

PortfolioSummary _portfolio() {
  final a = Asset(
    id: 'a1',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    createdAt: _now,
    updatedAt: _now,
  );
  return buildPortfolio(
    assets: [a],
    trades: [
      AssetTrade(
        id: 't1',
        assetId: 'a1',
        type: TradeType.buy,
        date: _now.subtract(const Duration(days: 2)),
        quantity: 1000,
        price: 9000,
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    prices: {
      'stock:BBCA': SecurityPrice(
        kind: AssetKind.stock,
        symbol: 'BBCA',
        price: 10000,
        prevClose: 9800,
        fetchedAt: _now,
        cachedAt: _now,
      ),
    },
    now: _now,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required DashboardSummary dash,
  PortfolioSummary portfolio = PortfolioSummary.empty,
  bool hidden = false,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: BalanceCard(dash: dash, currency: 'IDR'),
          ),
        ),
      ),
      GoRoute(
        path: '/investments',
        builder: (_, _) => const Scaffold(body: Text('PORTFOLIO')),
      ),
      GoRoute(
        path: '/wallets',
        builder: (_, _) => const Scaffold(body: Text('WALLETS')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        watchPortfolioProvider.overrideWith((ref) => Stream.value(portfolio)),
      ],
      child: MoneyVisibility(
        hidden: hidden,
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('net worth card: Kas · Investasi breakdown and today', (
    tester,
  ) async {
    await _pump(
      tester,
      dash: _dash(investments: 10000000),
      portfolio: _portfolio(),
    );
    expect(find.text('KEKAYAAN BERSIH'), findsOneWidget);
    expect(find.text('Rp 14.550.000'), findsOneWidget);
    expect(find.text('Rp 4.550.000'), findsOneWidget); // Kas
    expect(find.text('Rp 10.000.000'), findsOneWidget); // Investasi
    expect(find.text('+Rp 200 rb'), findsOneWidget); // today, compact
    expect(find.text(' (+2,04%)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-investments')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PORTFOLIO'), findsOneWidget);
  });

  testWidgets('respects balance privacy', (tester) async {
    await _pump(
      tester,
      dash: _dash(investments: 10000000),
      portfolio: _portfolio(),
      hidden: true,
    );
    expect(find.text('Rp 14.550.000'), findsNothing);
    expect(find.text('Rp 10.000.000'), findsNothing);
    expect(find.text('Rp •••••'), findsWidgets);
    // The percent isn't an amount: still visible.
    expect(find.text(' (+2,04%)'), findsOneWidget);
  });

  testWidgets('without investments it stays "Total saldo"', (tester) async {
    await _pump(tester, dash: _dash());
    expect(find.text('TOTAL SALDO'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-investments')), findsNothing);
    expect(find.text('Rp 4.550.000'), findsOneWidget);
  });
}
