import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_controller.dart';

/// Whether this account may use Screener (only allowlisted
/// accounts; others get 403 `{"error":"forbidden"}`). Learned from the API,
/// remembered per user on the device so the drawer can hide Screener politely.
enum ScreenerAccess { unknown, allowed, forbidden }

/// How long a 403 hides Screener from the menu (the allowlist can change).
const screenerForbiddenTtl = Duration(days: 7);

abstract interface class ScreenerAccessStore {
  /// `(userId, at)` of the last 403, if any.
  Future<({String userId, DateTime at})?> loadForbidden();
  Future<void> saveForbidden(String userId, DateTime at);
  Future<void> clear();
}

class SharedPrefsScreenerAccessStore implements ScreenerAccessStore {
  static const _user = 'screener.forbiddenUser';
  static const _at = 'screener.forbiddenAt';

  @override
  Future<({String userId, DateTime at})?> loadForbidden() async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_user);
    final at = p.getInt(_at);
    if (user == null || at == null) return null;
    return (userId: user, at: DateTime.fromMillisecondsSinceEpoch(at));
  }

  @override
  Future<void> saveForbidden(String userId, DateTime at) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_user, userId);
    await p.setInt(_at, at.millisecondsSinceEpoch);
  }

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_user);
    await p.remove(_at);
  }
}

class InMemoryScreenerAccessStore implements ScreenerAccessStore {
  ({String userId, DateTime at})? value;

  @override
  Future<({String userId, DateTime at})?> loadForbidden() async => value;

  @override
  Future<void> saveForbidden(String userId, DateTime at) async =>
      value = (userId: userId, at: at);

  @override
  Future<void> clear() async => value = null;
}

final screenerAccessStoreProvider = Provider<ScreenerAccessStore>(
  (ref) => SharedPrefsScreenerAccessStore(),
);

/// ```dart
/// ref.watch(screenerAccessProvider) == ScreenerAccess.forbidden // hide the entry
/// ref.read(screenerAccessProvider.notifier).markForbidden();  // after a 403
/// ```
final screenerAccessProvider =
    NotifierProvider<ScreenerAccessController, ScreenerAccess>(
      ScreenerAccessController.new,
    );

class ScreenerAccessController extends Notifier<ScreenerAccess> {
  bool _touched = false;

  ScreenerAccessStore get _store => ref.read(screenerAccessStoreProvider);
  String? get _userId => ref.read(currentUserProvider)?.id;

  @override
  ScreenerAccess build() {
    ref.watch(currentUserProvider.select((u) => u?.id));
    _touched = false;
    _load();
    return ScreenerAccess.unknown;
  }

  Future<void> _load() async {
    try {
      final f = await _store.loadForbidden();
      if (!ref.mounted || _touched || f == null) return;
      final fresh = DateTime.now().difference(f.at) < screenerForbiddenTtl;
      if (f.userId == _userId && fresh) state = ScreenerAccess.forbidden;
    } catch (_) {
      // No storage (tests): stay unknown.
    }
  }

  Future<void> markForbidden() async {
    _touched = true;
    if (state == ScreenerAccess.forbidden) return;
    state = ScreenerAccess.forbidden;
    final user = _userId;
    if (user == null) return;
    try {
      await _store.saveForbidden(user, DateTime.now());
    } catch (_) {}
  }

  Future<void> markAllowed() async {
    _touched = true;
    if (state == ScreenerAccess.allowed) return;
    final was = state;
    state = ScreenerAccess.allowed;
    if (was == ScreenerAccess.forbidden || was == ScreenerAccess.unknown) {
      try {
        await _store.clear();
      } catch (_) {}
    }
  }
}
