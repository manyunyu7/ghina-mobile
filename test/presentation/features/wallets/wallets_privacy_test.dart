import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/balance_privacy_provider.dart';

import '../transactions/_feature_harness.dart';

/// Like `pumpApp`, plus the app's root BalancePrivacyScope.
Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = makeRouter('/wallets');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: GhinaTheme.light(),
        routerConfig: router,
        builder: (_, child) => BalancePrivacyScope(child: child!),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('header eye masks wallet total and cards; persists', (
    tester,
  ) async {
    final store = InMemoryBalancePrivacyStore();
    final c = makeContainer(
      overrides: [balancePrivacyStoreProvider.overrideWithValue(store)],
    );
    await tester.runAsync(() async {
      (c.read(clockProvider) as FixedClock).advance(const Duration(seconds: 1));
      (await c.read(createWalletProvider)(
        const WalletInput(name: 'Tunai', initialBalance: 150000),
      )).valueOrThrow;
    });
    await _pump(tester, c);
    await settle(tester);
    expect(find.text('Rp 150.000'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('wallet-privacy')));
    await settle(tester);
    expect(find.text('Rp 150.000'), findsNothing);
    expect(find.text('Rp •••••'), findsWidgets);
    expect(store.value.hidden, isTrue);
    expect(c.read(balancePrivacyProvider).hidden, isTrue);

    // Forms where the user types amounts stay visible.
    await tester.tap(find.text('Tunai'));
    await settle(tester);
    expect(find.text('Rp 150.000'), findsWidgets);

    await tearDownApp(tester, c);
  });
}
