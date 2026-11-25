import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../habits/lock/habit_lock.dart';

// ---------------------------------------------------------------------------
// Biometric gate before a remote session

/// When to ask for biometrics / device PIN before opening a session.
enum RemoteLockPolicy {
  everySession('tiap', 'Tiap membuka sesi'),
  every5Min('5m', 'Paling sering tiap 5 menit'),
  off('mati', 'Tidak diminta');

  const RemoteLockPolicy(this.wire, this.label);
  final String wire;
  final String label;
}

enum RemoteUnlock {
  ok,

  /// Allowed, but the phone has no screen lock / biometrics to check.
  okWithoutLock,
  cancelled,
  lockedOut,
  failed,
}

/// Asks for biometrics (falls back to the device PIN/pattern, as local_auth
/// does by default) before a remote session. Policy lives in prefs; the
/// last success is kept in memory only, so restarting the app asks again.
class RemoteLock {
  RemoteLock({
    HabitAuthenticator? auth,
    Future<SharedPreferences>? prefs,
    DateTime Function()? now,
  }) : _auth = auth ?? LocalAuthHabitAuthenticator(),
       _prefs = prefs ?? SharedPreferences.getInstance(),
       _now = now ?? DateTime.now;

  final HabitAuthenticator _auth;
  final Future<SharedPreferences> _prefs;
  final DateTime Function() _now;

  static const prefKey = 'ravel.remote.lock';
  static const window = Duration(minutes: 5);

  /// Shared by every [RemoteLock] in this process.
  static DateTime? _lastOk;

  /// Forget the last success (tests, or "lock now").
  static void reset() => _lastOk = null;

  static const warnedKey = 'ravel.remote.nolock.warned';

  /// True the first time only: show the "no screen lock" warning once.
  Future<bool> shouldWarnNoLock() async {
    final p = await _prefs;
    if (p.getBool(warnedKey) ?? false) return false;
    await p.setBool(warnedKey, true);
    return true;
  }

  Future<RemoteLockPolicy> policy() async {
    final v = (await _prefs).getString(prefKey);
    return RemoteLockPolicy.values.firstWhere(
      (p) => p.wire == v,
      orElse: () => RemoteLockPolicy.everySession,
    );
  }

  Future<void> setPolicy(RemoteLockPolicy p) async =>
      (await _prefs).setString(prefKey, p.wire);

  bool needsAuth(RemoteLockPolicy p) => switch (p) {
    RemoteLockPolicy.off => false,
    RemoteLockPolicy.everySession => true,
    RemoteLockPolicy.every5Min =>
      _lastOk == null || _now().difference(_lastOk!) > window,
  };

  Future<RemoteUnlock> unlock(String machineName) async {
    if (!needsAuth(await policy())) return RemoteUnlock.ok;
    // A phone without any screen lock cannot prove anything; do not lock the
    // owner out of their own Mac because of it.
    if (!await _auth.canAuthenticate()) return RemoteUnlock.okWithoutLock;
    final r = await _auth.authenticate('Buka remote $machineName');
    switch (r) {
      case HabitAuthOutcome.success:
        _lastOk = _now();
        return RemoteUnlock.ok;
      case HabitAuthOutcome.unavailable:
        return RemoteUnlock.okWithoutLock;
      case HabitAuthOutcome.cancelled:
        return RemoteUnlock.cancelled;
      case HabitAuthOutcome.lockedOut:
        return RemoteUnlock.lockedOut;
      case HabitAuthOutcome.error:
        return RemoteUnlock.failed;
    }
  }
}

// ---------------------------------------------------------------------------
// DTLS fingerprint pinning

/// `a=fingerprint:<alg> <hex>` lines of an SDP, normalized.
List<String> sdpFingerprints(String sdp) {
  final out = <String>[];
  for (final line in sdp.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (!t.startsWith('a=fingerprint:')) continue;
    final n = normalizeFingerprint(t.substring('a=fingerprint:'.length));
    if (n != null && !out.contains(n)) out.add(n);
  }
  return out;
}

/// `"sha-256 ab:cd:…"` → `"sha-256 AB:CD:…"`; null if malformed.
String? normalizeFingerprint(String? raw) {
  if (raw == null) return null;
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.length != 2) return null;
  final alg = parts[0].toLowerCase();
  final hex = parts[1].toUpperCase();
  if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2})+$').hasMatch(hex)) return null;
  return '$alg $hex';
}

enum PinResult {
  ok,

  /// The offer has no (or a malformed) fingerprint.
  missing,

  /// The offer does not match what kantor-claude announced in `ready`.
  mismatchAnnounced,

  /// The offer does not match the fingerprint pinned on first use.
  mismatchPinned,
}

/// Decides whether to accept an offer. [announced] comes from `ready`,
/// [pinned] is what was stored for this Mac before (TOFU).
PinResult checkFingerprint({
  required String sdp,
  String? announced,
  String? pinned,
}) {
  final offered = sdpFingerprints(sdp);
  if (offered.length != 1) return PinResult.missing;
  final fp = offered.single;
  final a = normalizeFingerprint(announced);
  if (announced != null && a != fp) return PinResult.mismatchAnnounced;
  final p = normalizeFingerprint(pinned);
  if (pinned != null && p != fp) return PinResult.mismatchPinned;
  return PinResult.ok;
}

/// Pinned fingerprints, one per MACHINE (not per hub): the same Mac reached
/// through any hub must present the same identity.
abstract interface class RemotePinStore {
  Future<String?> read(String machine);
  Future<void> write(String machine, String fingerprint);
  Future<void> clear(String machine);
}

class SecureRemotePinStore implements RemotePinStore {
  SecureRemotePinStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static String keyFor(String machine) => 'ravel.remote.pin.m.$machine';

  @override
  Future<String?> read(String machine) => _s.read(key: keyFor(machine));

  @override
  Future<void> write(String machine, String fingerprint) =>
      _s.write(key: keyFor(machine), value: fingerprint);

  @override
  Future<void> clear(String machine) => _s.delete(key: keyFor(machine));
}

/// In-memory store for tests.
class MemoryRemotePinStore implements RemotePinStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String machine) async => data[machine];

  @override
  Future<void> write(String machine, String fingerprint) async =>
      data[machine] = fingerprint;

  @override
  Future<void> clear(String machine) async => data.remove(machine);
}
