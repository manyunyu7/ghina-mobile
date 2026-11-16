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

/// Absolute sequence numbers [from, to) as text items `Pesan <n>`.
List<Map<String, dynamic>> _seq(int from, int to) => [
  for (var i = from; i < to; i++) _text('Pesan $i'),
];

List<String> _names(List<Map<String, dynamic>> l) => [
  for (final e in l) '${e['s']}',
];

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Lets real HTTP round trips finish until [done] holds (bounded).
Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

KantorTranscriptWindow _win(
  List<Map<String, dynamic>> items, {
  int? first,
  String? gen,
  bool older = false,
  String? cursor = 'c',
}) => (items: items, cursor: cursor, first: first, gen: gen, older: older);

void main() {
  group('applyTranscriptDelta', () {
    test('whole tail takes first/gen/older from the answer', () {
      final m = applyTranscriptDelta(null, {
        'items': _seq(60, 100),
        'cursor': 'c1',
        'reset': true,
        'first': 60,
        'gen': 'g1',
        'older': true,
      });
      expect(m.window.first, 60);
      expect(m.window.gen, 'g1');
      expect(m.window.older, isTrue);
      expect(m.window.cursor, 'c1');
      expect(m.window.items.length, 40);
    });

    test('delta keeps the start of the held window', () {
      final m = applyTranscriptDelta(
        _win(_seq(60, 100), first: 60, gen: 'g1', older: true),
        {
          'items': _seq(100, 102),
          'cursor': 'c2',
          'reset': false,
          'first': 100,
          'gen': 'g1',
          'older': true,
        },
      );
      expect(m.changed, isTrue);
      expect(m.window.first, 60);
      expect(m.window.gen, 'g1');
      expect(m.window.older, isTrue);
      expect(_names(m.window.items).last, 'Pesan 101');
    });

    test('trimming to keep moves first forward and sets older', () {
      final m = applyTranscriptDelta(_win(_seq(0, 5), first: 0, gen: 'g'), {
        'items': _seq(5, 7),
        'cursor': 'c',
        'reset': false,
      }, keep: 4);
      expect(_names(m.window.items), [
        'Pesan 3',
        'Pesan 4',
        'Pesan 5',
        'Pesan 6',
      ]);
      expect(m.window.first, 3);
      expect(m.window.older, isTrue);
    });

    test('reset replaces items and paging position', () {
      final m = applyTranscriptDelta(
        _win(_seq(60, 100), first: 60, gen: 'g1', older: true),
        {
          'items': _seq(0, 3),
          'cursor': 'n1',
          'reset': true,
          'first': 0,
          'gen': 'g2',
          'older': false,
        },
      );
      expect(m.window.first, 0);
      expect(m.window.gen, 'g2');
      expect(m.window.older, isFalse);
      expect(m.window.items.length, 3);
    });

    test('empty delta keeps items, reports no change', () {
      final held = _seq(10, 12);
      final m = applyTranscriptDelta(
        _win(held, first: 10, gen: 'g', older: true),
        {'items': <Object>[], 'cursor': 'c9', 'reset': false},
      );
      expect(identical(m.window.items, held), isTrue);
      expect(m.changed, isFalse);
      expect(m.window.cursor, 'c9');
      expect(m.window.first, 10);
      expect(m.window.older, isTrue);
    });

    test('held window without paging info is placed by the delta', () {
      final m = applyTranscriptDelta(_win(_seq(50, 60)), {
        'items': _seq(60, 61),
        'cursor': 'c',
        'reset': false,
        'first': 60,
        'gen': 'g',
      });
      expect(m.window.first, 50);
      expect(m.window.older, isTrue);
      expect(m.window.gen, 'g');
    });

    test('old daemon without paging fields: no paging', () {
      final m = applyTranscriptDelta(null, {
        'items': _seq(0, 3),
        'cursor': 'c',
        'reset': true,
      });
      expect(m.window.first, isNull);
      expect(m.window.gen, isNull);
      expect(m.window.older, isFalse);
    });
  });

  group('prependTranscript', () {
    test('older page goes in front and moves first back', () {
      final m = prependTranscript(
        _win(_seq(60, 100), first: 60, gen: 'g1', older: true),
        {'items': _seq(20, 60), 'first': 20, 'gen': 'g1', 'older': true},
      );
      expect(m.changed, isTrue);
      expect(m.window.items.length, 80);
      expect(_names(m.window.items).first, 'Pesan 20');
      expect(m.window.first, 20);
      expect(m.window.older, isTrue);
      expect(m.window.cursor, 'c');
    });

    test('the last page stops paging', () {
      final m = prependTranscript(
        _win(_seq(10, 20), first: 10, gen: 'g', older: true),
        {'items': _seq(0, 10), 'first': 0, 'gen': 'g', 'older': false},
      );
      expect(m.window.first, 0);
      expect(m.window.older, isFalse);
    });

    test('reset keeps the items and stops paging', () {
      final held = _seq(60, 100);
      final m = prependTranscript(
        _win(held, first: 60, gen: 'g1', older: true),
        {'items': <Object>[], 'reset': true, 'gen': 'g2'},
      );
      expect(m.changed, isFalse);
      expect(identical(m.window.items, held), isTrue);
      expect(m.window.first, 60);
      expect(m.window.gen, 'g1');
      expect(m.window.older, isFalse);
    });

    test('overlap is dropped, a gap is refused', () {
      final held = _win(_seq(60, 100), first: 60, gen: 'g', older: true);
      final overlap = prependTranscript(held, {
        'items': _seq(30, 65),
        'first': 30,
        'gen': 'g',
        'older': true,
      });
      expect(overlap.window.items.length, 70);
      expect(overlap.window.first, 30);
      expect(_names(overlap.window.items)[29], 'Pesan 59');
      expect(_names(overlap.window.items)[30], 'Pesan 60');

      final gap = prependTranscript(held, {
        'items': _seq(10, 20),
        'first': 10,
        'gen': 'g',
        'older': true,
      });
      expect(gap.changed, isFalse);
      expect(gap.window.first, 60);
      expect(gap.window.older, isFalse);
    });

    test('cache trims a long window to the newest items and moves first', () {
      final c = KantorTranscriptCache(maxItems: 200);
      const k = (connection: 'c', office: 'o', sid: 's');
      c.put(
        k,
        KantorTranscriptSnap(
          items: _seq(0, 240),
          cursor: 'x',
          size: 240,
          at: DateTime(2026),
          first: 0,
          gen: 'g',
        ),
      );
      final s = c.get(k)!;
      expect(s.items.length, 200);
      expect(s.first, 40);
      expect(s.older, isTrue);
      expect(s.gen, 'g');
    });
  });

  group('chat open', () {
    late HttpServer server;
    late KantorConfig config;
    final hits = <String>[];
    final queries = <String, List<Map<String, String>>>{};
    var hasOpen = true;
    var beforeReset = false;
    Completer<void>? holdBefore;

    setUp(() async {
      hits.clear();
      queries.clear();
      hasOpen = true;
      beforeReset = false;
      holdBefore = null;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        final q = req.uri.queryParameters;
        final name = path.split('/').last;
        hits.add(name);
        (queries[name] ??= []).add(q);
        Object body = {};
        var code = 200;
        final tail = {
          'items': _seq(60, 100),
          'cursor': 'c1',
          'reset': true,
          'size': 100,
          'first': 60,
          'gen': 'g1',
          'older': true,
        };
        if (name == 'open') {
          if (hasOpen) {
            body = {'transcript': tail, 'attachments': [], 'session': null};
          } else {
            code = 404;
            body = {'error': 'not found'};
          }
        } else if (name == 'transcript') {
          if (q['before'] != null) {
            await holdBefore?.future;
            final b = int.parse(q['before']!);
            body = beforeReset
                ? {'items': [], 'reset': true, 'gen': 'g2'}
                : {
                    'items': _seq(b - 40 < 0 ? 0 : b - 40, b),
                    'first': b - 40 < 0 ? 0 : b - 40,
                    'gen': 'g1',
                    'older': b - 40 > 0,
                  };
          } else {
            body = q['after'] == null
                ? tail
                : {
                    'items': [],
                    'cursor': 'c1',
                    'reset': false,
                    'size': 100,
                    'gen': 'g1',
                  };
          }
        } else if (name == 'attachments') {
          body = [];
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
      ProviderContainer? container,
      String sid = 's1',
    }) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': sid, 'status': 'idle', 'tmux': 'x'},
          ],
        };
      addTearDown(feed.dispose);
      final c =
          container ??
          ProviderContainer(
            overrides: [
              kantorApiProvider.overrideWith((ref) => KantorApi(config)),
              kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
            ],
          );
      if (container == null) addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              body: KantorChatTab(key: ValueKey(sid), feed: feed, sid: sid),
            ),
          ),
        ),
      );
      return c;
    }

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 31));
    }

    testWidgets('first open asks /open for 40 items, attachments included', (
      t,
    ) async {
      final c = await pumpChat(t);
      await _until(
        t,
        () => find.textContaining('Pesan 99').evaluate().isNotEmpty,
      );
      await _settle(t);
      expect(hits.first, 'open');
      expect(queries['open']!.first['n'], '40');
      expect(queries['open']!.first.containsKey('after'), isFalse);
      expect(queries['attachments'], isNull, reason: 'came with /open');
      expect(
        queries['transcript']?.where((q) => q['before'] == null),
        anyOf(isNull, isEmpty),
      );
      expect(find.textContaining('Pesan 99'), findsOneWidget);
      final key = (
        connection: kantorConnectionKey(config),
        office: 'o',
        sid: 's1',
      );
      final snap = c.read(kantorTranscriptCacheProvider).peek(key)!;
      expect(snap.items.length, 40);
      expect(snap.first, 60);
      expect(snap.gen, 'g1');
      expect(snap.older, isTrue);
      expect(kantorChatTimings[key]!.first.source, 'open');
      expect(kantorChatTimings[key]!.first.items, 40);
      expect(kantorChatTimings[key]!.first.network, isNotNull);
      expect(kantorChatTimings[key]!.first.shown, isNotNull);
      await end(t);
    });

    testWidgets('old daemon: /open 404 falls back and is not asked again', (
      t,
    ) async {
      hasOpen = false;
      final c = await pumpChat(t);
      await _until(t, () => queries['transcript'] != null);
      await _settle(t);
      expect(hits.where((h) => h == 'open').length, 1);
      final tq = queries['transcript']!.first;
      expect(tq['n'], '200');
      expect(tq['delta'], '1');
      expect(queries['attachments'], isNotNull);
      expect(find.textContaining('Pesan 99'), findsOneWidget);

      // another chat on the same connection goes straight to /transcript
      c.read(kantorTranscriptCacheProvider).clear();
      final before = queries['transcript']!.length;
      await pumpChat(t, container: c, sid: 's2');
      await _until(t, () => queries['transcript']!.length > before);
      await _settle(t);
      expect(hits.where((h) => h == 'open').length, 1);
      expect(queries['transcript']!.length, before + 1);
      await end(t);
    });

    testWidgets('scrolling up pages older items in front without a jump', (
      t,
    ) async {
      holdBefore = Completer<void>();
      await pumpChat(t);
      await _until(
        t,
        () => find.textContaining('Pesan 99').evaluate().isNotEmpty,
      );
      await _settle(t);
      final list = find.byKey(const ValueKey('chat-list'));
      // scroll towards the oldest end (reversed list: drag down)
      for (var i = 0; i < 12; i++) {
        await t.drag(list, const Offset(0, 400));
        await t.pump();
      }
      await _until(
        t,
        () => (queries['transcript'] ?? []).any((q) => q['before'] != null),
      );
      expect(
        queries['transcript']!.where((q) => q['before'] != null).length,
        1,
      );
      final bq = queries['transcript']!.firstWhere((q) => q['before'] != null);
      expect(bq['before'], '60');
      expect(bq['gen'], 'g1');
      expect(bq['n'], '40');
      expect(find.text('memuat pesan lama…'), findsOneWidget);

      // let the last fling come to rest before measuring
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      final anchor = find.textContaining('Pesan 61');
      expect(anchor, findsOneWidget);
      final y0 = t.getTopLeft(anchor).dy;
      holdBefore!.complete();
      await _until(t, () => find.text('memuat pesan lama…').evaluate().isEmpty);
      await _settle(t);
      expect(t.getTopLeft(anchor).dy, y0, reason: 'scroll position kept');
      expect(find.text('memuat pesan lama…'), findsNothing);

      for (var i = 0; i < 20; i++) {
        await t.drag(list, const Offset(0, 400));
        await t.pump();
      }
      await _settle(t);
      expect(find.textContaining('Pesan 20'), findsWidgets);
      await end(t);
    });

    testWidgets('a reset answer to before keeps the chat and stops paging', (
      t,
    ) async {
      beforeReset = true;
      await pumpChat(t);
      await _until(
        t,
        () => find.textContaining('Pesan 99').evaluate().isNotEmpty,
      );
      await _settle(t);
      final list = find.byKey(const ValueKey('chat-list'));
      for (var i = 0; i < 12; i++) {
        await t.drag(list, const Offset(0, 400));
        await t.pump();
      }
      await _settle(t);
      expect(
        queries['transcript']!.where((q) => q['before'] != null).length,
        1,
      );
      expect(find.textContaining('Pesan 60'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await t.drag(list, const Offset(0, 400));
        await t.pump();
      }
      await _settle(t);
      expect(
        queries['transcript']!.where((q) => q['before'] != null).length,
        1,
        reason: 'no more paging after reset',
      );
      expect(find.textContaining('Pesan 60'), findsOneWidget);
      await end(t);
    });
  });
}
