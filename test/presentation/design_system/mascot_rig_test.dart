import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

/// The painter a MascotView under [finder] is currently using.
CustomPainter? painterOf(WidgetTester tester, Finder finder) => tester
    .widget<CustomPaint>(
      find.descendant(of: finder, matching: find.byType(CustomPaint)).first,
    )
    .painter;

/// The mascot kind a MascotView under [finder] paints.
MascotKind? paintedKind(WidgetTester tester, Finder finder) =>
    switch (painterOf(tester, finder)) {
      MascotRigPainter(:final kind) => kind,
      MascotPainter() => MascotKind.pohon,
      _ => null,
    };

Widget _wrap(Widget child, {MascotKind? choice}) {
  final app = MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
  return choice == null ? app : MascotChoice(kind: choice, child: app);
}

void main() {
  group('painters', () {
    test('every kind × every mood × several phases paints without '
        'throwing', () {
      for (final kind in MascotKind.values) {
        for (final mood in MascotMood.values) {
          for (final phase in const [0.0, 0.13, 0.42, 0.5, 0.77, 0.9, 0.999]) {
            for (final size in const [Size(40, 40), Size(180, 120)]) {
              final rec = ui.PictureRecorder();
              final canvas = Canvas(rec);
              // Rig version of every kind (tree included)...
              MascotRigPainter(
                kind: kind,
                mood: mood,
                phase: phase,
                shadowColor: Colors.black12,
              ).paint(canvas, size);
              // ...and what MascotView actually uses.
              mascotPainterFor(
                kind,
                mood: mood,
                phase: phase,
              ).paint(canvas, size);
              rec.endRecording().dispose();
            }
          }
        }
      }
    });

    test('the tree stays the classic painter; others use the rig', () {
      expect(
        mascotPainterFor(MascotKind.pohon, mood: MascotMood.happy),
        isA<MascotPainter>(),
      );
      for (final k in MascotKind.values.skip(1)) {
        final p = mascotPainterFor(k, mood: MascotMood.happy);
        expect(p, isA<MascotRigPainter>());
        expect((p as MascotRigPainter).kind, k);
      }
    });

    test('repaints on phase / mood / kind changes only', () {
      final a = MascotRigPainter(kind: MascotKind.koin, mood: MascotMood.sad);
      expect(
        a.shouldRepaint(
          MascotRigPainter(kind: MascotKind.koin, mood: MascotMood.sad),
        ),
        isFalse,
      );
      expect(
        a.shouldRepaint(
          MascotRigPainter(
            kind: MascotKind.koin,
            mood: MascotMood.sad,
            phase: .5,
          ),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          MascotRigPainter(kind: MascotKind.kura, mood: MascotMood.sad),
        ),
        isTrue,
      );
    });
  });

  group('MascotView', () {
    testWidgets('defaults to the tree without a MascotChoice', (tester) async {
      await tester.pumpWidget(_wrap(const MascotView()));
      expect(paintedKind(tester, find.byType(MascotView)), MascotKind.pohon);
    });

    testWidgets('paints the MascotChoice kind; explicit kind wins', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MascotView(key: Key('chosen'), size: 60),
              MascotView(key: Key('explicit'), size: 60, kind: MascotKind.ayam),
            ],
          ),
          choice: MascotKind.kapibara,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        paintedKind(tester, find.byKey(const Key('chosen'))),
        MascotKind.kapibara,
      );
      expect(
        paintedKind(tester, find.byKey(const Key('explicit'))),
        MascotKind.ayam,
      );
    });

    testWidgets('every kind animates every mood in a real view', (
      tester,
    ) async {
      var kind = MascotKind.pohon;
      var mood = MascotMood.happy;
      late StateSetter set;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, s) {
              set = s;
              return MascotView(kind: kind, mood: mood, size: 120);
            },
          ),
        ),
      );
      for (final k in MascotKind.values) {
        for (final m in MascotMood.values) {
          set(() {
            kind = k;
            mood = m;
          });
          await tester.pump(const Duration(milliseconds: 170));
          await tester.pump(const Duration(milliseconds: 900));
          expect(tester.takeException(), isNull);
          expect(paintedKind(tester, find.byType(MascotView)), k);
        }
      }
    });
  });
}
