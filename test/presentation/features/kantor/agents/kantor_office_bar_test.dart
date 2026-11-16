import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_office_bar.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_two_pane.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_shell_page.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
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
    'fav': true,
    'roles': [
      {'id': 'c', 'name': 'Citra', 'title': 'Desain', 'model': 'opus'},
    ],
    'sessions': [
      {'sid': 's3', 'role': 'c', 'status': 'idle', 'tmux': 'z'},
    ],
  },
  'tiga': {
    'id': 'tiga',
    'name': 'Kantor Tiga',
    'roles': [
      {'id': 'd', 'name': 'Dewi', 'title': 'Data', 'model': 'opus'},
    ],
    'sessions': [],
  },
};

/// Office feeds created so far (the bar prefetches the chip offices).
final _built = <String>{};

KantorOfficeFeed _feed(String id) => KantorOfficeFeed(id, null)
  ..loading = false
  ..office = _offices[id];

/// The real office page and session route, so taps, back, fold/unfold and the
/// office switcher run through go_router as in the app (no daemon: api null).
Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester t, {
  ChatStyle style = ChatStyle.bawaan,
  String initial = '/kantor/o/demo?tab=agen',
}) async {
  final feeds = {for (final id in _offices.keys) id: _feed(id)};
  for (final f in feeds.values) {
    addTearDown(f.dispose);
  }
  final c = ProviderContainer(
    overrides: [
      kantorOfficeFeedProvider.overrideWith((ref, id) {
        _built.add(id);
        return feeds[id]!;
      }),
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
    initialLocation: initial,
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

Finder get _paneSession =>
    find.byWidgetPredicate((w) => w is KantorSessionPage && w.embedded);

String _sidOf(WidgetTester t, Finder f) => t.widget<KantorSessionPage>(f).sid;

/// The session content shown by the session route (full page or right pane).
Finder _view({required bool embedded}) => find.byWidgetPredicate(
  (w) => w is KantorSessionView && w.embedded == embedded,
);
Finder get _sessionTwoPane => find.byKey(const ValueKey('session-two-pane'));

/// Every chat in the tree, also those under a covered route.
Finder get _allChats => find.byType(KantorChatTab, skipOffstage: false);

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 7)); // let chat timers lapse
}

Finder get _bar => find.byKey(const ValueKey('kantor-office-bar'));
Finder _chip(String id) => find.byKey(ValueKey('office-chip-$id'));

bool _chipSelected(WidgetTester t, String id) => t
    .widget<ChunkyChip>(
      find.byKey(ValueKey('office-chip-$id'), skipOffstage: false),
    )
    .selected;

void _expectApart(WidgetTester t, Finder a, Finder b) {
  final ra = t.getRect(a);
  final rb = t.getRect(b);
  expect(ra.overlaps(rb), isFalse, reason: '$ra overlaps $rb');
  expect(ra.bottom, lessThanOrEqualTo(rb.top));
}

Finder get _newAgent => find.widgetWithText(FloatingActionButton, 'Agen baru');

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    _built.clear();
  });

  test('chips: favourites, then offices with live agents, current always', () {
    final offices = [
      {'id': 'a', 'name': 'A', 'sessions': []},
      {
        'id': 'b',
        'name': 'B',
        'sessions': [
          {'status': 'working'},
        ],
      },
      {'id': 'c', 'name': 'C', 'fav': true, 'sessions': []},
      {
        'id': 'd',
        'name': 'D',
        'sessions': [
          {'status': 'ended'},
        ],
      },
      {
        'id': 'e',
        'name': 'E',
        'sessions': [
          {'status': 'idle'},
          {'status': 'working'},
        ],
      },
    ];
    List<String> ids(String cur) => [
      for (final o in kantorBarOffices(offices, cur)) '${o['id']}',
    ];
    expect(ids('c'), ['c', 'e', 'b']);
    expect(ids('a'), ['a', 'c', 'e', 'b']);
  });

  testWidgets('400dp: bar at the bottom, chip switches office, '
      '"Agen baru" stays above it', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 400);
    final (router, _) = await _pump(t);
    expect(_bar, findsOneWidget);
    expect(_chipSelected(t, 'demo'), isTrue);
    expect(_chipSelected(t, 'lain'), isFalse);
    expect(_chip('tiga'), findsNothing); // not fav, nobody working
    expect(_chip('all'), findsOneWidget);
    // thumb reach: the bar is at the bottom of the screen
    expect(t.getRect(_bar).bottom, 900);
    expect(t.getSize(_bar).height, inInclusiveRange(52, 56));
    expect(t.getSize(_chip('lain')).height, greaterThanOrEqualTo(44));
    _expectApart(t, _newAgent, _bar);
    // the chip offices are loaded ahead
    expect(_built, contains('lain'));

    await t.tap(_chip('lain'));
    await _settle(t);
    expect(_path(router), '/kantor/o/lain');
    expect(router.state.uri.queryParameters['tab'], 'agen');
    expect(find.text('Citra'), findsWidgets);
    expect(find.text('Budi'), findsNothing);
    expect(_chipSelected(t, 'lain'), isTrue);
    expect(_chipSelected(t, 'demo'), isFalse);
    await _close(t);
  });

  testWidgets('400dp messenger styles: bar shows, new-chat button above it', (
    t,
  ) async {
    addTearDown(t.view.reset);
    await _size(t, 400);
    for (final style in [ChatStyle.telegram, ChatStyle.whatsapp]) {
      await _pump(t, style: style);
      expect(_bar, findsOneWidget);
      _expectApart(t, find.byKey(const ValueKey('room-new-chat')), _bar);
      await _close(t);
    }
  });

  testWidgets('"Semua…" opens the office sheet, search below the list', (
    t,
  ) async {
    addTearDown(t.view.reset);
    await _size(t, 400);
    final (router, _) = await _pump(t);
    await t.tap(_chip('all'));
    await _settle(t);
    expect(find.text('Pindah kantor'), findsOneWidget);
    final search = find.descendant(
      of: find.byType(ChunkyBottomSheet),
      matching: find.byType(TextField),
    );
    final list = find.byKey(const ValueKey('office-switcher-list'));
    expect(t.getRect(search).top, greaterThanOrEqualTo(t.getRect(list).bottom));
    await t.tap(find.text('Kantor Tiga').last);
    await _settle(t);
    expect(_path(router), '/kantor/o/tiga');
    // current office joins the bar, highlighted, even if not fav/active
    expect(_chipSelected(t, 'tiga'), isTrue);
    await _close(t);
  });

  testWidgets('840dp office page: bar in the left pane; chip swaps the list, '
      'chat on the right stays', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 840);
    final (router, _) = await _pump(t);
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(_bar, findsOneWidget);
    expect(t.getRect(_bar).left, 0);
    expect(t.getRect(_bar).right, lessThanOrEqualTo(kantorListPaneWidth(840)));
    expect(t.getRect(_bar).bottom, 900);
    _expectApart(t, _newAgent, _bar);
    // header still there
    expect(find.byKey(const ValueKey('pane-office')), findsOneWidget);

    await t.tap(find.text('Ayu').first);
    await _settle(t);
    expect(_sidOf(t, _paneSession), 's1');

    await t.tap(_chip('lain'));
    await _settle(t);
    expect(_path(router), '/kantor/o/lain');
    expect(find.text('Citra'), findsWidgets);
    expect(find.text('Budi'), findsNothing);
    final pane = t.widget<KantorSessionPage>(_paneSession);
    expect((pane.officeId, pane.sid), ('demo', 's1'));
    expect(_chipSelected(t, 'lain'), isTrue);
    await _close(t);
  });

  testWidgets('840dp session route: chip swaps only the left list', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 840);
    final (router, _) = await _pump(t);
    router.go('/kantor/o/demo/s/s1');
    await _settle(t);
    final bar = find.descendant(of: _sessionTwoPane, matching: _bar);
    expect(bar, findsOneWidget);
    expect(t.getRect(bar).bottom, 900);

    await t.tap(find.descendant(of: _sessionTwoPane, matching: _chip('lain')));
    await _settle(t);
    expect(_path(router), '/kantor/o/demo/s/s1'); // no navigation
    expect(
      find.descendant(of: _sessionTwoPane, matching: find.text('Citra')),
      findsWidgets,
    );
    expect(t.widget<KantorSessionView>(_view(embedded: true)).sid, 's1');
    expect(_allChats, findsOneWidget);

    // "Semua…" here also only swaps the list
    await t.tap(find.descendant(of: _sessionTwoPane, matching: _chip('all')));
    await _settle(t);
    await t.tap(find.text('Kantor Demo').last);
    await _settle(t);
    expect(_path(router), '/kantor/o/demo/s/s1');
    expect(
      find.descendant(of: _sessionTwoPane, matching: find.text('Budi')),
      findsWidgets,
    );
    await _close(t);
  });
}
