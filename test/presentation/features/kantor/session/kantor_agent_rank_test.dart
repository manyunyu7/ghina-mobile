import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_agent_rank.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _s(
  String sid,
  String name,
  String status, {
  Object? waiting,
  Object? blocker,
  int seen = 0,
}) => {
  'sid': sid,
  'status': status,
  'tmux': 't-$sid',
  'look': {'name': name},
  'lastSeen': seen,
  'waiting': ?waiting,
  'blocker': ?blocker,
};

final _offices = <String, Map<String, dynamic>>{
  'demo': {
    'id': 'demo',
    'name': 'Kantor Demo',
    'sessions': [
      _s('s1', 'Ayu', 'working', seen: 5),
      _s('s2', 'Budi', 'idle', seen: 4),
      _s(
        's4',
        'Priskilla',
        'waiting',
        waiting: {'tool': 'Bash', 'summary': 'ls'},
      ),
    ],
  },
  'lain': {
    'id': 'lain',
    'name': 'Kantor Lain',
    'sessions': [_s('s3', 'Citra', 'idle', seen: 3)],
  },
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('peringkat: perlu tindakan > bekerja > terakhir dibuka > idle', () {
    String id(String sid) => kantorComplexChatIdentity('', 'o', sid);
    final ranked = kantorRankAgents(
      [
        (
          connection: '',
          connectionName: 'Mac mini',
          active: true,
          state: {
            'offices': [
              {
                'id': 'o',
                'name': 'Kantor',
                'sessions': [
                  _s('idle-lama', 'A', 'idle', seen: 1),
                  _s('idle-baru', 'B', 'idle', seen: 9),
                  _s('kerja', 'C', 'working', seen: 2),
                  _s('dibuka', 'D', 'idle', seen: 0),
                  _s('izin', 'E', 'waiting', waiting: {'tool': 'Bash'}),
                  _s('login', 'F', 'idle', blocker: {'kind': 'login'}),
                  // server lama / blocker kosong: bukan perlu tindakan
                  _s('kosong', 'G', 'idle', blocker: false, seen: 5),
                  _s('selesai', 'H', 'ended'),
                ],
              },
            ],
          },
        ),
        (
          connection: 'vps',
          connectionName: 'VPS',
          active: false,
          state: {
            'offices': [
              {
                'id': 'o',
                'name': 'Kantor VPS',
                'sessions': [_s('kerja', 'V', 'working', seen: 8)],
              },
            ],
          },
        ),
      ],
      [id('dibuka'), id('kerja')],
    );
    expect(ranked.map((a) => a.name).toList(), [
      'E', 'F', // perlu tindakan
      'C', 'V', // bekerja: yang baru dibuka dulu, lalu yang terakhir aktif
      'D', // terakhir dibuka
      'B', 'G', 'A', // idle, terbaru dulu
    ]);
    expect(ranked.first.actionLabel, 'izin');
    expect(ranked[1].actionLabel, 'login');
    expect(ranked[1].needsAction, isTrue);
    expect(ranked.firstWhere((a) => a.name == 'G').needsAction, isFalse);
    final v = ranked.firstWhere((a) => a.name == 'V');
    expect(
      (v.connection, v.active, v.officeName),
      ('vps', false, 'Kantor VPS'),
    );
    expect(v.haystack, contains('vps'));
  });

  Future<GoRouter> pumpSession(WidgetTester t, double width) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final feeds = {
      for (final e in _offices.entries)
        e.key: KantorOfficeFeed(e.key, null)
          ..loading = false
          ..office = e.value,
    };
    for (final f in feeds.values) {
      addTearDown(f.dispose);
    }
    final router = GoRouter(
      initialLocation: '/kantor/o/demo/s/s1',
      routes: [
        GoRoute(
          path: '/kantor/o/:office/s/:sid',
          builder: (_, s) => KantorSessionPage(
            officeId: s.pathParameters['office']!,
            sid: s.pathParameters['sid']!,
            tab: s.uri.queryParameters['tab'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feeds[id]!),
          kantorOfficeProvider.overrideWith((ref, id) async => _offices[id]!),
          kantorStateProvider.overrideWith(
            (ref) async => {'offices': _offices.values.toList(), 'inbox': []},
          ),
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    return router;
  }

  Finder strip() => find.byKey(const ValueKey('kantor-agent-strip'));
  double slotHeight(WidgetTester t) =>
      t.getSize(find.byKey(const ValueKey('agent-strip-slot'))).height;

  testWidgets('400dp: strip tampil, urut, ketuk avatar pindah ke kantor lain', (
    t,
  ) async {
    final router = await pumpSession(t, 400);
    expect(strip(), findsOneWidget);
    // urutan di strip: Priskilla (izin) → Ayu (bekerja, saat ini) → Budi, Citra
    final xs = [
      for (final n in ['Priskilla', 'Ayu', 'Budi', 'Citra'])
        t.getCenter(find.descendant(of: strip(), matching: find.text(n))).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    await t.tap(find.descendant(of: strip(), matching: find.text('Citra')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    // pindah kantor juga, tetap di tab yang sama
    expect(router.state.uri.toString(), '/kantor/o/lain/s/s3?tab=chat');
    expect(strip(), findsOneWidget);
  });

  testWidgets('900dp: dua panel, tanpa strip', (t) async {
    await pumpSession(t, 900);
    expect(find.byKey(const ValueKey('session-two-pane')), findsOneWidget);
    expect(strip(), findsNothing);
  });

  testWidgets('strip sembunyi saat chat digulir ke riwayat, muncul lagi', (
    t,
  ) async {
    await pumpSession(t, 400);
    expect(slotHeight(t), greaterThan(40));
    final ctx = t.element(find.byType(KantorChatTab));
    // daftar chat terbalik: offset membesar = menjauh dari pesan terbaru
    ScrollMetrics m(double px) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 3000,
      pixels: px,
      viewportDimension: 500,
      axisDirection: AxisDirection.up,
      devicePixelRatio: 1,
    );
    UserScrollNotification(
      metrics: m(300),
      context: ctx,
      direction: ScrollDirection.reverse,
    ).dispatch(ctx);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(slotHeight(t), 0);

    UserScrollNotification(
      metrics: m(250),
      context: ctx,
      direction: ScrollDirection.forward,
    ).dispatch(ctx);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(slotHeight(t), greaterThan(40));

    // ke riwayat lagi, lalu berhenti di dasar (pesan terbaru) → tampil
    UserScrollNotification(
      metrics: m(300),
      context: ctx,
      direction: ScrollDirection.reverse,
    ).dispatch(ctx);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(slotHeight(t), 0);
    ScrollEndNotification(metrics: m(0), context: ctx).dispatch(ctx);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(slotHeight(t), greaterThan(40));

    // juga di tab Terminal; tidak di tab lain
    await t.tap(find.text('Terminal'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(strip(), findsOneWidget);
    expect(slotHeight(t), greaterThan(40));
    await t.tap(find.text('Profil'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(strip(), findsNothing);
  });

  testWidgets('chips: pil avatar + nama, agen saat ini ditandai', (t) async {
    KantorRankedAgent? opened;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorStateProvider.overrideWith(
            (ref) async => {'offices': _offices.values.toList()},
          ),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: KantorAgentStrip(
              currentSid: 's1',
              chips: true,
              onOpen: (a) => opened = a,
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.text('Priskilla'), findsOneWidget);
    expect(find.text('Citra'), findsOneWidget);
    await t.tap(find.text('Ayu'));
    expect(opened, isNull, reason: 'agen saat ini tidak dibuka ulang');
    await t.tap(find.text('Citra'));
    expect(opened?.sid, 's3');
    expect(opened?.officeId, 'lain');
  });

  testWidgets(
    'pencari cepat: bagian, cari di bawah, ketik + Enter buka teratas',
    (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('demo', null)
        ..loading = false
        ..office = {
          ..._offices['demo']!,
          'roles': [
            {'id': 'r9', 'name': 'Sari', 'title': 'Ops'},
          ],
        };
      addTearDown(feed.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showKantorAgentSwitcher(
                    c,
                    officeId: 'demo',
                    currentSid: 's1',
                    tab: 'terminal',
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
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
            kantorStateProvider.overrideWith(
              (ref) async => {'offices': _offices.values.toList()},
            ),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('PERLU TINDAKAN  1'), findsOneWidget);
      expect(find.text('BEKERJA  1'), findsOneWidget);
      expect(find.text('SEMUA AGEN · 4'), findsOneWidget);
      expect(find.text('LIBUR  1'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final search = find.byKey(const ValueKey('agent-switcher-search'));
      expect(
        t.getTopLeft(search).dy,
        greaterThan(t.getBottomLeft(find.text('LIBUR  1')).dy),
        reason: 'kolom cari di bawah daftar (zona jempol)',
      );

      await t.enterText(find.byType(TextField), 'cit');
      await t.pump();
      expect(find.text('HASIL  1'), findsOneWidget);
      expect(find.textContaining('Budi'), findsNothing);
      await t.testTextInput.receiveAction(TextInputAction.go);
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
      expect(router.state.uri.toString(), '/kantor/o/lain/s/s3?tab=terminal');
      expect(find.text('Pindah agen'), findsNothing);
    },
  );
}
