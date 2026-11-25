import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_gestures.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Only the ctl messages, in order.
List<Map<String, Object?>> sent(List<GestureAction> a) =>
    a.whereType<SendCtl>().map((s) => s.msg).toList();

void main() {
  late RemoteViewport vp;
  late RemoteGestureEngine g;

  setUp(() {
    vp = RemoteViewport()
      ..setGeometry(const Size(1000, 500), const Size(2000, 1000));
    // picture fills the view: 2 remote px per dp
    g = RemoteGestureEngine(toRemote: vp.toRemote, gain: () => vp.gain(2000));
  });

  group('viewport', () {
    test('fit, toRemote/fromRemote round trip', () {
      final v = RemoteViewport()
        ..setGeometry(const Size(1000, 1000), const Size(1600, 1000));
      expect(v.fitted, const Rect.fromLTWH(0, 187.5, 1000, 625));
      expect(v.toRemote(const Offset(500, 500)), const Offset(0.5, 0.5));
      expect(v.fromRemote(const Offset(1, 1)), const Offset(1000, 812.5));
      // outside the picture clamps to the edge
      expect(v.toRemote(const Offset(10, 0)).dy, 0);
    });

    test('zoom keeps the focal point and clamps pan', () {
      vp.zoom(2, const Offset(250, 125));
      expect(vp.scale, 2);
      expect(vp.toRemote(const Offset(250, 125)), const Offset(0.25, 0.25));
      expect(vp.gain(2000), 1); // finer pointer when zoomed
      vp.pan(const Offset(5000, 5000));
      expect(vp.shown.topLeft, Offset.zero); // cannot pan past the edge
      vp.zoom(0.1, Offset.zero);
      expect(vp.scale, 1);
      expect(vp.offset, Offset.zero);
    });

    test('follow pans to keep the cursor visible when zoomed', () {
      vp.zoom(3, Offset.zero);
      expect(vp.follow(const Offset(0.9, 0.9)), isTrue);
      final p = vp.fromRemote(const Offset(0.9, 0.9));
      expect(p.dx, lessThanOrEqualTo(1000));
      expect(p.dy, lessThanOrEqualTo(500));
    });
  });

  group('trackpad mode', () {
    test('tap = left click, quick second tap = double click', () {
      g.down(1, const Offset(100, 100), ms(0));
      expect(sent(g.up(1, ms(80))), [
        {'t': 'click', 'b': 0, 'n': 1},
      ]);
      g.down(1, const Offset(105, 102), ms(200));
      expect(sent(g.up(1, ms(260))), [
        {'t': 'click', 'b': 0, 'n': 2},
      ]);
      // much later: single again
      g.down(1, const Offset(105, 102), ms(2000));
      expect(sent(g.up(1, ms(2050))).single['n'], 1);
    });

    test('one-finger move = relative mouse move', () {
      g.down(1, const Offset(100, 100), ms(0));
      final first = sent(g.move(1, const Offset(130, 100), ms(100)));
      expect(first.single['t'], 'mr');
      expect(first.single['dx'] as double, greaterThan(30)); // 2 px/dp × accel
      expect(first.single['dy'], 0);
      final next = sent(g.move(1, const Offset(130, 90), ms(116)));
      expect(next.single['t'], 'mr');
      expect(next.single['dy'] as double, lessThan(0));
      expect(g.up(1, ms(130)), isEmpty); // no click after a move
    });

    test('two-finger tap = right click', () {
      g.down(1, const Offset(100, 100), ms(0));
      g.down(2, const Offset(200, 100), ms(10));
      expect(sent(g.up(1, ms(120))), [
        {'t': 'click', 'b': 1, 'n': 1},
      ]);
      expect(g.up(2, ms(130)), isEmpty);
    });

    test('two-finger move = natural scroll', () {
      g.down(1, const Offset(100, 300), ms(0));
      g.down(2, const Offset(200, 300), ms(5));
      final out = <Map<String, Object?>>[];
      for (var i = 1; i <= 5; i++) {
        out.addAll(
          sent(g.move(1, Offset(100, 300 - i * 10.0), ms(5 + i * 16))),
        );
        out.addAll(
          sent(g.move(2, Offset(200, 300 - i * 10.0), ms(6 + i * 16))),
        );
      }
      expect(out, isNotEmpty);
      expect(out.every((m) => m['t'] == 'wh'), isTrue);
      // fingers moved up → content scrolls down → positive dy
      expect(
        out.map((m) => m['dy'] as double).reduce((a, b) => a + b),
        greaterThan(0),
      );
      final end = g.up(1, ms(90));
      expect(end.whereType<ScrollFling>().single.velocity.dy, greaterThan(0));
    });

    test('pinch zooms the picture, sends nothing to the Mac', () {
      g.down(1, const Offset(400, 250), ms(0));
      g.down(2, const Offset(600, 250), ms(5));
      final a = g.move(2, const Offset(700, 250), ms(30));
      final b = g.move(2, const Offset(760, 250), ms(46));
      expect(sent([...a, ...b]), isEmpty);
      expect(b.whereType<ZoomView>().single.factor, greaterThan(1));
    });

    test('press-and-hold then move = drag (md … mr … mu)', () {
      g.down(1, const Offset(100, 100), ms(0));
      expect(g.holdDeadline, RemoteGestureEngine.holdDelay);
      expect(g.tick(ms(500)).single, isA<Haptic>());
      final start = sent(g.move(1, const Offset(140, 100), ms(560)));
      expect(start.map((m) => m['t']), ['md', 'mr']);
      expect(
        sent(g.move(1, const Offset(160, 100), ms(576))).single['t'],
        'mr',
      );
      expect(sent(g.up(1, ms(600))), [
        {'t': 'mu', 'b': 0},
      ]);
    });

    test('hold and lift without moving = right click', () {
      g.down(1, const Offset(100, 100), ms(0));
      g.tick(ms(500));
      expect(sent(g.up(1, ms(700))), [
        {'t': 'click', 'b': 1, 'n': 1},
      ]);
    });

    test('three-finger move pans the picture, tap = middle click', () {
      g.down(1, const Offset(100, 100), ms(0));
      g.down(2, const Offset(200, 100), ms(1));
      g.down(3, const Offset(300, 100), ms(2));
      expect(sent(g.up(1, ms(100))), [
        {'t': 'click', 'b': 2, 'n': 1},
      ]);
      g.up(2, ms(101));
      g.up(3, ms(102));

      g.down(1, const Offset(100, 100), ms(1000));
      g.down(2, const Offset(200, 100), ms(1001));
      g.down(3, const Offset(300, 100), ms(1002));
      final a = g.move(1, const Offset(100, 160), ms(1030));
      expect(a.whereType<PanView>(), isNotEmpty);
      expect(sent(a), isEmpty);
    });

    test('cancel during drag releases the button', () {
      g.down(1, const Offset(100, 100), ms(0));
      g.tick(ms(500));
      g.move(1, const Offset(150, 100), ms(520));
      expect(sent(g.cancel(1)), [
        {'t': 'mu', 'b': 0},
      ]);
    });
  });

  group('direct mode', () {
    setUp(() => g.mode = RemoteInputMode.direct);

    test('tap = move there + click', () {
      g.down(1, const Offset(250, 125), ms(0));
      expect(sent(g.up(1, ms(60))), [
        {'t': 'mm', 'x': 0.25, 'y': 0.25},
        {'t': 'click', 'b': 0, 'n': 1},
      ]);
    });

    test('one-finger drag = mm, md, mm…, mu', () {
      g.down(1, const Offset(100, 100), ms(0));
      final a = sent(g.move(1, const Offset(150, 100), ms(40)));
      expect(a.map((m) => m['t']), ['mm', 'md', 'mm']);
      expect(a.first['x'], 0.1);
      expect(a.last['x'], 0.15);
      expect(sent(g.move(1, const Offset(200, 100), ms(56))).single['x'], 0.2);
      expect(sent(g.up(1, ms(70))), [
        {'t': 'mu', 'b': 0},
      ]);
    });

    test('long press = right click at the point', () {
      g.down(1, const Offset(500, 250), ms(0));
      g.tick(ms(500));
      expect(sent(g.up(1, ms(600))), [
        {'t': 'mm', 'x': 0.5, 'y': 0.5},
        {'t': 'click', 'b': 1, 'n': 1},
      ]);
    });
  });
}
