// Draws the office: baked background, furniture and characters sorted by
// depth, then labels, name tags and action bubbles in screen space.
// Ported from the web renderer's `draw()/drawDesk()/drawEnt()/drawLabels()`.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'floor_furniture.dart';
import 'floor_pixel.dart';
import 'floor_poses.dart';
import 'floor_scene.dart';
import 'floor_sim.dart';
import 'floor_world.dart';

const _t = kTile;

/// Camera over the world: `x/y` = world px at the top-left of the viewport,
/// `z` = screen px per world px. The `t*` fields are the eased targets.
class FloorCamera extends ChangeNotifier {
  double x = 0, y = 0, z = 1, tx = 0, ty = 0, tz = 1;
  Size size = Size.zero;
  double insetBottom = 0, insetTop = 0;

  double get visW => math.max(80, size.width);
  double get visH => math.max(80, size.height - insetTop - insetBottom);

  void clamp(FloorWorld w) {
    final vw = visW / tz, vh = visH / tz;
    final ww = w.w * _t, wh = w.h * _t;
    tx = vw >= ww ? (ww - vw) / 2 : tx.clamp(-40 / tz, ww - vw + 40 / tz);
    ty = vh >= wh ? (wh - vh) / 2 : ty.clamp(-40 / tz, wh - vh + 40 / tz);
  }

  double fitZoom(FloorWorld w) =>
      math.min(visW / (w.w * _t), visH / (w.h * _t));

  void jump() {
    x = tx;
    y = ty;
    z = tz;
    notifyListeners();
  }

  /// Eases toward the target; returns true while still moving.
  bool ease(double dt) {
    final k = 1 - math.pow(.0008, dt);
    final moving =
        (tx - x).abs() > .01 || (ty - y).abs() > .01 || (tz - z).abs() > .0005;
    if (!moving) return false;
    x += (tx - x) * k;
    y += (ty - y) * k;
    z += (tz - z) * k;
    return true;
  }

  ui.Offset toWorld(ui.Offset p) =>
      ui.Offset(x + p.dx / z, y + (p.dy - insetTop) / z);
}

class FloorPainter extends CustomPainter {
  FloorPainter({
    required this.world,
    required this.sim,
    required this.cam,
    required this.bg,
    required this.deskImages,
    required this.selected,
    required Listenable repaint,
    required this.dark,
    this.catalog,
  }) : super(repaint: repaint);

  /// Sprites of the catalog furniture placed in [world]; null = none drawn.
  final FurnitureCatalog? catalog;

  final FloorWorld world;
  final FloorSim sim;
  final FloorCamera cam;
  final ui.Image bg;
  final Map<FloorDesk, ui.Image> deskImages;
  final String? selected;
  final bool dark;

  final _img = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  @override
  bool shouldRepaint(FloorPainter old) =>
      old.bg != bg ||
      old.selected != selected ||
      old.world != world ||
      old.dark != dark ||
      old.catalog != catalog;

  @override
  void paint(Canvas canvas, Size size) {
    final z = cam.z;
    canvas.drawRect(Offset.zero & size, Paint()..color = hex(kOut));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, cam.insetTop);
    canvas.scale(z);
    canvas.translate(-cam.x, -cam.y);
    final time = sim.now;
    final view = Rect.fromLTWH(
      cam.x - 40,
      cam.y - 60,
      (size.width) / z + 80,
      (size.height) / z + 120,
    );

    canvas.drawImage(bg, Offset.zero, _img);
    final px = Px(canvas);
    _elevator(px);
    _serverDoor(px);
    for (final l in world.leds) {
      if (!view.contains(l)) continue;
      var i = 0;
      for (var y = 4; y < 42; y += 4) {
        final on = ((time * 4).floor() + y + i * 3) % 5 != 0;
        px.r(
          l.dx + 3 + ((y + i) % 3) * 3,
          l.dy + y,
          1,
          1,
          on ? '#5CC28A' : '#E3A33A',
        );
        i++;
      }
    }

    // depth-sorted draw list
    final list = <(double, void Function())>[];
    for (final it in world.items) {
      if (it.x > view.right ||
          it.x + it.spr.w < view.left ||
          it.y > view.bottom ||
          it.y + it.spr.h < view.top)
        continue;
      list.add((
        it.sortY,
        () => canvas.drawImage(it.spr.img, Offset(it.x, it.y), _img),
      ));
    }
    final cat = catalog;
    if (cat != null) {
      for (final f in world.furn) {
        if (!f.bounds.overlaps(view)) continue;
        list.add((f.sortY, () => _furn(canvas, cat, f, time)));
      }
    }
    for (final d in world.desks) {
      final r = Rect.fromLTWH(d.tx * _t - 8, d.ty * _t - 30, d.w * _t + 16, 60);
      if (!r.overlaps(view)) continue;
      list.add(((d.ty + 2) * _t + 1, () => _desk(canvas, px, d, time)));
    }
    for (final e in sim.ents.values) {
      if (e.mode == 'sit' && !e.isSub) continue;
      if (!view.inflate(20).contains(Offset(e.x, e.y))) continue;
      list.add((e.pose?.sortY ?? e.y, () => _ent(canvas, e, time)));
    }
    list.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in list) {
      it.$2();
    }
    for (final e in sim.ents.values) {
      final p = e.parent == null ? null : sim.ents[e.parent!];
      if (!e.isSub || p == null || e.alpha <= 0) continue;
      _dash(
        px,
        e.x,
        e.y - 10,
        p.x,
        p.y - 12,
        e.cap ?? '#9AA3AF',
        .55 * e.alpha,
      );
    }
    if (dark) {
      canvas.drawRect(
        Rect.fromLTWH(
          cam.x - 2,
          cam.y - 2,
          size.width / z + 4,
          size.height / z + 4,
        ),
        Paint()..color = const Color(0x380E0A18),
      );
    }
    canvas.restore();

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _labels(canvas, size);
    canvas.restore();
  }

  void _dash(
    Px p,
    double x0,
    double y0,
    double x1,
    double y1,
    String col,
    double a,
  ) {
    final d = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final n = (d / 4).floor();
    final c = hex(col).withValues(alpha: a);
    for (var i = 0; i < n; i += 2) {
      final f = i / n;
      p.r((x0 + (x1 - x0) * f).round(), (y0 + (y1 - y0) * f).round(), 1, 1, c);
    }
  }

  void _furn(Canvas c, FurnitureCatalog cat, FloorFurn f, double time) {
    final active = sim.activeFurn.contains(f.uid);
    c.drawImage(
      cat.image(
        f.def,
        frame: active && f.def.activeRows != null ? -1 : f.frameAt(time),
        active: active,
      ),
      Offset(f.x, f.y),
      _img,
    );
  }

  void _elevator(Px p) {
    final x = world.elevatorX,
        y = world.elevatorY + 4,
        h = kWallRows * _t - 7,
        o = sim.elevatorOpen;
    p.r(x, y, 32, h, '#1E2129');
    final dw = (16 * (1 - o * .9)).round();
    p.r(x, y, dw, h, '#AEB5BF');
    p.r(x + 32 - dw, y, dw, h, '#AEB5BF');
    p.r(x + dw - 1, y, 1, h, '#7A808A');
    p.r(x + 32 - dw, y, 1, h, '#7A808A');
    p.r(x + 14, y - 4, 4, 2, o > .3 ? '#5CC28A' : '#E3A33A');
  }

  void _serverDoor(Px p) {
    final sv = world.server;
    if (sv == null || sv.doors.isEmpty) return;
    final d = sv.doors.first;
    final col = sim.serverBusy
        ? '#5CC28A'
        : sim.serverWaiting
        ? '#E3A33A'
        : '#E5655D';
    if (d.side == 't') {
      p.r((sv.x + d.at) * _t, sv.y * _t + kWallRows * _t - 3, d.w * _t, 3, col);
    } else if (d.side == 'b') {
      p.r((sv.x + d.at) * _t, (sv.y + sv.h) * _t - 3, d.w * _t, 2, col);
    }
  }

  void _glow(Canvas c, double x, double y, String color, bool strong) {
    final col = hex(color);
    c.drawCircle(
      Offset(x, y),
      15,
      Paint()
        ..shader = ui.Gradient.radial(Offset(x, y), 15, [
          col.withValues(alpha: strong ? .5 : .25),
          col.withValues(alpha: 0),
        ]),
    );
  }

  void _person(Canvas c, double x, double y, Look look, PersonPose pose) {
    c.drawImage(
      personImage(look, pose),
      Offset(x.roundToDouble() - kPersonCx, y.roundToDouble() - kPersonFeet),
      _img,
    );
  }

  bool _blink(double t) => (t % 4.2) < .14;

  void _desk(Canvas c, Px p, FloorDesk d, double time) {
    final x = d.tx * _t, y = d.ty * _t, w = d.w * _t;
    final e = d.occ == null ? null : sim.ents[d.occ!];
    final sitting = e != null && e.mode == 'sit' && e.desk == d;
    final s = e?.s;
    final on = s != null && s['status'] != 'ended';
    final busy = on && s['status'] == 'working';
    void stool(double sx, double sy) {
      p.r(sx - 5, sy - 4, 10, 7, kOl);
      p.r(sx - 4, sy - 3, 8, 5, '#D59A55');
      p.r(sx - 4, sy - 3, 8, 1, '#E8B371');
      p.r(sx - 3, sy + 3, 1, 2, kOl);
      p.r(sx + 2, sy + 3, 1, 2, kOl);
    }

    if (d.facing == 'down') {
      p.r(x + 18, y - 15, 20, 14, kOl);
      p.r(x + 19, y - 14, 18, 12, '#5A4A6E');
      p.r(x + 19, y - 14, 18, 2, '#6E5C86');
      if (sitting) {
        _glow(c, d.seatX, y - 8, e.look.color, busy);
        _person(
          c,
          d.seatX,
          y + 2,
          e.look,
          PersonPose(
            sit: true,
            typing: busy,
            phase: busy ? (time * 9).floor() % 2 : 0,
            blink: _blink(time + e.t0),
          ),
        );
      }
    }
    c.drawImage(deskImages[d]!, Offset(x + kDeskImgDx, y + kDeskImgDy), _img);
    final mx = x + (w / 2).round() - 7, my = y - 9;
    p.r(mx + 1, my + 1, 12, 7, on ? '#4E8FD8' : '#3B3F4A');
    if (busy) {
      const code = ['#E8F2FF', '#B9DAFF', '#FFE08A', '#C8F0D0'];
      for (var i = 0; i < 3; i++) {
        final ww = 3 + ((i * 5 + (time * 3).floor() + d.tx) % 7);
        p.r(mx + 2, my + 2 + i * 2, math.min(ww, 10), 1, code[(i + d.tx) % 4]);
      }
    }
    if (s?['worktree'] != null) {
      p.r(x + w - 3, y - 10, 1, 10, kOl);
      p.r(x + w - 2, y - 10, 5, 4, '#F59A3C');
    }
    if (d.facing != 'down') {
      final sx = d.seatX, sy = d.seatY;
      stool(sx, sy - 2);
      if (sitting) {
        _glow(c, sx, sy - 8, e.look.color, busy);
        _person(
          c,
          sx,
          sy,
          e.look,
          PersonPose(
            sit: true,
            dir: 'up',
            typing: busy,
            phase: busy ? (time * 9).floor() % 2 : 0,
          ),
        );
      }
    }
    if (sitting && e.waiting)
      _exclaim(
        p,
        d.facing == 'down' ? d.seatX : d.seatX,
        (d.facing == 'down' ? y - 24 : d.seatY - 28),
        time,
      );
  }

  void _exclaim(Px p, double x, double y, double time) {
    if ((time * 3).floor() % 2 == 1) return;
    p.r(x - 1, y, 3, 6, '#F59A3C');
    p.r(x - 1, y + 8, 3, 2, '#F59A3C');
  }

  void _ent(Canvas c, FloorEnt e, double time) {
    final prev = e.alpha.clamp(0.0, 1.0);
    final layer = prev < 1;
    if (layer)
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, prev));
    if (e.pose?.sortY == null)
      Px(c).r(e.x - 6, e.y - 1, 12, 3, 'rgba(0,0,0,.22)');
    if (e.working || e.isSub)
      _glow(
        c,
        e.x,
        e.y - 10,
        e.isSub ? (e.cap ?? '#9AA3AF') : e.look.color,
        false,
      );
    if (e.owner) _glow(c, e.x, e.y - 10, '#F5C542', false);
    final walking = e.mode == 'walk';
    if (e.pose != null && !walking) {
      drawPosedPerson(c, _img, e, time);
      if (e.owner)
        _crown(
          Px(c),
          e,
          e.pose!.kind == 'sit' ||
                  (e.pose!.kind == 'play' && e.pose!.sortY != null)
              ? 4
              : 0,
          e.pose!.kind,
        );
      if (layer) c.restore();
      return;
    }
    _person(
      c,
      e.x,
      e.y,
      e.look,
      PersonPose(
        dir: e.dir,
        walk: walking,
        phase: walking ? ((time + e.t0) * 8).floor() % 2 : 0,
        blink: _blink(time + e.t0),
        small: e.isSub,
        lanyard: e.isSub ? e.cap : null,
        cap: e.isSub ? e.cap : null,
      ),
    );
    if (e.waiting) _exclaim(Px(c), e.x, e.y - 38, time);
    if (e.minion && e.carry != null) _carry(Px(c), e, time);
    if (e.owner)
      _crown(
        Px(c),
        e,
        walking && ((time + e.t0) * 8).floor() % 2 == 1 ? -1 : 0,
        'stand',
      );
    if (layer) c.restore();
  }

  /// What a Magang carries (mail, folder, box, paper, book, cup, broom) or holds
  /// up: the "?" sign for an agent waiting on permission.
  void _carry(Px p, FloorEnt e, double time) {
    final k = e.carry;
    final t = time + e.t0;
    final bob = e.mode == 'walk' && (t * 8).floor() % 2 == 1 ? 1 : 0;
    final x = e.x.round(), y = e.y.round() - bob;
    final hx = x + (e.dir == 'left' ? -11 : 6), hy = y - 9;
    switch (k) {
      case 'mail':
        p.r(hx - 1, hy - 3, 9, 7, kOl);
        p.r(hx, hy - 2, 7, 5, '#FDFCF2');
        for (final d in const [[1, -2], [2, -1], [3, 0], [4, -1], [5, -2]]) {
          p.r(hx + d[0], hy + d[1], 1, 1, '#9AA3AF');
        }
        p.r(hx + 5, hy + 1, 1, 1, '#C2413A');
      case 'folder':
        p.r(hx - 1, hy - 4, 10, 9, kOl);
        p.r(hx, hy - 3, 8, 7, '#E3A33A');
        p.r(hx, hy - 3, 3, 1, '#C9922A');
        p.r(hx + 1, hy - 1, 6, 1, '#FDFCF2');
        p.r(hx + 1, hy + 1, 5, 1, '#FDFCF2');
      case 'box':
        p.r(hx - 1, hy - 4, 10, 9, kOl);
        p.r(hx, hy - 3, 8, 7, '#B5835A');
        p.r(hx + 3, hy - 3, 2, 7, '#D9B58A');
        p.r(hx, hy - 3, 8, 1, '#C99A6E');
      case 'paper':
        p.r(hx - 1, hy - 4, 8, 9, kOl);
        p.r(hx, hy - 3, 6, 7, '#FDFCF2');
        p.r(hx + 1, hy - 2, 4, 1, '#9AA3AF');
        p.r(hx + 1, hy, 4, 1, '#9AA3AF');
        p.r(hx + 1, hy + 2, 3, 1, '#9AA3AF');
      case 'book':
        p.r(hx - 1, hy - 4, 8, 9, kOl);
        p.r(hx, hy - 3, 6, 7, '#3E6BA8');
        p.r(hx, hy - 3, 1, 7, '#2C4F80');
        p.r(hx + 2, hy - 2, 3, 1, '#F2CF72');
      case 'cup':
        final lift = (t * 3).floor() % 4 == 0 ? 1 : 0;
        p.r(hx - 1, hy - 1, 6, 6, kOl);
        p.r(hx, hy, 4, 4, '#FDFCF2');
        p.r(hx + 1, hy + 1, 2, 1, '#6B4A2E');
        p.r(hx + 1 + lift, hy - 3, 1, 2, 'rgba(255,255,255,.7)');
      case 'broom':
        p.r(hx - 1, hy - 14, 3, 20, kOl);
        p.r(hx, hy - 13, 1, 15, '#8B6B3E');
        p.r(hx - 2, hy + 2, 6, 5, kOl);
        p.r(hx - 1, hy + 3, 4, 3, '#E2B04A');
        p.r(hx - 1, hy + 5, 4, 1, '#B98A2E');
      case 'clip':
        p.r(hx - 1, hy - 4, 8, 10, kOl);
        p.r(hx, hy - 3, 6, 8, '#B5835A');
        p.r(hx + 1, hy - 2, 4, 6, '#FDFCF2');
        p.r(hx + 2, hy - 4, 2, 1, '#9AA3AF');
        p.r(hx + 2, hy - 1, 2, 1, '#9AA3AF');
        p.r(hx + 2, hy + 1, 2, 1, '#9AA3AF');
      case 'sign':
        final sx = x + 7, top = y - 44, up = (t * 2).floor() % 2;
        p.r(sx - 1, top + 9 + up, 3, 28 - up, kOl);
        p.r(sx, top + 10 + up, 1, 27 - up, '#8B6B3E');
        p.r(sx - 5, top - 1 + up, 11, 12, kOl);
        p.r(sx - 4, top + up, 9, 10, '#F5C84C');
        for (final q in const [[1, 0], [2, 0], [3, 0], [0, 1], [4, 1], [4, 2], [3, 3], [2, 3], [2, 4], [2, 6]]) {
          p.r(sx - 2 + q[0], top + 1 + q[1] + up, 1, 1, '#3A240F');
        }
    }
  }

  /// Small gold crown on the owner's head (not while lying or praying).
  void _crown(Px p, FloorEnt e, int dy, String kind) {
    if (kind == 'sleep' || kind == 'pray') return;
    final x = e.x.round(), y = e.y.round() - 24 + dy;
    p.r(x - 4, y - 1, 8, 4, kOl);
    p.r(x - 3, y + 1, 6, 2, '#F5C542');
    p.r(x - 3, y - 1, 1, 2, '#F5C542');
    p.r(x, y - 1, 1, 2, '#F5C542');
    p.r(x + 2, y - 1, 1, 2, '#F5C542');
    p.r(x - 3, y + 2, 6, 1, '#C48A1C');
  }

  // ------------------------------------------------------- screen space

  static final _tp = <String, TextPainter>{};
  TextPainter _text(String s, double size, Color color, {bool bold = false}) {
    final k = '$s|$size|${color.toARGB32()}|$bold';
    if (_tp.length > 500) _tp.clear();
    return _tp.putIfAbsent(k, () {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontFamily: 'monospace',
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return tp;
    });
  }

  Offset _s(double wx, double wy) =>
      Offset((wx - cam.x) * cam.z, (wy - cam.y) * cam.z + cam.insetTop);

  /// Orange "MAGANG" badge + first name under the feet.
  void _minionTag(Canvas c, FloorEnt e, Offset foot, double a) {
    final nm = _text(e.name, 8, const Color(0xFFFBF4EA), bold: true);
    final bd = _text('MAGANG', 8, const Color(0xFF3A1E08), bold: true);
    final bw = bd.width + 8, w = bw + nm.width + 8;
    final left = foot.dx - w / 2;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, foot.dy + 1, w, 13),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xE61F1628).withValues(alpha: a),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 1, foot.dy + 2, bw, 11),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFF2842B).withValues(alpha: a),
    );
    bd.paint(c, Offset(left + 1 + (bw - bd.width) / 2, foot.dy + 2 + (11 - bd.height) / 2));
    nm.paint(c, Offset(left + bw + 5, foot.dy + 1 + (13 - nm.height) / 2));
  }

  void _labels(Canvas c, Size size) {
    final z = cam.z;
    final fs = z < 1.2 ? 8.0 : 10.0;
    for (final r in world.allRooms) {
      if (r.kind == 'openplan') continue;
      double wx, wy;
      if (r.kind == 'zone') {
        final op = world.room(r.zoneOf);
        if (op == null) continue;
        wx = (r.x + 1) * _t;
        wy = (op.y + kWallRows) * _t + 2;
      } else {
        wx = r.x * _t + 10;
        wy = r.y * _t + 8;
      }
      final o = _s(wx, wy);
      if (o.dx > size.width || o.dy > size.height || o.dx < -220 || o.dy < -40)
        continue;
      final maxW = r.kind == 'zone' || r.w == 0
          ? double.infinity
          : (r.w * _t - 14) * z - 12;
      var name = r.name.toUpperCase();
      var tp = _text(name, fs, Colors.white, bold: true);
      while (tp.width > maxW && name.length > 3) {
        name = name.substring(0, name.length - 1);
        tp = _text('${name.trimRight()}…', fs, Colors.white, bold: true);
      }
      final sel = selected == r.id;
      final bgc = sel
          ? const Color(0xF2F59A3C)
          : r.kind == 'server'
          ? const Color(0xE0962828)
          : const Color(0xC71F1628);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, tp.width + 12, fs + 8),
        const Radius.circular(4),
      );
      c.drawRRect(rect, Paint()..color = bgc);
      final tp2 = _text(
        tp.text!.toPlainText(),
        fs,
        sel ? const Color(0xFF3A240F) : const Color(0xFFFBF4EA),
        bold: true,
      );
      tp2.paint(c, Offset(o.dx + 6, o.dy + (fs + 8 - tp2.height) / 2));
    }
    final ents = sim.ents.values.toList()..sort((a, b) => a.y.compareTo(b.y));
    for (final e in ents) {
      if (e.alpha <= 0) continue;
      final sit = e.mode == 'sit' && e.desk != null;
      final d = e.desk;
      final fx = sit ? d!.seatX : e.x;
      final fy = sit
          ? (d!.facing == 'down' ? d.ty * _t + 2 * _t + 2 : d.seatY + 2)
          : e.y + 2;
      final headY = sit
          ? (d!.facing == 'down' ? d.ty * _t - 20 : d.seatY - 24)
          : e.y - 26;
      final foot = _s(fx, fy), head = _s(fx, headY);
      if (foot.dx < -150 ||
          foot.dx > size.width + 150 ||
          foot.dy < -80 ||
          foot.dy > size.height + 60)
        continue;
      final a = e.alpha.clamp(0.0, 1.0);
      if (e.minion && z >= 1.4) {
        _minionTag(c, e, foot, a);
      } else if (z >= 1.0 && !e.minion) {
        final f = e.isSub ? 8.0 : 10.0;
        final gold = e.mgr || e.owner;
        final tp = _text(
          e.name,
          f,
          gold
              ? const Color(0xFF3A240F)
              : e.isSub
              ? const Color(0xFFCDEDEA)
              : const Color(0xFFFBF4EA),
          bold: true,
        );
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            foot.dx - tp.width / 2 - 5,
            foot.dy + 1,
            tp.width + 10,
            f + 6,
          ),
          const Radius.circular(3),
        );
        c.drawRRect(
          r,
          Paint()
            ..color =
                (e.owner
                        ? const Color(0xF7F5C542)
                        : e.mgr
                        ? const Color(0xF7F59A3C)
                        : const Color(0xE61F1628))
                    .withValues(alpha: a),
        );
        tp.paint(
          c,
          Offset(foot.dx - tp.width / 2, foot.dy + 1 + (f + 6 - tp.height) / 2),
        );
        if (e.s?['engine'] == 'codex') {
          final dot = Offset(foot.dx + tp.width / 2 + 5, foot.dy + 1);
          c.drawCircle(
            dot,
            3.5,
            Paint()..color = const Color(0xFF10A37F).withValues(alpha: a),
          );
          c.drawCircle(
            dot,
            3.5,
            Paint()
              ..color = const Color(0xFF1F1628).withValues(alpha: a)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
      final text = e.minion
          ? e.bubble
          : e.sayUntil > sim.now
          ? e.say
          : e.waveUntil > sim.now
          ? '👋'
          : e.owner
          ? e.actLabel
          : e.mode == 'walk' && e.goingTo != null && !e.isSub
          ? '> menuju ${e.goingTo}'
          : e.bubble.isEmpty && !e.isSub
          ? e.actLabel
          : e.bubble;
      if (text.isEmpty) continue;
      final wait = e.bkind == 'wait';
      if (z < 1.0) {
        c.drawCircle(
          head,
          3.5,
          Paint()
            ..color = wait ? const Color(0xFFF59A3C) : const Color(0xFFFDFCF2),
        );
        c.drawCircle(
          head,
          3.5,
          Paint()
            ..color = const Color(0xFF1F1628)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        continue;
      }
      final tp = _text(
        shortText(text, 34),
        11,
        wait ? const Color(0xFF2A1A08) : const Color(0xFF1F1628),
      );
      final bw = tp.width + 14, bh = 19.0;
      final bx = (head.dx - bw / 2).roundToDouble(),
          by = (head.dy - 10 - bh).roundToDouble();
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, bw, bh),
        const Radius.circular(5),
      );
      final fill = Paint()
        ..color = wait
            ? const Color(0xFFF59A3C)
            : e.bkind == 'sub'
            ? const Color(0xFFE8F4F2)
            : const Color(0xFFFDFCF2);
      final stroke = Paint()
        ..color = const Color(0xFF1F1628)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      c.drawRRect(rr, fill);
      c.drawRRect(rr, stroke);
      c.drawCircle(Offset(head.dx - 1, by + bh + 4), 2.2, fill);
      c.drawCircle(Offset(head.dx - 1, by + bh + 4), 2.2, stroke);
      c.drawCircle(Offset(head.dx - 4, by + bh + 8), 1.4, fill);
      c.drawCircle(Offset(head.dx - 4, by + bh + 8), 1.4, stroke);
      tp.paint(c, Offset(bx + 7, by + (bh - tp.height) / 2));
    }
  }
}
