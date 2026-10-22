import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/di.dart';
import '../../presentation/features/shell/notification_navigation.dart';
import 'kantor_widget_bridge.dart';

/// Keeps the Kantor home-screen widget current while the app lives (a refresh
/// at start and whenever the office reports a change) and opens the screen a
/// widget tap asked for. The periodic refresh in the background is
/// [KantorWidgetBridge.scheduleBackground]. Mounted once, inside the
/// [NotificationRouteGate], in `app.dart`.
class KantorWidgetSync extends ConsumerStatefulWidget {
  const KantorWidgetSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KantorWidgetSync> createState() => _KantorWidgetSyncState();
}

class _KantorWidgetSyncState extends ConsumerState<KantorWidgetSync> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (!KantorWidgetBridge.supported) return;
    ref.listenManual(kantorConfigProvider, fireImmediately: true, (_, next) {
      final c = next.value;
      if (c == null) return;
      if (c.ready) {
        unawaited(KantorWidgetBridge.scheduleBackground());
        _refresh();
      } else {
        unawaited(KantorWidgetBridge.cancelBackground());
        unawaited(KantorWidgetBridge.clear());
      }
    });
    KantorWidgetBridge.onRoute(_open);
    unawaited(
      KantorWidgetBridge.takeLaunchRoute().then((r) {
        if (r != null) _open(r);
      }),
    );
  }

  void _open(String route) {
    if (!mounted || !route.startsWith('/kantor')) return;
    NotificationRouteGate.maybeOf(context)?.open(route);
  }

  void _refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final config = ref.read(kantorConfigProvider).value;
      if (config == null) return;
      await KantorWidgetBridge.refresh(config);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (KantorWidgetBridge.supported) {
      ref.listen(kantorEventsProvider, (_, next) {
        if (next.hasValue) _refresh();
      });
    }
    return widget.child;
  }
}
