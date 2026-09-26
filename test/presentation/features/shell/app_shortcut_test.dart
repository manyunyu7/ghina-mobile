import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/platform.dart' show FakeAppShortcuts;
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart'
    show HabitAuthOutcome;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/app_shortcuts.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/habits/pages/habit_routes.dart';
import 'package:ghina/presentation/features/shell/app_shortcut_listener.dart';
import 'package:ghina/presentation/features/shell/notification_navigation.dart';
import 'package:ghina/presentation/state/platform/platform_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../habits/_habits_harness.dart';
import 'test_utils.dart' show FakeSession;

const _notReady = {'/splash', '/login', '/register', '/onboarding'};

/// The app's wiring in miniature: auth redirect (signed out → /login,
/// sign-in → /home), the [NotificationRouteGate] pending-route mechanism and
/// the [AppShortcutListener] fed by a fake shortcut stream.
class _App {
  _App({bool signedIn = false})
    : session = FakeSession(
        signedIn ? const SignedIn(habitsUser) : const SignedOut(),
      );

  final h = HabitsHarness();
  final shortcuts = FakeAppShortcuts();
  final FakeSession session;
  late final ProviderContainer container;
  late final GoRouter router;

  /// The top-most location (pushed routes included).
  String get location {
    final last = router.routerDelegate.currentConfiguration.matches.last;
    return last is ImperativeRouteMatch
        ? last.matches.uri.toString()
        : router.routerDelegate.currentConfiguration.uri.toString();
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...h.overrides,
        appShortcutsProvider.overrideWithValue(shortcuts),
        sessionControllerProvider.overrideWith(() => session),
      ],
    );
    addTearDown(container.dispose);
    final refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    container.listen(sessionControllerProvider, (_, _) => refresh.value++);
    router = GoRouter(
      initialLocation: '/home',
      refreshListenable: refresh,
      redirect: (_, s) {
        final signedIn = container.read(sessionControllerProvider) is SignedIn;
        final loc = s.matchedLocation;
        if (!signedIn) return loc == '/login' ? null : '/login';
        return loc == '/login' ? '/home' : null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('LOGIN')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        ...habitRoutes,
      ],
      errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
          builder: (context, child) => NotificationRouteGate(
            router: router,
            canOpen: () =>
                container.read(sessionControllerProvider) is SignedIn &&
                !_notReady.contains(
                  router.routerDelegate.currentConfiguration.uri.path,
                ),
            child: AppShortcutListener(child: child!),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> launch(WidgetTester tester, AppShortcut s) async {
    shortcuts.launch(s);
    await settle(tester);
  }
}

Habit _quit(String id, String name, {bool archived = false}) =>
    habit(id, name, kind: HabitKind.quit, archived: archived);

void main() {
  group('urgeRouteFor', () {
    test('no active quit habit → new habit', () {
      expect(urgeRouteFor(const []), '/habits/new');
      expect(
        urgeRouteFor([
          habit('b', 'Olahraga'),
          _quit('q', 'Rokok', archived: true),
        ]),
        '/habits/new',
      );
    });

    test('exactly one → its urge screen', () {
      expect(
        urgeRouteFor([habit('b', 'Olahraga'), _quit('q1', 'Rokok')]),
        '/habits/q1/urge',
      );
    });

    test('several → the board with the picker', () {
      expect(
        urgeRouteFor([_quit('q1', 'Rokok'), _quit('q2', 'Begadang')]),
        '/habits?pick=urge',
      );
    });

    test('fixed routes of the other shortcuts; labels stay generic', () {
      expect(shortcutRoute(AppShortcut.expense), '/transactions/new');
      expect(shortcutRoute(AppShortcut.note), '/notes/new');
      expect(shortcutRoute(AppShortcut.task), '/tasks/new');
      expect(shortcutRoute(AppShortcut.urge), isNull);
      expect(AppShortcut.values.map((s) => s.label), [
        'Catat pengeluaran',
        'Catatan baru',
        'Tugas baru',
        'Lagi pengen…',
      ]);
      for (final s in AppShortcut.values) {
        expect(AppShortcut.fromType(s.type), s);
      }
      expect(AppShortcut.fromType('nope'), isNull);
    });
  });

  group('launcher shortcuts', () {
    testWidgets('publishes the four shortcuts at startup', (tester) async {
      final app = _App(signedIn: true);
      await app.pump(tester);
      expect(app.shortcuts.installed, AppShortcut.values);
    });

    testWidgets('signed out: waits on the login screen, opens after login', (
      tester,
    ) async {
      final app = _App();
      await app.pump(tester);
      expect(find.text('LOGIN'), findsOneWidget);

      await app.launch(tester, AppShortcut.expense);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(app.location, '/login');

      await app.session.signIn('ghina@contoh.id', 'rahasia');
      await settle(tester);
      expect(find.text('route:/transactions/new'), findsOneWidget);
      // Pushed on top of Beranda: back goes home.
      app.router.pop();
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('signed in (warm start): opens right away', (tester) async {
      final app = _App(signedIn: true);
      await app.pump(tester);
      await app.launch(tester, AppShortcut.note);
      expect(find.text('route:/notes/new'), findsOneWidget);
      await app.launch(tester, AppShortcut.task);
      expect(find.text('route:/tasks/new'), findsOneWidget);
    });

    testWidgets('only the latest pending shortcut is opened', (tester) async {
      final app = _App();
      await app.pump(tester);
      await app.launch(tester, AppShortcut.expense);
      await app.launch(tester, AppShortcut.task);
      await app.session.signIn('ghina@contoh.id', 'rahasia');
      await settle(tester);
      expect(find.text('route:/tasks/new'), findsOneWidget);
      app.router.pop();
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('"Lagi pengen…" with one quit habit → its urge screen', (
      tester,
    ) async {
      final app = _App();
      app.h.habits.s.put(habit('b', 'Olahraga'));
      app.h.habits.s.put(_quit('q1', 'Rokok'));
      await app.pump(tester);
      await app.launch(tester, AppShortcut.urge);
      expect(app.location, '/login');
      await app.session.signIn('ghina@contoh.id', 'rahasia');
      await settle(tester);
      expect(app.location, '/habits/q1/urge');
    });

    testWidgets('"Lagi pengen…" with none → new habit', (tester) async {
      final app = _App(signedIn: true);
      app.h.habits.s.put(habit('b', 'Olahraga'));
      await app.pump(tester);
      await app.launch(tester, AppShortcut.urge);
      expect(app.location, '/habits/new');
    });

    testWidgets('"Lagi pengen…" with several → pick one, then its urge '
        'screen', (tester) async {
      final app = _App(signedIn: true);
      app.h.habits.s.put(_quit('q1', 'Rokok'));
      app.h.habits.s.put(_quit('q2', 'Begadang', archived: false));
      await app.pump(tester);
      await app.launch(tester, AppShortcut.urge);
      expect(app.location, '/habits?pick=urge');
      expect(find.text('Lagi pengen apa?'), findsOneWidget);
      expect(find.byKey(const ValueKey('urge-pick-q1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('urge-pick-q2')));
      await settle(tester);
      expect(app.location, '/habits/q2/urge');
    });
  });

  group('habits board ?pick=urge', () {
    testWidgets('behind "Kunci Kebiasaan": asks only after unlocking', (
      tester,
    ) async {
      final h = HabitsHarness(
        lockEnabled: true,
        auth: FakeAuthenticator(outcome: HabitAuthOutcome.error),
      );
      h.habits.s.put(_quit('q1', 'Rokok'));
      h.habits.s.put(_quit('q2', 'Begadang'));
      await pumpHabits(tester, h, location: '/habits?pick=urge');
      expect(find.text('Lagi pengen apa?'), findsNothing);
      expect(find.text('Rokok'), findsNothing);

      h.auth.outcome = HabitAuthOutcome.success;
      await tester.tap(find.text('BUKA KUNCI'));
      await settle(tester);
      expect(find.text('Lagi pengen apa?'), findsOneWidget);
    });

    testWidgets('the plain board never shows the picker', (tester) async {
      final h = HabitsHarness();
      h.habits.s.put(_quit('q1', 'Rokok'));
      h.habits.s.put(_quit('q2', 'Begadang'));
      await pumpHabits(tester, h, location: '/habits');
      expect(find.text('Lagi pengen apa?'), findsNothing);
    });
  });
}
