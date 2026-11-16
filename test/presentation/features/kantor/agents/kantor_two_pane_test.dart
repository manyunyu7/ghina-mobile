import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_two_pane.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';

KantorOfficeFeed _feed() => KantorOfficeFeed('demo', null)
  ..loading = false
  ..office = {
    'id': 'demo',
    'roles': [
      {'id': 'a', 'name': 'Ayu', 'title': 'Backend', 'model': 'opus'},
      {'id': 'b', 'name': 'Budi', 'title': 'QA', 'model': 'sonnet'},
    ],
    'sessions': [
      {'sid': 's1', 'role': 'a', 'status': 'working', 'tmux': 'x'},
      {'sid': 's2', 'role': 'b', 'status': 'idle', 'tmux': 'y'},
    ],
  };

Future<void> _pump(WidgetTester t, KantorOfficeFeed feed) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [kantorOfficeFeedProvider.overrideWith((ref, id) => feed)],
      child: MaterialApp(
        theme: GhinaTheme.light(),
        home: const Scaffold(body: KantorAgentsTab(officeId: 'demo')),
      ),
    ),
  );
  await t.pump();
}

void _size(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('bubble width is capped at 560dp', () {
    expect(kantorBubbleMaxWidth(400, 0.8), closeTo(320, .001));
    expect(kantorBubbleMaxWidth(840, 0.8), 560);
    expect(kantorBubbleMaxWidth(1200, 1.0), 560);
  });

  testWidgets('400dp stays single pane', (t) async {
    _size(t, 400, 800);
    addTearDown(t.view.reset);
    await _pump(t, _feed());
    expect(find.byType(KantorTwoPane), findsNothing);
    expect(find.text('Pilih agen di sebelah kiri'), findsNothing);
  });

  testWidgets('800dp shows list and detail; tapping swaps the right pane', (
    t,
  ) async {
    _size(t, 800, 900);
    addTearDown(t.view.reset);
    await _pump(t, _feed());
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(find.text('Pilih agen di sebelah kiri'), findsOneWidget);

    await t.tap(find.text('Ayu').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(KantorSessionPage), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-open')), findsOneWidget);
    final first = t.widget<KantorSessionPage>(find.byType(KantorSessionPage));
    expect(first.sid, 's1');
    expect(first.embedded, isTrue);

    await t.tap(find.text('Budi').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(
      t.widget<KantorSessionPage>(find.byType(KantorSessionPage)).sid,
      's2',
    );
  });

  testWidgets('selection and draft survive fold and unfold', (t) async {
    _size(t, 800, 900);
    addTearDown(t.view.reset);
    await _pump(t, _feed());
    await t.tap(find.text('Ayu').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    await t.enterText(find.byType(TextField).last, 'draf saya');
    await t.pump();

    // fold: 400dp, single pane
    _size(t, 400, 900);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(KantorTwoPane), findsNothing);
    expect(find.byType(KantorSessionPage), findsNothing);

    // unfold: same session and same draft
    _size(t, 800, 900);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(
      t.widget<KantorSessionPage>(find.byType(KantorSessionPage)).sid,
      's1',
    );
    expect(find.text('draf saya'), findsOneWidget);
  });
}
