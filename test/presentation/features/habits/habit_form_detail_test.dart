import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  group('create / edit', () {
    testWidgets('creates a counted build habit and opens its detail', (
      t,
    ) async {
      final h = HabitsHarness();
      await pumpHabits(t, h, location: '/habits/new');
      await t.enterText(key('habit-name'), 'Minum air');
      await tapIn(t, key('emoji-💧'), 2);
      await tapIn(t, find.text('Jumlah'), 2);
      await t.enterText(
        find.descendant(
          of: key('habit-goal'),
          matching: find.byType(EditableText),
        ),
        '8',
      );
      await tapIn(t, key('habit-private'), 2);
      await tapIn(t, key('habit-save'), 30);
      final created = h.habits.s.items.values.single;
      expect(created.name, 'Minum air');
      expect(created.emoji, '💧');
      expect(created.target, HabitTarget.count(8, unit: 'gelas'));
      expect(created.isPrivate, isTrue);
      expect(created.kind, HabitKind.build);
      // Opened the detail page.
      expect(key('habit-streak-ring'), findsOneWidget);
      await settle(t, 30);
    });

    testWidgets('quit habits: "sudah bersih sejak" and forced daily/check', (
      t,
    ) async {
      final h = HabitsHarness();
      await pumpHabits(t, h, location: '/habits/new');
      await tapIn(t, find.text('Berhenti'), 2);
      expect(find.text('Jadwal'), findsNothing);
      expect(find.text('Target harian'), findsNothing);
      await t.enterText(key('habit-name'), 'Rokok');
      await t.scrollUntilVisible(
        find.text('Sudah bersih sejak…'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sudah bersih sejak…'), findsOneWidget);
      await t.enterText(
        find.descendant(
          of: key('habit-why'),
          matching: find.byType(EditableText),
        ),
        'Demi paru-paru',
      );
      await tapIn(t, key('habit-save'), 30);
      final created = h.habits.s.items.values.single;
      expect(created.kind, HabitKind.quit);
      expect(created.emoji, '🚭');
      expect(created.why, 'Demi paru-paru');
      expect(created.schedule, HabitSchedule.daily);
      await settle(t, 30);
    });

    testWidgets('empty name is refused with a friendly error', (t) async {
      final h = HabitsHarness();
      await pumpHabits(t, h, location: '/habits/new');
      await tapIn(t, key('habit-save'));
      expect(find.text('Kasih nama kebiasaannya dulu, ya'), findsOneWidget);
      expect(h.habits.s.items, isEmpty);
    });

    testWidgets('edit keeps the id and saves the new schedule', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(habit('run', 'Lari', emoji: '🏃'));
      await pumpHabits(t, h, location: '/habits/run/edit');
      expect(find.text('Ubah kebiasaan'), findsOneWidget);
      await tapIn(t, find.text('X kali seminggu'), 2);
      await tapIn(t, key('habit-save'));
      expect(h.habits.s.items['run']!.schedule, HabitSchedule.perWeek(3));
      await settle(t, 30);
    });
  });

  group('detail', () {
    HabitsHarness seeded() {
      final h = HabitsHarness();
      h.habits.s.put(
        habit('smoke', 'Rokok', kind: HabitKind.quit, startDate: daysAgo(20)),
      );
      h.logs.s
        ..put(
          log(
            'smoke',
            daysAgo(8),
            HabitLogType.relapse,
            triggers: ['stres'],
            note: 'Deadline berat',
            at: DateTime(2026, 9, 16, 22),
          ),
        )
        ..put(log('smoke', daysAgo(2), HabitLogType.urge, value: 3));
      return h;
    }

    testWidgets('streak ring, milestones, insights and journal', (t) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/smoke');
      expect(key('habit-streak-ring'), findsOneWidget);
      // Relapse 8 days ago → clean for 8 days incl. today.
      expect(find.text('8'), findsWidgets);
      expect(key('milestone-7'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Pemicu teratas'), 300);
      expect(find.text('stres · 1×'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Deadline berat'), 300);
      expect(find.text('Deadline berat'), findsOneWidget);
    });

    testWidgets('journal edit and log delete', (t) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/smoke');
      await t.scrollUntilVisible(find.text('Deadline berat'), 300);
      await tapIn(t, find.text('Deadline berat'), 6);
      await t.enterText(
        find.descendant(
          of: key('journal-text'),
          matching: find.byType(EditableText),
        ),
        'Deadline berat, besok lebih siap',
      );
      await tapIn(t, key('journal-save'));
      final relapse = h.logsOf('smoke', HabitLogType.relapse).single;
      expect(relapse.note, 'Deadline berat, besok lebih siap');
      await settle(t, 30);

      final urge = h.logsOf('smoke', HabitLogType.urge).single;
      await t.scrollUntilVisible(key('log-delete-${urge.id}'), 300);
      await tapIn(t, key('log-delete-${urge.id}'), 6);
      await tapIn(t, find.text('HAPUS'));
      expect(h.logsOf('smoke', HabitLogType.urge), isEmpty);
    });

    testWidgets('year heatmap toggle renders', (t) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/smoke');
      await t.scrollUntilVisible(find.text('Tahun'), 300);
      await tapIn(t, find.text('Tahun'), 6);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('first habit check-in unlocks "Teman Streak"', (t) async {
    final h = HabitsHarness(seenAchievements: const {});
    h.habits.s.put(habit('run', 'Lari', emoji: '🏃'));
    await pumpHabits(t, h, location: '/habits');
    await tapIn(t, key('habit-check-run'), 30);
    expect(find.text('Teman Streak'), findsOneWidget);
    await settle(t, 30);
  });
}
