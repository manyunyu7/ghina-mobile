import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';

import '../../domain/entities/entities.dart';
import '../../domain/services/notification_listener.dart';
import '../datasources/local/app_database.dart';
import '../repositories/notification_log_repositories.dart';
import 'platform_bridge.dart';

/// "Log Notifikasi" on Android via `flutter_notification_listener`.
///
/// Why this plugin (and not `notification_listener_service`): it hands every
/// notification to a registered **static Dart callback**, running in the UI
/// isolate while the app is open and in a headless background engine when it
/// isn't (the listener service is bound by the system as long as notification
/// access is granted, and is rebound after a reboot). So notifications are
/// stored even when Ghina is closed. `notification_listener_service` only
/// streams events to a live UI isolate — everything posted while the app is
/// closed would be lost.
///
/// The callback ([ghinaNotificationCallback]) only **stores** rows in the
/// shared drift database; turning matching rows into transactions happens in
/// the UI isolate (`ProcessCapturedNotifications`), which owns sync/outbox.
///
/// No foreground service is used (no permanent notification); see
/// `AndroidManifest.xml` for the service declaration.
class FlutterDeviceNotificationListener implements DeviceNotificationListener {
  FlutterDeviceNotificationListener({PlatformBridge? bridge})
    : _bridge = bridge ?? PlatformBridge();

  final PlatformBridge _bridge;
  bool _initialized = false;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasAccess() async {
    try {
      return await NotificationsListener.hasPermission ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openAccessSettings() async {
    try {
      await NotificationsListener.openPermissionSettings();
    } catch (_) {
      // Settings screen missing on some ROMs — nothing else to do.
    }
  }

  @override
  Future<bool> start() async {
    if (!await hasAccess()) return false;
    try {
      if (!_initialized) {
        // Registers the dispatcher + our callback and points the service at
        // this (UI) engine. Needed on every app start.
        await NotificationsListener.initialize(
          callbackHandle: ghinaNotificationCallback,
        );
        _initialized = true;
      }
      if (await NotificationsListener.isRunning != true) {
        await NotificationsListener.startService(
          foreground: false,
          title: 'Ghina',
          description: 'Mencatat notifikasi',
        );
      }
      return true;
    } catch (e) {
      debugPrint('notification listener start failed: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await NotificationsListener.stopService();
    } catch (_) {}
  }

  @override
  Future<bool> isRunning() async {
    try {
      return await NotificationsListener.isRunning ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<InstalledApp>> installedApps() async => [
    for (final a in await _bridge.launchableApps())
      InstalledApp(packageName: a.package, label: a.label),
  ];

  @override
  Future<String?> appLabel(String packageName) => _bridge.appLabel(packageName);
}

/// iOS / tests: other apps' notifications can't be read.
final class NoopDeviceNotificationListener
    implements DeviceNotificationListener {
  const NoopDeviceNotificationListener();

  @override
  bool get isSupported => false;
  @override
  Future<bool> hasAccess() async => false;
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<bool> isRunning() async => false;
  @override
  Future<List<InstalledApp>> installedApps() async => const [];
  @override
  Future<String?> appLabel(String packageName) async => null;
}

// ---------------------------------------------------------------- callback

/// Ghina's own package: its reminders are not logged.
const _ownPackage = 'com.henryaugusta.ghina';

/// `Notification.FLAG_ONGOING_EVENT` | `FLAG_FOREGROUND_SERVICE`: music
/// players, downloads, navigation — noise, not events.
const _ongoingFlags = 0x02 | 0x40;

/// Where the callback writes. The UI isolate registers its database
/// (`notificationCaptureDatabase = db` in the DI root) so the callback reuses
/// that connection; the background isolate opens its own, which connects to
/// the same shared drift isolate (`AppDatabase.open`).
AppDatabase? notificationCaptureDatabase;

/// Registered with the plugin; runs for every posted notification, in the UI
/// isolate or a background engine. Must stay a top-level entry point.
@pragma('vm:entry-point')
void ghinaNotificationCallback(NotificationEvent evt) {
  unawaited(_store(evt));
}

Future<void> _store(NotificationEvent evt) async {
  try {
    final pkg = evt.packageName;
    if (pkg == null || pkg.isEmpty || pkg == _ownPackage) return;
    if (evt.isGroup == true) return; // group summary duplicates its children
    if ((evt.flags ?? 0) & _ongoingFlags != 0) return;
    final title = (evt.title ?? '').trim();
    final raw = evt.raw;
    final big = raw?['bigText'];
    final text = (evt.text ?? '').trim();
    final body = big is String && big.trim().length > text.length
        ? big.trim()
        : text;
    if (title.isEmpty && body.isEmpty) return;
    final now = DateTime.now();
    final posted = evt.timestamp == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(evt.timestamp!);
    final db = notificationCaptureDatabase ??= AppDatabase.open();
    await insertCapturedNotification(
      db,
      packageName: pkg,
      title: title,
      body: body,
      notificationKey: evt.key,
      postedAt: posted,
      capturedAt: now,
    );
  } catch (e) {
    debugPrint('notification capture failed: $e');
  }
}
