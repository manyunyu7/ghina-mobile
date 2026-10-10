// Shared harness of the Mimpi widget tests: the real providers and use cases on
// in-memory repositories, a fixed clock and a router whose stubs record where a
// tap went. Invented data only ("Trip contoh ke Kota Sample").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../di/dreams_test_overrides.dart';
import '../../../domain/dreams_fakes.dart';

final dreamsNow = DateTime(2026, 10, 10, 12);

class DreamsSync implements SyncService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {}
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

Dream dreamFixture(
  String id, {
  String title = 'Mimpi contoh',
  String? emoji,
  String category = 'other',
  DreamStatus status = DreamStatus.idea,
  int? priority,
  String? targetDate,
  TargetPrecision precision = TargetPrecision.day,
  List<String> tags = const [],
  double? costEstimate,
  DateTime? updated,
}) => Dream(
  id: id,
  title: title,
  emoji: emoji,
  category: category,
  status: status,
  priority: priority,
  targetDate: targetDate,
  targetPrecision: precision,
  tags: tags,
  costEstimate: costEstimate,
  createdAt: dreamsNow,
  updatedAt: updated ?? dreamsNow,
);

DreamCategory categoryFixture(String key, String label, String emoji) =>
    DreamCategory(
      id: 'dc-$key',
      key: key,
      label: label,
      emoji: emoji,
      createdAt: dreamsNow,
      updatedAt: dreamsNow,
    );

class DreamsRig {
  DreamsRig({
    List<Dream>? dreams,
    List<DreamStep>? steps,
    List<DreamMetric>? metrics,
    List<DreamCategory>? categories,
    List<DreamFieldDef>? fields,
    this.online,
  }) {
    final st = FakeDreamStepRepository();
    final mt = FakeDreamMetricRepository();
    this.steps = st;
    this.metrics = mt;
    repo = FakeDreamRepository(steps: st, metrics: mt);
    cats = FakeDreamCategoryRepository();
    defs = FakeDreamFieldRepository();
    for (final d in dreams ?? const <Dream>[]) {
      repo.s.put(d);
    }
    for (final s in steps ?? const <DreamStep>[]) {
      st.s.put(s);
    }
    for (final m in metrics ?? const <DreamMetric>[]) {
      mt.s.put(m);
    }
    for (final c in categories ?? const <DreamCategory>[]) {
      cats.s.put(c);
    }
    for (final f in fields ?? const <DreamFieldDef>[]) {
      defs.s.put(f);
    }
  }

  late final FakeDreamRepository repo;
  late final FakeDreamStepRepository steps;
  late final FakeDreamMetricRepository metrics;
  late final FakeDreamCategoryRepository cats;
  late final FakeDreamFieldRepository defs;
  final FakeDreamOnlineRepository? online;

  /// Paths the stub routes received (`/dreams/d1`, `/dreams/review`, …).
  final visited = <String>[];

  List<Override> get overrides => [
    clockProvider.overrideWithValue(FixedClock(dreamsNow)),
    tickSourceProvider.overrideWithValue(() => Stream.value(dreamsNow)),
    syncServiceProvider.overrideWithValue(DreamsSync()),
    currentUserProvider.overrideWithValue(null),
    ...dreamsFakeOverrides(
      dreams: repo,
      steps: steps,
      metrics: metrics,
      categories: cats,
      fields: defs,
      online: online,
    ),
  ];

  /// The feature routes; the ones a test does not build are stubs.
  GoRouter router(String location, Widget Function() list) => GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/dreams', builder: (_, _) => list()),
      GoRoute(
        path: '/dreams/new',
        builder: (_, s) {
          visited.add(s.uri.toString());
          return const Scaffold(body: Text('stub-new'));
        },
      ),
      GoRoute(
        path: '/dreams/review',
        builder: (_, s) {
          visited.add(s.uri.toString());
          return const Scaffold(body: Text('stub-review'));
        },
      ),
      GoRoute(
        path: '/dreams/manage',
        builder: (_, s) {
          visited.add(s.uri.toString());
          return const Scaffold(body: Text('stub-manage'));
        },
      ),
      GoRoute(
        path: '/dreams/:id',
        builder: (_, s) {
          visited.add(s.uri.toString());
          return Scaffold(body: Text('stub-detail-${s.pathParameters['id']}'));
        },
      ),
    ],
  );

  Future<void> pump(
    WidgetTester t,
    String location,
    Widget Function() page,
  ) async {
    t.view.physicalSize = const Size(1080, 5200);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: ThemeMode.light,
          routerConfig: router(location, page),
        ),
      ),
    );
    await settle(t);
  }
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key), skipOffstage: false);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text, skipOffstage: false);
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await settle(t);
}
