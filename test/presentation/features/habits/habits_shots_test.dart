// Screenshots of the Kebiasaan screens for visual review:
// GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/habits/habits_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart';
import 'package:ghina/presentation/features/home/widgets/home_habits.dart';

import '../../design_system/_helpers.dart';
import '_habits_harness.dart';

const _key = ValueKey('shot');

HabitsHarness _seeded({bool lock = false}) {
  final h = HabitsHarness(lockEnabled: lock);
  h.habits.s
    ..put(habit('run', 'Lari pagi', emoji: '🏃', color: '#FF9600'))
    ..put(
      habit(
        'water',
        'Minum air',
        emoji: '💧',
        color: '#1CB0F6',
        target: HabitTarget.count(8, unit: 'gelas'),
        order: 1,
      ),
    )
    ..put(
      habit(
        'read',
        'Baca buku',
        emoji: '📖',
        color: '#CE82FF',
        target: HabitTarget.duration(30),
        order: 2,
      ),
    )
    ..put(
      habit(
        'gym',
        'Angkat beban',
        emoji: '🏋️',
        schedule: HabitSchedule.perWeek(3),
        order: 3,
      ),
    )
    ..put(
      habit(
        'smoke',
        'Rokok',
        emoji: '🚭',
        kind: HabitKind.quit,
        startDate: daysAgo(40),
        why: 'Biar napas lega main bola sama anak tiap sore.',
        order: 4,
      ),
    )
    ..put(
      habit(
        'judol',
        'Judi online',
        emoji: '🎰',
        kind: HabitKind.quit,
        isPrivate: true,
        startDate: daysAgo(5),
        order: 5,
      ),
    );
  // A lived-in month.
  for (var d = 1; d <= 25; d++) {
    if (d % 6 != 0) h.logs.s.put(log('run', daysAgo(d), HabitLogType.done));
    if (d % 4 != 0) {
      h.logs.s.put(
        log('water', daysAgo(d), HabitLogType.done, value: d % 3 == 0 ? 5 : 8),
      );
    }
    if (d % 3 == 0) {
      h.logs.s.put(
        log(
          'smoke',
          daysAgo(d),
          HabitLogType.urge,
          value: 1 + d % 2,
          at: DateTime(2026, 9, 24 - d, 20 + d % 3),
          triggers: d % 2 == 0 ? ['stres'] : ['bosan', 'malam'],
        ),
      );
    }
  }
  h.logs.s
    ..put(log('run', daysAgo(0), HabitLogType.done))
    ..put(log('water', daysAgo(0), HabitLogType.done, value: 3))
    ..put(log('read', daysAgo(0), HabitLogType.done, value: 10))
    ..put(
      log(
        'smoke',
        daysAgo(12),
        HabitLogType.relapse,
        triggers: ['stres', 'capek'],
        note: 'Deadline kantor, begadang. Besok coba jalan sore.',
        at: DateTime(2026, 9, 12, 23),
      ),
    )
    ..put(log('smoke', daysAgo(30), HabitLogType.relapse, triggers: ['medsos']))
    ..put(log('gym', daysAgo(1), HabitLogType.done));
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool lock = false,
  Widget? home,
  Future<void> Function(WidgetTester t)? act,
}) async {
  await loadGhinaFonts();
  final h = _seeded(lock: lock);
  if (lock) h.auth.outcome = HabitAuthOutcome.cancelled;
  await pumpHabits(
    tester,
    h,
    location: location,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: _key,
    home: home,
  );
  if (act != null) await act(tester);
  await saveShot(tester, _key, name);
  expect(tester.takeException(), isNull);
  await settle(tester, 40);
}

Future<void> _scroll(WidgetTester t, double dy) async {
  await t.drag(find.byType(Scrollable).first, Offset(0, -dy));
  await settle(t, 4);
}

void main() {
  testWidgets('list light', (t) => _shot(t, 'habits_list_light', '/habits'));
  testWidgets(
    'list light quit',
    (t) => _shot(
      t,
      'habits_list_quit_light',
      '/habits',
      act: (t) => _scroll(t, 900),
    ),
  );
  testWidgets(
    'list dark',
    (t) => _shot(t, 'habits_list_dark', '/habits', dark: true),
  );
  testWidgets(
    'list small',
    (t) => _shot(
      t,
      'habits_list_small',
      '/habits',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'list small quit',
    (t) => _shot(
      t,
      'habits_list_small_quit',
      '/habits',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) => _scroll(t, 1400),
    ),
  );
  testWidgets(
    'urge light',
    (t) => _shot(
      t,
      'habits_urge_light',
      '/habits/smoke/urge',
      act: (t) async {
        await t.pump(const Duration(milliseconds: 1500));
      },
    ),
  );
  testWidgets(
    'urge dark end',
    (t) => _shot(
      t,
      'habits_urge_dark_end',
      '/habits/smoke/urge',
      dark: true,
      act: (t) async {
        for (var i = 0; i < 62; i++) {
          await t.pump(const Duration(seconds: 1));
        }
      },
    ),
  );
  testWidgets(
    'urge small',
    (t) => _shot(
      t,
      'habits_urge_small',
      '/habits/smoke/urge',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) async {
        await t.pump(const Duration(seconds: 2));
      },
    ),
  );
  testWidgets(
    'relapse sheet',
    (t) => _shot(
      t,
      'habits_relapse_sheet',
      '/habits',
      act: (t) async {
        await tapIn(t, find.byKey(const ValueKey('habit-relapse-smoke')), 8);
      },
    ),
  );
  testWidgets(
    'relapse done small',
    (t) => _shot(
      t,
      'habits_relapse_done_small',
      '/habits',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) async {
        await tapIn(t, find.byKey(const ValueKey('habit-relapse-smoke')), 8);
        await tapIn(t, find.byKey(const ValueKey('relapse-save')), 8);
      },
    ),
  );
  testWidgets(
    'detail quit light',
    (t) => _shot(t, 'habits_detail_quit_light', '/habits/smoke'),
  );
  testWidgets(
    'detail quit insights',
    (t) => _shot(
      t,
      'habits_detail_quit_insights',
      '/habits/smoke',
      act: (t) => _scroll(t, 1300),
    ),
  );
  testWidgets(
    'detail quit journal',
    (t) => _shot(
      t,
      'habits_detail_quit_journal',
      '/habits/smoke',
      act: (t) => _scroll(t, 2300),
    ),
  );
  testWidgets(
    'detail build dark',
    (t) => _shot(t, 'habits_detail_build_dark', '/habits/water', dark: true),
  );
  testWidgets(
    'detail build heatmap dark',
    (t) => _shot(
      t,
      'habits_detail_build_heatmap_dark',
      '/habits/water',
      dark: true,
      act: (t) => _scroll(t, 700),
    ),
  );
  testWidgets(
    'detail small',
    (t) => _shot(
      t,
      'habits_detail_small',
      '/habits/run',
      size: const Size(360, 640),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'detail small scrolled',
    (t) => _shot(
      t,
      'habits_detail_small_scrolled',
      '/habits/run',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) => _scroll(t, 900),
    ),
  );
  testWidgets(
    'form light',
    (t) => _shot(t, 'habits_form_light', '/habits/new'),
  );
  testWidgets(
    'form count dark',
    (t) => _shot(
      t,
      'habits_form_count_dark',
      '/habits/water/edit',
      dark: true,
      act: (t) => _scroll(t, 450),
    ),
  );
  testWidgets(
    'form small',
    (t) => _shot(
      t,
      'habits_form_small',
      '/habits/smoke/edit',
      size: const Size(360, 640),
      textScale: 1.3,
      act: (t) => _scroll(t, 500),
    ),
  );
  testWidgets(
    'lock screen',
    (t) => _shot(t, 'habits_lock', '/habits', lock: true),
  );
  testWidgets(
    'home card light',
    (t) => _shot(
      t,
      'habits_home_card_light',
      '/',
      home: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: HomeHabitsCard(),
      ),
    ),
  );
  testWidgets(
    'home card small dark',
    (t) => _shot(
      t,
      'habits_home_card_small_dark',
      '/',
      dark: true,
      size: const Size(360, 640),
      textScale: 1.3,
      home: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: HomeHabitsCard(),
      ),
    ),
  );
}
