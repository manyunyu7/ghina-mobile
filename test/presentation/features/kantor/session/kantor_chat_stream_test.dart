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
import 'package:ghina/presentation/features/kantor/session/chat_model.dart';
import 'package:ghina/presentation/features/kantor/session/chat_stream.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _text(String s) => {'k': 'text', 's': s};
Map<String, dynamic> _user(String s) => {'k': 'user', 's': s};

/// Beri waktu IO nyata (server lokal) lalu jalankan beberapa frame.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Beberapa frame supaya teks sementara selesai muncul bertahap.
Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

final _live = find.byKey(const ValueKey('chat-live'));

void main() {
  group('kantorStreamCovered', () {
    test('sama atau awalan pesan asisten terakhir: sudah final', () {
      final e = [
        const UserEntry('tanya', ''),
        const ClaudeEntry('**Halo**, ini jawaban\nyang panjang.', ''),
      ];
      expect(kantorStreamCovered('Halo, ini jawaban yang panjang.', e), isTrue);
      expect(kantorStreamCovered('Halo, ini jawa', e), isTrue);
      expect(kantorStreamCovered('Jawaban lain sama sekali', e), isFalse);
    });

    test('pesan asisten dari giliran sebelumnya tidak dihitung', () {
      final e = [
        const ClaudeEntry('Halo, ini jawaban lama', ''),
        const UserEntry('pertanyaan baru', ''),
      ];
      expect(kantorStreamCovered('Halo', e), isFalse);
    });
  });

  group('chat sedang menulis', () {
    late HttpServer server;
    late KantorConfig config;
    var watches = 0;
    var streams = 0;
    var transcripts = 0;
    var watchCode = 200;
    var streamCode = 200;
    Map<String, dynamic> streamBody = {'text': null, 'seq': 0};
    var next = <Map<String, dynamic>>[];
    var cursor = 2;

    setUp(() async {
      watches = 0;
      streams = 0;
      transcripts = 0;
      watchCode = 200;
      streamCode = 200;
      streamBody = {'text': null, 'seq': 0};
      next = [];
      cursor = 2;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        Object body = {};
        var code = 200;
        final path = req.uri.path;
        if (path.endsWith('/watch') && req.method == 'POST') {
          watches++;
          code = watchCode;
          body = code == 200 ? {'ok': true, 'ttl': 30} : {'error': 'x'};
        } else if (path.endsWith('/stream')) {
          streams++;
          code = streamCode;
          body = code == 200 ? streamBody : {'error': 'x'};
        } else if (path.endsWith('/transcript')) {
          transcripts++;
          final items = next;
          next = [];
          if (items.isNotEmpty) cursor++;
          body = {
            'items': items,
            'cursor': 'c$cursor',
            'reset': false,
            'size': cursor,
          };
        } else if (path.endsWith('/attachments')) {
          body = [];
        }
        await req.drain<void>();
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

    Future<void> pumpChat(
      WidgetTester t, {
      Stream<Map<String, dynamic>>? events,
      List<Map<String, dynamic>>? history,
      ValueNotifier<bool>? shown,
    }) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': 's1', 'status': 'working', 'tmux': 'x'},
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
          items: history ?? [_user('Tolong cek'), _text('Pesan lama')],
          cursor: 'c2',
          size: 2,
          at: DateTime(2026, 11, 17, 9),
        ),
      );
      final chat = KantorChatTab(feed: feed, sid: 's1');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(
              body: shown == null
                  ? chat
                  : ValueListenableBuilder<bool>(
                      valueListenable: shown,
                      builder: (_, on, child) =>
                          TickerMode(enabled: on, child: child!),
                      child: chat,
                    ),
            ),
          ),
        ),
      );
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 7));
      await t.pump(const Duration(seconds: 7));
    }

    Map<String, dynamic> ev(Object? text, int seq, {String sid = 's1'}) => {
      't': 'stream',
      'office': 'o',
      'sid': sid,
      'text': text,
      'seq': seq,
      'at': 0,
      if (text == null) 'done': true,
    };

    testWidgets('watch saat chat dibuka, diulang tiap 20 dtk, berhenti saat '
        'ditutup', (t) async {
      await pumpChat(t);
      await _settle(t);
      expect(watches, 1);
      expect(streams, 1, reason: 'keadaan awal diambil sekali');
      await t.pump(const Duration(seconds: 20));
      await _settle(t);
      expect(watches, 2);
      await t.pump(const Duration(seconds: 20));
      await _settle(t);
      expect(watches, 3);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 45));
      await _settle(t);
      expect(watches, 3, reason: 'chat ditutup: tidak ada watch lagi');
      await t.pump(const Duration(seconds: 7));
      await t.pump(const Duration(seconds: 7));
    });

    testWidgets('app di belakang atau tab lain: watch berhenti', (t) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await pumpChat(t, shown: shown);
      await _settle(t);
      expect(watches, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(seconds: 45));
      await _settle(t);
      expect(watches, 1, reason: 'paused: tidak ada watch');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(watches, 2, reason: 'kembali ke depan: watch langsung');

      shown.value = false; // pindah ke tab Terminal
      await t.pump();
      await t.pump(const Duration(seconds: 45));
      await _settle(t);
      expect(watches, 2, reason: 'tab lain: tidak ada watch');
      shown.value = true;
      await t.pump();
      await _settle(t);
      expect(watches, 3);
      await close(t);
    });

    testWidgets('event stream menampilkan bubble sedang menulis yang tumbuh; '
        'seq lama dan sid lain diabaikan; done menghapus', (t) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);
      expect(_live, findsNothing);

      events.add(ev('Baik, saya cek dulu', 5));
      await _frames(t);
      expect(_live, findsOneWidget);
      expect(find.text('sedang menulis…'), findsOneWidget);
      expect(find.textContaining('Baik, saya cek dulu'), findsOneWidget);

      events.add(ev('Baik, saya cek dulu berkasnya.\n\n    kode()', 6));
      await _frames(t);
      expect(find.textContaining('saya cek dulu berkasnya.'), findsOneWidget);
      expect(find.textContaining('kode()'), findsOneWidget);

      events.add(ev('Teks basi', 4));
      await _frames(t);
      expect(find.textContaining('Teks basi'), findsNothing);
      expect(find.textContaining('berkasnya.'), findsOneWidget);

      events.add(ev('Sesi lain menulis', 9, sid: 's2'));
      await _frames(t);
      expect(find.textContaining('Sesi lain'), findsNothing);

      final fetched = transcripts;
      events.add(ev(null, 7));
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(transcripts, fetched + 1, reason: 'done: jawaban final dicari');
      await t.pump(const Duration(seconds: 2));
      expect(_live, findsNothing);
      expect(find.text('sedang menulis…'), findsNothing);
      await close(t);
    });

    testWidgets('jawaban final lewat transkrip menggantikan bubble', (t) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);

      events.add(ev('Sudah saya perbaiki di dua', 1));
      await _frames(t);
      expect(_live, findsOneWidget);

      next = [_text('Sudah saya perbaiki di dua tempat.')];
      events.add({'t': 'transcript', 'office': 'o', 'sid': 's1'});
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(_live, findsNothing);
      expect(find.text('sedang menulis…'), findsNothing);
      expect(
        find.textContaining('Sudah saya perbaiki di dua tempat.'),
        findsOneWidget,
      );

      // layar terminal tertinggal: teks lama datang lagi, tidak ditampilkan
      events.add(ev('Sudah saya perbaiki di dua tempat.', 2));
      await _frames(t);
      expect(_live, findsNothing);
      await close(t);
    });

    testWidgets('keadaan awal dari GET /stream; sama dengan pesan terakhir '
        'tidak ditampilkan', (t) async {
      streamBody = {'text': 'Sedang menyusun ringkasan', 'seq': 3, 'at': 0};
      await pumpChat(t);
      await _settle(t);
      await _frames(t);
      expect(_live, findsOneWidget);
      expect(find.textContaining('Sedang menyusun ringkasan'), findsOneWidget);
      await close(t);

      streamBody = {'text': 'Pesan lama', 'seq': 3, 'at': 0};
      await pumpChat(t);
      await _settle(t);
      await _frames(t);
      expect(_live, findsNothing);
      await close(t);
    });

    testWidgets('daemon lama (404 watch dan stream): diam, tidak diulang', (
      t,
    ) async {
      watchCode = 404;
      streamCode = 404;
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);
      expect(watches, 1);
      expect(streams, 1);
      await t.pump(const Duration(seconds: 45));
      await _settle(t);
      expect(watches, 1, reason: '404: tidak diulang');
      expect(_live, findsNothing);
      expect(t.takeException(), isNull);
      expect(find.textContaining('Pesan lama'), findsOneWidget);
      await close(t);
    });

    testWidgets('membaca ke atas: tidak dipaksa turun, ada tombol '
        'sedang menulis', (t) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(
        t,
        events: events.stream,
        history: [
          for (var i = 0; i < 30; i++)
            _text('Pesan nomor $i dengan isi yang cukup panjang untuk baris.'),
        ],
      );
      await _settle(t);
      await t.drag(
        find.byKey(const ValueKey('chat-list')),
        const Offset(0, 400),
      );
      await t.pump(const Duration(milliseconds: 500));
      final list = find.byKey(const ValueKey('chat-list'));
      final pos = t.widget<ListView>(list).controller!.position;
      final before = pos.pixels;
      expect(before, greaterThan(40));

      events.add(ev('Jawaban baru sedang diketik', 1));
      await _frames(t);
      expect(_live, findsNothing, reason: 'tidak menggeser yang sedang dibaca');
      expect(pos.pixels, before);
      final jump = find.byKey(const ValueKey('chat-live-jump'));
      expect(jump, findsOneWidget);

      await t.tap(jump);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await _frames(t);
      expect(pos.pixels, 0);
      expect(_live, findsOneWidget);
      expect(jump, findsNothing);
      await close(t);
    });
  });
}
