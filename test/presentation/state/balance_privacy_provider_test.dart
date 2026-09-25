import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/state/balance_privacy_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container([List<Override> overrides = const []]) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to visible', () async {
    final c = container();
    expect(c.read(balancePrivacyProvider).hidden, isFalse);
    await _flush();
    expect(c.read(balancePrivacyProvider), const BalancePrivacy());
  });

  test('toggle flips hidden and writes the store', () async {
    final store = InMemoryBalancePrivacyStore();
    final c = container([balancePrivacyStoreProvider.overrideWithValue(store)]);
    c.read(balancePrivacyProvider);
    await _flush();
    await c.read(balancePrivacyProvider.notifier).toggle();
    expect(c.read(balancePrivacyProvider).hidden, isTrue);
    expect(store.value.hidden, isTrue);
    await c.read(balancePrivacyProvider.notifier).toggle();
    expect(c.read(balancePrivacyProvider).hidden, isFalse);
    expect(store.value.hidden, isFalse);
  });

  test('persists across container recreation (shared_preferences)', () async {
    final a = container();
    a.read(balancePrivacyProvider);
    await _flush();
    await a.read(balancePrivacyProvider.notifier).setHidden(true);
    a.dispose();

    final b = container();
    b.read(balancePrivacyProvider); // starts loading
    await _flush();
    await _flush();
    expect(b.read(balancePrivacyProvider).hidden, isTrue);

    // Preloaded path (what main.dart does) is synchronous.
    final pre = await preloadBalancePrivacy();
    final d = container([balancePrivacyInitialProvider.overrideWithValue(pre)]);
    expect(d.read(balancePrivacyProvider).hidden, isTrue);
  });

  test('"hide on launch" starts hidden even if last shown', () async {
    final a = container();
    a.read(balancePrivacyProvider);
    await _flush();
    final n = a.read(balancePrivacyProvider.notifier);
    await n.setHideOnLaunch(true);
    await n.setHidden(false);
    expect(a.read(balancePrivacyProvider).hidden, isFalse);
    a.dispose();

    final pre = await preloadBalancePrivacy();
    expect(pre, const BalancePrivacy(hideOnLaunch: true));
    final b = container([balancePrivacyInitialProvider.overrideWithValue(pre)]);
    expect(
      b.read(balancePrivacyProvider),
      const BalancePrivacy(hidden: true, hideOnLaunch: true),
    );
  });

  test('a toggle before the async load finishes wins', () async {
    SharedPreferences.setMockInitialValues({'privacy.balanceHidden': true});
    final c = container();
    c.read(balancePrivacyProvider);
    await c.read(balancePrivacyProvider.notifier).setHidden(false);
    await _flush();
    await _flush();
    expect(c.read(balancePrivacyProvider).hidden, isFalse);
  });
}
