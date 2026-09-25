import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/format/money_visibility.dart';

/// Balance privacy ("sembunyikan saldo"): device-local, not synced.
class BalancePrivacy {
  const BalancePrivacy({this.hidden = false, this.hideOnLaunch = false});

  /// Amounts are masked right now (persisted: survives restarts).
  final bool hidden;

  /// Settings → "Sembunyikan saldo saat membuka app": every launch starts
  /// hidden regardless of the last state.
  final bool hideOnLaunch;

  /// The state a fresh launch should start in.
  BalancePrivacy get atLaunch =>
      hideOnLaunch && !hidden ? copyWith(hidden: true) : this;

  BalancePrivacy copyWith({bool? hidden, bool? hideOnLaunch}) => BalancePrivacy(
    hidden: hidden ?? this.hidden,
    hideOnLaunch: hideOnLaunch ?? this.hideOnLaunch,
  );

  @override
  bool operator ==(Object other) =>
      other is BalancePrivacy &&
      other.hidden == hidden &&
      other.hideOnLaunch == hideOnLaunch;

  @override
  int get hashCode => Object.hash(hidden, hideOnLaunch);
}

abstract interface class BalancePrivacyStore {
  Future<BalancePrivacy> load();
  Future<void> save(BalancePrivacy value);
}

class SharedPrefsBalancePrivacyStore implements BalancePrivacyStore {
  SharedPrefsBalancePrivacyStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const _hidden = 'privacy.balanceHidden';
  static const _hideOnLaunch = 'privacy.hideBalanceOnLaunch';

  @override
  Future<BalancePrivacy> load() async {
    final p = await _prefs;
    return BalancePrivacy(
      hidden: p.getBool(_hidden) ?? false,
      hideOnLaunch: p.getBool(_hideOnLaunch) ?? false,
    );
  }

  @override
  Future<void> save(BalancePrivacy v) async {
    final p = await _prefs;
    await p.setBool(_hidden, v.hidden);
    await p.setBool(_hideOnLaunch, v.hideOnLaunch);
  }
}

class InMemoryBalancePrivacyStore implements BalancePrivacyStore {
  InMemoryBalancePrivacyStore([this.value = const BalancePrivacy()]);

  BalancePrivacy value;

  @override
  Future<BalancePrivacy> load() async => value;

  @override
  Future<void> save(BalancePrivacy v) async => value = v;
}

final balancePrivacyStoreProvider = Provider<BalancePrivacyStore>(
  (ref) => SharedPrefsBalancePrivacyStore(),
);

/// Preloaded before `runApp` (see `main.dart`) so a "start hidden" launch never
/// flashes real amounts. Null → [BalancePrivacyController] loads async.
final balancePrivacyInitialProvider = Provider<BalancePrivacy?>((ref) => null);

/// Global balance privacy. Default visible.
///
/// ```dart
/// ref.watch(balancePrivacyProvider).hidden;
/// ref.read(balancePrivacyProvider.notifier).toggle();
/// ```
final balancePrivacyProvider =
    NotifierProvider<BalancePrivacyController, BalancePrivacy>(
      BalancePrivacyController.new,
    );

class BalancePrivacyController extends Notifier<BalancePrivacy> {
  bool _touched = false;

  BalancePrivacyStore get _store => ref.read(balancePrivacyStoreProvider);

  @override
  BalancePrivacy build() {
    final initial = ref.watch(balancePrivacyInitialProvider);
    if (initial != null) return initial.atLaunch;
    _touched = false;
    _load();
    return const BalancePrivacy();
  }

  Future<void> _load() async {
    final v = await _store.load();
    // A user action before the load finished wins.
    if (!ref.mounted || _touched) return;
    state = v.atLaunch;
  }

  Future<void> _set(BalancePrivacy v) async {
    _touched = true;
    state = v;
    await _store.save(v);
  }

  Future<void> setHidden(bool hidden) => _set(state.copyWith(hidden: hidden));

  Future<void> toggle() => setHidden(!state.hidden);

  Future<void> setHideOnLaunch(bool value) =>
      _set(state.copyWith(hideOnLaunch: value));
}

/// Loads the saved preference (call before `runApp`).
Future<BalancePrivacy> preloadBalancePrivacy([BalancePrivacyStore? store]) =>
    (store ?? SharedPrefsBalancePrivacyStore()).load().catchError(
      (_) => const BalancePrivacy(),
    );

/// Feeds [balancePrivacyProvider] into the design system's [MoneyVisibility]
/// (placed once at the app root; every `MoneyText` below reads it).
class BalancePrivacyScope extends ConsumerWidget {
  const BalancePrivacyScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancePrivacyProvider.select((s) => s.hidden));
    return MoneyVisibility(
      hidden: hidden,
      onToggle: _toggler(ref),
      child: child,
    );
  }

  // Stable identity per notifier so MoneyVisibility doesn't over-notify.
  static final _cache = Expando<VoidCallback>();
  VoidCallback _toggler(WidgetRef ref) {
    final n = ref.read(balancePrivacyProvider.notifier);
    return _cache[n] ??= () => n.toggle();
  }
}
