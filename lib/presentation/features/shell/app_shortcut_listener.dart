import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/app_shortcuts.dart';
import '../../state/platform/platform_providers.dart';
import 'notification_navigation.dart';

/// Where the "Lagi pengen…" shortcut goes: the urge screen of the only active
/// quit habit, the Habits board with a picker when there are several, or the
/// new-habit form when there is none.
String urgeRouteFor(Iterable<Habit> habits) {
  final quit = [
    for (final h in habits)
      if (h.isQuit && !h.archived) h,
  ];
  return switch (quit.length) {
    0 => '/habits/new',
    1 => '/habits/${quit.single.id}/urge',
    _ => '/habits?pick=urge',
  };
}

/// Route of a launcher shortcut; null for [AppShortcut.urge] (depends on the
/// user's habits — see [urgeRouteFor]).
String? shortcutRoute(AppShortcut s) => switch (s) {
  AppShortcut.expense => '/transactions/new',
  AppShortcut.note => '/notes/new',
  AppShortcut.task => '/tasks/new',
  AppShortcut.urge => null,
};

/// Publishes the launcher shortcuts (long-press the Ghina icon) and opens the
/// one the user picked — through the enclosing [NotificationRouteGate], so a
/// cold start waits until signed in and past splash/onboarding, like reminder
/// taps. The Habits pages keep their own lock gate.
class AppShortcutListener extends ConsumerStatefulWidget {
  const AppShortcutListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShortcutListener> createState() =>
      _AppShortcutListenerState();
}

class _AppShortcutListenerState extends ConsumerState<AppShortcutListener> {
  StreamSubscription<AppShortcut>? _sub;

  @override
  void initState() {
    super.initState();
    final shortcuts = ref.read(appShortcutsProvider);
    _sub = shortcuts.launches.listen(_onLaunch);
    unawaited(shortcuts.install(AppShortcut.values));
  }

  void _onLaunch(AppShortcut s) {
    if (!mounted) return;
    final gate = NotificationRouteGate.maybeOf(context);
    if (gate == null) return;
    final route = shortcutRoute(s);
    if (route != null) {
      gate.open(route);
    } else {
      gate.openWith(_resolveUrge);
    }
  }

  Future<String?> _resolveUrge() async {
    if (!mounted) return null;
    final keep = ref.listenManual(watchHabitsProvider, (_, _) {});
    try {
      final habits = await ref
          .read(watchHabitsProvider.future)
          .timeout(const Duration(seconds: 5));
      return urgeRouteFor(habits);
    } catch (_) {
      return '/habits';
    } finally {
      keep.close();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
