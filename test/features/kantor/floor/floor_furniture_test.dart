import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_furniture.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_painter.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_pixel.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_poses.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_scene.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_sim.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_world.dart';

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List)) x as Map<String, dynamic>,
];

/// A w*8 x [h] sprite: [body] colour with a lighter top row, '.' above [top].
Map<String, dynamic> _sprite(
  int tw,
  int h,
  String body, {
  int top = 0,
  String? hi,
  Map<String, String>? extra,
}) {
  final w = tw * 8;
  return {
    'w': w,
    'h': h,
    'palette': {'a': body, 'b': hi ?? '#ffffff', ...?extra},
    'rows': [
      for (var y = 0; y < h; y++)
        y < top
            ? '.' * w
            : y == top
            ? 'b' * w
            : 'a' * w,
    ],
  };
}

Map<String, dynamic> _item(
  String id,
  int w,
  int h,
  int sh,
  String col, {
  List<String> affords = const [],
  List<Map<String, dynamic>> spots = const [],
  bool solid = true,
  bool wall = false,
  bool anim = false,
  bool active = false,
}) {
  final base = _sprite(w, sh, col);
  return {
    'id': id,
    'name': id,
    'cat': 'tes',
    'w': w,
    'h': h,
    'sprite': base,
    if (anim)
      'frames': [
        {'rows': base['rows']},
        {'rows': (base['rows'] as List).reversed.toList()},
      ],
    if (anim) 'fps': 4,
    if (active) 'active': {'rows': (base['rows'] as List).reversed.toList()},
    'solid': solid,
    'wall': wall,
    'affords': affords,
    'spots': spots,
  };
}

Map<String, dynamic> _spot(
  int dx,
  int dy,
  String pose, [
  String face = 'down',
]) => {'dx': dx, 'dy': dy, 'pose': pose, 'face': face};

/// Rules copied in spirit from the daemon's behaviors.json.
const _behaviors = {
  'version': 1,
  'prayer': {
    'windowMin': 20,
    'names': ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'],
    'steps': [
      {
        'a': 'wudhu',
        'dwell': [6, 8],
      },
      {
        'a': 'pray',
        'dwell': [20, 24],
      },
    ],
  },
  'chat': {
    'distance': 6,
    'minIdleSec': 20,
    'dwell': [20, 30],
  },
  'rules': [
    {
      'id': 'sholat',
      'when': {'status': 'idle', 'prayer': true},
      'chance': 1,
      'pick': [
        {'a': 'wudhu', 'w': 1},
      ],
      'then': 'prayer.steps',
      'dwell': [6, 8],
    },
    {
      'id': 'kerja-papan',
      'when': {
        'status': 'working',
        'tools': ['TodoWrite'],
      },
      'pick': [
        {'a': 'whiteboard', 'w': 1},
      ],
      'dwell': [10, 20],
    },
    {
      'id': 'kerja-lain',
      'when': {'status': 'working'},
      'pick': [
        {'a': 'type', 'w': 1},
      ],
      'dwell': [15, 45],
    },
    {
      'id': 'ngobrol',
      'when': {
        'status': 'idle',
        'neighbor': true,
        'idleMin': [0.3, 20],
      },
      'chance': 1,
      'pick': [
        {'a': 'chat', 'w': 1},
      ],
      'dwell': [20, 30],
    },
    {
      'id': 'idle-singkat',
      'when': {
        'status': 'idle',
        'idleMin': [0, 5],
      },
      'pick': [
        {'a': 'coffee', 'w': 1},
      ],
      'dwell': [10, 12],
    },
    {
      'id': 'idle-lama',
      'when': {
        'status': 'idle',
        'idleMin': [20, null],
      },
      'pick': [
        {'a': 'sleep', 'w': 1},
      ],
      'dwell': [30, 40],
    },
  ],
  'fallback': [
    {
      'id': 'mejang',
      'pick': [
        {'a': 'sit', 'w': 1},
      ],
      'dwell': [10, 30],
    },
  ],
};

Map<String, dynamic> _catalogJson() => {
  'version': 'tes',
  'behaviors': _behaviors,
  'items': [
    _item(
      'kopi',
      2,
      1,
      14,
      '#6b4a2f',
      affords: ['coffee'],
      spots: [_spot(0, 1, 'stand')],
      anim: true,
      active: true,
    ),
    _item(
      'sofa',
      5,
      2,
      20,
      '#7a4e8c',
      affords: ['sofa', 'sit'],
      spots: [_spot(1, 1, 'sit'), _spot(3, 1, 'sit')],
    ),
    _item(
      'kasur',
      3,
      4,
      20,
      '#c9d6e8',
      affords: ['sleep'],
      spots: [_spot(1, 2, 'sleep', 'right')],
    ),
    _item(
      'sajadah',
      2,
      3,
      3,
      '#2f7a4f',
      affords: ['pray'],
      spots: [_spot(0, 1, 'pray', 'up')],
      solid: false,
    ),
    _item(
      'keran',
      2,
      1,
      12,
      '#9ab0c4',
      affords: ['wudhu'],
      spots: [_spot(0, 1, 'stand', 'up')],
    ),
    _item(
      'papan',
      3,
      1,
      22,
      '#f4f4f0',
      affords: ['whiteboard'],
      spots: [_spot(1, 1, 'stand', 'up')],
      wall: true,
    ),
    _item(
      'lari',
      2,
      3,
      24,
      '#3a3f4b',
      affords: ['exercise'],
      spots: [_spot(0, 1, 'exercise', 'right')],
    ),
    _item('rusak', 1, 1, 8, '#ff0000')
      ..['sprite'] = {
        'w': 8,
        'h': 8,
        'rows': ['x'],
      },
  ],
};

void main() {
  final office =
      jsonDecode(
            File(
              'test/features/kantor/floor/office_fixture.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  late FurnitureCatalog cat;
  late Map<String, dynamic> plan;
  late List<Map<String, dynamic>> roles;
  late FloorRoom room;

  setUp(() {
    cat = FurnitureCatalog.fromJson(_catalogJson());
    roles = _maps(office['roles']);
    plan = jsonDecode(jsonEncode(office['plan'])) as Map<String, dynamic>;
    room = FloorRoom(
      _maps(plan['rooms']).firstWhere((r) => r['id'] == 'pantry'),
    );
    final x = room.x, y = room.y;
    plan['furniture'] = [
      {'uid': 'kopi1', 'item': 'kopi', 'x': x + 3, 'y': y + 5},
      {'uid': 'sofa1', 'item': 'sofa', 'x': x + 10, 'y': y + 12},
      {'uid': 'kasur1', 'item': 'kasur', 'x': x + 24, 'y': y + 6},
      {'uid': 'saj1', 'item': 'sajadah', 'x': x + 16, 'y': y + 6},
      {'uid': 'keran1', 'item': 'keran', 'x': x + 6, 'y': y + 5},
      {'uid': 'papan1', 'item': 'papan', 'x': x + 12, 'y': y},
      {'uid': 'lari1', 'item': 'lari', 'x': x + 20, 'y': y + 14},
      {'uid': 'hantu', 'item': 'tidak-ada', 'x': x + 2, 'y': y + 2},
    ];
  });

  Map<String, dynamic> session(
    String sid,
    String role,
    String status, {
    String? tool,
    Duration idle = const Duration(seconds: 2),
    DateTime? now,
  }) => {
    'sid': sid,
    'room': 'pantry',
    'role': role,
    'kind': 'kantor',
    'status': status,
    'tool': tool == null ? null : {'name': tool, 'label': 'x'},
    'lastSeen': (now ?? DateTime.now())
        .subtract(idle)
        .toUtc()
        .toIso8601String(),
    'slot': 0,
    'subs': <dynamic>[],
  };

  FloorSim make(
    List<Map<String, dynamic>> sessions, {
    DateTime Function()? clock,
    FloorPrayer? prayer,
  }) {
    final world = FloorWorld(plan, roles, catalog: cat);
    final sim = FloorSim(world, roles)
      ..behaviors = cat.behaviors
      ..prayer = prayer;
    if (clock != null) sim.clock = clock;
    sim.sync(sessions);
    return sim;
  }

  void run(FloorSim sim, double seconds) {
    for (var i = 0; i < seconds * 20; i++) {
      sim.step(.05);
    }
  }

  test('catalog parses, skips broken items, bakes sprites', () {
    expect(cat.items.keys, containsAll(['kopi', 'sofa', 'kasur']));
    expect(cat.items.containsKey('rusak'), isFalse);
    final kopi = cat.items['kopi']!;
    expect(kopi.animated, isTrue);
    final img = cat.image(kopi, frame: 1);
    expect(img.width, 16);
    expect(img.height, 14);
    expect(identical(img, cat.image(kopi, frame: 1)), isTrue);
    expect(parseColor('#abc').toARGB32(), 0xFFAABBCC);
    expect(parseColor('#11223380').toARGB32(), 0x80112233);
    expect(unknownFurnitureIds(plan['furniture'], cat), {'tidak-ada'});
  });

  test(
    'world places furniture: solid blocks, flat rug and wall item do not',
    () {
      final world = FloorWorld(plan, roles, catalog: cat);
      expect(world.furn.map((f) => f.uid), isNot(contains('hantu')));
      final sofa = world.furn.firstWhere((f) => f.uid == 'sofa1');
      expect(world.walkable(sofa.tx + 1, sofa.ty), isFalse);
      final rug = world.furn.firstWhere((f) => f.uid == 'saj1');
      expect(world.walkable(rug.tx, rug.ty), isTrue);
      expect(rug.sortY, lessThan(rug.ty * 8));
      final board = world.furn.firstWhere((f) => f.uid == 'papan1');
      expect(board.sortY, lessThan(0));
      expect(world.spotsByAff['sleep'], hasLength(1));
      expect(world.approachFor(sofa.tx + 1, sofa.ty + 1, 'down'), isNotNull);
      // y grows upward from the footprint base
      final kopi = world.furn.firstWhere((f) => f.uid == 'kopi1');
      expect(kopi.y, (kopi.ty + 1) * 8 - 14);
    },
  );

  test('idle agent fetches coffee, uses the spot, then moves on', () {
    final sim = make([session('s1', 'r1', 'idle')]);
    final e = sim.ents['s1']!;
    expect(e.act?.aff, 'coffee');
    expect(sim.reserved, isNotEmpty);
    run(sim, 25);
    expect(e.pose, isNotNull, reason: 'standing at the machine');
    expect(e.pose!.kind, 'stand');
    expect(sim.activeFurn, contains('kopi1'));
    expect(e.actLabel, '= ngopi');
    run(sim, 20);
    // dwell over: the coffee rule picks again, as a fresh activity
    expect(e.pickSeq, greaterThan(0));
  });

  test('two agents never take the same spot', () {
    final sim = make([
      session('s1', 'r1', 'idle'),
      session('s2', 'r2', 'idle'),
    ]);
    final keys = [for (final e in sim.ents.values) e.act?.spot?.key];
    // one machine, one spot: the second one has no coffee and does something else
    expect(keys.where((k) => k == 'kopi1#0').length, lessThanOrEqualTo(1));
  });

  test(
    'working agent types at the desk; whiteboard use goes to the wall item',
    () {
      final sim = make([session('s1', 'r1', 'working', tool: 'TodoWrite')]);
      final e = sim.ents['s1']!;
      expect(e.act?.aff, 'whiteboard');
      run(sim, 30);
      expect(e.pose?.aff, 'whiteboard');
      // tool changes: after the minimum stay the rule switches back to the desk
      sim.sync([session('s1', 'r1', 'working', tool: 'Edit')]);
      run(sim, 8);
      sim.sync([session('s1', 'r1', 'working', tool: 'Edit')]);
      expect(e.act?.ruleId, 'kerja-lain');
      expect(e.pose, isNull);
      run(sim, 20);
      expect(e.mode, 'sit');
    },
  );

  test('long idle agent sleeps in bed and sits not at the desk', () {
    final sim = make([
      session('s1', 'r1', 'idle', idle: const Duration(minutes: 30)),
    ]);
    final e = sim.ents['s1']!;
    expect(e.act?.aff, 'sleep');
    run(sim, 30);
    expect(e.pose?.kind, 'sleep');
    expect(e.pose!.sortY, isNotNull);
    expect(sim.activeFurn, contains('kasur1'));
  });

  test('prayer window: wudhu then pray, once per prayer', () {
    final at = DateTime(2026, 10, 21, 12, 5);
    final today = FloorPrayer(FloorPrayer.dayKey(at), {'dzuhur': 12 * 60});
    final sim = make(
      [session('s1', 'r1', 'idle', now: at)],
      clock: () => at,
      prayer: today,
    );
    final e = sim.ents['s1']!;
    expect(e.act?.ruleId, 'sholat');
    expect(e.act?.aff, 'wudhu');
    final seen = <String>[];
    var prayedPose = false;
    for (var i = 0; i < 90; i++) {
      run(sim, 1);
      final k = '${e.act?.ruleId}:${e.act?.aff}';
      if (seen.isEmpty || seen.last != k) seen.add(k);
      prayedPose |= e.pose?.kind == 'pray';
    }
    expect(seen.take(2), ['sholat:wudhu', 'sholat:pray']);
    expect(prayedPose, isTrue);
    expect(e.prayed, isNotEmpty);
    // finished: the same prayer does not start again
    expect(seen.where((k) => k == 'sholat:wudhu'), hasLength(1));
  });

  test('prayer is skipped when there is nothing to pray on', () {
    plan['furniture'] = [
      for (final f in plan['furniture'] as List)
        if ((f as Map)['item'] != 'sajadah' && f['item'] != 'keran') f,
    ];
    final at = DateTime(2026, 10, 21, 12, 5);
    final sim = make(
      [session('s1', 'r1', 'idle', now: at)],
      clock: () => at,
      prayer: FloorPrayer(FloorPrayer.dayKey(at), {'dzuhur': 720}),
    );
    expect(sim.ents['s1']!.act?.ruleId, isNot('sholat'));
  });

  test('two idle agents next to each other chat, and stop together', () {
    // keep the coffee machine out of the picture so chat is the only option
    plan['furniture'] = [
      for (final f in plan['furniture'] as List)
        if ((f as Map)['item'] != 'kopi') f,
    ];
    final sim = make([
      session('s1', 'r1', 'idle', idle: const Duration(minutes: 1)),
      session('s2', 'r2', 'idle', idle: const Duration(minutes: 1)),
    ]);
    final a = sim.ents['s1']!, b = sim.ents['s2']!;
    // pull them next to each other so they count as neighbours
    final world = sim.world;
    final r = world.room('pantry')!;
    a
      ..x = (r.x + 6) * 8 + 4
      ..y = (r.y + 8) * 8 + 7;
    b
      ..x = (r.x + 8) * 8 + 4
      ..y = (r.y + 8) * 8 + 7;
    for (final e in [a, b]) {
      e
        ..q.clear()
        ..cur = null
        ..path = []
        ..mode = 'stand';
      sim.reserved.clear();
      e.act = null;
      e.pose = null;
      e.nextEval = 0;
    }
    sim.sync([
      session('s1', 'r1', 'idle', idle: const Duration(minutes: 1)),
      session('s2', 'r2', 'idle', idle: const Duration(minutes: 1)),
    ]);
    run(sim, 12);
    final chatting = [a, b].where((e) => e.act?.aff == 'chat').length;
    expect(chatting, 2, reason: '${a.act?.ruleId}/${b.act?.ruleId}');
    expect(a.act?.partner == b.id || b.act?.partner == a.id, isTrue);
    expect(a.actLabel, '= ngobrol');
    run(sim, 45);
    expect(a.act?.aff == 'chat' && b.act?.aff == 'chat', isFalse);
  });

  test('without furniture or catalog the classic placement still applies', () {
    plan.remove('furniture');
    final world = FloorWorld(plan, roles);
    final sim = FloorSim(world, roles)..sync([session('s1', 'r1', 'idle')]);
    run(sim, 20);
    expect(sim.ents['s1']!.act, isNull);
    expect(sim.ents['s1']!.desk, isNotNull);
  });

  test('swapping the world keeps characters and re-plans them', () {
    final sim = make([session('s1', 'r1', 'idle')]);
    run(sim, 25);
    final w2 = FloorWorld(plan, roles, catalog: cat);
    sim.swapWorld(w2);
    expect(sim.ents, hasLength(1));
    expect(sim.reserved, isEmpty);
    sim.sync([session('s1', 'r1', 'idle')]);
    run(sim, 30);
    expect(sim.ents['s1']!.act, isNotNull);
  });

  test('prayer stages cycle and times parse', () {
    expect(prayStage(0), 'berdiri');
    expect(prayStage(3.6), 'rukuk');
    expect(prayStage(8.0), 'sujud');
    expect(prayStage(17), 'berdiri');
    final p = FloorPrayer.fromJson({
      'date': '2026-10-21',
      'subuh': '04:41',
      'dzuhur': '11:49',
      'ashar': '15:08',
      'maghrib': '17:51',
      'isya': '19:01',
    });
    const names = ['subuh', 'dzuhur', 'ashar', 'maghrib', 'isya'];
    expect(p.active(DateTime(2026, 10, 21, 11, 55), 20, names), 'dzuhur');
    expect(p.active(DateTime(2026, 10, 21, 12, 30), 20, names), isNull);
    expect(p.active(DateTime(2026, 10, 22, 11, 55), 20, names), isNull);
  });

  test('renders every pose (set FLOOR_SHOT_DIR to keep the png)', () async {
    final sim = make([session('s1', 'r1', 'idle')]);
    final world = sim.world;
    final dir = Platform.environment['FLOOR_SHOT_DIR'];
    final cam = FloorCamera()..size = const Size(900, 360);
    final sc = <FloorEnt>[];
    final looks = sim.ents['s1']!.look;
    var i = 0;
    for (final (kind, face, t) in const [
      ('sit', 'down', 0.0),
      ('sleep', 'right', 0.0),
      ('pray', 'up', 1.0),
      ('pray', 'up', 4.0),
      ('pray', 'up', 6.5),
      ('pray', 'left', 9.0),
      ('play', 'down', 0.0),
      ('exercise', 'right', 0.0),
      ('read', 'down', 0.0),
      ('stand', 'down', 0.0),
    ]) {
      final e = FloorEnt('x$i', looks, 30.0 + i * 34, 40)
        ..pose = FloorPose(kind, face, kind == 'stand' ? 'coffee' : kind, -t);
      sc.add(e);
      i++;
    }
    final bg = bake(300, 60, (p) => p.r(0, 0, 300, 60, '#98AF9F'));
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(3);
    canvas.drawImage(bg, Offset.zero, Paint());
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (final e in sc) {
      drawPosedPerson(canvas, paint, e, 1.3);
    }
    final img = await rec.endRecording().toImage(900, 180);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (dir != null)
      File('$dir/poses.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(bytes!.lengthInBytes, greaterThan(100));
    expect(world.furn, isNotEmpty);
    expect(cam.size.width, 900);
  });

  test(
    'painter draws furniture, animation, active sprite and a pose',
    () async {
      final sim = make([
        session('s1', 'r1', 'idle', idle: const Duration(minutes: 30)),
      ]);
      run(sim, 30);
      final world = sim.world;
      final bg = buildBackground(world, roles, const []);
      final desks = {for (final d in world.desks) d: buildDeskBase(d)};
      final cam = FloorCamera()..size = const Size(1200, 700);
      cam.tz = 4;
      cam.tx = (room.x + 2) * 8;
      cam.ty = (room.y + 1) * 8;
      cam.jump();
      final rec = ui.PictureRecorder();
      FloorPainter(
        world: world,
        sim: sim,
        cam: cam,
        bg: bg,
        deskImages: desks,
        selected: null,
        repaint: ValueNotifier(0),
        dark: false,
        catalog: cat,
      ).paint(Canvas(rec), cam.size);
      final img = await rec.endRecording().toImage(1200, 700);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = Platform.environment['FLOOR_SHOT_DIR'];
      if (dir != null)
        File(
          '$dir/furniture_room.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(bytes!.lengthInBytes, greaterThan(1000));
    },
  );
}
