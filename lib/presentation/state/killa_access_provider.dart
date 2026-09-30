import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_controller.dart';

/// Whether this account may use Killa (`docs/killa.md`: only allowlisted
/// accounts; others get 403 `{"error":"forbidden"}`). Learned from the API,
/// remembered per user on the device so the drawer can hide Killa politely.
enum KillaAccess { unknown, allowed, forbidden }

/// How long a 403 hides Killa from the menu (the allowlist can change).
const killaForbiddenTtl = Duration(days: 7);

abstract interface class KillaAccessStore {
  /// `(userId, at)` of the last 403, if any.
  Future<({String userId, DateTime at})?> loadForbidden();
  Future<void> saveForbidden(String userId, DateTime at);
  Future<void> clear();
}

class SharedPrefsKillaAccessStore implements KillaAccessStore {
  static const _user = 'killa.forbiddenUser';
  static const _at = 'killa.forbiddenAt';

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

class InMemoryKillaAccessStore implements KillaAccessStore {
  ({String userId, DateTime at})? value;

  @override
  Future<({String userId, DateTime at})?> loadForbidden() async => value;

  @override
  Future<void> saveForbidden(String userId, DateTime at) async =>
      value = (userId: userId, at: at);

  @override
  Future<void> clear() async => value = null;
}

final killaAccessStoreProvider = Provider<KillaAccessStore>(
  (ref) => SharedPrefsKillaAccessStore(),
);

/// ```dart
/// ref.watch(killaAccessProvider) == KillaAccess.forbidden // hide the entry
/// ref.read(killaAccessProvider.notifier).markForbidden();  // after a 403
/// ```
final killaAccessProvider =
    NotifierProvider<KillaAccessController, KillaAccess>(
      KillaAccessController.new,
    );

class KillaAccessController extends Notifier<KillaAccess> {
  bool _touched = false;

  KillaAccessStore get _store => ref.read(killaAccessStoreProvider);
  String? get _userId => ref.read(currentUserProvider)?.id;

  @override
  KillaAccess build() {
    ref.watch(currentUserProvider.select((u) => u?.id));
    _touched = false;
    _load();
    return KillaAccess.unknown;
  }

  Future<void> _load() async {
    try {
      final f = await _store.loadForbidden();
      if (!ref.mounted || _touched || f == null) return;
      final fresh = DateTime.now().difference(f.at) < killaForbiddenTtl;
      if (f.userId == _userId && fresh) state = KillaAccess.forbidden;
    } catch (_) {
      // No storage (tests): stay unknown.
    }
  }

  Future<void> markForbidden() async {
    _touched = true;
    if (state == KillaAccess.forbidden) return;
    state = KillaAccess.forbidden;
    final user = _userId;
    if (user == null) return;
    try {
      await _store.saveForbidden(user, DateTime.now());
    } catch (_) {}
  }

  Future<void> markAllowed() async {
    _touched = true;
    if (state == KillaAccess.allowed) return;
    final was = state;
    state = KillaAccess.allowed;
    if (was == KillaAccess.forbidden || was == KillaAccess.unknown) {
      try {
        await _store.clear();
      } catch (_) {}
    }
  }
}
