import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';
import 'package:ghina/presentation/state/balance_privacy_provider.dart';

import '../shell/test_utils.dart';
import '_task_harness.dart';

void main() {
  testWidgets('eye on the balance card hides amounts and saves it', (
    tester,
  ) async {
    final store = InMemoryBalancePrivacyStore();
    await pumpPage(
      tester,
      const BalancePrivacyScope(child: HomePage()),
      overrides: withTasks([
        ...pageOverrides(),
        balancePrivacyStoreProvider.overrideWithValue(store),
      ]),
    );
    await settle(tester, 6);
    expect(find.text('Rp 4.550.000'), findsOneWidget);

    await tester.tap(find.byTooltip('Sembunyikan saldo'));
    await settle(tester);
    expect(store.value.hidden, isTrue);
    expect(find.text('Rp 4.550.000'), findsNothing);
    expect(find.text('Rp •••••'), findsWidgets);
    expect(find.textContaining('Hari ini keluar Rp •••••'), findsOneWidget);

    // Long-press peeks, release hides again.
    final g = await tester.startGesture(
      tester.getCenter(find.text('Rp •••••').first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Rp 4.550.000'), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(find.text('Rp 4.550.000'), findsNothing);
    expect(store.value.hidden, isTrue); // peeking doesn't change the setting

    await tester.tap(find.byTooltip('Tampilkan saldo'));
    await settle(tester);
    expect(find.text('Rp 4.550.000'), findsOneWidget);
    expect(store.value.hidden, isFalse);
  });

  testWidgets('starts hidden from the saved preference', (tester) async {
    await pumpPage(
      tester,
      const BalancePrivacyScope(child: HomePage()),
      overrides: withTasks([
        ...pageOverrides(),
        balancePrivacyInitialProvider.overrideWithValue(
          const BalancePrivacy(hideOnLaunch: true),
        ),
        balancePrivacyStoreProvider.overrideWithValue(
          InMemoryBalancePrivacyStore(),
        ),
      ]),
    );
    await settle(tester, 6);
    expect(find.text('Rp 4.550.000'), findsNothing);
    expect(find.byTooltip('Tampilkan saldo'), findsOneWidget);
  });
}
