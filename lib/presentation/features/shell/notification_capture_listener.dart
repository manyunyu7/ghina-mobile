import 'dart:async';

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
/// * refreshes the adb-pullable copy of the log (`notificationLogExportProvider`,
///   tool/pull_notification_log.sh) on start, on resume and after processing —
///   so opening the app is enough to bring the copy up to date;
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
  bool _exporting = false;
  DateTime? _exportedAt;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!ref.read(deviceNotificationListenerProvider).isSupported) return;
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(notificationCaptureProvider.notifier).refresh();
        _export();
      },
    );
    _export();
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

  /// Rewrites the adb copy of the log. At most one at a time and not more often
  /// than every 15 s (resume and processing can fire together); never throws.
  Future<void> _export({bool force = false}) async {
    final last = _exportedAt;
    if (_exporting ||
        (!force &&
            last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 15))) {
      return;
    }
    _exporting = true;
    try {
      await ref.read(notificationLogExportProvider).export();
      _exportedAt = DateTime.now();
    } catch (e) {
      debugPrint('notification log export failed: $e');
    } finally {
      _exporting = false;
    }
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
      // The copy should carry the outcome (rule, transaction) just recorded.
      if (mounted) unawaited(_export(force: true));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
