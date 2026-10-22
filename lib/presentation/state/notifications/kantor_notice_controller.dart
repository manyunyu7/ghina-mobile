import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/notifications/notifications.dart';
import '../../../di/core_providers.dart';

/// The Kantor Claude poller; null where notifications are unsupported
/// (desktop, `flutter test`). Tests override it.
final kantorNoticePollerProvider = Provider<KantorNoticePoller?>(
  (ref) => createKantorNoticePoller(ref.watch(apiClientProvider)),
);

/// How often the foreground app asks for new notices.
const kantorPollEvery = Duration(seconds: 20);

/// Keeps polling Kantor notices while the app is resumed (started once from
/// the app shell with `ref.watch`). Paused/hidden → timer off; resume → poll now.
final kantorNoticeControllerProvider = Provider<void>((ref) {
  final poller = ref.watch(kantorNoticePollerProvider);
  if (poller == null) return;
  Timer? timer;
  void start() {
    timer?.cancel();
    timer = Timer.periodic(kantorPollEvery, (_) => poller.poll());
  }

  void stop() {
    timer?.cancel();
    timer = null;
  }

  final lifecycle = AppLifecycleListener(
    onResume: () {
      poller.poll();
      start();
    },
    onPause: stop,
    onHide: stop,
    onDetach: stop,
  );
  poller.poll();
  start();
  ref.onDispose(() {
    stop();
    lifecycle.dispose();
  });
});
