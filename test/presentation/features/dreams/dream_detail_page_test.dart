// Widget tests of the Mimpi detail: computed metric values with the tri-state
// on-track badge, the offline fallback, manual readings (online first, local
// when offline), steps, the linked note, delete and the status change.
// Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/dreams/dream_detail_page.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/dreams_fakes.dart';
import 'dreams_test_rig.dart';

void main() {
  DreamMetric metric(
    String id, {
    MetricSource source = MetricSource.weight,
    double? manualValue,
    double? startValue = 80,
    double target = 70,
  }) => DreamMetric(
    id: id,
    dreamId: 'd1',
    label: 'Metrik $id',
    source: source,
    startValue: startValue,
    targetValue: target,
    targetDate: '2027-03-31',
    manualValue: manualValue,
    createdAt: dreamsNow,
    updatedAt: dreamsNow,
  );

  DreamStep step(
    String id, {
    bool done = false,
    String? reward,
    String? dueDate,
    double? cost,
  }) => DreamStep(
    id: id,
    dreamId: 'd1',
    title: 'Langkah $id',
    done: done,
    reward: reward,
    dueDate: dueDate,
    cost: cost,
    createdAt: dreamsNow,
    updatedAt: dreamsNow,
  );

  Dream dream({String? noteId, String? parentId, String id = 'd1'}) => Dream(
    id: id,
    title: id == 'd1' ? 'Trip contoh ke Kota Sample' : 'Mimpi contoh $id',
    emoji: '🏝️',
    category: 'travel',
    status: DreamStatus.planned,
    priority: 2,
    targetDate: '2027-03-31',
    why: 'Biar semangat',
    costEstimate: 5000000,
    tags: const ['liburan'],
    noteId: noteId,
    parentId: parentId,
    createdAt: dreamsNow,
    updatedAt: dreamsNow,
  );

  DreamDetail detailOf(List<DreamMetric> ms, List<DreamMetricReading> rs) =>
      DreamDetail(
        dream: dream(),
        metrics: [
          for (var i = 0; i < ms.length; i++)
            DreamMetricView(metric: ms[i], reading: rs[i]),
        ],
        progress: const DreamProgressView(pct: 40),
        reviewReasons: const ['off_track'],
      );

  Future<void> pumpDetail(
    WidgetTester t,
    DreamsRig rig, {
    List<Override> extra = const [],
    String id = 'd1',
  }) async {
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/dreams/$id',
      routes: [
        GoRoute(
          path: '/dreams',
          builder: (_, _) => const Scaffold(body: Text('stub-list')),
        ),
        GoRoute(
          path: '/dreams/:id',
          builder: (_, s) => DreamDetailPage(id: s.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, s) {
                rig.visited.add(s.uri.toString());
                return const Scaffold(body: Text('stub-edit'));
              },
            ),
          ],
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (_, s) {
            rig.visited.add(s.uri.toString());
            return const Scaffold(body: Text('stub-note'));
          },
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [...rig.overrides, ...extra],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          themeMode: ThemeMode.light,
          routerConfig: router,
        ),
      ),
    );
    await settle(t);
  }

  testWidgets('online metrics: badge per tri-state, null never on track', (
    t,
  ) async {
    final ms = [metric('m1'), metric('m2'), metric('m3')];
    final rig = DreamsRig(
      dreams: [dream()],
      metrics: ms,
      online: FakeDreamOnlineRepository(
        detailValue: detailOf(ms, const [
          DreamMetricReading(
            currentValue: 75,
            progressPct: 50,
            onTrack: true,
            projectedDate: '2027-02-01',
          ),
          DreamMetricReading(currentValue: 79, progressPct: 10, onTrack: false),
          DreamMetricReading(currentValue: 78),
        ]),
      ),
    );
    await pumpDetail(t, rig);

    Finder inCard(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('metric-$id')),
      matching: find.text(text),
      skipOffstage: false,
    );
    expect(inCard('m1', 'Di jalur'), findsOneWidget);
    expect(inCard('m1', '50%'), findsOneWidget);
    expect(inCard('m1', '75 kg → 70 kg'), findsOneWidget);
    expect(inCard('m1', 'Proyeksi 1 Feb 2027'), findsOneWidget);
    expect(inCard('m2', 'Meleset'), findsOneWidget);
    expect(inCard('m3', 'Belum bisa dinilai'), findsOneWidget);
    expect(inCard('m3', 'Di jalur'), findsNothing);
    expect(inCard('m3', 'Meleset'), findsNothing);
    // Unknown progress shows a dash, not 0%.
    expect(inCard('m3', '—'), findsOneWidget);
    // Header uses the online progress.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dream-progress')),
        matching: find.text('40%'),
      ),
      findsOneWidget,
    );
    expect(find.text('Lewat jalur'), findsOneWidget);
    expect(find.text('Butuh internet untuk nilai terhitung'), findsNothing);
  });

  testWidgets('offline: stored values, a note, and no on-track badge', (
    t,
  ) async {
    final ms = [
      metric('m1'),
      metric('m2', source: MetricSource.manual, manualValue: 75),
    ];
    final rig = DreamsRig(
      dreams: [dream()],
      metrics: ms,
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);

    expect(find.text('Target 70 kg'), findsOneWidget);
    expect(find.text('Butuh internet untuk nilai terhitung'), findsOneWidget);
    // The manual metric shows its stored reading and a local progress (50%).
    expect(find.text('75 → 70'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Di jalur'), findsNothing);
    expect(find.text('Meleset'), findsNothing);
    expect(find.text('Belum bisa dinilai'), findsNothing);
    expect(find.text('Lewat jalur'), findsNothing);
    // Local header data still renders.
    expect(find.text('Trip contoh ke Kota Sample'), findsWidgets);
    expect(find.text('Biar semangat'), findsOneWidget);
    expect(find.text('#liburan'), findsOneWidget);
  });

  testWidgets('manual reading goes online first and refreshes', (t) async {
    final m = metric('m1', source: MetricSource.manual);
    final online = FakeDreamOnlineRepository(
      detailValue: detailOf([m], const [DreamMetricReading(onTrack: true)]),
      manualValue: ManualValueResult(metric: DreamMetricView(metric: m)),
    );
    final rig = DreamsRig(dreams: [dream()], metrics: [m], online: online);
    await pumpDetail(t, rig);

    await t.enterText(find.byKey(const ValueKey('metric-input-m1')), '72,5');
    await tapKey(t, 'metric-save-m1');

    expect(online.calls, contains('value:d1/m1=72.5'));
    // Detail was fetched again after the reading.
    expect(online.calls.where((c) => c == 'fetch:d1').length, 2);
    // Nothing was written locally: the server owns the value.
    expect(rig.metrics.s.items['m1']!.manualValue, isNull);
  });

  testWidgets('manual reading offline falls back to the local write', (
    t,
  ) async {
    final m = metric('m1', source: MetricSource.manual);
    final online = FakeDreamOnlineRepository(failure: const NetworkFailure());
    final rig = DreamsRig(dreams: [dream()], metrics: [m], online: online);
    await pumpDetail(t, rig);

    await t.enterText(find.byKey(const ValueKey('metric-input-m1')), '72.5');
    await tapKey(t, 'metric-save-m1');

    expect(online.calls, contains('value:d1/m1=72.5'));
    expect(rig.metrics.s.items['m1']!.manualValue, 72.5);
    expect(find.textContaining('disimpan dulu'), findsOneWidget);
    // The stored reading is now on the card.
    expect(find.text('72,5 → 70'), findsOneWidget);
  });

  testWidgets('manual reading rejects empty and non-numeric input', (t) async {
    final m = metric('m1', source: MetricSource.manual);
    final online = FakeDreamOnlineRepository(failure: const NetworkFailure());
    final rig = DreamsRig(dreams: [dream()], metrics: [m], online: online);
    await pumpDetail(t, rig);

    await tapKey(t, 'metric-save-m1');
    expect(find.text('Isi nilainya dulu ya'), findsOneWidget);

    // The field's input filter drops letters, so only a lone sign is left.
    await t.enterText(find.byKey(const ValueKey('metric-input-m1')), 'abc');
    await tapKey(t, 'metric-save-m1');
    expect(find.text('Isi nilainya dulu ya'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('metric-input-m1')), '-');
    await tapKey(t, 'metric-save-m1');
    expect(find.text('Nilai harus berupa angka'), findsOneWidget);

    expect(online.calls.where((c) => c.startsWith('value:')), isEmpty);
    expect(rig.metrics.s.items['m1']!.manualValue, isNull);
  });

  testWidgets('toggling a step persists doneAt; a done step shows its reward', (
    t,
  ) async {
    final rig = DreamsRig(
      dreams: [dream()],
      steps: [
        step('s1', dueDate: '2026-10-20', cost: 1200000),
        step('s2', done: true, reward: 'Makan enak'),
      ],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);

    expect(find.byKey(const ValueKey('step-reward-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-reward-s1')), findsNothing);
    expect(find.textContaining('Tersisa 10 hari'), findsOneWidget);

    await tapKey(t, 'step-check-s1');
    expect(rig.steps.s.items['s1']!.done, isTrue);
    expect(rig.steps.s.items['s1']!.doneAt, isNotNull);
    expect(find.text('Langkah s1'), findsOneWidget);
  });

  testWidgets('cost panel uses the local totals', (t) async {
    final rig = DreamsRig(
      dreams: [dream()],
      steps: [step('s1', cost: 1200000), step('s2', done: true, cost: 300000)],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);
    final panel = find.byKey(const ValueKey('dream-cost'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Perkiraan')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.textContaining('5.000.000')),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.textContaining('3.500.000')),
      findsOneWidget,
    );
  });

  testWidgets('linked note: title and a button that opens it', (t) async {
    final rig = DreamsRig(
      dreams: [dream(noteId: 'n1')],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(
      t,
      rig,
      extra: [
        watchNoteProvider('n1').overrideWith(
          (ref) => Stream.value(
            NoteView(
              note: Note(
                id: 'n1',
                title: 'Catatan contoh',
                createdAt: dreamsNow,
                updatedAt: dreamsNow,
              ),
              labels: const [],
            ),
          ),
        ),
      ],
    );
    expect(find.text('📝 Catatan contoh'), findsOneWidget);
    await tapKey(t, 'dream-note-open');
    expect(rig.visited, contains('/notes/n1'));
  });

  testWidgets('linked note that is gone says so', (t) async {
    final rig = DreamsRig(
      dreams: [dream(noteId: 'n9')],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(
      t,
      rig,
      extra: [
        watchNoteProvider('n9').overrideWith((ref) => Stream.value(null)),
      ],
    );
    expect(find.text('📝 Catatan tidak ditemukan'), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-note-open')), findsNothing);
  });

  testWidgets('no linked note: no note section', (t) async {
    final rig = DreamsRig(
      dreams: [dream()],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);
    expect(find.byKey(const ValueKey('dream-note-title')), findsNothing);
  });

  testWidgets('delete asks first, then removes the dream', (t) async {
    final rig = DreamsRig(
      dreams: [dream()],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);

    await t.tap(find.byTooltip('Hapus'));
    await settle(t);
    expect(find.text('Hapus mimpi ini?'), findsOneWidget);

    // Cancel keeps it.
    await t.tap(find.text('BATAL'));
    await settle(t);
    expect(rig.repo.s.items.containsKey('d1'), isTrue);

    await t.tap(find.byTooltip('Hapus'));
    await settle(t);
    await t.tap(find.text('HAPUS'));
    await settle(t);
    expect(rig.repo.s.items.containsKey('d1'), isFalse);
    expect(find.text('stub-list'), findsOneWidget);
  });

  testWidgets('edit pushes the edit route', (t) async {
    final rig = DreamsRig(
      dreams: [dream()],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);
    await t.tap(find.byTooltip('Ubah'));
    await settle(t);
    expect(rig.visited, contains('/dreams/d1/edit'));
  });

  testWidgets('status chip opens the sheet and persists the change', (t) async {
    final rig = DreamsRig(
      dreams: [dream()],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig);

    await tapKey(t, 'dream-status-chip');
    await settle(t);
    await t.tap(find.byKey(const ValueKey('status-active')));
    await settle(t);

    expect(rig.repo.s.items['d1']!.status, DreamStatus.active);
    expect(rig.repo.s.items['d1']!.startedAt, isNotNull);
  });

  testWidgets('parent and children are tiles to their detail', (t) async {
    final rig = DreamsRig(
      dreams: [
        dream(),
        dream(id: 'p1'),
        dream(id: 'c1', parentId: 'd1'),
      ],
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    // Make d1 a child of p1.
    rig.repo.s.put(rig.repo.s.items['d1']!.copyWith(parentId: 'p1'));
    await pumpDetail(t, rig);

    expect(find.byKey(const ValueKey('dream-parent')), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-child-c1')), findsOneWidget);
    await tapKey(t, 'dream-child-c1');
    expect(find.text('Mimpi contoh c1'), findsWidgets);
  });

  testWidgets('a missing dream shows the empty state', (t) async {
    final rig = DreamsRig(
      online: FakeDreamOnlineRepository(failure: const NetworkFailure()),
    );
    await pumpDetail(t, rig, id: 'nope');
    expect(find.text('Mimpi ini nggak ketemu'), findsOneWidget);
  });
}
