// Furniture activities: what a session's character does with the catalog
// furniture (coffee, sofa, nap, prayer, whiteboard...), driven by the
// behaviour rules from /api/furniture. Same rules and order as the web
// renderer: the first rule whose `when` matches (and passes `chance`) wins;
// its picks are tried by weight until one has a free spot.
part of 'floor_sim.dart';

/// How a character is drawn while using a spot.
class FloorPose {
  const FloorPose(
    this.kind,
    this.face,
    this.aff,
    this.since, {
    this.sortY,
    this.uid,
  });

  /// stand | sit | sleep | pray | play | exercise | read
  final String kind, face, aff;
  final double since;

  /// Depth override: spots on the item itself are drawn right after it.
  final double? sortY;
  final String? uid;
}

class FloorActState {
  FloorActState(this.ruleId, this.startedAt);
  final String ruleId;
  final double startedAt;
  String aff = '';

  /// Set on arrival (spot activities) or at once (desk activities).
  double? until;
  double deadline = double.infinity;
  FloorSpot? spot;
  bool arrived = false, failed = false, guest = false;

  /// Remaining steps after the current one (prayer: wudhu, then pray).
  List<FurnStep> steps = [];

  /// Chat: id of the other character.
  String? partner;
}

class _Ctx {
  _Ctx(
    this.status,
    this.tool,
    this.label,
    this.subagent,
    this.idleSec,
    this.prayer,
  );
  final String status;
  final String? tool, label, prayer;
  final bool subagent;
  final double idleSec;
  bool get thinking => status == 'working' && tool == null;
}

class _Plan {
  _Plan(this.rule, this.steps);
  final FurnRule rule;
  final List<FurnStep> steps;
}

const _deskAffs = {'type', 'think', 'sit'};

const _labels = {
  'coffee': '= ngopi',
  'water': '= minum',
  'snack': '= ngemil',
  'eat': '= makan',
  'sofa': '= santai',
  'sleep': '= tidur',
  'chat': '= ngobrol',
  'game': '= main game',
  'play': '= main',
  'music': '= dengar musik',
  'plant': '= urus tanaman',
  'pray': '= sholat',
  'wudhu': '= wudhu',
  'exercise': '= olahraga',
  'train': '= latihan',
  'read': '= membaca',
  'whiteboard': '= corat-coret papan',
  'print': '= mencetak',
  'phone': '= menelepon',
  'test': '= cek tes',
  'server': '= cek server',
  'meeting': '= diskusi',
  'think': '= berpikir',
  'sit': '= duduk',
};

extension _Activities on FloorSim {
  bool _engineEligible(FloorEnt e) {
    if (!world.hasFurniture || behaviors == null) return false;
    final s = e.s;
    if (s == null || e.isSub || e.leaving || e.fade) return false;
    final st = s['status'];
    if (s['kind'] == 'rapat' || st == 'ended' || st == 'starting') return false;
    final w = _map(s['waiting']);
    if (w != null &&
        _serverish.hasMatch('${w['summary'] ?? ''}') &&
        world.serverDoor() != null)
      return false;
    return true;
  }

  _Ctx _ctx(FloorEnt e) {
    final s = e.s!;
    final tool = _map(s['tool']);
    final status = s['waiting'] != null ? 'waiting' : '${s['status']}';
    final last = DateTime.tryParse('${s['lastSeen'] ?? ''}');
    final idleSec = status == 'idle' && last != null
        ? math.max(0, clock().difference(last).inSeconds).toDouble()
        : 0.0;
    final b = behaviors!;
    var pr = prayer?.active(clock(), b.prayerWindowMin, b.prayerNames);
    if (pr != null && e.prayed.contains('${FloorPrayer.dayKey(clock())}-$pr'))
      pr = null;
    final subs = (s['subs'] as List?) ?? const [];
    return _Ctx(
      status,
      tool == null ? null : '${tool['name']}',
      tool == null ? null : '${tool['label'] ?? ''}',
      subs.any((x) => x is Map && x['status'] == 'working'),
      idleSec,
      pr,
    );
  }

  bool _matches(FurnRule r, _Ctx c, FloorEnt e) {
    final w = r.when;
    if (w['status'] != null && w['status'] != c.status) return false;
    final tools = w['tools'];
    if (tools is List && (c.tool == null || !tools.contains(c.tool)))
      return false;
    if (r.bash != null && (c.label == null || !r.bash!.hasMatch(c.label!)))
      return false;
    if (r.label != null && (c.label == null || !r.label!.hasMatch(c.label!)))
      return false;
    if (w.containsKey('subagent') && (w['subagent'] == true) != c.subagent)
      return false;
    if (w.containsKey('thinking') && (w['thinking'] == true) != c.thinking)
      return false;
    final im = w['idleMin'];
    if (im is List && im.length == 2) {
      final min = c.idleSec / 60;
      final lo = (im[0] as num?)?.toDouble() ?? 0,
          hi = (im[1] as num?)?.toDouble() ?? double.infinity;
      if (min < lo || min >= hi) return false;
    }
    if (w.containsKey('neighbor') &&
        (w['neighbor'] == true) != (_partnerFor(e, c) != null))
      return false;
    if (w.containsKey('prayer') && (w['prayer'] == true) != (c.prayer != null))
      return false;
    return true;
  }

  /// Stable per (character, rule, pick): `chance` is not re-rolled on every
  /// session event, so the activity does not flicker.
  double _roll(FloorEnt e, FurnRule r) =>
      math.Random(hashStr('${e.id}|${r.id}|${e.pickSeq}')).nextDouble();

  Iterable<FurnRule> _applicable(FloorEnt e, _Ctx c) sync* {
    final b = behaviors!;
    for (final r in [...b.rules, ...b.fallback]) {
      if (!_matches(r, c, e)) continue;
      if (r.chance < 1 && _roll(e, r) >= r.chance) continue;
      yield r;
    }
  }

  _Plan? _evaluate(FloorEnt e, _Ctx c) {
    final b = behaviors!;
    for (final r in _applicable(e, c)) {
      if (r.then == 'prayer.steps') {
        final steps = [
          for (final st in b.prayerSteps)
            if (_canDo(e, st.a)) st,
        ];
        if (steps.isNotEmpty) return _Plan(r, steps);
        continue;
      }
      for (final p in weightedOrder(r.picks, _rnd)) {
        if (_canDo(e, p.a)) return _Plan(r, [FurnStep(p.a, r.lo, r.hi)]);
      }
    }
    return null;
  }

  bool _canDo(FloorEnt e, String aff) {
    if (_deskAffs.contains(aff) && e.desk != null) return true;
    if (aff == 'chat' && e.instant) return false;
    if (aff == 'chat' && _partnerFor(e, _ctx(e)) != null) return true;
    return _findSpot(e, aff) != null;
  }

  // ------------------------------------------------------------- spots

  bool _spotFree(FloorEnt e, FloorSpot sp) {
    if (e.bad.contains(sp.key)) return false;
    final owner = reserved[sp.key];
    if (owner == null || owner == e.id) return true;
    final holder = ents[owner];
    if (holder != null && holder.minion) return !e.minion; // a Magang gives way
    return holder?.act?.spot?.key != sp.key; // stale reservation
  }

  FloorSpot? _findSpot(FloorEnt e, String aff) {
    final list = world.spotsByAff[aff];
    if (list == null || list.isEmpty) return null;
    final cands = <(FloorSpot, double)>[];
    for (final sp in list) {
      if (!_spotFree(e, sp) || sp.furn.def.weight <= 0) continue;
      final dx = sp.x - e.x, dy = sp.y - e.y;
      cands.add((sp, math.sqrt(dx * dx + dy * dy)));
    }
    if (cands.isEmpty) return null;
    cands.sort((a, b) => a.$2.compareTo(b.$2));
    final pool = <(FloorSpot, double)>[];
    for (final c in cands) {
      if (pool.isNotEmpty && c.$2 > pool.first.$2 + 140) break;
      if (world.approachFor(c.$1.tx, c.$1.ty, c.$1.face) == null) continue;
      pool.add(c);
      if (pool.length >= 8) break;
    }
    if (pool.isEmpty) return null;
    final total = pool.fold<double>(0, (a, c) => a + c.$1.furn.def.weight);
    var r = _rnd.nextDouble() * total;
    for (final c in pool) {
      r -= c.$1.furn.def.weight;
      if (r < 0) return c.$1;
    }
    return pool.last.$1;
  }

  FloorEnt? _partnerFor(FloorEnt e, _Ctx c) {
    final b = behaviors!;
    if (c.status != 'idle' ||
        c.idleSec < b.chatMinIdleSec ||
        e.act?.partner != null)
      return null;
    final ex = e.x / _t, ey = e.y / _t;
    final myRoom = world.roomAtTile(ex.floor(), ey.floor());
    FloorEnt? best;
    var bd = double.infinity;
    for (final f in ents.values) {
      final fs = f.s;
      if (f == e || f.isSub || fs == null || f.leaving || f.fade) continue;
      if (fs['status'] != 'idle' || fs['waiting'] != null) continue;
      if (f.act?.partner != null ||
          f.mode == 'walk' ||
          f.q.isNotEmpty ||
          f.cur != null)
        continue;
      if (f.act != null && !(f.act!.arrived && f.act!.spot == null)) continue;
      final last = DateTime.tryParse('${fs['lastSeen'] ?? ''}');
      if (last != null && clock().difference(last).inSeconds < b.chatMinIdleSec)
        continue;
      final dx = f.x / _t - ex, dy = f.y / _t - ey;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > b.chatDistance || d >= bd) continue;
      if (world.roomAtTile((f.x / _t).floor(), (f.y / _t).floor()) != myRoom)
        continue;
      best = f;
      bd = d;
    }
    return best;
  }

  // -------------------------------------------------------- life cycle

  /// Ticks one character's activity; false = engine has nothing for them and
  /// the classic desk/room placement applies.
  bool _engineTick(FloorEnt e, {bool force = false}) {
    if (!_engineEligible(e)) {
      if (e.act != null) _endAct(e);
      return false;
    }
    var a = e.act;
    if (a != null) {
      if (a.failed) {
        if (a.spot != null) e.bad.add(a.spot!.key);
        _endAct(e);
        e.nextEval = now + 2;
        a = null;
      } else if (now >= (a.until ?? a.deadline)) {
        if (a.until != null && a.steps.isNotEmpty && _enterNext(e)) return true;
        _endAct(e);
        a = null;
      } else {
        if (!force && now < e.nextEval) return true;
        e.nextEval = now + 1.2;
        if (a.guest) {
          final p = a.partner == null ? null : ents[a.partner!];
          if (p == null ||
              p.act?.partner != e.id ||
              '${e.s?['status']}' != 'idle')
            _endAct(e);
          return e.act != null;
        }
        if (a.partner != null && a.arrived) {
          final p = ents[a.partner!];
          if (p == null || p.act?.partner != e.id) {
            _endAct(e);
            return false;
          }
        }
        if (now - a.startedAt < 5) return true;
        final top = _applicable(e, _ctx(e)).firstOrNull;
        if (top == null || top.id == a.ruleId) return true;
        a = null;
      }
    }
    if (!force && now < e.nextEval) return false;
    e.nextEval = now + 1.2;
    final plan = _evaluate(e, _ctx(e));
    if (plan == null) {
      e.nextEval = now + 3;
      return false;
    }
    return _startAct(e, plan);
  }

  bool _startAct(FloorEnt e, _Plan plan) {
    _endAct(e);
    final a = FloorActState(plan.rule.id, now)..steps = [...plan.steps];
    e.act = a;
    if (plan.rule.then == 'prayer.steps' && prayer != null) {
      final pr = prayer!.active(
        clock(),
        behaviors!.prayerWindowMin,
        behaviors!.prayerNames,
      );
      if (pr != null) e.prayed.add('${FloorPrayer.dayKey(clock())}-$pr');
    }
    if (!_enterNext(e)) {
      _endAct(e);
      e.nextEval = now + 4;
      return false;
    }
    return true;
  }

  bool _enterNext(FloorEnt e) {
    final a = e.act!;
    while (a.steps.isNotEmpty) {
      if (_realize(e, a.steps.removeAt(0))) return true;
    }
    return false;
  }

  bool _realize(FloorEnt e, FurnStep st) {
    final a = e.act!;
    final dwell = st.lo + _rnd.nextDouble() * (st.hi - st.lo);
    _clearSpot(e);
    a
      ..aff = st.a
      ..arrived = false
      ..failed = false
      ..until = null
      ..deadline = now + 70;
    e.actLabel = '';
    if (_deskAffs.contains(st.a) && e.desk != null) {
      if (!(e.mode == 'sit' && e.place == 'desk')) {
        _goPlace(e, const FloorPlace('desk', 'desk'), keepAct: true);
      }
      a
        ..arrived = true
        ..until = now + dwell;
      e.actLabel = _labels[st.a] ?? '';
      return true;
    }
    if (st.a == 'chat') {
      final p = _partnerFor(e, _ctx(e));
      if (p != null && !e.instant) return _chatWith(e, p, dwell);
    }
    final sp = _findSpot(e, st.a);
    if (sp == null) return false;
    final ap = world.approachFor(sp.tx, sp.ty, sp.face);
    if (ap == null) return false;
    _evictMinion(sp.key, e.id);
    reserved[sp.key] = e.id;
    a.spot = sp;
    e.q.clear();
    e.cur = null;
    e.path = [];
    e.place = 'act';
    e.placeAt = now;
    e.goingTo = sp.furn.def.name;
    if (e.instant) {
      e.instant = false;
      e.x = sp.x;
      e.y = sp.y;
      e.mode = 'stand';
      _arrive(e, sp, dwell);
      return true;
    }
    final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
    if (ap.tx != cx || ap.ty != cy) e.q.add(FloorAct.go(ap.tx, ap.ty));
    if (ap.tx != sp.tx || ap.ty != sp.ty) e.q.add(FloorAct.slide(sp.x, sp.y));
    e.q.add(FloorAct.call(() => _arrive(e, sp, dwell)));
    return true;
  }

  void _arrive(FloorEnt e, FloorSpot sp, double dwell) {
    final a = e.act;
    if (a == null || a.spot != sp) return;
    e
      ..x = sp.x
      ..y = sp.y
      ..mode = 'stand'
      ..dir = sp.face
      ..pose = FloorPose(
        sp.pose,
        sp.face,
        a.aff,
        now,
        sortY: sp.onItem ? sp.furn.sortY + .1 : null,
        uid: sp.furn.uid,
      )
      ..actLabel = _labels[a.aff] ?? '';
    a
      ..arrived = true
      ..until = now + dwell;
    activeFurn.add(sp.furn.uid);
  }

  bool _chatWith(FloorEnt e, FloorEnt p, double dwell) {
    final a = e.act!;
    final tile = world.tileBeside(
      (p.x / _t).floor(),
      (p.y / _t).floor(),
      (e.x / _t).floor(),
      (e.y / _t).floor(),
    );
    if (tile == null) return false;
    a.partner = p.id;
    e.q.clear();
    e.cur = null;
    e.path = [];
    e.place = 'act';
    e.placeAt = now;
    e.goingTo = p.name;
    e.q.addAll([
      FloorAct.go(tile.tx, tile.ty),
      FloorAct.call(() {
        final pa = p.act;
        if (e.act != a ||
            p.s == null ||
            p.leaving ||
            (pa != null && pa.partner != null)) {
          a.failed = true;
          return;
        }
        if (pa != null) _endAct(p);
        final dx = p.x - e.x, dy = p.y - e.y;
        e
          ..mode = 'stand'
          ..dir = dx.abs() > dy.abs()
              ? (dx < 0 ? 'left' : 'right')
              : (dy < 0 ? 'up' : 'down')
          ..actLabel = _labels['chat']!;
        a
          ..arrived = true
          ..until = now + dwell;
        final g = FloorActState('chat-guest', now)
          ..aff = 'chat'
          ..guest = true
          ..arrived = true
          ..partner = e.id
          ..until = now + dwell;
        p.act = g;
        p.actLabel = _labels['chat']!;
        if (p.mode != 'sit')
          p.dir = dx.abs() > dy.abs()
              ? (dx < 0 ? 'right' : 'left')
              : (dy < 0 ? 'down' : 'up');
      }),
    ]);
    return true;
  }

  void _clearSpot(FloorEnt e) {
    final sp = e.act?.spot;
    if (sp != null && reserved[sp.key] == e.id) reserved.remove(sp.key);
    final uid = e.pose?.uid;
    e.pose = null;
    if (uid != null && !ents.values.any((x) => x != e && x.pose?.uid == uid))
      activeFurn.remove(uid);
    e.act?.spot = null;
  }

  void _endAct(FloorEnt e) {
    final a = e.act;
    if (a == null && e.pose == null) return;
    final partner = a?.partner;
    _clearSpot(e);
    e
      ..act = null
      ..actLabel = '';
    if (a != null) e.pickSeq++;
    if (partner != null) {
      final p = ents[partner];
      if (p != null && p.act?.guest == true && p.act?.partner == e.id) {
        p.act = null;
        p.actLabel = '';
        p.pickSeq++;
        p.nextEval = now;
      }
    }
  }
}
