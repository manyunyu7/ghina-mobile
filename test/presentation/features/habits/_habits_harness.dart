/// Shared setup for the Kebiasaan screen tests: real use cases over in-memory
/// repositories, a controllable clock, the game engine (XP toasts,
/// achievements) and a fake device authenticator for "Kunci Kebiasaan".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart';
import 'package:ghina/presentation/features/habits/pages/habit_routes.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../di/habits_investments_test_overrides.dart';
import '../../../domain/fakes.dart';
import '../profile/_harness.dart'
    show FakeFoodRepository, FakeHealthRepository, FakePrayerRepository;
import '../tasks/_tasks_harness.dart'
    show FakeScheduler, FakeSettingsStore, FakeSyncService;

/// Thursday 24 September 2026, 10:00.
final habitsNow = DateTime(2026, 9, 24, 10);
String get todayKey => dateKey(habitsNow);
String daysAgo(int n) => dateKey(addDays(habitsNow, -n));

const habitsUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

Habit habit(
  String id,
  String name, {
  String? emoji,
  HabitKind kind = HabitKind.build,
  HabitSchedule schedule = HabitSchedule.daily,
  HabitTarget target = HabitTarget.check,
  bool isPrivate = false,
  String? why,
  String? startDate,
  int order = 0,
  bool archived = false,
  String color = '#58CC02',
}) => Habit(
  id: id,
  name: name,
  emoji: emoji,
  color: color,
  kind: kind,
  schedule: schedule,
  target: target,
  isPrivate: isPrivate,
  why: why,
  startDate: startDate ?? daysAgo(30),
  sortOrder: order,
  archived: archived,
  createdAt: habitsNow.subtract(const Duration(days: 30)),
  updatedAt: habitsNow.subtract(const Duration(days: 30)),
);

var _logSeq = 0;

HabitLog log(
  String habitId,
  String date,
  HabitLogType type, {
  double? value,
  String? note,
  List<String> triggers = const [],
  DateTime? at,
}) => HabitLog(
  id: 'log-${_logSeq++}',
  habitId: habitId,
  date: date,
  type: type,
  value: value ?? (type == HabitLogType.skip ? null : 1),
  note: note,
  triggers: triggers,
  at: at,
  createdAt: parseDateKey(date).add(const Duration(hours: 9)),
  updatedAt: parseDateKey(date).add(const Duration(hours: 9)),
);

/// Device authentication stub.
class FakeAuthenticator implements HabitAuthenticator {
  FakeAuthenticator({
    this.available = true,
    this.outcome = HabitAuthOutcome.success,
  });

  bool available;
  HabitAuthOutcome outcome;
  int prompts = 0;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<HabitAuthOutcome> authenticate(String reason) async {
    prompts++;
    return outcome;
  }
}

/// Habit achievements, marked seen by default so badge sheets don't cover
/// the screen under test.
const habitAchievementIds = {
  'first_habit',
  'habit_build_streak_7',
  'habit_clean_30',
  'habit_urges_100',
  'habit_trio_7',
};

class HabitsHarness {
  HabitsHarness({
    bool lockEnabled = false,
    FakeAuthenticator? auth,
    Set<String> seenAchievements = habitAchievementIds,
  }) : lockStore = InMemoryHabitLockStore(lockEnabled),
       auth = auth ?? FakeAuthenticator(),
       gameStore = InMemoryGameStore({
         GameLocalState.storageKey: GameLocalState(
           onboardingDone: true,
           lastSeenLevel: 1,
           seenAchievements: seenAchievements,
         ).encode(),
       });

  final clock = FixedClock(habitsNow);
  final InMemoryGameStore gameStore;
  final habits = FakeHabitRepository();
  final logs = FakeHabitLogRepository();
  final InMemoryHabitLockStore lockStore;
  final FakeAuthenticator auth;
  final scheduler = FakeScheduler();

  List<HabitLog> logsOf(String habitId, [HabitLogType? type]) => [
    for (final l in logs.s.items.values)
      if (l.habitId == habitId && (type == null || l.type == type)) l,
  ];

  HabitLog? todayLog(String habitId, HabitLogType type) {
    for (final l in logsOf(habitId, type)) {
      if (l.date == dateKey(clock.now())) return l;
    }
    return null;
  }

  List<Override> get overrides => [
    ...habitsInvestmentsFakeOverrides(habits: habits, habitLogs: logs),
    ...buildGameOverrides(store: gameStore),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    clockProvider.overrideWithValue(clock),
    tickSourceProvider.overrideWithValue(() => Stream.value(clock.now())),
    taskRepositoryProvider.overrideWithValue(FakeTaskRepository()),
    taskAreaRepositoryProvider.overrideWithValue(FakeTaskAreaRepository()),
    contentItemRepositoryProvider.overrideWithValue(
      FakeContentItemRepository(),
    ),
    contentPostRepositoryProvider.overrideWithValue(
      FakeContentPostRepository(),
    ),
    socialAccountRepositoryProvider.overrideWithValue(
      FakeSocialAccountRepository(),
    ),
    walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
    categoryRepositoryProvider.overrideWithValue(FakeCategoryRepository()),
    transactionRepositoryProvider.overrideWithValue(
      FakeTransactionRepository(),
    ),
    budgetRepositoryProvider.overrideWithValue(FakeBudgetRepository()),
    prayerRepositoryProvider.overrideWithValue(FakePrayerRepository()),
    healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
    foodRepositoryProvider.overrideWithValue(FakeFoodRepository()),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    syncServiceProvider.overrideWithValue(FakeSyncService()),
    currentUserProvider.overrideWithValue(habitsUser),
    notificationSettingsStoreProvider.overrideWithValue(FakeSettingsStore()),
    reminderSchedulerProvider.overrideWithValue(scheduler),
    remindersSourceProvider.overrideWith((ref) => Stream.value(const [])),
    habitLockStoreProvider.overrideWithValue(lockStore),
    habitAuthenticatorProvider.overrideWithValue(auth),
  ];
}

/// Pumps [location] inside a router with the habit routes (+ [routes]);
/// other routes render `route:<uri>`. `/` is a "HOME" stub so pushes can pop.
Future<GoRouter> pumpHabits(
  WidgetTester tester,
  HabitsHarness h, {
  required String location,
  List<RouteBase> routes = const [],
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
  Widget? home,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            Scaffold(body: home ?? const Center(child: Text('HOME'))),
      ),
      ...habitRoutes,
      ...routes,
    ],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: h.overrides,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (location != '/') router.push(location);
  await settle(tester);
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps [finder] after scrolling it into view.
Future<void> tapIn(
  WidgetTester tester,
  Finder finder, [
  int frames = 12,
]) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // A focused text field may still be scrolling itself into view.
  await tester.ensureVisible(finder);
  await settle(tester, 6);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await settle(tester, frames);
}
