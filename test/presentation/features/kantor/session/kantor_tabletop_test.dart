import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_konteks.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_tabletop.dart';
import 'package:ghina/presentation/features/kantor/session/permission_card.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_tab.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

/// Fold 8 Ultra dalam posisi meja (disederhanakan): layar 830x750, engsel
/// mendatar di y 370..380.
const _w = 830.0, _h = 750.0;
const _hinge = DisplayFeature(
  bounds: Rect.fromLTWH(0, 370, 830, 10),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

/// Kotak ketik composer (pesan chat juga EditableText, tapi readOnly).
final _composer = find.byWidgetPredicate(
  (w) => w is EditableText && !w.readOnly,
);

/// Posisi yang dipakai MaterialApp.builder (bisa diganti di tengah tes).
final _features = ValueNotifier<List<DisplayFeature>>(const []);

Widget _withFeatures(BuildContext c, Widget? child) =>
    ValueListenableBuilder<List<DisplayFeature>>(
      valueListenable: _features,
      builder: (c, f, _) => MediaQuery(
        data: MediaQuery.of(c).copyWith(displayFeatures: f),
        child: child!,
      ),
    );

/// Beri waktu IO sungguhan (http / websocket) lalu render.
Future<void> _settle(WidgetTester t, [int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester t) {
  t.view.physicalSize = const Size(_w, _h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Panggilan `ravel/screen` keepOn (true/false) yang sampai ke "Android".
List<Object?> _mockScreen(WidgetTester t) {
  final calls = <Object?>[];
  KantorScreenAwake.resetForTest();
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    KantorScreenAwake.channel,
    (call) async {
      if (call.method == 'keepOn') calls.add(call.arguments);
      return null;
    },
  );
  addTearDown(() {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      KantorScreenAwake.channel,
      null,
    );
    KantorScreenAwake.resetForTest();
  });
  return calls;
}

void main() {
  setUp(() {
    _features.value = const [];
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('deteksi engsel', () {
    testWidgets('hanya engsel mendatar setengah terbuka yang dianggap meja', (
      t,
    ) async {
      Future<Rect?> at(List<DisplayFeature> f) async {
        Rect? out;
        await t.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: const Size(_w, _h), displayFeatures: f),
            child: Builder(
              builder: (c) {
                out = kantorTabletopHinge(c);
                return const SizedBox();
              },
            ),
          ),
        );
        return out;
      }

      expect(await at(const []), isNull);
      expect(await at(const [_hinge]), const Rect.fromLTWH(0, 370, 830, 10));
      // rata / terbuka penuh
      expect(
        await at(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 370, 830, 10),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ]),
        isNull,
      );
      // gaya buku: engsel tegak
      expect(
        await at(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(410, 0, 10, 750),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]),
        isNull,
      );
      // poni kamera bukan engsel
      expect(
        await at(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 0, 830, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ]),
        isNull,
      );
      // engsel nol-tebal (Android melaporkan tinggi 0)
      expect(
        await at(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 375, 830, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]),
        isNotNull,
      );
    });
  });

  group('chat sesi', () {
    late HttpServer server;
    late KantorConfig config;
    final posts = <String, Object?>{};
    final hits = <String>[];

    setUp(() async {
      posts.clear();
      hits.clear();
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        final name = path.split('/').last;
        // hanya muatan chat sesi s1 (kartu agen juga menghangatkan chat lain)
        if (path.contains('/sessions/s1/')) hits.add(name);
        if (req.method == 'POST') {
          final raw = await utf8.decoder.bind(req).join();
          posts[path] = raw.isEmpty ? null : jsonDecode(raw);
        }
        final tail = {
          'items': [
            {'k': 'text', 's': 'Aku perlu menjalankan migrasi database.'},
          ],
          'cursor': 'c1',
          'reset': true,
          'size': 1,
          'gen': 'g1',
        };
        Object body = {'ok': true};
        if (name == 'open') {
          body = {'transcript': tail, 'attachments': [], 'session': null};
        } else if (name == 'transcript') {
          body = tail;
        } else if (name == 'attachments') {
          body = [];
        }
        req.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body))
          ..close();
      });
      config = KantorConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 't',
      );
    });
    tearDown(() => server.close(force: true));

    late GoRouter router;

    /// Kantor "168Railway": Priskilla (s1, sesi yang dibuka), Ayu bekerja,
    /// Budi idle berlabel, Dodi idle; kantor "Gudang": Citra minta izin.
    Future<KantorOfficeFeed> pumpPage(
      WidgetTester t, {
      List<Map<String, dynamic>> inbox = const [],
      String status = 'waiting',
      bool dark = false,
    }) async {
      _size(t);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'id': 'o',
          'name': '168Railway',
          'roles': [
            {'id': 'p', 'name': 'Priskilla', 'title': 'Backend'},
            {'id': 'a', 'name': 'Ayu', 'title': 'QA'},
          ],
          'sessions': [
            {
              'sid': 's1',
              'role': 'p',
              'status': status,
              'tmux': 'x',
              'look': {'name': 'Priskilla'},
            },
            {
              'sid': 's2',
              'role': 'a',
              'status': 'working',
              'tmux': 'x2',
              'look': {'name': 'Ayu'},
              'tool': {'name': 'Bash', 'label': 'npm test'},
            },
            {
              'sid': 's3',
              'status': 'idle',
              'tmux': 'x3',
              'look': {'name': 'Budi'},
              'lastSeen': 2,
              'konteks': {
                'topic': 'Migrasi jadwal',
                'auto': 'Judul otomatis',
                'label': {'text': 'Migrasi jadwal', 'scope': 'sesi'},
                'state': {'k': 'tunggu', 'label': 'Menunggu'},
              },
            },
            {
              'sid': 's5',
              'status': 'idle',
              'tmux': 'x5',
              'look': {'name': 'Dodi'},
              'lastSeen': 1,
            },
          ],
        }
        ..inbox = inbox;
      addTearDown(feed.dispose);
      final other = {
        'id': 'g',
        'name': 'Gudang',
        'sessions': [
          {
            'sid': 's4',
            'status': 'waiting',
            'tmux': 'x4',
            'look': {'name': 'Citra'},
            'waiting': {'tool': 'Edit', 'summary': 'lib/main.dart'},
          },
        ],
      };
      router = GoRouter(
        initialLocation: '/kantor/o/o/s/s1',
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
            kantorApiProvider.overrideWithValue(KantorApi(config)),
            kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
            kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
            kantorStateProvider.overrideWith(
              (ref) async => {
                'offices': [feed.office, other],
                'inbox': inbox,
              },
            ),
          ],
          child: MaterialApp.router(
            theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
            builder: _withFeatures,
            routerConfig: router,
          ),
        ),
      );
      await _settle(t);
      return feed;
    }

    Future<void> finish(WidgetTester t) async {
      // tunggu prefetch chat dari kartu agen selesai dulu
      await _settle(t, 4);
      await t.pumpWidget(const SizedBox());
      await _settle(t, 2);
      // toast dan timer prefetch kartu agen
      await t.pump(const Duration(seconds: 31));
    }

    final grid = find.byKey(const ValueKey('tabletop-agents'));
    Finder inGrid(String text) =>
        find.descendant(of: grid, matching: find.text(text));

    testWidgets('tanpa engsel: tata letak lama (AppBar + tab), tanpa meja', (
      t,
    ) async {
      final screen = _mockScreen(t);
      await pumpPage(t);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byKey(const ValueKey('tabletop-header')), findsNothing);
      expect(find.byType(KantorTabletopLayout), findsNothing);
      expect(grid, findsNothing);
      expect(screen, isEmpty);
      await finish(t);
    });

    testWidgets(
      'posisi meja: header + chat + kartu izin + composer di atas engsel, '
      'kartu agen di bawah; tanpa tombol izin besar; layar tetap menyala',
      (t) async {
        final screen = _mockScreen(t);
        _features.value = const [_hinge];
        await pumpPage(
          t,
          inbox: [
            {
              'id': 'i1',
              'sid': 's1',
              'tool': 'Edit',
              'summary':
                  'php artisan migrate --force --seed && php artisan '
                  'queue:restart && php artisan cache:clear && php artisan '
                  'config:cache && php artisan route:cache && php artisan '
                  'view:cache && php artisan optimize && echo selesai',
              'held': true,
            },
          ],
        );
        expect(t.takeException(), isNull);

        // AppBar diganti header mini: avatar, nama, kantor, status
        expect(find.byType(TabBar), findsNothing);
        final header = find.byKey(const ValueKey('tabletop-header'));
        expect(header, findsOneWidget);
        for (final s in ['Priskilla', '168Railway', 'minta izin']) {
          expect(
            find.descendant(of: header, matching: find.text(s)),
            findsOneWidget,
            reason: s,
          );
        }

        // atas berakhir di engsel: header, chat, kartu izin, lalu composer
        final topSlot = t.getRect(
          find.ancestor(of: header, matching: find.byType(SafeArea)).first,
        );
        expect(topSlot.bottom, 370);
        final msg = find.text('Aku perlu menjalankan migrasi database.');
        expect(msg, findsOneWidget);
        // kartu izin versi ringkas (bukan kartu lengkap) di atas composer
        final card = find.byKey(const ValueKey('tabletop-perm-i1'));
        expect(card, findsOneWidget);
        expect(find.byType(KantorPermissionCard), findsNothing);
        final composer = t.getRect(_composer);
        expect(composer.bottom, lessThanOrEqualTo(370));
        expect(t.getRect(header).bottom, lessThanOrEqualTo(composer.top));
        final extras = t.getRect(
          find.byKey(const ValueKey('tabletop-top-extras')),
        );
        expect(extras.bottom, lessThanOrEqualTo(composer.top));
        // batas kartu izin/login ±40% bagian atas
        expect(extras.height, lessThanOrEqualTo(370 * .4 + .5));
        // area chat minimal 110px walau ada izin tertunda
        final chatArea = extras.top - t.getRect(header).bottom;
        expect(chatArea, greaterThanOrEqualTo(110));
        expect(t.getRect(msg).bottom, lessThanOrEqualTo(extras.top));
        // composer satu baris (±56px): dari kartu izin sampai engsel
        expect(370 - extras.bottom, lessThanOrEqualTo(60));
        // chip cepat (lanjut/ya/Hentikan) disembunyikan di mode meja
        expect(find.text('lanjut'), findsNothing);
        expect(find.text('Hentikan'), findsNothing);
        // Izinkan / Tolak terlihat utuh tanpa menggulir
        for (final k in ['allow', 'deny']) {
          final r = t.getRect(find.byKey(ValueKey('tabletop-perm-$k-i1')));
          expect(r.top, greaterThanOrEqualTo(extras.top), reason: k);
          expect(r.bottom, lessThanOrEqualTo(extras.bottom), reason: k);
        }
        // ringkasan perintah maksimal 2 baris; ketuk = tampil penuh
        final sum = find.descendant(
          of: find.byKey(const ValueKey('tabletop-perm-summary-i1')),
          matching: find.byType(Text),
        );
        expect(t.widget<Text>(sum).maxLines, 2);
        await t.tap(sum);
        await t.pump();
        expect(t.widget<Text>(sum).maxLines, isNull);

        // tombol izin besar mode meja tidak ada lagi
        for (final k in ['allow', 'deny', 'always']) {
          expect(find.byKey(ValueKey('tabletop-$k-i1')), findsNothing);
        }

        // bawah mulai tepat di bawah engsel: grid kartu agen saja
        final bottom = t.getRect(find.byKey(const ValueKey('tabletop-bottom')));
        expect(bottom.top, 380);
        expect(bottom.bottom, _h);
        expect(grid, findsOneWidget);
        expect(t.getRect(grid).top, greaterThanOrEqualTo(380));
        // avatar agen di header tidak tampil di mode meja
        expect(
          find.byKey(const ValueKey('kantor-header-agents')),
          findsNothing,
        );

        // 830dp: 4 kolom, tinggi kartu seragam
        final delegate =
            t.widget<GridView>(grid).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, inInclusiveRange(3, 4));
        expect(delegate.crossAxisCount, 4);

        // urutan: yang dibuka dulu, lalu perlu tindakan → bekerja → idle
        final names = ['Priskilla', 'Citra', 'Ayu', 'Budi', 'Dodi'];
        Rect cardOf(String n) => t.getRect(
          find.ancestor(of: inGrid(n), matching: find.byType(ChunkySurface)),
        );
        final pos = [for (final n in names) cardOf(n)];
        for (var i = 1; i < 4; i++) {
          expect(pos[i].top, pos[0].top, reason: names[i]);
          expect(pos[i].left, greaterThan(pos[i - 1].left), reason: names[i]);
        }
        expect(pos[4].top, greaterThan(pos[0].bottom));
        expect(pos[4].left, pos[0].left);
        // tinggi seragam, 4 kartu + celah muat selebar 830dp
        for (final r in pos) {
          expect(r.height, kantorTabletopCardHeight);
        }
        expect(pos[3].right, lessThanOrEqualTo(_w));

        // isi kartu: kantor, pil status, stiker label, aktivitas
        expect(inGrid('Gudang'), findsOneWidget);
        expect(inGrid('168Railway'), findsNWidgets(4));
        expect(inGrid('izin'), findsNWidgets(2));
        expect(inGrid('bekerja'), findsOneWidget);
        expect(inGrid('idle'), findsNWidgets(2));
        expect(
          find.descendant(
            of: grid,
            matching: find.widgetWithText(KantorLabelSticker, 'Migrasi jadwal'),
          ),
          findsOneWidget,
        );
        expect(inGrid('Bash npm test'), findsOneWidget);

        // agen yang sedang dibuka disorot garis aksen
        ChunkySurface surfaceOf(String n) => t.widget<ChunkySurface>(
          find.ancestor(of: inGrid(n), matching: find.byType(ChunkySurface)),
        );
        final accent = Theme.of(t.element(grid)).colorScheme.primary;
        expect(surfaceOf('Priskilla').borderColor, accent);
        expect(surfaceOf('Ayu').borderColor, isNot(accent));

        expect(screen, [true]);

        // kartu izin inline tetap bekerja
        await t.tap(find.byKey(const ValueKey('tabletop-perm-allow-i1')));
        await _settle(t);
        expect(posts['/api/inbox/i1'], {'behavior': 'allow'});
        await finish(t);
        expect(screen, [true, false]);
      },
    );

    testWidgets('ketuk kartu agen: chat di atas pindah ke agen itu', (t) async {
      _mockScreen(t);
      _features.value = const [_hinge];
      await pumpPage(t);
      // kartu agen yang sedang dibuka tidak memindahkan apa pun
      await t.tap(inGrid('Priskilla'));
      await _settle(t, 3);
      expect(router.state.uri.toString(), '/kantor/o/o/s/s1');

      await t.tap(inGrid('Ayu'));
      await _settle(t, 6);
      expect(router.state.uri.toString(), '/kantor/o/o/s/s2?tab=chat');
      final header = find.byKey(const ValueKey('tabletop-header'));
      expect(
        find.descendant(of: header, matching: find.text('Ayu')),
        findsOneWidget,
      );
      // Ayu sekarang yang disorot dan ada di depan
      final first = t.getCenter(inGrid('Ayu'));
      expect(first.dx, lessThan(t.getCenter(inGrid('Priskilla')).dx));
      await finish(t);
    });

    testWidgets('tema gelap 830x750: tanpa overflow', (t) async {
      _mockScreen(t);
      _features.value = const [_hinge];
      await pumpPage(
        t,
        dark: true,
        inbox: [
          {
            'id': 'i3',
            'sid': 's1',
            'tool': 'Bash',
            'summary': 'php artisan migrate --force',
            'held': true,
          },
        ],
      );
      expect(t.takeException(), isNull);
      expect(grid, findsOneWidget);
      expect(find.byKey(const ValueKey('tabletop-perm-i3')), findsOneWidget);
      final extras = t.getRect(
        find.byKey(const ValueKey('tabletop-top-extras')),
      );
      final header = t.getRect(find.byKey(const ValueKey('tabletop-header')));
      expect(extras.top - header.bottom, greaterThanOrEqualTo(110));
      expect(t.getRect(_composer).bottom, lessThanOrEqualTo(370));
      await finish(t);
    });

    testWidgets(
      'masuk/keluar posisi meja: chat tidak dimuat ulang, draf tetap, layar '
      'menyala hanya selama meja',
      (t) async {
        final screen = _mockScreen(t);
        await pumpPage(t, status: 'working');
        final chat = t.state(find.byType(KantorChatTab));
        final loads = hits.where((h) => h == 'open' || h == 'transcript');
        final before = loads.length;
        await t.enterText(_composer, 'draf meja');
        await t.pump();
        final field = t.state(_composer);

        _features.value = const [_hinge];
        await _settle(t);
        expect(find.byType(KantorTabletopLayout), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('tabletop-header')),
            matching: find.text('bekerja'),
          ),
          findsOneWidget,
        );
        expect(t.state(find.byType(KantorChatTab)), same(chat));
        expect(t.state(_composer), same(field));
        expect(t.widget<EditableText>(_composer).controller.text, 'draf meja');
        // composer di atas engsel
        expect(t.getRect(_composer).bottom, lessThanOrEqualTo(370));
        expect(grid, findsOneWidget);
        expect(screen, [true]);

        _features.value = const [];
        await _settle(t);
        expect(find.byType(KantorTabletopLayout), findsNothing);
        expect(find.byType(TabBar), findsOneWidget);
        expect(grid, findsNothing);
        expect(t.state(find.byType(KantorChatTab)), same(chat));
        expect(t.state(_composer), same(field));
        expect(t.widget<EditableText>(_composer).controller.text, 'draf meja');
        expect(screen, [true, false]);
        expect(
          hits.where((h) => h == 'open' || h == 'transcript').length,
          before,
        );

        // app ke background saat posisi meja: layar dilepas, kembali: menyala
        _features.value = const [_hinge];
        await _settle(t);
        expect(screen, [true, false, true]);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        expect(screen, [true, false, true, false]);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pump();
        expect(screen, [true, false, true, false, true]);
        // kembali ke depan memuat ulang chat: tunggu sampai selesai
        await _settle(t, 8);
        await finish(t);
      },
    );
  });

  group('terminal sesi', () {
    late HttpServer server;
    late List<String> input;
    WebSocket? sock;

    setUp(() async {
      HttpOverrides.global = null;
      input = [];
      sock = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path != '/ws/term') {
          req.response
            ..statusCode = 404
            ..close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        sock = ws;
        ws.add('\x1b[Hhalo dunia');
        ws.listen((d) {
          // pesan resize diawali '\x00'; selebihnya ketikan
          if (d is String && !d.startsWith('\x00')) input.add(d);
        });
      });
    });
    tearDown(() async {
      await sock?.close();
      await server.close(force: true);
    });

    testWidgets(
      'layar + tombol kecil biasa di atas engsel, kartu agen di bawah, tanpa '
      'tombol besar',
      (t) async {
        _size(t);
        _features.value = const [_hinge];
        final opened = <String>[];
        final c = ProviderContainer(
          overrides: [
            kantorApiProvider.overrideWithValue(
              KantorApi(
                KantorConfig(
                  baseUrl: 'http://127.0.0.1:${server.port}',
                  token: 't',
                ),
              ),
            ),
            kantorStateProvider.overrideWith(
              (ref) async => {
                'offices': [
                  {
                    'id': 'o',
                    'name': '168Railway',
                    'sessions': [
                      {
                        'sid': 's1',
                        'status': 'working',
                        'look': {'name': 'Priskilla'},
                      },
                      {
                        'sid': 's2',
                        'status': 'idle',
                        'look': {'name': 'Budi'},
                      },
                    ],
                  },
                ],
                'inbox': [],
              },
            ),
          ],
        );
        addTearDown(c.dispose);
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: GhinaTheme.light(),
              builder: _withFeatures,
              home: Scaffold(
                body: KantorTabletopScope(
                  header: const SizedBox(
                    key: ValueKey('tabletop-header'),
                    height: 40,
                  ),
                  agents: KantorTabletopAgents(
                    currentSid: 's1',
                    onOpen: (a) => opened.add(a.sid),
                  ),
                  child: KantorTerminalPanel.session('s1'),
                ),
              ),
            ),
          ),
        );
        await _settle(t, 6);
        expect(t.takeException(), isNull);

        expect(find.byType(KantorTabletopLayout), findsOneWidget);
        final view = t.getRect(find.byType(TerminalView));
        expect(
          view.top,
          greaterThanOrEqualTo(
            t.getRect(find.byKey(const ValueKey('tabletop-header'))).bottom,
          ),
        );
        // bar atas biasa (Tempel / Salin layar) dan baris tombol kecil biasa,
        // semuanya di atas engsel
        for (final k in ['term-paste', 'term-copy-screen']) {
          final f = find.byKey(ValueKey(k));
          expect(f, findsOneWidget, reason: k);
          expect(t.getRect(f).bottom, lessThanOrEqualTo(370), reason: k);
        }
        final esc = find.text('Esc');
        expect(esc, findsOneWidget);
        expect(t.getRect(esc).top, greaterThanOrEqualTo(view.bottom));
        expect(t.getRect(esc).bottom, lessThanOrEqualTo(370));
        // tombol besar mode meja tidak ada lagi
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('tabletop-key-'),
          ),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('tabletop-term-input')), findsNothing);

        await t.tap(esc);
        await _settle(t, 2);
        expect(input, ['\x1b']);

        // kartu agen di bawah engsel; ketuk = pindah agen
        final grid = find.byKey(const ValueKey('tabletop-agents'));
        expect(grid, findsOneWidget);
        expect(t.getRect(grid).top, greaterThanOrEqualTo(380));
        await t.tap(find.descendant(of: grid, matching: find.text('Budi')));
        await t.pump();
        expect(opened, ['s2']);

        // keluar posisi meja: tata letak biasa, terminal tetap sama
        final term = t.state(find.byType(TerminalView));
        _features.value = const [];
        await _settle(t, 2);
        expect(find.byType(KantorTabletopLayout), findsNothing);
        expect(grid, findsNothing);
        expect(find.byKey(const ValueKey('term-paste')), findsOneWidget);
        expect(t.state(find.byType(TerminalView)), same(term));

        await t.pumpWidget(const SizedBox());
        await _settle(t, 2);
        await t.pump(const Duration(seconds: 5));
      },
    );
  });
}
