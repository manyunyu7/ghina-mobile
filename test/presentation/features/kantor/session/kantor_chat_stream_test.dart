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
import 'package:ghina/presentation/features/kantor/widgets/kantor_markdown.dart';
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

/// Beberapa frame supaya teks sementara selesai muncul bertahap (laju dasar
/// ±50 grafem/dtk, sisa teks terkejar dalam ±0,9 dtk).
Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

final _live = find.byKey(const ValueKey('chat-live'));

/// Teks markdown yang tampil di bubble sementara (isi terbaru saat crossfade).
String _shown(WidgetTester t) {
  final md = find.byKey(const ValueKey('chat-live-md'));
  if (md.evaluate().isEmpty) return '';
  return t
      .widgetList<RichText>(
        find.descendant(of: md.last, matching: find.byType(RichText)),
      )
      .map((r) => r.text.toPlainText(includePlaceholders: false))
      .join('\n');
}

/// Semua TextSpan berisi teks di bubble sementara.
List<TextSpan> _spans(WidgetTester t) {
  final out = <TextSpan>[];
  for (final r in t.widgetList<RichText>(
    find.descendant(
      of: find.byKey(const ValueKey('chat-live-md')).last,
      matching: find.byType(RichText),
    ),
  )) {
    r.text.visitChildren((s) {
      if (s is TextSpan && (s.text ?? '').isNotEmpty) out.add(s);
      return true;
    });
  }
  return out;
}

Future<void> _pumpLive(
  WidgetTester t,
  String text, {
  bool animate = true,
  bool partial = false,
}) => t.pumpWidget(
  MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: KantorLiveText(text: text, animate: animate, partial: partial),
      ),
    ),
  ),
);

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

  group('kantorLiveMarkdown', () {
    test('penanda terbuka di ekor ditutup sementara', () {
      expect(kantorLiveMarkdown('Ini **teb'), 'Ini **teb**');
      expect(kantorLiveMarkdown('Ini *mir'), 'Ini *mir*');
      expect(kantorLiveMarkdown('pakai `kod'), 'pakai `kod`');
      expect(
        kantorLiveMarkdown('```dart\nvar a = 1;'),
        '```dart\nvar a = 1;\n```',
      );
      expect(
        kantorLiveMarkdown('lihat [docs](https://ex'),
        'lihat [docs](https://ex)',
      );
      expect(kantorLiveMarkdown('**a `b'), '**a `b`**');
      expect(kantorLiveMarkdown('* butir **teb'), '* butir **teb**');
    });

    test('pembuka tanpa isi dibuang, yang sudah lengkap tidak diubah', () {
      expect(kantorLiveMarkdown('Ini **'), 'Ini');
      expect(kantorLiveMarkdown('Ini `'), 'Ini');
      expect(
        kantorLiveMarkdown('Ini **tebal** dan `kode`'),
        'Ini **tebal** dan `kode`',
      );
      expect(kantorLiveMarkdown('2 * 3 = 6'), '2 * 3 = 6');
      expect(kantorLiveMarkdown('- satu\n- dua'), '- satu\n- dua');
      // paragraf sebelumnya sudah selesai: tidak disentuh
      expect(kantorLiveMarkdown('a **b\n\nc'), 'a **b\n\nc');
      expect(kantorLiveMarkdown('```\nx\n```\n\nok'), '```\nx\n```\n\nok');
    });

    test('kursor hanya di tempat yang aman', () {
      const m = kantorCursorMark;
      expect(kantorLiveMarkdown('Halo', cursor: true), 'Halo$m');
      expect(kantorLiveMarkdown('Halo\n\n', cursor: true), 'Halo$m');
      expect(kantorLiveMarkdown('**teb', cursor: true), '**teb**$m');
      expect(kantorLiveMarkdown('# Judul', cursor: true), '# Judul$m');
      for (final s in ['```\nx', '| a | b |', '- ', '1.', '#', '    kode()']) {
        expect(
          kantorLiveMarkdown(s, cursor: true),
          isNot(endsWith(m)),
          reason: s,
        );
      }
    });

    test('kepala dipotong hanya di batas blok yang aman', () {
      expect(kantorLiveSplit('Satu'), 0);
      expect(kantorLiveSplit('Satu\n\nDua'), 6);
      expect(kantorLiveSplit('- a\n\n- b'), 0);
      expect(kantorLiveSplit('Teks\n\n    kode'), 0);
      const fenced = '```\nx\n\ny\n```\n\nZ';
      expect(kantorLiveSplit(fenced), fenced.indexOf('Z'));
    });

    test('laju: dasar ±50/dtk, backlog besar terkejar dalam 0,9 dtk', () {
      expect(kantorLiveRate(10), kantorLiveBase);
      expect(kantorLiveRate(900), closeTo(1000, 0.01));
      expect(900 / kantorLiveRate(900), lessThanOrEqualTo(1));
    });
  });

  group('KantorLiveText', () {
    testWidgets('pacing: 0,5 dtk sebagian, ~1 dtk penuh', (t) async {
      final text = List.filled(20, 'kata ').join().trim(); // 99 karakter
      await _pumpLive(t, text);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      final half = _shown(t);
      expect(half.length, inInclusiveRange(30, 80));
      expect(text.startsWith(half.trim()), isTrue);
      await t.pump(const Duration(milliseconds: 450));
      expect(_shown(t), text);
    });

    testWidgets('teks pendek mengalir di laju dasar, tidak sekaligus', (
      t,
    ) async {
      await _pumpLive(t, 'Halo semua orang');
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(_shown(t).length, inInclusiveRange(3, 8));
      await t.pump(const Duration(milliseconds: 300));
      expect(_shown(t), 'Halo semua orang');
    });

    testWidgets('backlog besar (bongkah Claude) terkejar <= 1 dtk', (t) async {
      final big = List.filled(600, 'baris ').join().trim();
      await _pumpLive(t, big.substring(0, 100));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      // bongkah baru datang: laju naik supaya sisanya terkejar ±0,9 dtk
      await _pumpLive(t, big);
      await t.pump(const Duration(milliseconds: 400));
      final mid = _shown(t);
      expect(mid.length, greaterThan(200));
      expect(mid.length, lessThan(big.length));
      await t.pump(const Duration(milliseconds: 560));
      expect(_shown(t), big);
    });

    testWidgets('emoji dan grafem gabungan tidak pernah terpotong', (t) async {
      final text = List.filled(
        12,
        '👍🏽 👨‍👩‍👧 caf\u00e9 e\u0301 ',
      ).join().trim();
      final all = text.characters.toList();
      await _pumpLive(t, text);
      for (var i = 0; i < 90; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final s = _shown(t);
        final n = s.characters.length;
        expect(all.take(n).join(), s, reason: 'frame $i: "$s"');
        for (var k = 0; k < s.length; k++) {
          final u = s.codeUnitAt(k);
          if (u >= 0xD800 && u <= 0xDBFF) {
            final v = k + 1 < s.length ? s.codeUnitAt(k + 1) : 0;
            expect(v >= 0xDC00 && v <= 0xDFFF, isTrue, reason: 'surrogate');
          }
        }
      }
      expect(_shown(t), text);
    });

    testWidgets('markdown ringan dirender tanpa penanda mentah', (t) async {
      const src =
          '# Judul Besar\n\nIni **tebal**, *miring*, dan `kode`.\n\n'
          '- satu\n- dua\n\n```dart\nprint(1);\n```\n\nEkor **belum ditutup';
      await _pumpLive(t, src, animate: false);
      await t.pump();
      final shown = _shown(t);
      for (final raw in ['**', '`', '# ', '```']) {
        expect(shown, isNot(contains(raw)), reason: raw);
      }
      for (final w in [
        'Judul Besar',
        'tebal',
        'miring',
        'kode',
        'satu',
        'print(1);',
        'belum ditutup',
      ]) {
        expect(shown, contains(w));
      }
      final spans = _spans(t);
      TextStyle? styleOf(String w) =>
          spans.firstWhere((s) => s.text!.contains(w)).style;
      final body = styleOf('Ini')!;
      expect(styleOf('Judul Besar')!.fontSize, greaterThan(body.fontSize!));
      expect(styleOf('tebal')!.fontWeight!.value, greaterThanOrEqualTo(700));
      expect(
        styleOf('belum ditutup')!.fontWeight!.value,
        greaterThanOrEqualTo(700),
      );
      expect(styleOf('miring')!.fontStyle, FontStyle.italic);
      expect(styleOf('kode')!.fontFamily, 'monospace');
      expect(styleOf('print(1);')!.fontFamily, 'monospace');
      // blok kode berlatar seperti di bubble final
      expect(
        find.ancestor(
          of: find.textContaining('print(1);'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        ),
        findsWidgets,
      );
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('blok kode yang belum ditutup tetap monospace', (t) async {
      await _pumpLive(t, 'Contoh:\n\n```dart\nvar a = 1;', animate: false);
      await t.pump();
      expect(_shown(t), isNot(contains('```')));
      final code = _spans(t).firstWhere((s) => s.text!.contains('var a = 1;'));
      expect(code.style!.fontFamily, 'monospace');
    });

    testWidgets('teks dikoreksi server: tidak mundur ke awal', (t) async {
      await _pumpLive(t, 'Halo dunia yang indah sekali');
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(_shown(t), 'Halo dunia yang indah sekali');
      await _pumpLive(t, 'Hai semua, ini teks yang sudah diperbaiki');
      await t.pump();
      final s = _shown(t);
      expect(s.length, greaterThanOrEqualTo(25));
      expect('Hai semua, ini teks yang sudah diperbaiki'.startsWith(s), isTrue);
      await t.pump(const Duration(seconds: 1));
      expect(_shown(t), 'Hai semua, ini teks yang sudah diperbaiki');
    });

    testWidgets('partial: "…" dan keterangan di awal bubble', (t) async {
      await _pumpLive(t, 'lanjutan jawaban', partial: true, animate: false);
      expect(find.byKey(const ValueKey('chat-live-partial')), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('awal jawaban tidak terlihat'), findsOneWidget);
      await _pumpLive(t, 'lanjutan jawaban', animate: false);
      expect(find.text('awal jawaban tidak terlihat'), findsNothing);
    });

    testWidgets('KantorHandoff: crossfade singkat, tinggi tidak meloncat', (
      t,
    ) async {
      await t.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: KantorHandoff(
              from: SizedBox(height: 100, width: 50, child: Text('lama')),
              child: SizedBox(height: 40, width: 50, child: Text('baru')),
            ),
          ),
        ),
      );
      final box = find.byType(KantorHandoff);
      expect(find.text('lama'), findsOneWidget);
      expect(find.text('baru'), findsNothing);
      expect(t.getSize(box).height, 100);
      await t.pump(); // frame berikutnya: crossfade mulai
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('lama'), findsOneWidget);
      expect(find.text('baru'), findsOneWidget);
      expect(t.getSize(box).height, greaterThan(40));
      // fade selesai, lalu tinggi menyusut halus (bukan langsung)
      await t.pump(const Duration(milliseconds: 120));
      await t.pump();
      expect(find.text('lama'), findsNothing);
      expect(t.getSize(box).height, greaterThan(40));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('baru'), findsOneWidget);
      expect(t.getSize(box).height, 40);
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

    testWidgets('final menggantikan bubble lewat crossfade, tanpa duplikat, '
        'tetap di dasar', (t) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);
      events.add(ev('## Hasil\n\nSudah **beres** di `main.dart`', 1));
      await _frames(t);
      expect(_live, findsOneWidget);
      expect(_shown(t), isNot(contains('**')));

      next = [_text('## Hasil\n\nSudah **beres** di `main.dart`.')];
      events.add({'t': 'transcript', 'office': 'o', 'sid': 's1'});
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(_live, findsNothing);
      expect(find.byKey(const ValueKey('chat-handoff')), findsOneWidget);
      expect(find.text('sedang menulis…'), findsNothing);
      expect(find.textContaining('beres'), findsOneWidget);
      expect(find.textContaining('Hasil'), findsOneWidget);
      final list = find.byKey(const ValueKey('chat-list'));
      expect(t.widget<ListView>(list).controller!.position.pixels, 0);
      await close(t);
    });

    testWidgets('partial: tanda "…" di bubble, final tetap menggantikan', (
      t,
    ) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      await pumpChat(t, events: events.stream);
      await _settle(t);
      events.add({
        ...ev('bagian tengah jawaban yang panjang', 1),
        'partial': true,
      });
      await _frames(t);
      expect(_live, findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('awal jawaban tidak terlihat'), findsOneWidget);

      next = [
        _text(
          'Awal jawaban. Lalu bagian tengah jawaban yang panjang. Selesai.',
        ),
      ];
      events.add({'t': 'transcript', 'office': 'o', 'sid': 's1'});
      await t.pump(const Duration(milliseconds: 200));
      await _settle(t);
      expect(_live, findsNothing);
      expect(find.text('awal jawaban tidak terlihat'), findsNothing);
      expect(find.textContaining('Awal jawaban. Lalu'), findsOneWidget);
      await close(t);
    });
  });
}
