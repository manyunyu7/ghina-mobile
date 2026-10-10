import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/dreams/dream_form_page.dart';
import 'package:go_router/go_router.dart';

import 'dreams_test_rig.dart';

Future<void> pumpForm(WidgetTester t, DreamsRig rig, String location) async {
  t.view.physicalSize = const Size(1080, 5200);
  t.view.devicePixelRatio = 2.6;
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/dreams',
        builder: (_, s) {
          rig.visited.add(s.uri.toString());
          return const Scaffold(body: Text('stub-list'));
        },
      ),
      GoRoute(path: '/dreams/new', builder: (_, _) => const DreamFormPage()),
      GoRoute(
        path: '/dreams/:id/edit',
        builder: (_, s) => DreamFormPage(id: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/dreams/:id',
        builder: (_, s) {
          rig.visited.add(s.uri.toString());
          return Scaffold(body: Text('stub-detail-${s.pathParameters['id']}'));
        },
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: rig.overrides,
      child: MaterialApp.router(
        theme: GhinaTheme.light(),
        darkTheme: GhinaTheme.dark(),
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    ),
  );
  await settle(t);
}

Finder fieldOf(String key) => find.descendant(
  of: find.byKey(ValueKey(key), skipOffstage: false),
  matching: find.byType(TextField, skipOffstage: false),
);

Future<void> typeIn(WidgetTester t, String key, String text) async {
  final f = fieldOf(key);
  await t.ensureVisible(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

Future<void> openSheet(WidgetTester t, String key) async {
  await tapKey(t, key);
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> save(WidgetTester t) => tapKey(t, 'dream-save');

DreamFieldDef textDef(String key, String label, {List<String>? appliesTo}) =>
    DreamFieldDef(
      id: 'f-$key',
      key: key,
      label: label,
      appliesTo: appliesTo,
      createdAt: dreamsNow,
      updatedAt: dreamsNow,
    );

void main() {
  testWidgets('an empty title is an inline error and writes nothing', (
    t,
  ) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await save(t);

    expect(find.text('Judulnya diisi dulu ya'), findsOneWidget);
    expect(rig.repo.s.items, isEmpty);
    expect(find.text('stub-list'), findsNothing);
  });

  testWidgets('a cost that is not a number is an inline error', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await typeIn(t, 'dream-costEstimate', 'banyak');
    await save(t);

    expect(find.text('Estimasi biaya harus berupa angka'), findsOneWidget);
    expect(rig.repo.s.items, isEmpty);
  });

  testWidgets('a cost in Indonesian style is stored as a number', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await typeIn(t, 'dream-costEstimate', '15.000.000');
    await save(t);

    expect(rig.repo.s.items.values.single.costEstimate, 15000000);
  });

  testWidgets('a quarter target is stored at the quarter end', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Trip contoh ke Kota Sample');
    final chips = find.byKey(const ValueKey('dream-target-precision'));
    await t.ensureVisible(chips);
    await t.pump();
    await t.tap(find.descendant(of: chips, matching: find.text('Kuartal')));
    await settle(t);
    await openSheet(t, 'dream-target-picker');
    await tapKey(t, 'period-q1');
    expect(find.text('Q1 2026'), findsWidgets);

    await save(t);

    final d = rig.repo.s.items.values.single;
    expect(d.title, 'Trip contoh ke Kota Sample');
    expect(d.targetPrecision, TargetPrecision.quarter);
    expect(d.targetDate, '2026-03-31');
    expect(rig.visited, contains('/dreams'));
  });

  testWidgets('typed text sets the target and the precision', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await typeIn(t, 'dream-target-text', 'Maret 2027');
    await save(t);

    final d = rig.repo.s.items.values.single;
    expect(d.targetPrecision, TargetPrecision.month);
    expect(d.targetDate, '2027-03-31');
  });

  testWidgets('text that is not understood is an error and blocks the save', (
    t,
  ) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await typeIn(t, 'dream-target-text', 'besok lusa');
    expect(find.text('Tidak dimengerti'), findsOneWidget);
    await save(t);

    expect(rig.repo.s.items, isEmpty);
    expect(find.text('Tidak dimengerti'), findsOneWidget);
  });

  testWidgets('creating a dream with a step saves both', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Trip contoh ke Kota Sample');
    await openSheet(t, 'add-step');
    await t.enterText(fieldOf('step-title'), 'Tentukan tanggal');
    await t.pump();
    await tapKey(t, 'step-sheet-save');
    expect(find.text('Tentukan tanggal', skipOffstage: false), findsOneWidget);

    await save(t);

    final dream = rig.repo.s.items.values.single;
    final step = rig.steps.s.items.values.single;
    expect(step.dreamId, dream.id);
    expect(step.title, 'Tentukan tanggal');
    expect(rig.visited, contains('/dreams'));
  });

  testWidgets('a step without a title shows the error in the sheet', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await openSheet(t, 'add-step');
    await tapKey(t, 'step-sheet-save');

    expect(find.text('Judul langkah wajib diisi'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-sheet-save')), findsOneWidget);
  });

  testWidgets('creating a dream with a manual metric saves it', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await openSheet(t, 'add-metric');
    await t.enterText(fieldOf('metric-label'), 'Tabungan contoh');
    await t.pump();
    await t.enterText(fieldOf('metric-target'), '5000000');
    await t.pump();
    await tapKey(t, 'metric-sheet-save');

    await save(t);

    final dream = rig.repo.s.items.values.single;
    final metric = rig.metrics.s.items.values.single;
    expect(metric.dreamId, dream.id);
    expect(metric.source, MetricSource.manual);
    expect(metric.targetValue, 5000000);
  });

  testWidgets('editing loads the dream and saves the change', (t) async {
    final rig = DreamsRig(
      dreams: [
        dreamFixture(
          'd1',
          title: 'Mimpi contoh',
          targetDate: '2027-03-31',
          precision: TargetPrecision.quarter,
        ),
      ],
    );
    await pumpForm(t, rig, '/dreams/d1/edit');

    expect(find.text('Mimpi contoh'), findsOneWidget);
    expect(find.text('Q1 2027'), findsWidgets);

    await typeIn(t, 'dream-title', 'Mimpi contoh yang baru');
    await save(t);

    final d = rig.repo.s.items['d1']!;
    expect(d.title, 'Mimpi contoh yang baru');
    expect(d.targetPrecision, TargetPrecision.quarter);
    expect(d.targetDate, '2027-03-31');
    expect(rig.repo.s.items, hasLength(1));
    expect(rig.visited, contains('/dreams/d1'));
  });

  testWidgets('clearing the target stores none', (t) async {
    final rig = DreamsRig(
      dreams: [dreamFixture('d1', targetDate: '2027-03-31')],
    );
    await pumpForm(t, rig, '/dreams/d1/edit');

    await tapKey(t, 'dream-target-clear');
    await save(t);

    expect(rig.repo.s.items['d1']!.targetDate, isNull);
  });

  testWidgets('a missing dream shows an empty state', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/nope/edit');

    expect(find.text('Mimpi ini nggak ketemu'), findsOneWidget);
    expect(find.byKey(const ValueKey('dream-save')), findsNothing);
  });

  testWidgets('editing keeps existing steps and removes a deleted one', (
    t,
  ) async {
    final rig = DreamsRig(
      dreams: [dreamFixture('d1')],
      steps: [
        DreamStep(
          id: 's1',
          dreamId: 'd1',
          title: 'Langkah contoh satu',
          createdAt: dreamsNow,
          updatedAt: dreamsNow,
        ),
        DreamStep(
          id: 's2',
          dreamId: 'd1',
          title: 'Langkah contoh dua',
          sortOrder: 1,
          createdAt: dreamsNow,
          updatedAt: dreamsNow,
        ),
      ],
    );
    await pumpForm(t, rig, '/dreams/d1/edit');

    await openSheet(t, 'step-tile-0');
    await tapKey(t, 'step-sheet-delete');
    await save(t);

    expect(rig.steps.s.items.keys, ['s2']);
  });

  testWidgets('a custom field of the category is stored in fields', (t) async {
    final rig = DreamsRig(
      categories: [categoryFixture('travel', 'Perjalanan', '✈️')],
      fields: [
        textDef('kota', 'Kota tujuan', appliesTo: ['travel']),
      ],
    );
    await pumpForm(t, rig, '/dreams/new');

    expect(
      find.byKey(const ValueKey('field-kota'), skipOffstage: false),
      findsNothing,
    );

    await tapText(t, '✈️ Perjalanan');
    expect(
      find.byKey(const ValueKey('field-kota'), skipOffstage: false),
      findsOneWidget,
    );
    await typeIn(t, 'dream-title', 'Trip contoh ke Kota Sample');
    await typeIn(t, 'field-kota', 'Kota Sample');
    await save(t);

    final d = rig.repo.s.items.values.single;
    expect(d.category, 'travel');
    expect(d.fields, {'kota': 'Kota Sample'});
  });

  testWidgets('a field of another category is not shown or stored', (t) async {
    final rig = DreamsRig(
      categories: [categoryFixture('travel', 'Perjalanan', '✈️')],
      fields: [
        textDef('kota', 'Kota tujuan', appliesTo: ['travel']),
      ],
    );
    await pumpForm(t, rig, '/dreams/new');

    await tapText(t, '✈️ Perjalanan');
    await typeIn(t, 'field-kota', 'Kota Sample');
    await tapText(t, '✨ Lainnya');
    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await save(t);

    expect(rig.repo.s.items.values.single.fields, isEmpty);
  });

  testWidgets(
    'tags: Enter adds, duplicates are ignored, the typed one counts',
    (t) async {
      final rig = DreamsRig();
      await pumpForm(t, rig, '/dreams/new');

      await typeIn(t, 'dream-title', 'Mimpi contoh');
      await typeIn(t, 'dream-tag', 'liburan');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await typeIn(t, 'dream-tag', 'Liburan');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await typeIn(t, 'dream-tag', 'hemat');
      await save(t);

      expect(rig.repo.s.items.values.single.tags, ['liburan', 'hemat']);
    },
  );

  testWidgets('manual progress is stored and can go back to automatic', (
    t,
  ) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await tapKey(t, 'dream-progress-manual');
    expect(find.text('50%'), findsWidgets);
    await save(t);
    expect(rig.repo.s.items.values.single.progressManual, 50);

    final rig2 = DreamsRig(
      dreams: [dreamFixture('d2').copyWith(progressManual: 30)],
    );
    await pumpForm(t, rig2, '/dreams/d2/edit');
    await tapKey(t, 'dream-progress-auto');
    await save(t);
    expect(rig2.repo.s.items['d2']!.progressManual, isNull);
  });

  testWidgets('a rule from the use case shows next to its field', (t) async {
    final rig = DreamsRig();
    await pumpForm(t, rig, '/dreams/new');

    await typeIn(t, 'dream-title', 'Mimpi contoh');
    await typeIn(t, 'dream-costEstimate', '-5000');
    await save(t);

    expect(find.text('Estimasi biaya tidak boleh negatif'), findsWidgets);
    expect(rig.repo.s.items, isEmpty);
  });

  testWidgets('a category that no longer exists is reported on category', (
    t,
  ) async {
    final rig = DreamsRig(dreams: [dreamFixture('d1', category: 'ghost')]);
    await pumpForm(t, rig, '/dreams/d1/edit');

    await save(t);

    // The inline text under the chips, and the toast.
    expect(
      find.text('Kategori "ghost" belum ada', skipOffstage: false),
      findsNWidgets(2),
    );
    expect(find.text('stub-detail-d1'), findsNothing);
  });
}
