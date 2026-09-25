import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/analytics/pages/analytics_page.dart';
import 'package:ghina/presentation/features/analytics/pages/category_analytics_page.dart';
import 'package:go_router/go_router.dart';

import '../budgets/finance_test_harness.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Center(child: Text('HOME'))),
    ),
    GoRoute(path: '/analytics', builder: (_, _) => const AnalyticsPage()),
    GoRoute(
      path: '/analytics/category/:id',
      builder: (_, s) =>
          CategoryAnalyticsPage(categoryKey: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/:a/:b',
      builder: (_, s) => Scaffold(body: Text('STUB ${s.uri}')),
    ),
    GoRoute(
      path: '/:a',
      builder: (_, s) => Scaffold(body: Text('STUB ${s.uri}')),
    ),
  ],
);

Future<GoRouter> pump(
  WidgetTester tester,
  FinanceHarness h, {
  String location = '/analytics',
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = _router();
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: RepaintBoundary(
        key: shotKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 2,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  unawaited(router.push(location));
  await settle(tester);
  return router;
}

/// seedRich + timed September expenses with notes (hour / merchant charts).
void seedAnalytics(FinanceHarness h) {
  h.seedRich();
  const notes = ['Kopi Kenangan', 'Warteg Bahari', 'Grab', 'Indomaret'];
  const cats = ['food', 'food', 'transport', 'shop'];
  for (var d = 1; d <= 23; d++) {
    final k = d % 4;
    h.tx(
      TxType.expense,
      18000.0 + (d * 7919 % 90) * 1000,
      DateTime(2026, 9, d, 7 + (d * 5) % 15, 15),
      categoryId: cats[k],
      note: notes[k],
      walletId: d.isEven ? 'gopay' : 'bca',
    );
  }
  // Never spending: adjustments and transfers (off by default).
  h.tx(TxType.adjustment, -2000000, DateTime(2026, 9, 10, 10));
  h.tx(TxType.adjustment, 5000000, DateTime(2026, 9, 11, 10));
  h.transactions.s.put(
    Transaction(
      id: 'xfer',
      walletId: 'bca',
      toWalletId: 'gopay',
      type: TxType.transfer,
      amount: 750000,
      date: DateTime(2026, 9, 9, 8),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Finder _inList(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('analytics-list')),
  matching: f,
);

Future<void> jumpTo(WidgetTester tester, double offset) async {
  final s = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(const ValueKey('analytics-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  s.position.jumpTo(offset.clamp(0, s.position.maxScrollExtent));
  await settle(tester, 8);
}

void main() {
  setUpAll(loadGhinaFonts);

  testWidgets('renders every section for this month', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(390, 7000));
    expect(find.text('Analitik Pengeluaran'), findsOneWidget);
    expect(find.text('TOTAL PENGELUARAN'), findsOneWidget);
    for (final k in [
      'card-insights',
      'card-categories',
      'card-trend',
      'card-heatmap',
      'card-weekday',
      'card-hour',
      'card-budgets',
      'card-wallets',
      'card-income',
      'card-largest',
      'kpi-delta',
      'kpi-projection',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.text('Makan & Minum'), findsWidgets);
    expect(find.text('Harian'), findsOneWidget);
    expect(find.text('Anggaran vs realisasi'), findsOneWidget);
    expect(find.text('GoPay'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjustments and transfers are not spending', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    final expected = h.transactions.s.items.values
        .where(
          (t) =>
              t.type == TxType.expense &&
              t.date.year == 2026 &&
              t.date.month == 9,
        )
        .fold<double>(0, (s, t) => s + t.amount);
    await pump(tester, h, size: const Size(390, 1600));
    await settle(tester, 12); // count-up
    final total = tester.widget<MoneyText>(
      find.byKey(const ValueKey('hero-total')),
    );
    expect(total.amount, expected);

    await tapKey(tester, 'filter-transfers');
    await settle(tester);
    final withT = tester.widget<MoneyText>(
      find.byKey(const ValueKey('hero-total')),
    );
    expect(withT.amount, expected + 750000);
    expect(find.text('termasuk transfer keluar'), findsOneWidget);
  });

  testWidgets('switching period changes granularity; compare toggles', (
    tester,
  ) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(390, 3000));
    await tapKey(tester, 'preset-last6Months');
    await settle(tester);
    expect(find.text('Bulanan'), findsOneWidget);
    expect(find.text('6 bulan terakhir · 1 Apr – 30 Sep 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi-projection')), findsNothing);

    await tapKey(tester, 'preset-last3Months');
    await settle(tester);
    expect(find.text('Mingguan'), findsOneWidget);

    expect(find.byKey(const ValueKey('kpi-delta')), findsOneWidget);
    await tapKey(tester, 'filter-compare');
    await settle(tester);
    expect(find.byKey(const ValueKey('kpi-delta')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wallet filter narrows the numbers', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(390, 3000));
    await tapKey(tester, 'filter-wallets');
    await settle(tester);
    await tester.tap(find.text('GoPay').last);
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('wallets-apply')));
    await settle(tester);
    expect(find.text('1 dompet dipilih'), findsOneWidget);
    final expected = h.transactions.s.items.values
        .where(
          (t) =>
              t.type == TxType.expense &&
              t.walletId == 'gopay' &&
              t.date.month == 9,
        )
        .fold<double>(0, (s, t) => s + t.amount);
    await settle(tester, 12);
    expect(
      tester.widget<MoneyText>(find.byKey(const ValueKey('hero-total'))).amount,
      expected,
    );
  });

  testWidgets('legend row drills into a category', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(390, 4000));
    await tester.tap(find.byKey(const ValueKey('donut-row-food')));
    await settle(tester);
    expect(find.byType(CategoryAnalyticsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('category-hero')), findsOneWidget);
    expect(find.text('Paling sering'), findsOneWidget);
    expect(find.text('Kopi Kenangan'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('largest expense opens the transaction', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(390, 7000));
    final tile = _inList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key! as ValueKey).value}'.startsWith('largest-'),
      ),
    ).first;
    await tester.tap(tile);
    await settle(tester);
    expect(find.textContaining('STUB /transactions/'), findsOneWidget);
  });

  testWidgets('empty state without transactions', (tester) async {
    await pump(tester, FinanceHarness());
    expect(find.text('Belum ada pengeluaran di periode ini'), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-thisWeek')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty category drill-down', (tester) async {
    final h = FinanceHarness()..seedRich();
    await pump(tester, h, location: '/analytics/category/fun');
    expect(find.text('Belum ada pengeluaran Hiburan'), findsOneWidget);
  });

  testWidgets('many categories, huge and tiny amounts', (tester) async {
    final h = FinanceHarness()..addWallet('bca', 'BCA', 0);
    for (var i = 0; i < 14; i++) {
      h.cat(
        'c$i',
        'Kategori nomor $i yang namanya panjang',
        '#${(0x224466 + i * 0x0a0b0c).toRadixString(16).padLeft(6, '0')}',
        'circle',
      );
      h.tx(
        TxType.expense,
        i == 0 ? 987654321000 : 500.0 + i,
        DateTime(2026, 9, 1 + i, 10),
        categoryId: 'c$i',
      );
    }
    await pump(tester, h, size: const Size(360, 7000), textScale: 1.3);
    expect(find.text('Lainnya'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('small phone, large text (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      final h = FinanceHarness();
      seedAnalytics(h);
      await pump(
        tester,
        h,
        size: const Size(360, 7400),
        textScale: 1.3,
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('donut-row-food')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  // GHINA_SHOTS_DIR=… flutter test test/presentation/features/analytics
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('screenshots $mode', (tester) async {
      final h = FinanceHarness();
      seedAnalytics(h);
      await pump(tester, h, dark: dark);
      await shot(tester, 'analytics_top_$mode');
      for (final (i, off) in [900.0, 1750.0, 2600.0, 3450.0, 4300.0].indexed) {
        await jumpTo(tester, off);
        await shot(tester, 'analytics_${i + 1}_$mode');
      }
      await pump(tester, h, dark: dark, location: '/analytics/category/food');
      await shot(tester, 'analytics_category_$mode');
      await pump(tester, h, dark: dark, size: const Size(390, 6400));
      await tapKey(tester, 'preset-last6Months');
      await settle(tester);
      await shot(tester, 'analytics_full6m_$mode');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('screenshots small', (tester) async {
    final h = FinanceHarness();
    seedAnalytics(h);
    await pump(tester, h, size: const Size(360, 640), textScale: 1.3);
    await shot(tester, 'analytics_small_top');
    for (final (i, off) in [700.0, 1500.0, 2400.0].indexed) {
      await jumpTo(tester, off);
      await shot(tester, 'analytics_small_${i + 1}');
    }
    expect(tester.takeException(), isNull);
  });
}
