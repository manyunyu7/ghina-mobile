import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../domain/usecases/usecases.dart';

/// The user's broker fee rates (buy / sell, fractions of the gross value) —
/// a device preference, not synced (`docs/investments.md` Clarification 9).
abstract interface class FeePresetStore {
  Future<FeePreset?> load();
  Future<void> save(FeePreset value);
}

class SharedPrefsFeePresetStore implements FeePresetStore {
  SharedPrefsFeePresetStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const _buy = 'invest.feeBuy';
  static const _sell = 'invest.feeSell';

  @override
  Future<FeePreset?> load() async {
    final p = await _prefs;
    final b = p.getDouble(_buy), s = p.getDouble(_sell);
    if (b == null && s == null) return null;
    return FeePreset(
      buy: b ?? FeePreset.standard.buy,
      sell: s ?? FeePreset.standard.sell,
    );
  }

  @override
  Future<void> save(FeePreset v) async {
    final p = await _prefs;
    await p.setDouble(_buy, v.buy);
    await p.setDouble(_sell, v.sell);
  }
}

class InMemoryFeePresetStore implements FeePresetStore {
  InMemoryFeePresetStore([this.value]);
  FeePreset? value;

  @override
  Future<FeePreset?> load() async => value;

  @override
  Future<void> save(FeePreset v) async => value = v;
}

final feePresetStoreProvider = Provider<FeePresetStore>(
  (ref) => SharedPrefsFeePresetStore(),
);

/// Current fee rates (default: buy 0.15 %, sell 0.25 %).
final feePresetProvider = NotifierProvider<FeePresetController, FeePreset>(
  FeePresetController.new,
);

class FeePresetController extends Notifier<FeePreset> {
  bool _touched = false;

  @override
  FeePreset build() {
    _touched = false;
    _load();
    return FeePreset.standard;
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(feePresetStoreProvider).load();
      if (!ref.mounted || _touched || v == null) return;
      state = v;
    } catch (_) {
      // Keep the defaults.
    }
  }

  /// Remembers a rate the user typed for [buy] or sell.
  Future<void> setRate({required bool buy, required double rate}) async {
    if (!rate.isFinite || rate < 0 || rate > 0.1) return;
    _touched = true;
    state = buy
        ? FeePreset(buy: rate, sell: state.sell)
        : FeePreset(buy: state.buy, sell: rate);
    try {
      await ref.read(feePresetStoreProvider).save(state);
    } catch (_) {}
  }

  Future<void> reset() async {
    _touched = true;
    state = FeePreset.standard;
    try {
      await ref.read(feePresetStoreProvider).save(state);
    } catch (_) {}
  }
}
