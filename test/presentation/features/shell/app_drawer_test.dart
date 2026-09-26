import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/usecase_providers.dart';

import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/home/pages/home_page.dart';
import 'package:ghina/presentation/features/profile/pages/profile_page.dart';
import 'package:ghina/presentation/features/shell/app_menu.dart';
import 'package:ghina/presentation/features/shell/app_shell.dart';
import 'package:ghina/presentation/features/tasks/pages/tasks_page.dart';
import 'package:ghina/presentation/features/transactions/pages/transactions_page.dart';
import 'package:ghina/presentation/state/balance_privacy_provider.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/_helpers.dart' show loadGhinaFonts, saveShot;
import '../tasks/_tasks_harness.dart' hide settle, wallet;
import 'package:ghina/presentation/state/session_controller.dart';

import 'test_utils.dart'
    show
        FakeSession,
        sampleBudgets,
        sampleDashboard,
        sampleSubs,
        settle,
        testUser;

const _tabs = ['/home', '/transactions', '/tasks', '/profile'];

/// The real shell with the four real tab pages over the Tugas harness;
/// every other location renders `route:<uri>`.
class _Shell {
  _Shell() {
    h.seedAreas();
    // One overdue task (badge) and nothing prayed yet today (5 left).
    h.tasks.s.put(task('late', 'Kirim laporan', dueDate: '2026-09-21'));
  }

  final h = TasksHarness();
  final privacy = InMemoryBalancePrivacyStore();
  late ProviderContainer container;
  late GoRouter router;

  List<Override> get overrides => [
    ...h.overrides,
    watchDashboardProvider.overrideWith(
      (ref) => Stream.value(sampleDashboard()),
    ),
    watchBudgetMonthProvider.overrideWith(
      (ref, _) => Stream.value(sampleBudgets()),
    ),
    watchSubscriptionsProvider.overrideWith(
      (ref) => Stream.value(sampleSubs()),
    ),
    balancePrivacyStoreProvider.overrideWithValue(privacy),
    sessionControllerProvider.overrideWith(
      () => FakeSession(const SignedIn(testUser)),
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    String location = '/home',
    bool dark = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    Key? boundaryKey,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: location,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const HomePage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/transactions',
                  builder: (_, _) => const TransactionsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/tasks', builder: (_, _) => const TasksPage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => const ProfilePage(),
                ),
              ],
            ),
          ],
        ),
      ],
      errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ProviderScope(
          overrides: overrides,
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: GhinaTheme.light(),
                darkTheme: GhinaTheme.dark(),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                routerConfig: router,
                builder: (context, child) => BalancePrivacyScope(
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await settle(tester, 10);
  }
}

final _drawer = find.byKey(const ValueKey('app-drawer'));
final _button = find.byKey(const ValueKey('app-drawer-button'));

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(_button.hitTestable().first);
  await settle(tester, 6);
  expect(_drawer, findsOneWidget);
}

Future<void> _search(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const ValueKey('app-drawer-search')), q);
  await settle(tester, 2);
}

Future<void> _scrollDrawerTo(WidgetTester tester, String path) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('drawer-$path')),
    120,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('app-drawer-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await settle(tester, 2);
}

List<String> _visibleItems() => [
  for (final i in kAppMenu)
    if (find.byKey(ValueKey('drawer-${i.path}')).evaluate().isNotEmpty) i.path,
];

Color? _rowColor(WidgetTester tester, String path) => tester
    .widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey('drawer-$path')),
            matching: find.byType(Material),
          )
          .first,
    )
    .color;

void main() {
  group('filterAppMenu', () {
    List<String> labels(String q) => [
      for (final i in filterAppMenu(q)) i.label,
    ];

    test('empty query → everything, grouped in the spec order', () {
      expect(filterAppMenu('  '), kAppMenu);
      expect(
        [
          for (final g in AppMenuGroup.values)
            [
              for (final i in kAppMenu)
                if (i.group == g) i.label,
            ],
        ],
        [
          [
            'Dompet',
            'Transaksi',
            'Budget',
            'Langganan',
            'Proyeksi',
            'Laporan',
            'Analitik',
            'Investasi',
            'Kategori',
          ],
          ['Sholat', 'Kebiasaan', 'Kesehatan', 'Makanan'],
          ['Tugas', 'Catatan', 'Konten'],
          [
            'Belajar',
            'Pencapaian',
            'Log Notifikasi',
            'Sinkronisasi',
            'Pengaturan',
          ],
        ],
      );
    });

    test('matches labels, synonyms and groups, case-insensitively', () {
      expect(labels('saham'), ['Investasi']);
      expect(labels('HABIT'), ['Kebiasaan']);
      for (final q in ['doa', 'salat', 'shalat']) {
        expect(labels(q), ['Sholat'], reason: q);
      }
      expect(labels('anggaran'), ['Budget']);
      expect(labels('lapor'), ['Laporan']);
      expect(labels('hidup'), ['Sholat', 'Kebiasaan', 'Kesehatan', 'Makanan']);
      expect(labels('xyzzy'), isEmpty);
      // Word prefixes first ("sa" → saldo, saham, salat) …
      expect(labels('sa'), ['Dompet', 'Investasi', 'Sholat']);
      // … any substring only when no word starts with it.
      expect(labels('biasa'), ['Kebiasaan']);
    });

    test('active: the screen itself and its sub-pages', () {
      final tasks = appMenuItem('/tasks');
      expect(isAppMenuItemActive(tasks, '/tasks'), isTrue);
      expect(isAppMenuItemActive(tasks, '/tasks/areas'), isTrue);
      expect(isAppMenuItemActive(tasks, '/transactions'), isFalse);
    });
  });

  group('drawer in the shell', () {
    for (final tab in _tabs) {
      testWidgets('☰ opens it on $tab', (tester) async {
        final s = _Shell();
        await s.pump(tester, location: tab);
        expect(_drawer, findsNothing);
        await _openDrawer(tester);
        expect(find.text('UANG'), findsOneWidget);
        expect(find.text('Ghina Putri'), findsWidgets);
      });
    }

    testWidgets('edge swipe from the left opens it', (tester) async {
      final s = _Shell();
      await s.pump(tester, location: '/tasks');
      await tester.dragFrom(const Offset(4, 420), const Offset(260, 0));
      await settle(tester, 6);
      expect(_drawer, findsOneWidget);
    });

    testWidgets('a swipe that starts inside the page does not', (tester) async {
      final s = _Shell();
      await s.pump(tester, location: '/tasks');
      await tester.dragFrom(const Offset(120, 420), const Offset(200, 0));
      await settle(tester, 6);
      expect(_drawer, findsNothing);
      await settle(tester, 20);
    });

    testWidgets('search filters the menu; no match shows a hint', (
      tester,
    ) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      expect(_visibleItems().length, greaterThan(8));

      await _search(tester, 'saham');
      expect(_visibleItems(), ['/investments']);
      expect(find.text('UANG'), findsOneWidget);
      expect(find.text('HIDUP'), findsNothing);

      await _search(tester, 'doa');
      expect(_visibleItems(), ['/prayers']);

      await _search(tester, 'habit');
      expect(_visibleItems(), ['/habits']);

      await _search(tester, 'qwerty');
      expect(_visibleItems(), isEmpty);
      expect(find.textContaining('nggak ketemu'), findsOneWidget);
    });

    testWidgets('a module is pushed and the drawer closes', (tester) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      await _search(tester, 'saham');
      await tester.tap(find.byKey(const ValueKey('drawer-/investments')));
      await settle(tester, 8);
      expect(find.text('route:/investments'), findsOneWidget);
      expect(_drawer, findsNothing);
      // Back returns to the tab (pushed on top of the shell).
      s.router.pop();
      await settle(tester, 6);
      expect(s.router.state.uri.path, '/home');
    });

    for (final path in [
      for (final i in kAppMenu)
        if (!i.isTab) i.path,
    ]) {
      testWidgets('item $path pushes $path', (tester) async {
        final s = _Shell();
        await s.pump(tester);
        await _openDrawer(tester);
        final item = find.byKey(ValueKey('drawer-$path'));
        await _scrollDrawerTo(tester, path);
        await tester.ensureVisible(item);
        await settle(tester, 3);
        await tester.tap(item);
        await settle(tester, 6);
        expect(find.text('route:$path'), findsOneWidget);
      });
    }

    testWidgets('a tab item switches the branch (go, not push)', (
      tester,
    ) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      await _search(tester, 'tugas');
      await tester.tap(find.byKey(const ValueKey('drawer-/tasks')));
      await settle(tester, 8);
      expect(_drawer, findsNothing);
      expect(s.router.state.uri.path, '/tasks');
      expect(s.router.canPop(), isFalse);
    });

    testWidgets('the header opens Profil', (tester) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      await tester.tap(find.byKey(const ValueKey('app-drawer-profile')));
      await settle(tester, 8);
      expect(s.router.state.uri.path, '/profile');
    });

    testWidgets('highlights the current tab', (tester) async {
      final s = _Shell();
      await s.pump(tester, location: '/tasks');
      await _openDrawer(tester);
      expect(_rowColor(tester, '/transactions'), Colors.transparent);
      await _scrollDrawerTo(tester, '/tasks');
      expect(_rowColor(tester, '/tasks'), isNot(Colors.transparent));
    });

    testWidgets('badges: overdue tasks and prayers left today', (tester) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      await _scrollDrawerTo(tester, '/tasks');
      final tasks = find.byKey(const ValueKey('drawer-badge-/tasks'));
      final prayers = find.byKey(const ValueKey('drawer-badge-/prayers'));
      expect(
        find.descendant(of: tasks, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prayers, matching: find.text('5')),
        findsOneWidget,
      );
    });

    testWidgets('footer toggles "Sembunyikan saldo"', (tester) async {
      final s = _Shell();
      await s.pump(tester);
      await _openDrawer(tester);
      expect(s.container.read(balancePrivacyProvider).hidden, isFalse);
      await tester.tap(find.byKey(const ValueKey('app-drawer-privacy')));
      await settle(tester, 3);
      expect(s.container.read(balancePrivacyProvider).hidden, isTrue);
      expect(s.privacy.value.hidden, isTrue);
      expect(find.textContaining('Ghina v'), findsOneWidget);
    });

    testWidgets('"Semua menu" tile on Beranda opens the drawer', (
      tester,
    ) async {
      final s = _Shell();
      await s.pump(tester);
      final all = find.byKey(const ValueKey('qa-all'));
      await tester.scrollUntilVisible(
        all,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester, 3);
      await tester.tap(all);
      await settle(tester, 6);
      expect(_drawer, findsOneWidget);
    });
  });

  group('screenshots', () {
    setUpAll(loadGhinaFonts);
    const key = ValueKey('shot');

    Future<void> shot(
      WidgetTester tester,
      String name, {
      String location = '/home',
      bool dark = false,
      Size size = const Size(390, 844),
      double textScale = 1,
      String? query,
      bool open = true,
    }) async {
      final s = _Shell();
      await s.pump(
        tester,
        location: location,
        dark: dark,
        size: size,
        textScale: textScale,
        boundaryKey: key,
      );
      if (open) await _openDrawer(tester);
      if (query != null) await _search(tester, query);
      await settle(tester, 4);
      final error = tester.takeException();
      await saveShot(tester, key, name);
      expect(error, isNull);
    }

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('drawer ($mode)', (t) => shot(t, 'drawer_$mode', dark: dark));
      testWidgets(
        'drawer on Tugas ($mode)',
        (t) => shot(t, 'drawer_tasks_$mode', location: '/tasks', dark: dark),
      );
      testWidgets(
        'drawer search ($mode)',
        (t) => shot(t, 'drawer_search_$mode', dark: dark, query: 'sa'),
      );
      for (final tab in _tabs) {
        final name = tab.substring(1);
        testWidgets(
          'tab $name with ☰ ($mode)',
          (t) => shot(
            t,
            'tab_${name}_$mode',
            location: tab,
            dark: dark,
            open: false,
          ),
        );
      }
    }
    testWidgets(
      'drawer small phone, text 1.3',
      (t) => shot(
        t,
        'drawer_small_text130',
        size: const Size(360, 640),
        textScale: 1.3,
      ),
    );
    testWidgets(
      'drawer search empty small phone',
      (t) => shot(
        t,
        'drawer_search_empty_small',
        size: const Size(360, 640),
        textScale: 1.3,
        query: 'qwerty',
      ),
    );
    testWidgets(
      'home small phone, text 1.3',
      (t) => shot(
        t,
        'home_small_text130',
        size: const Size(360, 640),
        textScale: 1.3,
        open: false,
      ),
    );
    testWidgets(
      'home grid (light)',
      (t) =>
          shot(t, 'home_grid_light', size: const Size(390, 2000), open: false),
    );
  });
}
