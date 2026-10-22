// Data-driven furniture: the shared catalog (GET /api/furniture), the behaviour
// rules that decide what idle/working agents do with it, prayer times, and the
// per-office placements (plan.furniture) turned into drawable instances.
// Mirrors the web renderer's furniture.js so both show the same behaviour.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'floor_pixel.dart';

const double _t = kTile;

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;
int? _int(Object? v) => v is num ? v.toInt() : null;

/// Accepts #RGB, #RGBA, #RRGGBB and #RRGGBBAA (CSS order).
ui.Color parseColor(String s) {
  var h = s.startsWith('#') ? s.substring(1) : s;
  if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6 && h.length != 8) return const ui.Color(0xFFFF00FF);
  final rgb = int.tryParse(h.substring(0, 6), radix: 16);
  if (rgb == null) return const ui.Color(0xFFFF00FF);
  final a = h.length == 8
      ? int.tryParse(h.substring(6, 8), radix: 16) ?? 255
      : 255;
  return ui.Color((a << 24) | rgb);
}

// ------------------------------------------------------------------ items

class FurnSpotDef {
  const FurnSpotDef(this.dx, this.dy, this.pose, this.face);
  final int dx, dy;

  /// stand | sit | sleep | pray | play | exercise | read
  final String pose;

  /// up | down | left | right
  final String face;
}

class FurnItemDef {
  FurnItemDef._({
    required this.id,
    required this.name,
    required this.cat,
    required this.w,
    required this.h,
    required this.sw,
    required this.sh,
    required this.palette,
    required this.rows,
    required this.frames,
    required this.fps,
    required this.activeRows,
    required this.solid,
    required this.wall,
    required this.affords,
    required this.spots,
    required this.rooms,
    required this.weight,
  });

  /// Tolerant parser: a broken item yields null and is simply skipped.
  static FurnItemDef? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    try {
      final id = j['id'];
      final w = _int(j['w']), h = _int(j['h']);
      final sp = _map(j['sprite']);
      if (id is! String ||
          w == null ||
          h == null ||
          sp == null ||
          w < 1 ||
          h < 1)
        return null;
      final sw = _int(sp['w']) ?? w * 8, sh = _int(sp['h']);
      final rows = [for (final r in (sp['rows'] as List)) '$r'];
      if (sh == null || rows.length != sh) return null;
      final pal = <String, ui.Color>{
        for (final e in (_map(sp['palette']) ?? const {}).entries)
          e.key: parseColor('${e.value}'),
      };
      List<String>? rowsOf(Object? o) {
        final m = _map(o);
        final l = m?['rows'];
        return l is List && l.length == sh ? [for (final r in l) '$r'] : null;
      }

      final frames = <List<String>>[
        for (final f in (j['frames'] as List? ?? const []))
          if (rowsOf(f) != null) rowsOf(f)!,
      ];
      return FurnItemDef._(
        id: id,
        name: '${j['name'] ?? id}',
        cat: '${j['cat'] ?? ''}',
        w: w,
        h: h,
        sw: sw,
        sh: sh,
        palette: pal,
        rows: rows,
        frames: frames,
        fps: (j['fps'] as num?)?.toDouble() ?? (frames.isEmpty ? 0 : 2),
        activeRows: rowsOf(j['active']),
        solid: j['solid'] != false,
        wall: j['wall'] == true,
        affords: {for (final a in (j['affords'] as List? ?? const [])) '$a'},
        spots: [
          for (final s in (j['spots'] as List? ?? const []))
            if (s is Map && _int(s['dx']) != null && _int(s['dy']) != null)
              FurnSpotDef(
                _int(s['dx'])!,
                _int(s['dy'])!,
                '${s['pose'] ?? 'stand'}',
                '${s['face'] ?? 'down'}',
              ),
        ],
        rooms: [for (final r in (j['rooms'] as List? ?? const [])) '$r'],
        weight: (j['weight'] as num?)?.toDouble() ?? 1,
      );
    } on Object {
      return null;
    }
  }

  final String id, name, cat;
  final int w, h, sw, sh;
  final Map<String, ui.Color> palette;
  final List<String> rows;
  final List<List<String>> frames;
  final double fps;
  final List<String>? activeRows;
  final bool solid, wall;
  final Set<String> affords;
  final List<FurnSpotDef> spots;
  final List<String> rooms;
  final double weight;

  bool get animated => frames.length > 1 && fps > 0;

  /// Lies flat on the floor (rugs, mats): drawn below everything standing.
  bool get flat => !solid && !wall && sh <= h * 8;
}

// -------------------------------------------------------------- behaviours

class FurnPick {
  const FurnPick(this.a, this.w);
  final String a;
  final double w;
}

class FurnRule {
  FurnRule._(
    this.id,
    this.when,
    this.chance,
    this.picks,
    this.lo,
    this.hi,
    this.then,
    this.bash,
    this.label,
  );

  static FurnRule? tryParse(Object? raw, String fallbackId) {
    final j = _map(raw);
    if (j == null) return null;
    final picks = [
      for (final p in (j['pick'] as List? ?? const []))
        if (p is Map && p['a'] is String)
          FurnPick(p['a'] as String, (p['w'] as num?)?.toDouble() ?? 1),
    ];
    final d = j['dwell'];
    if (picks.isEmpty || d is! List || d.length < 2) return null;
    final when = _map(j['when']) ?? const <String, dynamic>{};
    RegExp? re(Object? o) {
      if (o is! String || o.isEmpty) return null;
      try {
        return RegExp(o, caseSensitive: false);
      } on FormatException {
        return null;
      }
    }

    return FurnRule._(
      '${j['id'] ?? fallbackId}',
      when,
      (j['chance'] as num?)?.toDouble() ?? 1,
      picks,
      (d[0] as num).toDouble(),
      (d[1] as num).toDouble(),
      j['then'] as String?,
      re(when['bash']),
      re(when['label']),
    );
  }

  final String id;
  final Map<String, dynamic> when;
  final double chance, lo, hi;
  final List<FurnPick> picks;
  final String? then;
  final RegExp? bash, label;
}

class FurnStep {
  const FurnStep(this.a, this.lo, this.hi);
  final String a;
  final double lo, hi;
}

class FurnBehaviors {
  FurnBehaviors({
    required this.rules,
    required this.fallback,
    required this.prayerWindowMin,
    required this.prayerNames,
    required this.prayerSteps,
    required this.chatDistance,
    required this.chatMinIdleSec,
    required this.chatLo,
    required this.chatHi,
  });

  factory FurnBehaviors.fromJson(Object? raw) {
    final j = _map(raw) ?? const <String, dynamic>{};
    List<FurnRule> rules(Object? o, String p) => [
      for (final (i, r) in ((o as List?) ?? const []).indexed)
        if (FurnRule.tryParse(r, '$p$i') != null) FurnRule.tryParse(r, '$p$i')!,
    ];
    final pr = _map(j['prayer']) ?? const <String, dynamic>{};
    final chat = _map(j['chat']) ?? const <String, dynamic>{};
    final steps = [
      for (final s in (pr['steps'] as List? ?? const []))
        if (s is Map &&
            s['a'] is String &&
            s['dwell'] is List &&
            (s['dwell'] as List).length >= 2)
          FurnStep(
            s['a'] as String,
            ((s['dwell'] as List)[0] as num).toDouble(),
            ((s['dwell'] as List)[1] as num).toDouble(),
          ),
    ];
    final cd = chat['dwell'];
    return FurnBehaviors(
      rules: rules(j['rules'], 'rule'),
      fallback: rules(j['fallback'], 'fallback'),
      prayerWindowMin: (pr['windowMin'] as num?)?.toDouble() ?? 20,
      prayerNames: [
        for (final n
            in (pr['names'] as List? ??
                const ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya']))
          '$n',
      ],
      prayerSteps: steps.isNotEmpty
          ? steps
          : const [FurnStep('wudhu', 25, 50), FurnStep('pray', 90, 180)],
      chatDistance: (chat['distance'] as num?)?.toDouble() ?? 6,
      chatMinIdleSec: (chat['minIdleSec'] as num?)?.toDouble() ?? 20,
      chatLo: cd is List && cd.length >= 2 ? (cd[0] as num).toDouble() : 30,
      chatHi: cd is List && cd.length >= 2 ? (cd[1] as num).toDouble() : 90,
    );
  }

  final List<FurnRule> rules, fallback;
  final double prayerWindowMin, chatDistance, chatMinIdleSec, chatLo, chatHi;
  final List<String> prayerNames;
  final List<FurnStep> prayerSteps;
}

/// Today's prayer times (minutes after local midnight) from /api/prayer-times.
class FloorPrayer {
  FloorPrayer(this.date, this.minutes);

  factory FloorPrayer.fromJson(Object? raw) {
    final j = _map(raw) ?? const <String, dynamic>{};
    final m = <String, int>{};
    for (final n in const ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya']) {
      final v = '${j[n] ?? ''}'.split(':');
      if (v.length == 2) {
        final h = int.tryParse(v[0]), mi = int.tryParse(v[1]);
        if (h != null && mi != null) m[n] = h * 60 + mi;
      }
    }
    return FloorPrayer('${j['date'] ?? ''}', m);
  }

  final String date;
  final Map<String, int> minutes;

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The prayer whose window (time .. time + [windowMin]) contains [now].
  String? active(DateTime now, double windowMin, List<String> names) {
    if (date.isNotEmpty && date != dayKey(now)) return null;
    final cur = now.hour * 60 + now.minute + now.second / 60;
    for (final n in names) {
      final t = minutes[n];
      if (t != null && cur >= t && cur < t + windowMin) return n;
    }
    return null;
  }
}

// ----------------------------------------------------------------- catalog

/// A short multi-step Magang scene tied to the kind of room (scenes.json, see
/// docs/FRONTEND-CONTRACT.md): go somewhere, pose, speech bubble, wait.
class FurnScene {
  FurnScene({
    required this.id,
    required this.title,
    required this.rooms,
    required this.steps,
    this.weight = 1,
    this.hourWeights = const [],
    this.actorsMin = 1,
    this.actorsMax = 1,
    this.withAgent = false,
    this.cooldown = 60,
    this.need = const [],
    this.when,
  });

  static FurnScene? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final id = j['id'];
    final rooms = j['rooms'], steps = j['steps'];
    if (id is! String ||
        id.isEmpty ||
        rooms is! List ||
        rooms.isEmpty ||
        steps is! List ||
        steps.isEmpty) {
      return null;
    }
    final act = j['actors'];
    var lo = 1, hi = 1;
    if (act is List && act.length == 2) {
      lo = ((act[0] as num?) ?? 1).toInt().clamp(1, 3);
      hi = ((act[1] as num?) ?? lo).toInt().clamp(lo, 3);
    }
    return FurnScene(
      id: id,
      title: '${j['title'] ?? id}',
      rooms: [for (final r in rooms) '$r'],
      steps: [
        for (final s in steps)
          if (_map(s) != null) _map(s)!,
      ],
      weight: ((j['weight'] as num?) ?? 1).toDouble(),
      hourWeights: [
        for (final w in (j['hourWeights'] as List? ?? const []))
          if (_map(w) != null && _map(w)!['h'] is List)
            (
              ((_map(w)!['h'] as List)[0] as num).toDouble(),
              ((_map(w)!['h'] as List)[1] as num).toDouble(),
              ((_map(w)!['w'] as num?) ?? 1).toDouble(),
            ),
      ],
      actorsMin: lo,
      actorsMax: hi,
      withAgent: j['withAgent'] == true,
      cooldown: ((j['cooldown'] as num?) ?? 60).toDouble(),
      need: [for (final n in (j['need'] as List? ?? const [])) '$n'],
      when: j['when'] is String ? j['when'] as String : null,
    );
  }

  final String id, title;
  final List<String> rooms;
  final List<Map<String, dynamic>> steps;
  final double weight, cooldown;

  /// (from hour, to hour, multiplier); local hour as a fraction, `from` inclusive.
  final List<(double, double, double)> hourWeights;
  final int actorsMin, actorsMax;
  final bool withAgent;

  /// Conditions (`agent`: a real agent is working, `mgr-desk`: there is a manager desk) and `when` (`prayer`).
  final List<String> need;
  final String? when;

  /// Weight at local hour [h] (0..24): base weight x every matching multiplier.
  double weightAt(double h) {
    var w = weight;
    for (final (from, to, m) in hourWeights) {
      bool inside(double x) =>
          from <= to ? (x >= from && x < to) : (x >= from || x < to);
      // `to` may run past 24 (22..29 = 22:00-05:00)
      if (inside(h) || inside(h + 24)) w *= m;
    }
    return w;
  }
}

class FurnitureCatalog {
  FurnitureCatalog._(this.items, this.behaviors, this.version, this.scenes);

  factory FurnitureCatalog.fromJson(Object? raw) {
    final j = _map(raw) ?? const <String, dynamic>{};
    final items = <String, FurnItemDef>{};
    for (final r in (j['items'] as List? ?? const [])) {
      final d = FurnItemDef.tryParse(r);
      if (d != null) items[d.id] = d;
    }
    return FurnitureCatalog._(
      items,
      FurnBehaviors.fromJson(j['behaviors']),
      '${j['version'] ?? ''}',
      [
        for (final s in (j['scenes'] as List? ?? const []))
          ?FurnScene.tryParse(s),
      ],
    );
  }

  final Map<String, FurnItemDef> items;
  final FurnBehaviors behaviors;
  final String version;

  /// Magang room scenes (empty on an older daemon).
  final List<FurnScene> scenes;

  final _images = <String, ui.Image>{};

  /// The loaded catalog of this app session (one fetch).
  static FurnitureCatalog? shared;
  static Future<FurnitureCatalog?>? _loading;

  /// Fetches the catalog once per session; null when the daemon predates it.
  /// [force] re-reads (a placed item the catalog does not know yet).
  static Future<FurnitureCatalog?> load(
    Future<dynamic> Function(String path) get, {
    bool force = false,
  }) {
    if (!force && shared != null) return Future.value(shared);
    return _loading ??= () async {
      try {
        final res = await get('/api/furniture');
        final c = FurnitureCatalog.fromJson(res);
        if (c.items.isNotEmpty) shared = c;
      } on Object {
        // Older daemon, offline: the floor just has no catalog furniture.
      }
      _loading = null;
      return shared;
    }();
  }

  /// Image for the static sprite, an animation [frame] or the in-use sprite.
  ui.Image image(FurnItemDef d, {int frame = -1, bool active = false}) {
    final useActive = active && d.activeRows != null;
    final k = useActive
        ? '${d.id}:a'
        : frame >= 0 && d.frames.isNotEmpty
        ? '${d.id}:f${frame % d.frames.length}'
        : '${d.id}:s';
    return _images.putIfAbsent(k, () {
      final rows = useActive
          ? d.activeRows!
          : frame >= 0 && d.frames.isNotEmpty
          ? d.frames[frame % d.frames.length]
          : d.rows;
      return bake(d.sw, d.sh, (p) {
        for (var y = 0; y < rows.length; y++) {
          final row = rows[y];
          var x = 0;
          while (x < row.length) {
            final ch = row[x];
            var e = x + 1;
            while (e < row.length && row[e] == ch) {
              e++;
            }
            final col = ch == '.' ? null : d.palette[ch];
            if (col != null) p.r(x, y, e - x, 1, col);
            x = e;
          }
        }
      });
    });
  }
}

// ---------------------------------------------------------------- instances

class FloorSpot {
  FloorSpot(this.furn, this.idx, this.def, this.tx, this.ty)
    : key = '${furn.uid}#$idx',
      x = tx * _t + 4,
      y = ty * _t + 7;
  final FloorFurn furn;
  final int idx, tx, ty;
  final FurnSpotDef def;
  final String key;
  final double x, y;

  String get pose => def.pose;
  String get face => def.face;

  /// True when the spot lies on the item itself (sofa seat, bed): the person
  /// is drawn right after the item instead of by their own y.
  bool get onItem =>
      tx >= furn.tx &&
      tx < furn.tx + furn.def.w &&
      ty >= furn.ty &&
      ty < furn.ty + furn.def.h;
}

class FloorFurn {
  FloorFurn(this.uid, this.def, this.tx, this.ty)
    : x = tx * _t,
      y = (ty + def.h) * _t - def.sh,
      sortY = def.wall
          ? -10
          : def.flat
          ? ty * _t - .5
          : (ty + def.h) * _t;
  final String uid;
  final FurnItemDef def;
  final int tx, ty;
  final double x, y, sortY;
  late final List<FloorSpot> spots = [
    for (final (i, s) in def.spots.indexed)
      FloorSpot(this, i, s, tx + s.dx, ty + s.dy),
  ];

  ui.Rect get bounds =>
      ui.Rect.fromLTWH(x, y, def.sw.toDouble(), def.sh.toDouble());

  /// Picks the frame for [time] seconds.
  int frameAt(double time) =>
      def.animated ? (time * def.fps).floor() % def.frames.length : -1;
}

/// Parses plan.furniture against [catalog]; unknown items are skipped.
List<FloorFurn> placeFurniture(
  Object? list,
  FurnitureCatalog? catalog,
  int w,
  int h,
) {
  if (catalog == null || list is! List) return const [];
  final out = <FloorFurn>[];
  for (final (i, p) in list.indexed) {
    final m = _map(p);
    if (m == null) continue;
    final def = catalog.items['${m['item']}'];
    final x = _int(m['x']), y = _int(m['y']);
    if (def == null || x == null || y == null) continue;
    if (x < 0 || y < 0 || x + def.w > w || y + def.h > h) continue;
    out.add(FloorFurn('${m['uid'] ?? 'f$i'}', def, x, y));
  }
  return out;
}

/// Ids the plan places that the catalog does not (yet) know.
Set<String> unknownFurnitureIds(Object? list, FurnitureCatalog? catalog) => {
  if (list is List)
    for (final p in list)
      if (p is Map &&
          (catalog == null || !catalog.items.containsKey('${p['item']}')))
        '${p['item']}',
};

/// Weighted shuffle: higher-weight picks tend to come first.
List<FurnPick> weightedOrder(List<FurnPick> picks, math.Random rnd) {
  final left = [...picks];
  final out = <FurnPick>[];
  while (left.isNotEmpty) {
    final total = left.fold<double>(0, (a, b) => a + math.max(0, b.w));
    if (total <= 0) {
      out.addAll(left);
      break;
    }
    var r = rnd.nextDouble() * total;
    var k = 0;
    for (; k < left.length - 1; k++) {
      r -= math.max(0, left[k].w);
      if (r < 0) break;
    }
    out.add(left.removeAt(k));
  }
  return out;
}
