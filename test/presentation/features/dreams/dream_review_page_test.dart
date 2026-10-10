// "Segarkan": the pure helpers and the page against the in-memory fakes.
// Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dream_list_logic.dart';
import 'package:ghina/presentation/features/dreams/dream_review_logic.dart';
import 'package:ghina/presentation/features/dreams/dream_review_page.dart';

import 'dreams_test_rig.dart';

void main() {
  final stale = dreamsNow.subtract(const Duration(days: 90));

  group('logic', () {
    DreamRow row(Dream d) => buildDreamRow(
      d,
      steps: const [],
      metrics: const [],
      nowMs: dreamsNow.millisecondsSinceEpoch,
      today: '2026-10-10',
    );

    test('the session queue keeps list order and only open stale / tagged', () {
      final rows = [
        row(dreamFixture('a', updated: stale)),
        row(dreamFixture('b')),
        row(dreamFixture('c', tags: const ['Perlu-Ditinjau'])),
        row(dreamFixture('d', status: DreamStatus.done, updated: stale)),
      ];
      expect(reviewSessionIds(rows), ['a', 'c']);
      expect(reviewSessionIds(const []), isEmpty);
    });

    test('position text is one-based', () {
      expect(reviewPositionText(2, 43), '3 / 43');
      expect(reviewPositionText(0, 1), '1 / 1');
    });

    test('removeReviewTag is case-insensitive and keeps the rest', () {
      expect(removeReviewTag(['liburan', 'Perlu-Ditinjau', 'x']), [
        'liburan',
        'x',
      ]);
      expect(removeReviewTag(const ['liburan']), ['liburan']);
    });

    test('dreamInputOf copies every field and changes only what is asked', () {
      final d = dreamFixture(
        'a',
        title: 'Trip contoh ke Kota Sample',
        emoji: '🏝️',
        category: 'travel',
        status: DreamStatus.planned,
        priority: 2,
        targetDate: '2027-03-31',
        precision: TargetPrecision.quarter,
        tags: const ['liburan'],
        costEstimate: 5000000,
      ).copyWith(progressManual: 40, why: 'Alasan contoh');
      final same = dreamInputOf(d);
      expect(same.title, d.title);
      expect(same.emoji, '🏝️');
      expect(same.category, 'travel');
      expect(same.status, DreamStatus.planned);
      expect(same.priority, 2);
      expect(same.targetDate, '2027-03-31');
      expect(same.targetPrecision, TargetPrecision.quarter);
      expect(same.progressManual, 40);
      expect(same.why, 'Alasan contoh');
      expect(same.costEstimate, 5000000);
      expect(same.tags, ['liburan']);

      final cleared = dreamInputOf(
        d,
        targetDate: null,
        targetPrecision: null,
        progressManual: null,
      );
      expect(cleared.targetDate, isNull);
      expect(cleared.targetPrecision, isNull);
      expect(cleared.progressManual, isNull);
      expect(cleared.title, d.title);

      final moved = dreamInputOf(d, status: DreamStatus.done, tags: const []);
      expect(moved.status, DreamStatus.done);
      expect(moved.tags, isEmpty);
    });
  });

  group('page', () {
    DreamsRig rig() => DreamsRig(
      categories: [
        categoryFixture('travel', 'Perjalanan', '🧳'),
        categoryFixture('other', 'Lainnya', '✨'),
      ],
      dreams: [
        dreamFixture(
          'd1',
          title: 'Trip contoh ke Kota Sample',
          emoji: '🏝️',
          category: 'travel',
          status: DreamStatus.planned,
          targetDate: '2027-03-31',
          precision: TargetPrecision.quarter,
          tags: const ['liburan', 'perlu-ditinjau'],
          updated: stale,
        ),
        dreamFixture('d2', title: 'Mimpi contoh lama', updated: stale),
        dreamFixture('d3', title: 'Buku contoh'),
        dreamFixture(
          'd4',
          title: 'Mimpi contoh selesai',
          status: DreamStatus.done,
          updated: stale,
        ),
      ],
    );

    Future<void> pump(WidgetTester t, DreamsRig r) async {
      t.view.physicalSize = const Size(1080, 5200);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: '/dreams/review',
        routes: [
          GoRoute(
            path: '/dreams',
            builder: (_, _) => const Scaffold(body: Text('stub-list')),
          ),
          GoRoute(
            path: '/dreams/review',
            builder: (_, _) => const DreamReviewPage(),
          ),
          GoRoute(
            path: '/dreams/:id/edit',
            builder: (_, s) {
              r.visited.add(s.uri.toString());
              return const Scaffold(body: Text('stub-edit'));
            },
          ),
          GoRoute(
            path: '/dreams/:id',
            builder: (_, s) => const Scaffold(body: Text('stub-detail')),
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: r.overrides,
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            themeMode: ThemeMode.light,
            routerConfig: router,
          ),
        ),
      );
      await settle(t);
    }

    testWidgets('shows the first dream, its facts and "1 / 2"', (t) async {
      final r = rig();
      await pump(t, r);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Trip contoh ke Kota Sample'), findsOneWidget);
      expect(find.text('Target Q1 2027'), findsOneWidget);
      expect(find.textContaining('lebih dari'), findsOneWidget);
      expect(find.textContaining('Ditandai perlu ditinjau'), findsOneWidget);
      expect(find.text('Diperbarui 3 bulan lalu'), findsOneWidget);
    });

    testWidgets('Masih berlaku stamps the dream, drops the tag, advances', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-keep');

      final d1 = r.repo.s.items['d1']!;
      expect(d1.updatedAt, dreamsNow);
      expect(d1.tags, ['liburan']);
      // Nothing else moved.
      expect(d1.title, 'Trip contoh ke Kota Sample');
      expect(d1.targetDate, '2027-03-31');
      expect(d1.targetPrecision, TargetPrecision.quarter);
      expect(d1.status, DreamStatus.planned);

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Mimpi contoh lama'), findsOneWidget);

      await tapKey(t, 'review-keep');
      expect(find.byKey(const ValueKey('review-empty')), findsOneWidget);
      expect(find.text('Semua sudah segar'), findsOneWidget);
    });

    testWidgets('skip advances without writing', (t) async {
      final r = rig();
      final before = r.repo.s.items['d1'];
      await pump(t, r);
      await tapKey(t, 'review-skip');
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Mimpi contoh lama'), findsOneWidget);
      expect(r.repo.s.items['d1'], before);
    });

    testWidgets('status change persists and a done dream moves on', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-status');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await tapKey(t, 'status-active');
      expect(r.repo.s.items['d1']!.status, DreamStatus.active);
      // Still open: stays on the same dream.
      expect(find.text('1 / 2'), findsOneWidget);

      await tapKey(t, 'review-status');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await tapKey(t, 'status-done');
      expect(r.repo.s.items['d1']!.status, DreamStatus.done);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Mimpi contoh lama'), findsOneWidget);
    });

    testWidgets('progress slider stores progressManual only', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-progress');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await t.drag(
        find.byKey(const ValueKey('progress-slider')),
        const Offset(150, 0),
      );
      await settle(t);
      await tapKey(t, 'progress-save');
      final d1 = r.repo.s.items['d1']!;
      expect(d1.progressManual, isNotNull);
      expect(d1.progressManual, greaterThan(0));
      expect(d1.title, 'Trip contoh ke Kota Sample');
      expect(d1.targetDate, '2027-03-31');
      expect(d1.tags, ['liburan', 'perlu-ditinjau']);
    });

    testWidgets('Hapus target clears the date, keeps the dream', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-target');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await tapKey(t, 'target-clear');
      final d1 = r.repo.s.items['d1']!;
      expect(d1.targetDate, isNull);
      expect(d1.title, 'Trip contoh ke Kota Sample');
      expect(find.text('Belum ada target'), findsOneWidget);
    });

    testWidgets('picking a day stores it with day precision', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-target');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await tapKey(t, 'target-pick');
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      // The picker opens on the current target month (March 2027).
      await t.tap(find.text('15'));
      await settle(t);
      final d1 = r.repo.s.items['d1']!;
      expect(d1.targetDate, '2027-03-15');
      expect(d1.targetPrecision, TargetPrecision.day);
    });

    testWidgets('Ubah opens the edit route', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'review-edit');
      expect(r.visited, ['/dreams/d1/edit']);
    });

    testWidgets('an empty queue says everything is fresh', (t) async {
      final r = DreamsRig(dreams: [dreamFixture('d3', title: 'Buku contoh')]);
      await pump(t, r);
      expect(find.text('Semua sudah segar'), findsOneWidget);
      await tapText(t, 'KEMBALI');
      expect(find.text('stub-list'), findsOneWidget);
    });
  });
}
