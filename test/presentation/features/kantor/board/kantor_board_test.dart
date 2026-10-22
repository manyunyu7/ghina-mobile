// Runs against a demo Kantor daemon (KANTOR_DEMO_URL / KANTOR_DEMO_TOKEN); skipped without it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_data.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_lib.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_card_detail.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_tab.dart';
import 'package:ghina/presentation/features/kantor/timeline/kantor_timeline_lib.dart';
import 'package:ghina/presentation/features/kantor/timeline/kantor_timeline_tab.dart';

void main() {
  test('pure logic: quick add, filter, spans', () {
    final q = kParseQuick(
      'Perbaiki login #bug @dina !p1',
      labels: const [KLabel(id: 'l1', name: 'bug', color: '#ff0000')],
      roles: const [(id: 'dina', name: 'Dina')],
    );
    expect(q.title, 'Perbaiki login');
    expect(q.labels, ['bug']);
    expect(q.who, 'dina');
    expect(q.prio, 'P1');

    final a = KCard.fromJson({
      'id': 'a',
      'title': 'Satu',
      'col': 2,
      'who': 'dina',
      'due': '2026-10-30',
      'start': '2026-10-26',
    });
    final b = KCard.fromJson({
      'id': 'b',
      'title': 'Dua',
      'col': 1,
      'deps': ['a'],
    });
    final map = {'a': a, 'b': b};
    expect(kMatchCard(a, const KFilter(unassigned: true), map: map), isFalse);
    expect(kMatchCard(b, const KFilter(waiting: true), map: map), isTrue);
    expect(
      kMatchCard(a, const KFilter(mine: true, me: 'dina'), map: map),
      isTrue,
    );
    expect(kMidOrd(1, 3), 2);

    final sp = ganttSpan(a)!;
    expect(sp.e - sp.s, 4);
    final spans = {
      'a': sp,
      'b': ganttSpan(b.copyWith(start: '2026-10-27', due: '2026-10-28')),
    };
    final bb = b.copyWith(start: '2026-10-27', due: '2026-10-28');
    expect(ganttConflicts([a, bb], spans), hasLength(1));
    expect(ganttPlanShift([a, bb], spans)['b'], greaterThan(0));
  });

  final url = Platform.environment['KANTOR_DEMO_URL'];
  final token = Platform.environment['KANTOR_DEMO_TOKEN'];
  if (url == null || token == null) return;

  Widget app(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: GhinaTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('board, detail and timeline build against a live daemon', (
    t,
  ) async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': url,
      'kantor.token': token,
    });
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    await t.pumpWidget(app(const KantorBoardTab(officeId: '168railway')));
    await settle(t);
    expect(find.text('Backlog'), findsWidgets);
    expect(find.byIcon(Icons.more_horiz_rounded), findsWidgets);
    expect(t.takeException(), isNull);

    // list view
    await t.tap(find.byIcon(Icons.view_list_rounded));
    await settle(t);
    expect(find.text('Siap'), findsWidgets);
    expect(t.takeException(), isNull);

    // detail
    final ctx = t.element(find.byType(KantorBoardTab));
    openKantorCard(ctx, officeId: '168railway', cardId: 'k19ff9a');
    await settle(t);
    expect(find.text('Kartu k19ff9a'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    await t.dragUntilVisible(
      find.text('RIWAYAT'),
      find.byType(ListView).last,
      const Offset(0, -400),
    );
    expect(find.text('RIWAYAT'), findsOneWidget);
    expect(t.takeException(), isNull);

    // timeline
    await t.pumpWidget(app(const KantorTimelineTab(officeId: '168railway')));
    await settle(t);
    expect(t.takeException(), isNull);

    // let the event socket's reconnect timers finish
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 40));
  });

  testWidgets(
    'phone width, create / move / edit / archive on the demo daemon',
    (t) async {
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({
        'kantor.url': url,
        'kantor.token': token,
      });
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);

      await t.pumpWidget(app(const KantorBoardTab(officeId: '168railway')));
      await settle(t);
      final c = ProviderScope.containerOf(
        t.element(find.byType(KantorBoardTab)),
      );
      final n = c.read(kantorBoardProvider('168railway').notifier);
      final api = c.read(kantorApiProvider)!;

      await t.runAsync(() async {
        final id = await n.create({
          'title': 'Kartu uji mobile',
          'col': 0,
          'labels': [],
          'prio': 'P1',
        });
        var card = Map<String, dynamic>.from(
          await api.get('/api/offices/168railway/cards/$id') as Map,
        );
        expect(card['title'], 'Kartu uji mobile');
        expect(card['prio'], 'P1');

        await n.place([id], 2);
        card = Map<String, dynamic>.from(
          await api.get('/api/offices/168railway/cards/$id') as Map,
        );
        expect(card['col'], 2);

        await n.patchCard(id, {
          'start': '2026-10-26',
          'due': '2026-10-30',
          'blocked': 'uji',
        });
        card = Map<String, dynamic>.from(
          await api.get('/api/offices/168railway/cards/$id') as Map,
        );
        expect(card['due'], '2026-10-30');
        expect(card['blocked'], 'uji');

        await api.post('/api/offices/168railway/cards/$id/check', {
          'text': 'butir uji',
        });
        await api.post('/api/offices/168railway/cards/$id/comment', {
          'text': 'komentar uji',
          'notify': false,
        });
        card = Map<String, dynamic>.from(
          await api.get('/api/offices/168railway/cards/$id') as Map,
        );
        expect((card['checklist'] as List), hasLength(1));
        expect((card['comments'] as List), hasLength(1));

        await n.archive(id);
        final board = c.read(kantorBoardProvider('168railway')).value!;
        expect(board.map.containsKey(id), isFalse);
      });
      await settle(t);
      expect(t.takeException(), isNull);

      // the timeline at phone width, with the new schedule gone again
      await t.pumpWidget(app(const KantorTimelineTab(officeId: '168railway')));
      await settle(t);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 40));
    },
  );
}
