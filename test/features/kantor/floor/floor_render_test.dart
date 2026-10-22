import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_painter.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_scene.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_sim.dart';
import 'package:ghina/presentation/features/kantor/floor/floor_world.dart';

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List)) x as Map<String, dynamic>,
];

void main() {
  final office =
      jsonDecode(
            File(
              'test/features/kantor/floor/office_fixture.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('world builds, sim places characters, painter renders', () async {
    final roles = _maps(office['roles']);
    final world = FloorWorld(office['plan'] as Map<String, dynamic>, roles);
    expect(world.rooms, isNotEmpty);
    expect(world.desks, isNotEmpty);
    final sim = FloorSim(world, roles)..sync(_maps(office['sessions']));
    for (var i = 0; i < 400; i++) {
      sim.step(.05);
    }
    expect(sim.ents, isNotEmpty);
    // everybody ended up inside the world
    for (final e in sim.ents.values) {
      expect(e.x, inInclusiveRange(0, world.w * 8));
      expect(e.y, inInclusiveRange(0, world.h * 8));
    }
    final bg = buildBackground(world, roles, _maps(office['cards']));
    final desks = {for (final d in world.desks) d: buildDeskBase(d)};
    final cam = FloorCamera()..size = const Size(1200, 900);
    cam.tz = cam.fitZoom(world);
    cam.tx = 0;
    cam.ty = 0;
    cam.clamp(world);
    cam.jump();

    Future<void> shot(String name) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      FloorPainter(
        world: world,
        sim: sim,
        cam: cam,
        bg: bg,
        deskImages: desks,
        selected: null,
        repaint: ValueNotifier(0),
        dark: false,
      ).paint(canvas, cam.size);
      final img = await rec.endRecording().toImage(1200, 900);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = Platform.environment['FLOOR_SHOT_DIR'];
      if (dir != null)
        File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await shot('floor_fit');
    final web = world.room('web')!;
    cam.tz = 3.0;
    cam.tx = web.x * 8 - 20;
    cam.ty = web.y * 8 - 20;
    cam.jump();
    await shot('floor_web');
  });
}
