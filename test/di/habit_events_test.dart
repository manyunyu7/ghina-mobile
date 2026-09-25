import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/models/habits_investments_wire.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/activity.dart';

final _t = DateTime(2026, 9, 20, 8);

HabitLog _l(String habitId, String date, HabitLogType type, [double? v]) =>
    HabitLog(
      id: '$habitId$date${type.wire}',
      habitId: habitId,
      date: date,
      type: type,
      value: v,
      createdAt: _t,
      updatedAt: _t,
    );

void main() {
  test('habit activity events: day met, clean check-in, urges, milestones', () {
    final build = Habit(
      id: 'b',
      name: 'Air',
      target: HabitTarget.count(8),
      startDate: '2026-09-01',
      createdAt: _t,
      updatedAt: _t,
    );
    final quit = Habit(
      id: 'q',
      name: 'Rokok',
      kind: HabitKind.quit,
      startDate: '2026-09-19',
      createdAt: _t,
      updatedAt: _t,
    );
    final events = habitActivityEventsFrom(
      [build, quit],
      [
        _l('b', '2026-09-20', HabitLogType.done, 8),
        _l('b', '2026-09-21', HabitLogType.done, 3), // not met
        _l('q', '2026-09-20', HabitLogType.done, 1),
        _l('q', '2026-09-21', HabitLogType.urge, 4),
      ],
      DateTime(2026, 9, 25, 10),
    );
    final byType = <HabitEventType, List<ActivityEvent>>{};
    for (final e in events) {
      expect(e.kind, ActivityKind.habit);
      byType.putIfAbsent(e.habitType!, () => []).add(e);
    }
    expect(byType[HabitEventType.buildDayMet]!.single.id, 'b:2026-09-20');
    expect(byType[HabitEventType.buildDayMet]!.single.at, _t);
    expect(byType[HabitEventType.quitCleanCheckIn]!.single.habitKind, 'quit');
    expect(byType[HabitEventType.urgeResisted]!.single.habitValue, 4);
    // Quit clean since 19th → 1, 3, 7 reached by the 25th; the habit was
    // created on the 20th, so day 1 (the 19th, before it existed) is history.
    expect(
      [for (final e in byType[HabitEventType.milestone]!) e.habitMilestone],
      [3, 7],
    );
    expect(byType[HabitEventType.milestone]!.last.id, 'q:7:2026-09-19');
  });

  test('a backdated start date pays no milestones already passed at creation, '
      'only the ones reached afterwards', () {
    // "Sudah bersih sejak…" 400 days ago, entered on Sep 20.
    final quit = Habit(
      id: 'q',
      name: 'Rokok',
      kind: HabitKind.quit,
      startDate: '2025-08-17',
      createdAt: _t,
      updatedAt: _t,
    );
    List<int?> milestones(DateTime today) => [
      for (final e in habitActivityEventsFrom([quit], const [], today))
        if (e.habitType == HabitEventType.milestone) e.habitMilestone,
    ];
    // Day 400 is Sep 20 itself (creation day): nothing earned yet.
    expect(milestones(DateTime(2026, 9, 20, 10)), isEmpty);
    // Day 500 (Dec 29) is reached in the app → earned.
    expect(milestones(DateTime(2026, 12, 29, 10)), [500]);
    // A relapse after creation starts a fresh run: its milestones count.
    final after = habitActivityEventsFrom(
      [quit],
      [_l('q', '2026-09-21', HabitLogType.relapse, 1)],
      DateTime(2026, 9, 29, 10),
    );
    expect(
      [
        for (final e in after)
          if (e.habitType == HabitEventType.milestone) e.habitMilestone,
      ],
      [1, 3, 7],
    );
    // Not backdated (start = creation day): day 1 counts as before.
    final fresh = Habit(
      id: 'f',
      name: 'Begadang',
      kind: HabitKind.quit,
      startDate: '2026-09-20',
      createdAt: _t,
      updatedAt: _t,
    );
    expect(
      [
        for (final e in habitActivityEventsFrom(
          [fresh],
          const [],
          DateTime(2026, 9, 20, 22),
        ))
          e.habitMilestone,
      ],
      [1],
    );
  });

  test(
    'prices response: quotes by key, not_found reported, no price kept out',
    () {
      final now = DateTime.utc(2026, 9, 25, 3);
      final r = pricesResponseFromWire({
        'serverTime': 1,
        'prices': [
          {
            'kind': 'stock',
            'symbol': 'BBCA',
            'name': 'BCA',
            'price': 9500,
            'prevClose': 9400,
            'change': 100,
            'changePct': 1.06,
            'currency': 'IDR',
            'asOf': '2026-09-25T02:00:00.000Z',
            'fetchedAt': '2026-09-25T02:55:00.000Z',
            'source': 'yahoo',
            'stale': false,
            'error': null,
          },
          {
            'kind': 'stock',
            'symbol': 'ZZZZ',
            'price': null,
            'error': 'not_found',
          },
          {
            'kind': 'crypto',
            'symbol': 'BTC',
            'price': null,
            'error': 'unavailable',
          },
        ],
      }, receivedAt: now);
      expect(r.prices.keys, ['stock:BBCA']);
      final p = r.prices['stock:BBCA']!;
      expect(
        (p.price, p.prevClose, p.name, p.cachedAt),
        (9500, 9400, 'BCA', now),
      );
      expect(
        p.fetchedAt!.isAtSameMomentAs(DateTime.utc(2026, 9, 25, 2, 55)),
        isTrue,
      );
      expect(r.notFound, ['stock:ZZZZ']);
    },
  );
}
