import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_clipboard.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

/// Layar awal tmux palsu: layar alternatif + teks dua baris.
const _screen = '\x1b[?1049h\x1b[Hhalo dunia\r\nbaris dua';

/// Bracketed paste dinyalakan program (Claude Code, shell modern).
const _bracketOn = '\x1b[?2004h';

void main() {
  group('helper', () {
    test('tidyCopied membuang spasi ujung dan baris kosong akhir', () {
      expect(tidyCopied('a  \nb\t\n  \n\n'), 'a\nb');
      expect(tidyCopied(''), '');
    });

    test('pasteReady: baris baru jadi CR, penanda bracket dibuang', () {
      expect(pasteReady('a\r\nb\nc'), 'a\rb\rc');
      expect(pasteReady('x\x1b[201~rm -rf\x1b[200~'), 'xrm -rf');
    });

    test('pasteEnters 0 saat bracketed paste, hitung CR kalau tidak', () {
      final t = Terminal();
      expect(pasteEnters(t, 'a\rb\r'), 2);
      expect(pasteEnters(t, 'satu baris'), 0);
      t.write(_bracketOn);
      expect(pasteEnters(t, 'a\rb\r'), 0);
    });

    test('termScreenText dan seleksi membaca buffer layar alternatif', () {
      final t = Terminal()..resize(20, 4);
      t.write(_screen);
      expect(termScreenText(t), 'halo dunia\nbaris dua');
      final c = TerminalController();
      expect(termSelectionText(t, c), isNull);
      c.setSelection(t.buffer.createAnchor(5, 0), t.buffer.createAnchor(10, 0));
      expect(termSelectionText(t, c), 'dunia');
    });
  });

  group('panel terminal', () {
    late HttpServer server;
    late List<String> input;
    late List<String> clip;
    String? clipboard;
    WebSocket? sock;
    var greeting = _screen;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      HttpOverrides.global = null;
      input = [];
      clip = [];
      clipboard = null;
      sock = null;
      greeting = _screen;
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
        ws.add(greeting);
        ws.listen((d) {
          // pesan resize diawali '\x00'; selebihnya ketikan / tempelan
          if (d is String && !d.startsWith('\x00')) input.add(d);
        });
      });
    });
    tearDown(() async {
      await sock?.close();
      await server.close(force: true);
    });

    void mockClipboard(WidgetTester t) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final text = (call.arguments as Map)['text'] as String;
              clip.add(text);
              clipboard = text;
              return null;
            case 'Clipboard.getData':
              return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    /// Beri waktu IO sungguhan (websocket) lalu render.
    Future<void> settle(WidgetTester t, [int rounds = 4]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpPanel(WidgetTester t) async {
      t.view.physicalSize = const Size(400, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      mockClipboard(t);
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
            home: Scaffold(body: KantorTerminalPanel.session('s1')),
          ),
        ),
      );
      await settle(t, 6);
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await settle(t, 2);
      await t.pump(const Duration(seconds: 5)); // toast
    }

    /// Tekan lama sel pertama layar: xterm memilih kata "halo".
    Future<void> selectFirstWord(WidgetTester t) async {
      final at = t.getTopLeft(find.byType(TerminalView)) + const Offset(9, 7);
      await t.longPressAt(at);
      await t.pump();
    }

    Future<void> chord(
      WidgetTester t,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(key);
      if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(t, 2);
    }

    testWidgets('tekan lama lalu "Salin" menaruh kata terpilih di clipboard', (
      t,
    ) async {
      await pumpPanel(t);
      expect(find.byKey(const ValueKey('term-copy')), findsNothing);
      await selectFirstWord(t);
      final copy = find.byKey(const ValueKey('term-copy'));
      expect(copy, findsOneWidget);
      await t.tap(copy);
      await settle(t, 2);
      expect(clip, ['halo']);
      // seleksi dilepas, tombol kembali ke "Salin layar"
      expect(copy, findsNothing);
      expect(find.byKey(const ValueKey('term-copy-screen')), findsOneWidget);
      expect(input, isEmpty);
      await finish(t);
    });

    testWidgets('"Salin layar" menyalin seluruh layar yang terlihat', (
      t,
    ) async {
      await pumpPanel(t);
      await t.tap(find.byKey(const ValueKey('term-copy-screen')));
      await settle(t, 2);
      expect(clip, ['halo dunia\nbaris dua']);
      await finish(t);
    });

    testWidgets('Ctrl+C dengan seleksi menyalin, tanpa seleksi tetap ^C', (
      t,
    ) async {
      await pumpPanel(t);
      await selectFirstWord(t);
      await chord(t, LogicalKeyboardKey.keyC);
      expect(clip, ['halo']);
      expect(input, isEmpty);
      // seleksi sudah lepas: Ctrl+C kembali jadi interupsi ke program
      await chord(t, LogicalKeyboardKey.keyC);
      expect(input, ['\x03']);
      // Ctrl+Shift+C tanpa seleksi tidak boleh jadi ^C
      await chord(t, LogicalKeyboardKey.keyC, shift: true);
      expect(input, ['\x03']);
      // Ctrl+A milik shell lagi, bukan "pilih semua" xterm
      await chord(t, LogicalKeyboardKey.keyA);
      expect(input.last, '\x01');
      expect(find.byKey(const ValueKey('term-copy')), findsNothing);
      await finish(t);
    });

    testWidgets('"Tempel" mengirim clipboard ke sesi sebagai bracketed paste', (
      t,
    ) async {
      greeting = '$_screen$_bracketOn';
      await pumpPanel(t);
      clipboard = 'echo satu\ndua';
      await t.tap(find.byKey(const ValueKey('term-paste')));
      await settle(t, 3);
      expect(input, ['\x1b[200~echo satu\rdua\x1b[201~']);
      expect(find.byType(AlertDialog), findsNothing);
      // Ctrl+V dan Ctrl+Shift+V dari keyboard fisik lewat jalur yang sama
      await t.tap(find.byType(TerminalView));
      await settle(t, 1);
      clipboard = 'ls';
      await chord(t, LogicalKeyboardKey.keyV);
      await chord(t, LogicalKeyboardKey.keyV, shift: true);
      expect(input.skip(1), ['\x1b[200~ls\x1b[201~', '\x1b[200~ls\x1b[201~']);
      await finish(t);
    });

    testWidgets('tanpa bracketed paste, teks multi-baris minta konfirmasi', (
      t,
    ) async {
      await pumpPanel(t);
      clipboard = 'rm a\nrm b\n';
      await t.tap(find.byKey(const ValueKey('term-paste')));
      await settle(t, 2);
      expect(find.text('Tempel teks multi-baris?'), findsOneWidget);
      await t.tap(find.text('Batal'));
      await settle(t, 2);
      expect(input, isEmpty);

      await t.tap(find.byKey(const ValueKey('term-paste')));
      await settle(t, 2);
      await t.tap(find.widgetWithText(TextButton, 'Tempel'));
      await settle(t, 3);
      expect(input, ['rm a\rrm b\r']);

      // satu baris langsung terkirim tanpa dialog
      clipboard = 'git status';
      await t.tap(find.byKey(const ValueKey('term-paste')));
      await settle(t, 3);
      expect(find.byType(AlertDialog), findsNothing);
      expect(input.last, 'git status');
      await finish(t);
    });
  });
}
