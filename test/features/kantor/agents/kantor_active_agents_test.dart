import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_active_agents.dart';

Map<String, dynamic> _s(String sid, Map<String, dynamic> extra) => {
  'sid': sid,
  'status': 'idle',
  'title': sid,
  'room': 'app',
  'lastSeen': DateTime.now().toIso8601String(),
  'model': 'opus',
  'engine': 'claude',
  ...extra,
};

final _state = <String, dynamic>{
  'offices': [
    {
      'id': 'a',
      'name': 'Kantor A',
      'sessions': [
        _s('idle1', {'title': 'Catatan'}),
        _s('work1', {
          'title': 'Perbaiki login',
          'status': 'working',
          'tool': {'name': 'Edit', 'label': 'auth.dart'},
          'bgAgents': 2,
        }),
        _s('gone', {'status': 'ended'}),
      ],
    },
    {
      'id': 'b',
      'name': 'Kantor B',
      'sessions': [
        _s('wait1', {
          'title': 'Review PR',
          'status': 'waiting',
          'waiting': {'tool': 'Bash', 'summary': 'flutter test'},
        }),
        _s('cx1', {
          'title': 'Riset saham',
          'engine': 'codex',
          'model': 'gpt-5',
          'status': 'working',
        }),
      ],
    },
  ],
};

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: child),
  ),
);

void main() {
  test('orders waiting, working, idle and drops ended', () {
    final l = kantorActiveAgents(_state);
    expect(l.map((a) => a.sid).first, 'wait1');
    expect(l.map((a) => a.sid).toSet(), {'wait1', 'work1', 'cx1', 'idle1'});
    expect(l.last.sid, 'idle1');
    expect(l.firstWhere((a) => a.sid == 'cx1').codex, isTrue);
    expect(l.firstWhere((a) => a.sid == 'work1').subs, 2);
  });

  testWidgets('list groups, filters and opens chat or terminal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    var query = '';
    late StateSetter set;
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return KantorActiveAgentsList(
              state: _state,
              query: query,
              onOpen: (a, tab) => opened.add('${a.sid}:${tab ?? 'chat'}'),
            );
          },
        ),
      ),
    );
    expect(find.text('MENUNGGU KAMU  1'), findsOneWidget);
    expect(find.text('BEKERJA  2'), findsOneWidget);
    expect(find.text('IDLE  1'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.textContaining('minta izin: flutter test'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-work1')));
    expect(opened.last, 'work1:chat');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('agent-work1')),
        matching: find.byTooltip('Terminal'),
      ),
    );
    expect(opened.last, 'work1:terminal');

    set(() => query = 'codex');
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-cx1')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-work1')), findsNothing);

    set(() => query = '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-idle1')));
    await tester.pump();
    expect(find.text('DISEMATKAN  1'), findsOneWidget);
  });

  testWidgets('strip shows waiting badge and opens via See all', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(KantorActiveAgentsStrip(state: _state)));
    expect(find.text('AGEN AKTIF  4'), findsOneWidget);
    expect(find.text('1 menunggu'), findsOneWidget);
    expect(find.text('Lihat semua'), findsOneWidget);
    expect(find.byKey(const ValueKey('strip-wait1')), findsOneWidget);
  });

  testWidgets('strip hides without agents', (tester) async {
    await tester.pumpWidget(
      _wrap(const KantorActiveAgentsStrip(state: {'offices': []})),
    );
    expect(find.byKey(const ValueKey('kantor-active-agents')), findsNothing);
  });
}
