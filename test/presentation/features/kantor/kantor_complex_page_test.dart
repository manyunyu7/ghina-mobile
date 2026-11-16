import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    }),
  );

  testWidgets('Kompleks lists offices, inbox and active agents', (t) async {
    final state = {
      'offices': [
        {
          'id': 'a',
          'name': 'Kantor A',
          'fav': true,
          'style': 'Satu repo',
          'sessions': [
            {
              'sid': 's1',
              'status': 'working',
              'title': 'Dina',
              'look': {
                'name': 'Dina',
                'color': '#2F5D9E',
                'hair': '#2B1D14',
                'skin': '#F1C9A5',
              },
            },
          ],
          'cards': {'open': 3},
          'monthCost': 12.5,
        },
      ],
      'inbox': [
        {
          'id': 'i1',
          'office': 'a',
          'who': 'Dina',
          'tool': 'Bash',
          'summary': 'ls',
          'held': true,
        },
      ],
      'loose': [],
    };
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/kantor',
      routes: [
        GoRoute(path: '/kantor', builder: (_, _) => const KantorComplexPage()),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          kantorStateProvider.overrideWith((_) async => state),
          kantorEndedProvider.overrideWith((_) async => const []),
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Kantor A'), findsWidgets);
    expect(find.text('IZINKAN'), findsOneWidget);
    expect(find.text('Dina'), findsWidgets);
  });

  group('wide layout (Galaxy Fold inner display)', () {
    Map<String, dynamic> office(String id) => {
      'id': id,
      'name': 'Kantor $id',
      'sessions': [],
      'cards': {'open': 1},
      'monthCost': 1,
    };
    final state = {
      'offices': [office('A'), office('B'), office('C')],
      'inbox': [],
      'loose': [],
    };

    Future<void> pumpAt(WidgetTester t, double width) async {
      t.view.physicalSize = Size(width, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: '/kantor',
        routes: [
          GoRoute(
            path: '/kantor',
            builder: (_, _) => const KantorComplexPage(),
            routes: [
              GoRoute(
                path: 'o/:id',
                builder: (_, s) => Text('office ${s.pathParameters['id']}'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            kantorStateProvider.overrideWith((_) async => state),
            kantorEndedProvider.overrideWith((_) async => const []),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('400dp keeps the single-column list', (t) async {
      await pumpAt(t, 400);
      final a = t.getTopLeft(find.text('Kantor A'));
      final b = t.getTopLeft(find.text('Kantor B'));
      final c = t.getTopLeft(find.text('Kantor C'));
      expect(b.dx, a.dx);
      expect(c.dx, a.dx);
      expect(b.dy, greaterThan(a.dy));
      expect(c.dy, greaterThan(b.dy));
      // Same full-width cards as before: page padding on both sides.
      final search = t.getRect(find.byKey(const ValueKey('kantor-search-bar')));
      expect(search.left, GhinaSpace.page);
      expect(search.right, 400 - GhinaSpace.page);
    });

    testWidgets('900dp puts office cards side by side', (t) async {
      await pumpAt(t, 900);
      final a = t.getTopLeft(find.text('Kantor A'));
      final b = t.getTopLeft(find.text('Kantor B'));
      expect(b.dx, isNot(a.dx));
      expect(b.dy, a.dy);
      // Tapping a card in the grid still opens the office.
      await t.tap(find.text('Kantor B'));
      await t.pumpAndSettle();
      expect(find.text('office B'), findsOneWidget);
    });

    testWidgets('very wide screens center the content at 1280dp', (t) async {
      await pumpAt(t, 1400);
      final split = t.getRect(
        find.byKey(const ValueKey('kantor-complex-split')),
      );
      expect(split.width, kantorComplexMaxContentWidth);
      expect(split.center.dx, 700);
      // Kartu ringkas berjajar: A, B, C dalam satu baris.
      final a = t.getTopLeft(find.text('Kantor A'));
      final c = t.getTopLeft(find.text('Kantor C'));
      expect(c.dy, a.dy);
      expect(c.dx, greaterThan(a.dx));
    });

    test('column count follows the Fold postures', () {
      // Fold tegak (±690dp, satu kolom di tengah).
      expect(kantorComplexColumns(690 - 2 * GhinaSpace.page), 3);
      expect(kantorComplexColumns(560), 2);
      // Layar dalam Fold (±830dp): kolom kiri di samping panel kanan.
      expect(kantorComplexColumns(474), 2);
      // Tablet 1200dp dan layar sangat lebar.
      expect(kantorComplexColumns(784), 3);
      expect(kantorComplexColumns(904), 4);
      expect(kantorComplexColumns(300), 2);
      expect(kantorComplexAsideWidth(790), 300);
      expect(kantorComplexAsideWidth(1160), 360);
    });
  });
}
