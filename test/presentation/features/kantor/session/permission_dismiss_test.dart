import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/permission_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [GhinaTokens.light]),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('tombol ✕ menutup kartu tanpa menjawab', (t) async {
    var closed = 0;
    await t.pumpWidget(
      _wrap(
        KantorPermissionCard(
          item: const {
            'id': 'ib1',
            'tool': 'AskUserQuestion',
            'summary':
                '{"questions":[{"question":"Pakai kode galeri yang mana?"}]}',
            'held': false,
          },
          who: 'Budi Contoh',
          onDecide: (_) {},
          onAnswer: (_) {},
          onDismiss: () => closed++,
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('dismiss-ib1')));
    expect(closed, 1);
  });

  testWidgets('tanpa onDismiss tidak ada tombol ✕', (t) async {
    await t.pumpWidget(
      _wrap(
        KantorPermissionCard(
          item: const {
            'id': 'ib2',
            'tool': 'Bash',
            'summary': 'ls',
            'held': true,
          },
          onDecide: (_) {},
          onAnswer: (_) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('dismiss-ib2')), findsNothing);
  });
}
