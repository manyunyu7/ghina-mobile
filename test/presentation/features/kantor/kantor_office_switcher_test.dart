import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_shell_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('switcher sheet filters, and picking keeps the tab', (t) async {
    t.view.physicalSize = const Size(400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/kantor/o/a?tab=agen',
      routes: [
        GoRoute(
          path: '/kantor/o/:office',
          builder: (_, s) => KantorShellPage(
            officeId: s.pathParameters['office']!,
            tab: s.uri.queryParameters['tab'],
          ),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorStateProvider.overrideWith(
            (_) async => {
              'offices': [
                {
                  'id': 'a',
                  'name': 'Alfa',
                  'fav': true,
                  'style': 'Folder induk',
                  'sessions': [],
                },
                {
                  'id': 'b',
                  'name': 'Bravo',
                  'sessions': [
                    {'sid': 's', 'status': 'working'},
                  ],
                },
              ],
              'inbox': [],
            },
          ),
          kantorOfficeProvider.overrideWith(
            (ref, id) async => {
              'name': id == 'a' ? 'Alfa' : 'Bravo',
              'sessions': [],
            },
          ),
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Alfa').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah kantor'), findsOneWidget);
    expect(find.text('Sedang aktif'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'brav');
    await t.pump(const Duration(milliseconds: 600));
    expect(
      find.descendant(
        of: find.byType(ChunkyBottomSheet),
        matching: find.text('Alfa'),
      ),
      findsNothing,
    );
    await t.tap(find.text('Bravo').last);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah kantor'), findsNothing);
    expect(router.state.uri.toString(), '/kantor/o/b?tab=agen');
    expect(t.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });
}
