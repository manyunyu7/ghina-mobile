import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock_gate.dart';

import '_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('lock off: the Habits area opens without a prompt', (t) async {
    final h = HabitsHarness();
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Kebiasaan terkunci 🔒'), findsNothing);
    expect(h.auth.prompts, 0);
  });

  testWidgets('lock on: prompts right away and opens on success', (t) async {
    final h = HabitsHarness(lockEnabled: true);
    h.habits.s.put(habit('a', 'Olahraga'));
    await pumpHabits(t, h, location: '/habits');
    expect(h.auth.prompts, 1);
    expect(find.text('Olahraga'), findsOneWidget);
  });

  testWidgets('cancelled prompt keeps it locked; "Buka kunci" retries', (
    t,
  ) async {
    final auth = FakeAuthenticator(outcome: HabitAuthOutcome.cancelled);
    final h = HabitsHarness(lockEnabled: true, auth: auth);
    h.habits.s.put(habit('a', 'Rahasia banget', isPrivate: true));
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Kebiasaan terkunci 🔒'), findsOneWidget);
    expect(find.text('Rahasia banget'), findsNothing);

    auth.outcome = HabitAuthOutcome.success;
    await tapIn(t, key('habit-unlock'));
    expect(auth.prompts, 2);
    expect(find.text('Rahasia banget'), findsOneWidget);
  });

  testWidgets('session unlock survives short trips, re-locks after 5 min', (
    t,
  ) async {
    final h = HabitsHarness(lockEnabled: true);
    h.habits.s.put(habit('a', 'Olahraga'));
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Olahraga'), findsOneWidget);

    // 2 minutes in the background: still open.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    h.clock.advance(const Duration(minutes: 2));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t, 3);
    expect(find.text('Olahraga'), findsOneWidget);
    expect(h.auth.prompts, 1);

    // 6 minutes: locked again (and prompts again).
    h.auth.outcome = HabitAuthOutcome.cancelled;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    h.clock.advance(const Duration(minutes: 6));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t, 3);
    expect(find.text('Kebiasaan terkunci 🔒'), findsOneWidget);
    expect(h.auth.prompts, 2);
  });

  testWidgets('a re-lock keeps the page mounted: the emergency screen does '
      'not log a second urge after unlocking', (t) async {
    final h = HabitsHarness(lockEnabled: true);
    h.habits.s.put(habit('q', 'Rokok', kind: HabitKind.quit));
    await pumpHabits(t, h, location: '/habits/q/urge');
    expect(h.todayLog('q', HabitLogType.urge)!.value, 1);

    h.auth.outcome = HabitAuthOutcome.cancelled;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    h.clock.advance(const Duration(minutes: 6));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t, 3);
    expect(find.text('Kebiasaan terkunci 🔒'), findsOneWidget);
    expect(
      find.text('Tarik napas'),
      findsNothing,
      reason: 'hidden while locked',
    );

    h.auth.outcome = HabitAuthOutcome.success;
    await tapIn(t, key('habit-unlock'));
    expect(find.text('Kebiasaan terkunci 🔒'), findsNothing);
    expect(h.todayLog('q', HabitLogType.urge)!.value, 1);
    await settle(t, 70);
  });

  testWidgets('device without any screen lock: opens with a hint', (t) async {
    final auth = FakeAuthenticator(available: false);
    final h = HabitsHarness(lockEnabled: true, auth: auth);
    h.habits.s.put(habit('a', 'Olahraga'));
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Olahraga'), findsOneWidget);
    expect(find.textContaining('belum pakai kunci layar'), findsOneWidget);
    expect(auth.prompts, 0);
    await settle(t, 40);
  });

  group('settings switch', () {
    Widget tile() => const Scaffold(body: HabitLockSettingTile());

    testWidgets('turning on needs one successful prompt', (t) async {
      final h = HabitsHarness();
      await pumpHabits(t, h, location: '/', home: tile());
      await tapIn(t, key('settings-habit-lock'));
      expect(h.auth.prompts, 1);
      expect(h.lockStore.enabled, isTrue);
      expect(find.textContaining('sekarang terkunci'), findsOneWidget);
      await settle(t, 30);
    });

    testWidgets('failed prompt leaves it off', (t) async {
      final h = HabitsHarness(
        auth: FakeAuthenticator(outcome: HabitAuthOutcome.cancelled),
      );
      await pumpHabits(t, h, location: '/', home: tile());
      await tapIn(t, key('settings-habit-lock'));
      expect(h.lockStore.enabled, isFalse);
      await settle(t, 40);
    });

    testWidgets('no device lock: explains instead of enabling', (t) async {
      final h = HabitsHarness(auth: FakeAuthenticator(available: false));
      await pumpHabits(t, h, location: '/', home: tile());
      await tapIn(t, key('settings-habit-lock'));
      expect(find.text('Pasang kunci layar dulu, ya'), findsOneWidget);
      expect(h.lockStore.enabled, isFalse);
      expect(h.auth.prompts, 0);
    });

    testWidgets('turning off asks the device too', (t) async {
      final h = HabitsHarness(lockEnabled: true);
      await pumpHabits(t, h, location: '/', home: tile());
      await tapIn(t, key('settings-habit-lock'));
      expect(h.auth.prompts, 1);
      expect(h.lockStore.enabled, isFalse);
      await settle(t, 30);
    });
  });
}
