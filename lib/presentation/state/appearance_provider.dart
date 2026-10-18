import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/theme/ghina_appearance.dart';

/// The "Tampilan" choices (mode, accent, text size, style): device-local,
/// not synced.
abstract interface class AppearancePrefs {
  Future<GhinaAppearance> load();
  Future<void> save(GhinaAppearance value);
}

class SharedPrefsAppearancePrefs implements AppearancePrefs {
  SharedPrefsAppearancePrefs([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const modeKey = 'appearance.mode';
  static const accentKey = 'appearance.accent';
  static const textSizeKey = 'appearance.textSize';
  static const styleKey = 'appearance.style';

  @override
  Future<GhinaAppearance> load() async {
    final p = await _prefs;
    return GhinaAppearance(
      mode: _mode(p.getString(modeKey)),
      accent: GhinaAccent.fromId(p.getString(accentKey)),
      textSize: GhinaTextSize.fromId(p.getString(textSizeKey)),
      style: GhinaStyle.fromId(p.getString(styleKey)),
    );
  }

  @override
  Future<void> save(GhinaAppearance value) async {
    final p = await _prefs;
    await Future.wait([
      p.setString(modeKey, value.mode.name),
      p.setString(accentKey, value.accent.id),
      p.setString(textSizeKey, value.textSize.id),
      p.setString(styleKey, value.style.id),
    ]);
  }

  static ThemeMode _mode(String? name) {
    for (final m in ThemeMode.values) {
      if (m.name == name) return m;
    }
    return ThemeMode.system;
  }
}

class InMemoryAppearancePrefs implements AppearancePrefs {
  InMemoryAppearancePrefs([this.value = const GhinaAppearance()]);

  GhinaAppearance value;

  @override
  Future<GhinaAppearance> load() async => value;

  @override
  Future<void> save(GhinaAppearance value) async => this.value = value;
}

final appearancePrefsProvider = Provider<AppearancePrefs>(
  (ref) => SharedPrefsAppearancePrefs(),
);

/// Preloaded before `runApp` (see `main.dart`) so the chosen theme shows
/// from the first frame. Null → [AppearanceController] loads async.
final appearanceInitialProvider = Provider<GhinaAppearance?>((ref) => null);

/// The user's "Tampilan" choices. Default: system mode, Hijau Ghina, normal
/// text, chunky.
///
/// ```dart
/// ref.watch(appearanceProvider).accent;                       // GhinaAccent
/// ref.read(appearanceProvider.notifier).setAccent(GhinaAccent.ungu);
/// ```
final appearanceProvider =
    NotifierProvider<AppearanceController, GhinaAppearance>(
      AppearanceController.new,
    );

class AppearanceController extends Notifier<GhinaAppearance> {
  bool _touched = false;

  AppearancePrefs get _prefs => ref.read(appearancePrefsProvider);

  @override
  GhinaAppearance build() {
    final initial = ref.watch(appearanceInitialProvider);
    if (initial != null) return initial;
    _touched = false;
    _load();
    return const GhinaAppearance();
  }

  Future<void> _load() async {
    final GhinaAppearance v;
    try {
      v = await _prefs.load();
    } catch (_) {
      return;
    }
    // A change made before the load finished wins.
    if (!ref.mounted || _touched) return;
    state = v;
  }

  Future<void> _set(GhinaAppearance v) async {
    _touched = true;
    if (v == state) return;
    state = v;
    await _prefs.save(v);
  }

  Future<void> setMode(ThemeMode mode) => _set(state.copyWith(mode: mode));

  Future<void> setAccent(GhinaAccent accent) =>
      _set(state.copyWith(accent: accent));

  Future<void> setTextSize(GhinaTextSize size) =>
      _set(state.copyWith(textSize: size));

  /// Switching style also swaps the accent when it is the old style's
  /// default (Hijau ↔ Monokrom for Minimal); a picked accent stays.
  Future<void> setStyle(GhinaStyle style) => _set(
    state.copyWith(
      style: style,
      accent: state.accent == state.style.defaultAccent
          ? style.defaultAccent
          : null,
    ),
  );

  /// "Reset ke default".
  Future<void> reset() => _set(const GhinaAppearance());
}

/// Loads the saved appearance (call before `runApp`).
Future<GhinaAppearance> preloadAppearance([AppearancePrefs? prefs]) =>
    (prefs ?? SharedPrefsAppearancePrefs()).load().catchError(
      (_) => const GhinaAppearance(),
    );

/// Placed once below the app root (`MaterialApp.builder`):
/// - applies the chosen text size: the system text scale times
///   [GhinaTextSize.factor], clamped (see [GhinaTextSize.apply]);
/// - rebuilds the whole tree when the font family flips (Minimal uses the
///   system font; `GhinaType` styles are static, so widgets that don't
///   depend on the theme would otherwise keep the old font).
class AppearanceScope extends ConsumerStatefulWidget {
  const AppearanceScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends ConsumerState<AppearanceScope> {
  void _rebuildAll() {
    if (!mounted) return;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appearanceProvider.select((a) => a.style == GhinaStyle.minimal),
      (_, _) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll()),
    );
    final size = ref.watch(appearanceProvider.select((a) => a.textSize));
    // Always the same wrapper, so switching sizes keeps the navigator state.
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: size.apply(mq.textScaler)),
      child: widget.child,
    );
  }
}
