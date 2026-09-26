import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../state/notifications/notification_route_listener.dart';

/// Resolves the route to open once the app is ready (e.g. the "Lagi
/// pengen…" shortcut picks a habit from the signed-in user's data). Null =
/// open nothing.
typedef PendingRouteResolver = FutureOr<String?> Function();

/// Opens routes of tapped reminders (`/tasks/<id>`) and launcher shortcuts on
/// [router], waiting until [canOpen] is true (signed in and past
/// splash/onboarding/login — e.g. a cold start from a notification) before
/// pushing. Only the latest pending route is kept.
class NotificationRouteOpener {
  NotificationRouteOpener({required this.router, required this.canOpen});

  final GoRouter router;
  final bool Function() canOpen;
  PendingRouteResolver? _pending;
  bool _listening = false;
  bool _disposed = false;

  void open(String route) => openWith(() => route);

  /// Like [open], but the route is computed only once the app is ready.
  void openWith(PendingRouteResolver resolve) {
    _pending = resolve;
    _flush();
  }

  void _flush() {
    final r = _pending;
    if (r == null) return _stopListening();
    if (!canOpen()) {
      if (!_listening) {
        router.routerDelegate.addListener(_flush);
        _listening = true;
      }
      return;
    }
    _pending = null;
    _stopListening();
    final FutureOr<String?> route;
    try {
      route = r();
    } catch (_) {
      return;
    }
    if (route is Future<String?>) {
      route.then(_push, onError: (Object _) {});
    } else {
      _push(route);
    }
  }

  void _push(String? route) {
    if (route == null || _disposed) return;
    // Push after the current frame so a redirect in progress settles first.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!_disposed) router.push(route);
      })
      ..ensureVisualUpdate();
  }

  /// Re-checks a pending route (e.g. when the session changes).
  void retry() => _flush();

  void _stopListening() {
    if (!_listening) return;
    router.routerDelegate.removeListener(_flush);
    _listening = false;
  }

  void dispose() {
    _disposed = true;
    _stopListening();
  }
}

/// Wraps the app (inside `MaterialApp.router(builder:)`) and routes reminder
/// taps through a [NotificationRouteOpener]. Descendants (the launcher
/// shortcut listener) queue routes with [NotificationRouteGate.maybeOf].
class NotificationRouteGate extends StatefulWidget {
  const NotificationRouteGate({
    super.key,
    required this.router,
    required this.canOpen,
    required this.child,
  });

  final GoRouter router;
  final bool Function() canOpen;
  final Widget child;

  @override
  State<NotificationRouteGate> createState() => NotificationRouteGateState();

  static NotificationRouteGateState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<NotificationRouteGateState>();
}

class NotificationRouteGateState extends State<NotificationRouteGate> {
  late NotificationRouteOpener _opener = _create();

  NotificationRouteOpener _create() => NotificationRouteOpener(
    router: widget.router,
    canOpen: () => widget.canOpen(),
  );

  /// Re-checks a pending route (call when the session / onboarding changes).
  void retry() => _opener.retry();

  /// Opens [route] as soon as the app is ready (see [NotificationRouteOpener]).
  void open(String route) => _opener.open(route);

  /// Opens the route [resolve] returns once the app is ready.
  void openWith(PendingRouteResolver resolve) => _opener.openWith(resolve);

  @override
  void didUpdateWidget(NotificationRouteGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      _opener.dispose();
      _opener = _create();
    }
  }

  @override
  void dispose() {
    _opener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationRouteListener(
    onRoute: (r) => _opener.open(r),
    child: widget.child,
  );
}
