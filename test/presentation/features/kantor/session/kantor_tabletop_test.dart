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
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_tabletop.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_tab.dart';
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
        hits.add(name);
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

    Future<KantorOfficeFeed> pumpPage(
      WidgetTester t, {
      List<Map<String, dynamic>> inbox = const [],
      String status = 'waiting',
    }) async {
      _size(t);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'id': 'o',
          'name': '168Railway',
          'roles': [
            {'id': 'p', 'name': 'Priskilla', 'title': 'Backend'},
          ],
          'sessions': [
            {'sid': 's1', 'role': 'p', 'status': status, 'tmux': 'x'},
          ],
        }
        ..inbox = inbox;
      addTearDown(feed.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorApiProvider.overrideWithValue(KantorApi(config)),
            kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
            kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
            kantorStateProvider.overrideWith(
              (ref) async => {
                'offices': [feed.office],
                'inbox': inbox,
              },
            ),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            builder: _withFeatures,
            home: const KantorSessionPage(officeId: 'o', sid: 's1'),
          ),
        ),
      );
      await _settle(t);
      return feed;
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await _settle(t, 2);
      // toast dan timer prefetch strip agen
      await t.pump(const Duration(seconds: 31));
    }

    testWidgets('tanpa engsel: tata letak lama (AppBar + tab), tanpa meja', (
      t,
    ) async {
      final screen = _mockScreen(t);
      await pumpPage(t);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byKey(const ValueKey('tabletop-header')), findsNothing);
      expect(find.byType(KantorTabletopLayout), findsNothing);
      expect(screen, isEmpty);
      await finish(t);
    });

    testWidgets(
      'posisi meja: chat di atas engsel, izin + composer di bawah; Izinkan '
      'memanggil endpoint kartu izin; layar tetap menyala',
      (t) async {
        final screen = _mockScreen(t);
        _features.value = const [_hinge];
        await pumpPage(
          t,
          inbox: [
            {
              'id': 'i1',
              'sid': 's1',
              'tool': 'Bash',
              'summary': 'php artisan migrate',
              'held': true,
            },
          ],
        );

        // AppBar diganti header mini: avatar, nama, kantor, status
        expect(find.byType(TabBar), findsNothing);
        final header = find.byKey(const ValueKey('tabletop-header'));
        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text('Priskilla')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: find.text('168Railway')),
          findsOneWidget,
        );
        expect(find.text('minta izin'), findsOneWidget);

        // atas berakhir di atas engsel
        final msg = find.text('Aku perlu menjalankan migrasi database.');
        expect(msg, findsOneWidget);
        expect(t.getRect(msg).bottom, lessThanOrEqualTo(370));
        expect(t.getRect(header).bottom, lessThanOrEqualTo(370));
        final topSlot = t.getRect(
          find.ancestor(of: header, matching: find.byType(SafeArea)).first,
        );
        expect(topSlot.bottom, 370);

        // bawah mulai tepat di bawah engsel: tombol izin besar + composer
        final bottom = t.getRect(find.byKey(const ValueKey('tabletop-bottom')));
        expect(bottom.top, 380);
        expect(bottom.bottom, _h);
        final allow = find.byKey(const ValueKey('tabletop-allow-i1'));
        expect(allow, findsOneWidget);
        expect(t.getRect(allow).top, greaterThanOrEqualTo(380));
        expect(find.byKey(const ValueKey('tabletop-deny-i1')), findsOneWidget);
        // Bash: "Izinkan selalu" tidak ada (daemon belum mendukung)
        expect(find.byKey(const ValueKey('tabletop-always-i1')), findsNothing);
        final field = _composer;
        expect(field, findsOneWidget);
        expect(t.getRect(field).top, greaterThanOrEqualTo(380));

        expect(screen, [true]);

        await t.tap(allow);
        await _settle(t);
        expect(posts.keys, contains('/api/inbox/i1'));
        expect(posts['/api/inbox/i1'], {'behavior': 'allow'});
        await finish(t);
        expect(screen, [true, false]);
      },
    );

    testWidgets('Izinkan selalu (alat edit) = izinkan + mode Edit otomatis', (
      t,
    ) async {
      _mockScreen(t);
      _features.value = const [_hinge];
      await pumpPage(
        t,
        inbox: [
          {
            'id': 'i2',
            'sid': 's1',
            'tool': 'Edit',
            'summary': 'lib/main.dart',
            'held': true,
          },
        ],
      );
      final always = find.byKey(const ValueKey('tabletop-always-i2'));
      expect(always, findsOneWidget);
      await t.tap(always);
      await _settle(t, 10);
      expect(posts['/api/inbox/i2'], {'behavior': 'allow'});
      expect(posts['/api/sessions/s1/mode'], {'mode': 'acceptEdits'});
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
        expect(find.text('bekerja'), findsOneWidget);
        expect(t.state(find.byType(KantorChatTab)), same(chat));
        expect(t.state(_composer), same(field));
        expect(t.widget<EditableText>(_composer).controller.text, 'draf meja');
        expect(t.getRect(_composer).top, greaterThan(380));
        expect(screen, [true]);

        _features.value = const [];
        await _settle(t);
        expect(find.byType(KantorTabletopLayout), findsNothing);
        expect(find.byType(TabBar), findsOneWidget);
        expect(t.state(find.byType(KantorChatTab)), same(chat));
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

    testWidgets('layar di atas engsel; tombol besar mengirim byte yang benar', (
      t,
    ) async {
      _size(t);
      _features.value = const [_hinge];
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
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            builder: _withFeatures,
            home: Scaffold(body: KantorTerminalPanel.session('s1')),
          ),
        ),
      );
      await _settle(t, 6);

      expect(find.byType(KantorTabletopLayout), findsOneWidget);
      expect(t.getRect(find.byType(TerminalView)).bottom, 370);
      final keys = {
        'Esc': '\x1b',
        'Tab': '\t',
        'up': '\x1b[A',
        'down': '\x1b[B',
        'left': '\x1b[D',
        'right': '\x1b[C',
        'Ctrl+C': '\x03',
        'Enter': '\r',
        '/': '/',
        'y': 'y',
        'n': 'n',
      };
      for (final k in keys.keys) {
        final f = find.byKey(ValueKey('tabletop-key-$k'));
        expect(f, findsOneWidget, reason: k);
        expect(t.getRect(f).top, greaterThanOrEqualTo(380), reason: k);
        await t.tap(f);
        await _settle(t, 2);
      }
      expect(input, keys.values.toList());

      // kolom ketik: teks lalu Enter
      input.clear();
      await t.enterText(
        find.byKey(const ValueKey('tabletop-term-input')),
        'ls -la',
      );
      await t.tap(find.byKey(const ValueKey('tabletop-term-send')));
      await _settle(t, 2);
      expect(input.join(), 'ls -la\r');
      expect(find.byKey(const ValueKey('tabletop-key-Tempel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tabletop-key-Salin layar')),
        findsOneWidget,
      );

      // keluar posisi meja: bar terminal lama kembali, terminal tetap sama
      final term = t.state(find.byType(TerminalView));
      _features.value = const [];
      await _settle(t, 2);
      expect(find.byType(KantorTabletopLayout), findsNothing);
      expect(find.byKey(const ValueKey('term-paste')), findsOneWidget);
      expect(t.state(find.byType(TerminalView)), same(term));

      await t.pumpWidget(const SizedBox());
      await _settle(t, 2);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
