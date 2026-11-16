import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_offline_cache_tile.dart';
import 'package:ghina/presentation/features/kantor/session/chat_context.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_snapshot_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _conn = 'conn-a';

Map<String, dynamic> _text(String s) => {'k': 'text', 's': s};

KantorTranscriptSnap _snap(int n, {int? first = 100, String pad = ''}) =>
    KantorTranscriptSnap(
      items: [for (var i = 0; i < n; i++) _text('m$i$pad')],
      cursor: 'c$n',
      size: n,
      at: DateTime(2026, 11, 16),
      first: first,
      gen: 'g1',
    );

KantorChatKey _key(String sid, [String office = 'o']) =>
    (connection: _conn, office: office, sid: sid);

Map<String, dynamic> _office() => {
  'id': 'o',
  'name': 'Kantor O',
  'roles': [
    {'id': 'a', 'name': 'Ayu', 'title': 'Backend'},
    {'id': 'b', 'name': 'Budi', 'title': 'QA'},
  ],
  'sessions': [
    {
      'sid': 's1',
      'role': 'a',
      'status': 'working',
      'tmux': 'x',
      'tool': {'name': 'Bash', 'label': 'flutter test'},
    },
    {
      'sid': 's2',
      'role': 'b',
      'status': 'waiting',
      'tmux': 'y',
      'waiting': {'tool': 'Bash', 'summary': 'rm -rf build'},
      'konteks': {
        'state': {'k': 'izin', 'label': 'Minta izin'},
        'reply': {'s': 'Sudah kucek'},
        'draft': {'title': 'Laporan', 'siap': true},
      },
    },
    {'sid': 's3', 'role': 'a', 'status': 'ended'},
  ],
  'inbox': [
    {'id': 'i1', 'sid': 's2'},
  ],
};

void main() {
  late Directory tmp;
  var now = 0;
  const day = 24 * 3600 * 1000;
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(1000000000 + now++);

  KantorSnapshotStore store({int maxBytes = kantorSnapshotMaxBytes}) =>
      KantorSnapshotStore(
        root: () async => Directory(p.join(tmp.path, 'kantor_snapshot')),
        maxBytes: maxBytes,
        debounce: const Duration(milliseconds: 1),
        clock: clock,
      );

  Directory connDir([String c = _conn]) =>
      Directory(p.join(tmp.path, 'kantor_snapshot', c));

  List<String> chatFiles() => [
    for (final f in connDir().listSync())
      if (p.basename(f.path).startsWith('c_')) p.basename(f.path),
  ];

  final rnd = Random(1);
  String noise() => String.fromCharCodes([
    for (var i = 0; i < 600; i++) 33 + rnd.nextInt(90),
  ]);
  // ~24 KB gzip (random text does not compress much)
  KantorTranscriptSnap big() => KantorTranscriptSnap(
    items: [for (var i = 0; i < 40; i++) _text(noise())],
    cursor: null,
    size: null,
    at: DateTime(2026),
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kantor_snap_');
    now = 0;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('defaults: 50 MB, 40 chats x 200 items, 20 back in memory', () {
    expect(kantorSnapshotMaxBytes, 50 * 1024 * 1024);
    expect(kantorSnapshotMaxChats, 40);
    expect(kantorSnapshotMaxItems, 200);
    expect(kantorSnapshotWarmChats, 20);
  });

  test('keeps 40 chats of the last 200 items; 20 most recent come back '
      'into memory, the rest is read when opened', () async {
    final s = store();
    await s.activate(_conn);
    for (var i = 0; i < 45; i++) {
      s.putChat(_key('s$i'), _snap(300));
    }
    await s.flush();
    expect(chatFiles(), hasLength(40));

    final again = store();
    final cache = KantorTranscriptCache(maxChats: 24);
    again.attachCache(cache);
    await again.activate(_conn);
    final keys = again.chatKeys;
    expect(keys, hasLength(40));
    // least recently used first; s0..s4 were dropped
    expect(keys.first.sid, 's5');
    expect(keys.last.sid, 's44');
    expect(cache.length, 20);
    expect(cache.peek(_key('s44')), isNotNull);
    expect(cache.peek(_key('s24')), isNull);

    final snap = cache.peek(_key('s44'))!;
    expect(snap.items, hasLength(200));
    expect(snap.items.first['s'], 'm100');
    expect(snap.first, 200);
    expect(snap.older, isTrue);
    expect(snap.cursor, 'c300');
    expect(snap.gen, 'g1');

    // on disk but not in memory: warm() makes get() show it at once
    expect(await again.warm(_key('s10')), isTrue);
    expect(cache.get(_key('s10'))!.items, hasLength(200));
    expect(again.usedBytes.value, greaterThan(0));
  });

  test('size limit: ended chats not opened for 24 h go first, then LRU '
      'chats, offices last', () async {
    final s = store(maxBytes: 60 * 1024);
    await s.activate(_conn);
    s.putChat(_key('lru'), big()); // oldest, session still live
    s.putChat(_key('gone'), big()); // newer, but its session ended
    s.putOffice('o', {
      'id': 'o',
      'sessions': [
        {'sid': 'lru', 'status': 'idle'},
        {'sid': 'fresh', 'status': 'idle'},
      ],
    });
    await s.flush();
    expect(s.isEnded(_key('gone')), isTrue);
    expect(s.isEnded(_key('lru')), isFalse);
    expect(chatFiles(), hasLength(2)); // ended but it fits: still there
    expect(await s.warm(_key('gone')), isFalse); // no cache attached

    now += 2 * day;
    s.putChat(_key('fresh'), big());
    await s.flush();
    var sids = s.chatKeys.map((e) => e.sid).toList();
    expect(sids, ['lru', 'fresh']); // 'gone' went first though newer
    expect(s.office('o'), isNotNull);

    s.putChat(_key('newest'), big());
    await s.flush();
    sids = s.chatKeys.map((e) => e.sid).toList();
    expect(sids, ['fresh', 'newest']); // then the least recently used
    expect(s.office('o'), isNotNull); // offices only after chats

    final total = connDir().listSync().whereType<File>().fold<int>(
      0,
      (a, f) => a + f.lengthSync(),
    );
    expect(total, lessThanOrEqualTo(60 * 1024));
    expect(s.usedBytes.value, total);
  });

  test('an ended chat opened within 24 h is not the first to go', () async {
    final s = store(maxBytes: 60 * 1024);
    await s.activate(_conn);
    s.putChat(_key('lru'), big());
    s.putChat(_key('gone'), big());
    s.markEnded('o', 'gone'); // e.g. session-gone from the live feed
    await s.flush();
    expect(s.isEnded(_key('gone')), isTrue);
    s.putChat(_key('fresh'), big());
    await s.flush();
    expect(s.chatKeys.map((e) => e.sid), ['gone', 'fresh']);
  });

  test('offices: every office is kept', () async {
    final s = store();
    await s.activate(_conn);
    for (var i = 0; i < 15; i++) {
      s.putOffice('k$i', {'id': 'k$i'});
    }
    await s.flush();
    final again = store();
    await again.activate(_conn);
    expect([
      for (var i = 0; i < 15; i++) again.office('k$i') != null,
    ], everyElement(isTrue));
  });

  test('switching connection deletes the other folders', () async {
    final s = store();
    await s.activate(_conn);
    s.putChat(_key('s1'), _snap(3));
    await s.flush();
    expect(connDir().existsSync(), isTrue);

    await s.activate('conn-b');
    expect(connDir().existsSync(), isFalse);
    expect(connDir('conn-b').existsSync(), isTrue);
    expect(s.chatKeys, isEmpty);
    // a put for the old connection is not written under the new one
    s.putChat(_key('s1'), _snap(3));
    await s.flush();
    expect(
      connDir('conn-b').listSync().where((f) => f.path.endsWith('.gz')),
      isEmpty,
    );
  });

  test(
    'unreadable files are ignored (and removed), the rest is read',
    () async {
      final s = store();
      await s.activate(_conn);
      s.putChat(_key('good'), _snap(2));
      await s.flush();
      File(p.join(connDir().path, 'c_broken.json.gz')).writeAsStringSync('xx');
      File(
        p.join(connDir().path, 'c_badjson.json.gz'),
      ).writeAsBytesSync(gzip.encode(utf8.encode('{"v":1')));
      File(p.join(connDir().path, 'o_x.json.gz.tmp')).writeAsStringSync('half');
      File(p.join(connDir().path, 'index.json')).writeAsStringSync('{broken');

      final again = store();
      await again.activate(_conn);
      expect(again.chatKeys.map((e) => e.sid), ['good']);
      expect(chatFiles(), hasLength(1));
      expect(
        connDir().listSync().map((f) => p.basename(f.path)),
        isNot(contains('o_x.json.gz.tmp')),
      );
      await again.flush(); // the index is rebuilt
      final third = store();
      await third.activate(_conn);
      expect(third.chatKeys.map((e) => e.sid), ['good']);
    },
  );

  test(
    'office snapshot: neutral, no inbox; state keeps the office list only',
    () async {
      final s = store();
      await s.activate(_conn);
      s.putOffice('o', _office());
      s.putState({
        'offices': [
          {
            'id': 'o',
            'name': 'Kantor O',
            'fav': true,
            'sessions': [
              {'status': 'working'},
            ],
          },
        ],
        'inbox': [
          {'id': 'i1'},
        ],
        'settings': {'x': 1},
      });
      await s.flush();
      final raw = connDir()
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gz'))
          .map((f) => utf8.decode(gzip.decode(f.readAsBytesSync())))
          .join();
      expect(raw, isNot(contains('waiting')));
      expect(raw, isNot(contains('rm -rf')));
      expect(raw, isNot(contains('"inbox"')));
      expect(raw, isNot(contains('settings')));

      final again = store();
      await again.activate(_conn);
      final o = again.office('o')!;
      final sessions = asJsonList(o['sessions']);
      expect(sessions.map((e) => e['status']), ['', '', 'ended']);
      expect(sessions[1]['konteks']['state']['k'], 'sinkron');
      expect(sessions[1]['konteks']['reply']['s'], 'Sudah kucek');
      expect(sessions[1]['konteks']['draft'], isNull);
      expect(again.state!['offices'][0]['fav'], isTrue);
      expect(again.state!['offices'][0]['sessions'], isNull);
    },
  );

  test('clearAll empties disk and the memory cache', () async {
    final s = store();
    final cache = KantorTranscriptCache();
    s.attachCache(cache);
    await s.activate(_conn);
    cache.put(_key('s1'), _snap(5)); // written through onPut
    await s.flush();
    expect(s.usedBytes.value, greaterThan(0));
    expect(connDir().listSync(), isNotEmpty);

    await s.clearAll();
    expect(s.usedBytes.value, 0);
    expect(cache.length, 0);
    expect(connDir().existsSync() ? connDir().listSync() : [], isEmpty);
    expect(s.chatKeys, isEmpty);
  });

  test('seed puts disk chats under the ones already opened', () {
    final cache = KantorTranscriptCache(maxChats: 3);
    cache.put(_key('fresh'), _snap(1));
    cache.seed([
      (_key('d1'), _snap(1)),
      (_key('d2'), _snap(1)),
      (_key('d3'), _snap(1)),
      (_key('fresh'), _snap(9)),
    ]);
    expect(cache.length, 3);
    expect(cache.peek(_key('d1')), isNull); // oldest dropped
    expect(cache.peek(_key('fresh'))!.items, hasLength(1)); // not replaced
    expect(cache.peek(_key('d3')), isNotNull);
  });

  group('feed from disk', () {
    late HttpServer server;
    late KantorConfig config;
    var fail = false;

    setUp(() async {
      fail = false;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        Object body = <Object>[];
        var code = 200;
        if (fail) {
          code = 500;
          body = {'error': 'down'};
        } else if (req.uri.path == '/api/offices/o') {
          body = {
            'id': 'o',
            'name': 'Kantor O',
            'roles': <Object>[],
            'sessions': [
              {'sid': 's1', 'status': 'working'},
            ],
          };
        } else if (req.uri.path == '/api/inbox') {
          body = [
            {'id': 'i9', 'office': 'o', 'sid': 's1'},
          ];
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
        token: 'rahasia-token',
      );
      // an earlier run left this office on disk
      final seed = store();
      await seed.activate(kantorConnectionKey(config));
      seed.putOffice('o', _office());
      seed.putChat((
        connection: kantorConnectionKey(config),
        office: 'o',
        sid: 's1',
      ), _snap(3));
      await seed.flush();
    });
    tearDown(() => server.close(force: true));

    Future<ProviderContainer> container() async {
      final c = ProviderContainer(
        overrides: [
          kantorSnapshotRootProvider.overrideWithValue(
            () async => Directory(p.join(tmp.path, 'kantor_snapshot')),
          ),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(c.dispose);
      await c
          .read(kantorConfigProvider.notifier)
          .save(baseUrl: config.baseUrl, token: config.token);
      await c.read(kantorSnapshotStoreProvider).ready;
      return c;
    }

    test('shows neutral agents and no inbox until load succeeds', () async {
      fail = true;
      final c = await container();
      final feed = c.read(kantorOfficeFeedProvider('o'));
      await c.read(kantorSnapshotStoreProvider).ready;
      await Future<void>.delayed(Duration.zero);
      expect(feed.fromDisk, isTrue);
      expect(feed.loading, isFalse);
      expect(feed.inbox, isEmpty);
      expect(feed.sessions.map((s) => s['status']), ['', '', 'ended']);
      expect(feed.sessions.any((s) => s['waiting'] != null), isFalse);
      // the disk tail of the chat is in the memory cache
      final cache = c.read(kantorTranscriptCacheProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        cache.peek((
          connection: kantorConnectionKey(config),
          office: 'o',
          sid: 's1',
        ))?.items,
        hasLength(3),
      );
      // no token in any path or file
      final all = tmp.listSync(recursive: true);
      for (final f in all) {
        expect(f.path, isNot(contains('rahasia')));
        if (f is File) {
          final bytes = f.readAsBytesSync();
          expect(
            utf8.decode(f.path.endsWith('.gz') ? gzip.decode(bytes) : bytes),
            isNot(contains('rahasia')),
          );
        }
      }

      await feed.load(); // the daemon is down: still neutral
      expect(feed.fromDisk, isTrue);
      expect(feed.sessions.first['status'], '');

      fail = false;
      await feed.load();
      expect(feed.fromDisk, isFalse);
      expect(feed.sessions.single['status'], 'working');
      expect(feed.inbox.single['id'], 'i9');

      // the live feed says the session ended: a removal candidate, kept
      final store = c.read(kantorSnapshotStoreProvider);
      final key = (
        connection: kantorConnectionKey(config),
        office: 'o',
        sid: 's1',
      );
      expect(store.isEnded(key), isFalse);
      feed.apply({'t': 'session-gone', 'office': 'o', 'sid': 's1'});
      expect(store.isEnded(key), isTrue);
      expect(store.chatKeys, contains(key));
    });
  });

  testWidgets('agents tab from disk: no statuses, no permission, no actions', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final feed = KantorOfficeFeed('o', null)..hydrate(_office());
    addTearDown(feed.dispose);
    expect(feed.fromDisk, isTrue);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
          kantorSnapshotRootProvider.overrideWithValue(() async => null),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: KantorAgentsTab(officeId: 'o')),
        ),
      ),
    );
    await t.pump();
    expect(find.text('MENYINKRONKAN'), findsOneWidget);
    expect(find.text('BEKERJA'), findsNothing);
    expect(find.text('MENUNGGU KAMU'), findsNothing);
    expect(find.textContaining('rm -rf'), findsNothing);
    expect(find.textContaining('Ketuk untuk mulai shift'), findsNothing);
  });

  testWidgets('settings row shows the size and clears the cache', (t) async {
    late KantorSnapshotStore s;
    await t.runAsync(() async {
      s = store();
      await s.activate(_conn);
      s.putChat(_key('s1'), _snap(30, pad: 'x' * 200));
      await s.flush();
    });
    expect(s.usedBytes.value, greaterThan(0));
    await t.pumpWidget(
      ProviderScope(
        overrides: [kantorSnapshotStoreProvider.overrideWithValue(s)],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: KantorOfflineCacheTile()),
        ),
      ),
    );
    expect(find.text('Cache offline'), findsOneWidget);
    expect(find.textContaining('KB dari 50 MB'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Hapus cache'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(s.usedBytes.value, 0);
    expect(find.textContaining('0 KB dari 50 MB'), findsOneWidget);
    expect(find.text('Cache offline dihapus'), findsOneWidget);
  });

  test('size text uses an Indonesian decimal comma', () {
    expect(kantorCacheSize(0), '0 KB');
    expect(kantorCacheSize(1258291), '1,2 MB');
    expect(kantorCacheSize(50 * 1024 * 1024), '50 MB');
  });
}
