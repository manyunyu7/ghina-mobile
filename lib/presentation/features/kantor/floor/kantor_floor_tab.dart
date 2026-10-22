import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../proses/kantor_proses_page.dart';
import 'floor_furniture.dart';
import 'floor_minion_ui.dart';
import 'floor_owner_ui.dart';
import 'floor_painter.dart';
import 'floor_panels.dart';
import 'floor_pixel.dart';
import 'floor_scene.dart';
import 'floor_sim.dart';
import 'floor_world.dart';

const _peekHeight = 84.0;
const _chipBar = 52.0;

/// Native office floor ("Kantor" tab): the pixel plan with live characters,
/// plus inbox, "Suruh [manager]" and announcements in a pull-up panel.
class KantorFloorTab extends ConsumerStatefulWidget {
  const KantorFloorTab({
    super.key,
    required this.officeId,
    @visibleForTesting this.onSim,
  });
  final String officeId;

  /// Called whenever the simulation is (re)built; tests use it to look inside.
  final void Function(FloorSim sim)? onSim;

  @override
  ConsumerState<KantorFloorTab> createState() => _KantorFloorTabState();
}

class _KantorFloorTabState extends ConsumerState<KantorFloorTab>
    with SingleTickerProviderStateMixin {
  final _cam = FloorCamera();
  final _frame = ValueNotifier<int>(0);
  final _mgrCtl = TextEditingController();
  final _newsCtl = TextEditingController();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  Map<String, dynamic>? _office;
  Object? _error;
  var _loading = true;
  FloorWorld? _world;
  FloorSim? _sim;
  ui.Image? _bg;
  final _deskImgs = <FloorDesk, ui.Image>{};
  String? _planSig, _cardsSig, _furnSig, _prayerDay;
  FurnitureCatalog? _catalog;
  FloorPrayer? _prayer;
  var _inbox = <Map<String, dynamic>>[];
  var _news = <Map<String, dynamic>>[];
  String? _selected, _focus;
  var _mgrBusy = false;
  Timer? _bgTimer, _tapTimer, _ownerTimer;

  // owner (own character): control, camera follow and server sync
  var _owner = false;
  var _follow = true;
  Look _ownerLook = kOwnerLook;
  String? _sentSig;
  DateTime _sentAt = DateTime.fromMillisecondsSinceEpoch(0);
  var _sending = false;

  // gesture state
  Offset _startFocal = Offset.zero;
  double _startZ = 1;
  Offset _startCam = Offset.zero;
  int _maxPointers = 0;
  var _moved = false;
  DateTime? _lastTapAt;
  Offset _lastTapPos = Offset.zero;

  // remembered so dispose() can still tell the daemon the owner left (ref is unusable there)
  KantorApi? _lastApi;
  KantorApi? get _api => _lastApi = ref.read(kantorApiProvider);
  String get _id => widget.officeId;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _bgTimer = Timer.periodic(const Duration(minutes: 2), (_) => _rebuildBg());
    _load();
  }

  @override
  void didUpdateWidget(KantorFloorTab old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId) {
      _stopOwner(send: true, api: _api, office: old.officeId);
      _world = null;
      _sim = null;
      _planSig = _cardsSig = _furnSig = null;
      _load();
    }
  }

  @override
  void dispose() {
    _stopOwner(send: true, api: _lastApi, office: _id);
    _sim?.target.dispose();
    _ticker.dispose();
    _bgTimer?.cancel();
    _tapTimer?.cancel();
    _mgrCtl.dispose();
    _newsCtl.dispose();
    _frame.dispose();
    _cam.dispose();
    super.dispose();
  }

  void _onTick(Duration t) {
    final dt = math.min(.05, (t - _last).inMicroseconds / 1e6);
    _last = t;
    _sim?.step(dt);
    final o = _sim?.owner;
    final w = _world;
    if (_owner && _follow && o != null && w != null) {
      _cam
        ..tx = o.x - _cam.visW / _cam.tz / 2
        ..ty = o.y - 10 - _cam.visH / _cam.tz / 2
        ..clamp(w);
    }
    _cam.ease(dt);
    _frame.value++;
  }

  // ------------------------------------------------------------------ owner

  static Map<String, dynamic> _lookJson(Look l) => {
    'crown': true,
    'color': l.color,
    'hair': l.hair,
    'skin': l.skin,
    'hairStyle': l.hairStyle,
    'outfit': l.outfit,
    'acc': l.acc,
    'hijab': l.hijab,
    'tie': l.tie,
  };

  void _enterOffice() {
    final sim = _sim;
    if (sim == null || _owner) return;
    HapticFeedback.mediumImpact();
    sim.ownerEnter(_ownerLook);
    _cam.tz = math.max(_cam.tz, 2.6);
    _focus = null;
    setState(() {
      _owner = true;
      _follow = true;
    });
    _sentSig = null;
    _ownerTimer?.cancel();
    _ownerTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _syncOwner(),
    );
    unawaited(_pushOwner(present: true));
  }

  void _leaveOffice() {
    HapticFeedback.selectionClick();
    _stopOwner(send: true, api: _api, office: _id);
    setState(() {});
  }

  static const _client = 'ghina-android';

  /// The server speaks tiles (feet at tile centre); the sim speaks world px.
  static double _tileX(double px) =>
      double.parse(((px - 4) / kTile).toStringAsFixed(2));
  static double _tileY(double py) =>
      double.parse(((py - 7) / kTile).toStringAsFixed(2));

  void _stopOwner({
    required bool send,
    required KantorApi? api,
    required String office,
  }) {
    _ownerTimer?.cancel();
    _ownerTimer = null;
    if (!_owner) return;
    final e = _sim?.owner;
    _owner = false;
    _sim?.ownerLeave();
    if (send && api != null && e != null) {
      unawaited(
        api
            .put('/api/offices/$office/owner', {
              'x': _tileX(e.x),
              'y': _tileY(e.y),
              'face': e.dir,
              'client': _client,
              'present': false,
            })
            .then((_) => null, onError: (Object _) => null),
      );
    }
  }

  /// Throttled: ~4 writes/s while moving, a heartbeat every few seconds idle.
  void _syncOwner() {
    final e = _sim?.owner;
    if (!_owner || e == null) return;
    final sig = '${e.x.round()},${e.y.round()},${e.dir}';
    final age = DateTime.now().difference(_sentAt);
    if (sig != _sentSig || age.inSeconds >= 10)
      unawaited(_pushOwner(present: true));
  }

  Future<void> _pushOwner({required bool present}) async {
    final api = _api, e = _sim?.owner, w = _world;
    if (api == null || e == null || w == null || _sending) return;
    _sending = true;
    _sentSig = '${e.x.round()},${e.y.round()},${e.dir}';
    _sentAt = DateTime.now();
    try {
      await api.put('/api/offices/$_id/owner', {
        'x': _tileX(e.x),
        'y': _tileY(e.y),
        'face': e.dir,
        'room': w.roomAtTile((e.x / kTile).floor(), (e.y / kTile).floor()),
        'pose': e.pose?.kind,
        'fx': e.act?.arrived == true ? e.act?.aff : null,
        'client': _client,
        'look': _lookJson(_ownerLook),
        'present': present,
      });
    } on Object {
      // Position sync is best effort; the next tick tries again.
    }
    _sending = false;
  }

  Future<void> _loadOwner(KantorApi api) async {
    try {
      _applyRemoteOwner(asMap(await api.get('/api/offices/$_id/owner')));
    } on Object {
      // Older daemon: no owner endpoint.
    }
  }

  void _applyRemoteOwner(Map<String, dynamic> o) {
    final sim = _sim;
    if (sim == null || o.isEmpty || o['client'] == _client) return;
    if (_owner) {
      // another device took over: let go without telling the server
      if (o['present'] == true) {
        _stopOwner(send: false, api: null, office: _id);
        if (mounted) setState(() {});
      }
      return;
    }
    final x = o['x'], y = o['y'];
    final look = o['look'];
    if (look is Map<String, dynamic>) _ownerLook = Look.fromRole(look);
    if (x is! num || y is! num) {
      if (o['present'] == false)
        sim.ownerRemote(present: false, x: 0, y: 0, face: 'down');
      return;
    }
    sim.ownerRemote(
      present: o['present'] == true,
      x: x * kTile + 4,
      y: y * kTile + 7,
      face: '${o['face'] ?? 'down'}',
      look: look is Map<String, dynamic> ? Look.fromRole(look) : null,
    );
  }

  void _doAction(OwnerTarget t) {
    final sim = _sim;
    if (sim == null) return;
    HapticFeedback.lightImpact();
    switch (t.kind) {
      case 'agent':
        _agentSheet(t.ent!);
      case 'minion':
        _usirMinion(t.ent!);
      case 'tab':
        context.push('/kantor/o/${Uri.encodeComponent(_id)}?tab=${t.tab}');
      default:
        sim.ownerUse(t);
    }
  }

  void _usirMinion(FloorEnt m) {
    final api = _api, sim = _sim;
    if (api == null || sim == null) return;
    unawaited(
      usirMinion(api: api, officeId: _id, sim: sim, minion: m, toast: _toast),
    );
  }

  void _minionSheet(FloorEnt m) {
    if (m.mn?.state == 'leave') return;
    HapticFeedback.selectionClick();
    unawaited(
      showMinionSheet(
        context,
        minion: m,
        actionLabel: _owner ? 'Suruh pergi' : 'Usir',
        onUsir: () => _usirMinion(m),
      ),
    );
  }

  void _minionSettings() {
    final api = _api;
    if (api == null) return;
    unawaited(
      showMinionSettings(
        context,
        api: api,
        officeId: _id,
        view: asMapOrNull(_office?['minions']),
        sim: _sim,
        onView: (v) {
          _office?['minions'] = v;
          _sim?.minionsApply(v);
        },
        toast: _toast,
      ),
    );
  }

  void _agentSheet(FloorEnt a) {
    final api = _api, sim = _sim;
    if (api == null || sim == null || a.s == null) return;
    showOwnerAgentSheet(
      context,
      api: api,
      officeId: _id,
      agent: a,
      role: sim.roleOf(a.s!),
      toast: _toast,
      open: (p) => context.push(p),
    );
  }

  // ----------------------------------------------------------------- data

  Future<void> _load({bool quiet = false}) async {
    final api = _api;
    if (api == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await api.get('/api/offices/$_id');
      if (!mounted) return;
      final prevCards = _office == null ? null : asMaps(_office!['cards']);
      _office = asMap(res);
      _news = asMaps(_office!['news']);
      await _ensureCatalog(api, asMap(_office!['plan'])['furniture']);
      if (!mounted) return;
      _applyOffice();
      if (prevCards != null) {
        _sim?.minionsCards(prevCards, asMaps(_office!['cards']));
      }
      unawaited(_loadPrayer(api));
      _error = null;
      unawaited(_loadInbox());
    } on Object catch (e) {
      if (!mounted) return;
      if (!quiet || _office == null) _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Furniture catalog: one fetch per app session (re-read only when the plan
  /// places an item the catalog has never heard of).
  Future<void> _ensureCatalog(KantorApi api, Object? placed) async {
    var cat = FurnitureCatalog.shared;
    if (cat == null || unknownFurnitureIds(placed, cat).isNotEmpty) {
      cat = await FurnitureCatalog.load(api.get, force: cat != null);
    }
    _catalog = cat;
  }

  Future<void> _loadPrayer(KantorApi api) async {
    final day = FloorPrayer.dayKey(DateTime.now());
    if (_prayerDay == day) return;
    try {
      final res = await api.get('/api/prayer-times', query: {'date': day});
      _prayer = FloorPrayer.fromJson(res);
      _prayerDay = day;
      _sim?.prayer = _prayer;
    } on Object {
      // Older daemon: no prayer rule fires, everything else works.
    }
  }

  Future<void> _loadInbox() async {
    try {
      final res = await _api?.get('/api/inbox');
      if (!mounted || res is! List) return;
      setState(
        () => _inbox = [
          for (final i in asMaps(res))
            if (i['office'] == _id) i,
        ],
      );
    } on Object {
      // The inbox also arrives live; a failed first read is not fatal.
    }
  }

  void _applyOffice() {
    final o = _office!;
    final plan = asMap(o['plan']);
    if (plan['rooms'] is! List || plan['w'] == null) return;
    final roles = asMaps(o['roles']);
    final cards = asMaps(o['cards']);
    final base = {...plan}..remove('furniture');
    final planSig = jsonEncode([
      base,
      [
        for (final r in roles)
          [
            r['id'],
            r['room'],
            r['color'],
            r['hair'],
            r['skin'],
            r['hairStyle'],
            r['outfit'],
            r['acc'],
            r['archived'],
          ],
      ],
    ]);
    final furnSig = '${_catalog?.version}|${jsonEncode(plan['furniture'])}';
    final cardsSig = jsonEncode(cards);
    if (_world == null || planSig != _planSig) {
      _planSig = planSig;
      _furnSig = furnSig;
      _cardsSig = cardsSig;
      final w = FloorWorld(plan, roles, catalog: _catalog);
      _world = w;
      _rebuildDesks(w);
      _bg?.dispose();
      _bg = buildBackground(w, roles, cards);
      final sim = FloorSim(w, roles)
        ..behaviors = _catalog?.behaviors
        ..prayer = _prayer;
      sim.mh.scenes = _catalog?.scenes ?? const [];
      final prev = _sim?.owner;
      _sim = sim;
      sim.sync(asMaps(o['sessions']));
      sim.minionsApply(asMapOrNull(o['minions']));
      if (_owner) {
        final me = sim.ownerEnter(_ownerLook, fromLift: false);
        if (prev != null) {
          me
            ..x = prev.x
            ..y = prev.y
            ..dir = prev.dir;
        }
      }
      widget.onSim?.call(sim);
      unawaited(_loadOwner(_api!));
      _fit(jump: true);
    } else {
      final sim = _sim!;
      if (furnSig != _furnSig) {
        // furniture edited: new world, characters stay and re-plan
        _furnSig = furnSig;
        final w = FloorWorld(plan, roles, catalog: _catalog);
        _world = w;
        _rebuildDesks(w);
        sim
          ..swapWorld(w)
          ..behaviors = _catalog?.behaviors;
        sim.mh.scenes = _catalog?.scenes ?? const [];
        sim.owner?.pose = null;
        _cardsSig = cardsSig;
        _rebuildBg();
      }
      sim
        ..roles = roles
        ..sync(asMaps(o['sessions']))
        ..minionsApply(asMapOrNull(o['minions']));
      if (cardsSig != _cardsSig) {
        _cardsSig = cardsSig;
        _rebuildBg();
      }
    }
  }

  void _rebuildDesks(FloorWorld w) {
    _deskImgs
      ..forEach((_, i) => i.dispose())
      ..clear();
    for (final d in w.desks) {
      _deskImgs[d] = buildDeskBase(d);
    }
  }

  void _rebuildBg() {
    final w = _world, o = _office;
    if (w == null || o == null || !mounted) return;
    final old = _bg;
    setState(
      () => _bg = buildBackground(w, asMaps(o['roles']), asMaps(o['cards'])),
    );
    // The old image may still be in the current frame; release it after.
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  void _onEvent(Map<String, dynamic> m) {
    final o = _office;
    if (o == null || !mounted) return;
    final t = m['t'];
    final sameOffice = m['office'] == _id;
    if (sameOffice) _sim?.minionsLive(m);
    switch (t) {
      case 'hello':
        setState(
          () => _inbox = [
            for (final i in asMaps(m['inbox']))
              if (i['office'] == _id) i,
          ],
        );
      case 'session' when sameOffice:
        final s = asMap(m['session']);
        final list = asMaps(o['sessions']);
        final i = list.indexWhere((x) => x['sid'] == s['sid']);
        if (i >= 0) {
          list[i] = s;
        } else {
          list.add(s);
        }
        o['sessions'] = list;
        _sim?.sync(list);
        setState(() {});
      case 'session-gone' when sameOffice:
        final list = asMaps(o['sessions'])
          ..removeWhere((x) => x['sid'] == m['sid']);
        o['sessions'] = list;
        _sim?.sync(list);
        setState(() {});
      case 'inbox':
        final item = asMap(m['item']);
        if (item['office'] == _id) {
          setState(
            () =>
                _inbox = [item, ..._inbox.where((x) => x['id'] != item['id'])],
          );
        }
      case 'inbox-update':
        if (m['status'] != 'open')
          setState(
            () => _inbox = _inbox.where((x) => x['id'] != m['id']).toList(),
          );
      case 'minions' when sameOffice:
        o['minions'] = m['minions'];
        _sim?.minionsApply(asMapOrNull(m['minions']));
      case 'owner' when sameOffice:
        _applyRemoteOwner(asMap(m['owner']));
      case 'changed' when sameOffice || m['office'] == '*':
        final what = '${m['what']}';
        if (const {
          'board',
          'roles',
          'plan',
          'news',
          'furniture',
        }.contains(what))
          unawaited(_load(quiet: true));
    }
  }

  // --------------------------------------------------------------- camera

  void _fit({bool jump = false}) {
    final w = _world;
    if (w == null) return;
    _focus = null;
    _cam
      ..insetTop = _chipBar
      ..insetBottom = _peekHeight
      ..tz = _cam.fitZoom(w)
      ..tx = 0
      ..ty = 0
      ..clamp(w);
    if (jump) _cam.jump();
    setState(() {});
  }

  void _focusRoom(String id, {bool jump = false}) {
    final w = _world;
    final r = w?.room(id);
    if (w == null || r == null) return;
    var y = r.y, h = r.h;
    if (r.kind == 'zone') {
      final op = w.room(r.zoneOf);
      if (op != null) {
        y = op.y;
        h = op.h;
      }
    }
    final z = math.min(
      math.min(_cam.visW / ((r.w + 4) * kTile), _cam.visH / ((h + 4) * kTile)),
      3.2,
    );
    _cam
      ..tz = z
      ..tx = (r.x + r.w / 2) * kTile - _cam.visW / 2 / z
      ..ty = (y + h / 2) * kTile - _cam.visH / 2 / z
      ..clamp(w);
    if (jump) _cam.jump();
    setState(() {
      _focus = id;
      _selected = id;
    });
  }

  void _zoomBy(double f, [Offset? at]) {
    final w = _world;
    if (w == null) return;
    final p = at ?? Offset(_cam.size.width / 2, _cam.insetTop + _cam.visH / 2);
    final wx = _cam.tx + p.dx / _cam.tz,
        wy = _cam.ty + (p.dy - _cam.insetTop) / _cam.tz;
    _cam.tz = (_cam.tz * f)
        .clamp(math.max(.15, _cam.fitZoom(w) * .9), 6.0)
        .toDouble();
    _cam.tx = wx - p.dx / _cam.tz;
    _cam.ty = wy - (p.dy - _cam.insetTop) / _cam.tz;
    _cam.clamp(w);
    _focus = null;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startFocal = d.localFocalPoint;
    _startZ = _cam.tz;
    _startCam = Offset(_cam.tx, _cam.ty);
    _maxPointers = d.pointerCount;
    _moved = false;
    _cam
      ..tx = _cam.x
      ..ty = _cam.y
      ..tz = _cam.z;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final w = _world;
    if (w == null) return;
    _maxPointers = math.max(_maxPointers, d.pointerCount);
    if (!_moved && (d.localFocalPoint - _startFocal).distance > 8)
      _moved = true;
    if (d.pointerCount >= 2) _moved = true;
    if (!_moved) return;
    if (_follow && _owner && d.pointerCount == 1)
      setState(() => _follow = false);
    final z = (_startZ * d.scale)
        .clamp(math.max(.15, _cam.fitZoom(w) * .9), 6.0)
        .toDouble();
    // keep the world point under the start focal where the fingers are now
    final wx = _startCam.dx + _startFocal.dx / _startZ;
    final wy = _startCam.dy + (_startFocal.dy - _cam.insetTop) / _startZ;
    _cam
      ..tz = z
      ..tx = wx - d.localFocalPoint.dx / z
      ..ty = wy - (d.localFocalPoint.dy - _cam.insetTop) / z
      ..clamp(w);
    _cam.jump();
    _focus = null;
  }

  void _onTapUp(TapUpDetails d) {
    if (_maxPointers > 1) return;
    final pos = d.localPosition;
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null &&
        now.difference(last).inMilliseconds < 320 &&
        (pos - _lastTapPos).distance < 32) {
      _tapTimer?.cancel();
      _lastTapAt = null;
      final w = _world;
      if (w == null) return;
      if (_cam.tz > _cam.fitZoom(w) * 1.3) {
        _fit();
      } else {
        _zoomBy(math.min(2.4, 6 / _cam.tz), pos);
      }
      return;
    }
    _lastTapAt = now;
    _lastTapPos = pos;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 280), () {
      _lastTapAt = null;
      if (mounted) _tap(pos);
    });
  }

  // ------------------------------------------------------------ interaction

  void _tap(Offset p) {
    final w = _world, sim = _sim;
    if (w == null || sim == null) return;
    final wp = _cam.toWorld(p);
    final e = sim.entAt(wp.dx, wp.dy);
    if (e != null && e.minion) {
      _minionSheet(e);
      return;
    }
    if (_owner) {
      HapticFeedback.selectionClick();
      if (e != null && !e.owner && !e.isSub && e.s != null) {
        sim.ownerGoBeside(e, () {
          if (mounted) _agentSheet(e);
        });
      } else {
        sim.ownerGoTo(wp.dx, wp.dy);
      }
      return;
    }
    if (e != null) {
      final sid = e.isSub ? e.parent : e.sid;
      if (sid != null) _openSession(sid);
      return;
    }
    final desk = sim.emptyDeskAt(wp.dx, wp.dy);
    if (desk?.role != null) {
      _openRole(desk!.role!);
      return;
    }
    final id = w.roomAtTile((wp.dx / kTile).floor(), (wp.dy / kTile).floor());
    if (id != null) {
      setState(() => _selected = id);
      if (_focus != id && _cam.z < 2.2) _focusRoom(id);
      _openRoom(id);
    }
  }

  void _openSession(String sid) => context.push('/kantor/o/$_id/s/$sid');

  Map<String, dynamic>? _role(String id) {
    for (final r in asMaps(_office?['roles'])) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  void _toast(String msg, {bool bad = false}) => showToastBadge(
    context,
    message: msg,
    icon: bad ? Icons.error_outline_rounded : Icons.check_circle_rounded,
    color: bad ? GhinaColors.red : GhinaColors.green,
  );

  Future<void> _decide(String id, bool allow) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.post('/api/inbox/$id', {'behavior': allow ? 'allow' : 'deny'});
      if (!mounted) return;
      setState(() => _inbox = _inbox.where((x) => '${x['id']}' != id).toList());
      _toast(allow ? 'Diizinkan' : 'Ditolak', bad: !allow);
    } on Object catch (e) {
      if (mounted) _toast('$e', bad: true);
    }
  }

  Future<void> _askManager() async {
    final api = _api;
    final text = _mgrCtl.text.trim();
    final mgr = asMaps(
      _office?['roles'],
    ).where((r) => r['isMgr'] == true && r['archived'] != true).firstOrNull;
    if (api == null || mgr == null || text.isEmpty) return;
    final live = asMaps(_office?['sessions'])
        .where(
          (s) =>
              s['role'] == mgr['id'] &&
              s['status'] != 'ended' &&
              s['tmux'] != null,
        )
        .firstOrNull;
    setState(() => _mgrBusy = true);
    try {
      if (live != null) {
        await api.post('/api/sessions/${live['sid']}/action', {
          'action': 'text',
          'text': text,
        });
        if (mounted) _toast('Terkirim ke ${mgr['name']}');
      } else {
        await api.post('/api/offices/$_id/roles/${mgr['id']}/start', {
          'task': text,
        });
        if (mounted) _toast('${mgr['name']} mulai shift dengan permintaanmu');
      }
      _mgrCtl.clear();
    } on Object catch (e) {
      if (mounted) _toast('$e', bad: true);
    }
    if (mounted) setState(() => _mgrBusy = false);
  }

  Future<void> _postNews() async {
    final api = _api;
    final text = _newsCtl.text.trim();
    if (api == null || text.isEmpty) return;
    try {
      final res = await api.post('/api/offices/$_id/news', {'text': text});
      _newsCtl.clear();
      if (mounted) setState(() => _news = asMaps(res));
    } on Object catch (e) {
      if (mounted) _toast('$e', bad: true);
    }
  }

  Future<void> _deleteNews(Object id) async {
    try {
      final res = await _api?.delete('/api/offices/$_id/news/$id');
      if (mounted && res is List) setState(() => _news = asMaps(res));
    } on Object catch (e) {
      if (mounted) _toast('$e', bad: true);
    }
  }

  // ----------------------------------------------------------------- sheets

  void _openRole(String roleId) {
    final r = _role(roleId);
    if (r == null) return;
    final sessions = asMaps(
      _office?['sessions'],
    ).where((s) => s['role'] == roleId && s['status'] != 'ended').toList();
    final g = context.ghina;
    showChunkyBottomSheet<void>(
      context,
      showClose: true,
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FloorAvatar(look: Look.fromRole(r), scale: 2.2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['name']}',
                      style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
                    ),
                    Text(
                      '${r['title'] ?? ''}',
                      style: GhinaType.body.copyWith(color: g.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChunkyPill(label: '${r['model'] ?? ''}', soft: true),
                        ChunkyPill(
                          label: sessions.isEmpty ? 'libur' : 'sedang shift',
                          color: sessions.isEmpty
                              ? GhinaColors.gray
                              : GhinaColors.green,
                          soft: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if ('${r['persona'] ?? ''}'.isNotEmpty)
            fact(
              c,
              'Watak',
              Text(
                '${r['persona']}',
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          if ((r['skills'] as List?)?.isNotEmpty ?? false)
            fact(
              c,
              'Keahlian',
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in r['skills'] as List)
                    ChunkyPill(label: '$s', soft: true, uppercase: false),
                ],
              ),
            ),
          fact(
            c,
            'Ruangan',
            Text(
              _world?.room(_world?.resolveRoom(r['room']))?.name ??
                  '${r['room']}',
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            ),
          ),
          const SizedBox(height: 4),
          if (sessions.isNotEmpty)
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChunkyButton(
                  label: sessions.length > 1
                      ? 'Buka sesi #${((s['slot'] as num?)?.toInt() ?? 0) + 1}'
                      : 'Buka sesi',
                  variant: ChunkyButtonVariant.secondary,
                  onPressed: () {
                    Navigator.of(c).pop();
                    _openSession('${s['sid']}');
                  },
                ),
              ),
          ChunkyButton(
            label: sessions.isEmpty ? 'Mulai shift' : 'Mulai sesi paralel',
            onPressed: () {
              Navigator.of(c).pop();
              _startShift(roleId: roleId);
            },
          ),
        ],
      ),
    );
  }

  void _openRoom(String roomId) {
    final w = _world, o = _office;
    final r = w?.room(roomId);
    if (w == null || o == null || r == null) return;
    final g = context.ghina;
    final res = asMaps(o['roles'])
        .where((x) => w.resolveRoom(x['room']) == r.id && x['archived'] != true)
        .toList();
    final ss = asMaps(o['sessions'])
        .where(
          (s) => w.resolveRoom(s['room']) == r.id && s['status'] != 'ended',
        )
        .toList();
    final cards = asMaps(
      o['cards'],
    ).where((c) => c['repo'] == r.id && ((c['col'] as num?) ?? 0) < 4).toList();
    showChunkyBottomSheet<void>(
      context,
      title: r.name,
      showClose: true,
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.path != null && r.path!.isNotEmpty)
            fact(
              c,
              'Folder',
              Text(
                '${r.path}/',
                style: GhinaType.bodyS.copyWith(
                  color: g.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (r.stack.isNotEmpty)
            fact(
              c,
              'Jenis',
              Text(
                r.stack,
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          if (r.worktrees.isNotEmpty)
            fact(
              c,
              'Worktree',
              Text(
                r.worktrees.join(', '),
                style: GhinaType.bodyS.copyWith(
                  color: g.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (r.note != null && r.note!.isNotEmpty)
            fact(
              c,
              'Catatan',
              Text(
                r.note!,
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          fact(
            c,
            'Penghuni',
            res.isEmpty
                ? Text(
                    'belum ada',
                    style: GhinaType.bodyS.copyWith(color: g.textMuted),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final x in res)
                        ActionChip(
                          label: Text('${x['name']}'),
                          onPressed: () {
                            Navigator.of(c).pop();
                            _openRole('${x['id']}');
                          },
                        ),
                    ],
                  ),
          ),
          fact(
            c,
            'Sesi',
            ss.isEmpty
                ? Text(
                    'tidak ada',
                    style: GhinaType.bodyS.copyWith(color: g.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in ss)
                        InkWell(
                          onTap: () {
                            Navigator.of(c).pop();
                            _openSession('${s['sid']}');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${_sim?.nameOf(s) ?? s['role']} · ${s['waiting'] != null ? 'menunggu izin' : s['status']}',
                              style: GhinaType.bodyS
                                  .w(800)
                                  .copyWith(color: GhinaColors.blue.base),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          fact(
            c,
            'Kartu',
            cards.isEmpty
                ? Text(
                    'tidak ada',
                    style: GhinaType.bodyS.copyWith(color: g.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final k in cards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            shortText('${k['title']}', 60),
                            style: GhinaType.bodyS.copyWith(
                              color: g.textPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 4),
          ChunkyButton(
            label: 'Proses di sini',
            variant: ChunkyButtonVariant.outline,
            onPressed: () {
              Navigator.of(c).pop();
              openKantorProses(context, officeId: widget.officeId, room: r.id);
            },
          ),
          const SizedBox(height: 8),
          ChunkyButton(
            label: 'Mulai shift di sini',
            onPressed: () {
              Navigator.of(c).pop();
              _startShift(room: r.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startShift({String? roleId, String? room}) async {
    final api = _api, w = _world;
    final roles = asMaps(
      _office?['roles'],
    ).where((r) => r['archived'] != true).toList();
    if (api == null || w == null || roles.isEmpty) {
      _toast('Belum ada role', bad: true);
      return;
    }
    var pick =
        roleId ??
        roles
            .where((r) => room != null && w.resolveRoom(r['room']) == room)
            .firstOrNull?['id'] ??
        roles.first['id'];
    var perm = '';
    var worktree = true;
    final task = TextEditingController();
    var cards = <Map<String, dynamic>>[];
    try {
      final b = asMap(await api.get('/api/offices/$_id/board'));
      cards = asMaps(
        b['cards'],
      ).where((c) => ((c['col'] as num?) ?? 0) < 4).toList();
    } on Object {
      // Cards are optional here.
    }
    String? card;
    if (!mounted) return;
    const perms = [
      ('', 'Default kantor'),
      ('ikut', 'Ikuti pengaturan Claude'),
      ('default', 'Selalu tanya'),
      ('acceptEdits', 'Edit file otomatis'),
      ('auto', 'Auto mode'),
      ('plan', 'Hanya merencanakan'),
    ];
    await showChunkyBottomSheet<void>(
      context,
      title: 'Mulai shift',
      showClose: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final live = asMaps(
            _office?['sessions'],
          ).where((s) => s['role'] == pick && s['status'] != 'ended').length;
          final mine = cards
              .where((k) => '${k['who'] ?? ''}'.isEmpty || k['who'] == pick)
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: '$pick',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in roles)
                    DropdownMenuItem(
                      value: '${r['id']}',
                      child: Text(
                        '${r['name']} · ${r['title'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => set(() {
                  pick = v ?? pick;
                  card = null;
                }),
              ),
              if (live > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Ini sesi paralel ke-${live + 1} untuk role ini.',
                  style: GhinaType.caption.copyWith(
                    color: c.ghina.textSecondary,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: worktree,
                  onChanged: (v) => set(() => worktree = v ?? true),
                  title: Text(
                    'Pakai worktree terpisah',
                    style: GhinaType.bodyS.copyWith(color: c.ghina.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ChunkyTextField(
                controller: task,
                label: 'Tugas pertama (opsional)',
                hint: 'mis. perbaiki bug login lalu jalankan tes',
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('card$pick'),
                initialValue: card,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Kartu (opsional)',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Tanpa kartu'),
                  ),
                  for (final k in mine)
                    DropdownMenuItem(
                      value: '${k['id']}',
                      child: Text(
                        shortText('${k['title']}', 50),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => set(() => card = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: perm,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mode izin'),
                items: [
                  for (final p in perms)
                    DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                ],
                onChanged: (v) => set(() => perm = v ?? ''),
              ),
              const SizedBox(height: 16),
              ChunkyButton(
                label: 'Mulai shift',
                onPressed: () async {
                  final body = <String, dynamic>{
                    if (task.text.trim().isNotEmpty) 'task': task.text.trim(),
                    'cardId': ?card,
                    if (perm.isNotEmpty) 'permissionMode': perm,
                    if (live > 0 && worktree) 'worktree': true,
                  };
                  try {
                    final res = asMap(
                      await api.post(
                        '/api/offices/$_id/roles/${Uri.encodeComponent('$pick')}/start',
                        body,
                      ),
                    );
                    if (!c.mounted) return;
                    Navigator.of(c).pop();
                    _toast('Shift dimulai');
                    final sid = res['sid'];
                    if (sid != null && mounted) _openSession('$sid');
                  } on Object catch (e) {
                    if (mounted) _toast('$e', bad: true);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
    task.dispose();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      kantorEventsProvider,
      (_, next) => next.whenData(_onEvent),
    );
    final g = context.ghina;
    if (_loading && _office == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final world = _world, sim = _sim, bg = _bg;
    if (_error != null && _office == null ||
        world == null ||
        sim == null ||
        bg == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error != null ? '$_error' : 'Denah kantor belum tersedia.',
                textAlign: TextAlign.center,
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 12),
              ChunkyButton(label: 'Coba lagi', expand: false, onPressed: _load),
            ],
          ),
        ),
      );
    }
    final mgr = asMaps(
      _office?['roles'],
    ).where((r) => r['isMgr'] == true && r['archived'] != true).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (_cam.size != size) {
          final first = _cam.size == Size.zero;
          _cam.size = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_focus != null) {
              _focusRoom(_focus!, jump: true);
            } else {
              _fit(jump: first);
            }
          });
        }
        final minFrac = (_peekHeight / box.maxHeight).clamp(.08, .5);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent)
                    _zoomBy(
                      e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12,
                      e.localPosition,
                    );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onTapUp: _onTapUp,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: FloorPainter(
                        world: world,
                        sim: sim,
                        cam: _cam,
                        bg: bg,
                        deskImages: _deskImgs,
                        selected: _selected,
                        repaint: _frame,
                        dark: Theme.of(context).brightness == Brightness.dark,
                        catalog: _catalog,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              height: _chipBar - 8,
              child: _chips(world),
            ),
            Positioned(
              right: 10,
              top: _chipBar + 6,
              child: Column(
                children: [
                  ChunkyIconButton(
                    icon: Icons.add_rounded,
                    size: 40,
                    tooltip: 'Perbesar',
                    onPressed: () => _zoomBy(1.4),
                  ),
                  const SizedBox(height: 8),
                  ChunkyIconButton(
                    icon: Icons.remove_rounded,
                    size: 40,
                    tooltip: 'Perkecil',
                    onPressed: () => _zoomBy(1 / 1.4),
                  ),
                  const SizedBox(height: 8),
                  ChunkyIconButton(
                    icon: Icons.fit_screen_rounded,
                    size: 40,
                    tooltip: 'Lihat semua',
                    onPressed: _fit,
                  ),
                  const SizedBox(height: 8),
                  ChunkyIconButton(
                    key: const ValueKey('minion-settings'),
                    icon: Icons.groups_rounded,
                    size: 40,
                    tooltip: 'Magang',
                    onPressed: _minionSettings,
                  ),
                  if (_owner) ...[
                    const SizedBox(height: 8),
                    ChunkyIconButton(
                      icon: _follow
                          ? Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      size: 40,
                      tooltip: _follow ? 'Kamera mengikuti' : 'Ikuti karakter',
                      color: _follow ? GhinaColors.yellow : null,
                      onPressed: () => setState(() => _follow = !_follow),
                    ),
                    const SizedBox(height: 8),
                    ChunkyIconButton(
                      icon: Icons.logout_rounded,
                      size: 40,
                      tooltip: 'Keluar kantor',
                      onPressed: _leaveOffice,
                    ),
                  ],
                ],
              ),
            ),
            if (_owner) ...[
              Positioned(
                left: 14,
                bottom: _peekHeight + 14,
                child: OwnerJoystick(onChanged: sim.ownerStick),
              ),
              Positioned(
                right: 12,
                bottom: _peekHeight + 18,
                child: ValueListenableBuilder<OwnerTarget?>(
                  valueListenable: sim.target,
                  builder: (_, t, _) => t == null
                      ? const SizedBox.shrink()
                      : OwnerActionButton(
                          target: t,
                          onPressed: () => _doAction(t),
                        ),
                ),
              ),
            ] else
              Positioned(
                left: 12,
                bottom: _peekHeight + 14,
                child: ChunkyButton(
                  key: const ValueKey('owner-enter'),
                  label: 'Masuk kantor',
                  icon: Icons.login_rounded,
                  expand: false,
                  onPressed: _enterOffice,
                ),
              ),
            DraggableScrollableSheet(
              initialChildSize: minFrac,
              minChildSize: minFrac,
              maxChildSize: .86,
              snap: true,
              snapSizes: [minFrac, .55],
              builder: (context, scroll) => FloorPanel(
                scroll: scroll,
                inbox: _inbox,
                news: _news,
                manager: mgr,
                mgrBusy: _mgrBusy,
                mgrController: _mgrCtl,
                newsController: _newsCtl,
                onDecide: _decide,
                onAsk: _askManager,
                onPost: _postNews,
                onDeleteNews: _deleteNews,
                onOpenSession: _openSession,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chips(FloorWorld world) {
    final rooms = [
      for (final r in world.allRooms)
        if (r.kind != 'openplan' && r.kind != 'lobby') r,
    ];
    final waitingRooms = <String>{
      for (final s in asMaps(_office?['sessions']))
        if (s['waiting'] != null) ...{world.resolveRoom(s['room']) ?? ''},
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChunkyChip(
            label: 'Semua',
            selected: _focus == null,
            icon: Icons.map_rounded,
            onTap: _fit,
          ),
        ),
        for (final r in rooms)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChunkyChip(
              label: r.name,
              selected: _focus == r.id,
              color: waitingRooms.contains(r.id) ? GhinaColors.orange : null,
              onTap: () => _focusRoom(r.id),
            ),
          ),
      ],
    );
  }
}
