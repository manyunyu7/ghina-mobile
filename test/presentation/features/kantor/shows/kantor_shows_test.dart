import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/shows/shows_button.dart';
import 'package:ghina/presentation/features/kantor/shows/shows_model.dart';
import 'package:ghina/presentation/features/kantor/shows/shows_screen.dart';

void main() {
  late HttpServer server;
  final posts = <String>[];
  final shows = <Map<String, dynamic>>[
    {
      'id': 't1',
      'office': 'o1',
      'sid': null,
      'who': 'Dina',
      'kind': 'file',
      'target': 'src/app.dart',
      'note': 'cek bagian ini',
      'lines': '150-152',
      'at': '2026-10-21T10:00:00Z',
      'seen': false,
      'closed': false,
    },
    {
      'id': 't2',
      'office': 'o1',
      'sid': null,
      'who': 'Raka',
      'kind': 'url',
      'target': 'http://localhost:5173/',
      'note': '',
      'lines': null,
      'at': '2026-10-21T09:00:00Z',
      'seen': true,
      'closed': false,
    },
  ];

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      req.response.headers.contentType = ContentType.json;
      final p = req.uri.path;
      if (req.method == 'POST') posts.add('$p $body');
      if (p == '/api/shows') {
        req.response.write(jsonEncode(shows));
      } else if (p == '/api/state') {
        req.response.write(
          jsonEncode({
            'offices': [
              {'id': 'o1', 'name': 'Kantor Satu', 'sessions': []},
            ],
            'inbox': [],
          }),
        );
      } else if (p == '/api/offices/o1/files/read') {
        req.response.write(
          jsonEncode({
            'path': 'src/app.dart',
            'size': 3000,
            'kind': 'text',
            'ext': '.dart',
            'text': [
              for (var i = 1; i <= 300; i++) 'baris nomor $i',
            ].join('\n'),
          }),
        );
      } else {
        req.response.write(jsonEncode({'ok': true}));
      }
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(posts.clear);

  Future<void> pump(
    WidgetTester t,
    Widget home, {
    Stream<Map<String, dynamic>>? events,
  }) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorApiProvider.overrideWithValue(
              KantorApi(
                KantorConfig(
                  baseUrl: 'http://127.0.0.1:${server.port}',
                  token: 't',
                ),
              ),
            ),
            kantorEventsProvider.overrideWith(
              (ref) => events ?? const Stream.empty(),
            ),
          ],
          child: MaterialApp(theme: GhinaTheme.light(), home: home),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pump(const Duration(milliseconds: 100));
  }

  test('parses lines and local hosts', () {
    expect(kantorParseLines('150-152'), (150, 152));
    expect(kantorParseLines([7, 3]), (3, 7));
    expect(kantorParseLines('9'), (9, 9));
    expect(kantorParseLines(null), isNull);
    expect(kantorIsLocalHost('localhost'), isTrue);
    expect(kantorIsLocalHost('192.168.1.5'), isTrue);
    expect(kantorIsLocalHost('example.com'), isFalse);
  });

  testWidgets('badge counts unseen, list shows newest first, closing posts', (
    t,
  ) async {
    await pump(
      t,
      Scaffold(appBar: AppBar(actions: const [KantorShowsButton()])),
    );
    expect(find.text('1'), findsOneWidget); // unseen badge
    await t.tap(find.byIcon(Icons.visibility_outlined));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Dibuka untukmu'), findsOneWidget);
    final dina = t.getTopLeft(find.textContaining('Dina · app.dart')).dy;
    final raka = t.getTopLeft(find.textContaining('Raka')).dy;
    expect(dina < raka, isTrue);
    expect(find.textContaining('cek bagian ini'), findsOneWidget);
    await t.tap(find.byTooltip('Tutup').first);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    expect(
      posts.any(
        (s) => s.startsWith('/api/shows/t1') && s.contains('"closed":true'),
      ),
      isTrue,
    );
    expect(find.textContaining('Dina · app.dart'), findsNothing);
    await t.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('live show event raises a notice', (t) async {
    final ev = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(ev.close);
    await pump(
      t,
      Scaffold(appBar: AppBar(actions: const [KantorShowsButton()])),
      events: ev.stream,
    );
    ev.add({
      't': 'show',
      'office': 'o1',
      'item': {
        ...shows[1],
        'id': 't3',
        'who': 'Mira',
        'kind': 'file',
        'target': 'docs/a.md',
        'seen': false,
      },
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Mira membukakan a.md untukmu'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('file opens with the range highlighted and scrolled into view', (
    t,
  ) async {
    await pump(t, KantorShowScreen(show: KantorShow.fromJson(shows[0])));
    await t.pump();
    await t.pump();
    expect(find.textContaining('baris 150–152 disorot'), findsOneWidget);
    expect(
      find.text('baris nomor 150'),
      findsOneWidget,
    ); // built only because it was scrolled to
    expect(find.text('baris nomor 1'), findsNothing);
    final hl = t.widget<Container>(find.byKey(const ValueKey('code-line-151')));
    expect(hl.color, isNotNull);
    final plain = t.widget<Container>(
      find.byKey(const ValueKey('code-line-149')),
    );
    expect(plain.color, isNull);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(
      posts.any(
        (s) => s.startsWith('/api/shows/t1') && s.contains('"seen":true'),
      ),
      isTrue,
      reason: '$posts',
    );
  });

  testWidgets('local URL offers Buka di Mac, not the browser', (t) async {
    await pump(t, KantorShowScreen(show: KantorShow.fromJson(shows[1])));
    expect(find.text('http://localhost:5173/'), findsWidgets);
    expect(find.text('BUKA DI MAC'), findsOneWidget);
    expect(find.text('BUKA DI BROWSER'), findsNothing);
    await t.tap(find.text('BUKA DI MAC'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }

    expect(
      posts.any((s) => s.startsWith('/api/offices/o1/open-local')),
      isTrue,
      reason: '$posts',
    );
    await t.pumpAndSettle(const Duration(seconds: 4));
  });
}
