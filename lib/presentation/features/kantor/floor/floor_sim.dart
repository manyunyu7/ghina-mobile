// Character simulation: which session sits/walks where, driven by live state.
// Ported from the web renderer's `desiredPlace()/goPlace()/sync()/step()`.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'floor_furniture.dart';
import 'floor_pixel.dart';
import 'floor_world.dart';

part 'floor_activity.dart';
part 'floor_minions.dart';
part 'floor_scenes.dart';
part 'floor_owner.dart';

const _t = kTile;

final _serverish = RegExp(
  r'\b(ssh|rsync|scp|deploy|git push|kubectl|docker push|sftp)\b',
);
final _testish = RegExp(
  r'\b(test|tests|pytest|phpunit|vitest|jest|analyze|lint|go vet|gradlew\b.*test|cargo test)\b',
);

const _verbs = {
  'Read': 'membaca',
  'Edit': 'mengedit',
  'Write': 'menulis',
  'MultiEdit': 'mengedit',
  'NotebookEdit': 'mengedit',
  'Bash': 'menjalankan',
  'Grep': 'mencari',
  'Glob': 'mencari',
  'WebSearch': 'riset',
  'WebFetch': 'membaca web',
  'Task': 'mendelegasikan',
  'Agent': 'mendelegasikan',
  'TodoWrite': 'menyusun todo',
  'Compact': 'merapikan',
};

String shortText(String s, int n) =>
    s.length > n ? '${s.substring(0, n - 1)}…' : s;

String _verb(Map<String, dynamic> tool) =>
    _verbs['${tool['name']}'] ?? '${tool['name']}';

Map<String, dynamic>? _map(Object? v) => v is Map<String, dynamic> ? v : null;

class FloorAct {
  FloorAct.go(this.tx, this.ty) : kind = 'go', ms = 0, fn = null;
  FloorAct.sit() : kind = 'sit', tx = 0, ty = 0, ms = 0, fn = null;
  FloorAct.wait(this.ms) : kind = 'wait', tx = 0, ty = 0, fn = null;
  FloorAct.call(this.fn) : kind = 'call', tx = 0, ty = 0, ms = 0;

  /// Glide to a world point (into a seat, a bed): the last step of an activity.
  FloorAct.slide(double x, double y, [this.ms = 380])
    : kind = 'slide',
      tx = 0,
      ty = 0,
      fn = null {
    px = x;
    py = y;
  }
  final String kind;
  final int tx, ty, ms;
  final void Function()? fn;
  double startedAt = 0, px = 0, py = 0, fromX = 0, fromY = 0;
}

class FloorEnt {
  FloorEnt(this.id, this.look, this.x, this.y)
    : t0 = math.Random().nextDouble() * 10;
  final String id;
  Look look;
  double x, y;
  final double t0;
  List<ui.Offset> path = [];
  final q = <FloorAct>[];
  FloorAct? cur;
  String mode = 'stand'; // stand | walk | sit
  String dir = 'down';
  String bubble = '', bkind = '';
  String name = '';
  String? goingTo;
  double alpha = 1;
  bool fade = false,
      leaving = false,
      instant = false,
      mgr = false,
      manual = false,
      reported = false;

  /// The owner's own character (see floor_owner.dart); [waveUntil]: shows a wave
  /// until that sim time.
  bool owner = false;
  double waveUntil = 0;

  /// Magang (floor_minions.dart): cosmetic NPC, no session. [carry] = what is in their hands, [speed] > 0 overrides the walking speed.
  bool minion = false;

  /// A balloon put over a real agent by a Magang scene (never changes the agent's own state).
  String say = '';
  double sayUntil = 0;
  String? carry;
  double speed = 0;
  MinionState? mn;
  FloorDesk? desk;

  /// Furniture activity in progress (see floor_activity.dart) and its pose.
  FloorActState? act;
  FloorPose? pose;
  String actLabel = '';
  int pickSeq = 0;
  double nextEval = 0;
  final prayed = <String>{};

  /// Spot keys this character could not reach (skipped from now on).
  final bad = <String>{};
  String? place;
  double placeAt = 0;
  Map<String, dynamic>? s; // session
  Map<String, dynamic>? sub; // subagent entry (when this is a subagent)
  String? parent, cap, sid;
  bool get isSub => sub != null;
  bool get working => s?['status'] == 'working';
  bool get waiting => s?['waiting'] != null;
}

class FloorPlace {
  const FloorPlace(this.key, this.type, {this.room, this.seed});
  final String key, type; // leave | desk | door | spot
  final String? room;
  final int? seed;
}

class FloorSim {
  FloorSim(this.world, this.roles);

  FloorWorld world;
  List<Map<String, dynamic>> roles;
  final ents = <String, FloorEnt>{};
  List<Map<String, dynamic>> sessions = const [];

  /// Seconds of simulated time; advanced by [step].
  double now = 0;
  double elevatorOpen = 0, elevatorUntil = 0;
  bool animateArrivals = false;

  /// Behaviour rules, prayer times and wall clock for furniture activities.
  FurnBehaviors? behaviors;
  FloorPrayer? prayer;
  DateTime Function() clock = DateTime.now;

  /// Spot key -> entity id, and the uids of furniture being used right now.
  final reserved = <String, String>{};

  /// Magang director state (floor_minions.dart).
  final mh = MinionHub();
  final activeFurn = <String>{};
  final _rnd = math.Random();

  /// The owner's character: [ownerLocal] = driven on this device (joystick /
  /// taps), else mirrored from [ownerRemoteTo] (web). [target] = what the
  /// action button offers.
  FloorEnt? owner;
  bool ownerLocal = false;
  ui.Offset ownerInput = ui.Offset.zero;
  ui.Offset? ownerRemoteTo;
  String ownerRemoteFace = 'down';
  final target = ValueNotifier<OwnerTarget?>(null);
  double _nextScan = 0;
  String? _greeted;

  /// Swaps in a rebuilt world (furniture edited live) keeping the characters.
  void swapWorld(FloorWorld w) {
    for (final e in ents.values) {
      _endAct(e);
      e.desk = null;
      e.bad.clear();
      e.q.clear();
      e.cur = null;
      e.path = [];
      e.place = null;
      if (e.mode == 'sit') e.mode = 'stand';
    }
    reserved.clear();
    activeFurn.clear();
    world = w;
    minionsWorldChanged();
  }

  Map<String, dynamic>? roleOf(Map<String, dynamic> s) {
    final id = s['role'];
    if (id == null) return null;
    for (final r in roles) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  Look lookOf(Map<String, dynamic> s) {
    final r = roleOf(s);
    return r != null ? Look.fromRole(r) : Look.guest('${s['sid']}');
  }

  String nameOf(Map<String, dynamic> s) {
    final r = roleOf(s);
    final slot = (s['slot'] as num?)?.toInt() ?? 0;
    if (r != null) return '${r['name']}${slot > 0 ? ' #${slot + 1}' : ''}';
    return s['kind'] == 'rapat'
        ? 'Rapat'
        : shortText('${s['title'] ?? 'Sesi manual'}', 14);
  }

  FloorDesk? _homeDesk(Map<String, dynamic> s) {
    final r = roleOf(s);
    final sid = '${s['sid']}';
    final slot = (s['slot'] as num?)?.toInt() ?? 0;
    if (r != null && slot == 0 && s['kind'] != 'rapat') {
      for (final d in world.desks) {
        if (d.role == r['id'] && (d.occ == null || d.occ == sid)) return d;
      }
    }
    for (final d in world.desks) {
      if (d.occ == sid) return d;
    }
    final roomId = world.resolveRoom(s['room']);
    for (final d in world.desks) {
      if (d.occ == null &&
          (d.spare || d.role == null) &&
          (d.zone != null ? d.zone == roomId : d.room == roomId))
        return d;
    }
    return null;
  }

  bool _hasRoom(String id) => world.room(id) != null;

  FloorPlace _desired(FloorEnt e, Map<String, dynamic> s) {
    if (s['status'] == 'ended') return const FloorPlace('leave', 'leave');
    if (s['kind'] == 'rapat') {
      return FloorPlace(
        'meeting',
        'spot',
        room: _hasRoom('meeting') ? 'meeting' : world.resolveRoom(s['room']),
        seed: hashStr('${s['sid']}'),
      );
    }
    final tool = _map(s['tool']);
    final waiting = _map(s['waiting']);
    final working = s['status'] == 'working';
    final isBash = tool != null && tool['name'] == 'Bash';
    if (waiting != null &&
        _serverish.hasMatch('${waiting['summary'] ?? ''}') &&
        world.serverDoor() != null) {
      return const FloorPlace('srvdoor', 'door');
    }
    final toolLabel = '${tool?['label'] ?? ''}';
    if (working &&
        isBash &&
        _serverish.hasMatch(toolLabel) &&
        world.server != null) {
      return FloorPlace('server', 'spot', room: world.server!.id);
    }
    if (working && isBash && _testish.hasMatch(toolLabel) && _hasRoom('qa'))
      return const FloorPlace('qa', 'spot', room: 'qa');
    if (working &&
        tool != null &&
        (tool['name'] == 'WebSearch' || tool['name'] == 'WebFetch') &&
        _hasRoom('lib')) {
      return const FloorPlace('lib', 'spot', room: 'lib');
    }
    final last = DateTime.tryParse('${s['lastSeen'] ?? ''}');
    if (s['status'] == 'idle' &&
        last != null &&
        DateTime.now().difference(last).inMinutes > 12 &&
        _hasRoom('pantry')) {
      return FloorPlace(
        'pantry',
        'spot',
        room: 'pantry',
        seed: hashStr('${s['sid']}'),
      );
    }
    if (e.desk != null) return const FloorPlace('desk', 'desk');
    return FloorPlace(
      'hot',
      'spot',
      room: world.resolveRoom(s['room']),
      seed: hashStr('${s['sid']}'),
    );
  }

  void _replan(FloorEnt e, Map<String, dynamic> s) {
    final pl = _desired(e, s);
    final dwell = (now - e.placeAt) * 1000;
    if (pl.key != e.place &&
        (dwell > 3500 ||
            e.place == 'desk' ||
            e.place == null ||
            pl.key == 'leave' ||
            pl.key == 'srvdoor')) {
      _goPlace(e, pl);
    }
  }

  void _goPlace(FloorEnt e, FloorPlace pl, {bool keepAct = false}) {
    if (!keepAct) _endAct(e);
    e.q.clear();
    e.cur = null;
    e.path = [];
    e.place = pl.key;
    e.placeAt = now;
    e.goingTo = pl.type == 'desk'
        ? 'meja'
        : pl.type == 'leave'
        ? 'lift'
        : pl.type == 'door'
        ? 'Ruang Server'
        : world.room(pl.room)?.name ?? '';
    if (e.instant) {
      e.instant = false;
      if (pl.type == 'desk' && e.desk != null) {
        e.x = e.desk!.seatX;
        e.y = e.desk!.seatY;
        e.mode = 'sit';
        return;
      }
      final tgt = pl.type == 'door'
          ? world.serverDoor()
          : pl.type == 'spot' && pl.room != null
          ? world.randomSpot(pl.room!, pl.seed)
          : null;
      if (tgt != null) {
        e.x = tgt.tx * _t + 4;
        e.y = tgt.ty * _t + 7;
        e.mode = 'stand';
        return;
      }
    }
    if (pl.type == 'desk' && e.desk != null) {
      e.q.addAll([FloorAct.go(e.desk!.seatTx, e.desk!.seatTy), FloorAct.sit()]);
    } else if (pl.type == 'door') {
      final d = world.serverDoor();
      if (d != null) e.q.add(FloorAct.go(d.tx, d.ty));
    } else if (pl.type == 'leave') {
      _leave(e);
    } else if (pl.room != null) {
      final sp = world.randomSpot(pl.room!, pl.seed);
      if (sp != null) e.q.add(FloorAct.go(sp.tx, sp.ty));
    }
  }

  void _leave(FloorEnt e) {
    e.q.addAll([
      FloorAct.go(world.elevatorTile.tx, world.elevatorTile.ty),
      FloorAct.call(() {
        elevatorUntil = now + 1.5;
        e.fade = true;
      }),
    ]);
  }

  ({String text, String kind}) _bubble(Map<String, dynamic> s) {
    final waiting = _map(s['waiting']);
    final tool = _map(s['tool']);
    final subs = (s['subs'] as List?) ?? const [];
    if (waiting != null) {
      return (
        text: 'menunggu izin: ${waiting['summary'] ?? waiting['tool'] ?? ''}'
            .trim(),
        kind: 'wait',
      );
    }
    if (s['compacting'] == true) return (text: '= merapikan konteks', kind: '');
    if (s['status'] == 'starting') return (text: '> datang', kind: '');
    if (s['kind'] == 'rapat' && s['status'] != 'ended')
      return (text: '= sedang rapat', kind: 'sub');
    if (s['status'] == 'working' && tool != null)
      return (text: '< ${_verb(tool)} ${tool['label'] ?? ''}'.trim(), kind: '');
    if (s['status'] == 'working') return (text: '= berpikir', kind: '');
    if (s['status'] == 'idle' &&
        subs.any((x) => x is Map && x['status'] == 'working')) {
      return (text: '= menunggu ${subs.length} subagent', kind: 'sub');
    }
    return (text: '', kind: '');
  }

  FloorEnt _spawn(String id, Look look, {required bool atElevator}) {
    final e = FloorEnt(
      id,
      look,
      world.elevatorTile.tx * _t + 4,
      world.elevatorTile.ty * _t + 7,
    );
    if (atElevator) elevatorUntil = now + 1.8;
    ents[id] = e;
    return e;
  }

  /// Reconcile characters with the session list.
  void sync(List<Map<String, dynamic>> list) {
    sessions = list;
    minionsSessions(list);
    final seen = <String>{};
    for (final d in world.desks) {
      if (!list.any((s) => s['sid'] == d.occ && s['status'] != 'ended'))
        d.occ = null;
    }
    for (final s in list) {
      final sid = '${s['sid']}';
      seen.add(sid);
      var e = ents[sid];
      if (e == null) {
        e = _spawn(sid, lookOf(s), atElevator: animateArrivals);
        e.sid = sid;
        if (!animateArrivals && s['status'] != 'starting') e.instant = true;
      }
      e
        ..look = lookOf(s)
        ..name = nameOf(s)
        ..mgr = roleOf(s)?['isMgr'] == true
        ..manual = s['role'] == null
        ..s = s;
      if (e.desk == null || e.desk!.occ != sid) {
        final d = _homeDesk(s);
        if (d != null) {
          d.occ = sid;
          e.desk = d;
        } else {
          e.desk = null;
        }
      }
      final b = _bubble(s);
      e
        ..bubble = b.text
        ..bkind = b.kind;
      if (!_engineTick(e, force: true)) _replan(e, s);
      final subs = [
        for (final x in (s['subs'] as List? ?? const []))
          if (x is Map<String, dynamic>) x,
      ];
      for (final sub in subs) {
        final id = '$sid:${sub['id']}';
        seen.add(id);
        var se = ents[id];
        if (se == null) {
          se = _spawn(id, Look.guest(id).withColor('#E8E2D0'), atElevator: true)
            ..sub = sub
            ..parent = sid
            ..cap = e.look.color;
          final t = '${sub['type'] ?? ''}'.toLowerCase();
          final room = RegExp('explore|research|search').hasMatch(t)
              ? 'lib'
              : t.contains('plan')
              ? 'meeting'
              : RegExp('review|qa|test').hasMatch(t)
              ? (_hasRoom('qa') ? 'qa' : 'meeting')
              : null;
          if (room != null && _hasRoom(room)) {
            final sp = world.randomSpot(room);
            if (sp != null) se.q.add(FloorAct.go(sp.tx, sp.ty));
          } else if (e.desk != null) {
            final k = (subs.indexOf(sub) % 3) - 1;
            se.q.add(
              FloorAct.go(e.desk!.frontTx + 2 + k * 2, e.desk!.frontTy + 1),
            );
          } else {
            final rid = world.resolveRoom(s['room']);
            final sp = rid == null ? null : world.randomSpot(rid);
            if (sp != null) se.q.add(FloorAct.go(sp.tx, sp.ty));
          }
        }
        se
          ..sub = sub
          ..name = '${sub['type'] ?? 'agen'}'
          ..cap = e.look.color;
        final stool = _map(sub['tool']);
        se.bubble = sub['status'] == 'done'
            ? '> lapor ke induk'
            : stool != null
            ? '< ${_verb(stool)} ${stool['label'] ?? ''}'
            : '= ${shortText('${sub['desc'] ?? 'bekerja'}', 30)}';
        se.bkind = sub['status'] == 'done' ? 'report' : 'sub';
        if (sub['status'] == 'done' && !se.reported) {
          se
            ..reported = true
            ..q.clear()
            ..cur = null;
          final fx = e.desk?.frontTx ?? (e.x / _t).floor();
          final fy = e.desk?.frontTy ?? (e.y / _t).floor() + 2;
          se.q.addAll([
            FloorAct.go(fx + 1, fy),
            FloorAct.wait(2600),
            FloorAct.go(world.elevatorTile.tx, world.elevatorTile.ty),
            FloorAct.call(() {
              elevatorUntil = now + 1.5;
              se!.fade = true;
            }),
          ]);
        }
      }
    }
    for (final e in ents.values) {
      if (seen.contains(e.id) || e.fade || e.leaving || e.owner || e.minion)
        continue;
      _endAct(e);
      e
        ..leaving = true
        ..q.clear()
        ..cur = null
        ..bubble = e.isSub ? '' : 'Pulang';
      _leave(e);
    }
    animateArrivals = true;
  }

  /// Advance by [dt] seconds.
  void step(double dt) {
    now += dt;
    elevatorOpen +=
        ((now < elevatorUntil ? 1 : 0) - elevatorOpen) * math.min(1, dt * 6);
    final gone = <String>[];
    if (owner != null) _ownerTick(dt);
    mh.pathLeft = 2;
    if (now >= mh.nextTick) {
      mh.nextTick = now + .4;
      _minionTick();
    }
    for (final e in ents.values) {
      _stepEnt(e, dt);
      if (world.hasFurniture && !e.isSub && !e.owner && !e.minion)
        _engineTick(e);
      if (e.fade) {
        e.alpha -= dt * 2.2;
        if (e.alpha <= 0) gone.add(e.id);
      }
    }
    for (final id in gone) {
      final e = ents.remove(id);
      if (e != null) _endAct(e);
    }
  }

  void _stepEnt(FloorEnt e, double dt) {
    if (e.cur == null && e.q.isNotEmpty) {
      final a = e.q.removeAt(0)..startedAt = now;
      e.cur = a;
      if (a.kind == 'go') {
        e.mode = 'stand';
        final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
        if (!world.walkable(cx, cy)) {
          // standing in a seat or on a bed: step out in front first
          final ap = world.approachFor(cx, cy, 'down');
          if (ap != null && (ap.tx != cx || ap.ty != cy)) {
            e.q.insert(0, a);
            e.cur = FloorAct.slide(ap.tx * _t + 4, ap.ty * _t + 7, 260)
              ..startedAt = now
              ..fromX = e.x
              ..fromY = e.y;
            return;
          }
        }
        List<ui.Offset>? path;
        if (e.minion) {
          final r = _minionPath(cx, cy, a.tx, a.ty);
          if (r.deferred) {
            // path budget for this frame is spent: try again next frame
            e.q.insert(0, a);
            e.cur = null;
            return;
          }
          path = r.path;
        } else {
          path = world.findPath(cx, cy, a.tx, a.ty);
        }
        if (path == null && e.act != null) {
          // unreachable activity spot: give up on it instead of teleporting
          e.act!.failed = true;
          e.q.clear();
          e.cur = null;
          return;
        }
        e.path = path ?? [];
      } else if (a.kind == 'slide') {
        a.fromX = e.x;
        a.fromY = e.y;
        e.mode = 'stand';
      }
    }
    final c = e.cur;
    if (c == null) return;
    switch (c.kind) {
      case 'go':
        if (e.path.isEmpty) {
          e.cur = null;
          return;
        }
        final tgt = e.path.first;
        final dx = tgt.dx - e.x, dy = tgt.dy - e.y;
        final dist = math.sqrt(dx * dx + dy * dy),
            sp = (e.speed > 0 ? e.speed : 56) * dt;
        if (dist <= sp) {
          e.x = tgt.dx;
          e.y = tgt.dy;
          e.path.removeAt(0);
        } else {
          e.x += dx / dist * sp;
          e.y += dy / dist * sp;
        }
        e.dir = dx.abs() > dy.abs()
            ? (dx < 0 ? 'left' : 'right')
            : (dy < 0 ? 'up' : 'down');
        e.mode = 'walk';
        if (e.path.isEmpty) {
          e.mode = 'stand';
          e.dir = 'down';
          e.cur = null;
        }
      case 'slide':
        final k = ((now - c.startedAt) * 1000 / c.ms).clamp(0.0, 1.0);
        e.x = c.fromX + (c.px - c.fromX) * k;
        e.y = c.fromY + (c.py - c.fromY) * k;
        if (k >= 1) e.cur = null;
      case 'sit':
        final d = e.desk;
        if (d != null) {
          e.x = d.seatX;
          e.y = d.seatY;
          e.mode = 'sit';
          e.dir = 'down';
        }
        e.cur = null;
      case 'wait':
        if ((now - c.startedAt) * 1000 >= c.ms) e.cur = null;
      case 'call':
        e.cur = null;
        c.fn?.call();
    }
  }

  /// Entities currently on screen as a tap target: topmost last.
  FloorEnt? entAt(double wx, double wy) {
    FloorEnt? best;
    for (final e in ents.values) {
      if (e.alpha <= 0.3) continue;
      final sitting = e.mode == 'sit' && e.desk != null;
      final cx = sitting ? e.desk!.seatX : e.x;
      final cy = sitting
          ? (e.desk!.facing == 'down' ? e.desk!.ty * _t + 2 : e.desk!.seatY)
          : e.y;
      if (wx >= cx - 9 && wx <= cx + 9 && wy >= cy - 25 && wy <= cy + 3) {
        if (best == null ||
            (e.isSub ? 1 : 0) < (best.isSub ? 1 : 0) ||
            e.y > best.y)
          best = e;
      }
    }
    return best;
  }

  /// A role desk with nobody sitting at it, at this world point.
  FloorDesk? emptyDeskAt(double wx, double wy) {
    for (final d in world.desks) {
      if (d.role == null) continue;
      final e = d.occ == null ? null : ents[d.occ!];
      if (e != null && e.mode == 'sit') continue;
      if (wx >= d.tx * _t &&
          wx <= (d.tx + d.w) * _t &&
          wy >= d.ty * _t - 12 &&
          wy <= (d.ty + 2) * _t)
        return d;
    }
    return null;
  }

  bool get meetingOn => sessions.any((s) => s['kind'] == 'rapat');
  bool get serverBusy => sessions.any(
    (s) =>
        _map(s['tool'])?['name'] == 'Bash' &&
        _serverish.hasMatch('${_map(s['tool'])?['label'] ?? ''}'),
  );
  bool get serverWaiting => sessions.any(
    (s) =>
        _map(s['waiting']) != null &&
        _serverish.hasMatch('${_map(s['waiting'])?['summary'] ?? ''}'),
  );
}
