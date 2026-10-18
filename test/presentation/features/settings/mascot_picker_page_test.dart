import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/settings/pages/mascot_picker_page.dart';
import 'package:ghina/presentation/state/mascot_kind_provider.dart';

import '../../design_system/mascot_rig_test.dart' show paintedKind;
import '../transactions/_feature_harness.dart' show settle;

void main() {
  late InMemoryMascotKindPrefs prefs;
  late ProviderContainer c;

  setUp(() {
    prefs = InMemoryMascotKindPrefs();
    c = ProviderContainer(
      overrides: [mascotKindPrefsProvider.overrideWithValue(prefs)],
    );
  });
  tearDown(() => c.dispose());

  Future<void> pumpPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          // Like GhinaApp: the choice reaches every route (sheets too).
          builder: (_, child) => MascotKindScope(child: child!),
          home: const MascotPickerPage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Advances frames without pumpAndSettle (the mascots animate forever).
  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows the mascots live, the tree selected by default', (
    tester,
  ) async {
    await pumpPicker(tester);
    expect(find.text('Pilih maskot'), findsOneWidget);
    for (final k in MascotKind.values.take(6)) {
      final tile = find.byKey(ValueKey('mascot-tile-${k.id}'));
      expect(tile, findsOneWidget);
      expect(paintedKind(tester, tile), k);
    }
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // The header speech uses the chosen mascot.
    expect(
      paintedKind(tester, find.byKey(const ValueKey('mascot-current'))),
      MascotKind.pohon,
    );
    // The last mascots are reachable by scrolling.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('mascot-tile-cendrawasih')),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    await frames(tester, 2);
    expect(
      paintedKind(
        tester,
        find.byKey(const ValueKey('mascot-tile-cendrawasih')),
      ),
      MascotKind.cendrawasih,
    );
  });

  testWidgets('preview moods, then "Pakai maskot ini" switches every '
      'MascotView', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byKey(const ValueKey('mascot-tile-kucing')));
    await frames(tester);
    final preview = find.byKey(const ValueKey('mascot-preview'));
    expect(preview, findsOneWidget);
    expect(paintedKind(tester, preview), MascotKind.kucing);
    expect(find.text(MascotKind.kucing.pitch), findsOneWidget);

    // Preview each mood.
    for (final m in MascotMood.values) {
      await tester.tap(find.widgetWithText(ChunkyChip, m.label));
      await frames(tester, 2);
      expect(tester.widget<MascotView>(preview).mood, m);
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(of: preview, matching: find.byType(CustomPaint)),
          )
          .painter;
      expect((painter! as MascotRigPainter).mood, m);
    }

    // Still the tree until confirmed.
    expect(c.read(mascotKindProvider), MascotKind.pohon);

    await tester.tap(find.byKey(const ValueKey('mascot-use')));
    await frames(tester, 8);

    expect(c.read(mascotKindProvider), MascotKind.kucing);
    expect(prefs.value, MascotKind.kucing);
    expect(preview, findsNothing); // sheet closed
    expect(find.textContaining('jadi maskotmu'), findsOneWidget); // toast

    // Every MascotView without an explicit kind now paints the cat.
    expect(
      paintedKind(tester, find.byKey(const ValueKey('mascot-current'))),
      MascotKind.kucing,
    );
    expect(find.text('Halo, aku Kucing Oren!'), findsOneWidget);

    // Reopening the chosen one shows it's already in use.
    await tester.tap(find.byKey(const ValueKey('mascot-tile-kucing')));
    await frames(tester);
    expect(find.text('LAGI DIPAKAI'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // toast timers
  });
}
