import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploader.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploads.dart';
import 'package:ghina/presentation/features/kantor/session/chat_look.dart';
import 'package:ghina/presentation/features/kantor/session/chat_look_paint.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _merged =
    'Cek layar ini ya\n\n[Lampiran dari pemilik, 2 file]\n- a.png\n- b.png';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('prefs', () {
    test('chat look round-trips through JSON; unknown values fall back', () {
      const p = ChatViewPrefs(
        wall: ChatWall.senja,
        bubble: ChatBubbleShape.awan,
        me: ChatMeColor.gradasi,
        peek: ChatPeek.hantu,
        wallPhoto: '/x/y.jpg',
      );
      final back = ChatViewPrefs.fromJson(p.toJson());
      expect(back.wall, ChatWall.senja);
      expect(back.bubble, ChatBubbleShape.awan);
      expect(back.me, ChatMeColor.gradasi);
      expect(back.peek, ChatPeek.hantu);
      expect(back.wallPhoto, '/x/y.jpg');
      final junk = ChatViewPrefs.fromJson({
        'wall': 'tidak-ada',
        'bubble': 7,
        'me': null,
        'peek': 'naga',
      });
      expect(junk.wall, ChatWall.polos);
      expect(junk.bubble, ChatBubbleShape.kantor);
      expect(junk.me, ChatMeColor.biru);
      expect(junk.peek, ChatPeek.none);
      // old saved prefs without the new keys still load
      expect(ChatViewPrefs.fromJson({'scale': 1.2}).wall, ChatWall.polos);
    });

    test('options follow the web: 9 walls, 6 bubbles, 7 colors, 4 mascots', () {
      expect(ChatWall.values, hasLength(9));
      expect(ChatBubbleShape.values, hasLength(6));
      expect(ChatMeColor.values, hasLength(7));
      expect(ChatPeek.values.where((p) => p.sprite != null), hasLength(4));
      expect(ChatMeColor.gradasi.from, const Color(0xFF7C4DFF));
      expect(ChatMeColor.gradasi.to, const Color(0xFFE84393));
      expect(ChatMeColor.biru.gradient, isNull);
    });

    test(
      'every sprite is a rectangle whose letters are all in its palette',
      () {
        for (final k in ChatPeek.values) {
          final s = k.sprite;
          if (s == null) continue;
          for (final row in s.rows) {
            expect(row.length, s.width, reason: '$k');
            for (final c in row.split('')) {
              expect(
                c == '.' || s.palette.containsKey(c),
                isTrue,
                reason: '$k $c',
              );
            }
          }
        }
      },
    );

    test('terminal prefs persist and reload', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(terminalPrefsProvider.notifier)
          .update((p) => p.copyWith(theme: 'dracula', face: TermFace.fira));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(terminalPrefsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c2.read(terminalPrefsProvider).theme, 'dracula');
      expect(c2.read(terminalPrefsProvider).face, TermFace.fira);
    });

    test('wallpaper photo is stored in the app folder and replaced', () async {
      final tmp = await Directory.systemTemp.createTemp('wall_');
      addTearDown(() => tmp.delete(recursive: true));
      final src = File('${tmp.path}/foto.jpg')..writeAsBytesSync([1, 2, 3]);
      final c = ProviderContainer(
        overrides: [
          chatWallDirProvider.overrideWithValue(
            Future.value(Directory('${tmp.path}/wall')..createSync()),
          ),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(chatViewPrefsProvider.notifier);
      expect(await n.setWallPhoto(src), isTrue);
      final first = c.read(chatViewPrefsProvider);
      expect(first.wall, ChatWall.foto);
      expect(first.wallPhoto, startsWith('${tmp.path}/wall/'));
      expect(File(first.wallPhoto!).existsSync(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await n.setWallPhoto(src), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(File(first.wallPhoto!).existsSync(), isFalse);
      expect(await n.setWallPhoto(File('${tmp.path}/tidak-ada')), isFalse);
    });
  });

  group('settings sheet follows the open tab', () {
    Future<void> sheet(WidgetTester t, ViewSheetScope scope) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: Scaffold(body: ChatViewSheet(scope: scope)),
          ),
        ),
      );
    }

    testWidgets('Chat: no terminal settings', (t) async {
      await sheet(t, ViewSheetScope.chat);
      expect(find.text('Wallpaper'), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-pixel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('theme-dracula'), skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Font'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('Terminal: no chat settings', (t) async {
      await sheet(t, ViewSheetScope.terminal);
      expect(find.byKey(const ValueKey('face-ubuntu')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('theme-matrix'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Wallpaper'), findsNothing);
      expect(find.byKey(const ValueKey('chat-scale')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('both from Settings', (t) async {
      await sheet(t, ViewSheetScope.both);
      expect(find.text('Wallpaper'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('face-jetbrains'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('picking wallpaper, bubble, color, mascot, theme and font', (
      t,
    ) async {
      await sheet(t, ViewSheetScope.both);
      final c = ProviderScope.containerOf(
        t.element(find.byType(ChatViewSheet)),
      );
      Future<void> tap(String key) async {
        final f = find.byKey(ValueKey(key));
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pump();
      }

      await tap('wall-malam');
      await tap('bubble-ekor');
      await tap('me-gradasi');
      await tap('peek-kodok');
      final p = c.read(chatViewPrefsProvider);
      expect(
        [p.wall, p.bubble, p.me, p.peek],
        [
          ChatWall.malam,
          ChatBubbleShape.ekor,
          ChatMeColor.gradasi,
          ChatPeek.kodok,
        ],
      );
      await tap('theme-nord');
      await tap('face-roboto');
      expect(c.read(terminalPrefsProvider).theme, 'nord');
      expect(c.read(terminalPrefsProvider).face, TermFace.roboto);
      await tap('term-reset');
      expect(c.read(terminalPrefsProvider).theme, defaultTermThemeId);
      expect(t.takeException(), isNull);
    });

    test('own photo: the picker result becomes the wallpaper', () async {
      final tmp = await Directory.systemTemp.createTemp('wall_');
      addTearDown(() => tmp.delete(recursive: true));
      final src = File('${tmp.path}/f.jpg')..writeAsBytesSync([9, 9, 9]);
      final c = ProviderContainer(
        overrides: [
          chatWallPickerProvider.overrideWithValue(() async => src),
          chatWallDirProvider.overrideWithValue(
            Future.value(Directory('${tmp.path}/w')..createSync()),
          ),
        ],
      );
      addTearDown(c.dispose);
      final picked = await c.read(chatWallPickerProvider)();
      expect(picked, isNotNull);
      await c.read(chatViewPrefsProvider.notifier).setWallPhoto(picked!);
      expect(c.read(chatViewPrefsProvider).wall, ChatWall.foto);
      expect(c.read(chatViewPrefsProvider).wallPhoto, isNotNull);
    });
  });

  group('terminal themes', () {
    test('15 presets with 16 ANSI colors and unique ids', () {
      expect(termThemes, hasLength(15));
      expect(termThemes.map((t) => t.id).toSet(), hasLength(15));
      for (final t in termThemes) {
        expect(t.ansi, hasLength(16), reason: t.id);
      }
      expect(termThemes.where((t) => t.light).map((t) => t.id), [
        'kertas',
        'github',
      ]);
    });

    test('a preset maps onto the xterm theme', () {
      final d = termThemeById('dracula');
      final x = d.toTerminalTheme();
      expect(x.background, const Color(0xFF282A36));
      expect(x.foreground, const Color(0xFFF8F8F2));
      expect(x.cursor, const Color(0xFFF8F8F2));
      expect(x.selection, const Color(0xFF44475A));
      expect(x.red, const Color(0xFFFF5555));
      expect(x.brightWhite, const Color(0xFFFFFFFF));
      expect(x.brightBlack, const Color(0xFF6272A4));
    });

    test('an unknown id is the default, saved junk is cleaned', () {
      expect(termThemeById('???').id, defaultTermThemeId);
      final p = TerminalPrefs.fromJson({
        'theme': 'x',
        'face': 'comic',
        'fontSize': 99,
      });
      expect(p.theme, defaultTermThemeId);
      expect(p.face, TermFace.jetbrains);
      expect(p.fontSize, termFontMax);
    });

    test('six fonts, JetBrains Mono first', () {
      expect(TermFace.values.map((f) => f.label), [
        'JetBrains Mono',
        'Ubuntu Mono',
        'Fira Code',
        'Source Code Pro',
        'IBM Plex Mono',
        'Roboto Mono',
      ]);
    });
  });

  group('chat tab', () {
    late HttpServer server;
    final hits = <String>[];
    var hidden = 2;

    setUp(() async {
      HttpOverrides.global = null;
      hits.clear();
      hidden = 2;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        hits.add(req.uri.toString());
        Object body = {};
        if (req.uri.path.endsWith('/transcript')) {
          body = {
            'size': 1,
            'items': [
              {
                'k': 'user',
                's':
                    '<teammate-message teammate_id="budi-contoh" color="green">'
                    '{"type":"idle_notification","summary":"Selesai rapikan","result":"Sudah beres."}'
                    '</teammate-message>\n\nBagus, lanjut',
                'at': '2026-11-12T09:00:00Z',
              },
              {'k': 'user', 's': _merged, 'at': '2026-11-12T09:01:00Z'},
              {'k': 'text', 's': 'Siap.', 'at': '2026-11-12T09:02:00Z'},
            ],
          };
        } else if (req.uri.path.endsWith('/attachments')) {
          final all = req.uri.queryParameters['all'] == '1';
          body = {
            'items': [
              {
                'id': 'a1',
                'name': 'a.png',
                'mime': 'image/png',
                'size': 5,
                'dir': 'in',
                'at': '2026-11-12T09:01:00Z',
                'message': _merged,
                'note': 'Cek layar ini ya',
              },
            ],
            'hiddenBeforeClear': all ? 0 : hidden,
          };
        }
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body))
          ..close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<ProviderContainer> pumpChat(WidgetTester t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': 's1', 'status': 'idle', 'tmux': 'x', 'title': 'Dina'},
          ],
        };
      addTearDown(feed.dispose);
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
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          kantorUploadsProvider.overrideWith(_QuietUploads.new),
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
      for (var i = 0; i < 6; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      return c;
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 20)); // idle HTTP connection timers
    }

    testWidgets(
      'teammate card, owner words, hidden merged prompt, old files button',
      (t) async {
        await pumpChat(t);
        // card on the left with sender, kind and summary
        expect(find.byKey(const ValueKey('teammate-card')), findsOneWidget);
        expect(find.text('budi-contoh'), findsOneWidget);
        expect(find.text('SELESAI'), findsOneWidget);
        expect(find.text('Selesai rapikan'), findsOneWidget);
        // the owner's sentence outside the tag is still a bubble
        expect(find.text('Bagus, lanjut'), findsOneWidget);
        // the merged prompt shows only the owner's note, never the file list
        expect(find.textContaining('[Lampiran dari pemilik'), findsNothing);
        expect(find.text('Cek layar ini ya'), findsOneWidget);
        // hidden files from before /clear
        final btn = find.byKey(const ValueKey('chat-old-files'));
        // Attachment Download controls make the timeline taller; older rows
        // are built lazily, so reveal the older end as a person would.
        await t.scrollUntilVisible(
          btn,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('chat-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(btn, findsOneWidget);
        expect(
          find.text('Tampilkan 2 berkas dari sebelum /clear'),
          findsOneWidget,
        );
        expect(
          hits.any((h) => h.contains('/attachments') && h.contains('all=1')),
          isFalse,
        );
        await t.tap(btn);
        await t.pump(const Duration(milliseconds: 300));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await t.pump(const Duration(milliseconds: 50));
        expect(
          hits.where((h) => h.contains('attachments')),
          contains('/api/sessions/s1/attachments?all=1'),
        );
        expect(btn, findsNothing);
        expect(t.takeException(), isNull);
        await finish(t);
      },
    );

    testWidgets('every wallpaper, bubble shape, color and mascot fits 360dp', (
      t,
    ) async {
      final c = await pumpChat(t);
      final n = c.read(chatViewPrefsProvider.notifier);
      for (final w in ChatWall.values) {
        n.update(
          (p) => p.copyWith(
            wall: w,
            bubble:
                ChatBubbleShape.values[w.index % ChatBubbleShape.values.length],
            me: ChatMeColor.values[w.index % ChatMeColor.values.length],
            peek: ChatPeek.values[w.index % ChatPeek.values.length],
          ),
        );
        await t.pump();
        expect(t.takeException(), isNull, reason: '$w');
      }
      for (final b in ChatBubbleShape.values) {
        n.update(
          (p) => p.copyWith(
            bubble: b,
            peek: ChatPeek.kucing,
            wall: ChatWall.doodle,
          ),
        );
        await t.pump();
        expect(t.takeException(), isNull, reason: '$b');
      }
      expect(find.byType(ChatWallpaper), findsOneWidget);
      expect(find.byType(ThemedBubble), findsWidgets);
      await finish(t);
    });
  });
}

class _QuietUploads extends KantorUploads {
  @override
  List<UploadJob> build() => [];
}
