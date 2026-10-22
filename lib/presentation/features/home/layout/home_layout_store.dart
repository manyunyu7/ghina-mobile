import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_layout.dart';
import 'home_presets.dart';

const _key = 'home.layout.v1';

/// The Beranda layout, kept on this device only (shared_preferences; there is
/// no synced settings store). It starts as the default preset and swaps to the
/// saved one as soon as storage answers, so Beranda never waits on it.
final homeLayoutProvider = NotifierProvider<HomeLayoutNotifier, HomeLayout>(
  HomeLayoutNotifier.new,
);

class HomeLayoutNotifier extends Notifier<HomeLayout> {
  bool _touched = false;

  @override
  HomeLayout build() {
    _load();
    return homeDefaultLayout();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = HomeLayout.decode(prefs.getString(_key));
      // An edit made before storage answered wins.
      if (saved != null && !_touched && ref.mounted) state = saved;
    } catch (_) {}
  }

  void set(HomeLayout layout) {
    _touched = true;
    state = layout;
    _save(layout);
  }

  void applyPreset(HomePreset p) => set(p.toLayout());

  /// Back to the default preset.
  void reset() => set(homeDefaultLayout());

  Future<void> _save(HomeLayout layout) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        layout.encode(),
      );
    } catch (_) {}
  }
}
