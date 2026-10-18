part of 'mascot_rig_painter.dart';

// The 15 mascot designs on the shared rig, ported 1:1 from the
// "maskot-ghina" reference (200×200 box, same colors, shapes and pivots).
// Paths and paints are built once (top-level finals are lazy).

/// Outline ink.
const _inkK = Color(0xFF2A2118);

typedef _Op = void Function(Canvas canvas);

Paint _strokeP(double w, [Color c = _inkK, StrokeCap cap = StrokeCap.round]) =>
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = cap;

// ---- shape DSL ----------------------------------------------------------------

/// Filled [path], outlined with ink when [sw] is given.
_Op _fp(Path path, int fill, [double? sw]) {
  final f = Paint()..color = Color(fill);
  final s = sw == null ? null : _strokeP(sw);
  return (c) {
    c.drawPath(path, f);
    if (s != null) c.drawPath(path, s);
  };
}

/// Filled SVG path.
_Op _p(String d, int fill, [double? sw]) => _fp(_svg(d), fill, sw);

/// Stroke-only SVG path ([dash] = on/off lengths).
_Op _ln(
  String d,
  int color,
  double w, {
  (double, double)? dash,
  StrokeCap cap = StrokeCap.round,
}) {
  var path = _svg(d);
  if (dash != null) path = _dashed(path, dash.$1, dash.$2);
  final s = _strokeP(w, Color(color), cap);
  return (c) => c.drawPath(path, s);
}

Path _ovalPath(double cx, double cy, double rx, double ry) => Path()
  ..addOval(
    Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
  );

_Op _el(double cx, double cy, double rx, double ry, int fill, [double? sw]) =>
    _fp(_ovalPath(cx, cy, rx, ry), fill, sw);

_Op _ci(double cx, double cy, double r, int fill, [double? sw]) =>
    _el(cx, cy, r, r, fill, sw);

/// Stroke-only circle.
_Op _ring(double cx, double cy, double r, int color, double w) {
  final path = _ovalPath(cx, cy, r, r);
  final s = _strokeP(w, Color(color));
  return (c) => c.drawPath(path, s);
}

Path _rrPath(double x, double y, double w, double h, double r) =>
    Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));

_Op _rr(
  double x,
  double y,
  double w,
  double h,
  double r,
  int fill, [
  double? sw,
]) => _fp(_rrPath(x, y, w, h, r), fill, sw);

/// Rotates [ops] by [deg] around ([cx], [cy]).
_Op _rot(double deg, double cx, double cy, List<_Op> ops) => (c) {
  c.save();
  c.translate(cx, cy);
  c.rotate(_deg(deg));
  c.translate(-cx, -cy);
  for (final op in ops) {
    op(c);
  }
  c.restore();
};

/// Centered Nunito Black text with its baseline at [y].
_Op _tx(String text, double x, double y, double size, int color) => (c) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: GhinaType.nunito(size, weight: 900, color: Color(color)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  tp.paint(c, Offset(x - tp.width / 2, y - base));
  tp.dispose();
};

// ---- rig parts ----------------------------------------------------------------

final _mouths = <_Mouth, List<_Op>>{
  _Mouth.smile: [_p('M-12,-3 Q0,14 12,-3 Q0,3 -12,-3Z', 0xFF7A2A2A, 3)],
  _Mouth.open: [
    _p('M-11,-4 Q0,-6 11,-4 Q11,12 0,13 Q-11,12 -11,-4Z', 0xFF7A2A2A, 3),
    _p('M-6,8 Q0,3 6,8 Q0,12 -6,8Z', 0xFFFF7A8A),
  ],
  _Mouth.tongue: [
    _p('M-12,-3 Q0,14 12,-3 Q0,3 -12,-3Z', 0xFF7A2A2A, 3),
    _p('M-1,3 Q5,2 7,7 Q6,14 1,13 Q-3,10 -1,3Z', 0xFFFF7A8A, 2),
  ],
  _Mouth.o: [_el(0, 0, 6, 7.5, 0xFF7A2A2A, 3)],
  _Mouth.flat: [_ln('M-8,0 Q0,2 8,0', 0xFF2A2118, 4)],
  _Mouth.frown: [_ln('M-10,5 Q0,-5 10,5', 0xFF2A2118, 4)],
};

enum _ArmType { capsule, wing, stick }

/// Two arms hanging from shoulders [l] / [r], drawn pointing down (+y) and
/// rotated by the pose (positive = clockwise).
class _Arm {
  _Arm(this.type, this.l, this.r, this.len, int fill, [int? hand])
    : _ops = switch (type) {
        _ArmType.wing => [
          _p(
            'M0,-4 Q15,${len * .5} 0,${len + 8} Q-15,${len * .5} 0,-4Z',
            fill,
            3.5,
          ),
        ],
        _ArmType.stick => [
          _ln('M0,0 L0,$len', fill, 5),
          _ci(0, len + 2, 7.5, hand ?? 0xFFFFFFFF, 3),
        ],
        _ArmType.capsule => [
          _rr(-6.5, -4, 13, len + 4, 6.5, fill, 3.5),
          _ci(0, len, 8.5, hand ?? fill, 3.5),
        ],
      };

  final _ArmType type;
  final Offset l, r;
  final double len;
  final List<_Op> _ops;

  void paint(Canvas c) {
    for (final op in _ops) {
      op(c);
    }
  }
}

enum _LegType { foot, claw, stick, wheel, fin }

class _Legs {
  _Legs(this.type, this.l, this.r, [int fill = 0xFF000000])
    : _left = _build(type, -1, fill),
      _right = _build(type, 1, fill);

  final _LegType type;
  final Offset l, r;
  final List<_Op> _left, _right;

  static Path _mirror(String d, double f) =>
      _svg(d).transform(Matrix4.diagonal3Values(f, 1, 1).storage);

  static List<_Op> _build(_LegType type, double f, int fill) {
    switch (type) {
      case _LegType.claw:
        const d = 'M0,-10 L0,2 M0,2 L-7,8 M0,2 L0,9 M0,2 L7,8';
        return [_ln(d, 0xFF2A2118, 8), _ln(d, fill, 4)];
      case _LegType.stick:
        return [
          _ln('M0,-12 L0,0', 0xFF2A2118, 5),
          _fp(_mirror('M-8,5 Q-8,-4 2,-4 Q12,-4 13,5 Z', f), fill, 3),
        ];
      case _LegType.fin:
        return [_fp(_mirror('M-4,-10 Q10,-7 17,4 Q6,9 -5,4 Z', f), fill, 3.5)];
      case _LegType.wheel:
        return [
          _ci(0, 0, 14, 0xFF33404F, 4),
          _ln('M0,-11 L0,11 M-11,0 L11,0', 0xFFC8D2DC, 3),
          _ci(0, 0, 5, 0xFFC8D2DC, 2),
        ];
      case _LegType.foot:
        return [_el(f * 3, 0, 13, 7, fill, 3.5)];
    }
  }

  /// [side] -1 = left, 1 = right. [wheel] spins wheels.
  void paint(Canvas c, double side, double wheel) {
    if (type == _LegType.wheel && wheel != 0) c.rotate(wheel);
    for (final op in side < 0 ? _left : _right) {
      op(c);
    }
  }
}

class _Design {
  _Design({
    this.back = const [],
    required this.body,
    this.head = const [],
    this.front = const [],
    required this.bodyPivot,
    required this.headPivot,
    required this.eyeL,
    required this.eyeR,
    required this.eyeScale,
    required this.mouth,
    required this.mouthScale,
    required this.blushL,
    required this.blushR,
    required this.arm,
    required this.legs,
    this.flareBack = false,
  });

  /// Behind everything (tails, plumes, cards).
  final List<_Op> back;
  final List<_Op> body;

  /// Moves with the face (crown, ears, flap...).
  final List<_Op> head;

  /// On top of the face (beaks, noses).
  final List<_Op> front;
  final Offset bodyPivot, headPivot;
  final Offset eyeL, eyeR;
  final double eyeScale;
  final Offset mouth;
  final double mouthScale;
  final Offset blushL, blushR;
  final _Arm arm;
  final _Legs legs;

  /// The back layer blooms when excited (cendrawasih plumes).
  final bool flareBack;
}

// ---- the designs ----------------------------------------------------------------

const _canopy = [
  (100.0, 84.0, 52.0),
  (56.0, 100.0, 28.0),
  (144.0, 100.0, 28.0),
  (70.0, 56.0, 26.0),
  (130.0, 56.0, 26.0),
  (100.0, 44.0, 28.0),
];

const _tailKucing = 'M132,170 Q172,166 166,128 Q162,108 176,98';
const _tailKomodo = 'M134,172 Q176,174 180,146 Q182,132 172,126';

final Map<MascotKind, _Design> _designs = {
  // 1. Pohon Uang (rig version; MascotView keeps the classic tree painter).
  MascotKind.pohon: _Design(
    body: [
      _p(
        'M88,126 L87,170 Q85,181 74,187 L126,187 Q115,181 113,170 L112,126 Z',
        0xFF9A6233,
        4,
      ),
      _ln('M96,140 Q98,152 95,164 M106,136 Q104,148 107,160', 0xFF7A4A22, 3),
    ],
    bodyPivot: const Offset(100, 187),
    head: [
      for (final (x, y, r) in _canopy) _ci(x, y, r, 0xFF5FBF3A, 4),
      for (final (x, y, r) in _canopy) _ci(x, y, r - 2, 0xFF5FBF3A),
      _el(78, 58, 12, 7, 0xFF8BE05E),
      _el(124, 44, 10, 6, 0xFF8BE05E),
      for (final (x, y) in const [(56.0, 80.0), (144.0, 82.0), (118.0, 26.0)])
        _ci(x, y, 8, 0xFFFFC531, 3),
    ],
    headPivot: const Offset(100, 128),
    eyeL: const Offset(82, 90),
    eyeR: const Offset(118, 90),
    eyeScale: 1,
    mouth: const Offset(100, 112),
    mouthScale: 1,
    blushL: const Offset(68, 104),
    blushR: const Offset(132, 104),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(90, 140),
      const Offset(110, 140),
      32,
      0xFF9A6233,
      0xFF6CC644,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(90, 184),
      const Offset(110, 184),
      0xFF9A6233,
    ),
  ),

  // 2. Celengan Ayam
  MascotKind.ayam: _Design(
    back: [
      _p(
        'M52,118 Q22,96 30,70 Q44,86 54,100 Q40,72 54,54 Q62,80 66,100 Z',
        0xFFE8433A,
        4,
      ),
    ],
    body: [
      _el(100, 132, 56, 50, 0xFFF2884A, 4),
      _el(100, 152, 34, 22, 0xFFFFD8B5),
      _ci(72, 162, 4, 0xFFFFD8B5),
      _ci(128, 162, 4, 0xFFFFD8B5),
      _ci(104, 77, 9, 0xFFFFC531, 3),
      _rr(90, 80, 28, 7, 3.5, 0xFF2A2118),
    ],
    bodyPivot: const Offset(100, 182),
    head: [
      _p(
        'M62,94 Q56,78 66,74 Q66,62 76,64 Q82,54 90,62 Q96,72 88,88 Z',
        0xFFE8433A,
        4,
      ),
    ],
    front: [_p('M90,122 L100,113 L110,122 L100,131 Z', 0xFFFFC531, 3)],
    headPivot: const Offset(100, 170),
    eyeL: const Offset(80, 108),
    eyeR: const Offset(120, 108),
    eyeScale: .9,
    mouth: const Offset(100, 136),
    mouthScale: .7,
    blushL: const Offset(66, 124),
    blushR: const Offset(134, 124),
    arm: _Arm(
      _ArmType.wing,
      const Offset(50, 134),
      const Offset(150, 134),
      28,
      0xFFE0703A,
    ),
    legs: _Legs(
      _LegType.claw,
      const Offset(86, 181),
      const Offset(114, 181),
      0xFFFFB020,
    ),
  ),

  // 3. Kucing Oren
  MascotKind.kucing: _Design(
    back: [
      _ln(_tailKucing, 0xFF2A2118, 20),
      _ln(_tailKucing, 0xFFF39A2E, 12),
      _ln('M168,116 L176,112', 0xFFCF6F12, 5),
    ],
    body: [
      _el(100, 158, 40, 30, 0xFFF39A2E, 4),
      _el(100, 166, 22, 17, 0xFFFFE2BF),
    ],
    bodyPivot: const Offset(100, 186),
    head: [
      _p('M60,76 L64,30 L96,56 Z', 0xFFF39A2E, 4),
      _p('M140,76 L136,30 L104,56 Z', 0xFFF39A2E, 4),
      _p('M68,62 L69,42 L86,56Z', 0xFFFFB3B3),
      _p('M132,62 L131,42 L114,56Z', 0xFFFFB3B3),
      _el(100, 92, 50, 43, 0xFFF39A2E, 4),
      _ln(
        'M92,52 Q94,61 92,67 M100,50 L100,65 M108,52 Q106,61 108,67',
        0xFFCF6F12,
        4,
      ),
      _el(100, 114, 20, 13, 0xFFFFF1DF),
      _ln(
        'M58,108 L38,104 M58,115 L40,118 M142,108 L162,104 M142,115 L160,118',
        0xFF2A2118,
        3,
      ),
    ],
    front: [_p('M95,105 L105,105 L100,111Z', 0xFFFF7A8A, 2)],
    headPivot: const Offset(100, 134),
    eyeL: const Offset(80, 90),
    eyeR: const Offset(120, 90),
    eyeScale: 1,
    mouth: const Offset(100, 120),
    mouthScale: .75,
    blushL: const Offset(64, 106),
    blushR: const Offset(136, 106),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(72, 150),
      const Offset(128, 150),
      22,
      0xFFF39A2E,
      0xFFFFF1DF,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(84, 184),
      const Offset(116, 184),
      0xFFF39A2E,
    ),
  ),

  // 4. Kapibara
  MascotKind.kapibara: _Design(
    body: [
      _el(100, 150, 60, 38, 0xFFB07A4C, 4),
      _ln(
        'M64,140 q6,-4 10,0 M126,136 q6,-4 10,0 M95,172 q6,-4 10,0',
        0xFF8D5C33,
        3,
      ),
    ],
    bodyPivot: const Offset(100, 188),
    head: [
      _ci(64, 64, 10, 0xFF9C6A40, 4),
      _ci(136, 64, 10, 0xFF9C6A40, 4),
      _rr(52, 56, 96, 78, 36, 0xFFC18C5C, 4),
      _el(100, 114, 30, 17, 0xFFA87348),
      _ci(100, 46, 12, 0xFFFF9F1C, 4),
      _p('M100,34 q6,-8 13,-4 q-4,6 -13,4Z', 0xFF5FBF3A, 2),
    ],
    front: [_el(100, 106, 11, 6, 0xFF2A2118), _el(96, 104, 3, 1.6, 0x99FFFFFF)],
    headPivot: const Offset(100, 140),
    eyeL: const Offset(78, 86),
    eyeR: const Offset(122, 86),
    eyeScale: .75,
    mouth: const Offset(100, 124),
    mouthScale: .65,
    blushL: const Offset(64, 104),
    blushR: const Offset(136, 104),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(58, 152),
      const Offset(142, 152),
      18,
      0xFFB07A4C,
      0xFF9C6A40,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(76, 184),
      const Offset(124, 184),
      0xFF9C6A40,
    ),
  ),

  // 5. Lokomotif Mungil
  MascotKind.loko: _Design(
    body: [
      _rr(50, 130, 100, 44, 12, 0xFF2F6FD6, 4),
      _ci(62, 142, 3, 0xFFA9C8FF),
      _ci(138, 142, 3, 0xFFA9C8FF),
      _p('M58,172 L142,172 L130,186 L70,186 Z', 0xFFE8433A, 4),
      _rr(80, 143, 40, 17, 4, 0xFFFFC531, 3),
      _tx('168', 100, 156.5, 12.5, 0xFF2A2118),
    ],
    bodyPivot: const Offset(100, 186),
    head: [
      _rr(64, 22, 22, 34, 4, 0xFF3D4F66, 4),
      _rr(60, 16, 30, 9, 4, 0xFF3D4F66, 4),
      _ci(100, 92, 46, 0xFF3B82F6, 4),
      _ci(100, 92, 37, 0xFF5A9CF8),
      _ci(100, 50, 10, 0xFFFFE066, 4),
    ],
    headPivot: const Offset(100, 136),
    eyeL: const Offset(82, 92),
    eyeR: const Offset(118, 92),
    eyeScale: 1,
    mouth: const Offset(100, 114),
    mouthScale: 1,
    blushL: const Offset(68, 106),
    blushR: const Offset(132, 106),
    arm: _Arm(
      _ArmType.stick,
      const Offset(52, 146),
      const Offset(148, 146),
      24,
      0xFF8A9BB0,
      0xFFDFE6EE,
    ),
    legs: _Legs(_LegType.wheel, const Offset(64, 177), const Offset(136, 177)),
  ),

  // 6. Bibit
  MascotKind.bibit: _Design(
    body: [
      _el(100, 140, 44, 44, 0xFFC4E46A, 4),
      _el(82, 120, 12, 7, 0xFFE4F6AC),
    ],
    bodyPivot: const Offset(100, 184),
    head: [
      _ln('M100,98 Q98,80 100,62', 0xFF2A2118, 10),
      _ln('M100,98 Q98,80 100,62', 0xFF3FA33A, 5),
      _p('M100,66 Q76,40 52,52 Q72,76 100,66Z', 0xFF6CC644, 4),
      _p('M100,62 Q120,24 152,32 Q142,68 100,62Z', 0xFF5FBF3A, 4),
      _ln('M98,64 Q80,54 64,54 M102,60 Q122,46 142,38', 0xFF3FA33A, 2.5),
    ],
    headPivot: const Offset(100, 176),
    eyeL: const Offset(84, 130),
    eyeR: const Offset(116, 130),
    eyeScale: .9,
    mouth: const Offset(100, 152),
    mouthScale: .8,
    blushL: const Offset(72, 144),
    blushR: const Offset(128, 144),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(58, 146),
      const Offset(142, 146),
      20,
      0xFFB4D655,
      0xFFB4D655,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(86, 184),
      const Offset(114, 184),
      0xFF9CBF44,
    ),
  ),

  // 7. Koin
  MascotKind.koin: _Design(
    body: [
      _ci(104, 116, 62, 0xFFE0A00C, 4),
      _ci(100, 112, 62, 0xFFFFC531, 4),
      _ring(100, 112, 50, 0xFFE8A90F, 5),
      _ln('M62,86 Q72,62 96,56', 0xFFFFF3C4, 7),
      _tx('Rp', 100, 164, 15, 0xFFC98A00),
    ],
    bodyPivot: const Offset(100, 176),
    headPivot: const Offset(100, 170),
    eyeL: const Offset(82, 102),
    eyeR: const Offset(118, 102),
    eyeScale: 1,
    mouth: const Offset(100, 130),
    mouthScale: 1,
    blushL: const Offset(66, 118),
    blushR: const Offset(134, 118),
    arm: _Arm(
      _ArmType.stick,
      const Offset(40, 122),
      const Offset(160, 122),
      26,
      0xFF2A2118,
      0xFFFFFFFF,
    ),
    legs: _Legs(
      _LegType.stick,
      const Offset(86, 182),
      const Offset(114, 182),
      0xFFE8433A,
    ),
  ),

  // 8. Burung Hantu
  MascotKind.hantu: _Design(
    body: [
      _el(100, 130, 54, 56, 0xFF8A6CF0, 4),
      _el(100, 152, 32, 28, 0xFFECE4FF),
      _ln(
        'M88,144 l4,4 l4,-4 M104,144 l4,4 l4,-4 M96,158 l4,4 l4,-4',
        0xFFB6A3F5,
        3,
      ),
    ],
    bodyPivot: const Offset(100, 186),
    head: [
      _p('M58,92 L52,56 L82,78Z', 0xFF7556D8, 4),
      _p('M142,92 L148,56 L118,78Z', 0xFF7556D8, 4),
      _ci(80, 104, 21, 0xFFF6F2FF, 3),
      _ci(120, 104, 21, 0xFFF6F2FF, 3),
      _ring(80, 104, 24, 0xFFFFC531, 4),
      _ring(120, 104, 24, 0xFFFFC531, 4),
      _ln('M96,100 Q100,95 104,100', 0xFFFFC531, 4, cap: StrokeCap.butt),
    ],
    front: [_p('M93,118 L107,118 L100,129Z', 0xFFFF9F1C, 3)],
    headPivot: const Offset(100, 172),
    eyeL: const Offset(80, 104),
    eyeR: const Offset(120, 104),
    eyeScale: 1.05,
    mouth: const Offset(100, 137),
    mouthScale: .55,
    blushL: const Offset(60, 128),
    blushR: const Offset(140, 128),
    arm: _Arm(
      _ArmType.wing,
      const Offset(50, 132),
      const Offset(150, 132),
      32,
      0xFF7556D8,
    ),
    legs: _Legs(
      _LegType.claw,
      const Offset(86, 185),
      const Offset(114, 185),
      0xFFFF9F1C,
    ),
  ),

  // 9. Kura-kura
  MascotKind.kura: _Design(
    body: [
      _p('M38,162 Q38,98 100,96 Q162,98 162,162 Z', 0xFF3E9B4A, 4),
      _ln(
        'M100,100 L100,124 M70,112 L82,128 M130,112 L118,128 '
        'M82,128 L118,128 L124,150 L76,150 Z M48,148 L76,150 M152,148 L124,150',
        0xFF2F7D3A,
        4,
      ),
      _rr(32, 156, 136, 16, 8, 0xFFF0C46A, 4),
      _ci(140, 130, 9, 0xFFFFC531, 3),
    ],
    bodyPivot: const Offset(100, 172),
    head: [_el(100, 108, 34, 30, 0xFFA8D96F, 4), _el(88, 94, 8, 5, 0xFFC8EC98)],
    headPivot: const Offset(100, 140),
    eyeL: const Offset(86, 104),
    eyeR: const Offset(114, 104),
    eyeScale: .8,
    mouth: const Offset(100, 122),
    mouthScale: .65,
    blushL: const Offset(75, 117),
    blushR: const Offset(125, 117),
    arm: _Arm(
      _ArmType.wing,
      const Offset(42, 150),
      const Offset(158, 150),
      20,
      0xFFA8D96F,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(70, 182),
      const Offset(130, 182),
      0xFFA8D96F,
    ),
  ),

  // 10. Dompet
  MascotKind.dompet: _Design(
    back: [
      _rot(-12, 112, 78, [
        _rr(80, 60, 64, 34, 4, 0xFF7CCF6A, 3),
        _ring(112, 77, 9, 0xFF3F8F30, 3),
      ]),
      _rot(8, 78, 81, [_rr(56, 66, 44, 30, 4, 0xFFFF5F8A, 3)]),
    ],
    body: [
      _rr(44, 82, 112, 96, 16, 0xFF8B5A3C, 4),
      () {
        final dashed = _dashed(_rrPath(52, 90, 96, 80, 11), 6, 5);
        final s = _strokeP(2.5, const Color(0xFFD9B38C), StrokeCap.butt);
        return (Canvas c) => c.drawPath(dashed, s);
      }(),
    ],
    bodyPivot: const Offset(100, 178),
    head: [
      _p(
        'M44,100 Q44,82 62,82 H138 Q156,82 156,100 V114 Q156,124 146,124 '
        'H112 L100,134 L88,124 H54 Q44,124 44,114 Z',
        0xFFA46C48,
        4,
      ),
      _ci(100, 128, 7, 0xFFFFC531, 3),
    ],
    headPivot: const Offset(100, 178),
    eyeL: const Offset(78, 148),
    eyeR: const Offset(122, 148),
    eyeScale: .85,
    mouth: const Offset(100, 164),
    mouthScale: .7,
    blushL: const Offset(62, 160),
    blushR: const Offset(138, 160),
    arm: _Arm(
      _ArmType.stick,
      const Offset(44, 136),
      const Offset(156, 136),
      24,
      0xFF2A2118,
      0xFFFFFFFF,
    ),
    legs: _Legs(
      _LegType.stick,
      const Offset(82, 186),
      const Offset(118, 186),
      0xFF3B82F6,
    ),
  ),

  // 11. Beluga
  MascotKind.beluga: _Design(
    body: [
      _el(100, 138, 58, 46, 0xFFE9F1F6, 4),
      _el(100, 156, 36, 20, 0xFFF7FBFD),
      _ln('M62,150 q5,-3 9,0 M130,152 q5,-3 9,0', 0xFFC9D8E2, 3),
    ],
    bodyPivot: const Offset(100, 184),
    head: [
      _el(100, 98, 52, 44, 0xFFF2F7FA, 4),
      _el(84, 74, 20, 11, 0xFFFFFFFF),
      _el(128, 70, 7, 4, 0xFFFFFFFF),
      _ln('M92,52 q8,-6 16,0', 0xFFC9D8E2, 3),
    ],
    headPivot: const Offset(100, 172),
    eyeL: const Offset(80, 112),
    eyeR: const Offset(120, 112),
    eyeScale: .8,
    mouth: const Offset(100, 134),
    mouthScale: .95,
    blushL: const Offset(64, 126),
    blushR: const Offset(136, 126),
    arm: _Arm(
      _ArmType.wing,
      const Offset(46, 136),
      const Offset(154, 136),
      26,
      0xFFD6E4EC,
    ),
    legs: _Legs(
      _LegType.fin,
      const Offset(84, 184),
      const Offset(116, 184),
      0xFFD6E4EC,
    ),
  ),

  // 12. Hiu Paus
  MascotKind.hiuPaus: _Design(
    back: [_p('M84,98 Q96,50 126,56 Q114,78 118,100 Z', 0xFF35516C, 4)],
    body: [
      _el(100, 136, 62, 48, 0xFF4A6B8A, 4),
      _el(100, 158, 42, 22, 0xFFEEF4F8),
      for (final (x, y, r) in const [
        (64.0, 122.0, 3.5),
        (76.0, 108.0, 3.0),
        (136.0, 122.0, 3.5),
        (124.0, 108.0, 3.0),
        (56.0, 140.0, 3.0),
        (144.0, 140.0, 3.0),
        (70.0, 150.0, 2.5),
        (130.0, 150.0, 2.5),
        (92.0, 100.0, 2.5),
        (108.0, 100.0, 2.5),
      ])
        _ci(x, y, r, 0xFFE6EEF5),
      _ln(
        'M50,128 Q54,112 64,102 M150,128 Q146,112 136,102',
        0xFFE6EEF5,
        2.5,
        dash: (2, 6),
      ),
    ],
    bodyPivot: const Offset(100, 184),
    head: [_ln('M62,110 Q100,88 138,110', 0xFF6F8FAA, 3)],
    headPivot: const Offset(100, 172),
    eyeL: const Offset(70, 120),
    eyeR: const Offset(130, 120),
    eyeScale: .72,
    mouth: const Offset(100, 140),
    mouthScale: 1.35,
    blushL: const Offset(60, 134),
    blushR: const Offset(140, 134),
    arm: _Arm(
      _ArmType.wing,
      const Offset(42, 140),
      const Offset(158, 140),
      26,
      0xFF35516C,
    ),
    legs: _Legs(
      _LegType.fin,
      const Offset(82, 184),
      const Offset(118, 184),
      0xFF35516C,
    ),
  ),

  // 13. Komodo
  MascotKind.komodo: _Design(
    back: [_ln(_tailKomodo, 0xFF2A2118, 20), _ln(_tailKomodo, 0xFF7D8F4A, 12)],
    body: [
      _el(100, 150, 48, 34, 0xFF7D8F4A, 4),
      _el(100, 160, 28, 18, 0xFFC9C58A),
      _ln(
        'M66,140 l5,-4 l5,4 M124,140 l5,-4 l5,4 M80,128 l5,-4 l5,4 '
        'M110,128 l5,-4 l5,4',
        0xFF5F6F36,
        2.5,
      ),
    ],
    bodyPivot: const Offset(100, 184),
    head: [
      _el(100, 96, 54, 38, 0xFF8A9C52, 4),
      _ln(
        'M66,72 l6,-6 l6,6 M94,62 l6,-6 l6,6 M122,72 l6,-6 l6,6',
        0xFF5F6F36,
        3,
      ),
      _el(100, 114, 34, 14, 0xFFA3B46A),
      _ci(92, 106, 2.2, 0xFF2A2118),
      _ci(108, 106, 2.2, 0xFF2A2118),
    ],
    front: [
      _ln(
        'M100,127 L100,134 M100,134 L96.5,138 M100,134 L103.5,138',
        0xFFE8433A,
        2.4,
      ),
    ],
    headPivot: const Offset(100, 134),
    eyeL: const Offset(76, 86),
    eyeR: const Offset(124, 86),
    eyeScale: .85,
    mouth: const Offset(100, 120),
    mouthScale: .75,
    blushL: const Offset(62, 102),
    blushR: const Offset(138, 102),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(58, 146),
      const Offset(142, 146),
      22,
      0xFF7D8F4A,
      0xFF6E7F40,
    ),
    legs: _Legs(
      _LegType.claw,
      const Offset(84, 184),
      const Offset(116, 184),
      0xFF6E7F40,
    ),
  ),

  // 14. Orangutan
  MascotKind.orangutan: _Design(
    body: [
      _el(100, 150, 44, 36, 0xFFD9772B, 4),
      _el(100, 158, 26, 22, 0xFFF0A868),
    ],
    bodyPivot: const Offset(100, 186),
    head: [
      _p('M74,60 Q78,40 90,52 Q96,34 106,50 Q118,38 124,58', 0xFFC4621D, 4),
      _el(100, 90, 48, 40, 0xFFD9772B, 4),
      _el(100, 100, 44, 28, 0xFFE8B07A, 3),
      _el(100, 104, 28, 22, 0xFFF5D2A8),
      _el(94, 112, 2, 2.6, 0xFF2A2118),
      _el(106, 112, 2, 2.6, 0xFF2A2118),
    ],
    headPivot: const Offset(100, 136),
    eyeL: const Offset(86, 96),
    eyeR: const Offset(114, 96),
    eyeScale: .75,
    mouth: const Offset(100, 122),
    mouthScale: .8,
    blushL: const Offset(66, 108),
    blushR: const Offset(134, 108),
    arm: _Arm(
      _ArmType.capsule,
      const Offset(62, 140),
      const Offset(138, 140),
      40,
      0xFFD9772B,
      0xFFB5571A,
    ),
    legs: _Legs(
      _LegType.foot,
      const Offset(84, 184),
      const Offset(116, 184),
      0xFFB5571A,
    ),
  ),

  // 15. Cendrawasih
  MascotKind.cendrawasih: _Design(
    flareBack: true,
    back: [
      _p('M84,134 Q34,132 18,84 Q52,112 88,124 Z', 0xFFFFC531, 4),
      _p('M116,134 Q166,132 182,84 Q148,112 112,124 Z', 0xFFFFC531, 4),
      _p('M86,146 Q42,166 24,134 Q56,144 88,138 Z', 0xFFE8433A, 4),
      _p('M114,146 Q158,166 176,134 Q144,144 112,138 Z', 0xFFE8433A, 4),
      _ln('M94,176 Q80,198 62,192 Q54,184 64,180', 0xFF2A2118, 2.5),
      _ln('M106,176 Q120,198 138,192 Q146,184 136,180', 0xFF2A2118, 2.5),
    ],
    body: [
      _el(100, 142, 40, 40, 0xFF6B3A1E, 4),
      _p(
        'M78,126 Q100,116 122,126 Q118,146 100,150 Q82,146 78,126 Z',
        0xFF2BB3A3,
      ),
    ],
    bodyPivot: const Offset(100, 182),
    head: [
      _ci(100, 92, 34, 0xFFFFD43B, 4),
      _el(88, 76, 9, 5, 0xFFFFF1A8),
      _p(
        'M76,110 Q100,124 124,110 Q118,122 100,124 Q82,122 76,110 Z',
        0xFF2F8A4A,
      ),
    ],
    front: [_p('M93,100 L107,100 L100,111 Z', 0xFF8FA3B8, 3)],
    headPivot: const Offset(100, 170),
    eyeL: const Offset(86, 88),
    eyeR: const Offset(114, 88),
    eyeScale: .72,
    mouth: const Offset(100, 118),
    mouthScale: .5,
    blushL: const Offset(72, 100),
    blushR: const Offset(128, 100),
    arm: _Arm(
      _ArmType.wing,
      const Offset(62, 138),
      const Offset(138, 138),
      28,
      0xFF7A4424,
    ),
    legs: _Legs(
      _LegType.claw,
      const Offset(88, 184),
      const Offset(112, 184),
      0xFF8FA3B8,
    ),
  ),
};
