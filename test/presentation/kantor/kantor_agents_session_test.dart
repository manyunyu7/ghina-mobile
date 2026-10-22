import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/session/chat_model.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/permission_card.dart';

KantorOfficeFeed _feed() {
  final f = KantorOfficeFeed('demo', null)
    ..loading = false
    ..office = {
      'id': 'demo',
      'plan': {
        'rooms': [
          {'id': 'r1', 'name': 'Ruang Kode'},
        ],
      },
      'roles': [
        {
          'id': 'a',
          'name': 'Ayu',
          'title': 'Backend',
          'room': 'r1',
          'model': 'opus',
        },
        {
          'id': 'b',
          'name': 'Budi',
          'title': 'QA',
          'room': 'r1',
          'model': 'sonnet',
        },
        {
          'id': 'c',
          'name': 'Cici',
          'title': 'Frontend',
          'room': 'r1',
          'model': 'haiku',
        },
        {
          'id': 'd',
          'name': 'Dewi',
          'title': 'Libur',
          'room': 'r1',
          'model': 'haiku',
        },
      ],
      'sessions': [
        {
          'sid': 's1',
          'role': 'a',
          'status': 'working',
          'tool': {'name': 'Edit', 'label': 'x.dart'},
          'room': 'r1',
        },
        {
          'sid': 's2',
          'role': 'b',
          'status': 'idle',
          'room': 'r1',
          'lastSeen': DateTime.now().toIso8601String(),
        },
        {
          'sid': 's3',
          'role': 'c',
          'status': 'waiting',
          'room': 'r1',
          'waiting': {'tool': 'Bash', 'summary': 'rm -rf build'},
        },
      ],
    }
    ..inbox = [
      {
        'id': 'i1',
        'sid': 's3',
        'office': 'demo',
        'tool': 'Bash',
        'summary': 'rm -rf build',
        'held': true,
        'who': 'Cici',
      },
    ];
  return f;
}

void main() {
  test('buildChat pairs results with calls and groups tools', () {
    final out = buildChat([
      {'k': 'user', 's': 'halo', 'at': '2026-10-21T10:00:00Z'},
      {'k': 'tool', 's': 'Read a.dart', 'at': 'x'},
      {'k': 'tool', 's': 'Bash ls', 'at': 'y'},
      {'k': 'result', 's': 'ok', 'err': false},
      {'k': 'result', 's': 'boom', 'err': true},
      {'k': 'text', 's': 'selesai', 'at': 'z'},
    ]);
    expect(out, hasLength(3));
    final tools = out[1] as ToolsEntry;
    expect(tools.calls.map((c) => c.shortName), ['Read', 'Bash']);
    expect(tools.calls[0].failed, isFalse);
    expect(tools.calls[1].failed, isTrue);
  });

  test('parseAsk reads full and truncated summaries', () {
    final full = parseAsk(
      '{"questions":[{"question":"Pilih?","options":[{"label":"A"},{"label":"B","description":"d"}]}]}',
    );
    expect(full.tappable, isTrue);
    expect(full.questions.single.options.map((o) => o.label), ['A', 'B']);
    final cut = parseAsk(
      '{"questions":[{"question":"Pilih?","options":[{"label":"A"},{"label":"B"',
    );
    expect(cut.partial, isTrue);
    expect(cut.questions.single.options.map((o) => o.label), ['A', 'B']);
  });

  testWidgets('agents tab groups waiting, working, idle and off shift', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final feed = _feed();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kantorOfficeFeedProvider('demo').overrideWithValue(feed)],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: KantorAgentsTab(officeId: 'demo')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('MENUNGGU KAMU'), findsOneWidget);
    expect(find.text('BEKERJA'), findsOneWidget);
    expect(find.text('IDLE'), findsOneWidget);
    expect(find.text('LIBUR'), findsOneWidget);
    expect(find.text('Izinkan'.toUpperCase()), findsOneWidget);
    expect(find.text('Edit x.dart'), findsOneWidget);
  });
}
