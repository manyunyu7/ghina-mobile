// Magang ("minion"): cosmetic NPCs that fill the office. NOT agents: they never
// call Claude, Codex or any model, it is all simulation on this device.
// Identity (name + look) and count come from the daemon (`minions` in the office
// payload, GET /api/offices/:id/minions, live event {t:'minions'}); movement is
// decided here. Ported from the web director (web/js/minions.js): same
// activities, same couriers for REAL work (dm, cards, meetings, processes,
// files, wiki, permission waits), same priorities (they always give way to real
// agents and the owner).
part of 'floor_sim.dart';

const kMinionMax = 30;

/// Auto mode: quiet at night, fewer while many real agents work.
int minionAutoCount(int base, int working, DateTime t) {
  if (base <= 0) return 0;
  final h = t.hour + t.minute / 60;
  final f = h >= 22 || h < 5.5
      ? .25
      : h >= 20
      ? .5
      : h >= 18
      ? .8
      : 1.0;
  final int n = (base * f + .0001).floor() - math.max<int>(0, working - 2);
  return math.max<int>(1, math.min<int>(base, n));
}

/// Board changes -> courier jobs. [prev]/[next]: cards `{id, col, who}`; col 4 = Selesai.
List<({String kind, Map<String, dynamic> card})> minionCardJobs(
  List<Map<String, dynamic>> prev,
  List<Map<String, dynamic>> next,
) {
  final was = {for (final c in prev) '${c['id']}': c};
  final out = <({String kind, Map<String, dynamic> card})>[];
  for (final c in next) {
    final o = was['${c['id']}'];
    final col = (c['col'] as num?)?.toInt() ?? 0;
    if (o == null) {
      out.add((kind: col >= 4 ? 'done' : 'baru', card: c));
      continue;
    }
    final ocol = (o['col'] as num?)?.toInt() ?? 0;
    if (ocol != col && col >= 4) {
      out.add((kind: 'done', card: c));
    } else if (o['who'] != c['who'] && c['who'] != null) {
      out.add((kind: 'tugas', card: c));
    } else if (ocol != col && c['who'] != null) {
      out.add((kind: 'pindah', card: c));
    }
  }
  return out;
}

class MinionState {
  /// idle | act | do | job | leave
  String state = 'idle';
  double nextAt = 0, born = 0, since = 0, until = 0;
  int n = 0;
  String? last, stand;
  MinionJob? job;
  FloorDesk? desk;
  List<(String, double, double)> chain = [];

  // room scene (floor_scenes.dart)
  SceneRun? run;
  int ix = 0, progress = 0, sayIx = 0;
  int? barrier;
  Map<String, dynamic>? step;
  bool onSpot = false, holding = false, doorWait = false;
  double stepAt = 0, stepEnd = 0, syncSince = 0, sayUntil = 0, sayNext = 0, doorUntil = 0, greetAt = -999;
  List<String> sayList = const [];
  String? lastScene;
}

/// One leg of a courier job. [carry]: null = keep, '' = put down, else the prop.
class MinionStep {
  const MinionStep(this.to, {this.carry, this.wait = 0, this.speed = 0});
  final String to;
  final String? carry;
  final double wait, speed;
}

class MinionJob {
  MinionJob(
    this.key,
    this.glyph,
    this.steps, {
    this.cool = 20,
    this.cond,
  });
  final String key, glyph;
  final List<MinionStep> steps;
  final double cool;

  /// false ends a long wait early (the agent got its permission).
  final bool Function()? cond;
  double at = 0;
}

class MinionStand {
  MinionStand(this.kind, this.tx, this.ty) : key = '$kind:$tx,$ty';
  final String kind, key;
  final int tx, ty;
}

class MinionHub {
  Map<String, dynamic>? view;
  bool first = true;
  final spawnQ = <Map<String, dynamic>>[];
  final pending = <MinionJob>[];
  final recent = <String, double>{};
  final seenDm = <String>{};
  final procSt = <String, String>{};
  Map<String, ({bool rapat, bool wait, bool deploy})>? known;
  Map<String, List<MinionStand>>? stands;
  final bocc = <String, String>{};
  final deskBy = <FloorDesk, String>{};
  final pathCache = <int, List<ui.Offset>>{};
  int pathLeft = 2;
  double nextTick = 0, lastAuto = 0, spawnAt = 0;

  /// Room scenes (scenes.json) and the ones running now, cooldown per scene id.
  List<FurnScene> scenes = const [];
  final runs = <SceneRun>[];
  final sceneCool = <String, double>{};
  final reach = <String, bool>{};
}

// What a stand-in-front-of item means (builtin sprites of the generated rooms).
const _builtin = {
  'counter': 'coffee',
  'water': 'water',
  'fridge': 'snack',
  'vending': 'snack',
  'printer': 'print',
  'shelf': 'read',
  'cabinet': 'file',
  'wbstand': 'whiteboard',
};

// affordance, weight, dwell lo/hi (seconds)
const _acts = <(String, double, double, double)>[
  ('coffee', 3, 12, 25),
  ('print', 2.2, 8, 14),
  ('plant', 2, 10, 20),
  ('water', 1.4, 6, 12),
  ('snack', 1, 8, 15),
  ('read', 2, 15, 30),
  ('whiteboard', 1.5, 15, 30),
  ('exercise', 1, 20, 40),
  ('type', 3, 30, 70),
  ('think', 1, 10, 20),
  ('phone', 1, 10, 20),
  ('eat', .5, 20, 40),
  ('sofa', .7, 25, 60),
  ('play', .6, 15, 35),
  ('music', .5, 15, 35),
  ('clean', 1.6, 0, 0),
  ('errand', 2.6, 0, 0),
];
final _arsip = RegExp('rak|lemari|arsip|berkas|katalog');
const _props = ['folder', 'box', 'paper', 'mail', 'book'];
final _deploy = RegExp(r'\b(deploy|rsync|scp|kubectl|docker push|pm2 restart)\b');

extension FloorMinions on FloorSim {
  double _rr(double a, double b) => a + _rnd.nextDouble() * (b - a);
  Iterable<FloorEnt> get _mins => ents.values.where((e) => e.minion);

  // ------------------------------------------------------------- public

  /// Number of Magang on the floor (not counting those walking out).
  int get minionCount => _mins.where((e) => e.mn?.state != 'leave').length;

  /// Config from the daemon. Idempotent: only the difference is acted on.
  void minionsApply(Map<String, dynamic>? v) {
    if (v == null) return;
    mh.view = v;
    mh.lastAuto = now;
    _reconcile();
  }

  /// The world was replaced (furniture edited): forget places tied to the old one.
  void minionsWorldChanged() {
    mh.stands = null;
    mh.bocc.clear();
    mh.deskBy.clear();
    mh.pathCache.clear();
    mh.reach.clear();
    for (final r in [...mh.runs]) {
      _abortScene(r);
    }
    for (final e in _mins) {
      e.mn?.stand = null;
      e.mn?.desk = null;
    }
  }

  /// Sends one Magang home (walks to the lift, then gone).
  void minionLeave(String id, [String why = 'Pamit']) {
    final e = ents[id];
    if (e == null || !e.minion || e.mn!.state == 'leave') return;
    _mnStop(e);
    e.mn!.state = 'leave';
    e.bubble = why;
    e.speed = 70;
    e.q.addAll([
      FloorAct.go(world.elevatorTile.tx, world.elevatorTile.ty),
      FloorAct.call(() {
        elevatorUntil = now + 1.5;
        e.fade = true;
        e.bubble = '';
      }),
    ]);
  }

  /// Live events -> courier jobs.
  void minionsLive(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'dm':
        final item = _map(m['item']);
        final id = '${item?['id']}';
        final from = '${m['from']}', to = '${m['to']}';
        if (m['from'] == null || m['to'] == null || from == to) return;
        if (!mh.seenDm.add(id)) return;
        if (mh.seenDm.length > 300) mh.seenDm.remove(mh.seenDm.first);
        _enqueue(
          MinionJob('dm:$id', '✉', [
            MinionStep('desk:$from', carry: 'mail', wait: .5),
            MinionStep('desk:$to', carry: '', wait: 1.5),
          ], cool: 6),
        );
      case 'attachment':
        final item = _map(m['item']);
        if (item != null) _parcel('${m['sid']}', '${item['id']}');
      case 'show':
        final item = _map(m['item']);
        if (item != null) _parcel('${item['sid']}', '${item['id']}');
      case 'proc':
        final p = _map(m['proc']);
        if (p == null) {
          if (m['removed'] != null) mh.procSt.remove('${m['removed']}');
          return;
        }
        final id = '${p['id']}', st = '${p['status']}', was = mh.procSt[id];
        mh.procSt[id] = st;
        if (was != null &&
            was != st &&
            (st == 'gagal' || (was == 'jalan' && st != 'jalan'))) {
          _enqueue(_serverJob('$id:$st'));
        }
      case 'changed':
        if (m['what'] == 'wiki' && m['slug'] != null) {
          final w = sessions
              .where((s) => s['status'] == 'working' && s['role'] != null)
              .firstOrNull;
          _enqueue(
            MinionJob('wiki:${m['slug']}', '📖', [
              MinionStep(
                w != null ? 'desk:${w['role']}' : 'mgr',
                carry: 'book',
                wait: .4,
              ),
              const MinionStep('room:lib', carry: '', wait: 2.2),
            ], cool: 15),
          );
        }
    }
  }

  /// Board refetched: the card lists before and after.
  void minionsCards(
    List<Map<String, dynamic>> prev,
    List<Map<String, dynamic>> next,
  ) {
    for (final d in minionCardJobs(prev, next).take(6)) {
      final c = d.card, who = c['who'];
      if (d.kind == 'done') {
        _enqueue(
          MinionJob('kartu-selesai:${c['id']}', '✓', [
            MinionStep(who != null ? 'desk:$who' : 'board', carry: 'folder', wait: .4),
            const MinionStep('archive', carry: '', wait: 1.8),
          ]),
        );
      } else {
        _enqueue(
          MinionJob('kartu:${c['id']}:${d.kind}', '📋', [
            MinionStep(d.kind == 'baru' ? 'board' : 'mgr', carry: 'folder', wait: .5),
            MinionStep(who != null ? 'side:$who' : 'board', carry: '', wait: 1.8),
          ]),
        );
      }
    }
  }

  /// Session list changed (called from sync): new meeting, agent waiting for
  /// permission, deploy-like command.
  void minionsSessions(List<Map<String, dynamic>> list) {
    final cur = <String, ({bool rapat, bool wait, bool deploy})>{};
    for (final s in list) {
      final tool = _map(s['tool']);
      final label = tool == null ? '' : '${tool['name']} ${tool['label'] ?? ''}';
      cur['${s['sid']}'] = (
        rapat: s['kind'] == 'rapat' && s['status'] != 'ended',
        wait: s['waiting'] != null,
        deploy: s['status'] == 'working' && _deploy.hasMatch(label),
      );
    }
    final known = mh.known;
    if (known != null) {
      for (final s in list) {
        final sid = '${s['sid']}', c = cur[sid]!, o = known[sid];
        if (c.rapat && !(o?.rapat ?? false)) {
          for (final n in [1, 2]) {
            _enqueue(
              MinionJob('rapat:$sid:$n', '☕', [
                const MinionStep('coffee', carry: 'cup', wait: .5),
                const MinionStep('room:meeting', carry: '', wait: 2.4),
              ], cool: 60),
            );
          }
        }
        if (c.wait && !(o?.wait ?? false) && s['role'] != null) {
          _enqueue(
            MinionJob(
              'izin:$sid',
              '?',
              [MinionStep('side:${s['role']}', carry: 'sign', wait: 60)],
              cool: 60,
              cond: () => sessions.any(
                (x) => x['sid'] == sid && x['waiting'] != null,
              ),
            ),
          );
        }
        if (c.deploy && !(o?.deploy ?? false)) _enqueue(_serverJob('deploy:$sid'));
      }
    }
    mh.known = cur;
  }

  // ------------------------------------------------------------ lifecycle

  List<Map<String, dynamic>> _wanted() {
    final v = mh.view;
    if (v == null) return const [];
    final base = [
      for (final m in (v['minions'] as List? ?? const []))
        if (m is Map<String, dynamic>) m,
    ];
    final count = (v['count'] as num?)?.toInt() ?? base.length;
    if (v['auto'] != true) return base.take(count).toList();
    final working = sessions
        .where((s) => s['status'] == 'working' && s['kind'] != 'rapat')
        .length;
    return base.take(minionAutoCount(count, working, clock())).toList();
  }

  void _reconcile() {
    final want = _wanted(), ids = {for (final w in want) '${w['id']}'};
    for (final e in _mins.toList()) {
      if (!ids.contains(e.id) && e.mn!.state != 'leave') minionLeave(e.id);
    }
    for (final w in want) {
      final id = '${w['id']}';
      if (ents.containsKey(id) || mh.spawnQ.any((x) => x['id'] == id)) continue;
      if (mh.first) {
        _mnSpawn(w, instant: true);
      } else {
        mh.spawnQ.add(w);
      }
    }
    mh.spawnQ.removeWhere((x) => !ids.contains('${x['id']}'));
    mh.first = false;
  }

  void _mnSpawn(Map<String, dynamic> mi, {required bool instant}) {
    final id = '${mi['id']}';
    final e = _spawn(
      id,
      Look.fromRole(asMapOrEmpty(mi['look'])),
      atElevator: !instant,
    );
    e
      ..minion = true
      ..name = '${mi['name']}'
      ..mn = (MinionState()
        ..nextAt = now + _rr(.8, 4)
        ..born = now
        ..n = hashStr(id) % 10);
    if (instant) {
      final rooms = world.rooms
          .where((r) => r.kind != 'zone' && r.kind != 'toilet')
          .toList();
      // a room the lift can actually reach (the plan may hold shut-in rooms)
      FloorTile? sp;
      for (var i = 0; i < 10 && rooms.isNotEmpty && sp == null; i++) {
        final t = world.randomSpot(rooms[_rnd.nextInt(rooms.length)].id);
        final el = world.elevatorTile;
        if (t != null && world.findPath(el.tx, el.ty, t.tx, t.ty) != null) {
          sp = t;
        }
      }
      if (sp != null) {
        e
          ..x = sp.tx * _t + 4
          ..y = sp.ty * _t + 7;
      }
      e.mn!.nextAt = now + _rr(.1, 3.5);
    }
  }

  // --------------------------------------------------------------- places

  Map<String, List<MinionStand>> _stands() {
    final cached = mh.stands;
    if (cached != null) return cached;
    final m = <String, List<MinionStand>>{};
    for (final it in world.items) {
      final k = it.spr.k ?? '';
      final kind = _builtin[k] ?? (k.startsWith('plant') ? 'plant' : null);
      if (kind == null) continue;
      for (var dy = 0; dy < 2; dy++) {
        final row = it.ty + it.fh + dy;
        final cols = [for (var i = 0; i < it.fw; i++) it.tx + i]
          ..sort(
            (a, b) => (a - it.tx - it.fw / 2).abs().compareTo(
              (b - it.tx - it.fw / 2).abs(),
            ),
          );
        final tx = cols
            .where((x) => world.walkable(x, row) && !world.seat.contains(row * world.w + x))
            .firstOrNull;
        if (tx != null) {
          (m[kind] ??= []).add(MinionStand(kind, tx, row));
          break;
        }
      }
    }
    return mh.stands = m;
  }

  FloorTile? _nearest(Iterable<FloorTile> list, FloorTile from) {
    FloorTile? best;
    var bd = 1 << 30;
    for (final t in list) {
      final d = (t.tx - from.tx).abs() + (t.ty - from.ty).abs();
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    return best;
  }

  /// Walkable activity tiles of an affordance (catalog spots + builtin stands).
  List<FloorTile> _tilesFor(String aff, {RegExp? only}) => [
    for (final sp in world.spotsByAff[aff] ?? const <FloorSpot>[])
      if (only == null || only.hasMatch(sp.furn.def.id)) FloorTile(sp.tx, sp.ty),
    if (only == null)
      for (final s in _stands()[aff] ?? const <MinionStand>[]) FloorTile(s.tx, s.ty),
  ];

  FloorTile? _roomTile(String id) {
    final r = world.room(id) ?? world.rooms.where((x) => x.kind == id).firstOrNull;
    return r == null ? null : world.randomSpot(r.id);
  }

  FloorTile? _deskTile(String? roleId, [int side = 0]) {
    if (roleId == null) return null;
    final d = world.desks.where((x) => x.role == roleId).firstOrNull;
    if (d != null) return FloorTile(d.frontTx + side, d.frontTy);
    final r = roles.where((x) => x['id'] == roleId).firstOrNull;
    return r == null ? null : _roomTile('${world.resolveRoom(r['room']) ?? r['room']}');
  }

  String? get _mgrId =>
      roles.where((r) => r['isMgr'] == true).firstOrNull?['id'] as String?;

  FloorTile? _resolve(String spec, FloorTile from) {
    final i = spec.indexOf(':');
    final k = i < 0 ? spec : spec.substring(0, i), arg = i < 0 ? '' : spec.substring(i + 1);
    switch (k) {
      case 'desk':
        return _deskTile(arg) ?? _deskTile(_mgrId);
      case 'side':
        return _deskTile(arg, 1) ?? _deskTile(_mgrId, 1);
      case 'mgr':
        return _deskTile(_mgrId);
      case 'room':
        return _roomTile(arg);
      case 'lift':
        return world.elevatorTile;
      case 'lobby':
        return _roomTile('lobby') ?? world.elevatorTile;
      case 'archive':
        return _nearest([
              ..._tilesFor('read', only: _arsip),
              for (final s in _stands()['file'] ?? const <MinionStand>[]) FloorTile(s.tx, s.ty),
            ], from) ??
            _nearest(_tilesFor('read'), from) ??
            _roomTile('lib');
      case 'server':
        return world.serverDoor() ?? _roomTile('server');
      case 'board':
        return _nearest(_tilesFor('whiteboard'), from) ?? _deskTile(_mgrId);
      default:
        return _nearest(_tilesFor(k), from);
    }
  }

  // ---------------------------------------------------------------- paths

  ({bool deferred, List<ui.Offset>? path}) _minionPath(int sx, int sy, int gx, int gy) {
    final key = ((sx * 4099 + sy) * 4099 + gx) * 4099 + gy;
    final hit = mh.pathCache[key];
    if (hit != null) return (deferred: false, path: [...hit]);
    if (mh.pathLeft <= 0) return (deferred: true, path: null);
    mh.pathLeft--;
    final p = world.findPath(sx, sy, gx, gy);
    if (mh.pathCache.length > 600) mh.pathCache.clear();
    if (p != null) mh.pathCache[key] = p;
    return (deferred: false, path: p == null ? null : [...p]);
  }

  // ----------------------------------------------------------- movement

  FloorTile _tileOf(FloorEnt e) => FloorTile((e.x / _t).floor(), (e.y / _t).floor());

  void _mnStop(FloorEnt e) {
    _endAct(e);
    _mnFree(e);
    e
      ..q.clear()
      ..cur = null
      ..path = []
      ..pose = null
      ..carry = null
      ..bubble = ''
      ..speed = 0
      ..mode = 'stand'
      ..dir = 'down';
    e.mn!
      ..job = null
      ..chain = []
      ..run = null
      ..step = null
      ..onSpot = false
      ..holding = false
      ..doorWait = false
      ..barrier = null
      ..sayUntil = 0;
  }

  void _mnFree(FloorEnt e) {
    final st = e.mn!;
    final s = st.stand;
    if (s != null) {
      if (mh.bocc[s] == e.id) mh.bocc.remove(s);
      st.stand = null;
    }
    final d = st.desk;
    if (d != null) {
      if (mh.deskBy[d] == e.id) mh.deskBy.remove(d);
      st.desk = null;
    }
  }

  void _mnIdle(FloorEnt e, [double? sec]) {
    e.mn!
      ..state = 'idle'
      ..nextAt = now + (sec ?? _rr(.4, 2.2));
  }

  /// A real agent or the owner takes a spot a Magang holds: they step away from it.
  void _evictMinion(String key, String by) {
    final id = reserved[key];
    if (id == null || id == by) return;
    final m = ents[id];
    if (m == null || !m.minion) return;
    _endAct(m);
    reserved.remove(key);
  }

  // ---------------------------------------------------------------- jobs

  MinionJob _serverJob(String key) => MinionJob('server:$key', '!', [
    const MinionStep('server', speed: 92, wait: 4.2),
    const MinionStep('lobby', speed: 56),
  ], cool: 30);

  void _parcel(String sid, String key) {
    final role = sessions.where((s) => s['sid'] == sid).firstOrNull?['role'];
    _enqueue(
      MinionJob('paket:$key', '📦', [
        MinionStep(role != null ? 'desk:$role' : 'mgr', carry: 'box', wait: .4),
        const MinionStep('lobby', carry: '', wait: 2.2),
      ]),
    );
  }

  void _enqueue(MinionJob job) {
    final last = mh.recent[job.key];
    if (last != null && last > now - job.cool) return;
    mh.recent[job.key] = now;
    if (mh.recent.length > 200) mh.recent.removeWhere((_, t) => t < now - 120);
    mh.pending.removeWhere((p) => p.key == job.key);
    job.at = now;
    mh.pending.add(job);
    while (mh.pending.length > 10) {
      mh.pending.removeAt(0); // too many: the oldest are skipped
    }
  }

  void _dispatch() {
    if (mh.pending.isEmpty) return;
    mh.pending.removeWhere((p) => now - p.at > 30);
    for (final job in [...mh.pending]) {
      final free = _mins
          .where(
            (m) =>
                (const {'idle', 'act', 'do'}.contains(m.mn!.state) ||
                    // an errand or sweeping is only filler: real work takes over
                    (m.mn!.state == 'job' &&
                        (m.mn!.job?.key == 'errand' || m.mn!.job?.key == 'clean'))) &&
                m.alpha >= 1 &&
                !m.fade &&
                now - m.mn!.born > 1.5,
          )
          .toList();
      if (free.isEmpty) {
        // real work beats a scene: the nearest scene actor drops it
        final scene = _mins.where((m) => m.mn!.state == 'scene' && m.alpha >= 1 && !m.fade).toList();
        if (scene.isEmpty) return;
        final r = scene.first.mn!.run;
        if (r != null) _abortScene(r);
        free.addAll(
          _mins.where((m) => const {'idle', 'act', 'do'}.contains(m.mn!.state) && m.alpha >= 1 && !m.fade),
        );
        if (free.isEmpty) return;
      }
      final to = _resolve(job.steps.first.to, const FloorTile(0, 0)) ?? const FloorTile(0, 0);
      free.sort(
        (a, b) =>
            ((a.x / _t - to.tx).abs() + (a.y / _t - to.ty).abs()).compareTo(
              (b.x / _t - to.tx).abs() + (b.y / _t - to.ty).abs(),
            ),
      );
      mh.pending.remove(job);
      _startJob(free.first, job);
    }
  }

  void _startJob(FloorEnt e, MinionJob job) {
    _mnStop(e);
    e.mn!
      ..state = 'job'
      ..job = job;
    e.bubble = job.glyph;
    final here = _tileOf(e);
    for (final s in job.steps) {
      final to = _resolve(s.to, here);
      if (to == null) continue;
      e.q.add(FloorAct.call(() => e.speed = s.speed));
      e.q.add(FloorAct.go(to.tx, to.ty));
      e.q.add(
        FloorAct.call(() {
          if (s.carry != null) e.carry = s.carry!.isEmpty ? null : s.carry;
        }),
      );
      if (s.wait > 0) e.q.add(FloorAct.wait((s.wait * 1000).round()));
    }
    if (e.q.isEmpty) {
      _mnStop(e);
      _mnIdle(e, .5);
    }
  }

  // ------------------------------------------------------------ idle life

  bool get _lunch {
    final t = clock();
    final h = t.hour + t.minute / 60;
    return h >= 11.5 && h < 13.5;
  }

  void _planIdle(FloorEnt e) {
    final st = e.mn!, here = _tileOf(e), hour = clock().hour;
    if (mh.scenes.any((s) => s.when == 'prayer') &&
        _prayerNow != null &&
        _startScene(e, prayerOnly: true)) {
      return;
    }
    final b = behaviors;
    if (b != null &&
        world.spotsByAff.containsKey('wudhu') &&
        world.spotsByAff.containsKey('pray') &&
        st.n < 7) {
      final pr = prayer?.active(clock(), b.prayerWindowMin, b.prayerNames);
      final key = pr == null ? null : '${FloorPrayer.dayKey(clock())}-$pr';
      if (key != null && e.prayed.add(key)) {
        st.chain = [('pray', 40, 70)];
        if (_spotAct(e, 'wudhu', 15, 25)) return;
        st.chain = [];
      }
    }
    if (mh.scenes.isNotEmpty && _rnd.nextDouble() < .75 && _startScene(e)) return;
    final opts = [
      for (final o in _acts)
        (
          o.$1,
          o.$1 == 'eat' && _lunch
              ? 5.0
              : o.$1 == 'exercise' && (hour < 6 || hour > 19)
              ? .3
              : o.$2,
          o.$3,
          o.$4,
        ),
    ];
    while (opts.isNotEmpty) {
      var total = 0.0;
      for (final o in opts) {
        total += o.$2;
      }
      var r = _rnd.nextDouble() * total;
      var pick = opts.last;
      for (final o in opts) {
        r -= o.$2;
        if (r <= 0) {
          pick = o;
          break;
        }
      }
      opts.remove(pick);
      final a = pick.$1;
      if (a == st.last && opts.isNotEmpty) continue;
      if (a == 'errand') {
        st.last = a;
        return _errand(e);
      }
      if (a == 'clean') {
        st.last = a;
        return _clean(e);
      }
      if (a == 'type' && _sitDesk(e, pick.$3, pick.$4)) {
        st.last = a;
        return;
      }
      if (world.spotsByAff.containsKey(a) && _spotAct(e, a, pick.$3, pick.$4)) {
        st.last = a;
        return;
      }
      if (_standAt(e, a, pick.$3, pick.$4, here)) {
        st.last = a;
        return;
      }
    }
    _errand(e);
  }

  /// Catalog furniture: same spots and poses as the agents (floor_activity).
  bool _spotAct(FloorEnt e, String aff, double lo, double hi) {
    final sp = _findSpot(e, aff);
    if (sp == null) return false;
    final ap = world.approachFor(sp.tx, sp.ty, sp.face);
    if (ap == null) return false;
    _endAct(e);
    final dwell = lo + _rnd.nextDouble() * (hi - lo);
    final a = FloorActState('magang', now)
      ..aff = aff
      ..spot = sp
      ..deadline = now + 90;
    e.act = a;
    reserved[sp.key] = e.id;
    e
      ..q.clear()
      ..cur = null
      ..path = []
      ..speed = 0;
    final cx = (e.x / _t).floor(), cy = (e.y / _t).floor();
    if (ap.tx != cx || ap.ty != cy) e.q.add(FloorAct.go(ap.tx, ap.ty));
    if (ap.tx != sp.tx || ap.ty != sp.ty) e.q.add(FloorAct.slide(sp.x, sp.y));
    e.q.add(FloorAct.call(() => _arrive(e, sp, dwell)));
    e.mn!
      ..state = 'act'
      ..since = now;
    return true;
  }

  /// Builtin counter / water / fridge / printer / shelf / whiteboard / plant: stand in front and use it.
  bool _standAt(FloorEnt e, String aff, double lo, double hi, FloorTile here) {
    final list = (_stands()[aff] ?? const <MinionStand>[])
        .where((s) => !mh.bocc.containsKey(s.key))
        .toList();
    if (list.isEmpty) return false;
    list.sort(
      (a, b) =>
          ((a.tx - here.tx).abs() + (a.ty - here.ty).abs() + (_rnd.nextDouble() - .5) * 14)
              .compareTo((b.tx - here.tx).abs() + (b.ty - here.ty).abs() + (_rnd.nextDouble() - .5) * 14),
    );
    final s = list.first, st = e.mn!;
    mh.bocc[s.key] = e.id;
    st
      ..stand = s.key
      ..state = 'act'
      ..since = now;
    e
      ..q.clear()
      ..cur = null
      ..path = []
      ..speed = 0;
    e.q
      ..add(FloorAct.go(s.tx, s.ty))
      ..add(
        FloorAct.call(() {
          if (!ents.containsKey(e.id) || st.stand != s.key) return;
          final reading = aff == 'read' || aff == 'file';
          e
            ..x = s.tx * _t + 4
            ..y = s.ty * _t + 7
            ..dir = 'up'
            ..mode = 'stand'
            ..pose = FloorPose(reading ? 'read' : 'stand', 'up', reading ? 'read' : aff, now);
          st
            ..state = 'do'
            ..until = now + (lo > 0 ? _rr(lo, hi) : _rr(8, 15));
        }),
      );
    return true;
  }

  /// An empty desk: sit and type (stands up the moment an agent is assigned to it).
  bool _sitDesk(FloorEnt e, double lo, double hi) {
    final free = world.desks
        .where((d) => d.occ == null && (d.spare || d.role == null) && !mh.deskBy.containsKey(d))
        .toList();
    if (free.isEmpty) return false;
    final here = _tileOf(e);
    free.sort(
      (a, b) =>
          ((a.seatTx - here.tx).abs() + (a.seatTy - here.ty).abs() + (_rnd.nextDouble() - .5) * 14)
              .compareTo((b.seatTx - here.tx).abs() + (b.seatTy - here.ty).abs() + (_rnd.nextDouble() - .5) * 14),
    );
    final d = free.first, st = e.mn!;
    mh.deskBy[d] = e.id;
    st
      ..desk = d
      ..state = 'act'
      ..since = now;
    e
      ..q.clear()
      ..cur = null
      ..path = []
      ..speed = 0;
    e.q
      ..add(FloorAct.go(d.seatTx, d.seatTy))
      ..add(
        FloorAct.call(() {
          if (!ents.containsKey(e.id) || st.desk != d || d.occ != null) return;
          e
            ..x = d.seatX
            ..y = d.seatY - 1
            ..dir = d.facing
            ..mode = 'stand'
            ..pose = FloorPose('sit', d.facing, 'type', now);
          st
            ..state = 'do'
            ..until = now + _rr(lo, hi);
        }),
      );
    return true;
  }

  List<FloorRoom> get _walkRooms =>
      world.rooms.where((r) => r.kind != 'zone' && r.kind != 'toilet').toList();

  /// Walk to another room carrying something, linger, come back later.
  void _errand(FloorEnt e) {
    final rooms = _walkRooms;
    if (rooms.isEmpty) return _mnIdle(e, 3);
    final here = _tileOf(e);
    final cur = rooms
        .where((r) => here.tx >= r.x && here.tx < r.x + r.w && here.ty >= r.y && here.ty < r.y + r.h)
        .firstOrNull;
    final others = [for (final r in rooms) if (r != cur) r];
    final pool = others.isEmpty ? rooms : others;
    final to = world.randomSpot(pool[_rnd.nextInt(pool.length)].id);
    if (to == null) return _mnIdle(e, 3);
    final st = e.mn!;
    st
      ..state = 'job'
      ..job = MinionJob('errand', '', const [])
      ..since = now;
    e
      ..carry = _props[_rnd.nextInt(_props.length)]
      ..speed = 0;
    e.q
      ..add(FloorAct.go(to.tx, to.ty))
      ..add(FloorAct.wait((_rr(1.2, 3.5) * 1000).round()))
      ..add(FloorAct.call(() => e.carry = null));
  }

  /// Sweep a room with a broom: a few waypoints.
  void _clean(FloorEnt e) {
    final rooms = _walkRooms;
    if (rooms.isEmpty) return _mnIdle(e, 3);
    final r = rooms[_rnd.nextInt(rooms.length)];
    final st = e.mn!;
    st
      ..state = 'job'
      ..job = MinionJob('clean', '', const [])
      ..since = now;
    e
      ..carry = 'broom'
      ..speed = 0;
    for (var i = 0; i < 4; i++) {
      final p = world.randomSpot(r.id);
      if (p != null) e.q.add(FloorAct.go(p.tx, p.ty));
    }
    e.q.add(FloorAct.call(() => e.carry = null));
  }

  // ----------------------------------------------------------------- tick

  void _minionTick() {
    final v = mh.view;
    if (v != null && v['auto'] == true && now - mh.lastAuto > 5) {
      mh.lastAuto = now;
      _reconcile();
    }
    if (mh.spawnQ.isNotEmpty &&
        now - mh.spawnAt > .7 &&
        _mins.length < kMinionMax) {
      mh.spawnAt = now;
      _mnSpawn(mh.spawnQ.removeAt(0), instant: false);
    }
    for (final e in _mins.toList()) {
      final st = e.mn!;
      if (e.fade || st.state == 'leave') continue;
      if (st.desk?.occ != null) {
        _mnStop(e); // an agent took the desk
        _mnIdle(e, .3);
        continue;
      }
      if (st.sayUntil > 0 && now >= st.sayUntil && st.state != 'scene') {
        st.sayUntil = 0;
        if (st.state != 'job') e.bubble = '';
      }
      _greetOwner(e);
      switch (st.state) {
        case 'idle':
          if (e.cur == null && e.q.isEmpty && now >= st.nextAt) _planIdle(e);
        case 'act':
          final a = e.act;
          if (a == null) {
            if (st.stand == null && st.desk == null) {
              _mnIdle(e); // the spot was taken back (an agent needs it)
            } else if (e.cur == null && e.q.isEmpty && now - st.since > 4) {
              _mnFree(e);
              _mnIdle(e);
            }
          } else if (a.failed) {
            if (a.spot != null) e.bad.add(a.spot!.key);
            _mnStop(e);
            _mnIdle(e);
          } else if (a.arrived && a.until != null && now >= a.until!) {
            _endAct(e);
            if (st.chain.isNotEmpty) {
              final c = st.chain.removeAt(0);
              if (!_spotAct(e, c.$1, c.$2, c.$3)) _mnIdle(e);
            } else {
              _mnIdle(e);
            }
          } else if (!a.arrived && e.cur == null && e.q.isEmpty && now - st.since > 2.5) {
            _mnStop(e);
            _mnIdle(e);
          }
        case 'do':
          if (now >= st.until) {
            if (st.desk != null) e.y += 1;
            _mnFree(e);
            e
              ..pose = null
              ..mode = 'stand';
            _mnIdle(e);
          }
        case 'scene':
          break; // driven by _sceneTick
        case 'job':
          final c = st.job?.cond;
          if (c != null && e.cur != null && e.cur!.kind == 'wait' && !c()) {
            e.cur!.startedAt = -1e9; // the wait is over
          }
          if (e.cur == null && e.q.isEmpty) {
            e
              ..carry = null
              ..bubble = ''
              ..speed = 0;
            st.job = null;
            _mnIdle(e, 1.5);
          }
      }
    }
    _sceneTick();
    _dispatch();
  }
}

Map<String, dynamic> asMapOrEmpty(Object? v) =>
    v is Map<String, dynamic> ? v : const {};

Map<String, dynamic>? asMapOrNull(Object? v) =>
    v is Map<String, dynamic> ? v : null;
