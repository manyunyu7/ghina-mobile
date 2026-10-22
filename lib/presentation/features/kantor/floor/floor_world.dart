// The office as a tile world: walkable grid, furniture, desks, routing.
// Ported from the web renderer's `build()/furnish()/findPath()` (office-canvas.js).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'floor_furniture.dart';
import 'floor_pixel.dart';
import 'floor_sprites.dart' as s;

const _t = kTile;
const _wh = kWallRows;

class FloorDoor {
  const FloorDoor(this.side, this.at, this.w);
  final String side;
  final int at, w;
}

class FloorRoom {
  FloorRoom(Map<String, dynamic> j)
    : id = '${j['id']}',
      name = '${j['name'] ?? ''}',
      kind = '${j['kind'] ?? 'kode'}',
      x = (j['x'] as num?)?.toInt() ?? 0,
      y = (j['y'] as num?)?.toInt() ?? 0,
      w = (j['w'] as num?)?.toInt() ?? 0,
      h = (j['h'] as num?)?.toInt() ?? 0,
      floor = j['floor'] as String?,
      glass = j['wall'] == 'glass',
      path = j['path'] as String?,
      stack = '${j['stack'] ?? ''}',
      zoneOf = j['zoneOf'] as String?,
      tint = j['tint'] as String?,
      note = j['note'] as String?,
      frozen = j['frozen'] == true,
      elevator = (j['elevator'] as num?)?.toInt() ?? 7,
      worktrees = [for (final w in (j['worktrees'] as List?) ?? const []) '$w'],
      doors = [
        for (final d in (j['doors'] as List?) ?? const [])
          FloorDoor(
            '${(d as Map)['s']}',
            (d['at'] as num).toInt(),
            (d['w'] as num?)?.toInt() ?? 3,
          ),
      ];

  final String id, name, kind, stack;
  final int x, y, w, h, elevator;
  final String? floor, path, zoneOf, tint, note;
  final bool glass, frozen;
  final List<String> worktrees;
  final List<FloorDoor> doors;
}

class FloorDesk {
  FloorDesk({
    required this.room,
    required this.tx,
    required this.ty,
    required this.big,
    required this.role,
    required this.spare,
  }) : w = big ? 7 : 5,
       mug = const [
         '#FFFFFF',
         '#E5655D',
         '#3E6BA8',
         '#F2CF72',
         '#4F8F5B',
       ][(tx + ty) % 5],
       item = const [
         'lamp',
         'duck',
         'plant',
         'cube',
         'none',
         'pen',
       ][(tx * 7 + ty) % 6],
       facing = big ? 'down' : 'up',
       seatX = big ? (tx + 3) * _t + 4 : (tx + 2) * _t + 4,
       seatY = big ? (ty - 1) * _t + 7 : (ty + 2) * _t + 9,
       seatTx = big ? tx + 3 : tx + 2,
       seatTy = big ? ty - 1 : ty + 2,
       frontTx = big ? tx + 3 : tx + 4,
       frontTy = ty + 3;

  final String room;
  String? zone;
  final int tx, ty, w;
  final String? role;
  final bool spare, big;
  String? occ;
  final String mug, item, facing;
  final double seatX, seatY;
  final int seatTx, seatTy, frontTx, frontTy;
}

class FloorItem {
  FloorItem(
    this.spr,
    this.x,
    this.y,
    this.sortY, {
    this.tx = 0,
    this.ty = 0,
    this.fw = 1,
    this.fh = 1,
  });
  final Sprite spr;
  final double x, y, sortY;

  /// Footprint in tiles (the Magang stand in front of counters, shelves, printers).
  final int tx, ty, fw, fh;
}

class FloorRug {
  FloorRug(this.x, this.y, this.w, this.h, this.c1, this.c2);
  final double x, y, w, h;
  final String c1, c2;
}

class FloorDeco {
  FloorDeco(
    this.t,
    this.room,
    this.x,
    this.y, {
    this.w = 0,
    this.col,
    this.repo,
  });
  final String t;
  final FloorRoom room;
  final double x, y;
  final int w;
  final String? col;
  final String? repo;
}

class FloorTile {
  const FloorTile(this.tx, this.ty);
  final int tx, ty;
}

class FloorWorld {
  FloorWorld(
    Map<String, dynamic> plan,
    List<Map<String, dynamic>> roles, {
    FurnitureCatalog? catalog,
  }) : w = (plan['w'] as num).toInt(),
       h = (plan['h'] as num).toInt() {
    furn = placeFurniture(plan['furniture'], catalog, w, h);
    for (final f in furn) {
      for (final sp in f.spots) {
        if (sp.tx < 0 || sp.ty < 0 || sp.tx >= w || sp.ty >= h) continue;
        spots.add(sp);
        for (final a in f.def.affords) {
          (spotsByAff[a] ??= []).add(sp);
        }
      }
    }
    _allRooms = [
      for (final r in (plan['rooms'] as List? ?? const []))
        if (r is Map<String, dynamic>) FloorRoom(r),
    ];
    rooms = _allRooms.where((r) => r.kind != 'zone').toList();
    zones = _allRooms.where((r) => r.kind == 'zone').toList();
    decor = [
      for (final d in (plan['decor'] as List? ?? const []))
        if (d is Map<String, dynamic>) d,
    ];
    _roles = roles;
    _build();
  }

  final int w, h;
  late final List<FloorRoom> _allRooms, rooms, zones;
  late final List<Map<String, dynamic>> decor;
  late final List<Map<String, dynamic>> _roles;
  late final List<bool> walk = List<bool>.filled(w * h, false);
  late final List<int> inRoom = List<int>.filled(w * h, -1);
  final items = <FloorItem>[];
  final desks = <FloorDesk>[];
  final deco = <FloorDeco>[];
  final rugs = <FloorRug>[];
  final leds = <ui.Offset>[];
  final seat = <int>{};

  /// Catalog furniture placed by the plan, with its usable spots.
  late final List<FloorFurn> furn;
  final spots = <FloorSpot>[];
  final spotsByAff = <String, List<FloorSpot>>{};
  bool get hasFurniture => furn.isNotEmpty;

  /// Elevator (spawn and exit) in tiles.
  late FloorTile elevatorTile;
  late double elevatorX, elevatorY;

  List<FloorRoom> get allRooms => _allRooms;

  FloorRoom? room(String? id) {
    for (final r in _allRooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  FloorRoom? get server => rooms.where((r) => r.kind == 'server').firstOrNull;

  bool _ok(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && walk[y * w + x];

  /// Room id for a role/session `room` value; the daemon sometimes names a
  /// room by its short folder name ("ltc" for "app-golang-ltc").
  String? resolveRoom(Object? id) {
    if (id == null) return null;
    final s = '$id';
    if (room(s) != null) return s;
    for (final r in _allRooms) {
      if (r.id.endsWith('-$s') || r.path == s) return r.id;
    }
    return null;
  }

  List<Map<String, dynamic>> _residents(String id) => [
    for (final r in _roles)
      if (resolveRoom(r['room']) == id && r['archived'] != true) r,
  ];

  void _block(int x, int y, int bw, int bh) {
    for (var yy = y; yy < y + bh; yy++) {
      for (var xx = x; xx < x + bw; xx++) {
        if (xx >= 0 && yy >= 0 && xx < w && yy < h) walk[yy * w + xx] = false;
      }
    }
  }

  FloorRoom? _cur;
  bool _put(Sprite img, int tx, int ty, int fw, int fh, {bool any = false}) {
    final cur = _cur;
    if (cur != null &&
        !any &&
        (tx < cur.x + 1 ||
            ty < cur.y + _wh ||
            tx + fw > cur.x + cur.w - 1 ||
            ty + fh > cur.y + cur.h - 1)) {
      return false;
    }
    final px = tx * _t + ((fw * _t - img.w) / 2).round();
    final py = (ty + fh) * _t - img.h;
    items.add(
      FloorItem(img, px, py, (ty + fh) * _t, tx: tx, ty: ty, fw: fw, fh: fh),
    );
    _block(tx, ty, fw, fh);
    return true;
  }

  void _build() {
    for (var i = 0; i < rooms.length; i++) {
      final r = rooms[i];
      for (var y = r.y; y < r.y + r.h; y++) {
        for (var x = r.x; x < r.x + r.w; x++) {
          if (x < w && y < h) inRoom[y * w + x] = i;
        }
      }
    }
    for (var i = 0; i < w * h; i++) {
      if (inRoom[i] == -1) walk[i] = true;
    }
    for (final r in rooms) {
      for (var y = r.y + _wh; y < r.y + r.h - 1; y++) {
        for (var x = r.x + 1; x < r.x + r.w - 1; x++) {
          if (x < w && y < h) walk[y * w + x] = true;
        }
      }
    }
    for (final r in rooms) {
      for (var x = r.x; x < r.x + r.w; x++) {
        for (var y = r.y; y < r.y + _wh; y++) {
          _set(x, y, false);
        }
        _set(x, r.y + r.h - 1, false);
      }
      for (var y = r.y; y < r.y + r.h; y++) {
        _set(r.x, y, false);
        _set(r.x + r.w - 1, y, false);
      }
    }
    for (final r in rooms) {
      for (final d in r.doors) {
        for (var k = 0; k < d.w; k++) {
          if (d.side == 'b') _set(r.x + d.at + k, r.y + r.h - 1, true);
          if (d.side == 't') {
            for (var y = r.y; y < r.y + _wh; y++) {
              _set(r.x + d.at + k, y, true);
            }
          }
          if (d.side == 'l') _set(r.x, r.y + d.at + k, true);
          if (d.side == 'r') _set(r.x + r.w - 1, r.y + d.at + k, true);
        }
      }
    }
    for (final r in rooms) {
      _cur = r;
      _furnish(r);
    }
    for (final z in zones) {
      _cur = room(z.zoneOf);
      if (_cur != null) _furnishZone(z, _cur!);
    }
    _cur = null;
    for (final d in decor) {
      final x = (d['x'] as num).toInt(), y = (d['y'] as num).toInt();
      switch (d['t']) {
        case 'plant':
          _put(plant(x % 3), x, y, 1, 1);
        case 'vending':
          _put(s.vending(), x, y, 2, 1);
        case 'bench':
          _put(s.bench(), x, y, 4, 1);
        case 'water':
          _put(s.water(), x, y, 1, 1);
      }
    }
    for (final f in furn) {
      if (f.def.solid && !f.def.wall) _block(f.tx, f.ty, f.def.w, f.def.h);
    }
    for (final d in desks) {
      _block(d.tx, d.ty, d.w, 2);
      _set(d.seatTx, d.seatTy, true);
      seat.add(d.seatTy * w + d.seatTx);
    }
    final lobby =
        rooms.where((r) => r.kind == 'lobby').firstOrNull ??
        (rooms.isEmpty ? null : rooms.first);
    if (!_hasElevator && lobby != null) {
      elevatorX = (lobby.x + 2) * _t;
      elevatorY = lobby.y * _t;
      elevatorTile = FloorTile(lobby.x + 3, lobby.y + _wh);
    } else if (!_hasElevator) {
      elevatorX = 0;
      elevatorY = 0;
      elevatorTile = const FloorTile(1, 1);
    }
    items.sort((a, b) => a.sortY.compareTo(b.sortY));
  }

  bool _hasElevator = false;
  void _set(int x, int y, bool v) {
    if (x >= 0 && y >= 0 && x < w && y < h) walk[y * w + x] = v;
  }

  FloorDesk _deskAt(
    FloorRoom room,
    int tx,
    int ty,
    String? role,
    bool big,
    bool spare,
  ) {
    final d = FloorDesk(
      room: room.id,
      tx: tx,
      ty: ty,
      big: big,
      role: role,
      spare: spare,
    );
    desks.add(d);
    return d;
  }

  void _placeDesks(
    FloorRoom room,
    List<({String? role, bool spare})> list,
    int x0,
    int x1,
    int row,
    int maxRow,
  ) {
    var x = x0, y = row;
    for (final it in list) {
      if (x + 5 > x1) {
        x = x0;
        y += 5;
      }
      if (y + 2 > maxRow) break;
      _deskAt(room, x, y, it.role, false, it.spare);
      x += 7;
    }
  }

  void _furnish(FloorRoom r) {
    final ix = r.x + 1, iy = r.y + _wh, iw = r.w - 2, ih = r.h - _wh - 1;
    void dc(String t, num px, {int w = 0, String? col, String? repo}) =>
        deco.add(
          FloorDeco(
            t,
            r,
            r.x * _t + px.toDouble(),
            r.y * _t,
            w: w,
            col: col,
            repo: repo,
          ),
        );
    final ext = r.y == 0;
    final res = [
      for (final role in _residents(r.id))
        (role: '${role['id']}' as String?, spare: false),
    ];
    List<({String? role, bool spare})> spares(int n) =>
        List.generate(n, (_) => (role: null, spare: true));
    switch (r.kind) {
      case 'manager':
        dc('window', 12);
        dc('poster', 50);
        dc('wb', math.min(80, r.w * 8 - 100), w: 64);
        if (r.w > 22) dc('window', r.w * 8 - 40);
        dc('clock', r.w * 8 - 24);
        final cx = ix + (iw / 2).floor() - 3;
        rugs.add(
          FloorRug(
            (cx - 3) * _t,
            (iy + 4) * _t,
            13 * _t,
            6 * _t,
            '#9E2F2F',
            '#D9A441',
          ),
        );
        final mgr = res.firstOrNull;
        _deskAt(r, cx, iy + 6, mgr?.role, true, mgr == null);
        _placeDesks(
          r,
          [...res.skip(1), ...spares(2)],
          ix + 2,
          ix + iw,
          iy + 11,
          iy + ih - 3,
        );
        _put(s.bookshelf(), ix, iy, 4, 1);
        _put(plant(1), ix + iw - 1, iy, 1, 1);
        _put(s.trash(), cx + 8, iy + 7, 1, 1);
        _put(s.sofa('#5A4A6E'), ix + 1, iy + ih - 2, 5, 2);
        _put(s.cabinet(), ix + iw - 2, iy + 9, 2, 1);
        _put(plant(0), ix + iw - 1, iy + ih - 1, 1, 1);
      case 'meeting':
        dc('tv', math.max(24, (r.w * 8 / 2).floor() - 22), w: 44);
        dc('clock', r.w * 8 - 26);
        dc('plantWall', 12);
        _put(
          s.meetingTable(),
          ix + math.max(1, ((iw - 10) / 2).floor()),
          iy + 4,
          10,
          4,
        );
        _put(plant(0), ix, iy, 1, 1);
        _put(plant(1), ix + iw - 1, iy, 1, 1);
        _put(s.wbStand(), ix + iw - 4, iy + 9, 4, 1);
        _placeDesks(r, res, ix + 1, ix + iw, iy + 11, iy + ih - 1);
      case 'lib':
        if (ext) dc('window', r.w * 8 - 50);
        for (var k = 0; k * 5 + 4 <= iw - 2; k++) {
          if (k != 2) _put(s.bookshelf(), ix + k * 5, iy, 4, 1);
        }
        _put(s.roundTable(), ix + 6, iy + 7, 4, 2);
        _put(s.armchair('#3E6BA8'), ix + 14, iy + 8, 2, 2);
        _put(s.armchair('#3E6BA8'), ix + 1, iy + 12, 2, 2);
        _put(s.globe(), ix + iw - 2, iy + 12, 1, 1);
        _put(plant(1), ix + iw - 1, iy + ih - 1, 1, 1);
        _put(s.bookshelf(), ix + 8, iy + 13, 4, 1);
        _placeDesks(r, res, ix + 4, ix + iw, iy + 4, iy + 6);
      case 'qa':
        dc('ci', 40);
        dc('clock', r.w * 8 - 26);
        _put(s.qaBench(), ix + 1, iy, 8, 1);
        _placeDesks(
          r,
          [...res, ...spares(1)],
          ix + 2,
          ix + iw,
          iy + 6,
          iy + ih - 1,
        );
        _put(s.cabinet(), ix + iw - 2, iy, 2, 1);
        _put(plant(0), ix + iw - 1, iy + ih - 1, 1, 1);
        _put(s.printer(), ix, iy + ih - 1, 2, 1);
      case 'server':
        dc('warn', 20);
        dc('clock', r.w * 8 - 26);
        for (var k = 0; k < 4; k++) {
          if (_put(s.rack(), ix + 1 + k * 2, iy, 2, 1))
            leds.add(ui.Offset((ix + 1 + k * 2) * _t, (iy + 1) * _t - 44));
        }
        _put(s.cooling(), ix + iw - 3, iy, 3, 1);
        for (var k = 0; k < 3; k++) {
          if (_put(s.rack(), ix + 2 + k * 2, iy + 7, 2, 1))
            leds.add(ui.Offset((ix + 2 + k * 2) * _t, (iy + 8) * _t - 44));
        }
        _placeDesks(r, res, ix + 9, ix + iw, iy + 7, iy + ih - 1);
      case 'beku':
        dc('beku', 30);
        _put(s.sheet(), ix + 1, iy + 3, 5, 2);
        _put(s.sheet(), ix + 7, iy + 3, 5, 2);
        _put(s.boxes(), ix, iy + 9, 3, 2);
        _put(s.boxes(), ix + 9, iy + 10, 3, 2);
        _put(s.cabinet(), ix + iw - 2, iy, 2, 1);
        _placeDesks(r, res, ix + 1, ix + iw, iy + 13, iy + ih - 1);
      case 'pantry':
        dc('menu', 74);
        dc('clock', r.w * 8 - 60);
        if (r.w > 24) dc('window', r.w * 8 - 40);
        _put(s.counter(), ix + 1, iy, 7, 1);
        _put(s.fridge(), ix + 9, iy, 2, 1);
        _put(s.water(), ix + 12, iy, 1, 1);
        _put(s.vending(), ix + iw - 3, iy, 2, 1);
        _put(s.longTable(), ix + 4, iy + 7, 9, 2);
        _put(s.roundTable(), ix + 16, iy + 13, 4, 2);
        _put(s.roundTable(), ix + 4, iy + 13, 4, 2);
        _put(plant(1), ix + iw - 1, iy + ih - 1, 1, 1);
        _put(plant(0), ix, iy + ih - 1, 1, 1);
      case 'musik':
        dc('vinyl', 38);
        dc('vinyl', 56, col: '#3E6BA8');
        dc('eq', 76);
        dc('neonNote', 140);
        dc('gig', 174);
        dc('clock', r.w * 8 - 22);
        rugs.add(
          FloorRug(
            (ix + 9) * _t,
            (iy + 6) * _t,
            14 * _t,
            8 * _t,
            '#5B3F7A',
            '#E2B04A',
          ),
        );
        _put(s.speaker(), ix, iy, 2, 2);
        _put(s.piano(), ix + 3, iy, 6, 2);
        _put(s.musicBench(), ix + 5, iy + 2, 2, 1);
        _put(plant(0), ix + 10, iy + 1, 1, 1);
        _put(s.turntable(), ix + 16, iy, 4, 2);
        _put(s.guitar(), ix + 21, iy, 2, 2);
        _put(s.speaker(), ix + iw - 2, iy, 2, 2);
        _put(s.drums(), ix + 1, iy + 7, 5, 3);
        _put(s.sofa('#7A4E8C'), ix + 12, iy + 7, 5, 2);
        for (final b in const [
          ('#E5655D', 10, 11),
          ('#F2CF72', 17, 12),
          ('#3E6BA8', 19, 9),
        ]) {
          if (_put(s.beanbag(b.$1), ix + b.$2, iy + b.$3, 2, 1))
            _set(ix + b.$2, iy + b.$3, true);
        }
        _put(plant(0), ix, iy + ih - 1, 1, 1);
        _put(plant(1), ix + iw - 1, iy + ih - 1, 1, 1);
      case 'toilet':
        dc('wc', 60);
        for (var k = 0; k < 3; k++) {
          _put(s.stall(), ix + 1 + k * 3, iy, 3, 1);
        }
        _put(s.sink(), ix + 12, iy, 2, 1);
        _put(s.sink(), ix + 14, iy, 2, 1);
      case 'booth':
        _put(s.phoneBooth(), ix + 2, iy + 2, 4, 2);
        _put(s.phoneBooth(), ix + 9, iy + 2, 4, 2);
        _put(plant(0), ix + iw - 1, iy + ih - 1, 1, 1);
      case 'lobby':
        dc('logo', math.min(64, (r.w - 10) * 8), w: 60);
        dc('elevator', r.elevator * 8);
        _hasElevator = true;
        elevatorX = (r.x + r.elevator) * _t;
        elevatorY = r.y * _t;
        elevatorTile = FloorTile(r.x + r.elevator + 2, r.y + _wh);
        rugs.add(
          FloorRug(
            (ix + 2) * _t,
            (iy + 10) * _t,
            math.min(14, iw - 4) * _t,
            8 * _t,
            '#3E5A7A',
            '#C9A15A',
          ),
        );
        _put(
          s.reception(),
          ix + math.max(1, ((iw - 8) / 2).floor()),
          iy + 5,
          8,
          2,
        );
        _put(s.sofa('#2F5D6E'), ix + 1, iy + 16, 5, 2);
        _put(s.sofa('#2F5D6E'), ix + iw - 6, iy + 16, 5, 2);
        _put(plant(1), ix, iy, 1, 1);
        _put(plant(0), ix + iw - 1, iy + 3, 1, 1);
        _put(plant(1), ix, iy + ih - 1, 1, 1);
        _put(plant(0), ix + iw - 1, iy + ih - 1, 1, 1);
        _put(s.water(), ix + 2, iy + 24, 1, 1);
        _put(s.bench(), ix + 6, iy + 32, 4, 1);
        _put(s.armchair('#7A3E3E'), ix + 2, iy + 38, 2, 2);
        _put(s.armchair('#7A3E3E'), ix + iw - 4, iy + 38, 2, 2);
      case 'openplan':
        if (ext) dc('window', 20);
        dc('clock', math.min(200, r.w * 8 - 30));
        dc('poster2', 120);
        if (r.w > 40) dc('poster3', 300);
        _put(s.printer(), ix + 22, iy + ih - 1, 2, 1);
        _put(s.water(), ix + 25, iy + ih - 1, 1, 1);
        _put(s.trash(), ix + 20, iy + ih - 1, 1, 1);
      case 'game':
        dc('window', 20);
        dc('poster3', 90);
        dc('wb', 130, w: 44, repo: r.id);
        dc('clock', r.w * 8 - 26);
        _placeDesks(
          r,
          [...res, ...spares(2)],
          ix + 2,
          ix + iw - 6,
          iy + 3,
          iy + ih - 6,
        );
        _put(s.arcade(), ix + iw - 3, iy, 2, 1);
        _put(s.arcade(), ix + iw - 6, iy, 2, 1);
        _put(s.beanbag('#E5655D'), ix + 3, iy + ih - 3, 2, 1);
        _put(s.beanbag('#3E6BA8'), ix + 7, iy + ih - 2, 2, 1);
        _put(plant(1), ix, iy + ih - 1, 1, 1);
        _put(s.bookshelf(), ix + 12, iy + ih - 2, 4, 1);
      case 'musholla':
      case 'lounge':
      case 'gym':
      case 'taman':
      case 'telepon':
      case 'tidur':
        // Furnished entirely from the catalog; only the wall gets decor.
        if (ext && r.w > 14) dc('window', 12);
        if (r.kind != 'taman') dc('clock', r.w * 8 - 22);
      default:
        if (ext) {
          dc('window', 12);
        } else {
          dc('poster2', 12);
        }
        dc('wb', (r.w * 8 / 2).floor() - 20, w: 40, repo: r.id);
        dc('clock', r.w * 8 - 22);
        _placeDesks(
          r,
          [...res, ...spares(res.isNotEmpty ? 1 : 2)],
          ix + 2,
          ix + iw - 1,
          iy + 3,
          iy + ih - 1,
        );
        _put(plant(r.x % 2), ix + iw - 1, iy, 1, 1);
        if (ih > 12) {
          _put(s.cabinet(), ix, iy + ih - 2, 2, 1);
          _put(plant(0), ix + iw - 1, iy + ih - 1, 1, 1);
        }
        if (r.w > 30) {
          _put(s.printer(), ix + iw - 4, iy + ih - 1, 2, 1);
          _put(s.sofa('#6E5A3E'), ix + 12, iy + ih - 3, 5, 2);
        }
    }
  }

  /// Zone: a sub-area of a parent room, with its own desks.
  late final zonePx = <String, ({double py, double ph})>{};
  void _furnishZone(FloorRoom z, FloorRoom op) {
    final iy = op.y + _wh;
    zonePx[z.id] = (py: iy * _t, ph: (op.h - _wh - 1) * _t);
    final res = _residents(z.id);
    var x = z.x + 2;
    final list = <({String? role, bool spare})>[
      for (final role in res) (role: '${role['id']}', spare: false),
      (role: null, spare: true),
      if (res.isEmpty) (role: null, spare: true),
    ];
    for (final it in list) {
      if (x + 5 > z.x + z.w - 1) break;
      final d = _deskAt(op, x, iy + 6, it.role, false, it.spare);
      d.zone = z.id;
      x += 7;
    }
    if (z.x + z.w < op.x + op.w - 1)
      _put(s.part(), z.x + z.w - 1, iy + 1, 1, 7, any: true);
    _put(plant(z.x % 2), z.x + 1, iy + 12, 1, 1, any: true);
  }

  // ------------------------------------------------------------ routing

  bool walkable(int x, int y) => _ok(x, y);

  /// Where to walk to reach a spot: the spot itself when free to stand on,
  /// else the closest walkable tile (preferring the side the spot faces).
  FloorTile? approachFor(int tx, int ty, String face) {
    if (_ok(tx, ty)) return FloorTile(tx, ty);
    final fx = face == 'left'
            ? -1
            : face == 'right'
            ? 1
            : 0,
        fy = face == 'up'
            ? -1
            : face == 'down'
            ? 1
            : 0;
    FloorTile? best;
    var bs = double.infinity;
    for (var dy = -7; dy <= 7; dy++) {
      for (var dx = -7; dx <= 7; dx++) {
        if (!_ok(tx + dx, ty + dy)) continue;
        final sc =
            math.sqrt(dx * dx + dy * dy) - (dx == fx && dy == fy ? .4 : 0);
        if (sc < bs) {
          bs = sc;
          best = FloorTile(tx + dx, ty + dy);
        }
      }
    }
    return best;
  }

  /// Free walkable tile next to ([tx],[ty]) closest to ([fromX],[fromY]) tiles.
  FloorTile? tileBeside(
    int tx,
    int ty,
    int fromX,
    int fromY, {
    Set<int> taken = const {},
  }) {
    FloorTile? best;
    var bs = double.infinity;
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        if ((dx == 0 && dy == 0) ||
            !_ok(tx + dx, ty + dy) ||
            taken.contains((ty + dy) * w + tx + dx))
          continue;
        final ring = math.max(dx.abs(), dy.abs());
        final ddx = tx + dx - fromX, ddy = ty + dy - fromY;
        final sc = ring * 10 + math.sqrt(ddx * ddx + ddy * ddy);
        if (sc < bs) {
          bs = sc;
          best = FloorTile(tx + dx, ty + dy);
        }
      }
    }
    return best;
  }

  List<int>? nearestWalk(int x, int y) {
    for (var r = 1; r < 10; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (_ok(x + dx, y + dy)) return [x + dx, y + dy];
        }
      }
    }
    return null;
  }

  /// A* over the walk grid, 8-neighbour, corner cutting forbidden; returns
  /// waypoints (turn points) in world px, ready to follow.
  List<ui.Offset>? findPath(int sx, int sy, int gx, int gy) {
    if (!_ok(gx, gy)) {
      final n = nearestWalk(gx, gy);
      if (n == null) return null;
      gx = n[0];
      gy = n[1];
    }
    if (!_ok(sx, sy)) {
      final n = nearestWalk(sx, sy);
      if (n == null) return null;
      sx = n[0];
      sy = n[1];
    }
    final n = w * h;
    final g = List<double>.filled(n, double.infinity);
    final from = List<int>.filled(n, -1);
    final closed = List<bool>.filled(n, false);
    final heap = _Heap();
    double hh(int x, int y) {
      final dx = (x - gx).abs(), dy = (y - gy).abs();
      return math.max(dx, dy) + .414 * math.min(dx, dy);
    }

    final start = sy * w + sx, goal = gy * w + gx;
    g[start] = 0;
    heap.push(hh(sx, sy), start);
    const dirs = [
      [1, 0, 1.0],
      [-1, 0, 1.0],
      [0, 1, 1.0],
      [0, -1, 1.0],
      [1, 1, 1.414],
      [1, -1, 1.414],
      [-1, 1, 1.414],
      [-1, -1, 1.414],
    ];
    var iter = 0;
    while (heap.isNotEmpty && iter++ < 60000) {
      final i = heap.pop();
      if (closed[i]) continue;
      closed[i] = true;
      if (i == goal) break;
      final x = i % w, y = i ~/ w;
      for (final d in dirs) {
        final dx = d[0].toInt(), dy = d[1].toInt();
        final nx = x + dx, ny = y + dy;
        if (!_ok(nx, ny)) continue;
        if (dx != 0 && dy != 0 && (!_ok(x + dx, y) || !_ok(x, y + dy)))
          continue;
        final ni = ny * w + nx;
        final ng = g[i] + d[2].toDouble();
        if (ng < g[ni]) {
          g[ni] = ng;
          from[ni] = i;
          heap.push(ng + hh(nx, ny), ni);
        }
      }
    }
    if (from[goal] == -1 && goal != start) return null;
    final pts = <int>[];
    var k = goal;
    while (k != -1 && k != start) {
      pts.add(k);
      k = from[k];
    }
    final rev = pts.reversed.toList();
    final out = <int>[];
    int? pdx, pdy;
    var prev = start;
    for (var idx = 0; idx < rev.length; idx++) {
      final p = rev[idx];
      final dx = p % w - prev % w, dy = p ~/ w - prev ~/ w;
      if (dx != pdx || dy != pdy) {
        if (idx > 0) out.add(prev);
        pdx = dx;
        pdy = dy;
      }
      prev = p;
    }
    out.add(goal);
    return [
      for (final p in out) ui.Offset((p % w) * _t + 4, (p ~/ w) * _t + 7),
    ];
  }

  ({int x0, int x1, int y0, int y1})? roomRect(String id) {
    final r = room(id);
    if (r == null) return null;
    if (r.kind == 'zone') {
      final op = room(r.zoneOf);
      if (op == null) return null;
      return (
        x0: r.x + 1,
        x1: r.x + r.w - 2,
        y0: op.y + _wh + 9,
        y1: op.y + op.h - 3,
      );
    }
    return (
      x0: r.x + 2,
      x1: r.x + r.w - 3,
      y0: r.y + _wh + 1,
      y1: r.y + r.h - 3,
    );
  }

  FloorTile? randomSpot(String id, [int? seed]) {
    final rc = roomRect(id);
    if (rc == null) return null;
    final rnd = math.Random(seed);
    for (var i = 0; i < 80; i++) {
      final x = rc.x0 + rnd.nextInt(math.max(1, rc.x1 - rc.x0 + 1));
      final y = rc.y0 + rnd.nextInt(math.max(1, rc.y1 - rc.y0 + 1));
      if (_ok(x, y) && !seat.contains(y * w + x)) return FloorTile(x, y);
    }
    return FloorTile(((rc.x0 + rc.x1) / 2).floor(), rc.y1);
  }

  FloorTile? serverDoor() {
    final sv = server;
    if (sv == null || sv.doors.isEmpty) return null;
    final d =
        sv.doors.where((x) => x.side == 't').firstOrNull ?? sv.doors.first;
    if (d.side == 't') return FloorTile(sv.x + d.at + 1, sv.y - 1);
    if (d.side == 'b') return FloorTile(sv.x + d.at + 1, sv.y + sv.h);
    return FloorTile(sv.x + 2, sv.y + _wh + 2);
  }

  /// Room (or zone) id under a world tile; zones win over their parent room.
  String? roomAtTile(int tx, int ty) {
    for (final z in zones) {
      final op = room(z.zoneOf);
      if (op != null &&
          tx >= z.x &&
          tx < z.x + z.w &&
          ty >= op.y &&
          ty < op.y + op.h)
        return z.id;
    }
    for (final r in rooms) {
      if (tx >= r.x && tx < r.x + r.w && ty >= r.y && ty < r.y + r.h)
        return r.id;
    }
    return null;
  }
}

Sprite plant(int v) => sprite('plant$v', 16, 24, (p) {
  p.r(4, 18, 8, 6, '#B5653A');
  p.r(3, 17, 10, 2, '#C9784A');
  p.r(4, 22, 8, 2, '#9A532F');
  const g1 = '#3E8E4E', g2 = '#58A867', g3 = '#2F7340';
  if (v % 2 == 1) {
    p.r(6, 2, 4, 15, g1);
    p.r(2, 6, 4, 9, g2);
    p.r(10, 5, 4, 10, g2);
    p.r(7, 0, 2, 3, g2);
    p.r(4, 10, 2, 6, g3);
    p.r(11, 11, 2, 5, g3);
  } else {
    p.r(3, 8, 10, 9, g1);
    p.r(5, 5, 6, 4, g2);
    p.r(1, 11, 3, 4, g2);
    p.r(12, 10, 3, 5, g2);
    p.r(6, 9, 2, 2, g2);
    p.r(9, 12, 2, 2, g3);
  }
});

class _Heap {
  final _a = <(double, int)>[];
  bool get isNotEmpty => _a.isNotEmpty;

  void push(double f, int i) {
    _a.add((f, i));
    var k = _a.length - 1;
    while (k > 0) {
      final p = (k - 1) >> 1;
      if (_a[p].$1 <= _a[k].$1) break;
      final t = _a[p];
      _a[p] = _a[k];
      _a[k] = t;
      k = p;
    }
  }

  int pop() {
    final top = _a.first, last = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = last;
      var k = 0;
      for (;;) {
        final l = 2 * k + 1, r = l + 1;
        var m = k;
        if (l < _a.length && _a[l].$1 < _a[m].$1) m = l;
        if (r < _a.length && _a[r].$1 < _a[m].$1) m = r;
        if (m == k) break;
        final t = _a[m];
        _a[m] = _a[k];
        _a[k] = t;
        k = m;
      }
    }
    return top.$2;
  }
}
