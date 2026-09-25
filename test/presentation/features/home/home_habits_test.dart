import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/home/widgets/home_habits.dart';

import '../habits/_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

Widget _home() => const SingleChildScrollView(
  padding: EdgeInsets.all(20),
  child: HomeHabitsCard(),
);

void main() {
  testWidgets('hidden when there are no habits', (t) async {
    final h = HabitsHarness();
    await pumpHabits(t, h, location: '/', home: _home());
    expect(key('home-habits'), findsNothing);
  });

  testWidgets('private habits are masked: publicTitle, no emoji', (t) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(
        habit(
          'p',
          'Berhenti judol',
          emoji: '🎰',
          kind: HabitKind.quit,
          isPrivate: true,
          startDate: daysAgo(3),
        ),
      )
      ..put(habit('w', 'Minum air', emoji: '💧', order: 1));
    await pumpHabits(t, h, location: '/', home: _home());
    expect(find.text('Kebiasaan hari ini'), findsOneWidget);
    expect(find.text('Kebiasaan pribadi'), findsOneWidget);
    expect(find.textContaining('judol'), findsNothing);
    expect(find.text('🎰'), findsNothing);
    expect(find.text('Hari bersih ke-4'), findsOneWidget);
    // Non-private habits keep their name and emoji.
    expect(find.text('Minum air'), findsOneWidget);
    expect(find.text('💧'), findsOneWidget);
  });

  testWidgets('a private count habit hides its unit on home', (t) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(
        habit(
          'p',
          'Kurangi rokok',
          isPrivate: true,
          target: HabitTarget.count(5, unit: 'batang'),
        ),
      )
      ..put(
        habit(
          'w',
          'Minum air',
          target: HabitTarget.count(8, unit: 'gelas'),
          order: 1,
        ),
      );
    await pumpHabits(t, h, location: '/', home: _home());
    expect(find.text('0/5'), findsOneWidget);
    expect(find.textContaining('batang'), findsNothing);
    expect(find.text('0/8 gelas'), findsOneWidget);
  });

  testWidgets('one-tap check and clean check-in from home', (t) async {
    final h = HabitsHarness();
    h.habits.s
      ..put(habit('run', 'Lari', emoji: '🏃'))
      ..put(habit('q', 'Rokok', kind: HabitKind.quit, order: 1));
    await pumpHabits(t, h, location: '/', home: _home());
    await tapIn(t, key('home-habit-check-run'));
    expect(h.todayLog('run', HabitLogType.done), isNotNull);
    await settle(t, 30);
    await tapIn(t, key('home-habit-clean-q'));
    expect(h.todayLog('q', HabitLogType.done), isNotNull);
    await settle(t, 30);
  });

  testWidgets('private milestone celebration hides the name', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(
      habit(
        'p',
        'Berhenti judol',
        kind: HabitKind.quit,
        isPrivate: true,
        startDate: daysAgo(6),
      ),
    );
    await pumpHabits(t, h, location: '/', home: _home());
    await tapIn(t, key('home-habit-clean-p'), 30);
    expect(find.text('7 hari bersih! 🌳'), findsOneWidget);
    expect(find.textContaining('judol'), findsNothing);
    expect(find.textContaining('kebiasaan pribadimu'), findsOneWidget);
  });

  testWidgets('tapping a row opens the habit', (t) async {
    final h = HabitsHarness();
    h.habits.s.put(habit('run', 'Lari'));
    await pumpHabits(t, h, location: '/', home: _home());
    await tapIn(t, key('home-habit-run'));
    expect(key('habit-streak-ring'), findsOneWidget);
  });
}
