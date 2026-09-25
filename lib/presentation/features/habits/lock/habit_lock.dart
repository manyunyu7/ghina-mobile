/// "Kunci Kebiasaan" (`docs/habits.md` → Privacy): an optional device
/// biometrics / PIN lock in front of the Habits area. Device-local, not synced.
///
/// - Session based: once unlocked, the area stays open until the app has been
///   in the background for [habitRelockAfter] (or the user locks it again).
/// - Graceful: when the device has no screen lock / biometrics at all the
///   lock can't be turned on, and an already-enabled lock lets the user in
///   (with a hint) instead of shutting them out.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../di/di.dart';

/// Background time after which the Habits area locks again.
const habitRelockAfter = Duration(minutes: 5);

/// What an authentication attempt ended with.
enum HabitAuthOutcome {
  success,

  /// Dismissed by the user / the system.
  cancelled,

  /// No biometrics and no device PIN/pattern/password set up.
  unavailable,

  /// Too many attempts; try again later.
  lockedOut,
  error,
}

/// Device authentication (biometrics with PIN fallback). Tests use a fake.
abstract interface class HabitAuthenticator {
  /// The device can authenticate (biometrics or a screen lock is set).
  Future<bool> canAuthenticate();

  Future<HabitAuthOutcome> authenticate(String reason);
}

/// `local_auth` implementation.
class LocalAuthHabitAuthenticator implements HabitAuthenticator {
  LocalAuthHabitAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HabitAuthOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? HabitAuthOutcome.success : HabitAuthOutcome.cancelled;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress => HabitAuthOutcome.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.uiUnavailable => HabitAuthOutcome.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => HabitAuthOutcome.lockedOut,
        _ => HabitAuthOutcome.error,
      };
    } on MissingPluginException {
      return HabitAuthOutcome.unavailable;
    } on PlatformException {
      return HabitAuthOutcome.error;
    } catch (_) {
      return HabitAuthOutcome.error;
    }
  }
}

/// Where the on/off setting lives.
abstract interface class HabitLockStore {
  Future<bool> load();
  Future<void> save(bool enabled);
}

class SharedPrefsHabitLockStore implements HabitLockStore {
  SharedPrefsHabitLockStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;
  static const _key = 'privacy.habitLock';

  @override
  Future<bool> load() async => (await _prefs).getBool(_key) ?? false;

  @override
  Future<void> save(bool enabled) async =>
      (await _prefs).setBool(_key, enabled);
}

class InMemoryHabitLockStore implements HabitLockStore {
  InMemoryHabitLockStore([this.enabled = false]);
  bool enabled;

  @override
  Future<bool> load() async => enabled;

  @override
  Future<void> save(bool v) async => enabled = v;
}

final habitLockStoreProvider = Provider<HabitLockStore>(
  (ref) => SharedPrefsHabitLockStore(),
);

final habitAuthenticatorProvider = Provider<HabitAuthenticator>(
  (ref) => LocalAuthHabitAuthenticator(),
);

/// Lock state for this app session.
@immutable
class HabitLockState {
  const HabitLockState({
    this.loaded = false,
    this.enabled = false,
    this.unlocked = false,
    this.busy = false,
    this.deviceHasNoLock = false,
  });

  /// The setting was read.
  final bool loaded;
  final bool enabled;

  /// Unlocked in this session.
  final bool unlocked;

  /// An authentication prompt is showing.
  final bool busy;

  /// The lock is on but the device can't authenticate anymore (screen lock
  /// removed): the area opens anyway, with a hint.
  final bool deviceHasNoLock;

  /// The Habits area must show the lock screen.
  bool get locked => !loaded || (enabled && !unlocked);

  HabitLockState copyWith({
    bool? loaded,
    bool? enabled,
    bool? unlocked,
    bool? busy,
    bool? deviceHasNoLock,
  }) => HabitLockState(
    loaded: loaded ?? this.loaded,
    enabled: enabled ?? this.enabled,
    unlocked: unlocked ?? this.unlocked,
    busy: busy ?? this.busy,
    deviceHasNoLock: deviceHasNoLock ?? this.deviceHasNoLock,
  );
}

/// Result of flipping the setting.
enum HabitLockToggle { changed, noDeviceLock, failed }

final habitLockProvider = NotifierProvider<HabitLockController, HabitLockState>(
  HabitLockController.new,
);

class HabitLockController extends Notifier<HabitLockState> {
  DateTime? _hiddenAt;

  HabitAuthenticator get _auth => ref.read(habitAuthenticatorProvider);
  DateTime get _now => ref.read(clockProvider).now();

  @override
  HabitLockState build() {
    final listener = AppLifecycleListener(onStateChange: _onLifecycle);
    ref.onDispose(listener.dispose);
    unawaited(_load());
    return const HabitLockState();
  }

  Future<void> _load() async {
    bool enabled;
    try {
      enabled = await ref.read(habitLockStoreProvider).load();
    } catch (_) {
      enabled = false;
    }
    if (!ref.mounted) return;
    state = state.copyWith(loaded: true, enabled: enabled);
  }

  void _onLifecycle(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _hiddenAt ??= _now;
      case AppLifecycleState.resumed:
        final at = _hiddenAt;
        _hiddenAt = null;
        if (at != null &&
            state.unlocked &&
            _now.difference(at) >= habitRelockAfter) {
          state = state.copyWith(unlocked: false);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Shows the device prompt; opens the area on success. Without any device
  /// lock the area opens anyway ([HabitLockState.deviceHasNoLock]).
  Future<HabitAuthOutcome> unlock() async {
    if (!state.enabled || state.unlocked) return HabitAuthOutcome.success;
    if (state.busy) return HabitAuthOutcome.cancelled;
    state = state.copyWith(busy: true);
    try {
      if (!await _auth.canAuthenticate()) {
        state = state.copyWith(unlocked: true, deviceHasNoLock: true);
        return HabitAuthOutcome.unavailable;
      }
      final r = await _auth.authenticate('Buka Kebiasaan kamu');
      if (r == HabitAuthOutcome.success) {
        state = state.copyWith(unlocked: true, deviceHasNoLock: false);
      } else if (r == HabitAuthOutcome.unavailable) {
        state = state.copyWith(unlocked: true, deviceHasNoLock: true);
      }
      return r;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Locks the area again right away ("Kunci sekarang").
  void lockNow() {
    if (state.enabled) state = state.copyWith(unlocked: false);
  }

  /// Settings switch. Turning it on needs a working device lock and one
  /// successful prompt (so nobody locks themselves out); turning it off needs
  /// a prompt too (when the device can still authenticate).
  Future<HabitLockToggle> setEnabled(bool on) async {
    if (on == state.enabled && state.loaded) return HabitLockToggle.changed;
    final can = await _auth.canAuthenticate();
    if (on && !can) return HabitLockToggle.noDeviceLock;
    if (can) {
      state = state.copyWith(busy: true);
      final r = await _auth.authenticate(
        on ? 'Aktifkan Kunci Kebiasaan' : 'Matikan Kunci Kebiasaan',
      );
      if (!ref.mounted) return HabitLockToggle.failed;
      state = state.copyWith(busy: false);
      if (r != HabitAuthOutcome.success) {
        return r == HabitAuthOutcome.unavailable && on
            ? HabitLockToggle.noDeviceLock
            : HabitLockToggle.failed;
      }
    }
    await ref.read(habitLockStoreProvider).save(on);
    if (!ref.mounted) return HabitLockToggle.changed;
    state = state.copyWith(
      loaded: true,
      enabled: on,
      unlocked: true,
      deviceHasNoLock: false,
    );
    return HabitLockToggle.changed;
  }
}
