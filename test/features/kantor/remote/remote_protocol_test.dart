import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_keys.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_protocol.dart';

void main() {
  group('hosts list', () {
    test('parses, sorts online first, tolerates junk', () {
      final hosts = RemoteHost.listFromJson([
        {'machine': 'b', 'name': 'Zed', 'online': false},
        {
          'machine': 'a',
          'name': 'Mac mini',
          'online': true,
          'version': '1.0.0',
          'busy': 1,
          'displays': [
            {'id': 1, 'name': 'Built-in', 'w': 3024, 'h': 1964, 'scale': 2},
            'junk',
          ],
        },
        {'name': 'no machine id'},
        42,
      ]);
      expect(hosts.map((h) => h.machine), ['a', 'b']);
      expect(hosts.first.busy, isTrue);
      expect(hosts.first.displays.single.sizeLabel, '3024×1964');
      expect(hosts.first.displays.single.scale, 2);
      expect(RemoteHost.listFromJson({'hosts': []}), isEmpty);
    });
  });

  group('signaling', () {
    test('decodes ready/error/offer/ice/bye', () {
      expect(
        (SignalMessage.decode('{"type":"ready","session":"s1"}') as SignalReady)
            .session,
        's1',
      );
      expect(
        (SignalMessage.decode('{"type":"error","message":"host offline"}')
                as SignalError)
            .message,
        'host offline',
      );
      final offer =
          SignalMessage.decode('{"type":"offer","session":"s1","sdp":"v=0"}')
              as SignalOffer;
      expect(offer.sdp, 'v=0');
      final ice =
          SignalMessage.decode(
                '{"type":"ice","session":"s1","candidate":"candidate:1",'
                '"sdpMid":"0","sdpMLineIndex":0}',
              )
              as SignalIce;
      expect(ice.candidate, 'candidate:1');
      expect(ice.sdpMid, '0');
      expect(ice.mLineIndex, 0);
      expect(
        (SignalMessage.decode('{"type":"bye","reason":"x"}') as SignalBye)
            .reason,
        'x',
      );
      expect(SignalMessage.decode('not json'), isNull);
      expect(SignalMessage.decode('{"type":"offer"}'), isNull);
      expect(SignalMessage.decode('{"type":"zzz"}'), isA<SignalOther>());
    });

    test('encodes answer/ice/bye with session', () {
      expect(jsonDecode(SignalOut.answer('s1', 'v=0')), {
        'type': 'answer',
        'session': 's1',
        'sdp': 'v=0',
      });
      expect(jsonDecode(SignalOut.ice('s1', 'candidate:1', '0', 0)), {
        'type': 'ice',
        'session': 's1',
        'candidate': 'candidate:1',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
      // null session is omitted, kantor-claude fills it in
      expect(jsonDecode(SignalOut.bye(null, 'done')), {
        'type': 'bye',
        'reason': 'done',
      });
    });
  });

  group('ctl viewer → host', () {
    test('mouse messages follow the contract', () {
      expect(Ctl.moveAbs(0.5, 1.7), {'t': 'mm', 'x': 0.5, 'y': 1.0});
      expect(Ctl.moveRel(1.234, -5.678), {'t': 'mr', 'dx': 1.23, 'dy': -5.68});
      expect(Ctl.down(RemoteButton.left), {'t': 'md', 'b': 0});
      expect(Ctl.up(RemoteButton.right), {'t': 'mu', 'b': 1});
      expect(Ctl.click(RemoteButton.middle, 5), {'t': 'click', 'b': 2, 'n': 3});
      expect(Ctl.wheel(0, 12.5), {'t': 'wh', 'dx': 0.0, 'dy': 12.5});
    });

    test('keyboard, text, clipboard, cfg, ping, release', () {
      expect(Ctl.keyDown('KeyA'), {'t': 'kd', 'code': 'KeyA'});
      expect(Ctl.keyUp('MetaLeft'), {'t': 'ku', 'code': 'MetaLeft'});
      expect(Ctl.key('KeyC', {RemoteMod.shift, RemoteMod.meta}), {
        't': 'key',
        'code': 'KeyC',
        'mods': ['meta', 'shift'],
      });
      expect(Ctl.text('halo 👋'), {'t': 'txt', 's': 'halo 👋'});
      expect(Ctl.clip('x'), {'t': 'clip', 's': 'x'});
      expect(Ctl.cfg(quality: RemoteQuality.sharp), {
        't': 'cfg',
        'quality': 'tajam',
      });
      expect(Ctl.cfg(display: 2, maxFps: 30), {
        't': 'cfg',
        'display': 2,
        'maxFps': 30,
      });
      expect(Ctl.ping(7), {'t': 'ping', 'ts': 7});
      expect(Ctl.release(), {'t': 'release'});
      expect(jsonDecode(encodeCtl(Ctl.release())), {'t': 'release'});
    });

    test('text is capped at 1 MB of UTF-8', () {
      final big = 'é' * 600000; // 1.2 MB in UTF-8
      final out = Ctl.text(big)['s'] as String;
      expect(utf8.encode(out).length, lessThanOrEqualTo(kRemoteTextLimit));
      expect(out.length, 500000);
    });
  });

  group('ctl host → viewer', () {
    test('hello with displays and permissions', () {
      final h =
          HostMessage.decode(
                '{"t":"hello","machine":"m","name":"Mac","display":1,"w":3024,'
                '"h":1964,"displays":[{"id":1,"name":"Built-in","w":3024,'
                '"h":1964,"scale":2}],"perms":{"screen":true,"input":false}}',
              )
              as HostHello;
      expect(h.display, 1);
      expect(h.displays.single.name, 'Built-in');
      expect(h.screenPerm, isTrue);
      expect(h.inputPerm, isFalse);
    });

    test('cursor, display, clip, pong, stats, warn', () {
      final c =
          HostMessage.decode(
                '{"t":"cursor","x":0.25,"y":0.5,"visible":true,'
                '"shape":"ibeam"}',
              )
              as HostCursor;
      expect((c.x, c.y, c.visible, c.shape), (0.25, 0.5, true, 'ibeam'));
      final d =
          HostMessage.decode('{"t":"display","display":2,"w":1920,"h":1080}')
              as HostDisplay;
      expect((d.display, d.w, d.h), (2, 1920, 1080));
      expect(
        (HostMessage.decode('{"t":"clip","s":"hi"}') as HostClip).text,
        'hi',
      );
      expect(
        (HostMessage.decode('{"t":"pong","ts":5,"hostTs":9}') as HostPong).ts,
        5,
      );
      expect(
        (HostMessage.decode('{"t":"stats","fps":60,"kbps":8000,"encMs":3.2}')
                as HostStats)
            .fps,
        60,
      );
      expect(
        (HostMessage.decode('{"t":"warn","message":"izin"}') as HostWarn)
            .message,
        'izin',
      );
      expect(HostMessage.decode('{"t":"cursor"}'), isNull);
      expect(HostMessage.decode('[]'), isNull);
    });
  });

  group('keyboard helpers', () {
    test('textToCtl: plain text, newline and tab', () {
      expect(textToCtl('ab\ncd\t', {}), [
        {'t': 'txt', 's': 'ab'},
        {'t': 'key', 'code': 'Enter', 'mods': <String>[]},
        {'t': 'txt', 's': 'cd'},
        {'t': 'key', 'code': 'Tab', 'mods': <String>[]},
      ]);
    });

    test('textToCtl: sticky Cmd turns characters into shortcuts', () {
      expect(textToCtl('c', {RemoteMod.meta}), [
        {
          't': 'key',
          'code': 'KeyC',
          'mods': ['meta'],
        },
      ]);
      expect(textToCtl('?', {RemoteMod.ctrl}), [
        {
          't': 'key',
          'code': 'Slash',
          'mods': ['ctrl', 'shift'],
        },
      ]);
    });

    test('textDiff handles autocorrect and emoji', () {
      expect(textDiff('ab teh', 'ab the '), (deleted: 2, inserted: 'he '));
      expect(textDiff('x👋', 'x'), (deleted: 1, inserted: ''));
      expect(textDiff('', 'hi'), (deleted: 0, inserted: 'hi'));
    });

    test('sticky modifiers: once, locked, off', () {
      final s = StickyModifiers();
      s.tap(RemoteMod.meta);
      expect(s.of(RemoteMod.meta), StickyState.once);
      s.consume();
      expect(s.any, isFalse);
      s
        ..tap(RemoteMod.shift)
        ..tap(RemoteMod.shift);
      expect(s.of(RemoteMod.shift), StickyState.locked);
      s.consume();
      expect(s.active, {RemoteMod.shift});
      s.tap(RemoteMod.shift);
      expect(s.any, isFalse);
    });
  });
}
