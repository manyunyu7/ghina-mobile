import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_widgets.dart';

void main() {
  const labels = [
    'Kartu saya',
    'Belum ditugaskan',
    'Terblokir',
    'Menunggu',
    'Lama disembunyikan',
  ];

  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets('chip strip fits text at 360px, textScaler $scale', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      await t.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.light(),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                KChipStrip(
                  children: [
                    for (final l in labels)
                      ChunkyChip(label: l, selected: false, onTap: () {}),
                    ChunkyChip(
                      label: 'Reset',
                      selected: true,
                      icon: Icons.close_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );

      expect(t.takeException(), isNull);

      final strip = t.getSize(find.byType(KChipStrip)).height;
      for (final l in labels) {
        final chip = t.getSize(find.widgetWithText(ChunkyChip, l)).height;
        final text = t.getSize(find.text(l)).height;
        expect(chip, greaterThanOrEqualTo(text), reason: '$l at $scale');
        expect(
          strip,
          greaterThanOrEqualTo(chip),
          reason: 'strip clips $l at $scale',
        );
      }

      // Scrolls horizontally: last chip reachable.
      await t.drag(find.byType(KChipStrip), const Offset(-600, 0));
      await t.pump();
      expect(find.text('Reset'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
