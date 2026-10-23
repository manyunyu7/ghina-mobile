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
}
