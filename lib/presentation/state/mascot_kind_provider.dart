import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../di/di.dart' show launcherIconProvider;
import '../design_system/mascot/mascot_kind.dart';

/// The chosen mascot ("Pilih maskot"): device-local, not synced.
abstract interface class MascotKindPrefs {
  Future<MascotKind> load();
  Future<void> save(MascotKind kind);
}

class SharedPrefsMascotKindPrefs implements MascotKindPrefs {
  SharedPrefsMascotKindPrefs([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const key = 'mascot.kind';

  @override
  Future<MascotKind> load() async =>
      MascotKind.fromId((await _prefs).getString(key));

  @override
  Future<void> save(MascotKind kind) async =>
      (await _prefs).setString(key, kind.id);
}

class InMemoryMascotKindPrefs implements MascotKindPrefs {
  InMemoryMascotKindPrefs([this.value = MascotKind.fallback]);

  MascotKind value;

  @override
  Future<MascotKind> load() async => value;

  @override
  Future<void> save(MascotKind kind) async => value = kind;
}

final mascotKindPrefsProvider = Provider<MascotKindPrefs>(
  (ref) => SharedPrefsMascotKindPrefs(),
);

/// Preloaded before `runApp` (see `main.dart`) so the chosen mascot shows
/// from the first frame. Null → [MascotKindController] loads async.
final mascotKindInitialProvider = Provider<MascotKind?>((ref) => null);

/// The user's mascot. Default: the money tree.
///
/// ```dart
/// ref.watch(mascotKindProvider);                       // MascotKind
/// ref.read(mascotKindProvider.notifier).select(MascotKind.kucing);
/// ```
final mascotKindProvider = NotifierProvider<MascotKindController, MascotKind>(
  MascotKindController.new,
);

class MascotKindController extends Notifier<MascotKind> {
  bool _touched = false;

  MascotKindPrefs get _prefs => ref.read(mascotKindPrefsProvider);

  @override
  MascotKind build() {
    final initial = ref.watch(mascotKindInitialProvider);
    if (initial != null) {
      Future.microtask(syncLauncherIcon);
      return initial;
    }
    _touched = false;
    _load();
    return MascotKind.fallback;
  }

  Future<void> _load() async {
    final MascotKind v;
    try {
      v = await _prefs.load();
    } catch (_) {
      return;
    }
    // A pick made before the load finished wins.
    if (!ref.mounted || _touched) return;
    state = v;
    await syncLauncherIcon();
  }

  Future<void> select(MascotKind kind) async {
    _touched = true;
    state = kind;
    await _prefs.save(kind);
    await syncLauncherIcon();
  }

  /// Points the home-screen icon (and the Android 12+ splash) at the current
  /// mascot. Called on every pick and once per app start, which also repairs
  /// a mismatch (e.g. restored prefs after a reinstall). Never throws.
  Future<void> syncLauncherIcon() async {
    try {
      await ref.read(launcherIconProvider).apply(state.id);
    } catch (_) {}
  }
}

/// Loads the saved mascot (call before `runApp`).
Future<MascotKind> preloadMascotKind([MascotKindPrefs? prefs]) =>
    (prefs ?? SharedPrefsMascotKindPrefs()).load().catchError(
      (_) => MascotKind.fallback,
    );

/// Feeds [mascotKindProvider] into the design system's [MascotChoice]
/// (placed once at the app root; every `MascotView` below reads it).
class MascotKindScope extends ConsumerWidget {
  const MascotKindScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MascotChoice(kind: ref.watch(mascotKindProvider), child: child);
}
