import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/widgets/kantor_widget_summary.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 8);

  Map<String, dynamic> session(
    String sid,
    String status, {
    Map<String, dynamic>? waiting,
    Map<String, dynamic>? tool,
    String? name,
  }) => {
    'sid': sid,
    'status': status,
    'waiting': waiting,
    'tool': tool,
    'title': 'Judul $sid',
    if (name != null) 'look': {'name': name},
  };

  test('counts, ranking and routes', () {
    final state = {
      'offices': [
        {
          'id': 'kantor a',
          'name': 'Kantor A',
          'sessions': [
            session('s1', 'idle'),
            session(
              's2',
              'working',
              tool: {'name': 'Edit', 'label': 'a.dart'},
              name: 'Rani',
            ),
            session('s3', 'working', waiting: {'tool': 'Bash'}),
            session('s4', 'ended'),
          ],
        },
        {
          'id': 'b',
          'name': 'B',
          'sessions': [session('s5', 'idle')],
        },
      ],
    };
    final s = KantorWidgetSummary.fromState(state, now: now);
    expect((s.waiting, s.working, s.idle), (1, 1, 2));
    expect(s.agents.map((a) => a.route), [
      '/kantor/o/kantor%20a/s/s3',
      '/kantor/o/kantor%20a/s/s2',
      '/kantor/o/kantor%20a/s/s1',
    ]);
    expect(s.agents[0].waiting, isTrue);
    expect(s.agents[0].action, 'menunggu izin: Bash');
    expect(s.agents[1].name, 'Rani');
    expect(s.agents[1].action, 'Edit a.dart');
  });

  test('empty office', () {
    final s = KantorWidgetSummary.fromState({}, now: now);
    expect((s.waiting, s.working, s.idle), (0, 0, 0));
    expect(s.agents, isEmpty);
    final j = jsonDecode(s.encode()) as Map;
    expect(j['ok'], isTrue);
    expect(j['updatedAt'], now.millisecondsSinceEpoch);
  });

  test('offline keeps the last numbers but flags them', () {
    final last = KantorWidgetSummary.fromState({}, now: now).encode();
    final later = now.add(const Duration(minutes: 20));
    final j =
        jsonDecode(
              KantorWidgetSummary.encodeOffline(previous: last, now: later),
            )
            as Map;
    expect(j['ok'], isFalse);
    expect(j['updatedAt'], now.millisecondsSinceEpoch);
    expect(j['checkedAt'], later.millisecondsSinceEpoch);
    final cold =
        jsonDecode(
              KantorWidgetSummary.encodeOffline(previous: null, now: later),
            )
            as Map;
    expect(cold['ok'], isFalse);
    expect(cold.containsKey('updatedAt'), isFalse);
  });
}
