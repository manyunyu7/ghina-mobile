import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/blocker_card.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

final _in15 = DateTime.now()
    .add(const Duration(minutes: 15))
    .toUtc()
    .toIso8601String();

/// Bentuk-bentuk blocker sesuai kontrak daemon.
final _menu = <String, dynamic>{
  'kind': 'login',
  'engine': 'codex',
  'method': 'menu',
  'title': 'Viodex belum bisa bekerja',
  'detail': 'Codex di MacBook menunggu login akun ChatGPT.',
  'url': null,
  'code': null,
  'expiresAt': null,
  'actions': [
    {'id': 'chatgpt', 'label': 'Masuk dengan ChatGPT', 'primary': true},
    {'id': 'device', 'label': 'Pakai kode perangkat', 'primary': false},
    {'id': 'apikey', 'label': 'API key', 'primary': false},
  ],
  'input': null,
  'at': '2026-11-17T09:00:00Z',
};

final _device = <String, dynamic>{
  'kind': 'login',
  'engine': 'codex',
  'method': 'device',
  'title': 'Login ChatGPT untuk Viodex',
  'detail': 'Buka halaman login, lalu masukkan kode ini.',
  'url': 'https://auth.openai.com/codex/device',
  'code': 'K7QX-2HB9P',
  'expiresAt': _in15,
  'actions': <Object>[],
  'input': null,
  'at': '2026-11-17T09:00:00Z',
};

final _browser = <String, dynamic>{
  'kind': 'login',
  'engine': 'codex',
  'method': 'browser',
  'title': 'Login ChatGPT untuk Viodex',
  'detail': null,
  'url': 'https://auth.openai.com/oauth/authorize?x=1',
  'code': null,
  'expiresAt': null,
  'actions': <Object>[],
  'input': {
    'id': 'callback',
    'label': 'Alamat dari browser',
    'placeholder': 'Tempel alamat 127.0.0.1:1455/auth/callback?code=…',
  },
  'at': '2026-11-17T09:00:00Z',
};

final _prompt = <String, dynamic>{
  'kind': 'prompt',
  'engine': 'claude',
  'method': null,
  'title': '"Trust the files in this folder?"',
  'detail': '~/Developer/168Railway/web',
  'url': null,
  'code': null,
  'expiresAt': null,
  'actions': [
    {'id': 'enter', 'label': 'Ya, lanjut', 'primary': true},
    {'id': 'esc', 'label': 'Batal', 'primary': false},
  ],
  'input': null,
  'at': '2026-11-17T09:00:00Z',
};

final _claude = <String, dynamic>{
  'kind': 'login',
  'engine': 'claude',
  'method': 'claude',
  'title': 'Claude minta login ulang',
  'detail': null,
  'url': 'https://claude.ai/oauth/authorize?code=true',
  'code': null,
  'expiresAt': null,
  'actions': <Object>[],
  'input': {
    'id': 'code',
    'label': 'Kode dari halaman login',
    'placeholder': 'Tempel kode dari halaman login',
  },
  'at': '2026-11-17T09:00:00Z',
};

/// Server HTTP lokal palsu: mencatat POST /blocker dan menjawab sesuai [reply].
class _FakeDaemon {
  late HttpServer server;
  final posts = <({String path, Map<String, dynamic> body})>[];
  Object? Function(Map<String, dynamic> body) reply = (_) => {
    'ok': true,
    'blocker': null,
  };
  int status = 200;
  Map<String, dynamic>? open;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      Object? body = <Object>[];
      var code = 200;
      final path = req.uri.path;
      if (path.endsWith('/blocker') && req.method == 'POST') {
        final b = raw.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map);
        posts.add((path: path, body: b));
        code = status;
        body = reply(b);
      } else if (path.endsWith('/open')) {
        body =
            open ??
            {
              'transcript': {
                'items': <Object>[],
                'cursor': 'c1',
                'reset': true,
                'size': 0,
              },
              'attachments': <Object>[],
            };
      } else if (path.endsWith('/transcript')) {
        body = {'items': <Object>[], 'cursor': 'c1', 'reset': false, 'size': 0};
      }
      req.response
        ..statusCode = code
        ..persistentConnection = false
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
  }

  KantorConfig get config =>
      KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 't');
}

Widget _host(Widget child) => MaterialApp(
  theme: GhinaTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

class _Holder extends StatefulWidget {
  const _Holder({super.key, required this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_Holder> createState() => _HolderState();
}

class _HolderState extends State<_Holder> {
  late Map<String, dynamic>? blocker = widget.initial;

  void set(Map<String, dynamic>? b) => setState(() => blocker = b);

  @override
  Widget build(BuildContext context) => KantorBlockerCard(
    blocker: kantorBlockerOf(blocker),
    sid: 's1',
    api: null,
    who: 'Viodex',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = null;
  });

  group('kantorBlockerOf', () {
    test('only maps with a kind count; old daemons give null', () {
      expect(kantorBlockerOf(null), isNull);
      expect(kantorBlockerOf('login'), isNull);
      expect(kantorBlockerOf({'title': 'x'}), isNull);
      expect(kantorBlockerOf(_prompt)?['kind'], 'prompt');
    });

    test('the disk snapshot never carries a blocker', () {
      final o = kantorNeutralOffice({
        'sessions': [
          {'sid': 's1', 'status': 'idle', 'blocker': _device},
        ],
      });
      expect(asJsonList(o['sessions']).single.containsKey('blocker'), isFalse);
    });
  });

  group('KantorBlockerCard renders', () {
    testWidgets('menu: pill, title, detail and action buttons', (t) async {
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_menu),
            sid: 's1',
            api: null,
            who: 'Viodex',
          ),
        ),
      );
      expect(find.text('Perlu login'), findsOneWidget);
      expect(find.text('Viodex belum bisa bekerja'), findsOneWidget);
      expect(
        find.textContaining('menunggu login akun ChatGPT'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('blocker-act-chatgpt')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-act-device')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-act-apikey')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-code')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-open')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-input')), findsNothing);
    });

    testWidgets('device: big code, open + copy, countdown', (t) async {
      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          calls.add(c);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_device),
            sid: 's1',
            api: null,
            who: 'Viodex',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('blocker-code')), findsOneWidget);
      expect(find.text('K7QX-2HB9P'), findsOneWidget);
      expect(find.text('Buka halaman login ↗'), findsOneWidget);
      expect(find.text('Salin kode'), findsOneWidget);
      final cd = t.widget<Text>(
        find.byKey(const ValueKey('blocker-countdown')),
      );
      expect(cd.data, matches(RegExp(r'Kode berlaku 1[45]:\d\d lagi')));

      await t.tap(find.byKey(const ValueKey('blocker-copy')));
      await t.pump();
      final set = calls.where((c) => c.method == 'Clipboard.setData');
      expect((set.single.arguments as Map)['text'], 'K7QX-2HB9P');

      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('browser: open login + callback field with one-tap paste', (
      t,
    ) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async => c.method == 'Clipboard.getData'
            ? {'text': ' http://127.0.0.1:1455/auth/callback?code=abc '}
            : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_browser),
            sid: 's1',
            api: null,
            who: 'Viodex',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('blocker-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-copy')), findsNothing);
      expect(find.text('Alamat dari browser'), findsOneWidget);
      expect(find.text('Kirim ke Viodex'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('blocker-paste')));
      await t.pump();
      final field = t.widget<TextField>(
        find.byKey(const ValueKey('blocker-input')),
      );
      expect(
        field.controller!.text,
        'http://127.0.0.1:1455/auth/callback?code=abc',
      );
    });

    testWidgets('prompt: blue pill and green primary action', (t) async {
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_prompt),
            sid: 's1',
            api: null,
            who: 'Joko',
          ),
        ),
      );
      expect(find.text('Menunggu di terminal'), findsOneWidget);
      expect(find.text('"Trust the files in this folder?"'), findsOneWidget);
      expect(find.text('Ya, lanjut'), findsOneWidget);
      final b = t.widget<ChunkyButton>(
        find.byKey(const ValueKey('blocker-act-enter')),
      );
      expect(b.color, GhinaColors.green);
      final esc = t.widget<ChunkyButton>(
        find.byKey(const ValueKey('blocker-act-esc')),
      );
      expect(esc.variant, ChunkyButtonVariant.outline);
    });

    testWidgets('claude: open login + code field', (t) async {
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_claude),
            sid: 's1',
            api: null,
            who: 'Joko',
          ),
        ),
      );
      expect(find.text('Claude minta login ulang'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-input')), findsOneWidget);
      expect(find.text('Kirim kode'), findsOneWidget);
      // tombol kirim mati selama kolomnya kosong
      expect(
        t
            .widget<ChunkyButton>(find.byKey(const ValueKey('blocker-send')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('nothing at all without a blocker', (t) async {
      await t.pumpWidget(
        _host(
          const KantorBlockerCard(
            blocker: null,
            sid: 's1',
            api: null,
            who: 'Viodex',
          ),
        ),
      );
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
    });
  });

  group('KantorBlockerCard sends', () {
    late _FakeDaemon d;
    setUp(() async {
      d = _FakeDaemon();
      await d.start();
    });
    tearDown(() => d.server.close(force: true));

    testWidgets('an action posts {action} and the answer replaces the card', (
      t,
    ) async {
      d.reply = (_) => {'ok': true, 'blocker': _device};
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_menu),
            sid: 's1',
            api: KantorApi(d.config),
            who: 'Viodex',
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('blocker-act-device')));
      await t.pump();
      expect(
        t
            .widget<ChunkyButton>(
              find.byKey(const ValueKey('blocker-act-device')),
            )
            .loading,
        isTrue,
      );
      await _settle(t);
      expect(d.posts.single.path, '/api/sessions/s1/blocker');
      expect(d.posts.single.body, {'action': 'device'});
      expect(find.text('K7QX-2HB9P'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-act-device')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('callback posts {action, value}; success shows ✓ then goes', (
      t,
    ) async {
      d.reply = (_) => {'ok': true, 'blocker': null};
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_browser),
            sid: 's1',
            api: KantorApi(d.config),
            who: 'Viodex',
          ),
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('blocker-input')),
        'http://127.0.0.1:1455/auth/callback?code=abc',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('blocker-send')));
      await _settle(t);
      expect(d.posts.single.body, {
        'action': 'callback',
        'value': 'http://127.0.0.1:1455/auth/callback?code=abc',
      });
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.text('✓ Viodex sudah login'), findsOneWidget);
      await t.pump(KantorBlockerCard.okFor);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
    });

    testWidgets('a refusal shows a short red line and keeps the card', (
      t,
    ) async {
      d.status = 400;
      d.reply = (_) => {'error': 'Kode salah atau kedaluwarsa'};
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_claude),
            sid: 's1',
            api: KantorApi(d.config),
            who: 'Joko',
          ),
        ),
      );
      await t.enterText(find.byKey(const ValueKey('blocker-input')), 'abc#1');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('blocker-send')));
      await _settle(t);
      expect(d.posts.single.body, {'action': 'code', 'value': 'abc#1'});
      expect(find.text('Kode salah atau kedaluwarsa'), findsOneWidget);
      expect(find.text('Claude minta login ulang'), findsOneWidget);
      final send = t.widget<ChunkyButton>(
        find.byKey(const ValueKey('blocker-send')),
      );
      expect(send.loading, isFalse);
      expect(send.onPressed, isNotNull);
    });

    testWidgets('daemon without the route: a short note, no crash', (t) async {
      d.status = 404;
      d.reply = (_) => {'error': 'Tidak ditemukan.'};
      await t.pumpWidget(
        _host(
          KantorBlockerCard(
            blocker: kantorBlockerOf(_prompt),
            sid: 's1',
            api: KantorApi(d.config),
            who: 'Joko',
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('blocker-act-enter')));
      await _settle(t);
      expect(d.posts.single.body, {'action': 'enter'});
      expect(find.byKey(const ValueKey('blocker-error')), findsOneWidget);
    });
  });

  group('KantorBlockerCard updates from the feed', () {
    testWidgets('login → null: green ✓ card for 3 s, then gone', (t) async {
      final key = GlobalKey<_HolderState>();
      await t.pumpWidget(_host(_Holder(key: key, initial: _device)));
      expect(find.byKey(const ValueKey('blocker-card')), findsOneWidget);
      key.currentState!.set(null);
      await t.pump();
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.text('✓ Viodex sudah login'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('blocker-ok')), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
    });

    testWidgets('prompt → null just disappears', (t) async {
      final key = GlobalKey<_HolderState>();
      await t.pumpWidget(_host(_Holder(key: key, initial: _prompt)));
      key.currentState!.set(null);
      await t.pump();
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
    });

    testWidgets('a new blocker replaces the shown one', (t) async {
      final key = GlobalKey<_HolderState>();
      await t.pumpWidget(_host(_Holder(key: key, initial: _menu)));
      key.currentState!.set(_device);
      await t.pump();
      expect(find.text('K7QX-2HB9P'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });

  group('chat tab', () {
    late _FakeDaemon d;
    setUp(() async {
      d = _FakeDaemon();
      await d.start();
    });
    tearDown(() => d.server.close(force: true));

    Future<KantorOfficeFeed> pumpChat(
      WidgetTester t, {
      Map<String, dynamic>? sessBlocker,
      StreamController<Map<String, dynamic>>? events,
    }) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..loadedAt = DateTime(2026, 11, 17, 9)
        ..office = {
          'sessions': [
            {
              'sid': 's1',
              'status': 'idle',
              'tmux': 'x',
              'blocker': ?sessBlocker,
            },
          ],
          'roles': <Object>[],
        };
      addTearDown(feed.dispose);
      final c = ProviderContainer(
        overrides: [
          kantorApiProvider.overrideWith((ref) => KantorApi(d.config)),
          kantorEventsProvider.overrideWith(
            (ref) => events?.stream ?? const Stream.empty(),
          ),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              body: KantorChatTab(feed: feed, sid: 's1'),
            ),
          ),
        ),
      );
      return feed;
    }

    Future<void> unmount(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 7));
      await t.pump(const Duration(seconds: 7));
    }

    testWidgets('empty chat + feed blocker: the card instead of "kosong"', (
      t,
    ) async {
      await pumpChat(t, sessBlocker: _device);
      await _settle(t);
      expect(find.byKey(const ValueKey('blocker-card')), findsOneWidget);
      expect(find.text('K7QX-2HB9P'), findsOneWidget);
      expect(find.text('Belum ada percakapan di transcript.'), findsNothing);
      await unmount(t);
    });

    testWidgets('blocker from GET /open shows; a session event updates it', (
      t,
    ) async {
      d.open = {
        'transcript': {
          'items': <Object>[],
          'cursor': 'c1',
          'reset': true,
          'size': 0,
        },
        'attachments': <Object>[],
        'session': {'sid': 's1', 'status': 'idle', 'blocker': _browser},
      };
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      final feed = await pumpChat(t, events: events);
      await _settle(t);
      expect(find.byKey(const ValueKey('blocker-card')), findsOneWidget);
      expect(find.text('Kirim ke Sesi manual'), findsOneWidget);
      expect(find.byKey(const ValueKey('blocker-input')), findsOneWidget);

      // login selesai: daemon mengabarkan sesi tanpa blocker
      final msg = {
        't': 'session',
        'office': 'o',
        'session': {
          'sid': 's1',
          'status': 'idle',
          'tmux': 'x',
          'blocker': null,
        },
      };
      events.add(msg);
      feed.apply(msg);
      await t.pump();
      await t.pump();
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.textContaining('sudah login'), findsOneWidget);
      await t.pump(KantorBlockerCard.okFor);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('blocker-ok')), findsNothing);
      expect(find.text('Belum ada percakapan di transcript.'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('old daemon (no blocker field): plain empty chat', (t) async {
      await pumpChat(t);
      await _settle(t);
      expect(find.byKey(const ValueKey('blocker-card')), findsNothing);
      expect(find.text('Belum ada percakapan di transcript.'), findsOneWidget);
      await unmount(t);
    });
  });
}
