// Pixel-art toolkit for the native office floor: a rect/disc/line painter that
// mirrors the web renderer's `R/disc/line`, outlined sprite baking, the
// character sprite, floors and walls. Everything is drawn once into small
// images and reused every frame.
// ignore_for_file: prefer_single_quotes

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;

/// World tile edge in px, and wall height in tiles (same as the web renderer).
const double kTile = 8;
const int kWallRows = 4;

const kOut = '#1C1825';
const kOl = '#2A2430';

final _colors = <String, Color>{};

/// '#RRGGBB', '#RRGGBBAA' (CSS order) and 'rgba(r,g,b,a)'.
Color hex(String s) => _colors.putIfAbsent(s, () {
  if (s.startsWith('rgba')) {
    final p = s.substring(s.indexOf('(') + 1, s.indexOf(')')).split(',');
    final a = double.parse(p[3].trim());
    return Color.fromARGB(
      (a * 255).round(),
      int.parse(p[0].trim()),
      int.parse(p[1].trim()),
      int.parse(p[2].trim()),
    );
  }
  final h = s.length >= 7 ? s.substring(1, 7) : 'ff00ff';
  final rgb = int.tryParse(h, radix: 16) ?? 0xff00ff;
  final a = s.length >= 9 ? int.parse(s.substring(7, 9), radix: 16) : 255;
  return Color((a << 24) | rgb);
});

/// Multiplies a '#RRGGBB' colour's channels by [k] (the web `shd`).
String shade(String h, double k) {
  final n =
      int.tryParse(h.length >= 7 ? h.substring(1, 7) : '0', radix: 16) ?? 0;
  String ch(int s) => ((((n >> s) & 255) * k).round().clamp(
    0,
    255,
  )).toRadixString(16).padLeft(2, '0');
  return '#${ch(16)}${ch(8)}${ch(0)}';
}

/// Integer-pixel painter over a [ui.Canvas]; accepts hex strings or [Color].
class Px {
  Px(this.c);
  final ui.Canvas c;
  final ui.Paint _p = ui.Paint()..isAntiAlias = false;

  void r(num x, num y, num w, num h, Object col) {
    _p.color = col is Color ? col : hex(col as String);
    c.drawRect(
      ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      _p,
    );
  }

  void disc(int cx, int cy, int rad, Object col) {
    for (var dy = -rad; dy <= rad; dy++) {
      final w = (math.sqrt(rad * rad - dy * dy) + .4).floor();
      r(cx - w, cy + dy, 2 * w + 1, 1, col);
    }
  }

  void line(num x0n, num y0n, num x1n, num y1n, Object col) {
    var x0 = x0n.toInt(), y0 = y0n.toInt();
    final x1 = x1n.toInt(), y1 = y1n.toInt();
    final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var e = dx + dy;
    for (var i = 0; i < 400; i++) {
      r(x0, y0, 1, 1, col);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * e;
      if (e2 >= dy) {
        e += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        e += dx;
        y0 += sy;
      }
    }
  }
}

/// Renders [fn] into an image of [w]x[h] logical px (nearest-neighbour use).
ui.Image bake(int w, int h, void Function(Px p) fn) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  fn(Px(c));
  final pic = rec.endRecording();
  final img = pic.toImageSync(w, h);
  pic.dispose();
  return img;
}

/// Same as [bake] but every opaque pixel painted in [col] (for outlines).
ui.Picture _record(int w, int h, void Function(Px p) fn) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  fn(Px(c));
  return rec.endRecording();
}

/// A baked, outlined sprite. [img] is 2px larger than the art on each axis.
class Sprite {
  const Sprite(this.img, [this.k]);
  final ui.Image img;

  /// Cache key the sprite was built with ('counter', 'water'...): tells the Magang what an item is.
  final String? k;
  int get w => img.width;
  int get h => img.height;
}

final _sprites = <String, Sprite>{};

/// Draws [fn] four times shifted by one pixel in the outline colour (silhouette
/// via a src-in layer), then the art itself, like the web `outlined()`.
Sprite sprite(String key, int w, int h, void Function(Px p) fn) =>
    _sprites.putIfAbsent(key, () {
      final art = _record(w, h, fn);
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w + 2.0, h + 2.0));
      final sil = ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(hex(kOl), ui.BlendMode.srcIn)
        ..isAntiAlias = false;
      for (final o in const [
        [0, 1],
        [2, 1],
        [1, 0],
        [1, 2],
      ]) {
        c.saveLayer(null, sil);
        c.translate(o[0].toDouble(), o[1].toDouble());
        c.drawPicture(art);
        c.restore();
      }
      c.translate(1, 1);
      c.drawPicture(art);
      final pic = rec.endRecording();
      final img = pic.toImageSync(w + 2, h + 2);
      pic.dispose();
      art.dispose();
      return Sprite(img, key);
    });

// ---------------------------------------------------------------- looks

/// A character's look (a role map from the daemon, or a guest look).
class Look {
  const Look({
    required this.color,
    required this.hair,
    required this.skin,
    this.hairStyle = 'short',
    this.outfit = 'kemeja',
    this.acc = '',
    this.hijab = '#E8EEF8',
    this.tie = false,
    this.lanyard,
  });

  factory Look.fromRole(Map<String, dynamic> r) => Look(
    color: _s(r['color'], '#55606E'),
    hair: _s(r['hair'], '#2B1D14'),
    skin: _s(r['skin'], '#F1C9A5'),
    hairStyle: _s(r['hairStyle'], 'short'),
    outfit: _s(r['outfit'], 'kemeja'),
    acc: _s(r['acc'], ''),
    hijab: _s(r['hijab'], '#E8EEF8'),
    tie: r['tie'] == true,
    lanyard: r['lanyard'] is String ? r['lanyard'] as String : null,
  );

  /// A stable look for sessions that are not bound to a role.
  factory Look.guest(String key) {
    final h = hashStr(key);
    final st = _guestStyles[(h >> 5) % _guestStyles.length];
    final fem = const ['long', 'bun', 'ponytail', 'bob'].contains(st);
    return Look(
      color: '#9AA3AF',
      hair: _hairs[h % _hairs.length],
      skin: _skins[(h >> 3) % _skins.length],
      hairStyle: st,
      outfit: fem && h % 2 == 1 ? 'rok' : 'kemeja',
    );
  }

  static String _s(Object? v, String d) => v is String && v.isNotEmpty ? v : d;

  final String color, hair, skin, hairStyle, outfit, acc, hijab;
  final bool tie;

  /// Magang uniform: lanyard colour shown on every pose.
  final String? lanyard;

  Look withColor(String c) => Look(
    color: c,
    hair: hair,
    skin: skin,
    hairStyle: hairStyle,
    outfit: outfit,
    acc: acc,
    hijab: hijab,
    tie: tie,
    lanyard: lanyard,
  );

  String get key =>
      '$color$hair$skin$hairStyle$outfit$acc$hijab${tie ? 1 : 0}${lanyard ?? ''}';
}

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
const _skins = ['#F1C9A5', '#D9A47C', '#B97E57', '#8D5A3B', '#E8B98F'];
const _hairs = [
  '#2B1D14',
  '#5A3A22',
  '#1E1E24',
  '#7A4B2A',
  '#C9A15A',
  '#3D2B4F',
];

int hashStr(String s) {
  var a = 7;
  for (final u in s.runes) {
    a = (a * 31 + u) & 0xFFFFFFFF;
  }
  return a;
}

// --------------------------------------------------------------- person

/// Pose of a character sprite; the combination is the image cache key.
class PersonPose {
  const PersonPose({
    this.dir = 'down',
    this.walk = false,
    this.sit = false,
    this.typing = false,
    this.blink = false,
    this.small = false,
    this.phase = 0,
    this.cap,
    this.lanyard,
  });
  final String dir;
  final bool walk, sit, typing, blink, small;

  /// 0/1 animation phase (step or typing hands).
  final int phase;
  final String? cap, lanyard;

  String get key =>
      '$dir${walk ? 1 : 0}${sit ? 1 : 0}${typing ? 1 : 0}${blink ? 1 : 0}${small ? 1 : 0}$phase${cap ?? ''}${lanyard ?? ''}';
}

/// Person image: [kPersonW]x[kPersonH], feet at ([kPersonCx], [kPersonFeet]).
const int kPersonW = 32, kPersonH = 40, kPersonCx = 16, kPersonFeet = 34;
final _persons = <String, ui.Image>{};

ui.Image personImage(Look look, PersonPose o) =>
    _persons.putIfAbsent('${look.key}|${o.key}', () {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(
        rec,
        ui.Rect.fromLTWH(0, 0, kPersonW.toDouble(), kPersonH.toDouble()),
      );
      final p = Px(c);
      for (final d in const [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1],
      ]) {
        _personShape(p, kPersonCx + d[0], kPersonFeet + d[1], look, o, kOl);
      }
      _personShape(p, kPersonCx, kPersonFeet, look, o, null);
      final pic = rec.endRecording();
      final img = pic.toImageSync(kPersonW, kPersonH);
      pic.dispose();
      return img;
    });

void _personShape(Px p, int x, int y, Look l, PersonPose o, String? ol) {
  String f(String col) => ol ?? col;
  final bob = o.walk && o.phase == 1 ? 1 : 0;
  final legs = o.sit ? 0 : (o.small ? 3 : 4);
  final bodyH = o.small ? 5 : 6;
  final top = y - legs - bodyH - 10 - bob;
  final back = o.dir == 'up';
  final tb = top + 10;
  final st = l.hairStyle, of = l.outfit, acc = l.acc;
  final hij = st == 'hijab';
  final fem =
      hij ||
      const ['long', 'bun', 'ponytail', 'bob', 'pigtails'].contains(st) ||
      of == 'rok' ||
      of == 'dress';
  final hc = f(l.hair), sk = f(l.skin), hl = f(shade(l.hair, 1.45));
  final hj = f(l.hijab),
      acn = f(shade(l.color, 1.25)),
      dk = f(shade(l.color, .7));
  final white = f('#F4F4F4');
  final cap = o.cap ?? (acc == 'topi' && !hij ? l.color : null);
  final ox = o.dir == 'left'
      ? -1
      : o.dir == 'right'
      ? 1
      : 0;
  final nol = ol == null;

  void hairBack() {
    if (hij) return;
    if (st == 'long') {
      p.r(x - 6, top + 2, 12, 12, hc);
    } else if (st == 'bob') {
      p.r(x - 6, top + 2, 12, 9, hc);
    } else if (st == 'curly') {
      p.r(x - 7, top, 14, 8, hc);
      p.r(x - 6, top - 2, 12, 2, hc);
      p.r(x - 6, top + 8, 2, 1, hc);
      p.r(x + 4, top + 8, 2, 1, hc);
      if (nol) {
        p.r(x - 5, top - 1, 1, 1, hl);
        p.r(x + 1, top - 2, 1, 1, hl);
        p.r(x + 5, top + 1, 1, 1, hl);
        p.r(x - 7, top + 3, 1, 1, hl);
        p.r(x + 6, top + 5, 1, 1, hl);
      }
    } else if (st == 'ponytail') {
      p.r(x + 5, top + 2, 3, 3, hc);
      p.r(x + 6, top + 5, 2, 6, hc);
      if (nol) p.r(x + 5, top + 2, 3, 1, acn);
    } else if (st == 'pigtails') {
      p.r(x - 8, top + 3, 3, 8, hc);
      p.r(x + 5, top + 3, 3, 8, hc);
      if (nol) {
        p.r(x - 8, top + 3, 3, 1, acn);
        p.r(x + 5, top + 3, 3, 1, acn);
      }
    } else if (st == 'bun') {
      p.r(x - 3, top - 4, 6, 4, hc);
    }
  }

  void hairBackView() {
    if (hij) {
      p.r(x - 6, top - 1, 12, 12, hj);
      p.r(x - 6, tb - 1, 12, 4, hj);
      p.r(x - 5, tb + 3, 10, 1, hj);
      p.r(x - 3, tb + 4, 6, 1, hj);
      if (nol) p.r(x, top + 2, 1, 9, shade(l.hijab, .85));
      return;
    }
    hairBack();
    if (st == 'long') {
      p.r(x - 6, top + 2, 12, bodyH + 9, hc);
    } else if (st == 'bob') {
      p.r(x - 6, top, 12, 11, hc);
    }
    p.r(x - 5, top, 10, 8, hc);
    if (st == 'ponytail') {
      p.r(x - 2, top + 3, 4, 9, hc);
      if (nol) p.r(x - 2, top + 3, 4, 1, acn);
    }
    if (nol && st != 'short') p.r(x - 3, top + 1, 2, 1, hl);
  }

  final skirt = f(shade(l.color, .55));
  final skirted = of == 'rok' || of == 'dress';
  if (!back) hairBack();
  p.r(x - 5, top, 10, 10, sk);
  if (!back) {
    if (hij) {
      p.r(x - 6, top - 1, 12, 4, hj);
      p.r(x - 6, top + 3, 2, 8, hj);
      p.r(x + 4, top + 3, 2, 8, hj);
      p.r(x - 4, top + 9, 8, 2, hj);
      if (nol) {
        p.r(x - 6, top + 2, 12, 1, shade(l.hijab, .85));
        p.r(x - 4, top + 8, 8, 1, shade(l.skin, .85));
      }
    } else {
      p.r(x - 5, top, 10, 3, hc);
      if (st == 'long' || st == 'bob') {
        p.r(x - 5, top + 3, 2, 6, hc);
        p.r(x + 3, top + 3, 2, 6, hc);
        p.r(x - 5, top + 3, st == 'bob' ? 10 : 6, 1, hc);
      } else if (st == 'pigtails') {
        p.r(x - 5, top + 3, 10, 1, hc);
        p.r(x - 5, top + 4, 1, 2, hc);
        p.r(x + 4, top + 4, 1, 2, hc);
      } else if (st == 'ponytail') {
        p.r(x - 5, top + 3, 6, 1, hc);
        p.r(x - 5, top + 4, 1, 3, hc);
        p.r(x + 4, top + 4, 1, 1, hc);
      } else if (st == 'curly') {
        p.r(x - 5, top + 3, 3, 1, hc);
        p.r(x + 2, top + 3, 3, 1, hc);
        p.r(x - 5, top + 4, 1, 2, hc);
        p.r(x + 4, top + 4, 1, 2, hc);
      } else {
        p.r(x - 5, top + 3, 2, 3, hc);
        p.r(x + 3, top + 3, 2, 2, hc);
      }
      if (nol && st != 'short') p.r(x - 2, top + 1, 3, 1, hl);
    }
  }
  if (nol && !back) {
    const eye = '#1F1628';
    if (fem) {
      p.r(x - 4 + ox, top + 7, 1, 1, '#F29C9C');
      p.r(x + 3 + ox, top + 7, 1, 1, '#F29C9C');
    }
    if (!o.blink) {
      p.r(x - 3 + ox, top + 5, 2, 2, eye);
      p.r(x + 1 + ox, top + 5, 2, 2, eye);
      if (fem) {
        p.r(x - 4 + ox, top + 5, 1, 1, eye);
        p.r(x + 3 + ox, top + 5, 1, 1, eye);
      }
    } else {
      p.r(x - 3 + ox, top + 6, 2, 1, eye);
      p.r(x + 1 + ox, top + 6, 2, 1, eye);
    }
    if (fem) p.r(x - 1 + ox, top + 8, 2, 1, '#D46A6A');
  }
  // body
  final th = of == 'rok' ? bodyH - 2 : bodyH;
  p.r(x - 5, tb, 10, th, f(l.color));
  if (skirted) {
    p.r(
      x - 6,
      tb + th - (of == 'dress' ? 1 : 0),
      12,
      3,
      of == 'dress' ? f(l.color) : skirt,
    );
  }
  if (nol) {
    if (of == 'dress') {
      p.r(x - 5, tb + 2, 10, 1, dk);
      p.r(x - 6, tb + bodyH + 1, 12, 1, 'rgba(0,0,0,.18)');
      p.r(x - 3, tb + bodyH, 1, 1, acn);
      p.r(x + 2, tb + bodyH + 1, 1, 1, acn);
    } else if (of == 'rok') {
      p.r(x - 5, tb + th - 1, 10, 1, 'rgba(0,0,0,.25)');
    } else {
      p.r(x - 5, tb + bodyH - 1, 10, 1, 'rgba(0,0,0,.2)');
    }
    if (!back) {
      if (of == 'jas') {
        p.r(x - 2, tb, 4, 3, white);
        p.r(x - 3, tb, 1, 4, dk);
        p.r(x + 2, tb, 1, 4, dk);
        if (l.tie) p.r(x - 1, tb + 1, 2, bodyH - 1, '#C2413A');
      } else if (of == 'hoodie') {
        p.r(x - 4, tb, 8, 2, dk);
        p.r(x - 1, tb, 2, 1, sk);
        p.r(x - 2, tb + 2, 1, 2, white);
        p.r(x + 1, tb + 2, 1, 2, white);
        p.r(x - 3, tb + bodyH - 2, 6, 1, dk);
      } else {
        p.r(x - 1, tb, 2, 1, l.skin);
        if (l.tie && of == 'kemeja')
          p.r(x - 1, tb + 1, 2, bodyH - 1, '#C2413A');
      }
    } else if (of == 'hoodie') {
      p.r(x - 4, tb - 1, 8, 4, dk);
    } else if (of == 'jas') {
      p.r(x, tb + 2, 1, bodyH - 2, dk);
    }
  }
  final lan = o.lanyard ?? l.lanyard;
  if (lan != null && nol && !back) {
    p.r(x - 2, tb, 1, 2, lan);
    p.r(x + 1, tb, 1, 2, lan);
    p.r(x - 2, tb + 2, 4, 2, '#F4F4F4');
  }
  if (back) {
    hairBackView();
  } else if (st == 'long' && !hij) {
    p.r(x - 5, tb, 2, 5, hc);
    p.r(x + 3, tb, 2, 5, hc);
  }
  if (hij && !back) {
    p.r(x - 6, tb - 1, 12, 3, hj);
    p.r(x - 5, tb + 2, 10, 1, hj);
    p.r(x - 3, tb + 3, 6, 1, hj);
    if (nol) p.r(x, tb + 2, 1, 2, shade(l.hijab, .85));
  }
  if (cap != null) {
    p.r(x - 6, top - 1, 12, 4, f(cap));
    if (!back) p.r(x - 6, top + 3, 12, 1, f(shade(cap, .7)));
  }
  if (nol && acc == 'anting') {
    p.r(x - 6, top + 8, 1, 2, '#F5C84C');
    p.r(x + 5, top + 8, 1, 2, '#F5C84C');
  }
  if (nol && !back && acc == 'kacamata') {
    const fr = '#D9A21B';
    final gx = x + ox;
    p.r(gx - 4, top + 4, 8, 1, fr);
    p.r(gx - 4, top + 5, 1, 2, fr);
    p.r(gx + 3, top + 5, 1, 2, fr);
    p.r(gx - 1, top + 5, 2, 1, fr);
    p.r(gx - 4, top + 7, 3, 1, fr);
    p.r(gx + 1, top + 7, 3, 1, fr);
  }
  // arms
  final a = o.typing ? o.phase : 0;
  if (o.sit) {
    p.r(x - 7, tb + 1 - a, 2, 4, f(l.color));
    p.r(x + 5, tb + a, 2, 4, f(l.color));
    if (nol) {
      p.r(x - 7, tb + 4 - a, 2, 1, l.skin);
      p.r(x + 5, tb + 3 + a, 2, 1, l.skin);
    }
  } else {
    final ph = o.walk ? o.phase : -1;
    p.r(x - 7, tb + 1 + (ph == 0 ? 1 : 0), 2, 4, f(l.color));
    p.r(x + 5, tb + 1 + (ph == 1 ? 1 : 0), 2, 4, f(l.color));
    if (nol) {
      p.r(x - 7, tb + 5 + (ph == 0 ? 1 : 0), 2, 1, l.skin);
      p.r(x + 5, tb + 5 + (ph == 1 ? 1 : 0), 2, 1, l.skin);
    }
    final lb = tb + bodyH;
    final l1 = ph == 1 ? legs - 1 : legs, l2 = ph == 0 ? legs - 1 : legs;
    final lc = skirted ? sk : f(of == 'hoodie' ? '#3B4F78' : '#2B3242');
    p.r(x - 4, lb, 3, l1, lc);
    p.r(x + 1, lb, 3, l2, lc);
    p.r(x - 4, lb + l1 - 1, 3, 1, f('#15181E'));
    p.r(x + 1, lb + l2 - 1, 3, 1, f('#15181E'));
  }
}
