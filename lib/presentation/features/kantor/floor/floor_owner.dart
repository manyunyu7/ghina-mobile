// The owner's own character on the floor: walks with a joystick or to a tapped
// point, uses furniture it stands next to, notices agents. Lives in the sim so
// it shares the world grid, spot reservations and drawing with the agents.
part of 'floor_sim.dart';

/// Walking speed of the owner in world px/s (agents walk at 56).
const _ownerSpeed = 66.0;

/// Reach (world px) to an agent / to the edge of a piece of furniture.
const _agentReach = 22.0;
const _furnReach = 12.0;

/// Default look of the owner: gold tie, so the crown is not the only hint.
const kOwnerLook = Look(
  color: '#E5A93B',
  hair: '#2B1D14',
  skin: '#E8B98F',
  tie: true,
);

/// What the big action button offers right now.
class OwnerTarget {
  const OwnerTarget(
    this.kind,
    this.label,
    this.aff, {
    this.ent,
    this.spot,
    this.tab,
  });

  /// agent | use (furniture activity) | tab (open an app tab) | stop (leave the activity)
  final String kind;
  final String label;

  /// Affordance (or tab name) the UI picks an icon from.
  final String aff;
  final FloorEnt? ent;
  final FloorSpot? spot;

  /// For [kind] `tab`: the shell tab key (board | rapat | wiki).
  final String? tab;

  String get key => '$kind|${ent?.id}|${spot?.key}|$aff|$tab';
}

const _ownerLabels = {
  'coffee': 'Ngopi',
  'water': 'Minum',
  'snack': 'Ngemil',
  'eat': 'Makan',
  'sofa': 'Duduk santai',
  'sit': 'Duduk',
  'sleep': 'Tidur siang',
  'pray': 'Sholat',
  'wudhu': 'Wudhu',
  'play': 'Main',
  'game': 'Main game',
  'music': 'Main musik',
  'exercise': 'Olahraga',
  'train': 'Latihan',
  'read': 'Baca',
  'plant': 'Urus tanaman',
  'phone': 'Telepon',
  'print': 'Cetak',
  'think': 'Berpikir',
  'test': 'Cek perangkat',
  'server': 'Cek server',
};

/// Order of preference when a piece of furniture affords several things.
const _ownerPrefer = [
  'pray',
  'wudhu',
  'sleep',
  'coffee',
  'water',
  'snack',
  'eat',
  'exercise',
  'play',
  'game',
  'music',
  'read', //
  'sofa', 'sit', 'plant', 'phone', 'print', 'think', 'test', 'server', 'train',
];

final _shelfId = RegExp(
  r'rak-buku|katalog|rak-dokumen|perpus|library|shelf|peta-jalur',
);

extension FloorOwnerSim on FloorSim {
  bool get ownerActive => owner != null && ownerLocal;

  /// The owner steps out of the lift and takes control.
  FloorEnt ownerEnter(Look look, {bool fromLift = true}) {
    final old = ents.remove('owner');
    if (old != null) _endAct(old);
    final e = _spawn('owner', look, atElevator: fromLift)
      ..owner = true
      ..name = 'Kamu';
    if (!fromLift) {
      e.x = world.elevatorTile.tx * _t + 4;
      e.y = (world.elevatorTile.ty + 2) * _t + 7;
    } else {
      e.q.add(FloorAct.go(world.elevatorTile.tx, world.elevatorTile.ty + 2));
    }
    owner = e;
    ownerLocal = true;
    ownerInput = ui.Offset.zero;
    return e;
  }

  /// Back to the lift; the character fades out there.
  void ownerLeave() {
    final e = owner;
    owner = null;
    ownerLocal = false;
    ownerInput = ui.Offset.zero;
    ownerRemoteTo = null;
    target.value = null;
    if (e == null) return;
    _endAct(e);
    e
      ..leaving = true
      ..bubble = ''
      ..goingTo = null
      ..mode = 'stand'
      ..q.clear()
      ..path = [];
    if (e.cur?.kind != 'slide') e.cur = null;
    _leave(e);
  }

  /// The owner as driven from elsewhere (web): glide to [x],[y].
  void ownerRemote({
    required bool present,
    required double x,
    required double y,
    required String face,
    Look? look,
  }) {
    if (ownerLocal) return;
    if (!present) {
      if (owner != null) ownerLeave();
      return;
    }
    var e = owner;
    if (e == null) {
      e = _spawn('owner', look ?? kOwnerLook, atElevator: false)
        ..owner = true
        ..name = 'Kamu'
        ..x = x
        ..y = y;
      owner = e;
    }
    if (look != null) e.look = look;
    ownerRemoteTo = ui.Offset(x, y);
    ownerRemoteFace = face;
  }

  /// Walk to a world point (tap on the plan). [onArrive] runs when there.
  void ownerGoTo(double wx, double wy, {void Function()? onArrive}) {
    final e = owner;
    if (e == null || !ownerLocal) return;
    _ownerReset(e);
    e.q.add(FloorAct.go((wx / _t).floor(), (wy / _t).floor()));
    if (onArrive != null) e.q.add(FloorAct.call(onArrive));
  }

  /// Walk next to an agent, then run [onArrive].
  void ownerGoBeside(FloorEnt a, void Function() onArrive) {
    final e = owner;
    if (e == null || !ownerLocal) return;
    final tile = world.tileBeside(
      (a.x / _t).floor(),
      (a.y / _t).floor(),
      (e.x / _t).floor(),
      (e.y / _t).floor(),
    );
    _ownerReset(e);
    if (tile != null) e.q.add(FloorAct.go(tile.tx, tile.ty));
    e.q.add(FloorAct.call(onArrive));
  }

  /// Do what [t] says: furniture activity, or stand up.
  void ownerUse(OwnerTarget t) {
    final e = owner;
    if (e == null || !ownerLocal) return;
    if (t.kind == 'stop') {
      _ownerReset(e);
      return;
    }
    if (t.kind != 'use' || t.spot == null) return;
    _ownerReset(e);
    final a = FloorActState('owner', now);
    e.act = a;
    if (t.aff == 'pray' && _findSpot(e, 'wudhu') != null) {
      a.steps = const [FurnStep('pray', 0, 0)];
      final w = _findSpot(e, 'wudhu')!;
      _ownerGo(e, w, 'wudhu', 7);
    } else {
      _ownerGo(e, t.spot!, t.aff, 1e9);
    }
  }

  /// Joystick vector (each axis -1..1); zero when released.
  void ownerStick(double dx, double dy) => ownerInput = ui.Offset(dx, dy);

  // ------------------------------------------------------------- internals

  /// Stop whatever the owner was doing; step out of a seat or bed if needed.
  void _ownerReset(FloorEnt e) {
    _endAct(e);
    e
      ..q.clear()
      ..path = []
      ..goingTo = null
      ..pose = null;
    if (e.cur?.kind == 'slide') return;
    e.cur = null;
    final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
    if (!world.walkable(cx, cy)) {
      final ap = world.approachFor(cx, cy, 'down');
      if (ap != null && (ap.tx != cx || ap.ty != cy)) {
        e.cur = FloorAct.slide(ap.tx * _t + 4, ap.ty * _t + 7, 260)
          ..startedAt = now
          ..fromX = e.x
          ..fromY = e.y;
        e.mode = 'stand';
      }
    }
  }

  void _ownerGo(FloorEnt e, FloorSpot sp, String aff, double dwell) {
    final a = e.act;
    final ap = world.approachFor(sp.tx, sp.ty, sp.face);
    if (a == null || ap == null) return;
    _evictMinion(sp.key, e.id);
    reserved[sp.key] = e.id;
    a
      ..spot = sp
      ..aff = aff
      ..arrived = false
      ..until = null;
    e.goingTo = sp.furn.def.name;
    final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
    if (ap.tx != cx || ap.ty != cy) e.q.add(FloorAct.go(ap.tx, ap.ty));
    if (ap.tx != sp.tx || ap.ty != sp.ty) e.q.add(FloorAct.slide(sp.x, sp.y));
    e.q.add(FloorAct.call(() => _arrive(e, sp, dwell)));
  }

  bool _ownerOk(double px, double py) =>
      world.walkable((px / _t).floor(), (py / _t).floor());

  void _ownerTick(double dt) {
    final e = owner;
    if (e == null) return;
    if (!ownerLocal) {
      _ownerFollowRemote(e, dt);
      return;
    }
    final v = ownerInput;
    if (v.distance > .02) {
      if (e.cur?.kind == 'slide') return; // still stepping out of a seat
      if (e.act != null || e.pose != null || e.q.isNotEmpty || e.cur != null) {
        _ownerReset(e);
        if (e.cur != null) return;
      }
      final k = math.min(1.0, v.distance), sp = _ownerSpeed * dt * k;
      final ux = v.dx / v.distance, uy = v.dy / v.distance;
      var nx = e.x + ux * sp, ny = e.y + uy * sp;
      if (!_ownerOk(nx, ny)) {
        if (_ownerOk(nx, e.y)) {
          ny = e.y;
        } else if (_ownerOk(e.x, ny)) {
          nx = e.x;
        } else {
          nx = e.x;
          ny = e.y;
        }
      }
      e
        ..x = nx
        ..y = ny
        ..mode = 'walk'
        ..dir = ux.abs() > uy.abs()
            ? (ux < 0 ? 'left' : 'right')
            : (uy < 0 ? 'up' : 'down');
    } else if (e.cur == null && e.q.isEmpty && e.mode == 'walk') {
      e.mode = 'stand';
    }
    // wudhu -> pray: the next step of a chain starts when the dwell is over
    final a = e.act;
    if (a != null && a.until != null && a.steps.isNotEmpty && now >= a.until!) {
      final st = a.steps.removeAt(0);
      _clearSpot(e);
      final sp = _findSpot(e, st.a);
      if (sp == null) {
        _endAct(e);
      } else {
        a
          ..aff = st.a
          ..until = null;
        _ownerGo(e, sp, st.a, 1e9);
      }
    }
    if (now >= _nextScan) {
      _nextScan = now + .18;
      final t = _scan(e);
      if (t?.key != target.value?.key) target.value = t;
    }
  }

  void _ownerFollowRemote(FloorEnt e, double dt) {
    final to = ownerRemoteTo;
    if (to == null) return;
    final dx = to.dx - e.x, dy = to.dy - e.y, d = math.sqrt(dx * dx + dy * dy);
    if (d > 90) {
      e
        ..x = to.dx
        ..y = to.dy;
    } else if (d > .8) {
      final sp = math.min(d, 90 * dt);
      e
        ..x += dx / d * sp
        ..y += dy / d * sp
        ..mode = 'walk'
        ..dir = dx.abs() > dy.abs()
            ? (dx < 0 ? 'left' : 'right')
            : (dy < 0 ? 'up' : 'down');
      return;
    }
    e
      ..mode = 'stand'
      ..dir = ownerRemoteFace;
  }

  OwnerTarget? _scan(FloorEnt e) {
    final a = e.act;
    if (a != null) {
      if (!a.arrived) return null;
      return OwnerTarget(
        'stop',
        'Selesai ${_ownerLabels[a.aff]?.toLowerCase() ?? ''}'.trim(),
        a.aff,
      );
    }
    if (e.cur != null || e.q.isNotEmpty) return null;

    // agents first: they are the point of walking up to someone
    FloorEnt? near;
    var nd = _agentReach;
    for (final o in ents.values) {
      if (o.isSub || o.s == null || o.leaving || o.fade || o.alpha < .5)
        continue;
      final sit = o.mode == 'sit' && o.desk != null;
      final ox = sit ? o.desk!.seatX : o.x, oy = sit ? o.desk!.seatY : o.y;
      final d = math.sqrt((ox - e.x) * (ox - e.x) + (oy - e.y) * (oy - e.y));
      if (d < nd) {
        nd = d;
        near = o;
      }
    }
    if (near != null) {
      if (_greeted != near.id) {
        _greeted = near.id;
        _greet(near, e);
      }
      return OwnerTarget('agent', near.name, 'agent', ent: near);
    }
    _greeted = null;

    // a Magang within reach: send them away
    FloorEnt? mn;
    var md = _agentReach;
    for (final o in ents.values) {
      if (!o.minion || o.fade || o.alpha < .5 || o.mn?.state == 'leave') continue;
      final d = math.sqrt((o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y));
      if (d < md) {
        md = d;
        mn = o;
      }
    }

    FloorFurn? best;
    var bd = _furnReach;
    for (final f in world.furn) {
      final dx = math.max(
        math.max(f.tx * _t - e.x, e.x - (f.tx + f.def.w) * _t),
        0.0,
      );
      final dy = math.max(
        math.max(f.ty * _t - e.y, e.y - (f.ty + f.def.h) * _t),
        0.0,
      );
      final d = math.sqrt(dx * dx + dy * dy);
      if (d >= bd) continue;
      if (_furnAction(e, f) == null) continue;
      bd = d;
      best = f;
    }
    if (best != null) return _furnAction(e, best);
    return mn == null
        ? null
        : OwnerTarget('minion', 'Suruh pergi', 'minion', ent: mn);
  }

  /// A new agent came within reach: it looks up and waves.
  void _greet(FloorEnt a, FloorEnt e) {
    a.waveUntil = now + 2.6;
    if (a.mode == 'stand' &&
        a.pose == null &&
        a.act == null &&
        a.cur == null &&
        a.q.isEmpty) {
      final dx = e.x - a.x, dy = e.y - a.y;
      a.dir = dx.abs() > dy.abs()
          ? (dx < 0 ? 'left' : 'right')
          : (dy < 0 ? 'up' : 'down');
    }
  }

  OwnerTarget? _furnAction(FloorEnt e, FloorFurn f) {
    final affs = f.def.affords;
    if (affs.contains('whiteboard'))
      return const OwnerTarget('tab', 'Buka Board', 'board', tab: 'board');
    if (affs.contains('meeting'))
      return const OwnerTarget('tab', 'Buka Rapat', 'rapat', tab: 'rapat');
    if (affs.contains('read') && _shelfId.hasMatch(f.def.id))
      return const OwnerTarget('tab', 'Buka Wiki', 'wiki', tab: 'wiki');
    for (final aff in _ownerPrefer) {
      if (!affs.contains(aff)) continue;
      FloorSpot? sp;
      var sd = double.infinity;
      for (final s in f.spots) {
        if (!_spotFree(e, s) || world.approachFor(s.tx, s.ty, s.face) == null)
          continue;
        final d = (s.x - e.x) * (s.x - e.x) + (s.y - e.y) * (s.y - e.y);
        if (d < sd) {
          sd = d;
          sp = s;
        }
      }
      if (sp != null)
        return OwnerTarget('use', _ownerLabels[aff] ?? aff, aff, spot: sp);
    }
    return null;
  }
}
