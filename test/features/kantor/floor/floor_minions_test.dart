import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_furniture.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_sim.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_world.dart';

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List)) x as Map<String, dynamic>,
];

Map<String, dynamic> _item(String id, int w, int h, List<String> affords, List<Map<String, dynamic>> spots) {
  final sw = w * 8;
  return {
    'id': id,
    'name': id,
    'cat': 'tes',
    'w': w,
    'h': h,
    'sprite': {'w': sw, 'h': 12, 'palette': {'a': '#6b4a2f'}, 'rows': [for (var y = 0; y < 12; y++) 'a' * sw]},
    'solid': true,
    'wall': false,
    'affords': affords,
    'spots': spots,
  };
}

Map<String, dynamic> _mini(int i) => {
  'id': 'mg-$i',
  'name': 'Magang$i',
  'look': {
    'color': '#F2842B', 'hair': '#2B1D14', 'skin': '#D9A47C', 'hairStyle': 'short',
    'outfit': 'kemeja', 'acc': 'topi', 'hijab': null, 'lanyard': '#3E6BA8',
  },
};

Map<String, dynamic> _view(int n, {bool auto = false}) => {
  'count': n, 'auto': auto, 'seed': 1, 'max': 30,
  'minions': [for (var i = 0; i < n; i++) _mini(i)],
};

void main() {
  final office = jsonDecode(File('test/features/kantor/floor/office_fixture.json').readAsStringSync()) as Map<String, dynamic>;

  group('Magang in the sim', () {
    late FloorSim sim;
    late List<Map<String, dynamic>> roles;
    late FurnitureCatalog cat;
    late FloorRoom pantry;
    late FloorFurn coffee;

    setUp(() {
      cat = FurnitureCatalog.fromJson({
        'version': 'mg',
        'behaviors': {'version': 1, 'rules': <dynamic>[], 'fallback': <dynamic>[]},
        'items': [
          _item('kopi', 2, 1, ['coffee'], [{'dx': 0, 'dy': 1, 'pose': 'stand', 'face': 'down'}]),
        ],
      });
      roles = _maps(office['roles']);
      final plan = jsonDecode(jsonEncode(office['plan'])) as Map<String, dynamic>;
      pantry = FloorRoom(_maps(plan['rooms']).firstWhere((r) => r['id'] == 'pantry'));
      plan['furniture'] = [{'uid': 'kopi1', 'item': 'kopi', 'x': pantry.x + 3, 'y': pantry.y + 5}];
      final world = FloorWorld(plan, roles, catalog: cat);
      coffee = world.furn.firstWhere((f) => f.uid == 'kopi1');
      sim = FloorSim(world, roles)..behaviors = cat.behaviors;
      sim.sync(const []);
    });

    void run(double s) {
      for (var i = 0; i < s * 20; i++) {
        sim.step(.05);
      }
    }

    Iterable<FloorEnt> minions() => sim.ents.values.where((e) => e.minion);

    test('spawn: count and identity come from the daemon, uniform has a lanyard', () {
      sim.minionsApply(_view(6));
      expect(minions().length, 6);
      expect(sim.minionCount, 6);
      final e = sim.ents['mg-2']!;
      expect(e.name, 'Magang2');
      expect(e.look.lanyard, '#3E6BA8');
      expect(e.look.color, '#F2842B');
      expect(e.s, isNull, reason: 'not a session: no agent, no tokens');
      // raising the count: the new ones come in from the lift one by one
      sim.minionsApply(_view(9));
      expect(minions().length, 6);
      run(4);
      expect(minions().length, 9);
      // zero sends everyone home
      sim.minionsApply(_view(0));
      run(60);
      expect(minions(), isEmpty);
    });

    test('usir: one walks to the lift and disappears, the others stay', () {
      sim.minionsApply(_view(4));
      run(1);
      sim.minionLeave('mg-1');
      expect(sim.ents['mg-1']!.mn!.state, 'leave');
      expect(sim.minionCount, 3);
      run(90);
      expect(sim.ents.containsKey('mg-1'), isFalse);
      expect(minions().length, 3);
    });

    test('they stay busy: activities by affordance, never idle for long', () {
      sim.minionsApply(_view(6));
      var used = false;
      final busy = <String>{};
      for (var i = 0; i < 20 * 400; i++) {
        sim.step(.05);
        for (final m in minions()) {
          if (m.pose?.aff == 'coffee') used = true;
          if (m.mn!.state == 'job' || m.mn!.state == 'act' || m.mn!.state == 'do') busy.add(m.id);
        }
      }
      expect(used, isTrue, reason: 'someone made coffee');
      expect(busy.length, 6, reason: 'every Magang did something');
    });

    test('courier: a dm carries an envelope from sender to receiver', () {
      sim.minionsApply(_view(3));
      run(3);
      final role = roles.map((r) => r['id']).whereType<String>().toList();
      sim.minionsLive({
        't': 'dm', 'office': 'x', 'from': role[0], 'to': role[1],
        'item': {'id': 'm1'},
      });
      sim.minionsLive({'t': 'dm', 'from': role[0], 'to': role[1], 'item': {'id': 'm1'}}); // same message: no second courier
      run(.5);
      final couriers = minions().where((m) => m.mn!.job?.key == 'dm:m1').toList();
      expect(couriers.length, 1);
      final c = couriers.single;
      var carried = false;
      for (var i = 0; i < 20 * 240 && c.mn!.job != null; i++) {
        sim.step(.05);
        if (c.carry == 'mail') carried = true;
      }
      expect(carried, isTrue);
      expect(c.mn!.job, isNull, reason: 'delivered');
      expect(c.carry, isNull);
    });

    test('courier: cards new / assigned / done, process failure, parcel', () {
      sim.minionsApply(_view(5));
      run(3);
      final r = roles.first['id'];
      sim.minionsCards([], [{'id': 'k1', 'col': 1, 'who': r}]);
      sim.minionsCards(
        [{'id': 'k1', 'col': 1, 'who': null}],
        [{'id': 'k1', 'col': 1, 'who': r}],
      );
      sim.minionsCards([{'id': 'k1', 'col': 3, 'who': r}], [{'id': 'k1', 'col': 4, 'who': r}]);
      sim.minionsLive({'t': 'proc', 'proc': {'id': 'p1', 'status': 'jalan'}});
      sim.minionsLive({'t': 'proc', 'proc': {'id': 'p1', 'status': 'gagal'}});
      run(.5);
      final keys = minions().map((m) => m.mn!.job?.key).whereType<String>().toSet();
      expect(keys, containsAll(['kartu:k1:baru', 'kartu:k1:tugas', 'kartu-selesai:k1', 'server:p1:gagal']));
      expect(minions().firstWhere((m) => m.mn!.job?.key == 'kartu-selesai:k1').carry, anyOf(isNull, 'folder'));
    });

    test('more jobs than Magang: the oldest are skipped, nobody crashes', () {
      sim.minionsApply(_view(2));
      run(3);
      for (var i = 0; i < 30; i++) {
        sim.minionsLive({'t': 'dm', 'from': 'a', 'to': 'b', 'item': {'id': 'x$i'}});
      }
      run(30);
      expect(minions().length, 2);
    });

    test('yield: a real agent takes the spot a Magang holds', () {
      sim.minionsApply(_view(1));
      final m = sim.ents['mg-0']!;
      final spot = coffee.spots.first;
      m.mn!.nextAt = 0;
      var held = false;
      for (var i = 0; i < 20 * 1500 && !held; i++) {
        sim.step(.05);
        if (sim.reserved[spot.key] == m.id) held = true;
      }
      expect(held, isTrue);
      // the owner walks up to the same machine: the Magang gives it up
      final me = sim.ownerEnter(kOwnerLook);
      me
        ..q.clear()
        ..cur = null
        ..x = spot.x
        ..y = spot.y;
      run(.5);
      final t = sim.target.value;
      expect(t, isNotNull);
      expect(t!.kind, 'use');
      sim.ownerUse(t);
      run(3);
      expect(sim.reserved[spot.key], 'owner');
      expect(m.act?.spot?.key == spot.key, isFalse, reason: 'the Magang stepped away');
      expect(m.pose?.aff == 'coffee' && m.x == spot.x && m.y == spot.y, isFalse);
    });

    test('auto mode: quiet at night, fewer when many agents work', () {
      expect(minionAutoCount(6, 0, DateTime(2026, 10, 21, 14)), 6);
      expect(minionAutoCount(6, 0, DateTime(2026, 10, 21, 23)), 1);
      expect(minionAutoCount(6, 5, DateTime(2026, 10, 21, 14)), 3);
      expect(minionAutoCount(6, 20, DateTime(2026, 10, 21, 14)), 1);
      expect(minionAutoCount(0, 0, DateTime(2026, 10, 21, 14)), 0);
    });

    test('card diff only reports real changes', () {
      expect(minionCardJobs([{'id': 1, 'col': 1}], [{'id': 1, 'col': 1}]), isEmpty);
      expect(minionCardJobs([{'id': 1, 'col': 1, 'who': 'a'}], [{'id': 1, 'col': 2, 'who': 'a'}]).single.kind, 'pindah');
      expect(minionCardJobs([{'id': 1, 'col': 3}], [{'id': 1, 'col': 4}]).single.kind, 'done');
    });
  });

  group('Magang room scenes', () {
    late FloorSim sim;
    late List<Map<String, dynamic>> roles;
    late FloorRoom pantry;
    late FloorFurn coffee;

    Map<String, dynamic> scene(String id, List<String> rooms, List<Map<String, dynamic>> steps, {List<int>? actors, double cooldown = 5, Map<String, dynamic> extra = const {}}) => {
      'id': id, 'title': id, 'rooms': rooms, 'weight': 1, 'cooldown': cooldown,
      'actors': ?actors,
      'steps': steps,
      ...extra,
    };

    void boot(List<Map<String, dynamic>> scenes) {
      final cat = FurnitureCatalog.fromJson({
        'version': 'sc',
        'behaviors': {'version': 1, 'rules': <dynamic>[], 'fallback': <dynamic>[]},
        'items': [_item('kopi', 2, 1, ['coffee'], [{'dx': 0, 'dy': 1, 'pose': 'stand', 'face': 'down'}])],
        'scenes': scenes,
      });
      roles = _maps(office['roles']);
      final plan = jsonDecode(jsonEncode(office['plan'])) as Map<String, dynamic>;
      pantry = FloorRoom(_maps(plan['rooms']).firstWhere((r) => r['id'] == 'pantry'));
      plan['furniture'] = [{'uid': 'kopi1', 'item': 'kopi', 'x': pantry.x + 3, 'y': pantry.y + 5}];
      final world = FloorWorld(plan, roles, catalog: cat);
      coffee = world.furn.firstWhere((f) => f.uid == 'kopi1');
      sim = FloorSim(world, roles)
        ..behaviors = cat.behaviors
        ..clock = (() => DateTime(2026, 10, 21, 9));
      sim.mh.scenes = cat.scenes;
      sim.sync(const []);
    }

    void run(double s) {
      for (var i = 0; i < s * 20; i++) {
        sim.step(.05);
      }
    }

    Iterable<FloorEnt> minions() => sim.ents.values.where((e) => e.minion);
    int inScene() => minions().where((m) => m.mn!.state == 'scene').length;

    test('scenes load from the catalog and tolerate bad ones', () {
      final cat = FurnitureCatalog.fromJson({
        'scenes': [
          {'id': 'ok', 'rooms': ['pantry'], 'steps': [{'wait': 1}]},
          {'id': 'tanpa-langkah', 'rooms': ['pantry'], 'steps': <dynamic>[]},
          {'rooms': ['x'], 'steps': [{}]},
          'rusak',
        ],
      });
      expect(cat.scenes.map((s) => s.id), ['ok']);
      expect(FurnitureCatalog.fromJson({'items': <dynamic>[]}).scenes, isEmpty);
    });

    test('hour weights, also past midnight', () {
      final sc = FurnScene.tryParse(scene('w', ['pantry'], [{'wait': 1}], extra: {
        'weight': 2,
        'hourWeights': [{'h': [7, 11], 'w': 3}, {'h': [22, 29], 'w': 0.5}],
      }))!;
      expect(sc.weightAt(9), 6);
      expect(sc.weightAt(14), 2);
      expect(sc.weightAt(23), 1);
      expect(sc.weightAt(3), 1);
      expect(sc.weightAt(5.5), 2);
    });

    test('only scenes whose room and furniture exist in this office are chosen', () {
      boot([
        scene('di-musholla', ['musholla'], [{'go': 'inside', 'say': 'x', 'wait': 1}]),
        scene('angkat-beban', ['pantry'], [{'go': 'aff:exercise', 'wait': 5}]),
        scene('ngopi', ['pantry'], [{'go': 'aff:coffee', 'say': '☕', 'wait': 3}]),
      ]);
      sim.minionsApply(_view(3));
      final seen = <String>{};
      for (var i = 0; i < 20 * 400; i++) {
        sim.step(.05);
        for (final r in sim.mh.runs) {
          seen.add(r.scene.id);
        }
      }
      expect(seen, {'ngopi'});
    });

    /// Steps until [cond] holds (at most [sec] simulated seconds).
    bool until(bool Function() cond, double sec) {
      for (var i = 0; i < sec * 20; i++) {
        if (cond()) return true;
        sim.step(.05);
      }
      return cond();
    }

    test('a scene uses the furniture with its pose and the balloon shows', () {
      boot([scene('ngopi', ['pantry'], [{'go': 'aff:coffee', 'say': '☕', 'wait': 6}], cooldown: 600)]);
      sim.minionsApply(_view(1));
      final m = sim.ents['mg-0']!;
      var posed = false, said = false;
      expect(until(() {
        if (m.pose?.aff == 'coffee') posed = true;
        if (m.mn!.state == 'scene' && m.bubble == '☕') said = true;
        return posed && said;
      }, 300), isTrue);
      expect(until(() => sim.mh.runs.isEmpty && m.mn!.state != 'scene', 60), isTrue, reason: 'the scene ends by itself');
      expect(m.bubble, '');
      expect(m.pose, isNull);
    });

    test('two actors meet face to face (sync) and the scene ends', () {
      boot([
        scene('ngobrol', ['pantry'], [
          {'actor': 0, 'go': 'inside', 'sync': true},
          {'actor': 'all', 'go': 'partner', 'face': 'partner', 'sync': true},
          {'actor': 'all', 'say': ['💬', '😂'], 'wait': [3, 4]},
        ], actors: [2, 2], cooldown: 600),
      ]);
      sim.minionsApply(_view(2));
      final a = sim.ents['mg-0']!, b = sim.ents['mg-1']!;
      var met = false;
      expect(until(() {
        if (a.mn!.state == 'scene' && b.mn!.state == 'scene' && a.bubble.isNotEmpty && b.bubble.isNotEmpty) {
          final dx = (a.x - b.x).abs() / 8, dy = (a.y - b.y).abs() / 8;
          if (dx + dy < 4) met = true;
        }
        return met;
      }, 400), isTrue, reason: 'they stand next to each other and talk');
      expect(until(() => sim.mh.runs.isEmpty, 60), isTrue);
      expect(inScene(), 0);
      expect(a.bubble, '');
      expect(b.bubble, '');
    });

    test('sent home: the whole scene is cancelled, nobody is stuck', () {
      boot([
        scene('ngobrol', ['pantry'], [
          {'actor': 'all', 'go': 'inside', 'sync': true},
          {'actor': 'all', 'say': '💬', 'wait': 30},
        ], actors: [2, 2], cooldown: 600),
      ]);
      sim.minionsApply(_view(2));
      expect(until(() => sim.mh.runs.isNotEmpty, 120), isTrue);
      final other = sim.mh.runs.first.actors.last;
      final leaver = sim.mh.runs.first.actors.first;
      sim.minionLeave(leaver.id);
      run(1);
      expect(sim.mh.runs, isEmpty);
      expect(other.mn!.state, isNot('scene'));
      expect(other.carry, isNull);
      expect(until(() => !sim.ents.containsKey(leaver.id), 120), isTrue);
    });

    test('a spot the owner holds is never taken; the owner takes one back from a scene', () {
      boot([scene('ngopi', ['pantry'], [{'go': 'aff:coffee', 'say': '☕', 'wait': 50}], cooldown: 0)]);
      final spot = coffee.spots.first;
      final me = sim.ownerEnter(kOwnerLook);
      me
        ..q.clear()
        ..cur = null
        ..x = spot.x
        ..y = spot.y;
      run(.5);
      sim.ownerUse(sim.target.value!);
      run(3);
      expect(sim.reserved[spot.key], 'owner');
      sim.minionsApply(_view(1));
      final m = sim.ents['mg-0']!;
      run(60);
      expect(sim.reserved[spot.key], 'owner', reason: 'never taken from the owner');
      expect(m.pose?.aff == 'coffee', isFalse);
      // the owner leaves: the Magang takes the spot, then the owner comes back and the scene gives way
      sim.ownerStick(0, 1);
      run(.3);
      sim.ownerStick(0, 0);
      expect(until(() => sim.reserved[spot.key] == m.id, 300), isTrue);
      me
        ..q.clear()
        ..cur = null
        ..x = spot.x
        ..y = spot.y;
      run(.5);
      final t = sim.target.value;
      expect(t?.kind, 'use');
      sim.ownerUse(t!);
      run(3);
      expect(sim.reserved[spot.key], 'owner');
      expect(m.act?.spot?.key == spot.key, isFalse, reason: 'the scene gave the spot up');
    });

    test('real work beats a scene: a courier pulls an actor out', () {
      boot([scene('ngopi', ['pantry'], [{'go': 'aff:coffee', 'wait': 60}], cooldown: 0)]);
      sim.minionsApply(_view(1));
      expect(until(() => inScene() == 1, 600), isTrue);
      final r = roles.map((x) => x['id']).whereType<String>().toList();
      sim.minionsLive({'t': 'dm', 'from': r[0], 'to': r[1], 'item': {'id': 'q1'}});
      run(1);
      expect(sim.ents['mg-0']!.mn!.job?.key, 'dm:q1');
      expect(sim.mh.runs, isEmpty);
    });

    test('the real scenes.json: parses, and runs for ten simulated minutes without trouble', () {
      final raw = jsonDecode(File('test/features/kantor/floor/scenes_fixture.json').readAsStringSync()) as Map<String, dynamic>;
      final parsed = [for (final x in raw['scenes'] as List) FurnScene.tryParse(x)];
      expect(parsed.every((x) => x != null), isTrue);
      boot([]);
      sim.mh.scenes = [for (final x in parsed) x!];
      sim.minionsApply(_view(8));
      final seen = <String>{};
      for (var i = 0; i < 20 * 600; i++) {
        sim.step(.05);
        for (final r in sim.mh.runs) {
          seen.add(r.scene.id);
        }
        if (i % 400 == 0) {
          for (final m in minions()) {
            // never lost outside the plan (a spot on furniture is fine: they step out of it when they go on)
            expect(m.x >= 0 && m.y >= 0 && m.x < sim.world.w * 8 && m.y < sim.world.h * 8, isTrue);
          }
        }
      }
      expect(seen, isNotEmpty);
      expect(minions().length, 8);
    });
  });
}
