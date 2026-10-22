// Smoke tests of the Mimpi list: the three views rendered from fakes, the status
// change through a card's menu, search, the filter sheet, "Segarkan" and the
// empty state. Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dreams_page.dart';

import 'dreams_test_rig.dart';

void main() {
  final stale = dreamsNow.subtract(const Duration(days: 90));

  DreamsRig rigWithDreams() => DreamsRig(
    categories: [
      categoryFixture('travel', 'Perjalanan', '🧳'),
      categoryFixture('money', 'Uang', '💰'),
      categoryFixture('other', 'Lainnya', '✨'),
    ],
    dreams: [
      dreamFixture(
        'd1',
        title: 'Trip contoh ke Kota Sample',
        emoji: '🏝️',
        category: 'travel',
        status: DreamStatus.planned,
        priority: 2,
        targetDate: '2027-03-31',
        precision: TargetPrecision.quarter,
        tags: const ['liburan'],
        costEstimate: 5000000,
      ),
      dreamFixture(
        'd2',
        title: 'Tabungan contoh dana darurat',
        emoji: '🐷',
        category: 'money',
        status: DreamStatus.active,
        priority: 1,
        updated: stale,
      ),
      dreamFixture('d3', title: 'Buku contoh', status: DreamStatus.done),
    ],
    steps: [
      DreamStep(
        id: 's1',
        dreamId: 'd1',
        title: 'Pesan tiket contoh',
        cost: 1200000,
        createdAt: dreamsNow,
        updatedAt: dreamsNow,
      ),
    ],
  );

  testWidgets('board: a column per status, cards from the fakes', (t) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    expect(find.byKey(const ValueKey('dreams-board')), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-card-d1')), findsOneWidget);
    expect(find.text('Trip contoh ke Kota Sample'), findsOneWidget);
    expect(find.text('🧳 Perjalanan'), findsWidgets);
    expect(find.byKey(const ValueKey('board-planned')), findsOneWidget);
    // Empty statuses keep their column.
    expect(find.byKey(const ValueKey('board-idea')), findsOneWidget);
    expect(find.text('Belum ada'), findsWidgets);
  });

  testWidgets('summary strip counts open dreams and the open cost', (t) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    expect(find.text('Terbuka 2'), findsOneWidget);
    expect(find.textContaining('Biaya terbuka'), findsOneWidget);
    expect(find.text('Basi 1'), findsOneWidget);
  });

  testWidgets('table: rows with progress and the effective cost', (t) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());
    await tapText(t, 'Tabel');

    expect(find.byKey(const ValueKey('dreams-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-row-d1')), findsOneWidget);
    // The estimate (5 juta) wins over the step sum.
    final row = find.byKey(const ValueKey('dream-row-d1'));
    expect(
      find.descendant(of: row, matching: find.textContaining('5.000.000')),
      findsOneWidget,
    );
  });

  testWidgets('timeline: quarter sections, horizons and undated last', (
    t,
  ) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());
    await tapText(t, 'Garis waktu');

    expect(find.byKey(const ValueKey('dreams-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-2027-Q1')), findsOneWidget);
    expect(find.text('Kuartal 1 2027'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-undated')), findsOneWidget);
    expect(find.text('Tanpa tanggal'), findsOneWidget);
  });

  testWidgets('status change through the card menu persists', (t) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    await tapKey(t, 'dream-menu-d1');
    await tapKey(t, 'status-done');

    expect(rig.repo.s.items['d1']!.status, DreamStatus.done);
    expect(rig.repo.s.items['d1']!.completedAt, isNotNull);
    expect(find.byKey(const ValueKey('dream-card-d1')), findsOneWidget);
  });

  testWidgets('search narrows the shown dreams', (t) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('dreams-search')),
        matching: find.byType(TextField),
      ),
      'tabungan',
    );
    await settle(t);

    expect(find.byKey(const ValueKey('dream-card-d2')), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-card-d1')), findsNothing);
  });

  testWidgets('filter sheet: status chip applies and shows the match', (
    t,
  ) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    await tapKey(t, 'dreams-filter');
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    // The board's own column header carries the same words: tap the chip.
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('filter-status')),
        matching: find.text('✅ Tercapai'),
      ),
    );
    await settle(t);
    await tapKey(t, 'filter-apply');

    expect(find.byKey(const ValueKey('dream-card-d3')), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-card-d1')), findsNothing);
  });

  testWidgets('"Segarkan (1)" appears for the stale dream and opens review', (
    t,
  ) async {
    final rig = rigWithDreams();
    await rig.pump(t, '/dreams', () => const DreamsPage());

    expect(find.byKey(const ValueKey('dreams-review')), findsOneWidget);
    // ChunkyButton sets its label in capitals.
    expect(find.text('SEGARKAN (1)'), findsOneWidget);
    await tapKey(t, 'dreams-review');
    expect(rig.visited, contains('/dreams/review'));
  });

  testWidgets('no review button when nothing is stale or tagged', (t) async {
    final rig = DreamsRig(dreams: [dreamFixture('d1', title: 'Buku contoh')]);
    await rig.pump(t, '/dreams', () => const DreamsPage());
    expect(find.byKey(const ValueKey('dreams-review')), findsNothing);
  });

  testWidgets('empty state when there are no dreams', (t) async {
    final rig = DreamsRig();
    await rig.pump(t, '/dreams', () => const DreamsPage());
    expect(find.text('Belum ada mimpi'), findsOneWidget);
    expect(find.byKey(const ValueKey('dreams-board')), findsNothing);
  });
}
