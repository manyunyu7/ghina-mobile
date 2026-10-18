import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/typography.dart';
import '../tokens/colors.dart';
import 'mascot_kind.dart';
import 'mascot_painter.dart';

part 'mascot_designs.dart';

/// The painter for [kind]: the classic tree painter for [MascotKind.pohon]
/// (so the default look never changes), the shared rig for every other one.
CustomPainter mascotPainterFor(
  MascotKind kind, {
  required MascotMood mood,
  double phase = 0,
  Color? shadowColor,
  ChunkySwatch? treeColor,
}) {
  if (kind == MascotKind.pohon) {
    return treeColor == null
        ? MascotPainter(mood: mood, phase: phase, shadowColor: shadowColor)
        : MascotPainter(
            mood: mood,
            phase: phase,
            shadowColor: shadowColor,
            color: treeColor,
          );
  }
  return MascotRigPainter(
    kind: kind,
    mood: mood,
    phase: phase,
    shadowColor: shadowColor,
  );
}

/// Paints any of the 15 mascots with one shared rig (ported from the
/// "maskot-ghina" exploration): back layer, legs/feet/wheels, body, head with
/// face (blush, blinking eyes, brows, swappable mouth), arms, and particles.
///
/// Everything is drawn in a 200×200 design box, scaled to the canvas.
/// [phase] (0..1, looping every 4 s in [MascotView]) drives the poses:
///
/// * happy: breathing
/// * excited: jumps with arms up, coins + sparkles
/// * thinking: hand to chin, "?"
/// * sad: droops, tears
/// * sleeping: closed eyes, Zzz
/// * waving: waves one arm
class MascotRigPainter extends CustomPainter {
  MascotRigPainter({
    required this.kind,
    required this.mood,
    this.phase = 0,
    this.shadowColor,
  });

  final MascotKind kind;
  final MascotMood mood;
  final double phase;

  /// Ground shadow color (theme-aware). Null = no ground shadow.
  final Color? shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final m = _designs[kind]!;
    final s = math.min(size.width, size.height) / 200;
    canvas.save();
    canvas.translate((size.width - 200 * s) / 2, (size.height - 200 * s) / 2);
    canvas.scale(s);

    final p = _Pose.of(mood, phase);

    if (shadowColor != null) {
      final k = (1 + p.rootDy / 60).clamp(0.4, 1.0);
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(100, 193),
          width: 112 * k,
          height: 12 * k,
        ),
        Paint()..color = shadowColor!,
      );
    }

    final fx = _Fx(m, mood, phase);
    fx.paintBack(canvas);

    // Root: the whole character (jump / squash).
    canvas.save();
    canvas.translate(100 + p.rootDx, 188 + p.rootDy);
    canvas.rotate(p.rootRot);
    canvas.scale(p.rootSx, p.rootSy);
    canvas.translate(-100, -188);

    if (m.back.isNotEmpty) {
      if (m.flareBack && p.flare != 0) {
        canvas.save();
        canvas.translate(100, 150);
        canvas.scale(1 + p.flare, 1 + p.flare);
        canvas.translate(-100, -150);
        _run(canvas, m.back);
        canvas.restore();
      } else {
        _run(canvas, m.back);
      }
    }
    _legs(canvas, m, p);

    // Body (breath / slump around its pivot).
    canvas.save();
    canvas.translate(m.bodyPivot.dx, m.bodyPivot.dy);
    canvas.scale(p.bodySx, p.bodySy);
    canvas.translate(-m.bodyPivot.dx, -m.bodyPivot.dy);
    _run(canvas, m.body);
    canvas.restore();

    // Head + face.
    canvas.save();
    canvas.translate(m.headPivot.dx + p.headDx, m.headPivot.dy + p.headDy);
    canvas.rotate(p.headRot);
    canvas.translate(-m.headPivot.dx, -m.headPivot.dy);
    _run(canvas, m.head);
    _face(canvas, m, p);
    canvas.restore();

    _arms(canvas, m, p);
    canvas.restore();

    fx.paintFront(canvas);
    canvas.restore();
  }

  static void _run(Canvas canvas, List<_Op> ops) {
    for (final op in ops) {
      op(canvas);
    }
  }

  // ---- face -------------------------------------------------------------------

  static final _blushPaint = Paint()..color = const Color(0x59FF7A8A);
  static final _white = Paint()..color = Colors.white;
  static final _inkFill = Paint()..color = _inkK;
  static final _eyeStroke = _strokeP(3.5);
  static final _browStroke = _strokeP(4);
  static final _closedStroke = _strokeP(4.2);
  static final _browPath = _svg('M-8,1 Q0,-3 8,1');
  static final _closedPath = _svg('M-10,-1 Q0,8 10,-1');
  static final _eyeRect = Rect.fromCenter(
    center: Offset.zero,
    width: 22,
    height: 26,
  );

  void _face(Canvas canvas, _Design m, _Pose p) {
    for (final b in [m.blushL, m.blushR]) {
      canvas.drawOval(
        Rect.fromCenter(center: b, width: 18, height: 10),
        _blushPaint,
      );
    }
    for (final e in [m.eyeL, m.eyeR]) {
      canvas.save();
      canvas.translate(e.dx, e.dy);
      canvas.scale(m.eyeScale);
      if (p.closed) {
        canvas.drawPath(_closedPath, _closedStroke);
      } else {
        canvas.scale(1, p.blink);
        canvas.drawOval(_eyeRect, _white);
        canvas.drawOval(_eyeRect, _eyeStroke);
        final c = p.pupil;
        canvas.drawCircle(c + const Offset(1, 1.5), 7, _inkFill);
        canvas.drawCircle(c + const Offset(-1.6, -2.2), 2.6, _white);
      }
      canvas.restore();
    }
    // Brows.
    for (final (e, dy, rot) in [
      (m.eyeL, p.browLDy, p.browLRot),
      (m.eyeR, p.browRDy, p.browRRot),
    ]) {
      canvas.save();
      canvas.translate(e.dx, e.dy - 13 * m.eyeScale - 8 + dy);
      canvas.rotate(rot);
      canvas.drawPath(_browPath, _browStroke);
      canvas.restore();
    }
    // Mouth.
    canvas.save();
    canvas.translate(m.mouth.dx, m.mouth.dy);
    canvas.scale(m.mouthScale, m.mouthScale * p.mouthSy);
    _run(canvas, _mouths[p.mouth]!);
    canvas.restore();
    _run(canvas, m.front);
  }

  // ---- limbs ------------------------------------------------------------------

  void _arms(Canvas canvas, _Design m, _Pose p) {
    for (final (at, angle) in [(m.arm.l, p.armL), (m.arm.r, p.armR)]) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      m.arm.paint(canvas);
      canvas.restore();
    }
  }

  void _legs(Canvas canvas, _Design m, _Pose p) {
    for (final (at, dy, side) in [
      (m.legs.l, p.legLDy, -1.0),
      (m.legs.r, p.legRDy, 1.0),
    ]) {
      canvas.save();
      canvas.translate(at.dx, at.dy + dy);
      m.legs.paint(canvas, side, p.wheel);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(MascotRigPainter old) =>
      old.phase != phase ||
      old.mood != mood ||
      old.kind != kind ||
      old.shadowColor != shadowColor;
}

// ---------------------------------------------------------------- poses

enum _Mouth { smile, open, tongue, o, flat, frown }

double _deg(double d) => d * math.pi / 180;

/// 0 → 1 → 0 over one cycle, eased.
double _wave(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * t);

/// CSS-like keyframes (ease-in-out per segment). [k] = (time, value).
double _kf(double t, List<(double, double)> k) {
  if (t <= k.first.$1) return k.first.$2;
  for (var i = 1; i < k.length; i++) {
    final (t1, v1) = k[i];
    if (t <= t1) {
      final (t0, v0) = k[i - 1];
      final u = t1 == t0 ? 1.0 : (t - t0) / (t1 - t0);
      return v0 + (v1 - v0) * Curves.easeInOut.transform(u.clamp(0.0, 1.0));
    }
  }
  return k.last.$2;
}

/// Cycles of each mood's move per 4 s loop (keeps the loop seamless).
int _cycles(MascotMood mood) => switch (mood) {
  MascotMood.happy => 1,
  MascotMood.sleeping => 1,
  MascotMood.waving => 2,
  MascotMood.thinking => 2,
  MascotMood.sad => 2,
  MascotMood.excited => 3,
};

class _Pose {
  double rootDx = 0, rootDy = 0, rootRot = 0, rootSx = 1, rootSy = 1;
  double bodySx = 1, bodySy = 1;
  double headDx = 0, headDy = 0, headRot = 0;
  double armL = _deg(20), armR = _deg(-20);
  double legLDy = 0, legRDy = 0;
  Offset pupil = Offset.zero;
  double blink = 1;
  bool closed = false;
  double browLDy = 0, browRDy = 0, browLRot = 0, browRRot = 0;
  _Mouth mouth = _Mouth.smile;
  double mouthSy = 1;
  double wheel = 0;

  /// Extra scale of the back layer (cendrawasih plumes bloom).
  double flare = 0;

  static double _blinkAt(double phase) {
    double b(double center) {
      final d = (phase - center).abs();
      return d < 0.025 ? math.max(0.1, d / 0.025) : 1;
    }

    return math.min(b(0.42), b(0.9));
  }

  factory _Pose.of(MascotMood mood, double phase) {
    final p = _Pose();
    final t = (phase * _cycles(mood)) % 1;
    p.blink = _blinkAt(phase);
    switch (mood) {
      case MascotMood.happy:
        // napas: breathing, floating head, arms swinging softly.
        final v = _wave(t);
        p.bodySx = 1 + 0.03 * v;
        p.bodySy = 1 + 0.05 * v;
        p.headDy = -3 * v;
        p.armL = _deg(16 + 10 * v);
        p.armR = _deg(-16 - 10 * v);
        p.mouth = _Mouth.smile;
      case MascotMood.waving:
        // lambai: right arm waves, head tilts, mouth chats.
        p.armR = _deg(
          _kf(t, const [
            (0, -20),
            (.14, -150),
            (.28, -118),
            (.42, -150),
            (.56, -118),
            (.70, -150),
            (.86, -20),
            (1, -20),
          ]),
        );
        p.headRot = _deg(_kf(t, const [(0, 0), (.2, 7), (.7, 7), (1, 0)]));
        p.mouth = _Mouth.open;
        p.mouthSy = _kf((phase * 8) % 1, const [(0, 1), (.5, .65), (1, 1)]);
        final v = _wave(phase);
        p.bodySx = 1 + 0.02 * v;
        p.bodySy = 1 + 0.03 * v;
      case MascotMood.excited:
        // lompat: crouch, jump with both arms up, land.
        p.rootDy = _kf(t, const [
          (0, 0),
          (.15, 0),
          (.40, -30),
          (.55, -30),
          (.80, 0),
          (1, 0),
        ]);
        p.rootSx = _kf(t, const [
          (0, 1),
          (.15, 1.12),
          (.40, .94),
          (.55, 1),
          (.80, 1.1),
          (.92, .98),
          (1, 1),
        ]);
        p.rootSy = _kf(t, const [
          (0, 1),
          (.15, .86),
          (.40, 1.08),
          (.55, 1),
          (.80, .88),
          (.92, 1.03),
          (1, 1),
        ]);
        final a = _kf(t, const [
          (0, 128),
          (.15, 118),
          (.40, 160),
          (.60, 160),
          (.85, 128),
          (1, 128),
        ]);
        p.armL = _deg(a);
        p.armR = _deg(-a);
        final tuck = _kf(t, const [
          (0, 0),
          (.2, 0),
          (.40, -6),
          (.55, -6),
          (.75, 0),
          (1, 0),
        ]);
        p.legLDy = tuck;
        p.legRDy = tuck;
        p.mouth = _Mouth.open;
        p.wheel = -phase * 2 * math.pi * 3;
        p.flare = 0.06 + 0.06 * _wave(t);
      case MascotMood.thinking:
        // mikir: head tilts, hand to chin, eyes up, one brow raised.
        final v = _wave(t);
        p.headRot = _deg(-8 - 3 * v);
        p.armR = _deg(146 - 8 * v);
        p.pupil = const Offset(3, -4);
        p.browRDy = -4;
        p.browRRot = _deg(-12);
        p.mouth = _Mouth.flat;
      case MascotMood.sad:
        // sedih: head droops, body slumps, arms hang, worried brows.
        final v = _wave(t);
        p.headDy = 6 + 3 * v;
        p.headRot = _deg(-4 - v);
        p.bodySy = 0.97;
        p.armL = _deg(6);
        p.armR = _deg(-6);
        p.browLDy = -2;
        p.browRDy = -2;
        p.browLRot = _deg(-16);
        p.browRRot = _deg(16);
        p.pupil = const Offset(0, 3);
        p.mouth = _Mouth.frown;
      case MascotMood.sleeping:
        // tidur: head rests to the side, slow breathing, eyes shut.
        final v = _wave(t);
        p.headDx = 3;
        p.headDy = 5 + 3 * v;
        p.headRot = _deg(12 + 2 * v);
        p.bodySx = 1 + 0.03 * v;
        p.bodySy = 1 + 0.05 * v;
        p.armL = _deg(8);
        p.armR = _deg(-8);
        p.closed = true;
        p.mouth = _Mouth.o;
        p.mouthSy = 1 + 0.15 * v;
    }
    return p;
  }

  _Pose();
}

// ---------------------------------------------------------------- particles

enum _Sym { coin, sparkle, zzz, question, sweat, dust }

/// A particle's animated transform at time [k] (0..1).
typedef _Anim = ({double dx, double dy, double rot, double scale, double op});

_Anim _rise(double k, double dx) => (
  dx: _kf(k, [(0, 0), (1, dx)]),
  dy: _kf(k, const [(0, 0), (1, -64)]),
  rot: 0,
  scale: _kf(k, const [(0, .5), (1, 1.1)]),
  op: _kf(k, const [(0, 0), (.15, 1), (1, 0)]),
);

_Anim _twinkle(double k) => (
  dx: 0,
  dy: 0,
  rot: _deg(_kf(k, const [(0, 0), (.5, 45), (1, 0)])),
  scale: _kf(k, const [(0, .25), (.5, 1), (1, .25)]),
  op: _kf(k, const [(0, .2), (.5, 1), (1, .2)]),
);

_Anim _bob(double k) => (
  dx: 0,
  dy: _kf(k, const [(0, 0), (.5, -8), (1, 0)]),
  rot: _deg(_kf(k, const [(0, -8), (.5, 8), (1, -8)])),
  scale: 1,
  op: 1,
);

_Anim _drop(double k) => (
  dx: 0,
  dy: _kf(k, const [(0, 0), (.25, 2), (1, 36)]),
  rot: 0,
  scale: _kf(k, const [(0, .3), (.25, 1), (1, .9)]),
  op: _kf(k, const [(0, 0), (.25, 1), (1, 0)]),
);

_Anim _pop(double k) => (
  dx: 0,
  dy: 0,
  rot: 0,
  scale: _kf(k, const [(0, 0), (.2, 1.25), (.55, 1), (1, 1.35)]),
  op: _kf(k, const [(0, 0), (.2, 1), (.55, 1), (1, 0)]),
);

class _Fx {
  _Fx(this.m, this.mood, this.phase);

  final _Design m;
  final MascotMood mood;
  final double phase;

  /// Move-cycle time for a particle with CSS-style negative delay [del].
  double _t(double del) => (phase * _cycles(mood) + del) % 1;

  double get _top => math.min(m.eyeL.dy, m.eyeR.dy) - 46;

  Offset _hand(Offset shoulder, double deg) {
    final r = _deg(deg);
    return Offset(
      shoulder.dx - math.sin(r) * m.arm.len,
      shoulder.dy + math.cos(r) * m.arm.len,
    );
  }

  void paintBack(Canvas canvas) {}

  void paintFront(Canvas canvas) {
    final eL = m.eyeL, eR = m.eyeR;
    switch (mood) {
      case MascotMood.happy:
        break;
      case MascotMood.waving:
        final h = _hand(m.arm.r, -140);
        _p(canvas, _Sym.sparkle, h + const Offset(10, -8), 16, _twinkle(_t(0)));
        _p(
          canvas,
          _Sym.sparkle,
          h + const Offset(-6, -16),
          10,
          _twinkle(_t(.5)),
        );
      case MascotMood.excited:
        // Coins fly up out of the raised hands, sparkles all around.
        final hl = _hand(m.arm.l, 150), hr = _hand(m.arm.r, -150);
        final mid = Offset((hl.dx + hr.dx) / 2, math.min(hl.dy, hr.dy) - 4);
        // Slower than the jump so each coin is readable.
        double slow(double del) => (phase * 2 + del) % 1;
        _p(canvas, _Sym.coin, hl, 18, _rise(slow(0), -14));
        _p(canvas, _Sym.coin, hr, 18, _rise(slow(.5), 14));
        _p(canvas, _Sym.coin, mid, 16, _rise(slow(.25), 0));
        const spots = [
          (22.0, 58.0),
          (178.0, 50.0),
          (26.0, 142.0),
          (174.0, 136.0),
        ];
        for (var i = 0; i < spots.length; i++) {
          final (x, y) = spots[i];
          _p(
            canvas,
            _Sym.sparkle,
            Offset(x, y),
            i.isEven ? 16 : 12,
            _twinkle((phase * 2 + i / 4) % 1),
          );
        }
        // Dust puffs on landing.
        for (final (f, dir) in [(m.legs.l, -1.0), (m.legs.r, 1.0)]) {
          _p(canvas, _Sym.dust, f + Offset(dir * 14, 2), 18, _pop(_t(-.72)));
        }
      case MascotMood.thinking:
        _p(
          canvas,
          _Sym.question,
          Offset(math.min(eR.dx + 36, 178), _top + 12),
          30,
          _bob(_t(0)),
        );
        _p(
          canvas,
          _Sym.sparkle,
          Offset(math.min(eR.dx + 18, 166), _top + 34),
          8,
          _twinkle(_t(.3)),
        );
      case MascotMood.sad:
        final y = 14 * m.eyeScale + 7;
        _p(canvas, _Sym.sweat, eL + Offset(6, y), 12, _drop(_t(0)));
        _p(canvas, _Sym.sweat, eR + Offset(-6, y), 12, _drop(_t(.5)));
      case MascotMood.sleeping:
        for (var i = 0; i < 3; i++) {
          // Three z's per loop, staggered.
          final k = (phase + i / 3) % 1;
          _p(
            canvas,
            _Sym.zzz,
            Offset(eR.dx + 24 + i * 6.0, _top + 22),
            14 + i * 3.0,
            _rise(k, 18),
          );
        }
    }
  }

  void _p(Canvas canvas, _Sym sym, Offset at, double size, _Anim a) {
    if (a.op <= 0.01 || a.scale <= 0.01) return;
    canvas.save();
    canvas.translate(at.dx + a.dx, at.dy + a.dy);
    if (a.rot != 0) canvas.rotate(a.rot);
    canvas.scale(a.scale * size / 20);
    canvas.translate(-10, -10);
    _symbol(canvas, sym, a.op.clamp(0.0, 1.0));
    canvas.restore();
  }
}

// 20×20 particle symbols.
final _coinRing = _svg('M7 6.5 Q8 5.5 10 5.5');
final _sparkle = _svg('M10 1 Q11 9 19 10 Q11 11 10 19 Q9 11 1 10 Q9 9 10 1Z');
final _zPath = _svg('M4 4 H16 L4 16 H16');
final _qPath = _svg(
  'M6 7 Q6 2.5 10.5 2.5 Q15 2.5 15 6.5 Q15 9.5 11.5 10.5 Q10 11 10 13',
);
final _sweat = _svg('M10 2 Q16.5 11 13.5 15.5 Q10 19 6.5 15.5 Q3.5 11 10 2Z');
final _sweatHi = _svg('M8 13 Q8 15 10 15.5');

void _symbol(Canvas canvas, _Sym sym, double op) {
  Paint f(int c) => Paint()..color = Color(c).withValues(alpha: op);
  Paint s(double w, [int c = 0xFF2A2118]) =>
      _strokeP(w, Color(c).withValues(alpha: op));
  switch (sym) {
    case _Sym.coin:
      const c = Offset(10, 10);
      canvas.drawCircle(c, 8.5, f(0xFFFFC531));
      canvas.drawCircle(c, 8.5, s(2));
      canvas.drawCircle(c, 5.2, s(1.8, 0xFFE0A00C));
      canvas.drawPath(_coinRing, s(1.6, 0xFFFFF3C4));
    case _Sym.sparkle:
      canvas.drawPath(_sparkle, f(0xFFFFD43B));
      canvas.drawPath(_sparkle, s(1.2));
    case _Sym.zzz:
      canvas.drawPath(_zPath, s(5));
      canvas.drawPath(_zPath, s(2.6, 0xFF7B95FF));
    case _Sym.question:
      canvas.drawPath(_qPath, s(5));
      canvas.drawPath(_qPath, s(2.6, 0xFF8A6CF0));
      canvas.drawCircle(const Offset(10, 17.3), 2.2, f(0xFF8A6CF0));
      canvas.drawCircle(const Offset(10, 17.3), 2.2, s(1.4));
    case _Sym.sweat:
      canvas.drawPath(_sweat, f(0xFF8FD0FF));
      canvas.drawPath(_sweat, s(1.6));
      canvas.drawPath(_sweatHi, s(1.4, 0xFFFFFFFF));
    case _Sym.dust:
      for (final (c, r) in [
        (const Offset(6, 13), 4.5),
        (const Offset(13, 11), 5.5),
      ]) {
        canvas.drawCircle(c, r, f(0xFFE6D8C2));
        canvas.drawCircle(c, r, s(1.2));
      }
  }
}

// ---------------------------------------------------------------- svg paths

final _tokens = RegExp(r'[MmLlHhVvQqCcZz]|-?(?:\d+\.?\d*|\.\d+)');

/// Tiny SVG path-data parser (M L H V Q C Z, absolute and relative) so the
/// designs keep the reference's exact path strings.
Path _svg(String d) {
  final t = _tokens.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0;
  bool isCmd(String s) => s.length == 1 && RegExp('[A-Za-z]').hasMatch(s);
  double n() => double.parse(t[i++]);
  while (i < t.length) {
    if (isCmd(t[i])) cmd = t[i++];
    switch (cmd) {
      case 'M':
        x = n();
        y = n();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = 'L';
      case 'm':
        x += n();
        y += n();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = 'l';
      case 'L':
        x = n();
        y = n();
        path.lineTo(x, y);
      case 'l':
        x += n();
        y += n();
        path.lineTo(x, y);
      case 'H':
        x = n();
        path.lineTo(x, y);
      case 'h':
        x += n();
        path.lineTo(x, y);
      case 'V':
        y = n();
        path.lineTo(x, y);
      case 'v':
        y += n();
        path.lineTo(x, y);
      case 'Q':
        final x1 = n(), y1 = n();
        x = n();
        y = n();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'q':
        final x1 = x + n(), y1 = y + n();
        x += n();
        y += n();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'C':
        final x1 = n(), y1 = n(), x2 = n(), y2 = n();
        x = n();
        y = n();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'c':
        final x1 = x + n(), y1 = y + n(), x2 = x + n(), y2 = y + n();
        x += n();
        y += n();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Z' || 'z':
        path.close();
        x = sx;
        y = sy;
      default:
        throw FormatException('Unsupported path command $cmd in "$d"');
    }
  }
  return path;
}

/// [source] as dashes of [on] / gaps of [off].
Path _dashed(Path source, double on, double off) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      out.addPath(
        metric.extractPath(d, math.min(d + on, metric.length)),
        Offset.zero,
      );
      d += on + off;
    }
  }
  return out;
}
