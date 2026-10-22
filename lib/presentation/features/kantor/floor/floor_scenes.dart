// Magang room scenes: short multi-step scenes per kind of room (facing the
// boss, testing in QA, a brew at the pantry, a chat...). The scenes are DATA
// (scenes.json on the daemon, FurnScene in floor_furniture.dart); this is the
// runner. Same format and rules as the web runner, see the Magang section of
// docs/FRONTEND-CONTRACT.md. A scene always gives way to real agents and the
// owner (spots are taken back through `reserved`), to real work (couriers) and
// to an eviction (minionLeave).
part of 'floor_sim.dart';

/// One running scene: its room, the Magang playing it, and a real idle agent
/// the Magang chat with (never driven, never changed).
class SceneRun {
  SceneRun(this.scene, this.room, this.actors, this.agent, this.t0);
  final FurnScene scene;
  final FloorRoom room;
  final List<FloorEnt> actors;
  final FloorEnt? agent;
  final double t0;

  /// `sync` barriers: step index -> actors that have reached it.
  final arr = <int, int>{};
}

const _sceneMaxSec = 180.0;
const _stepMaxSec = 70.0;
const _doorMaxWait = 6.0;
const _outsideWait = 20.0;

extension FloorScenes on FloorSim {
  // ------------------------------------------------------------- selection

  bool _roomMatches(FurnScene sc, FloorRoom r) =>
      sc.rooms.contains(r.id) || sc.rooms.contains(r.kind);

  bool _roomBusy(FloorRoom r) => mh.runs.any((x) => x.room.id == r.id);

  bool _spotInRoom(FloorSpot sp, FloorRoom r) =>
      world.roomAtTile(sp.tx, sp.ty) == r.id;

  List<MinionStand> _standsIn(String kind, FloorRoom r) => [
    for (final s in _stands()[kind] ?? const <MinionStand>[])
      if (world.roomAtTile(s.tx, s.ty) == r.id) s,
  ];

  /// Real agents (sessions) that sit at their desk working.
  Iterable<FloorEnt> get _workingAgents => ents.values.where(
    (a) =>
        a.s != null &&
        !a.minion &&
        !a.isSub &&
        !a.leaving &&
        !a.fade &&
        a.s!['status'] == 'working' &&
        a.desk != null &&
        a.mode == 'sit',
  );

  String? get _prayerNow {
    final b = behaviors;
    return b == null ? null : prayer?.active(clock(), b.prayerWindowMin, b.prayerNames);
  }

  /// Every furniture and condition a scene needs is really there.
  bool _sceneFeasible(FurnScene sc, FloorRoom r) {
    for (final n in sc.need) {
      if (n == 'agent' && _workingAgents.isEmpty) return false;
      if (n == 'mgr-desk' && _deskTile(_mgrId) == null) return false;
    }
    if (sc.when == 'prayer' && _prayerNow == null) return false;
    for (final st in sc.steps) {
      final go = '${st['go'] ?? ''}';
      if (st['optional'] == true) continue;
      if (go.startsWith('aff:')) {
        final aff = go.substring(4);
        if (!(world.spotsByAff[aff] ?? const <FloorSpot>[]).any(
          (s) => _spotInRoom(s, r),
        )) {
          return false;
        }
      } else if (go.startsWith('stand:')) {
        if (_standsIn(go.substring(6), r).isEmpty) return false;
      } else if (go == 'desk:mgr') {
        if (_deskTile(_mgrId) == null) return false;
      } else if (go == 'door') {
        if (r.doors.isEmpty) return false;
      }
    }
    return true;
  }

  /// Can [m] walk to [r] at all? (a minion shut in an unreachable room must not hold a scene up). Memoised per tile.
  bool _canReach(FloorEnt m, FloorRoom r) {
    final here = _tileOf(m), key = '${here.tx},${here.ty}>${r.id}';
    return mh.reach.putIfAbsent(key, () {
      final goal = _doorTile(r) ?? world.randomSpot(r.id);
      return goal != null && world.findPath(here.tx, here.ty, goal.tx, goal.ty) != null;
    });
  }

  bool _freeMinion(FloorEnt m) =>
      const {'idle', 'act', 'do'}.contains(m.mn!.state) &&
      m.alpha >= 1 &&
      !m.fade &&
      now - m.mn!.born > 1.5;

  /// A real agent standing idle in the room: someone to chat with.
  FloorEnt? _idleAgentIn(FloorRoom r) {
    for (final a in ents.values) {
      final s = a.s;
      if (s == null || a.isSub || a.leaving || a.fade || a.minion || a.owner) {
        continue;
      }
      if (s['status'] != 'idle' || s['waiting'] != null || a.mode != 'stand') {
        continue;
      }
      if (a.cur != null || a.q.isNotEmpty) continue;
      if (world.roomAtTile((a.x / _t).floor(), (a.y / _t).floor()) == r.id) {
        return a;
      }
    }
    return null;
  }

  /// A real agent working in the room (sitting at a desk, or standing busy).
  bool _agentWorkingIn(FloorRoom r) {
    for (final a in ents.values) {
      final s = a.s;
      if (s == null || a.isSub || a.leaving || a.fade || a.minion) continue;
      if (s['status'] != 'working') continue;
      final d = a.desk;
      if (d != null && a.mode == 'sit' && world.resolveRoom(d.room) == r.id) {
        return true;
      }
      if (world.roomAtTile((a.x / _t).floor(), (a.y / _t).floor()) == r.id) {
        return true;
      }
    }
    return false;
  }

  /// Picks a scene for [e] from the rooms this office really has and starts it.
  bool _startScene(FloorEnt e, {bool prayerOnly = false}) {
    final hour = clock().hour + clock().minute / 60;
    final here = world.roomAtTile((e.x / _t).floor(), (e.y / _t).floor());
    final cands = <(FurnScene, FloorRoom, double, FloorEnt?)>[];
    for (final sc in mh.scenes) {
      if ((mh.sceneCool[sc.id] ?? 0) > now) continue;
      if (prayerOnly && sc.when != 'prayer') continue;
      var w = sc.weightAt(hour);
      if (e.mn!.lastScene == sc.id) w *= .1;
      if (w <= 0) continue;
      final any = sc.rooms.contains('*');
      for (final r in world.rooms) {
        if (any
            ? (r.kind == 'toilet' || r.id != here)
            : !_roomMatches(sc, r)) {
          continue;
        }
        if (_roomBusy(r) || !_sceneFeasible(sc, r) || !_canReach(e, r)) {
          continue;
        }
        final pool = _mins
            .where((m) => m != e && _freeMinion(m) && _canReach(m, r))
            .toList();
        final agent = sc.withAgent ? _idleAgentIn(r) : null;
        final need = math.max(1, sc.actorsMin - (agent != null ? 1 : 0));
        if (1 + pool.length < need) continue;
        cands.add((sc, r, w, agent));
      }
    }
    if (cands.isEmpty) return false;
    var total = 0.0;
    for (final c in cands) {
      total += c.$3;
    }
    var roll = _rnd.nextDouble() * total;
    var pick = cands.last;
    for (final c in cands) {
      roll -= c.$3;
      if (roll <= 0) {
        pick = c;
        break;
      }
    }
    final (sc, room, _, agent) = pick;
    final pool = _mins
        .where((m) => m != e && _freeMinion(m) && _canReach(m, room))
        .toList();
    final cx = room.x + room.w / 2, cy = room.y + room.h / 2;
    pool.sort(
      (a, b) =>
          ((a.x / _t - cx).abs() + (a.y / _t - cy).abs()).compareTo(
            (b.x / _t - cx).abs() + (b.y / _t - cy).abs(),
          ),
    );
    final minN = math.max(1, sc.actorsMin - (agent != null ? 1 : 0));
    final maxN = math.max(minN, sc.actorsMax - (agent != null ? 1 : 0));
    final n = math.min(1 + pool.length, minN + _rnd.nextInt(maxN - minN + 1));
    final actors = [e, ...pool.take(n - 1)];
    final run = SceneRun(sc, room, actors, agent, now);
    mh.runs.add(run);
    mh.sceneCool[sc.id] = now + sc.cooldown;
    final pr = sc.when == 'prayer' ? _prayerNow : null;
    for (var i = 0; i < actors.length; i++) {
      final a = actors[i];
      _mnStop(a);
      // the whole congregation prays together: nobody prays again alone in this window
      if (pr != null) a.prayed.add('${FloorPrayer.dayKey(clock())}-$pr');
      a.mn!
        ..state = 'scene'
        ..run = run
        ..ix = i
        ..progress = 0
        ..lastScene = sc.id
        ..since = now;
    }
    return true;
  }

  // -------------------------------------------------------------- abort/end

  void _endSceneFor(SceneRun run, {required bool ok}) {
    mh.runs.remove(run);
    for (final a in run.actors) {
      if (a.mn?.run != run) continue;
      if (a.mn!.state == 'scene') {
        _mnStop(a);
        _mnIdle(a, ok ? _rr(1, 3) : .5);
      }
    }
  }

  void _abortScene(SceneRun run) => _endSceneFor(run, ok: false);

  // ---------------------------------------------------------------- targets

  FloorTile? _doorTile(FloorRoom r) {
    if (r.doors.isEmpty) return null;
    final d = r.doors.first;
    final int tx, ty;
    switch (d.side) {
      case 'b':
        tx = r.x + d.at + d.w ~/ 2;
        ty = r.y + r.h;
      case 't':
        tx = r.x + d.at + d.w ~/ 2;
        ty = r.y - 1;
      case 'l':
        tx = r.x - 1;
        ty = r.y + d.at;
      default:
        tx = r.x + r.w;
        ty = r.y + d.at;
    }
    return world.approachFor(tx, ty, 'down');
  }

  /// Who the actors face / stand beside: the real idle agent when there is one, else actor 0.
  FloorEnt? _partnerOf(SceneRun run, FloorEnt e) {
    if (run.agent != null) return run.agent;
    final first = run.actors.first;
    return first == e ? (run.actors.length > 1 ? run.actors[1] : null) : first;
  }

  FloorSpot? _sceneSpot(FloorEnt e, String aff, FloorRoom r) {
    FloorSpot? best;
    var bd = double.infinity;
    for (final sp in world.spotsByAff[aff] ?? const <FloorSpot>[]) {
      if (!_spotInRoom(sp, r) || !_spotFree(e, sp)) continue;
      if (world.approachFor(sp.tx, sp.ty, sp.face) == null) continue;
      final d =
          (sp.x - e.x).abs() + (sp.y - e.y).abs() + _rnd.nextDouble() * 20;
      if (d < bd) {
        bd = d;
        best = sp;
      }
    }
    return best;
  }

  /// Tile for a non-furniture `go` (null: not found; the caller falls back to `inside` unless the step is optional).
  FloorTile? _sceneTile(SceneRun run, FloorEnt e, String go) {
    final r = run.room, here = _tileOf(e);
    if (go == 'door') return _doorTile(r);
    if (go == 'inside') return world.randomSpot(r.id);
    if (go == 'lift') return world.elevatorTile;
    if (go == 'desk:mgr') return _deskTile(_mgrId);
    if (go == 'desk:agent') {
      FloorTile? best;
      var bd = 1 << 30;
      for (final a in _workingAgents) {
        final d = a.desk!;
        final t = FloorTile(d.frontTx + 1, d.frontTy);
        // an agent working in this room first, then the nearest one anywhere
        final dist =
            (t.tx - here.tx).abs() +
            (t.ty - here.ty).abs() +
            (world.resolveRoom(d.room) == r.id ? 0 : 1000);
        if (dist < bd) {
          bd = dist;
          best = t;
        }
      }
      return best;
    }
    if (go == 'partner') {
      final first = run.actors.first;
      if (run.agent == null && first == e) return null; // actor 0 stays put
      final p = _partnerOf(run, e);
      if (p == null) return null;
      final taken = <int>{
        for (final o in run.actors)
          if (o != e) (o.y / _t).floor() * world.w + (o.x / _t).floor(),
      };
      return world.tileBeside(
        (p.x / _t).floor(),
        (p.y / _t).floor(),
        here.tx,
        here.ty,
        taken: taken,
      );
    }
    if (go.startsWith('stand:')) {
      final l = _standsIn(go.substring(6), r)
          .where((s) => !mh.bocc.containsKey(s.key))
          .toList();
      if (l.isEmpty) return null;
      return _nearest([for (final s in l) FloorTile(s.tx, s.ty)], here);
    }
    if (go.startsWith('room:')) return _roomTile(go.substring(5));
    return null;
  }

  // ------------------------------------------------------------- step logic

  String _dirToward(FloorEnt e, FloorEnt p) {
    final dx = p.x - e.x, dy = p.y - e.y;
    return dx.abs() > dy.abs()
        ? (dx < 0 ? 'left' : 'right')
        : (dy < 0 ? 'up' : 'down');
  }

  double _waitSec(Map<String, dynamic> step) {
    final w = step['wait'];
    if (w is num) return w.toDouble();
    if (w is List && w.length == 2) {
      final lo = (w[0] as num).toDouble(), hi = (w[1] as num).toDouble();
      return lo + _rnd.nextDouble() * (hi - lo);
    }
    return 0;
  }

  bool _isMine(SceneRun run, Map<String, dynamic> step, int ix) {
    final a = step['actor'];
    if (a == 'all') return true;
    final n = a is num ? a.toInt() : 0;
    // the real idle agent is the last "actor": its lines are spoken through actor 0
    if (run.agent != null && n == run.actors.length) return ix == 0;
    return n == ix;
  }

  /// The idle real agent gets the balloon (nothing else about it changes).
  void _guestSay(SceneRun run, Map<String, dynamic> step, double wait) {
    final ag = run.agent, say = step['say'];
    if (ag == null || say == null) return;
    final a = step['actor'];
    if (!(a == 'all' || (a is num && a.toInt() == run.actors.length))) return;
    final list = say is List ? [for (final x in say) '$x'] : ['$say'];
    if (list.isEmpty) return;
    ag.say = list[_rnd.nextInt(list.length)];
    ag.sayUntil = now + math.max(2.5, wait);
  }

  void _setSay(FloorEnt e, Map<String, dynamic> step) {
    final st = e.mn!, say = step['say'];
    st.sayList = say is List
        ? [for (final x in say) '$x']
        : say is String && say.isNotEmpty
        ? [say]
        : const [];
    st.sayIx = st.sayList.isEmpty ? 0 : _rnd.nextInt(st.sayList.length);
    e.bubble = st.sayList.isEmpty ? '' : st.sayList[st.sayIx];
    st.sayNext = now + 2.2;
    st.sayUntil = 0;
  }

  void _applyArrival(FloorEnt e, SceneRun run, Map<String, dynamic> step) {
    final carry = step['carry'];
    if (carry is String) e.carry = carry.isEmpty ? null : carry;
    if (e.pose == null) e.mode = 'stand';
    final face = step['face'];
    if (face == 'partner') {
      final p = _partnerOf(run, e);
      if (p != null) e.dir = _dirToward(e, p);
    } else if (face is String &&
        const {'up', 'down', 'left', 'right'}.contains(face) &&
        e.pose == null) {
      e.dir = face;
    }
    final pose = step['pose'];
    if (pose is String && pose != 'stand' && e.pose == null) {
      e.pose = FloorPose(pose, e.dir, '${step['fx'] ?? pose}', now);
    } else if (pose == 'stand' && step['fx'] is String && e.pose == null) {
      e.pose = FloorPose('stand', e.dir, '${step['fx']}', now);
    }
    if (step['turnAgent'] == true) {
      // the nearest standing real agent in the room looks up (only a glance, no state change)
      for (final a in ents.values) {
        if (a.s == null || a.minion || a.isSub || a.mode != 'stand' || a.pose != null || a.cur != null || a.q.isNotEmpty) continue;
        if (world.roomAtTile((a.x / _t).floor(), (a.y / _t).floor()) == run.room.id) {
          a.dir = _dirToward(a, e);
          break;
        }
      }
    }
  }

  void _skipStep(FloorEnt e, SceneRun run, Map<String, dynamic> step) {
    e.mn!.step = null;
    e.bubble = '';
    _reachBarrier(run, e, step);
  }

  /// Begins [step] for [e]: reserves a spot or walks to the target.
  void _sceneBegin(FloorEnt e, SceneRun run, Map<String, dynamic> step) {
    final st = e.mn!;
    final go = '${step['go'] ?? ''}';
    st
      ..step = step
      ..onSpot = false
      ..doorWait = false
      ..stepAt = now;
    var wait = _waitSec(step);
    st.stepEnd = now + _stepMaxSec + wait;
    final onlyGuest = run.agent != null && step['actor'] == run.actors.length;
    if (onlyGuest) {
      // a line of the idle agent: only its balloon, the Magang just waits
      _guestSay(run, step, wait);
      e.q.clear();
      e.cur = null;
      if (wait > 0) e.q.add(FloorAct.wait((wait * 1000).round()));
      return;
    }
    _setSay(e, step);
    _guestSay(run, step, wait);
    if (go.isEmpty) {
      // no `go`: stay where (and how) the actor is: say / wait / carry only
      e.q.clear();
      e.cur = null;
      e.q.add(FloorAct.call(() => _applyArrival(e, run, step)));
      if (wait > 0) e.q.add(FloorAct.wait((wait * 1000).round()));
      return;
    }
    // moving on: let go of the previous spot and pose
    _endAct(e);
    st.holding = false;
    e
      ..pose = null
      ..mode = 'stand'
      ..q.clear()
      ..cur = null
      ..path = []
      ..speed = ((step['speed'] as num?) ?? 0).toDouble();
    if (go.startsWith('aff:')) {
      final sp = _sceneSpot(e, go.substring(4), run.room);
      final ap = sp == null ? null : world.approachFor(sp.tx, sp.ty, sp.face);
      if (sp != null && ap != null) {
        final a = FloorActState('scene', now)
          ..aff = go.substring(4)
          ..spot = sp
          ..deadline = now + _stepMaxSec;
        e.act = a;
        _evictMinion(sp.key, e.id);
        reserved[sp.key] = e.id;
        st
          ..onSpot = true
          ..holding = true;
        final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
        if (ap.tx != cx || ap.ty != cy) e.q.add(FloorAct.go(ap.tx, ap.ty));
        if (ap.tx != sp.tx || ap.ty != sp.ty) {
          e.q.add(FloorAct.slide(sp.x, sp.y));
        }
        e.q.add(
          FloorAct.call(() {
            _arrive(e, sp, wait);
            _applyArrival(e, run, {...step, 'pose': null, 'face': null});
          }),
        );
        return;
      }
      if (step['optional'] == true) return _skipStep(e, run, step);
    }
    if (go == 'door' && !(step['waitOutside'] == true)) {
      wait = math.min(wait, _doorMaxWait);
    }
    var t = _sceneTile(run, e, go);
    if (t == null && go == 'partner' && run.agent == null && run.actors.first == e) {
      t = _tileOf(e); // actor 0 stays where it is
    }
    if (t == null) {
      if (step['optional'] == true) return _skipStep(e, run, step);
      t = world.randomSpot(run.room.id); // not found: just somewhere inside
    }
    if (t == null) return _skipStep(e, run, step);
    final here = _tileOf(e);
    if (t.tx != here.tx || t.ty != here.ty) e.q.add(FloorAct.go(t.tx, t.ty));
    e.q.add(FloorAct.call(() => _applyArrival(e, run, step)));
    if (wait > 0) e.q.add(FloorAct.wait((wait * 1000).round()));
  }

  void _stepFinished(FloorEnt e, SceneRun run) {
    final st = e.mn!, step = st.step!;
    e
      ..bubble = ''
      ..speed = 0;
    st
      ..step = null
      ..onSpot = false
      ..sayList = const [];
    _reachBarrier(run, e, step);
  }

  /// Marks the current step done and, for a `sync` step, joins its barrier.
  void _reachBarrier(SceneRun run, FloorEnt e, Map<String, dynamic> step) {
    final st = e.mn!, i = st.progress;
    st.progress = i + 1;
    if (step['sync'] == true) {
      run.arr[i] = (run.arr[i] ?? 0) + 1;
      st.barrier = i;
      st.syncSince = now;
    }
  }

  // ------------------------------------------------------------------- tick

  void _sceneTick() {
    for (final run in [...mh.runs]) {
      final steps = run.scene.steps;
      // cancel everything when somebody was sent home, lost the spot, the agent partner
      // got busy, or it takes too long
      var abort = now - run.t0 > _sceneMaxSec;
      final ag = run.agent;
      if (ag != null &&
          (ag.s?['status'] != 'idle' ||
              ag.s?['waiting'] != null ||
              ag.mode != 'stand' ||
              ag.cur != null ||
              ag.q.isNotEmpty ||
              !ents.containsKey(ag.id))) {
        abort = true;
      }
      for (final a in run.actors) {
        final st = a.mn;
        if (st == null ||
            st.run != run ||
            st.state != 'scene' ||
            !ents.containsKey(a.id) ||
            a.fade) {
          abort = true;
        } else if (st.holding) {
          final act = a.act;
          if (act == null || act.failed || act.spot == null) abort = true;
        } else if (st.step != null && now > st.stepEnd && !st.doorWait) {
          abort = true;
        }
      }
      if (abort) {
        _abortScene(run);
        continue;
      }
      for (final a in run.actors) {
        final st = a.mn!;
        // rotating balloon (💬 ☕ 😂 👍)
        if (st.sayList.length > 1 && now >= st.sayNext) {
          st.sayIx = (st.sayIx + 1) % st.sayList.length;
          a.bubble = st.sayList[st.sayIx];
          st.sayNext = now + 2.2;
        }
        final cur = st.step;
        if (cur != null) {
          if (st.doorWait) {
            // waiting outside the door while a real agent works inside
            final arrived = a.cur == null && a.q.isEmpty;
            if (!_agentWorkingIn(run.room)) {
              st.doorWait = false;
              _sceneBegin(a, run, {...cur, 'skipIf': null});
            } else if (arrived && now >= st.doorUntil) {
              _abortScene(run); // still busy after 20 s: the scene is cancelled
              break;
            }
            continue;
          }
          final done = st.onSpot
              ? (a.act != null &&
                    a.act!.arrived &&
                    now >= (a.act!.until ?? double.infinity))
              : a.cur == null && a.q.isEmpty;
          if (done) _stepFinished(a, run);
          continue;
        }
        // `sync` barrier after a step: wait until every actor reached it (at most 15 s)
        final bar = st.barrier;
        if (bar != null) {
          // at most 15 s, but never while the one we wait for is still walking over
          final walking = run.actors.any(
            (o) => o.mn!.step != null && (o.cur != null || o.q.isNotEmpty),
          );
          if ((run.arr[bar] ?? 0) >= run.actors.length ||
              (now - st.syncSince > 15 && !walking)) {
            st.barrier = null;
          } else {
            continue;
          }
        }
        // next step of this actor
        while (st.progress < steps.length) {
          final step = steps[st.progress];
          if (!_isMine(run, step, st.ix)) {
            _reachBarrier(run, a, step);
            if (st.barrier != null) break;
            continue;
          }
          if (step['skipIf'] == 'agent-in-room' && _agentWorkingIn(run.room)) {
            final d = step['waitOutside'] == true ? _doorTile(run.room) : null;
            if (d != null) {
              _endAct(a);
              st.holding = false;
              a
                ..pose = null
                ..q.clear()
                ..cur = null
                ..path = []
                ..mode = 'stand';
              st
                ..step = step
                ..doorWait = true
                ..stepAt = now
                ..doorUntil = now + _outsideWait;
              a.q.add(FloorAct.go(d.tx, d.ty));
              break;
            }
            _reachBarrier(run, a, step);
            if (st.barrier != null) break;
            continue;
          }
          _sceneBegin(a, run, step);
          break;
        }
      }
      if (run.actors.every((a) => a.mn!.progress >= steps.length && a.mn!.step == null)) {
        _endSceneFor(run, ok: true);
      }
    }
  }

  // --------------------------------------------------------------- greeting

  /// A Magang waves at the owner passing by (< 3 tiles, once per 40 s each).
  void _greetOwner(FloorEnt e) {
    final o = owner, st = e.mn!;
    if (o == null || st.state == 'job' || st.state == 'scene') return;
    if (st.greetAt > now - 40 || e.bubble.isNotEmpty || e.alpha < 1) return;
    final dx = o.x - e.x, dy = o.y - e.y;
    if (dx * dx + dy * dy > 24 * 24) return;
    st.greetAt = now;
    e.bubble = '👋';
    st.sayUntil = now + 2.5;
    if (e.mode != 'walk' && e.pose == null && e.cur == null && e.q.isEmpty) {
      e.dir = dx.abs() > dy.abs()
          ? (dx < 0 ? 'left' : 'right')
          : (dy < 0 ? 'up' : 'down');
    }
  }
}
