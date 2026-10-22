import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_furniture.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_owner_ui.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_sim.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_world.dart';
import 'package:ghina/presentation/features/kantor/floor/kantor_floor_tab.dart';

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List)) x as Map<String, dynamic>,
];

Map<String, dynamic> _item(
  String id,
  int w,
  int h,
  List<String> affords,
  List<Map<String, dynamic>> spots,
) {
  final sw = w * 8;
  return {
    'id': id,
    'name': id,
    'cat': 'tes',
    'w': w,
    'h': h,
    'sprite': {
      'w': sw,
      'h': 12,
      'palette': {'a': '#6b4a2f'},
      'rows': [for (var y = 0; y < 12; y++) 'a' * sw],
    },
    'solid': true,
    'wall': false,
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

Map<String, dynamic> _catalogJson() => {
  'version': 'owner',
  'behaviors': {'version': 1, 'rules': <dynamic>[], 'fallback': <dynamic>[]},
  'items': [
    _item('kopi', 2, 1, ['coffee'], [_spot(0, 1, 'stand')]),
    _item('papan', 3, 1, ['whiteboard'], [_spot(1, 1, 'stand', 'up')]),
    _item('rak-buku', 3, 1, ['read'], [_spot(1, 1, 'stand', 'up')]),
  ],
};

/// The floor ticker never stops, so pumpAndSettle would time out.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final office =
      jsonDecode(
            File(
              'test/features/kantor/floor/office_fixture.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('owner in the sim', () {
    late FurnitureCatalog cat;
    late Map<String, dynamic> plan;
    late List<Map<String, dynamic>> roles;
    late FloorSim sim;
    late FloorRoom pantry;

    setUp(() {
      cat = FurnitureCatalog.fromJson(_catalogJson());
      roles = _maps(office['roles']);
      plan = jsonDecode(jsonEncode(office['plan'])) as Map<String, dynamic>;
      pantry = FloorRoom(
        _maps(plan['rooms']).firstWhere((r) => r['id'] == 'pantry'),
      );
      final x = pantry.x, y = pantry.y;
      plan['furniture'] = [
        {'uid': 'kopi1', 'item': 'kopi', 'x': x + 3, 'y': y + 5},
        {'uid': 'papan1', 'item': 'papan', 'x': x + 12, 'y': y + 5},
        {'uid': 'rak1', 'item': 'rak-buku', 'x': x + 20, 'y': y + 5},
      ];
      final world = FloorWorld(plan, roles, catalog: cat);
      sim = FloorSim(world, roles)..behaviors = cat.behaviors;
      sim.sync(const []);
    });

    void run(double seconds) {
      for (var i = 0; i < seconds * 20; i++) {
        sim.step(.05);
      }
    }

    FloorEnt enterAt(double x, double y) {
      final e = sim.ownerEnter(kOwnerLook);
      e
        ..q.clear()
        ..cur = null
        ..x = x
        ..y = y;
      return e;
    }

    test('the joystick walks the owner and walls stop it', () {
      final t = sim.world.randomSpot('pantry', 3)!;
      final e = enterAt(t.tx * 8 + 4, t.ty * 8 + 7);
      expect(sim.ownerActive, isTrue);
      final x0 = e.x, y0 = e.y;
      sim.ownerStick(1, 0);
      run(.5);
      sim.ownerStick(0, 1);
      run(.5);
      expect((e.x - x0).abs() + (e.y - y0).abs(), greaterThan(8));
      expect(e.mode, 'walk');
      sim.ownerStick(0, 0);
      run(.1);
      expect(e.mode, 'stand');
      // pushing against the outside of the plan never leaves the walkable grid
      sim.ownerStick(-1, -1);
      run(60);
      expect(sim.world.walkable((e.x / 8).floor(), (e.y / 8).floor()), isTrue);
    });

    test('next to the coffee machine the owner can make coffee', () {
      final f = sim.world.furn.firstWhere((f) => f.uid == 'kopi1');
      final spot = f.spots.first;
      final e = enterAt(spot.x, spot.y);
      run(.5);
      final t = sim.target.value;
      expect(t, isNotNull);
      expect(t!.kind, 'use');
      expect(t.aff, 'coffee');
      expect(t.label, 'Ngopi');
      expect(t.spot, same(spot));

      sim.ownerUse(t);
      run(3);
      expect(e.pose?.aff, 'coffee');
      expect(sim.reserved[spot.key], 'owner');
      expect(sim.activeFurn, contains('kopi1'));
      expect(sim.target.value?.kind, 'stop');

      // moving ends the activity and frees the spot
      sim.ownerStick(0, 1);
      run(.3);
      expect(e.pose, isNull);
      expect(sim.reserved.containsKey(spot.key), isFalse);
      expect(sim.activeFurn, isNot(contains('kopi1')));
    });

    test('whiteboard and bookshelf open tabs instead of an activity', () {
      final board = sim.world.furn.firstWhere((f) => f.uid == 'papan1');
      enterAt(board.spots.first.x, board.spots.first.y);
      run(.5);
      expect(sim.target.value?.kind, 'tab');
      expect(sim.target.value?.tab, 'board');
      final shelf = sim.world.furn.firstWhere((f) => f.uid == 'rak1');
      sim.owner!
        ..x = shelf.spots.first.x
        ..y = shelf.spots.first.y;
      run(.5);
      expect(sim.target.value?.tab, 'wiki');
    });

    test(
      'an agent in reach turns around and waves, and becomes the target',
      () {
        final s = {
          'sid': 'a1',
          'room': 'pantry',
          'role': 'r1',
          'kind': 'kantor',
          'status': 'idle',
          'lastSeen': DateTime.now().toUtc().toIso8601String(),
          'slot': 0,
          'subs': <dynamic>[],
        };
        sim.sync([s]);
        run(30);
        final a = sim.ents['a1']!;
        final e = enterAt(a.x + 10, a.y);
        run(.5);
        expect(sim.target.value?.kind, 'agent');
        expect(sim.target.value?.ent, same(a));
        expect(a.waveUntil, greaterThan(sim.now));
        // the agent is not removed by a session sync while the owner is around
        sim.sync([s]);
        expect(sim.ents.containsKey('owner'), isTrue);
        expect(e.owner, isTrue);
      },
    );

    test(
      'leaving walks to the lift and fades out; web owner mirrors position',
      () {
        final t = sim.world.randomSpot('pantry', 3)!;
        enterAt(t.tx * 8 + 4, t.ty * 8 + 7);
        sim.ownerLeave();
        expect(sim.ownerActive, isFalse);
        run(60);
        expect(sim.ents.containsKey('owner'), isFalse);

        sim.ownerRemote(
          present: true,
          x: t.tx * 8 + 4,
          y: t.ty * 8 + 7,
          face: 'left',
        );
        final r = sim.owner!;
        expect(r.x, t.tx * 8 + 4);
        sim.ownerRemote(
          present: true,
          x: t.tx * 8 + 24,
          y: t.ty * 8 + 7,
          face: 'left',
        );
        run(1);
        expect(r.x, closeTo(t.tx * 8 + 24, 1));
        expect(r.dir, 'left');
        sim.ownerRemote(present: false, x: 0, y: 0, face: 'down');
        expect(sim.owner, isNull);
      },
    );
  });

  testWidgets('joystick reports a vector and releases to zero', (tester) async {
    final seen = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: OwnerJoystick(onChanged: (x, y) => seen.add(Offset(x, y))),
        ),
      ),
    );
    final c = tester.getCenter(find.byType(OwnerJoystick));
    final g = await tester.startGesture(c);
    await g.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(seen.last.dx, closeTo(1, .001));
    expect(seen.last.dy.abs(), lessThan(.01));
    await g.moveBy(const Offset(-200, -200));
    await tester.pump();
    expect(seen.last.dy, lessThan(0));
    await g.up();
    await tester.pump();
    expect(seen.last, Offset.zero);
  });

  group('on the floor tab', () {
    late HttpServer server;
    late String fixture;
    final posts = <String>[];

    setUpAll(() async {
      HttpOverrides.global = null;
      fixture = File(
        'test/features/kantor/floor/office_fixture.json',
      ).readAsStringSync();
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (req.method != 'GET')
          posts.add('${req.method} ${req.uri.path} $body');
        switch ((req.method, req.uri.path)) {
          case ('GET', '/api/offices/contoh'):
            req.response.write(fixture);
          case ('GET', '/api/inbox'):
            req.response.write('[]');
          case ('GET', '/api/offices/contoh/owner'):
            req.response.statusCode = 404;
            req.response.write('{}');
          default:
            req.response.write(jsonEncode({'ok': true}));
        }
        await req.response.close();
      });
    });

    tearDownAll(() => server.close(force: true));

    testWidgets(
      'enter, walk with the stick, meet an agent and tap its shoulder',
      (tester) async {
        posts.clear();
        final events = StreamController<Map<String, dynamic>>.broadcast();
        addTearDown(events.close);
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        FloorSim? sim;
        await tester.runAsync(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                kantorApiProvider.overrideWithValue(
                  KantorApi(
                    KantorConfig(
                      baseUrl: 'http://127.0.0.1:${server.port}',
                      token: 't',
                    ),
                  ),
                ),
                kantorEventsProvider.overrideWith((ref) => events.stream),
              ],
              child: MaterialApp(
                theme: GhinaTheme.light(),
                home: Scaffold(
                  body: KantorFloorTab(
                    officeId: 'contoh',
                    onSim: (s) => sim = s,
                  ),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 600));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(sim, isNotNull);
        expect(find.byType(OwnerJoystick), findsNothing);

        await tester.tap(find.byKey(const ValueKey('owner-enter')));
        await tester.pump();
        expect(find.byType(OwnerJoystick), findsOneWidget);
        expect(find.byKey(const ValueKey('owner-enter')), findsNothing);
        final me = sim!.owner!;
        expect(me.owner, isTrue);

        // let the lift scene finish, then push the stick in whichever way is open
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(seconds: 4));
        var moved = false;
        for (final d in const [
          Offset(0, 80),
          Offset(80, 0),
          Offset(-80, 0),
          Offset(0, -80),
        ]) {
          final x0 = me.x, y0 = me.y;
          final g = await tester.startGesture(
            tester.getCenter(find.byType(OwnerJoystick)),
          );
          await g.moveBy(d);
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await g.up();
          await tester.pump();
          if ((me.x - x0).abs() + (me.y - y0).abs() > 4) {
            moved = true;
            break;
          }
        }
        expect(moved, isTrue);

        // stand next to an agent: a big action button shows up
        final a = sim!.ents['sess-1']!;
        final sit = a.mode == 'sit' && a.desk != null;
        me
          ..x = sit ? a.desk!.seatX + 8 : a.x + 8
          ..y = sit ? a.desk!.seatY : a.y;
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('owner-action')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('owner-action')));
        await _settle(tester);
        expect(find.byKey(const ValueKey('agent-chat')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent-screen')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent-card')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('agent-tap')));
        await _settle(tester);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('tap-esc')));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await _settle(tester);
        expect(
          posts.any(
            (p) =>
                p.startsWith('POST /api/sessions/sess-1/action') &&
                p.contains('"esc"'),
          ),
          isTrue,
        );
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        // position goes to the server while present
        expect(
          posts.any(
            (p) =>
                p.startsWith('PUT /api/offices/contoh/owner') &&
                p.contains('"present":true'),
          ),
          isTrue,
        );

        // leaving tells the server too
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Keluar kantor'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        expect(find.byType(OwnerJoystick), findsNothing);
        expect(
          posts.any(
            (p) =>
                p.startsWith('PUT /api/offices/contoh/owner') &&
                p.contains('"present":false'),
          ),
          isTrue,
        );
        // let toast badges time out before the tree goes away
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
