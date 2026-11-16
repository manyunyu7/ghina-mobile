import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_two_pane.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_shell_page.dart';
import 'package:ghina/presentation/features/kantor/session/chat_context.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _offices = <String, Map<String, dynamic>>{
  'demo': {
    'id': 'demo',
    'name': 'Kantor Demo',
    'roles': [
      {'id': 'a', 'name': 'Ayu', 'title': 'Backend', 'model': 'opus'},
      {'id': 'b', 'name': 'Budi', 'title': 'QA', 'model': 'sonnet'},
    ],
    'sessions': [
      {'sid': 's1', 'role': 'a', 'status': 'working', 'tmux': 'x'},
      {'sid': 's2', 'role': 'b', 'status': 'idle', 'tmux': 'y'},
    ],
  },
  'lain': {
    'id': 'lain',
    'name': 'Kantor Lain',
    'roles': [
      {'id': 'c', 'name': 'Citra', 'title': 'Desain', 'model': 'opus'},
    ],
    'sessions': [
      {'sid': 's3', 'role': 'c', 'status': 'idle', 'tmux': 'z'},
    ],
  },
};

KantorOfficeFeed _feed(String id) => KantorOfficeFeed(id, null)
  ..loading = false
  ..office = _offices[id];

/// The real office page and session route, so taps, back, fold/unfold and the
/// office switcher run through go_router as in the app (no daemon: api null).
Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester t, {
  ChatStyle style = ChatStyle.bawaan,
}) async {
  final feeds = {for (final id in _offices.keys) id: _feed(id)};
  for (final f in feeds.values) {
    addTearDown(f.dispose);
  }
  final c = ProviderContainer(
    overrides: [
      kantorOfficeFeedProvider.overrideWith((ref, id) => feeds[id]!),
      kantorOfficeProvider.overrideWith((ref, id) async => _offices[id]!),
      kantorStateProvider.overrideWith(
        (ref) async => {'offices': _offices.values.toList(), 'inbox': []},
      ),
    ],
  );
  addTearDown(c.dispose);
  if (style != ChatStyle.bawaan) {
    c
        .read(chatViewPrefsProvider.notifier)
        .update((p) => p.copyWith(style: style));
  }
  final router = GoRouter(
    initialLocation: '/kantor/o/demo?tab=agen',
    routes: [
      GoRoute(
        path: '/kantor/o/:office',
        builder: (_, s) => KantorShellPage(
          officeId: s.pathParameters['office']!,
          tab: s.uri.queryParameters['tab'],
        ),
        routes: [
          GoRoute(
            path: 's/:sid',
            builder: (_, s) => KantorSessionPage(
              officeId: s.pathParameters['office']!,
              sid: s.pathParameters['sid']!,
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: GhinaTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await _settle(t);
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _size(WidgetTester t, double w, {double h = 900}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  await _settle(t);
}

Finder get _pageSession =>
    find.byWidgetPredicate((w) => w is KantorSessionPage && !w.embedded);
Finder get _paneSession =>
    find.byWidgetPredicate((w) => w is KantorSessionPage && w.embedded);

String _sidOf(WidgetTester t, Finder f) => t.widget<KantorSessionPage>(f).sid;

/// The chat field of the visible chat.
Finder get _field => find.byType(EditableText).last;

String _draftOf(ProviderContainer c, String office, String sid) =>
    c
        .read(kantorChatMemoryProvider)[(
          connection: '',
          office: office,
          sid: sid,
        )]
        ?.draft
        .text ??
    '';

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 7)); // let chat timers lapse
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('bubble width follows the setting but is capped at 560dp', () {
    expect(kantorBubbleMaxWidth(400, 0.8), closeTo(320, .001));
    expect(
      kantorBubbleMaxWidth(400, ChatBubbleWidth.wide.fraction),
      closeTo(384, .001),
    );
    expect(kantorBubbleMaxWidth(840, 0.8), 560);
    expect(kantorBubbleMaxWidth(1200, 1.0), 560);
  });

  testWidgets('400dp: one pane, tapping an agent pushes the session page', (
    t,
  ) async {
    addTearDown(t.view.reset);
    await _size(t, 400);
    final (router, _) = await _pump(t);
    expect(find.byType(KantorTwoPane), findsNothing);
    expect(find.byKey(const ValueKey('pane-office')), findsNothing);

    await t.tap(find.text('Ayu').first);
    await _settle(t);
    expect(_pageSession, findsOneWidget);
    expect(_paneSession, findsNothing);
    expect(_sidOf(t, _pageSession), 's1');

    // back returns to the list, nothing left selected
    router.pop();
    await _settle(t);
    expect(_pageSession, findsNothing);
    expect(find.text('Budi'), findsWidgets);
    await _close(t);
  });

  testWidgets('800dp: list left, chat right; tapping swaps the right pane', (
    t,
  ) async {
    addTearDown(t.view.reset);
    await _size(t, 800);
    final (router, _) = await _pump(t);
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(find.byKey(const ValueKey('pane-empty')), findsOneWidget);
    final left = t.getSize(
      find
          .ancestor(
            of: find.byKey(const ValueKey('pane-office')),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(left.width, inInclusiveRange(320, 360));

    await t.tap(find.text('Ayu').first);
    await _settle(t);
    expect(_pageSession, findsNothing); // no route pushed
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/kantor/o/demo',
    );
    expect(_sidOf(t, _paneSession), 's1');
    expect(find.byKey(const ValueKey('tile-open')), findsOneWidget);
    // embedded: no back button in the right pane
    expect(find.byType(BackButton), findsNothing);

    await t.tap(find.text('Budi').first);
    await _settle(t);
    expect(_sidOf(t, _paneSession), 's2');
    expect(find.byKey(const ValueKey('tile-open')), findsOneWidget);
    await _close(t);
  });

  testWidgets('draft and open chat survive 400 -> 800 -> 400', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 400);
    final (router, c) = await _pump(t);
    await t.tap(find.text('Ayu').first);
    await _settle(t);
    expect(_sidOf(t, _pageSession), 's1');
    await t.enterText(_field, 'draf saya');
    await t.pump();

    // unfold: the full page closes itself and the chat moves to the right pane
    await _size(t, 800);
    expect(_pageSession, findsNothing);
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(_sidOf(t, _paneSession), 's1');
    expect(find.text('draf saya'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/kantor/o/demo',
    );

    // fold again: the same chat opens as a full page, draft still there
    await _size(t, 400);
    expect(find.byType(KantorTwoPane), findsNothing);
    expect(_sidOf(t, _pageSession), 's1');
    expect(find.text('draf saya'), findsOneWidget);
    expect(_draftOf(c, 'demo', 's1'), 'draf saya');

    // back from the chat at 400dp: the list, and the chat is no longer open
    router.pop();
    await _settle(t);
    expect(_pageSession, findsNothing);
    await _size(t, 800);
    expect(find.byKey(const ValueKey('pane-empty')), findsOneWidget);
    expect(_draftOf(c, 'demo', 's1'), 'draf saya');
    await _close(t);
  });

  testWidgets('800 -> 400 -> 800 keeps the chat open (WhatsApp style)', (
    t,
  ) async {
    addTearDown(t.view.reset);
    await _size(t, 800);
    final (_, c) = await _pump(t, style: ChatStyle.whatsapp);
    await t.tap(find.byKey(const ValueKey('room-s2')));
    await _settle(t);
    expect(_sidOf(t, _paneSession), 's2');
    expect(find.byKey(const ValueKey('room-open-s2')), findsOneWidget);
    await t.enterText(_field, 'balasan WA');
    await t.pump();

    await _size(t, 400);
    expect(_sidOf(t, _pageSession), 's2');
    expect(find.text('balasan WA'), findsOneWidget);
    // narrow chat: one tap to the all-agents / all-offices switcher
    expect(find.byKey(const ValueKey('all-complex-agents')), findsOneWidget);

    await _size(t, 800);
    expect(_pageSession, findsNothing);
    expect(_sidOf(t, _paneSession), 's2');
    expect(find.text('balasan WA'), findsOneWidget);
    expect(_draftOf(c, 'demo', 's2'), 'balasan WA');
    await _close(t);
  });

  testWidgets('Telegram style also opens chats in the right pane', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 800);
    await _pump(t, style: ChatStyle.telegram);
    await t.tap(find.byKey(const ValueKey('room-s1')));
    await _settle(t);
    expect(_pageSession, findsNothing);
    expect(_sidOf(t, _paneSession), 's1');
    expect(find.byKey(const ValueKey('room-open-s1')), findsOneWidget);
    await _close(t);
  });

  testWidgets(
    'switching office from the left header keeps the open chat and draft',
    (t) async {
      addTearDown(t.view.reset);
      await _size(t, 800);
      final (router, c) = await _pump(t);
      final header = find.byKey(const ValueKey('pane-office'));
      expect(
        find.descendant(of: header, matching: find.text('Kantor Demo')),
        findsOneWidget,
      );
      await t.tap(find.text('Ayu').first);
      await _settle(t);
      await t.enterText(_field, 'draf kantor demo');
      await t.pump();

      // one tap on the header opens the existing office switcher
      await t.tap(header);
      await _settle(t);
      expect(find.text('Pindah kantor'), findsOneWidget);
      await t.tap(find.text('Kantor Lain').last);
      await _settle(t);

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/kantor/o/lain',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pane-office')),
          matching: find.text('Kantor Lain'),
        ),
        findsOneWidget,
      );
      // left list follows the new office, right pane keeps the old chat
      expect(find.text('Citra'), findsWidgets);
      expect(find.text('Budi'), findsNothing);
      final pane = t.widget<KantorSessionPage>(_paneSession);
      expect((pane.officeId, pane.sid), ('demo', 's1'));
      expect(find.text('draf kantor demo'), findsOneWidget);
      // the old office's agent is not highlighted in the new list
      expect(find.byKey(const ValueKey('tile-open')), findsNothing);

      // picking an agent of the new office replaces the right pane
      await t.tap(find.text('Citra').first);
      await _settle(t);
      final next = t.widget<KantorSessionPage>(_paneSession);
      expect((next.officeId, next.sid), ('lain', 's3'));
      expect(find.byKey(const ValueKey('tile-open')), findsOneWidget);
      expect(_draftOf(c, 'demo', 's1'), 'draf kantor demo');
      await _close(t);
    },
  );
}
