// Static layer of the floor: corridors, room floors, rugs, walls and wall
// decorations baked into one image, plus the per-desk base image.
// Ported from the web renderer's `buildBg()/drawFloor()/drawWalls()/drawWallDeco()`.
// ignore_for_file: prefer_single_quotes

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'floor_pixel.dart';
import 'floor_world.dart';

const _t = 8;
const _wh = kWallRows;

const _wall = '#EEEAE2';
const _wallHi = '#FBF9F4';
const _wallEdge = '#2A2430';
const _face = '#EAE6DD';
const _faceLow = '#DDD8CE';
const _trim = '#B9B2A6';
const _glass = 'rgba(170,205,225,.45)';
const _glassFrame = '#7F98A6';
const _corr = ['#9DB3A6', '#99AFA2', '#89A093'];
const _teal = ['#98AF9F', '#94AB9B', '#869E8E', '#7F9787'];

const _floors = <String, List<String>>{
  'teal': _teal,
  'teal2': ['#9AAFB0', '#96ABAC', '#879D9E', '#7E9496'],
  'carpetGreen': ['#A3B596', '#9FB192', '#90A383', '#889B7B'],
  'wood2': ['#B98F62', '#B08759', '#9A774D'],
  'marble': ['#E3DFD6', '#DCD8CF', '#CBC6BC'],
  'tile': ['#E6E8EA', '#DEE1E4', '#CACED2'],
  'metal': ['#5A616E', '#555B68', '#4A505C'],
  'plum': ['#9B8CAE', '#9687A9', '#887A9C', '#7E7092'],
  'frozen': ['#BFC1C6', '#B8BABF'],
  'musholla': ['#6FA07E', '#689878', '#5A8869', '#D9C27A'],
  'grass': ['#79B268', '#70A95F', '#5F984F', '#F4E58A'],
  'gymMat': ['#4C5667', '#454E5E', '#394251', '#E7EAF0'],
  'lounge': ['#C8A98E', '#C1A185', '#AE8A6E', '#EBD9C2'],
};

void _drawFloor(Px p, String kind, int x, int y, int w, int h, int seed) {
  final k = const {'wood': 'teal', 'carpet': 'teal'}[kind] ?? kind;
  final pal = _floors[k] ?? _teal;
  if (k == 'wood2') {
    for (var yy = 0; yy < h; yy += 6) {
      p.r(x, y + yy, w, math.min(6, h - yy), (yy ~/ 6).isOdd ? pal[0] : pal[1]);
      p.r(x, y + yy, w, 1, pal[2]);
      final off = ((yy ~/ 6) * 13 + seed) % 28;
      for (var xx = off; xx < w; xx += 28) {
        p.r(x + xx, y + yy, 1, math.min(6, h - yy), pal[2]);
      }
    }
    return;
  }
  if (k == 'musholla') {
    p.c.save();
    p.c.clipRect(
      ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
    );
    // green prayer carpet: 16px panels with a gold diamond and border
    p.r(x, y, w, h, pal[0]);
    for (var yy = 0; yy < h; yy += 16) {
      for (var xx = 0; xx < w; xx += 16) {
        if (((xx + yy) ~/ 16).isOdd) p.r(x + xx, y + yy, 16, 16, pal[1]);
        p.r(x + xx, y + yy, 16, 1, pal[2]);
        p.r(x + xx, y + yy, 1, 16, pal[2]);
        if (xx + 16 <= w && yy + 16 <= h) {
          p.r(x + xx + 7, y + yy + 4, 2, 8, pal[3]);
          p.r(x + xx + 4, y + yy + 7, 8, 2, pal[3]);
          p.r(x + xx + 6, y + yy + 6, 4, 4, pal[2]);
        }
      }
    }
    p.c.restore();
    return;
  }
  if (k == 'grass') {
    p.r(x, y, w, h, pal[0]);
    for (var i = 0; i < (w * h) ~/ 40; i++) {
      final gx = x + (_rng(seed, i * 3) * w).floor(),
          gy = y + (_rng(seed, i * 3 + 1) * h).floor();
      final r = _rng(seed, i * 3 + 2);
      if (r > .985) {
        p.r(gx, gy, 2, 2, pal[3]);
        p.r(gx, gy + 2, 1, 2, pal[2]);
      } else if (r > .5) {
        p.r(gx, gy, 1, 3, pal[1]);
        p.r(gx + 1, gy + 1, 1, 2, pal[2]);
      } else {
        p.r(gx, gy, 2, 1, pal[2]);
      }
    }
    return;
  }
  if (k == 'gymMat') {
    p.c.save();
    p.c.clipRect(
      ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
    );
    // rubber tiles with light seams
    p.r(x, y, w, h, pal[0]);
    for (var yy = 0; yy < h; yy += 16) {
      for (var xx = 0; xx < w; xx += 16) {
        if (((xx + yy) ~/ 16).isOdd) p.r(x + xx, y + yy, 16, 16, pal[1]);
        p.r(x + xx, y + yy, 16, 1, pal[2]);
        p.r(x + xx, y + yy, 1, 16, pal[2]);
        p.r(x + xx + 4, y + yy + 4, 1, 1, pal[3]);
      }
    }
    p.c.restore();
    return;
  }
  if (k == 'lounge') {
    // warm herringbone carpet
    p.r(x, y, w, h, pal[0]);
    for (var yy = 0; yy < h; yy += 8) {
      for (var xx = 0; xx < w; xx += 16) {
        final off = ((yy ~/ 8).isOdd ? 8 : 0);
        final bw = math.min(8, w - xx - off), bh = math.min(8, h - yy);
        if (bw <= 0) continue;
        p.r(x + xx + off, y + yy, bw, bh, pal[1]);
        p.r(x + xx + off, y + yy + bh - 1, bw, 1, pal[2]);
        if (bw == 8) p.r(x + xx + off + 7, y + yy, 1, bh, pal[2]);
        if ((xx + yy) % 48 == 0 && bw == 8 && bh == 8)
          p.r(x + xx + off + 3, y + yy + 3, 2, 2, pal[3]);
      }
    }
    return;
  }
  if (k == 'frozen') {
    p.r(x, y, w, h, pal[0]);
    for (var i = 0; i < w + h; i += 10) {
      p.line(
        x + math.max(0, i - h),
        y + math.min(h - 1, i),
        x + math.min(w - 1, i),
        y + math.max(0, i - w + 1),
        'rgba(255,255,255,.12)',
      );
    }
    return;
  }
  final s2 = k == 'tile' ? 8 : 16;
  p.r(x, y, w, h, pal[0]);
  for (var yy = 0; yy < h; yy += s2) {
    for (var xx = 0; xx < w; xx += s2) {
      if (((xx + yy) ~/ s2).isOdd) p.r(x + xx, y + yy, s2, s2, pal[1]);
      p.r(x + xx, y + yy, s2, 1, pal[2]);
      p.r(x + xx, y + yy, 1, s2, pal[2]);
      if (pal.length > 3 && s2 == 16) {
        p.r(x + xx - 1, y + yy, 3, 1, pal[3]);
        p.r(x + xx, y + yy - 1, 1, 3, pal[3]);
      }
    }
  }
}

Set<int> _doorCols(FloorRoom r, String side) => {
  for (final d in r.doors)
    if (d.side == side)
      for (var k = 0; k < d.w; k++) d.at + k,
};

void _drawWalls(Px p, FloorRoom r) {
  final x = r.x * _t, y = r.y * _t, w = r.w * _t, h = r.h * _t;
  final glass = r.glass;
  final tops = _doorCols(r, 't'),
      bots = _doorCols(r, 'b'),
      lefts = _doorCols(r, 'l'),
      rights = _doorCols(r, 'r');
  for (var k = 1; k < r.w - 1; k++) {
    final fx = x + k * _t;
    if (tops.contains(k)) {
      p.r(fx, y, _t, _wh * _t, _corr[0]);
      p.r(fx, y, _t, 1, _corr[2]);
      continue;
    }
    p.r(fx, y, _t, 5, _wallHi);
    p.r(fx, y + 5, _t, 1, _wallEdge);
    if (glass) {
      p.r(fx, y + 6, _t, _wh * _t - 6, _glass);
      p.r(fx, y + 6, 1, _wh * _t - 6, _glassFrame);
    } else {
      p.r(fx, y + 6, _t, _wh * _t - 9, _face);
      p.r(fx, y + _wh * _t - 8, _t, 5, _faceLow);
    }
    p.r(fx, y + _wh * _t - 3, _t, 2, _trim);
    p.r(fx, y + _wh * _t - 1, _t, 1, kOl);
  }
  for (final k in tops) {
    if (!tops.contains(k - 1)) p.r(x + k * _t - 2, y, 2, _wh * _t, _wallEdge);
    if (!tops.contains(k + 1)) p.r(x + (k + 1) * _t, y, 2, _wh * _t, _wallEdge);
  }
  void side(int sx, Set<int> set) {
    for (var k = 0; k < r.h; k++) {
      if (set.contains(k)) continue;
      p.r(sx, y + k * _t, _t, _t, glass && k >= _wh ? _glassFrame : _wall);
      p.r(sx + 1, y + k * _t, 2, _t, _wallHi);
      p.r(sx, y + k * _t, 1, _t, _wallEdge);
      p.r(sx + _t - 1, y + k * _t, 1, _t, _wallEdge);
    }
  }

  side(x, lefts);
  side(x + w - _t, rights);
  for (var k = 0; k < r.w; k++) {
    if (bots.contains(k)) continue;
    p.r(x + k * _t, y + h - _t, _t, _t, glass ? _glassFrame : _wall);
    p.r(x + k * _t, y + h - _t, _t, 2, _wallHi);
    p.r(x + k * _t, y + h - _t, _t, 1, _wallEdge);
    p.r(x + k * _t, y + h - 1, _t, 1, _wallEdge);
  }
  for (final k in bots) {
    if (!bots.contains(k - 1))
      p.r(x + k * _t - 1, y + h - _t, 1, _t, _wallEdge);
    if (!bots.contains(k + 1))
      p.r(x + (k + 1) * _t, y + h - _t, 1, _t, _wallEdge);
  }
  for (final k in lefts) {
    if (!lefts.contains(k - 1)) p.r(x, y + k * _t - 1, _t, 1, _wallEdge);
    if (!lefts.contains(k + 1)) p.r(x, y + (k + 1) * _t, _t, 1, _wallEdge);
  }
  for (final k in rights) {
    if (!rights.contains(k - 1))
      p.r(x + w - _t, y + k * _t - 1, _t, 1, _wallEdge);
    if (!rights.contains(k + 1))
      p.r(x + w - _t, y + (k + 1) * _t, _t, 1, _wallEdge);
  }
}

double _rng(int seed, int i) {
  var t = (seed * 2654435761 + i * 40503) & 0xFFFFFFFF;
  t = ((t ^ (t >> 15)) * 2246822519) & 0xFFFFFFFF;
  return ((t ^ (t >> 13)) & 0xFFFF) / 65536.0;
}

void _drawWallDeco(
  Px p,
  FloorDeco d,
  List<Map<String, dynamic>> roles,
  List<Map<String, dynamic>> cards,
) {
  final x = d.x.round(), y = d.y.round() + 4;
  final hr = DateTime.now().hour;
  final day = hr >= 6 && hr < 18;
  if (d.x + 30 > (d.room.x + d.room.w) * _t) return;
  switch (d.t) {
    case 'window':
      final sky = hr >= 6 && hr < 16
          ? '#8CC6EE'
          : hr >= 16 && hr < 18
          ? '#EFA867'
          : '#1A2342';
      p.r(x, y + 2, 34, 22, '#EDEDED');
      p.r(x + 2, y + 4, 30, 18, sky);
      if (day) {
        p.r(x + 22, y + 6, 4, 4, '#FFE58A');
        p.r(x + 5, y + 7, 7, 2, '#FFFFFF');
      } else {
        p.r(x + 23, y + 6, 3, 3, '#E8E8F0');
      }
      var i = 0;
      for (var bx = x + 2; bx < x + 32; bx += 5) {
        final bh = 5 + (_rng(x, i++) * 9).floor();
        p.r(bx, y + 22 - bh, 4, bh, day ? '#5C6B85' : '#0E1426');
        if (!day) {
          for (var k = 0; k < 3; k++) {
            if (_rng(x, i++) > .4)
              p.r(
                bx + 1 + (k % 2) * 2,
                y + 22 - bh + 2 + k * 2,
                1,
                1,
                '#F2CF72',
              );
          }
        }
      }
      p.r(x + 16, y + 2, 2, 22, '#EDEDED');
      p.r(x - 1, y + 24, 36, 2, '#C9C9C9');
    case 'poster':
      p.r(x, y + 1, 18, 22, '#C9A15A');
      p.r(x + 2, y + 3, 14, 18, '#2F5D9E');
      p.r(x + 2, y + 3, 14, 4, '#F2CF72');
      final top =
          roles.where((r) => r['isMgr'] == true).firstOrNull ??
          roles.firstOrNull;
      if (top != null) {
        final l = Look.fromRole(top);
        p.r(x + 5, y + 9, 8, 7, l.skin);
        p.r(x + 5, y + 9, 8, 2, l.hair);
        p.r(x + 7, y + 13, 1, 1, '#1B1B22');
        p.r(x + 10, y + 13, 1, 1, '#1B1B22');
        p.r(x + 4, y + 16, 10, 5, l.color);
      }
    case 'poster2':
      p.r(x, y + 3, 16, 20, '#FFFFFF');
      p.r(x + 1, y + 4, 14, 18, '#2C8452');
      p.r(x + 3, y + 7, 10, 2, '#F2CF72');
      p.r(x + 3, y + 11, 7, 1, '#FFFFFF');
      p.r(x + 3, y + 13, 9, 1, '#FFFFFF');
    case 'poster3':
      p.r(x, y + 3, 20, 16, '#1E1E24');
      p.r(x + 2, y + 5, 16, 12, '#C2413A');
      p.r(x + 4, y + 8, 12, 2, '#F2CF72');
      p.r(x + 4, y + 12, 3, 3, '#FFFFFF');
    case 'wb':
      final w = d.w == 0 ? 40 : d.w;
      p.r(x, y + 1, w, 22, '#9AA0A8');
      p.r(x + 1, y + 2, w - 2, 20, '#F7F7F2');
      p.r(x + 3, y + 23, w - 6, 1, '#7A808A');
      final list = d.repo != null
          ? cards.where((k) => k['repo'] == d.repo).toList()
          : cards;
      const cols = ['#F2CF72', '#9FD67F', '#7FD3C9', '#F49AC1', '#C8C8C8'];
      final cw = ((w - 4) / 5).floor();
      for (var k = 0; k < 5; k++) {
        p.r(x + 2 + k * cw + cw - 1, y + 3, 1, 18, '#DADAD2');
        final inCol = list.where((cd) => cd['col'] == k).take(4).toList();
        for (var i = 0; i < inCol.length; i++) {
          final blocked = '${inCol[i]['blocked'] ?? ''}'.isNotEmpty;
          p.r(
            x + 3 + k * cw + (i % 2) * 3,
            y + 4 + (i ~/ 2) * 4 + (i % 2),
            3,
            3,
            blocked ? '#E5655D' : cols[k],
          );
        }
      }
    case 'tv':
      p.r(x, y + 1, d.w, 22, '#14181F');
      p.r(x + 2, y + 3, d.w - 4, 18, '#1E2A38');
      for (var i = 0; i < 4; i++) {
        p.r(x + 5, y + 6 + i * 4, 6 + (i * 7) % 20, 2, '#2B3A4A');
      }
    case 'clock':
      p.disc(x + 7, y + 10, 7, '#2B303A');
      p.disc(x + 7, y + 10, 6, '#F7F7F2');
      final n = DateTime.now();
      final a = n.minute / 60 * math.pi * 2,
          b = ((n.hour % 12) / 12 + n.minute / 720) * math.pi * 2;
      p.line(
        x + 7,
        y + 10,
        x + 7 + (math.sin(a) * 5).round(),
        y + 10 - (math.cos(a) * 5).round(),
        '#2B303A',
      );
      p.line(
        x + 7,
        y + 10,
        x + 7 + (math.sin(b) * 3).round(),
        y + 10 - (math.cos(b) * 3).round(),
        '#C2413A',
      );
    case 'ci':
      p.r(x, y + 3, 30, 14, '#2C8452');
      p.r(x + 2, y + 5, 26, 10, '#3A9A62');
      p.r(x + 4, y + 7, 4, 4, '#FFFFFF');
      p.r(x + 10, y + 7, 15, 1, '#FFFFFF');
    case 'warn':
      p.r(x, y + 2, 24, 18, '#F2CF72');
      p.r(x + 1, y + 3, 22, 16, '#1E1E24');
      p.r(x + 2, y + 4, 20, 3, '#C2413A');
      p.r(x + 10, y + 9, 3, 6, '#F2CF72');
      p.r(x + 10, y + 16, 3, 2, '#F2CF72');
    case 'beku':
      p.r(x, y + 4, 56, 14, '#BFC3C9');
      for (var k = 0; k < 56; k += 8) {
        p.r(x + k, y + 8, 4, 6, '#F2CF72');
        p.r(x + k + 4, y + 8, 4, 6, '#1E1E24');
      }
    case 'menu':
      p.r(x, y + 2, 34, 20, '#2B2B2B');
      p.r(x + 2, y + 4, 30, 16, '#3A3A3A');
      for (var k = 0; k < 4; k++) {
        p.r(x + 4, y + 6 + k * 4, 12 + (k * 5) % 10, 1, '#E8E8E8');
      }
    case 'wc':
      p.r(x, y + 6, 22, 12, '#3E6BA8');
      p.r(x + 4, y + 9, 3, 6, '#FFFFFF');
      p.r(x + 15, y + 9, 3, 6, '#FFFFFF');
    case 'logo':
      p.r(x, y + 4, d.w, 14, '#1E2A38');
      p.r(x + 2, y + 6, d.w - 4, 10, '#A9620F');
      for (var k = 0; k < 7; k++) {
        p.r(x + 6 + k * 7, y + 8, 5, 6, '#F2CF72');
      }
    case 'plantWall':
      p.r(x, y + 4, 26, 18, '#4F8F5B');
      for (var k = 0; k < 26; k += 4) {
        p.r(x + k, y + 4 + (k % 3) * 2, 3, 3, '#6CB37A');
      }
    case 'vinyl':
      p.disc(x + 8, y + 10, 8, '#2A2430');
      p.disc(x + 8, y + 10, 7, '#14161C');
      p.disc(x + 8, y + 10, 5, '#22252D');
      p.disc(x + 8, y + 10, 3, d.col ?? '#C2413A');
      p.r(x + 8, y + 10, 1, 1, '#14161C');
    case 'gig':
      p.r(x, y + 1, 20, 24, '#F4F0E4');
      p.r(x + 1, y + 2, 18, 22, '#2A1F4A');
      p.r(x + 1, y + 2, 18, 4, '#F49AC1');
      p.disc(x + 8, y + 15, 3, '#F2CF72');
      p.r(x + 10, y + 7, 2, 9, '#F2CF72');
      p.r(x + 3, y + 20, 14, 1, '#7FD3C9');
    case 'neonNote':
      p.r(x, y + 2, 24, 20, '#1E1A2E');
      p.r(x, y + 2, 24, 1, '#3A3358');
      p.r(x + 4, y + 14, 5, 4, '#F49AC1');
      p.r(x + 8, y + 5, 2, 11, '#F49AC1');
      p.r(x + 10, y + 5, 5, 2, '#F49AC1');
      p.r(x + 15, y + 15, 4, 3, '#7FD3C9');
      p.r(x + 18, y + 8, 2, 8, '#7FD3C9');
    case 'eq':
      p.r(x, y + 3, 28, 18, '#14181F');
      p.r(x + 1, y + 4, 26, 16, '#1B2230');
      for (var i = 0; i < 6; i++) {
        p.r(
          x + 3 + i * 4,
          y + 17,
          3,
          1,
          i > 4
              ? '#E5655D'
              : i > 2
              ? '#F2CF72'
              : '#5CC28A',
        );
      }
    case 'elevator':
      p.r(x - 2, y - 1, 36, _wh * _t - 2, '#8E959F');
      p.r(x, y + 4, 32, _wh * _t - 7, '#5A606E');
  }
}

/// Bakes floors, rugs, walls and wall decor of the whole [world] into one
/// image (1 world px = 1 image px).
ui.Image buildBackground(
  FloorWorld world,
  List<Map<String, dynamic>> roles,
  List<Map<String, dynamic>> cards,
) {
  final w = world.w * _t, h = world.h * _t;
  return bake(w, h, (p) {
    p.r(0, 0, w, h, kOut);
    for (var y = 0; y < world.h; y += 2) {
      for (var x = 0; x < world.w; x += 2) {
        if (world.inRoom[y * world.w + x] != -1) continue;
        p.r(
          x * _t,
          y * _t,
          2 * _t,
          2 * _t,
          ((x + y) ~/ 2).isOdd ? _corr[0] : _corr[1],
        );
        p.r(x * _t, y * _t, 2 * _t, 1, _corr[2]);
        p.r(x * _t, y * _t, 1, 2 * _t, _corr[2]);
        p.r(x * _t - 1, y * _t, 3, 1, _teal[3]);
        p.r(x * _t, y * _t - 1, 1, 3, _teal[3]);
      }
    }
    for (var i = 0; i < world.rooms.length; i++) {
      final r = world.rooms[i];
      _drawFloor(
        p,
        r.frozen ? 'frozen' : (r.floor ?? 'carpet'),
        r.x * _t + _t,
        r.y * _t + _wh * _t,
        r.w * _t - 2 * _t,
        r.h * _t - _wh * _t - _t,
        i * 7,
      );
    }
    for (final z in world.zones) {
      final zp = world.zonePx[z.id];
      if (zp != null)
        p.r(
          z.x * _t,
          zp.py + 2,
          (z.w - 1) * _t,
          zp.ph - 4,
          z.tint ?? 'rgba(255,255,255,.1)',
        );
    }
    for (final g in world.rugs) {
      p.r(g.x, g.y, g.w, g.h, g.c1);
      p.r(g.x + 3, g.y + 3, g.w - 6, 1, g.c2);
      p.r(g.x + 3, g.y + g.h - 4, g.w - 6, 1, g.c2);
      p.r(g.x + 3, g.y + 3, 1, g.h - 6, g.c2);
      p.r(g.x + g.w - 4, g.y + 3, 1, g.h - 6, g.c2);
    }
    for (final r in world.rooms) {
      _drawWalls(p, r);
    }
    for (final r in world.rooms) {
      if (r.kind == 'toilet' || r.kind == 'booth' || r.w < 10) continue;
      final n = r.w > 26 ? 2 : 1;
      for (var i = 0; i < n; i++) {
        final lx = (r.x + (r.w * (i + 1) / (n + 1)).round()) * _t;
        final ly = (r.y + _wh + 1) * _t + 2;
        final warm = r.kind == 'pantry' || r.kind == 'lobby';
        p.r(lx - 3, ly - 2, 6, 5, kOl);
        p.r(lx - 2, ly - 1, 4, 3, warm ? '#FFC46E' : '#FF6C50');
        p.r(lx - 1, ly - 1, 1, 1, '#FFE2C8');
      }
    }
    for (final d in world.deco) {
      _drawWallDeco(p, d, roles, cards);
    }
  });
}

/// Desk without the monitor screen, sitting person or glow (those are live).
ui.Image buildDeskBase(FloorDesk d) {
  final w = d.w * _t;
  const pad = 4;
  return bake(w + pad * 2, 2 * _t + 26 + pad, (p) {
    // local origin: desk top-left at (pad, 22)
    const oy = 22;
    const x = pad;
    p.r(x - 1, oy - 1, w + 2, 2 * _t + 2, kOl);
    p.r(x, oy, w, 2 * _t - 3, '#D6B07A');
    p.r(x, oy, w, 1, '#E4C28F');
    p.r(x, oy + 2 * _t - 3, w, 3, '#B88E58');
    for (var k = 6; k < w - 2; k += 9) {
      p.r(x + k, oy + 2, 1, 2 * _t - 6, '#9C7646');
    }
    final mx = x + (w / 2).round() - 7, my = oy - 9;
    p.r(mx - 1, my - 1, 16, 12, kOl);
    p.r(mx, my, 14, 10, '#2F2A35');
    p.r(mx + 6, my + 10, 2, 2, kOl);
    p.r(mx + 4, my + 12, 6, 1, kOl);
    p.r(mx + 1, oy + 5, 12, 3, kOl);
    p.r(mx + 2, oy + 5, 10, 2, '#C9CDD4');
    p.r(x + w - 7, oy + 3, 4, 4, kOl);
    p.r(x + w - 6, oy + 4, 2, 2, d.mug);
    if (d.item == 'lamp') {
      p.r(x + 3, oy + 2, 3, 3, kOl);
      p.r(x + 4, oy + 3, 1, 1, '#F2CF72');
    }
    if (d.item == 'plant') {
      p.r(x + 2, oy + 2, 5, 5, kOl);
      p.r(x + 3, oy + 3, 3, 3, '#58A867');
    }
    if (d.item == 'duck') p.r(x + 3, oy + 3, 3, 3, '#F2CF72');
    if (d.item == 'pen') p.r(x + 3, oy + 3, 2, 3, '#4F79B8');
  });
}

/// Where the desk image sits relative to the desk tile (px).
const double kDeskImgDx = -4, kDeskImgDy = -22;
