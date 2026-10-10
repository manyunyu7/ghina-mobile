// Mimpi markers on the calendar: the pure range logic and the read-only
// overlay on CalendarPage. Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/calendar/pages/calendar_page.dart';
import 'package:ghina/presentation/features/dreams/dream_calendar.dart';
import 'package:go_router/go_router.dart';

import 'dreams_test_rig.dart';

void main() {
  group('dreamTargetMarkers', () {
    final dreams = [
      dreamFixture(
        'a',
        title: 'Trip contoh ke Kota Sample',
        emoji: '🏝️',
        status: DreamStatus.planned,
        targetDate: '2026-12-31',
        precision: TargetPrecision.quarter,
      ),
      dreamFixture('b', targetDate: '2026-12-31', status: DreamStatus.done),
      dreamFixture('c', targetDate: '2026-12-31', status: DreamStatus.dropped),
      dreamFixture('d'),
      dreamFixture('e', targetDate: '2026-11-01'),
      dreamFixture(
        'f',
        targetDate: '2026-11-30',
        precision: TargetPrecision.month,
      ),
      dreamFixture('g', targetDate: '2026-10-31'),
      dreamFixture(
        'h',
        targetDate: '2027-12-31',
        precision: TargetPrecision.year,
      ),
    ];

    test('keeps open dreams with a target in range, by target date', () {
      final m = dreamTargetMarkers(
        dreams,
        from: '2026-11-01',
        to: '2026-12-31',
      );
      expect(m.keys.toSet(), {'2026-11-01', '2026-11-30', '2026-12-31'});
      expect(m['2026-12-31']!.map((x) => x.dreamId), ['a']);
    });

    test('done, dropped and undated dreams are left out', () {
      final m = dreamTargetMarkers(
        dreams,
        from: '2026-01-01',
        to: '2030-01-01',
      );
      final ids = [for (final l in m.values) ...l.map((x) => x.dreamId)];
      expect(ids, isNot(contains('b')));
      expect(ids, isNot(contains('c')));
      expect(ids, isNot(contains('d')));
    });

    test('both ends of the range are inclusive', () {
      final m = dreamTargetMarkers(
        dreams,
        from: '2026-11-01',
        to: '2026-11-30',
      );
      expect(m.keys.toSet(), {'2026-11-01', '2026-11-30'});
      expect(m.containsKey('2026-10-31'), isFalse);
      expect(m.containsKey('2026-12-31'), isFalse);
    });

    test('carries the precision label and the period text', () {
      final m = dreamTargetMarkers(
        dreams,
        from: '2026-01-01',
        to: '2030-12-31',
      );
      final q = m['2026-12-31']!.single;
      expect([q.title, q.emoji], ['Trip contoh ke Kota Sample', '🏝️']);
      expect([q.precisionLabel, q.period], ['Kuartal', 'Q4 2026']);
      expect(m['2026-11-30']!.single.precisionLabel, 'Bulan');
      expect(m['2026-11-30']!.single.period, 'November 2026');
      expect(m['2026-11-01']!.single.precisionLabel, 'Tanggal');
      expect(m['2026-11-01']!.single.period, '1 Nov 2026');
      expect(m['2027-12-31']!.single.precisionLabel, 'Tahun');
      expect(m['2027-12-31']!.single.period, '2027');
    });

    test('a dream without an emoji reads as the target mark', () {
      final m = dreamTargetMarkers(
        [dreamFixture('x', targetDate: '2026-11-01')],
        from: '2026-11-01',
        to: '2026-11-01',
      );
      expect(m['2026-11-01']!.single.emoji, '🎯');
    });
  });

  group('calendar overlay', () {
    Future<void> pump(WidgetTester t, DreamsRig rig) async {
      t.view.physicalSize = const Size(1080, 5200);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: '/calendar',
        routes: [
          GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
          GoRoute(
            path: '/dreams/:id',
            builder: (_, s) {
              rig.visited.add(s.uri.toString());
              return const Scaffold(body: Text('stub-detail'));
            },
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ...rig.overrides,
            calendarEventRepositoryProvider.overrideWithValue(_Events()),
            reminderItemRepositoryProvider.overrideWithValue(_Reminders()),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await settle(t);
    }

    testWidgets('an open dream with a quarter target marks its day', (t) async {
      final rig = DreamsRig(
        dreams: [
          dreamFixture(
            'd1',
            title: 'Trip contoh ke Kota Sample',
            emoji: '🏝️',
            status: DreamStatus.planned,
            targetDate: '2026-12-31',
            precision: TargetPrecision.quarter,
          ),
          dreamFixture(
            'd2',
            title: 'Buku contoh',
            status: DreamStatus.done,
            targetDate: '2026-10-20',
          ),
          dreamFixture('d3', title: 'Mimpi contoh', targetDate: '2026-10-25'),
        ],
      );
      await pump(t, rig);

      // The Oct 2026 grid also shows the first days of November.
      expect(
        find.byKey(const ValueKey('cal-dream-2026-10-25')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cal-dream-2026-10-20')), findsNothing);
      expect(find.byKey(const ValueKey('cal-dream-2026-12-31')), findsNothing);

      await t.tap(find.byKey(const ValueKey('cal-day-2026-10-25')));
      await settle(t);
      expect(find.text('🎯 Mimpi contoh'), findsOneWidget);
      expect(find.text('Target 25 Okt 2026'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('cal-day-2026-10-20')));
      await settle(t);
      expect(find.textContaining('Buku contoh'), findsNothing);
    });

    testWidgets('the quarter-end day shows the tile and opens the dream', (
      t,
    ) async {
      final rig = DreamsRig(
        dreams: [
          dreamFixture(
            'd1',
            title: 'Trip contoh ke Kota Sample',
            emoji: '🏝️',
            status: DreamStatus.planned,
            targetDate: '2026-12-31',
            precision: TargetPrecision.quarter,
          ),
        ],
      );
      await pump(t, rig);
      // Move two months ahead with the month switcher.
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byTooltip('Bulan berikutnya'));
        await settle(t);
      }
      expect(
        find.byKey(const ValueKey('cal-dream-2026-12-31')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('cal-day-2026-12-31')));
      await settle(t);
      expect(find.text('Target Q4 2026'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cal-dream-tile-d1')));
      await settle(t);
      expect(rig.visited, ['/dreams/d1']);
    });

    testWidgets('no marker for a done dream', (t) async {
      final rig = DreamsRig(
        dreams: [
          dreamFixture(
            'd1',
            title: 'Buku contoh',
            status: DreamStatus.done,
            targetDate: '2026-10-25',
          ),
        ],
      );
      await pump(t, rig);
      expect(find.byKey(const ValueKey('cal-dream-2026-10-25')), findsNothing);
    });
  });
}

class _Events implements CalendarEventRepository {
  final items = <String, CalendarEvent>{};
  @override
  Stream<List<CalendarEvent>> watchAll() => Stream.value(items.values.toList());
  @override
  Future<List<CalendarEvent>> getAll() async => items.values.toList();
  @override
  Stream<CalendarEvent?> watchById(String id) => Stream.value(items[id]);
  @override
  Future<CalendarEvent?> getById(String id) async => items[id];
  @override
  Future<void> save(CalendarEvent e) async => items[e.id] = e;
  @override
  Future<void> delete(String id) async => items.remove(id);
}

class _Reminders implements ReminderItemRepository {
  @override
  Stream<List<ReminderItem>> watchAll() => Stream.value(const []);
  @override
  Future<List<ReminderItem>> getAll() async => const [];
  @override
  Stream<ReminderItem?> watchById(String id) => Stream.value(null);
  @override
  Future<ReminderItem?> getById(String id) async => null;
  @override
  Future<void> save(ReminderItem r) async {}
  @override
  Future<void> delete(String id) async {}
}
