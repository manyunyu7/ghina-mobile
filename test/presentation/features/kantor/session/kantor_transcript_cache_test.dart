import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/chat_context.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _text(String s) => {'k': 'text', 's': s};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('mergeTranscript', () {
    test('delta appends only the new lines', () {
      final m = mergeTranscript(
        [_text('a'), _text('b')],
        {
          'items': [_text('c')],
          'cursor': 'c2',
          'reset': false,
        },
      );
      expect(m.items.map((e) => e['s']), ['a', 'b', 'c']);
      expect(m.cursor, 'c2');
      expect(m.changed, isTrue);
    });

    test('empty delta keeps what is held and reports no change', () {
      final held = [_text('a')];
      final m = mergeTranscript(held, {
        'items': <Object>[],
        'cursor': 'c3',
        'reset': false,
      });
      expect(identical(m.items, held), isTrue);
      expect(m.cursor, 'c3');
      expect(m.changed, isFalse);
    });

    test('reset replaces the held history (e.g. after /clear)', () {
      final m = mergeTranscript(
        [_text('old')],
        {
          'items': [_text('new')],
          'cursor': 'g2',
          'reset': true,
        },
      );
      expect(m.items.map((e) => e['s']), ['new']);
    });

    test('daemon without delta support: the answer is the whole tail', () {
      final m = mergeTranscript(
        [_text('old')],
        {
          'items': [_text('x'), _text('y')],
        },
      );
      expect(m.items.map((e) => e['s']), ['x', 'y']);
      expect(m.cursor, isNull);
    });

    test('never holds more than keep items', () {
      final m = mergeTranscript(
        [for (var i = 0; i < 5; i++) _text('$i')],
        {
          'items': [_text('5'), _text('6')],
          'cursor': 'c',
          'reset': false,
        },
        keep: 4,
      );
      expect(m.items.map((e) => e['s']), ['3', '4', '5', '6']);
    });
  });

  group('KantorTranscriptCache', () {
    KantorChatKey key(String sid) => (connection: 'c', office: 'o', sid: sid);
    KantorTranscriptSnap snap(int n) => KantorTranscriptSnap(
      items: [for (var i = 0; i < n; i++) _text('$i')],
      cursor: 'x',
      size: n,
      at: DateTime(2026),
    );

    test('drops the least recently used chat beyond maxChats', () {
      final c = KantorTranscriptCache(maxChats: 2);
      c.put(key('a'), snap(1));
      c.put(key('b'), snap(1));
      c.get(key('a')); // a becomes most recent
      c.put(key('c'), snap(1));
      expect(c.length, 2);
      expect(c.get(key('b')), isNull);
      expect(c.get(key('a')), isNotNull);
      expect(c.get(key('c')), isNotNull);
    });

    test('caps items per chat and clears fully', () {
      final c = KantorTranscriptCache(maxItems: 3);
      c.put(key('a'), snap(10));
      expect(c.get(key('a'))!.items.map((e) => e['s']), ['7', '8', '9']);
      c.clear();
      expect(c.length, 0);
    });
  });

  group('chat opened from cache', () {
    late HttpServer server;
    late KantorConfig config;
    final queries = <Map<String, String>>[];
    Completer<void>? hold;
    var fail = false;

    setUp(() async {
      queries.clear();
      hold = null;
      fail = false;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        Object body = [];
        var code = 200;
        if (req.uri.path.endsWith('/transcript')) {
          queries.add(req.uri.queryParameters);
          await hold?.future;
          if (fail) {
            code = 500;
            body = {'error': 'down'};
          } else {
            body = {
              'items': [_text('Pesan baru')],
              'cursor': 'c2',
              'reset': false,
              'size': 2,
            };
          }
        }
        req.response
          ..statusCode = code
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body))
          ..close();
      });
      config = KantorConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'test',
      );
    });
    tearDown(() => server.close(force: true));

    Future<ProviderContainer> pumpChat(
      WidgetTester t, {
      Stream<Map<String, dynamic>>? events,
    }) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': 's1', 'status': 'idle', 'tmux': 'x'},
          ],
        };
      addTearDown(feed.dispose);
      final c = ProviderContainer(
        overrides: [
          kantorApiProvider.overrideWith((ref) => KantorApi(config)),
          kantorEventsProvider.overrideWith(
            (ref) => events ?? const Stream.empty(),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(kantorTranscriptCacheProvider).put(
        (connection: kantorConnectionKey(config), office: 'o', sid: 's1'),
        KantorTranscriptSnap(
          items: [_text('Pesan lama')],
          cursor: 'c1',
          size: 1,
          at: DateTime(2026, 11, 16, 9, 5),
        ),
      );
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
      return c;
    }

    testWidgets('shows cached history at once, then appends only the delta', (
      t,
    ) async {
      hold = Completer<void>();
      await pumpChat(t);
      await t.pump();
      expect(find.textContaining('Pesan lama'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-sync-badge')), findsOneWidget);
      expect(find.text('Menyinkronkan…'), findsOneWidget);

      hold!.complete();
      await _settle(t);
      expect(queries.first['after'], 'c1');
      expect(queries.first['delta'], '1');
      expect(find.textContaining('Pesan lama'), findsOneWidget);
      expect(find.textContaining('Pesan baru'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-sync-badge')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 7)); // let HTTP timeouts lapse
    });

    testWidgets('says plainly when the cached history could not be refreshed', (
      t,
    ) async {
      fail = true;
      await pumpChat(t);
      await _settle(t);
      expect(find.textContaining('Pesan lama'), findsOneWidget);
      final badge = t.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('chat-sync-badge')),
          matching: find.byType(Text),
        ),
      );
      expect(badge.data, contains('Belum tersinkron'));
      expect(badge.data, contains('09:05'));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 7)); // let HTTP timeouts lapse
    });

    testWidgets('a transcript event fetches the delta right away', (t) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);
      final before = queries.length;
      events.add({'t': 'transcript', 'office': 'o', 'sid': 's1', 'size': 3});
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(queries.length, before + 1);
      expect(queries.last['after'], 'c2');
      events.add({'t': 'transcript', 'office': 'o', 'sid': 'other'});
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(queries.length, before + 1, reason: 'other chats are ignored');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 7));
    });

    testWidgets('no polling in the background, delta at once on resume', (
      t,
    ) async {
      await pumpChat(t);
      await _settle(t);
      final before = queries.length;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(seconds: 40));
      await _settle(t);
      expect(queries.length, before, reason: 'paused: no fetches');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(queries.length, before + 1);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(
        const Duration(seconds: 31),
      ); // receive timeout of the resume fetch
    });
  });
}
