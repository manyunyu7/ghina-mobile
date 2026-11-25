import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';

class _FakeViewport implements RemoteGestureViewport {
  final zooms = <({Offset focal, double scaleRatio, Offset pan})>[];
  final haptics = <RemoteHaptic>[];
  int predictedX = 0;
  int predictedY = 0;

  @override
  Offset normalize(Offset local) => Offset(local.dx / 1000, local.dy / 1000);

  @override
  double get trackpadPxPerDp => 2.0;

  @override
  void zoomView({
    required Offset focal,
    required double scaleRatio,
    required Offset pan,
  }) => zooms.add((focal: focal, scaleRatio: scaleRatio, pan: pan));

  @override
  void predictCursor(int dx, int dy) {
    predictedX += dx;
    predictedY += dy;
  }

  @override
  void haptic(RemoteHaptic kind) => haptics.add(kind);
}

class _Rig {
  _Rig(InputMode mode, {List<RemoteModifier> Function()? mods}) {
    actions = RemoteActions(send: sent.add, takeModifiers: mods);
    engine = RemoteGestureEngine(
      actions: actions,
      viewport: viewport,
      mode: mode,
    );
  }

  final sent = <Map<String, dynamic>>[];
  final viewport = _FakeViewport();
  late final RemoteActions actions;
  late final RemoteGestureEngine engine;
  int now = 0;

  List<String> get types => [for (final m in sent) m['t'] as String];

  void down(int p, Offset at) => engine.handle(
    PointerDownEvent(
      pointer: p,
      position: at,
      timeStamp: Duration(milliseconds: now),
    ),
  );

  void move(int p, Offset at) => engine.handle(
    PointerMoveEvent(
      pointer: p,
      position: at,
      timeStamp: Duration(milliseconds: now),
    ),
  );

  void up(int p, Offset at) => engine.handle(
    PointerUpEvent(
      pointer: p,
      position: at,
      timeStamp: Duration(milliseconds: now),
    ),
  );

  void tick(FakeAsync async, int ms) {
    now += ms;
    async.elapse(Duration(milliseconds: ms));
  }

  /// Satu jari bergerak lurus dari [from] ke [to] dalam [steps] langkah.
  void drag1(
    FakeAsync async,
    int p,
    Offset from,
    Offset to, {
    int steps = 10,
    int stepMs = 8,
  }) {
    for (var i = 1; i <= steps; i++) {
      tick(async, stepMs);
      move(p, Offset.lerp(from, to, i / steps)!);
    }
  }
}

void main() {
  group('trackpad', () {
    test('ketuk = click kiri setelah jendela ketuk ganda', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.tick(async, 60);
        r.up(1, const Offset(100, 100));
        expect(r.sent, isEmpty, reason: 'ditunda menunggu ketuk ganda');
        r.tick(async, 300);
        expect(r.sent, [
          {'t': 'click', 'b': 0, 'n': 1},
        ]);
        expect(r.viewport.haptics, [RemoteHaptic.click]);
      });
    });

    test('ketuk ganda = satu click n=2, tanpa click n=1', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.tick(async, 50);
        r.up(1, const Offset(100, 100));
        r.tick(async, 100);
        r.down(2, const Offset(110, 104));
        r.tick(async, 50);
        r.up(2, const Offset(110, 104));
        r.tick(async, 500);
        expect(r.sent, [
          {'t': 'click', 'b': 0, 'n': 2},
        ]);
      });
    });

    test('dua ketukan berjauhan = dua click n=1', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.tick(async, 50);
        r.up(1, const Offset(100, 100));
        r.tick(async, 100);
        r.down(2, const Offset(400, 400));
        r.tick(async, 50);
        r.up(2, const Offset(400, 400));
        r.tick(async, 500);
        expect(r.types, ['click', 'click']);
        expect(r.sent.every((m) => m['n'] == 1), isTrue);
      });
    });

    test('geser 1 jari = mr relatif, kursor diprediksi', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.drag1(async, 1, const Offset(100, 100), const Offset(200, 100));
        r.up(1, const Offset(200, 100));
        r.tick(async, 500);
        expect(r.types.toSet(), {'mr'});
        final dx = r.sent.fold<int>(0, (s, m) => s + (m['dx'] as int));
        final dy = r.sent.fold<int>(0, (s, m) => s + (m['dy'] as int));
        expect(dx, greaterThan(0));
        expect(dy, 0);
        expect(r.viewport.predictedX, dx);
        expect(r.sent.every((m) => m['dx'] is int && m['dy'] is int), isTrue);
      });
    });

    test('akselerasi: gerak cepat menempuh lebih jauh dari gerak pelan', () {
      int total(int stepMs) {
        late int dx;
        fakeAsync((async) {
          final r = _Rig(InputMode.trackpad);
          r.down(1, Offset.zero);
          r.drag1(
            async,
            1,
            Offset.zero,
            const Offset(200, 0),
            steps: 20,
            stepMs: stepMs,
          );
          r.up(1, const Offset(200, 0));
          dx = r.sent
              .where((m) => m['t'] == 'mr')
              .fold<int>(0, (s, m) => s + (m['dx'] as int));
        });
        return dx;
      }

      final slow = total(60); // ~0.17 dp/ms
      final fast = total(4); // ~2.5 dp/ms
      expect(fast, greaterThan(slow * 2));
    });

    test('tahan lalu geser = drag md…mr…mu', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.tick(async, 500);
        expect(r.sent, [
          {'t': 'md', 'b': 0},
        ]);
        expect(r.viewport.haptics, [RemoteHaptic.heavy]);
        r.drag1(async, 1, const Offset(100, 100), const Offset(100, 180));
        r.up(1, const Offset(100, 180));
        expect(r.types.first, 'md');
        expect(r.types.last, 'mu');
        expect(r.types.sublist(1, r.types.length - 1).toSet(), {'mr'});
      });
    });

    test('ketuk-ketuk-tahan-geser = drag, klik pertama tidak dikirim', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.tick(async, 40);
        r.up(1, const Offset(100, 100));
        r.tick(async, 100);
        r.down(2, const Offset(102, 100));
        r.drag1(async, 2, const Offset(102, 100), const Offset(250, 100));
        r.up(2, const Offset(250, 100));
        r.tick(async, 500);
        expect(r.types.first, 'md');
        expect(r.types.last, 'mu');
        expect(r.types.contains('click'), isFalse);
      });
    });

    test('geser 3 jari = geser tampilan, tidak dikirim ke Mac', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.down(2, const Offset(150, 100));
        r.down(3, const Offset(200, 100));
        r.tick(async, 20);
        for (var i = 1; i <= 4; i++) {
          r.move(1, Offset(100, 100 + i * 10.0));
          r.move(2, Offset(150, 100 + i * 10.0));
          r.move(3, Offset(200, 100 + i * 10.0));
          r.tick(async, 16);
        }
        r.up(1, const Offset(100, 140));
        r.up(2, const Offset(150, 140));
        r.up(3, const Offset(200, 140));
        r.tick(async, 400);
        expect(r.sent, isEmpty);
        expect(r.viewport.zooms, isNotEmpty);
        expect(r.viewport.zooms.every((z) => z.scaleRatio == 1.0), isTrue);
        final total = r.viewport.zooms.fold(0.0, (a, z) => a + z.pan.dy);
        expect(total, closeTo(40, 0.01));
      });
    });

    test('ketuk 2 jari = klik kanan, 3 jari = klik tengah', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(100, 100));
        r.down(2, const Offset(160, 100));
        r.tick(async, 80);
        r.up(1, const Offset(100, 100));
        r.up(2, const Offset(160, 100));
        r.tick(async, 400);
        r.down(3, const Offset(100, 100));
        r.down(4, const Offset(150, 100));
        r.down(5, const Offset(200, 100));
        r.tick(async, 80);
        r.up(3, const Offset(100, 100));
        r.up(4, const Offset(150, 100));
        r.up(5, const Offset(200, 100));
        r.tick(async, 400);
        expect(r.sent, [
          {'t': 'click', 'b': 1, 'n': 1},
          {'t': 'click', 'b': 2, 'n': 1},
        ]);
      });
    });

    test(
      'geser 2 jari = wh (natural), lalu inersia; sentuhan baru menghentikannya',
      () {
        fakeAsync((async) {
          final r = _Rig(InputMode.trackpad);
          r.down(1, const Offset(100, 300));
          r.down(2, const Offset(160, 300));
          for (var i = 1; i <= 10; i++) {
            r.tick(async, 8);
            r.move(1, Offset(100, 300 - i * 12.0));
            r.move(2, Offset(160, 300 - i * 12.0));
          }
          expect(r.types.toSet(), {'wh'});
          expect(
            r.sent.every((m) => (m['dy'] as num) >= 0),
            isTrue,
            reason: 'jari ke atas → scroll ke bawah (positif)',
          );
          final during = r.sent.length;
          r.up(1, const Offset(100, 180));
          r.up(2, const Offset(160, 180));
          r.tick(async, 100);
          final coasting = r.sent.length;
          expect(coasting, greaterThan(during), reason: 'inersia');
          r.down(3, const Offset(10, 10));
          r.tick(async, 100);
          expect(
            r.sent.length,
            coasting,
            reason: 'sentuhan menghentikan inersia',
          );
          expect(r.viewport.zooms, isEmpty);
        });
      },
    );

    test('pinch = zoom tampilan, tidak ada pesan ke Mac', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad);
        r.down(1, const Offset(200, 300));
        r.down(2, const Offset(260, 300));
        for (var i = 1; i <= 10; i++) {
          r.tick(async, 8);
          r.move(1, Offset(200 - i * 6.0, 300));
          r.move(2, Offset(260 + i * 6.0, 300));
        }
        r.up(1, const Offset(140, 300));
        r.up(2, const Offset(320, 300));
        r.tick(async, 500);
        expect(r.sent, isEmpty);
        expect(r.viewport.zooms, isNotEmpty);
        final total = r.viewport.zooms.fold<double>(
          1,
          (s, z) => s * z.scaleRatio,
        );
        expect(total, closeTo(3.0, 0.05));
      });
    });

    test('klik dengan modifier sticky dibungkus kd/ku', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.trackpad, mods: () => [RemoteModifier.meta]);
        r.down(1, const Offset(100, 100));
        r.tick(async, 50);
        r.up(1, const Offset(100, 100));
        r.tick(async, 300);
        expect(r.sent, [
          {'t': 'kd', 'code': 'MetaLeft'},
          {'t': 'click', 'b': 0, 'n': 1},
          {'t': 'ku', 'code': 'MetaLeft'},
        ]);
      });
    });
  });

  group('sentuh', () {
    test('ketuk = mm di titik itu + click', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.touch);
        r.down(1, const Offset(250, 500));
        r.tick(async, 50);
        r.up(1, const Offset(250, 500));
        r.tick(async, 300);
        expect(r.sent, [
          {'t': 'mm', 'x': 0.25, 'y': 0.5},
          {'t': 'click', 'b': 0, 'n': 1},
        ]);
      });
    });

    test('ketuk ganda = mm + click n=2', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.touch);
        r.down(1, const Offset(250, 500));
        r.tick(async, 50);
        r.up(1, const Offset(250, 500));
        r.tick(async, 100);
        r.down(2, const Offset(252, 502));
        r.tick(async, 50);
        r.up(2, const Offset(252, 502));
        r.tick(async, 300);
        expect(r.types, ['mm', 'mm', 'click']);
        expect(r.sent.last, {'t': 'click', 'b': 0, 'n': 2});
      });
    });

    test('tahan = klik kanan di titik itu', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.touch);
        r.down(1, const Offset(100, 200));
        r.tick(async, 700);
        r.up(1, const Offset(100, 200));
        r.tick(async, 300);
        expect(r.sent, [
          {'t': 'mm', 'x': 0.1, 'y': 0.2},
          {'t': 'click', 'b': 1, 'n': 1},
        ]);
        expect(r.viewport.haptics, [RemoteHaptic.heavy]);
      });
    });

    test('geser = drag absolut mm, md, mm…, mu', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.touch);
        r.down(1, const Offset(100, 100));
        r.drag1(async, 1, const Offset(100, 100), const Offset(300, 100));
        r.up(1, const Offset(300, 100));
        expect(r.sent.first, {'t': 'mm', 'x': 0.1, 'y': 0.1});
        expect(r.sent[1], {'t': 'md', 'b': 0});
        expect(r.sent.last, {'t': 'mu', 'b': 0});
        expect(r.sent[r.sent.length - 2], {'t': 'mm', 'x': 0.3, 'y': 0.1});
        expect(r.types.where((t) => t == 'mr'), isEmpty);
      });
    });

    test('ketuk 2 jari = klik kanan di titik tengah', () {
      fakeAsync((async) {
        final r = _Rig(InputMode.touch);
        r.down(1, const Offset(100, 100));
        r.down(2, const Offset(300, 100));
        r.tick(async, 80);
        r.up(1, const Offset(100, 100));
        r.up(2, const Offset(300, 100));
        expect(r.sent, [
          {'t': 'mm', 'x': 0.2, 'y': 0.1},
          {'t': 'click', 'b': 1, 'n': 1},
        ]);
      });
    });
  });
}
