import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('agent switcher groups agents and opens a session', (t) async {
    t.view.physicalSize = const Size(400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final feed = KantorOfficeFeed('o', null)
      ..loading = false
      ..office = {
        'roles': [
          {'id': 'r1', 'name': 'Rina', 'title': 'Dev'},
          {'id': 'r2', 'name': 'Tono', 'title': 'QA'},
          {'id': 'r3', 'name': 'Sari', 'title': 'Ops'},
        ],
        'sessions': [
          {'sid': 's1', 'role': 'r1', 'status': 'working', 'tool': null},
          {
            'sid': 's2',
            'role': 'r2',
            'status': 'waiting',
            'waiting': {'tool': 'Bash', 'summary': 'ls'},
          },
        ],
      };
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showKantorAgentSwitcher(
                  c,
                  officeId: 'o',
                  currentSid: 's1',
                  tab: 'agen',
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/kantor/o/:o/s/:sid',
          builder: (_, _) => const Text('sesi'),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [kantorOfficeFeedProvider.overrideWith((ref, id) => feed)],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah agen'), findsOneWidget);
    expect(find.text('MENUNGGU KAMU  1'), findsOneWidget);
    expect(find.text('LIBUR  1'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.tap(find.textContaining('Tono'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(router.state.uri.toString(), '/kantor/o/o/s/s2?tab=agen');
  });
}
