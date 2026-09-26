import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../di/di.dart';
import '../../domain/services/services.dart';

/// State of "Log Notifikasi" (Android notification listener).
class NotificationCaptureState {
  const NotificationCaptureState({
    this.supported = false,
    this.loading = true,
    this.enabled = false,
    this.hasAccess = false,
    this.running = false,
  });

  /// Android only; the feature is hidden elsewhere.
  final bool supported;
  final bool loading;

  /// The user's on/off switch (device-local).
  final bool enabled;

  /// Notification access granted in Settings.
  final bool hasAccess;

  /// The listener service is running.
  final bool running;

  /// On, but notification access is still missing.
  bool get waitingForAccess => enabled && !hasAccess;

  /// Capturing right now.
  bool get active => enabled && hasAccess;

  NotificationCaptureState copyWith({
    bool? loading,
    bool? enabled,
    bool? hasAccess,
    bool? running,
  }) => NotificationCaptureState(
    supported: supported,
    loading: loading ?? this.loading,
    enabled: enabled ?? this.enabled,
    hasAccess: hasAccess ?? this.hasAccess,
    running: running ?? this.running,
  );
}

/// Device-local on/off switch of the notification listener.
abstract interface class NotificationCapturePrefs {
  Future<bool> loadEnabled();
  Future<void> saveEnabled(bool value);
}

class SharedPrefsNotificationCapturePrefs implements NotificationCapturePrefs {
  static const _key = 'notifListener.enabled';

  @override
  Future<bool> loadEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> saveEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_key, value);
}

final notificationCapturePrefsProvider = Provider<NotificationCapturePrefs>(
  (ref) => SharedPrefsNotificationCapturePrefs(),
);

/// ```dart
/// ref.watch(notificationCaptureProvider).active;
/// ref.read(notificationCaptureProvider.notifier).setEnabled(true);
/// ```
///
/// Kept alive and started by the signed-in shell
/// (`NotificationCaptureListener`), which also calls [refresh] when the app
/// resumes (the user may come back from Settings › Notification access).
final notificationCaptureProvider =
    NotifierProvider<NotificationCaptureController, NotificationCaptureState>(
      NotificationCaptureController.new,
    );

class NotificationCaptureController extends Notifier<NotificationCaptureState> {
  DeviceNotificationListener get _listener =>
      ref.read(deviceNotificationListenerProvider);
  NotificationCapturePrefs get _prefs =>
      ref.read(notificationCapturePrefsProvider);

  @override
  NotificationCaptureState build() {
    final supported = ref.watch(deviceNotificationListenerProvider).isSupported;
    if (!supported) {
      return const NotificationCaptureState(loading: false);
    }
    Future.microtask(refresh);
    return const NotificationCaptureState(supported: true);
  }

  /// Re-reads the switch and the access, and (re)starts the listener when
  /// both are on — also registers this app run's engine with the service.
  Future<void> refresh() async {
    if (!state.supported) return;
    final enabled = await _prefs.loadEnabled();
    final access = await _listener.hasAccess();
    var running = false;
    if (enabled && access) {
      running = await _listener.start();
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      loading: false,
      enabled: enabled,
      hasAccess: access,
      running: running,
    );
  }

  /// Turning on without access opens Settings › Notification access; the
  /// listener starts on the next [refresh] (app resume) once granted.
  Future<void> setEnabled(bool value) async {
    if (!state.supported) return;
    await _prefs.saveEnabled(value);
    state = state.copyWith(enabled: value);
    if (value) {
      final access = await _listener.hasAccess();
      if (!access) {
        state = state.copyWith(hasAccess: false, running: false);
        await _listener.openAccessSettings();
        return;
      }
      final running = await _listener.start();
      if (!ref.mounted) return;
      state = state.copyWith(hasAccess: true, running: running);
    } else {
      await _listener.stop();
      if (!ref.mounted) return;
      state = state.copyWith(running: false);
    }
  }

  Future<void> openAccessSettings() => _listener.openAccessSettings();
}
