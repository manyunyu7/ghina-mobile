// Drawing a character that is using furniture: sitting, napping, praying,
// playing, exercising, reading. Built from the same baked person images as
// walking/typing, rotated by exact quarter turns so the pixels stay crisp.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;

import 'floor_pixel.dart';
import 'floor_sim.dart';

/// Sholat cycle in seconds: stand, bow, stand, prostrate, sit, prostrate, sit.
const _prayCycle = [
  ('berdiri', 3.4),
  ('rukuk', 2.2),
  ('berdiri', 1.4),
  ('sujud', 2.2),
  ('duduk', 1.6),
  ('sujud', 2.2),
  ('duduk', 3.2),
];

/// Name of the prayer stage at [t] seconds since the pose began.
String prayStage(double t) {
  final total = _prayCycle.fold<double>(0, (a, b) => a + b.$2);
  var k = t % total;
  for (final s in _prayCycle) {
    if (k < s.$2) return s.$1;
    k -= s.$2;
  }
  return 'berdiri';
}

PersonPose _pp(
  String dir, {
  bool walk = false,
  bool sit = false,
  bool typing = false,
  bool blink = false,
  int phase = 0,
}) => PersonPose(
  dir: dir,
  walk: walk,
  sit: sit,
  typing: typing,
  blink: blink,
  phase: phase,
);

/// Draws [e] (which has a [FloorEnt.pose]) with feet at its position.
void drawPosedPerson(ui.Canvas c, ui.Paint img, FloorEnt e, double time) {
  final pose = e.pose!;
  final x = e.x.roundToDouble(), y = e.y.roundToDouble();
  final blink = ((time + e.t0) % 4.2) < .14;
  final t = time - pose.since;
  final face = pose.face;
  final px = Px(c);

  void draw(PersonPose p, double dx, double dy) => c.drawImage(
    personImage(e.look, p),
    ui.Offset(x - kPersonCx + dx, y - kPersonFeet + dy),
    img,
  );

  /// Whole person turned a quarter: `turn` = +1 head right, -1 head left.
  void turned(
    PersonPose p,
    int turn,
    double cx,
    double cy, {
    double scale = 1,
  }) {
    c.save();
    c.translate(x + cx, y + cy);
    c.rotate(turn * math.pi / 2);
    if (scale != 1) c.scale(scale, 1);
    c.drawImage(
      personImage(e.look, p),
      ui.Offset(-kPersonCx.toDouble(), -24),
      img,
    );
    c.restore();
  }

  switch (pose.kind) {
    case 'sit':
      final typing = const {'type', 'think', 'test', 'server'}.contains(pose.aff);
      draw(
        _pp(
          face == 'up' ? 'up' : face,
          sit: true,
          typing: typing,
          phase: typing ? (time * 9).floor() % 2 : 0,
          blink: blink,
        ),
        0,
        1,
      );
    case 'play':
      final ph = (time * 9).floor() % 2;
      if (pose.sortY != null) {
        // on a seat (console, sofa): hands mashing
        draw(_pp(face, sit: true, typing: true, phase: ph, blink: blink), 0, 1);
      } else {
        draw(_pp(face, walk: true, phase: ph), 0, ph == 1 ? -1 : 0);
      }
    case 'exercise':
      final ph = (time * 6).floor() % 2;
      draw(_pp(face, walk: true, phase: ph), 0, ph == 1 ? -1 : 0);
    case 'read':
      draw(_pp(face, blink: blink), 0, 0);
      _book(px, x, y);
    case 'sleep':
      final head = face == 'right' ? 1 : -1;
      turned(_pp('down'), head, 0, -5);
      _zzz(px, x + head * 10.0, y - 14, time);
    case 'pray':
      _pray(c, img, e, t, draw, turned);
    default:
      draw(_pp(face, blink: blink), 0, 0);
      _prop(px, pose.aff, x, y, time);
      if (e.minion) _minionProp(px, pose.aff, x, y, time);
  }
}

void _pray(
  ui.Canvas c,
  ui.Paint img,
  FloorEnt e,
  double t,
  void Function(PersonPose, double, double) draw,
  void Function(PersonPose, int, double, double, {double scale}) turned,
) {
  final face = e.pose!.face;
  final side = face == 'right' ? 1 : -1;
  switch (prayStage(t)) {
    case 'rukuk':
      // upper body bent forward, hips stay
      final x = e.x.roundToDouble(), y = e.y.roundToDouble();
      c.save();
      c.translate(x, y - 6);
      c.rotate(side * math.pi / 2);
      c.clipRect(const ui.Rect.fromLTWH(-20, -40, 40, 40));
      c.drawImage(
        personImage(e.look, _pp('down')),
        ui.Offset(-kPersonCx.toDouble(), -(kPersonFeet - 6).toDouble()),
        img,
      );
      c.restore();
      c.save();
      c.clipRect(ui.Rect.fromLTWH(x - 20, y - 6, 40, 12));
      c.drawImage(
        personImage(e.look, _pp('down')),
        ui.Offset(x - kPersonCx, y - kPersonFeet),
        img,
      );
      c.restore();
    case 'sujud':
      turned(_pp('down'), side, 0, -4, scale: .78);
    case 'duduk':
      draw(_pp(face == 'up' ? 'up' : face, sit: true), 0, 3);
    default:
      draw(_pp(face), 0, 0);
  }
}

void _prop(Px p, String aff, double x, double y, double time) {
  switch (aff) {
    case 'coffee':
    case 'water':
    case 'snack':
    case 'eat':
      p.r(x + 5, y - 9, 4, 4, kOl);
      p.r(
        x + 6,
        y - 8,
        2,
        2,
        aff == 'water'
            ? '#8FC7EA'
            : aff == 'snack'
            ? '#F2CF72'
            : '#F4F4F4',
      );
      if (aff == 'coffee' && (time * 2).floor() % 2 == 0)
        p.r(x + 7, y - 11, 1, 2, 'rgba(255,255,255,.6)');
    case 'phone':
      p.r(x + 4, y - 20, 3, 5, kOl);
      p.r(x + 5, y - 19, 1, 3, '#7FD3C9');
    case 'whiteboard':
      if ((time * 2).floor() % 2 == 0) p.r(x + 6, y - 14, 1, 1, '#C2413A');
    case 'plant':
      p.r(x + 5, y - 8, 3, 3, kOl);
      p.r(x + 6, y - 7, 1, 1, '#8FC7EA');
    case 'wudhu':
      for (var i = 0; i < 2; i++) {
        final k = ((time * 3).floor() + i) % 3;
        p.r(x - 5 + i * 9, y - 9 + k, 1, 1, '#8FC7EA');
      }
  }
}

/// Extra props only Magang carry while working: watering can, a sheet from the printer.
void _minionProp(Px p, String aff, double x, double y, double time) {
  if (aff == 'plant') {
    final k = (time * 4).floor() % 3;
    p.r(x + 3, y - 14, 6, 5, kOl);
    p.r(x + 4, y - 13, 4, 3, '#6FA8DC');
    p.r(x + 9, y - 13, 2, 1, '#6FA8DC');
    p.r(x + 11, y - 11 + k, 1, 1, '#BFE3F5');
    p.r(x + 12, y - 8 + k, 1, 1, '#8EC6EA');
  } else if (aff == 'print') {
    p.r(x + 4, y - 14, 7, 8, kOl);
    p.r(x + 5, y - 13, 5, 6, '#FDFCF2');
    p.r(x + 6, y - 11, 3, 1, '#9AA3AF');
    p.r(x + 6, y - 9, 3, 1, '#9AA3AF');
  }
}

void _book(Px p, double x, double y) {
  p.r(x - 5, y - 12, 10, 6, kOl);
  p.r(x - 4, y - 11, 4, 4, '#F4F4F4');
  p.r(x + 0, y - 11, 4, 4, '#E8E2D0');
  p.r(x - 1, y - 11, 1, 4, '#9A8F7A');
}

void _zzz(Px p, double x, double y, double time) {
  for (var i = 0; i < 3; i++) {
    final k = ((time * .55) + i / 3) % 1;
    final a = (1 - k).clamp(0.0, 1.0);
    final zx = x + k * 5 + i * 2, zy = y - k * 14;
    final col = Color.fromRGBO(255, 255, 255, a);
    final o = Color.fromRGBO(30, 22, 40, a * .8);
    p.r(zx - 1, zy - 1, 5, 1, o);
    p.r(zx - 1, zy + 3, 5, 1, o);
    p.r(zx, zy, 3, 1, col);
    p.r(zx + 1, zy + 1, 1, 1, col);
    p.r(zx, zy + 2, 3, 1, col);
  }
}
