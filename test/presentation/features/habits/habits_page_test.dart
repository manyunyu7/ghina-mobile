import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('empty state invites to create the first habit', (t) async {
    final h = HabitsHarness();
    await pumpHabits(t, h, location: '/habits');
    expect(key('habits-empty'), findsOneWidget);
    expect(find.text('Yuk mulai satu kebiasaan'), findsOneWidget);
    await tapIn(t, find.text('BUAT KEBIASAAN'));
    expect(find.text('Kebiasaan baru'), findsWidgets);
  });

  testWidgets('build sections + one-tap check toggles today and toasts XP', (
    t,
  ) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(habit('run', 'Lari pagi', emoji: '🏃'))
      ..put(
        habit('smoke', 'Rokok', emoji: '🚭', kind: HabitKind.quit, order: 1),
      );
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Membangun'), findsOneWidget);
    expect(find.text('Berhenti'), findsOneWidget);

    await tapIn(t, key('habit-check-run'));
    expect(h.todayLog('run', HabitLogType.done), isNotNull);
    expect(find.textContaining('+5 XP'), findsOneWidget);
    await settle(t, 30);

    await tapIn(t, key('habit-check-run'));
    expect(h.todayLog('run', HabitLogType.done), isNull);
    await settle(t, 30);
  });

  testWidgets('counter −/+1 sets the day value', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(
      habit(
        'water',
        'Minum air',
        emoji: '💧',
        target: HabitTarget.count(8, unit: 'gelas'),
      ),
    );
    await pumpHabits(t, h, location: '/habits');
    expect(find.textContaining('0/8 gelas'), findsOneWidget);
    await tapIn(t, key('habit-inc-water'));
    await tapIn(t, key('habit-inc-water'));
    expect(h.todayLog('water', HabitLogType.done)!.value, 2);
    expect(find.textContaining('2/8 gelas'), findsOneWidget);
    await tapIn(t, key('habit-dec-water'));
    expect(h.todayLog('water', HabitLogType.done)!.value, 1);
    await settle(t, 30);
  });

  testWidgets('timer logs the stopwatch minutes; quick +15 adds', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(
      habit('read', 'Baca buku', emoji: '📖', target: HabitTarget.duration(30)),
    );
    await pumpHabits(t, h, location: '/habits');
    await tapIn(t, key('habit-timer-read'), 2);
    expect(find.text('00:00'), findsOneWidget);
    h.clock.advance(const Duration(minutes: 12, seconds: 20));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('12:20'), findsOneWidget);
    await tapIn(t, key('habit-timer-read'));
    expect(h.todayLog('read', HabitLogType.done)!.value, 12);

    await tapIn(t, key('habit-add-15-read'));
    expect(h.todayLog('read', HabitLogType.done)!.value, 27);
    await settle(t, 30);
  });

  testWidgets('a stopwatch under a minute is not logged', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(habit('read', 'Baca', target: HabitTarget.duration(30)));
    await pumpHabits(t, h, location: '/habits');
    await tapIn(t, key('habit-timer-read'), 2);
    h.clock.advance(const Duration(seconds: 20));
    await tapIn(t, key('habit-timer-read'), 3);
    expect(h.todayLog('read', HabitLogType.done), isNull);
    expect(find.textContaining('Belum semenit'), findsOneWidget);
    await settle(t, 30);
  });

  testWidgets('"Libur hari ini" logs a skip; the 2-in-7 limit is explained', (
    t,
  ) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(habit('a', 'Olahraga'))
      ..put(habit('b', 'Jurnal', order: 1));
    h.logs.s
      ..put(log('b', daysAgo(2), HabitLogType.skip))
      ..put(log('b', daysAgo(4), HabitLogType.skip));
    await pumpHabits(t, h, location: '/habits');

    expect(find.text('Sisa jatah libur: 2'), findsOneWidget);
    expect(find.text('Jatah libur minggu ini habis'), findsOneWidget);

    await tapIn(t, key('habit-skip-b'));
    expect(h.todayLog('b', HabitLogType.skip), isNull);
    expect(
      find.textContaining('Maksimal 2 hari libur dalam 7 hari'),
      findsOneWidget,
    );
    await settle(t, 30);

    await tapIn(t, key('habit-skip-a'));
    expect(h.todayLog('a', HabitLogType.skip), isNotNull);
    expect(find.text('Batal libur'), findsOneWidget);
    await settle(t, 30);
  });

  testWidgets('quit card: clean days, "Hari ini bersih" check-in', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(
      habit('smoke', 'Rokok', kind: HabitKind.quit, startDate: daysAgo(4)),
    );
    await pumpHabits(t, h, location: '/habits');
    expect(find.text('Hari bersih ke-5'), findsOneWidget);
    expect(find.textContaining('2 hari lagi menuju 7 hari'), findsOneWidget);
    await tapIn(t, key('habit-clean-check-smoke'));
    expect(h.todayLog('smoke', HabitLogType.done), isNotNull);
    expect(find.textContaining('+3 XP'), findsOneWidget);
    await settle(t, 30);
  });

  testWidgets('"Aku kalah" → relapse sheet with triggers, kind message', (
    t,
  ) async {
    final h = HabitsHarness();
    h.habits.s.put(
      habit('smoke', 'Rokok', kind: HabitKind.quit, startDate: daysAgo(12)),
    );
    await pumpHabits(t, h, location: '/habits');
    await tapIn(t, key('habit-relapse-smoke'));
    // Today counted as clean so far: the run it ends is 12 days.
    expect(
      find.textContaining('Kamu sempat bersih 12 hari — itu nyata'),
      findsOneWidget,
    );
    await tapIn(t, key('trigger-stres'), 2);
    await tapIn(t, key('trigger-malam'), 2);
    await tapIn(t, key('relapse-save'));
    final r = h.todayLog('smoke', HabitLogType.relapse)!;
    expect(r.triggers, containsAll(['stres', 'malam']));
    expect(
      find.text('Kamu sempat bersih 12 hari — itu nyata.'),
      findsOneWidget,
    );
    await tapIn(t, key('relapse-ok'));
    expect(find.text('Hari bersih barumu mulai besok 🌱'), findsOneWidget);
    await settle(t, 30);
  });

  testWidgets('quit milestone is celebrated once', (t) async {
    final h = HabitsHarness();
    // Clean since 6 days ago → today is day 7.
    h.habits.s.put(
      habit('smoke', 'Rokok', kind: HabitKind.quit, startDate: daysAgo(6)),
    );
    await pumpHabits(t, h, location: '/habits');
    await settle(t, 10);
    expect(find.text('7 hari bersih! 🌳'), findsOneWidget);
    await tapIn(t, find.text('LANJUT'));
    expect(find.text('7 hari bersih! 🌳'), findsNothing);
    final local = h.gameStore;
    expect(local, isNotNull);
  });

  testWidgets('archive section lists archived habits and restores them', (
    t,
  ) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(habit('a', 'Olahraga'))
      ..put(habit('old', 'Diet gula', archived: true, order: 1));
    await pumpHabits(t, h, location: '/habits');
    await tapIn(t, key('habit-archive-toggle'));
    expect(find.text('Diet gula'), findsOneWidget);
    await tapIn(t, key('habit-unarchive-old'));
    expect(h.habits.s.items['old']!.archived, isFalse);
    await settle(t, 30);
  });
}
