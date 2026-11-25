import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart';
import 'package:ghina/presentation/features/remote/remote_protocol.dart';
import 'package:ghina/presentation/features/remote/remote_security.dart';
import 'package:ghina/presentation/features/remote/remote_session_page.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fpA =
    'sha-256 AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';
const _fpB =
    'sha-256 11:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

String _offer(String fp) =>
    'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\na=group:BUNDLE 0 1\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=fingerprint:${fp.toLowerCase()}\r\n'
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n'
    'a=fingerprint:$fp\r\n';

class _FakeAuth implements HabitAuthenticator {
  _FakeAuth(this.result);
  HabitAuthOutcome result;
  bool supported = true;
  int calls = 0;

  @override
  Future<bool> canAuthenticate() async => supported;

  @override
  Future<HabitAuthOutcome> authenticate(String reason) async {
    calls++;
    return result;
  }
}

void main() {
  group('DTLS fingerprint', () {
    test('parses and normalizes a=fingerprint (deduped across m-lines)', () {
      expect(sdpFingerprints(_offer(_fpA)), [_fpA]);
      expect(normalizeFingerprint('SHA-256 ab:cd'), 'sha-256 AB:CD');
      expect(normalizeFingerprint('sha-256'), isNull);
      expect(normalizeFingerprint('sha-256 xyz'), isNull);
    });

    test('accepts a match, rejects announced or pinned mismatch', () {
      expect(
        checkFingerprint(sdp: _offer(_fpA), announced: _fpA),
        PinResult.ok,
      );
      expect(
        checkFingerprint(sdp: _offer(_fpA), announced: _fpA, pinned: _fpA),
        PinResult.ok,
      );
      expect(
        checkFingerprint(sdp: _offer(_fpA), announced: _fpB),
        PinResult.mismatchAnnounced,
      );
      expect(
        checkFingerprint(sdp: _offer(_fpA), announced: _fpA, pinned: _fpB),
        PinResult.mismatchPinned,
      );
      expect(checkFingerprint(sdp: 'v=0\r\n'), PinResult.missing);
      // two different fingerprints in one offer is not acceptable
      expect(
        checkFingerprint(sdp: '${_offer(_fpA)}a=fingerprint:$_fpB\r\n'),
        PinResult.missing,
      );
    });

    test('ready carries the fingerprint', () {
      final r =
          SignalMessage.decode(
                '{"type":"ready","session":"s","fingerprint":"$_fpA"}',
              )
              as SignalReady;
      expect(r.fingerprint, _fpA);
    });
  });

  group('biometric gate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      RemoteLock.reset();
    });

    test('every session asks every time', () async {
      final auth = _FakeAuth(HabitAuthOutcome.success);
      final lock = RemoteLock(auth: auth);
      expect(await lock.policy(), RemoteLockPolicy.everySession);
      expect(await lock.unlock('Mac'), RemoteUnlock.ok);
      expect(await lock.unlock('Mac'), RemoteUnlock.ok);
      expect(auth.calls, 2);
    });

    test('every 5 minutes reuses a recent success', () async {
      var now = DateTime(2026, 11, 25, 10);
      final auth = _FakeAuth(HabitAuthOutcome.success);
      final lock = RemoteLock(auth: auth, now: () => now);
      await lock.setPolicy(RemoteLockPolicy.every5Min);
      await lock.unlock('Mac');
      now = now.add(const Duration(minutes: 4));
      await lock.unlock('Mac');
      expect(auth.calls, 1);
      now = now.add(const Duration(minutes: 2));
      await lock.unlock('Mac');
      expect(auth.calls, 2);
    });

    test('cancel blocks; off and no screen lock pass', () async {
      final auth = _FakeAuth(HabitAuthOutcome.cancelled);
      final lock = RemoteLock(auth: auth);
      expect(await lock.unlock('Mac'), RemoteUnlock.cancelled);
      auth.result = HabitAuthOutcome.lockedOut;
      expect(await lock.unlock('Mac'), RemoteUnlock.lockedOut);
      auth.supported = false;
      expect(await lock.unlock('Mac'), RemoteUnlock.okWithoutLock);
      expect(await lock.shouldWarnNoLock(), isTrue);
      expect(await lock.shouldWarnNoLock(), isFalse); // only once
      auth.supported = true;
      await lock.setPolicy(RemoteLockPolicy.off);
      final before = auth.calls;
      expect(await lock.unlock('Mac'), RemoteUnlock.ok);
      expect(auth.calls, before);
    });
  });

  test('default input mode by form factor', () {
    expect(remoteIsWideDevice(const Size(411, 914)), isFalse); // phone
    expect(remoteIsWideDevice(const Size(904, 1000)), isTrue); // Fold open
    expect(remoteDefaultMode(false), InputMode.trackpad);
    expect(remoteDefaultMode(true), InputMode.touch);
  });
}
