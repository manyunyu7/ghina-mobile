import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_habits_harness.dart';

HabitsHarness _seeded({HabitKind kind = HabitKind.quit}) {
  final h = HabitsHarness();
  h.habits.s.put(habit('late', 'Berhenti begadang', kind: kind));
  return h;
}

HabitAnalysis _full({String kind = 'quit'}) => HabitAnalysis(
  habitId: 'late',
  kind: kind,
  from: '2026-06-27',
  to: '2026-09-24',
  days: 90,
  current: 14,
  longest: 31,
  lastRelapse: '2026-09-10',
  runCount: 4,
  longestRun: const HabitRun(start: '2026-07-01', end: '2026-07-31', days: 31),
  recentRuns: const [
    HabitRun(start: '2026-09-11', end: '2026-09-24', days: 14, ongoing: true),
  ],
  relapseTotal: 4,
  relapseDays: 3,
  perMonth: const {'2026-08': 3, '2026-09': 1},
  weekday: const {'thu': 3, 'sat': 1},
  timeOfDay: const {'morning': 1, 'evening': 3},
  riskWindows: const [
    HabitRiskWindow(from: '21:00', to: '23:59', count: 3, share: 0.75),
  ],
  triggers: const [HabitTriggerStat(tag: 'bosan', count: 3, share: 0.75)],
  dimensions: const [
    HabitDimensionStat(
      key: 'tingkat_stres',
      label: 'Tingkat stres',
      type: 'number',
      lapse: HabitDimensionAgg(n: 3, avg: 6.67),
      ok: HabitDimensionAgg(n: 1, avg: 6),
      comparable: true,
    ),
    HabitDimensionStat(key: 'suasana', label: 'Suasana', type: 'select'),
  ],
  lastEvents: const [
    HabitEventBrief(
      date: '2026-09-15',
      kind: 'event',
      label: 'Lembur proyek contoh',
      note: 'Cuma sekali',
    ),
  ],
);

void main() {
  testWidgets('renders every section with the numbers', (t) async {
    final h = _seeded();
    h.online.analyses['late'] = _full();
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(find.text('Analisis · Berhenti begadang'), findsOneWidget);
    expect(find.text('14 hari'), findsWidgets);
    expect(find.text('31 hari'), findsWidgets);
    expect(find.text('4 rentetan · terpanjang 31 hari'), findsOneWidget);
    expect(find.text('14 hari · berlangsung'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Pemicu terbanyak'), 300);
    expect(find.text('bosan'), findsOneWidget);
    expect(find.text('3× · 75%'), findsWidgets);
    await t.scrollUntilVisible(find.text('Jam rawan'), 300);
    expect(find.text('21.00–23.59 · 3× · 75%'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Perbandingan dimensi'), 300);
    expect(find.text('Hari kambuh: rata-rata 6.7'), findsOneWidget);
    expect(find.text('Hari bersih: rata-rata 6'), findsOneWidget);
    expect(find.text('belum bisa dibandingkan'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Kejadian terakhir'), 300);
    expect(find.text('2026-09-15 · Lembur proyek contoh'), findsOneWidget);
    expect(h.online.analysisGets, 1);
  });

  testWidgets('empty analysis shows a friendly message', (t) async {
    final h = _seeded();
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(find.byKey(const ValueKey('analysis-empty')), findsOneWidget);
    expect(find.text('Ringkasan'), findsNothing);
  });

  testWidgets('offline shows a distinct message and retries', (t) async {
    final h = _seeded();
    h.online.analyses['late'] = _full();
    h.online.failWith = const NetworkFailure();
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(find.text('Analisis butuh internet'), findsOneWidget);
    h.online.failWith = null;
    await tapIn(t, find.text('COBA LAGI'));
    expect(find.text('Analisis butuh internet'), findsNothing);
    expect(find.text('Ringkasan'), findsOneWidget);
  });

  testWidgets('a generic error shows its message and retry succeeds', (
    t,
  ) async {
    final h = _seeded();
    h.online.analyses['late'] = _full();
    h.online.failWith = const UnknownFailure('Server lagi bermasalah');
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(find.text('Server lagi bermasalah'), findsOneWidget);
    expect(find.text('Analisis butuh internet'), findsNothing);
    h.online.failWith = null;
    await tapIn(t, find.text('COBA LAGI'));
    expect(find.text('Ringkasan'), findsOneWidget);
  });

  testWidgets('switching the range refetches', (t) async {
    final h = _seeded();
    h.online.analyses['late'] = _full();
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(h.online.analysisGets, 1);
    await tapIn(t, find.text('30 hari'));
    expect(h.online.analysisGets, 2);
    await tapIn(t, find.text('365 hari'));
    expect(h.online.analysisGets, 3);
  });

  testWidgets('a build habit says terlewat / terpenuhi', (t) async {
    final h = _seeded(kind: HabitKind.build);
    h.online.analyses['late'] = _full(kind: 'build');
    await pumpHabits(t, h, location: '/habits/late/insights');
    expect(find.text('Rentetan terpenuhi'), findsOneWidget);
    await t
        .scrollUntilVisible(
          find.text('Terpenuhi per bulan'),
          300,
          maxScrolls: 30,
        )
        .catchError((_) {});
    expect(find.textContaining('kambuh'), findsNothing);
    await t.scrollUntilVisible(find.text('Perbandingan dimensi'), 300);
    expect(find.text('Hari terlewat: rata-rata 6.7'), findsOneWidget);
  });
}
