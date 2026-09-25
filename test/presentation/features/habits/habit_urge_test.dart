import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart' show urgeEncouragements;
import 'package:ghina/presentation/features/habits/habit_format.dart';
import 'package:ghina/presentation/features/habits/widgets/box_breathing.dart';

import '_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

HabitsHarness _seeded() {
  final h = HabitsHarness();
  h.habits.s.put(
    habit(
      'smoke',
      'Rokok',
      emoji: '🚭',
      kind: HabitKind.quit,
      startDate: daysAgo(9),
      why: 'Biar napas lega main bola sama anak.',
    ),
  );
  return h;
}

Future<void> _breathe(WidgetTester t) async {
  for (var i = 0; i < 62; i++) {
    await t.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('opening the emergency screen logs the urge right away', (
    t,
  ) async {
    final h = _seeded();
    await pumpHabits(t, h, location: '/habits/smoke/urge');
    expect(h.todayLog('smoke', HabitLogType.urge)!.value, 1);
    expect(find.text('Tarik napas'), findsOneWidget);
    await t.scrollUntilVisible(key('urge-why'), 200);
    expect(find.text('Biar napas lega main bola sama anak.'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Hari bersih ke-10'), 200);
    expect(find.text('Hari bersih ke-10'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Jalan sebentar'), 200);
    expect(find.text('Jalan sebentar'), findsOneWidget);
    final line = t.widget<Text>(key('urge-encouragement')).data;
    expect(urgeEncouragements, contains(line));
    await _breathe(t);
    expect(find.text('Berhasil tahan? 💪'), findsOneWidget);
  });

  testWidgets('"Berhasil tahan" keeps the urge, toasts XP and closes', (
    t,
  ) async {
    final h = _seeded();
    await pumpHabits(t, h, location: '/habits/smoke/urge');
    await _breathe(t);
    await tapIn(t, key('urge-resisted'));
    expect(find.textContaining('+5 XP'), findsOneWidget);
    await settle(t, 10);
    expect(find.text('HOME'), findsOneWidget);
    expect(h.todayLog('smoke', HabitLogType.urge)!.value, 1);
    await settle(t, 30);
  });

  testWidgets('"Aku kalah kali ini" converts the urge into a relapse', (
    t,
  ) async {
    final h = _seeded();
    await pumpHabits(t, h, location: '/habits/smoke/urge');
    await _breathe(t);
    await tapIn(t, key('urge-lost'));
    expect(find.textContaining('Kamu sempat bersih 9 hari'), findsOneWidget);
    await tapIn(t, key('trigger-bosan'), 2);
    await tapIn(t, key('relapse-save'));
    expect(h.todayLog('smoke', HabitLogType.urge), isNull);
    final r = h.todayLog('smoke', HabitLogType.relapse)!;
    expect(r.value, 1);
    expect(r.triggers, ['bosan']);
    expect(find.text('Kamu sempat bersih 9 hari — itu nyata.'), findsOneWidget);
    await tapIn(t, key('relapse-ok'));
    await settle(t, 5);
    expect(find.text('HOME'), findsOneWidget);
  });

  test('box breathing phases are 4 s each and the circle breathes', () {
    expect(breathPhaseAt(Duration.zero), BreathPhase.inhale);
    expect(breathPhaseAt(const Duration(seconds: 5)), BreathPhase.holdIn);
    expect(breathPhaseAt(const Duration(seconds: 9)), BreathPhase.exhale);
    expect(breathPhaseAt(const Duration(seconds: 13)), BreathPhase.holdOut);
    expect(breathPhaseAt(const Duration(seconds: 17)), BreathPhase.inhale);
    expect(breathScaleAt(0), closeTo(0.55, 1e-9));
    expect(breathScaleAt(0.3), 1.0);
    expect(breathScaleAt(0.8), 0.55);
  });

  test('relapse copy never shames', () {
    expect(relapseDoneTitle(12), 'Kamu sempat bersih 12 hari — itu nyata.');
    expect(relapseDoneTitle(0), 'Tercatat. Terima kasih sudah jujur.');
    expect(relapseSheetMessage(3), contains('itu nyata'));
    for (final s in [relapseSheetMessage(0), relapseDoneBody]) {
      expect(s.toLowerCase(), isNot(contains('gagal')));
    }
  });
}
