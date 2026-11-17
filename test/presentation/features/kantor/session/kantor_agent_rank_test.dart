import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_agent_rank.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_konteks.dart';
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

/// Banyak agen: 2 perlu tindakan, 3 bekerja (selain agen saat ini), 2 idle.
final _busy = <String, Map<String, dynamic>>{
  'demo': {
    'id': 'demo',
    'name': 'Kantor Demo',
    'sessions': [
      _s('s1', 'Scout Penjelajah Samudra', 'working', seen: 5),
      _s('s2', 'Budi', 'idle', seen: 4),
      _s(
        's4',
        'Priskilla',
        'waiting',
        waiting: {'tool': 'Bash', 'summary': 'ls'},
      ),
      _s('s5', 'Vega', 'working', seen: 9),
      _s('s6', 'Cakra', 'working', seen: 3),
    ],
  },
  'lain': {
    'id': 'lain',
    'name': 'Kantor Lain',
    'sessions': [
      _s('s3', 'Citra', 'idle', seen: 3),
      _s('s7', 'Dewi', 'idle', blocker: {'kind': 'login'}),
      _s('s8', 'Eko', 'working', seen: 1),
    ],
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

  Future<GoRouter> pumpSession(
    WidgetTester t,
    double width, {
    Map<String, Map<String, dynamic>>? offices,
    ThemeData? theme,
    ChatStyle style = ChatStyle.bawaan,
  }) async {
    final data = offices ?? _offices;
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final feeds = {
      for (final e in data.entries)
        e.key: KantorOfficeFeed(e.key, null)
          ..loading = false
          ..office = e.value,
    };
    for (final f in feeds.values) {
      addTearDown(f.dispose);
    }
    // sesi di bawah rute induk: header punya tombol kembali seperti di app
    final router = GoRouter(
      initialLocation: '/kantor/o/demo/s/s1',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('beranda')),
          routes: [
            GoRoute(
              path: 'kantor/o/:office/s/:sid',
              builder: (_, s) => KantorSessionPage(
                officeId: s.pathParameters['office']!,
                sid: s.pathParameters['sid']!,
                tab: s.uri.queryParameters['tab'],
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    final c = ProviderContainer(
      overrides: [
        kantorOfficeFeedProvider.overrideWith((ref, id) => feeds[id]!),
        kantorOfficeProvider.overrideWith((ref, id) async => data[id]!),
        kantorStateProvider.overrideWith(
          (ref) async => {'offices': data.values.toList(), 'inbox': []},
        ),
      ],
    );
    addTearDown(c.dispose);
    if (style != ChatStyle.bawaan) {
      c
          .read(chatViewPrefsProvider.notifier)
          .update((p) => p.copyWith(style: style));
    }
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: theme ?? GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    return router;
  }

  String id(String office, String sid) =>
      kantorComplexChatIdentity('', office, sid);
  Finder header() => find.byKey(const ValueKey('kantor-header-agents'));
  Finder face(String office, String sid) =>
      find.byKey(ValueKey('header-agent-${id(office, sid)}'));
  Finder more() => find.byKey(const ValueKey('header-agents-more'));

  /// Identitas avatar header yang tampil, urut kiri → kanan.
  List<String> shown(WidgetTester t) {
    final found = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('header-agent-'),
    );
    final items = [
      for (final e in found.evaluate())
        (
          (e.widget.key! as ValueKey<String>).value.substring(
            'header-agent-'.length,
          ),
          t.getTopLeft(find.byWidget(e.widget)).dx,
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final i in items) i.$1];
  }

  String moreText(WidgetTester t) => t
      .widget<Text>(find.descendant(of: more(), matching: find.byType(Text)))
      .data!;

  void expectHeaderFits(WidgetTester t) {
    final bar = t.getRect(find.byType(AppBar));
    final cluster = t.getRect(header());
    expect(cluster.right, lessThanOrEqualTo(bar.right));
    expect(cluster.top, greaterThanOrEqualTo(bar.top));
    // nama agen saat ini tetap terbaca (≥ 90dp) dan tidak ditimpa avatar
    final name = t.getRect(find.byKey(const ValueKey('header-name')));
    expect(name.width, greaterThanOrEqualTo(90));
    expect(name.right, lessThanOrEqualTo(cluster.left));
    // aksi header tetap ada
    expect(find.byKey(const ValueKey('all-complex-agents')), findsOneWidget);
    expect(find.byTooltip('Aksi sesi'), findsOneWidget);
  }

  testWidgets('360dp: 3 avatar penting (merah lalu biru) + "+N", tanpa strip', (
    t,
  ) async {
    final router = await pumpSession(t, 360, offices: _busy);
    expect(t.takeException(), isNull);
    expect(header(), findsOneWidget);
    expect(shown(t), [id('demo', 's4'), id('lain', 's7'), id('demo', 's5')]);
    // 7 agen lain - 3 tampil
    expect(moreText(t), '+4');
    // idle bukan avatar
    expect(face('demo', 's2'), findsNothing);
    expect(face('lain', 's3'), findsNothing);
    // avatar 24–26dp tanpa nama, saling tumpang
    final a = t.getRect(face('demo', 's4'));
    final b = t.getRect(face('lain', 's7'));
    expect(a.width, inInclusiveRange(24, 26));
    expect(b.left, lessThan(a.right));
    expect(find.text('Priskilla'), findsNothing);
    expectHeaderFits(t);

    // tidak ada strip di bawah header: area chat langsung di bawah bar konteks
    final bar = t.getRect(find.byType(AppBar));
    final konteks = t.getRect(find.byType(KantorKonteksBar));
    final chat = t.getRect(find.byKey(const ValueKey('tab0')));
    expect(konteks.top, bar.bottom);
    expect(chat.top, konteks.bottom);
    expect(chat.bottom, 900);

    // ketuk avatar: pindah ke agen itu (kantor lain), tab sama
    await t.tap(face('lain', 's7'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(router.state.uri.toString(), '/kantor/o/lain/s/s7?tab=chat');
    // agen yang sekarang dibuka tidak tampil sebagai avatar
    expect(face('lain', 's7'), findsNothing);
    expect(face('demo', 's4'), findsOneWidget);
  });

  testWidgets('400dp: 4 avatar penting + "+N"; "+N" membuka pencari', (
    t,
  ) async {
    await pumpSession(t, 400, offices: _busy);
    expect(t.takeException(), isNull);
    expect(shown(t), [
      id('demo', 's4'),
      id('lain', 's7'),
      id('demo', 's5'),
      id('demo', 's6'),
    ]);
    expect(moreText(t), '+3');
    expectHeaderFits(t);

    await t.tap(more());
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah agen'), findsOneWidget);
  });

  testWidgets('tab Terminal juga, tab lain tidak; tanpa agen penting hanya '
      '"+N"', (t) async {
    await pumpSession(t, 360);
    // data dasar: Priskilla (izin) satu-satunya agen lain yang penting
    expect(shown(t), [id('demo', 's4')]);
    expect(moreText(t), '+2');
    await t.tap(find.text('Terminal'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(header(), findsOneWidget);
    await t.tap(find.text('Profil'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(header(), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());

    // tidak ada agen yang perlu tindakan/bekerja: hanya chip "+N"
    await pumpSession(
      t,
      360,
      offices: {
        'demo': {
          'id': 'demo',
          'name': 'Kantor Demo',
          'sessions': [
            _s('s1', 'Ayu', 'working'),
            _s('s2', 'Budi', 'idle'),
            _s('s3', 'Citra', 'idle'),
          ],
        },
      },
    );
    expect(shown(t), isEmpty);
    expect(moreText(t), '+2');
    await t.pumpWidget(const SizedBox.shrink());

    // tanpa agen lain: tidak tampil apa-apa
    await pumpSession(
      t,
      360,
      offices: {
        'demo': {
          'id': 'demo',
          'name': 'Kantor Demo',
          'sessions': [_s('s1', 'Ayu', 'working')],
        },
      },
    );
    expect(more(), findsNothing);
    expect(shown(t), isEmpty);
  });

  testWidgets('360dp tema gelap dan gaya WhatsApp: muat tanpa overflow', (
    t,
  ) async {
    await pumpSession(t, 360, offices: _busy, theme: GhinaTheme.dark());
    expect(t.takeException(), isNull);
    expect(shown(t), hasLength(3));
    expectHeaderFits(t);
    await t.pumpWidget(const SizedBox.shrink());

    await pumpSession(t, 360, offices: _busy, style: ChatStyle.whatsapp);
    expect(t.takeException(), isNull);
    expect(header(), findsOneWidget);
    // avatar mengalah lebih dulu: jumlahnya boleh berkurang, nama tetap ≥ 90
    expect(shown(t), isNotEmpty);
    expect(shown(t).first, id('demo', 's4'));
    final bar = t.getRect(find.byType(AppBar));
    expect(t.getRect(header()).right, lessThanOrEqualTo(bar.right));
    // baris pertama judul messenger = nama agen saat ini
    final title = find
        .descendant(
          of: find.byKey(const ValueKey('messenger-profile-header')),
          matching: find.byType(Text),
        )
        .first;
    expect(t.getSize(title).width, greaterThanOrEqualTo(90));
    expect(find.byKey(const ValueKey('all-complex-agents')), findsOneWidget);
  });

  testWidgets('900dp: dua panel, tanpa avatar header', (t) async {
    await pumpSession(t, 900, offices: _busy);
    expect(find.byKey(const ValueKey('session-two-pane')), findsOneWidget);
    expect(header(), findsNothing);
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
