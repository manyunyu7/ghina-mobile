import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pixel-art office character (12x16 grid), a port of the web `sprite()`.
/// [look] is a role-like map: color, hair, skin, hairStyle, outfit, acc,
/// hijab, tie. Pass `{}` or null-ish fields for a plain guest.
class KantorSprite extends StatelessWidget {
  const KantorSprite({super.key, required this.look, this.size = 48});

  final Map<String, dynamic> look;

  /// Height in logical pixels; width is 3/4 of it.
  final double size;

  /// A stable look for sessions that are not bound to a role.
  static Map<String, dynamic> guestLook(String key) {
    final h = _hashStr(key);
    final st = _guestStyles[(h >> 5) % _guestStyles.length];
    return {
      'color': '#9AA3AF',
      'hair': _hairs[h % _hairs.length],
      'skin': _skins[(h >> 3) % _skins.length],
      'hairStyle': st,
      'outfit':
          const ['long', 'bun', 'ponytail', 'bob'].contains(st) && h % 2 == 1
          ? 'rok'
          : 'kemeja',
    };
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 0.75,
    height: size,
    child: CustomPaint(painter: _SpritePainter(look)),
  );
}

const _skins = ['#F1C9A5', '#D9A47C', '#B97E57', '#8D5A3B', '#E8B98F'];
const _hairs = [
  '#2B1D14',
  '#5A3A22',
  '#1E1E24',
  '#7A4B2A',
  '#C9A15A',
  '#3D2B4F',
];
const _guestStyles = [
  'short',
  'long',
  'short',
  'ponytail',
  'bob',
  'short',
  'curly',
  'bun',
];
const _femStyles = ['long', 'bun', 'ponytail', 'bob', 'pigtails', 'hijab'];

int _hashStr(String s) {
  var a = 7;
  for (final c in s.codeUnits) {
    a = (a * 31 + c) & 0xFFFFFFFF;
  }
  return a;
}

int _hex(String? hex, [int fallback = 0x9AA3AF]) {
  if (hex == null || hex.length < 7 || !hex.startsWith('#')) return fallback;
  return int.tryParse(hex.substring(1, 7), radix: 16) ?? fallback;
}

Color _c(int rgb) => Color(0xFF000000 | rgb);

int _shade(int rgb, double f) {
  int ch(int s) => math.max(0, math.min(255, (((rgb >> s) & 255) * f).round()));
  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.look);
  final Map<String, dynamic> look;

  static const _w = 12, _h = 16;

  String _s(String k, String d) {
    final v = look[k];
    return v is String && v.isNotEmpty ? v : d;
  }

  List<List<int?>> _cells() {
    final g = List.generate(_h, (_) => List<int?>.filled(_w, null));
    void p(int x, int y, int w, int h, int? c) {
      for (var j = y; j < y + h; j++) {
        for (var i = x; i < x + w; i++) {
          if (j >= 0 && j < _h && i >= 0 && i < _w) g[j][i] = c;
        }
      }
    }

    final st = _s('hairStyle', 'short');
    final of = _s('outfit', 'kemeja');
    final acc = _s('acc', '');
    final hair = _hex(look['hair'] as String?, 0x2B1D14);
    final skin = _hex(look['skin'] as String?, 0xF1C9A5);
    final col = _hex(look['color'] as String?);
    final dk = _shade(col, .7);
    final hj = _hex(look['hijab'] as String?, 0xE8EEF8);
    final fem = _femStyles.contains(st) || of == 'rok' || of == 'dress';
    final hijab = st == 'hijab';
    final tieOn = look['tie'] == true;
    const eye = 0x1B1B22,
        white = 0xF4F4F4,
        tie = 0xC2413A,
        gold = 0xF5C84C,
        shoe = 0x15181E;
    final hl = _shade(hair, 1.45), accent = _shade(col, 1.25);

    // behind the body
    if (st == 'long') {
      p(1, 3, 10, 9, hair);
      p(0, 5, 12, 6, hair);
      p(1, 11, 10, 1, hair);
    } else if (st == 'bob') {
      p(1, 3, 10, 5, hair);
      p(2, 8, 1, 1, hair);
      p(9, 8, 1, 1, hair);
    } else if (st == 'curly') {
      p(3, 0, 6, 1, hair);
      p(1, 1, 10, 1, hair);
      p(0, 2, 12, 6, hair);
      p(1, 8, 1, 1, hair);
      p(10, 8, 1, 1, hair);
      p(2, 1, 1, 1, hl);
      p(6, 0, 1, 1, hl);
      p(9, 2, 1, 1, hl);
      p(1, 5, 1, 1, hl);
      p(10, 6, 1, 1, hl);
    } else if (st == 'ponytail') {
      p(9, 2, 3, 2, hair);
      p(10, 4, 2, 5, hair);
      p(10, 9, 1, 1, hair);
      p(9, 3, 3, 1, accent);
    } else if (st == 'pigtails') {
      p(0, 5, 2, 5, hair);
      p(10, 5, 2, 5, hair);
      p(0, 10, 1, 1, hair);
      p(11, 10, 1, 1, hair);
      p(0, 4, 2, 1, accent);
      p(10, 4, 2, 1, accent);
    }
    // legs
    if (of == 'dress') {
      p(3, 15, 2, 1, shoe);
      p(7, 15, 2, 1, shoe);
    } else if (of == 'rok') {
      p(3, 14, 2, 1, skin);
      p(7, 14, 2, 1, skin);
      p(2, 15, 3, 1, shoe);
      p(7, 15, 3, 1, shoe);
    } else {
      final pc = of == 'hoodie' ? 0x3B4F78 : 0x2B3242;
      p(3, 13, 6, 1, pc);
      p(3, 14, 2, 1, pc);
      p(7, 14, 2, 1, pc);
      p(2, 15, 3, 1, shoe);
      p(7, 15, 3, 1, shoe);
    }
    // torso + arms
    p(3, 9, 6, 4, col);
    p(2, 9, 1, 2, col);
    p(9, 9, 1, 2, col);
    p(2, 11, 1, 1, skin);
    p(9, 11, 1, 1, skin);
    if (of == 'kemeja') {
      if (tieOn) {
        p(4, 9, 4, 1, white);
        p(5, 10, 2, 3, tie);
      } else {
        p(5, 9, 2, 1, skin);
      }
    } else if (of == 'jas') {
      p(5, 9, 2, 3, white);
      p(4, 9, 1, 3, dk);
      p(7, 9, 1, 3, dk);
      if (tieOn) p(5, 10, 2, 2, tie);
      p(3, 12, 6, 1, dk);
      p(2, 11, 1, 1, white);
      p(9, 11, 1, 1, white);
      p(2, 10, 1, 1, col);
    } else if (of == 'hoodie') {
      p(3, 9, 6, 1, dk);
      p(2, 9, 1, 1, dk);
      p(9, 9, 1, 1, dk);
      p(5, 10, 1, 2, white);
      p(6, 10, 1, 2, white);
      p(4, 12, 4, 1, dk);
      p(2, 10, 1, 1, dk);
      p(9, 10, 1, 1, dk);
    } else if (of == 'rok') {
      p(5, 9, 2, 1, skin);
      p(3, 12, 6, 1, _shade(col, .55));
      p(2, 13, 8, 1, _shade(col, .55));
    } else if (of == 'dress') {
      p(5, 9, 2, 1, skin);
      p(3, 12, 6, 1, dk);
      p(2, 13, 8, 1, col);
      p(1, 14, 10, 1, col);
      p(2, 14, 8, 1, col);
      p(3, 13, 1, 1, accent);
      p(6, 14, 1, 1, accent);
      p(9, 13, 1, 1, accent);
    }
    // head
    p(2, 3, 8, 6, skin);
    p(2, 8, 1, 1, null);
    p(9, 8, 1, 1, null);
    p(4, 5, 1, 2, eye);
    p(7, 5, 1, 2, eye);
    if (fem) {
      p(3, 5, 1, 1, eye);
      p(8, 5, 1, 1, eye);
      p(3, 7, 1, 1, 0xF29C9C);
      p(8, 7, 1, 1, 0xF29C9C);
      p(5, 8, 2, 1, 0xD46A6A);
    } else {
      p(5, 8, 2, 1, _shade(skin, .78));
    }
    // in front: hair or scarf
    void cap() {
      p(3, 1, 6, 1, hair);
      p(2, 2, 8, 1, hair);
    }

    void bang() {
      p(2, 3, 3, 1, hair);
      p(7, 3, 3, 1, hair);
    }

    if (hijab) {
      p(3, 1, 6, 1, hj);
      p(2, 2, 8, 2, hj);
      p(2, 4, 1, 4, hj);
      p(9, 4, 1, 4, hj);
      p(2, 8, 2, 1, hj);
      p(8, 8, 2, 1, hj);
      p(2, 3, 8, 1, _shade(hj, .88));
      p(3, 4, 1, 1, _shade(hj, .9));
      p(8, 4, 1, 1, _shade(hj, .9));
      p(2, 9, 8, 1, hj);
      p(3, 10, 6, 1, hj);
      p(4, 11, 4, 1, hj);
      p(2, 9, 1, 1, _shade(hj, .85));
      p(9, 9, 1, 1, _shade(hj, .85));
      p(5, 11, 2, 1, _shade(hj, .88));
    } else if (st == 'short') {
      cap();
      bang();
      p(2, 4, 1, 1, hair);
      p(9, 4, 1, 1, hair);
    } else if (st == 'long') {
      cap();
      p(2, 3, 5, 1, hair);
      p(2, 4, 1, 4, hair);
      p(9, 3, 1, 5, hair);
      p(3, 1, 2, 1, hl);
      p(3, 9, 1, 3, hair);
      p(8, 9, 1, 3, hair);
    } else if (st == 'bob') {
      cap();
      p(2, 3, 8, 1, hair);
      p(2, 4, 1, 4, hair);
      p(9, 4, 1, 4, hair);
      p(4, 2, 2, 1, hl);
    } else if (st == 'curly') {
      p(2, 3, 2, 1, hair);
      p(5, 3, 2, 1, hair);
      p(8, 3, 2, 1, hair);
      p(2, 4, 1, 2, hair);
      p(9, 4, 1, 2, hair);
    } else if (st == 'ponytail') {
      cap();
      p(2, 3, 5, 1, hair);
      p(2, 4, 1, 2, hair);
      p(9, 4, 1, 1, hair);
      p(4, 1, 2, 1, hl);
    } else if (st == 'pigtails') {
      cap();
      p(2, 3, 8, 1, hair);
      p(2, 4, 1, 2, hair);
      p(9, 4, 1, 2, hair);
      p(4, 2, 2, 1, hl);
    } else if (st == 'bun') {
      p(4, 0, 4, 2, hair);
      p(5, 0, 1, 1, hl);
      p(2, 2, 8, 1, hair);
      bang();
      p(2, 4, 1, 1, hair);
      p(9, 4, 1, 1, hair);
    }
    // accessories
    if (acc == 'topi' && !hijab) {
      p(3, 1, 6, 1, col);
      p(2, 2, 8, 1, col);
      p(1, 3, 10, 1, dk);
      p(5, 1, 2, 1, accent);
    }
    if (acc == 'anting') {
      p(2, 8, 1, 1, gold);
      p(9, 8, 1, 1, gold);
    }
    if (acc == 'kacamata') {
      const fr = 0xD9A21B;
      p(3, 4, 6, 1, fr);
      p(3, 5, 1, 2, fr);
      p(8, 5, 1, 2, fr);
      p(5, 5, 2, 1, fr);
      p(2, 5, 1, 1, fr);
      p(9, 5, 1, 1, fr);
      p(4, 7, 1, 1, fr);
      p(7, 7, 1, 1, fr);
    }
    return g;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / _w, size.height / _h);
    final g = _cells();
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final c = g[y][x];
        if (c == null) continue;
        paint.color = _c(c);
        // overdraw by a hair to avoid seams between cells
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + .5, cell + .5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) => !_same(old.look, look);

  static bool _same(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
