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
    .widget<KantorOfficeChip>(
      find.byKey(ValueKey('office-chip-$id'), skipOffstage: false),
    )
    .selected;

void _expectApart(WidgetTester t, Finder a, Finder b) {
  final ra = t.getRect(a);
  final rb = t.getRect(b);
  expect(ra.overlaps(rb), isFalse, reason: '$ra overlaps $rb');
  expect(ra.bottom, lessThanOrEqualTo(rb.top));
}

/// Badge chip kantor [id] (null finder bila tidak ada).
Finder _badgeOf(String id) => find.descendant(
  of: _chip(id),
  matching: find.byKey(const ValueKey('office-chip-badge')),
);

/// Badge harus utuh: min 18dp, di dalam chip dan bilah, tidak terpotong.
void _expectBadgeWhole(WidgetTester t, String id, {Finder? bar}) {
  final badge = _badgeOf(id);
  expect(badge, findsOneWidget, reason: 'badge $id');
  final r = t.getRect(badge);
  expect(r.height, greaterThanOrEqualTo(18), reason: 'badge $id $r');
  expect(r.width, greaterThanOrEqualTo(18), reason: 'badge $id $r');
  final chip = t.getRect(_chip(id));
  expect(
    chip.contains(r.topLeft) &&
        chip.contains(r.bottomRight - const Offset(0.01, 0.01)),
    isTrue,
    reason: 'badge $r keluar dari chip $chip',
  );
  final b = t.getRect(bar ?? _bar);
  expect(r.top, greaterThanOrEqualTo(b.top), reason: 'badge $r vs bar $b');
  expect(r.bottom, lessThanOrEqualTo(b.bottom), reason: 'badge $r vs bar $b');
  // teks badge memakai 11sp tebal
  final text = t.widget<Text>(
    find.descendant(of: badge, matching: find.byType(Text)),
  );
  expect(text.style?.fontSize, 11);
  expect(text.style?.fontWeight, FontWeight.w800);
}

/// Bilah saja (tanpa halaman) di lebar [w], untuk kantor dengan nama panjang
/// dan banyak agen menunggu.
Future<void> _pumpBar(WidgetTester t, double w) async {
  final offices = [
    {
      'id': 'demo',
      'name': 'Kantor Demo',
      'sessions': [
        {'status': 'working'},
        {'status': 'idle'},
      ],
    },
    {
      'id': 'panjang',
      'name': 'Kantor Dengan Nama Yang Sangat Panjang Sekali Untuk Diuji',
      'fav': true,
      'sessions': [
        for (var i = 0; i < 150; i++) {'status': 'idle', 'waiting': 'izin'},
      ],
    },
    {
      'id': 'sepi',
      'name': 'Sepi',
      'fav': true,
      'sessions': [
        {'status': 'idle'},
      ],
    },
  ];
  final feeds = <KantorOfficeFeed>[];
  final c = ProviderContainer(
    overrides: [
      kantorOfficeFeedProvider.overrideWith((ref, id) {
        final f = KantorOfficeFeed(id, null)..loading = false;
        feeds.add(f);
        return f;
      }),
      kantorStateProvider.overrideWith(
        (ref) async => {'offices': offices, 'inbox': []},
      ),
    ],
  );
  addTearDown(() {
    c.dispose();
    for (final f in feeds) {
      f.dispose();
    }
  });
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: GhinaTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: w,
              child: const KantorOfficeBar(currentId: 'demo'),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(t);
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
  for (final w in [360.0, 330.0]) {
    testWidgets('${w.toInt()}dp: badges readable and whole, long name '
        'ellipsised, big counts "99+"', (t) async {
      addTearDown(t.view.reset);
      await _size(t, w);
      await _pumpBar(t, w);
      expect(t.takeException(), isNull); // tidak ada overflow
      expect(t.getSize(_bar).height, kKantorOfficeBarHeight);
      // nama panjang: chip dibatasi, nama dielipsis, badge tetap utuh
      _expectBadgeWhole(t, 'panjang');
      expect(
        find.descendant(of: _badgeOf('panjang'), matching: find.text('99+')),
        findsOneWidget,
      );
      final name = t.widget<Text>(
        find.descendant(
          of: _chip('panjang'),
          matching: find.textContaining('Sangat Panjang'),
        ),
      );
      expect(name.overflow, TextOverflow.ellipsis);
      expect(t.getSize(_chip('panjang')).width, lessThanOrEqualTo(240));
      // "Semua…" tetap terlihat di kanan, di dalam bilah
      expect(_chip('all'), findsOneWidget);
      expect(t.getRect(_chip('all')).right, lessThanOrEqualTo(w));
      // bisa digulir: chip berikutnya tercapai
      final list = find.descendant(
        of: find.byKey(const ValueKey('kantor-office-bar-list')),
        matching: find.byType(Scrollable),
      );
      await t.scrollUntilVisible(_chip('sepi'), 80, scrollable: list);
      await _settle(t);
      _expectBadgeWhole(t, 'sepi');
      await t.scrollUntilVisible(_chip('demo'), 80, scrollable: list);
      await _settle(t);
      // kantor aktif (bukan menunggu, ada yang bekerja): jumlah agen hidup
      _expectBadgeWhole(t, 'demo');
      expect(
        find.descendant(of: _badgeOf('demo'), matching: find.text('2')),
        findsOneWidget,
      );
      expect(_chipSelected(t, 'demo'), isTrue);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('830dp two-pane: badges whole in the 330dp left pane', (t) async {
    addTearDown(t.view.reset);
    await _size(t, 830);
    await _pump(t);
    expect(find.byType(KantorTwoPane), findsOneWidget);
    expect(t.getSize(_bar).width, lessThanOrEqualTo(330));
    expect(t.takeException(), isNull);
    _expectBadgeWhole(t, 'demo');
    _expectBadgeWhole(t, 'lain');
    expect(_chipSelected(t, 'demo'), isTrue);
    await _close(t);
  });
}
