import 'dart:async';

import 'package:quick_actions/quick_actions.dart';

import '../../domain/services/app_shortcuts.dart';

/// [AppShortcuts] over the `quick_actions` plugin: Android dynamic shortcuts
/// (ShortcutManager; the launch intent reaches the singleTask `MainActivity`,
/// cold start via `getLaunchAction`, warm start via `onNewIntent`) and iOS
/// Home Screen quick actions.
final class QuickActionsAppShortcuts implements AppShortcuts {
  QuickActionsAppShortcuts({QuickActions? plugin})
    : _plugin = plugin ?? const QuickActions() {
    _controller = StreamController<AppShortcut>.broadcast(onListen: _onListen);
  }

  final QuickActions _plugin;
  late final StreamController<AppShortcut> _controller;
  final _early = <AppShortcut>[];
  bool _initialized = false;

  @override
  Stream<AppShortcut> get launches => _controller.stream;

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    // Also delivers the shortcut that cold-started the app.
    unawaited(
      _plugin
          .initialize((type) {
            final s = AppShortcut.fromType(type);
            if (s == null || _controller.isClosed) return;
            if (_controller.hasListener) {
              _controller.add(s);
            } else {
              _early.add(s);
            }
          })
          .catchError((Object _) {}),
    );
  }

  void _onListen() {
    _ensureInitialized();
    final queued = List.of(_early);
    _early.clear();
    // After the listen call returns, so the new listener gets them.
    scheduleMicrotask(() {
      for (final s in queued) {
        if (!_controller.isClosed) _controller.add(s);
      }
    });
  }

  @override
  Future<void> install(List<AppShortcut> items) async {
    _ensureInitialized();
    try {
      await _plugin.setShortcutItems([
        for (final s in items)
          ShortcutItem(type: s.type, localizedTitle: s.label, icon: s.icon),
      ]);
    } catch (_) {
      // Launchers without shortcut support: nothing to do.
    }
  }

  @override
  Future<void> dispose() => _controller.close();
}
