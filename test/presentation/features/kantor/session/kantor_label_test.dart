import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/app/ravel_notifications.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_agent_switcher.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_agent_rank.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_konteks.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_label.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Konteks sesi dengan label pemilik [text] (null = tanpa label).
Map<String, dynamic> _konteks(String? text) => {
  'topic': text ?? 'Judul otomatis',
  if (text != null) 'auto': 'Judul otomatis',
  if (text != null) 'label': {'text': text, 'scope': 'sesi'},
  'state': {'k': 'tunggu', 'label': 'Menunggu'},
};

Map<String, dynamic> _s(String sid, String name, String status, {String? l}) =>
    {
      'sid': sid,
      'status': status,
      'tmux': 't-$sid',
      'look': {'name': name},
      'lastSeen': 1,
      'konteks': _konteks(l),
    };

Map<String, dynamic> _offices() => {
  'demo': {
    'id': 'demo',
    'name': 'Kantor Demo',
    'sessions': [
      _s('s1', 'Ayu', 'working'),
      _s('s2', 'Budi', 'idle', l: 'Migrasi jadwal'),
    ],
  },
  'lain': {
    'id': 'lain',
    'name': 'Kantor Lain',
    'sessions': [_s('s3', 'Citra', 'idle')],
  },
};

Finder _sticker(String text) => find.descendant(
  of: find.byType(KantorLabelSticker),
  matching: find.text(text),
);

class _RealHttp extends HttpOverrides {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    kantorLabelPatches.clear();
  });

  group('judul notifikasi', () {
    test('label sesi masuk judul, dipotong sekitar 40 karakter', () {
      final item = {'id': 'i1', 'who': 'Budi', 'sid': 's2', 'office': 'demo'};
      expect(RavelNotifications.inboxTitle(item), 'Budi menunggu izin');
      expect(
        RavelNotifications.inboxTitle(item, label: ' Migrasi\njadwal '),
        'Budi · Migrasi jadwal',
      );
      final long = RavelNotifications.inboxTitle(
        item,
        label: 'Migrasi jadwal kereta api seluruh Jawa dan Sumatra 2027',
      );
      expect(long, startsWith('Budi · Migrasi jadwal'));
      expect(long, endsWith('…'));
      expect(long.length, lessThanOrEqualTo('Budi · '.length + 40));
    });

    test('label dicari dari sesi item di state', () {
      final state = {
        'offices': _offices().values.toList(),
        'loose': [_s('x9', 'Lepas', 'idle', l: 'Sesi lepas')],
      };
      expect(
        RavelNotifications.inboxLabel(state, {'sid': 's2'}),
        'Migrasi jadwal',
      );
      expect(RavelNotifications.inboxLabel(state, {'sid': 's1'}), isNull);
      expect(RavelNotifications.inboxLabel(state, {'sid': 'x9'}), 'Sesi lepas');
      expect(RavelNotifications.inboxLabel(null, {'sid': 's2'}), isNull);
    });
  });

  testWidgets('daftar agen: stiker label; tahan → sheet → POST, tampilan '
      'berubah segera', (t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final saved = HttpOverrides.current;
    HttpOverrides.global = _RealHttp();
    addTearDown(() => HttpOverrides.global = saved);

    // server palsu: catat POST label, tahan jawaban sampai [answer] selesai
    final posts = <(String, Map<String, dynamic>)>[];
    final answer = Completer<void>();
    final server = (await t.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    final feed = KantorOfficeFeed('demo', null)
      ..loading = false
      ..office = {
        'id': 'demo',
        'name': 'Kantor Demo',
        'roles': [
          {'id': 'ra', 'name': 'Ayu', 'title': 'Backend'},
          {'id': 'rb', 'name': 'Budi', 'title': 'QA'},
        ],
        'sessions': [
          {..._s('s1', 'Ayu', 'idle'), 'role': 'ra'},
          {..._s('s2', 'Budi', 'idle', l: 'Migrasi jadwal'), 'role': 'rb'},
        ],
      };
    addTearDown(feed.dispose);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      req.response.headers.contentType = ContentType.json;
      if (req.method == 'POST' && req.uri.path.endsWith('/label')) {
        posts.add((req.uri.path, jsonDecode(body) as Map<String, dynamic>));
        await answer.future;
        req.response.write(jsonEncode({'ok': true}));
      } else {
        req.response.write(req.uri.path == '/api/state' ? '{}' : '[]');
      }
      await req.response.close();
    });
    final api = KantorApi(
      KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 't'),
    );

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
          kantorApiProvider.overrideWithValue(api),
          kantorStateProvider.overrideWith(
            (ref) async => {'offices': <Object>[], 'inbox': <Object>[]},
          ),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: KantorAgentsTab(officeId: 'demo')),
        ),
      ),
    );
    await t.pump();
    // stiker label di bawah nama agen
    expect(_sticker('Migrasi jadwal'), findsOneWidget);
    expect(find.byType(KantorLabelSticker), findsOneWidget);

    // Ayu belum berlabel: tahan kartunya → "Beri label"
    await t.longPress(find.byKey(const ValueKey('agent-tile-s1')));
    await t.pumpAndSettle();
    expect(find.text('Beri label'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('label-menu-edit')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('label-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('label-delete')), findsNothing);
    await t.enterText(find.byType(TextField), '  Rilis Android ');
    await t.tap(find.byKey(const ValueKey('label-tell')));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('label-save')));
    await t.tap(find.byKey(const ValueKey('label-save')));
    await t.pump();
    for (var i = 0; i < 200 && posts.isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 10));
    }
    // body persis seperti web; sesi tanpa role → carry selalu false
    expect(posts, hasLength(1));
    expect(posts.single.$1, '/api/sessions/s1/label');
    expect(posts.single.$2, {
      'text': 'Rilis Android',
      'carry': false,
      'tell': true,
    });
    // optimistis: stiker baru sudah tampil sebelum server menjawab
    expect(_sticker('Rilis Android'), findsOneWidget);

    // server menjawab dan menyiarkan data segar lewat /ws (sesi kini berlabel)
    feed.apply({
      't': 'session',
      'office': 'demo',
      'session': {..._s('s1', 'Ayu', 'idle', l: 'Rilis Android'), 'role': 'ra'},
    });
    answer.complete();
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 10));
    }
    await t.pumpAndSettle();
    expect(find.text('Label disimpan'), findsOneWidget);
    expect(find.byKey(const ValueKey('label-save')), findsNothing);
    expect(_sticker('Rilis Android'), findsOneWidget);
    expect(_sticker('Migrasi jadwal'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
  });

  test('gagal simpan: label kembali ke semula', () async {
    final c = ProviderContainer(
      overrides: [
        kantorApiProvider.overrideWithValue(
          KantorApi(
            const KantorConfig(baseUrl: 'http://127.0.0.1:1', token: 't'),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final s = _s('s2', 'Budi', 'idle', l: 'Migrasi jadwal');
    await expectLater(
      kantorSaveLabel(c, sid: 's2', text: 'Baru', carry: false, tell: false),
      throwsA(anything),
    );
    expect(kantorLabelOf(s), 'Migrasi jadwal');
    // simpanan yang sedang berjalan langsung tampil (optimistis)
    kantorLabelPatches.put('s2', KantorLabelPatch('Baru'));
    expect(kantorLabelOf(s), 'Baru');
    expect(KantorKonteks.ofSession(s)?.auto, 'Judul otomatis');
    kantorLabelPatches.put('s2', KantorLabelPatch(null));
    expect(kantorLabelOf(s), isNull);
    expect(KantorKonteks.ofSession(s)?.topic, 'Judul otomatis');
  });

  testWidgets('judul chat: subjudul jadi stiker label satu baris', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final offices = _offices();
    final feeds = {
      for (final e in offices.entries)
        e.key: KantorOfficeFeed(e.key, null)
          ..loading = false
          ..office = e.value,
    };
    for (final f in feeds.values) {
      addTearDown(f.dispose);
    }
    final router = GoRouter(
      initialLocation: '/kantor/o/demo/s/s2',
      routes: [
        GoRoute(
          path: '/kantor/o/:office/s/:sid',
          builder: (_, s) => KantorSessionPage(
            officeId: s.pathParameters['office']!,
            sid: s.pathParameters['sid']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feeds[id]!),
          kantorOfficeProvider.overrideWith((ref, id) async => offices[id]!),
          kantorStateProvider.overrideWith(
            (ref) async => {'offices': offices.values.toList(), 'inbox': []},
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
    final header = find.byKey(const ValueKey('header-label'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: _sticker('Migrasi jadwal')),
      findsOneWidget,
    );
    final sticker = t.widget<KantorLabelSticker>(
      find.descendant(of: header, matching: find.byType(KantorLabelSticker)),
    );
    expect(sticker.maxLines, 1);
    // teks "kantor · status" diganti stiker
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.textContaining('Kantor Demo'),
      ),
      findsNothing,
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets(
    'avatar header: pojok kuning untuk agen berlabel, tahan → label lengkap',
    (t) async {
      // agen berlabel harus penting (bekerja) agar tampil di header
      final offices = _offices();
      offices['demo']!['sessions'] = [
        _s('s1', 'Ayu', 'working'),
        _s('s2', 'Budi', 'working', l: 'Migrasi jadwal'),
      ];
      offices['lain']!['sessions'] = [_s('s3', 'Citra', 'working')];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorStateProvider.overrideWith(
              (ref) async => {'offices': offices.values.toList()},
            ),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: const Scaffold(
              body: Center(
                child: KantorHeaderAgents(maxWidth: 200, currentSid: 's1'),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      String id(String o, String sid) => kantorComplexChatIdentity('', o, sid);
      expect(
        find.byKey(ValueKey('label-corner-${id('demo', 's2')}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('label-corner-${id('lain', 's3')}')),
        findsNothing,
      );
      // avatar header tanpa nama
      expect(find.text('Budi'), findsNothing);
      await t.longPress(
        find.byKey(ValueKey('header-agent-${id('demo', 's2')}')),
      );
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('label-menu-full')),
          matching: find.text('Migrasi jadwal'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ubah label'), findsOneWidget);
    },
  );

  testWidgets('pencari cepat: stiker label dan cari "migrasi" menemukan agen '
      'berlabel', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final feed = KantorOfficeFeed('demo', null)
      ..loading = false
      ..office = _offices()['demo'];
    addTearDown(feed.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
          kantorStateProvider.overrideWith(
            (ref) async => {'offices': _offices().values.toList()},
          ),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showKantorAgentSwitcher(
                  c,
                  officeId: 'demo',
                  currentSid: 's1',
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(_sticker('Migrasi jadwal'), findsOneWidget);

    await t.enterText(
      find.byKey(const ValueKey('agent-switcher-search')),
      'migrasi',
    );
    await t.pump();
    expect(find.text('HASIL  1'), findsOneWidget);
    expect(find.textContaining('Budi'), findsOneWidget);
    expect(find.textContaining('Citra'), findsNothing);

    // judul otomatis yang tergeser label juga dicari
    await t.enterText(
      find.byKey(const ValueKey('agent-switcher-search')),
      'judul otomatis',
    );
    await t.pump();
    expect(find.textContaining('Budi'), findsOneWidget);

    // tahan baris → menu label
    await t.enterText(
      find.byKey(const ValueKey('agent-switcher-search')),
      'migrasi',
    );
    await t.pump();
    await t.longPress(
      find.byKey(
        ValueKey('switch-${kantorComplexChatIdentity('', 'demo', 's2')}'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Ubah label'), findsOneWidget);
  });
}
