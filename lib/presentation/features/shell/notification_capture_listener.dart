import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../design_system/design_system.dart';
import '../../state/notification_capture_controller.dart';
import '../../state/session_controller.dart';

/// "Log Notifikasi" hook of the signed-in shell (Android; inert on iOS):
///
/// * starts [notificationCaptureProvider] on every app start (registers this
///   engine with the listener service) and refreshes it on resume — the user
///   may come back from Settings › Notification access;
/// * turns captured notifications into transactions: whenever the log has
///   unchecked rows (also ones stored by the background isolate while the app
///   was closed) it runs `ProcessCapturedNotifications` and toasts what was
///   recorded.
class NotificationCaptureListener extends ConsumerStatefulWidget {
  const NotificationCaptureListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationCaptureListener> createState() =>
      _NotificationCaptureListenerState();
}

class _NotificationCaptureListenerState
    extends ConsumerState<NotificationCaptureListener> {
  bool _processing = false;
  bool _again = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!ref.read(deviceNotificationListenerProvider).isSupported) return;
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(notificationCaptureProvider.notifier).refresh(),
    );
    ref.listenManual(notificationCaptureProvider, (_, _) {});
    ref.listenManual<AsyncValue<int>>(
      watchUnprocessedNotificationCountProvider,
      (_, next) {
        if ((next.value ?? 0) > 0) _process();
      },
      fireImmediately: true,
    );
    ref.listenManual(currentUserProvider, (_, user) {
      if (user != null) _process();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    if (_processing) {
      _again = true;
      return;
    }
    if (ref.read(currentUserProvider) == null) return;
    _processing = true;
    try {
      do {
        _again = false;
        final r = await ref.read(processCapturedNotificationsProvider)();
        final n = r.created.length;
        if (n > 0 && mounted) {
          showToastBadge(
            context,
            message: n == 1
                ? 'Transaksi dicatat dari notifikasi 🔔'
                : '$n transaksi dicatat dari notifikasi 🔔',
            icon: Icons.notifications_active_rounded,
            color: GhinaColors.green,
          );
        }
      } while (_again && mounted);
    } catch (_) {
      // Rows stay unprocessed and are retried on the next change / start.
    } finally {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
