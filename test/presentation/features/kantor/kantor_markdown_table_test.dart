import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/widgets/kantor_markdown.dart';

const _table = '''
| Bulan | Google Play | Keterangan panjang sekali untuk menguji pembungkusan teks di kolom | Total |
|:--|:--|:--|--:|
| Januari | Pendaftaran akun pengembang | Biaya sekali bayar untuk akun developer | 25 |
| Februari | Langganan | Bulanan | 1.000.000 |
''';

void main() {
  testWidgets(
    'wide table scrolls horizontally without overflow or word splitting',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: KantorMarkdown(_table)),
          ),
        ),
      );
      expect(tester(t), isNull); // no layout exception
      final scroll = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(scroll, findsOneWidget);
      final pos = t
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      expect(pos.maxScrollExtent, greaterThan(0));
      // "Pendaftaran" stays on one line: a one-word cell is never narrower than the word
      final h = t.getSize(find.text('Pendaftaran akun pengembang')).height;
      expect(h, lessThan(80));
      final bulan = t.getSize(find.text('Januari'));
      expect(bulan.height, lessThan(24));
      await t.drag(scroll, const Offset(-200, 0));
      await t.pump();
      expect(pos.pixels, greaterThan(0));
    },
  );
}

Object? tester(WidgetTester t) => t.takeException();
