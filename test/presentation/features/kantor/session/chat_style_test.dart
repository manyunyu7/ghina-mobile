import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/features/kantor/session/chat_look.dart';
import 'package:ghina/presentation/features/kantor/session/chat_style.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_actions.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/session/permission_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  late HttpServer server;
  late KantorApi api;
  var previewItems = <Map<String, dynamic>>[];
  setUp(() async {
    previewItems = [];
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      Object body = [];
      if (req.uri.path.endsWith('/transcript')) {
        body = {
          'items': [
            {'k': 'text', 's': 'Balasan agent'},
          ],
        };
      }
      if (req.uri.path.contains('/pratinjau')) body = {'items': previewItems};
      req.response
        ..persistentConnection = false
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    api = KantorApi(
      KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 'test'),
    );
  });
  tearDown(() => server.close(force: true));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'style picker persists and reloads without replacing custom look',
    (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: const Scaffold(body: ChatViewSheet()),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.text('Telegram'));
      await _settle(t);
      expect(container.read(chatViewPrefsProvider).style, ChatStyle.telegram);
      final saved = await SharedPreferences.getInstance();
      expect(
        jsonDecode(saved.getString('kantor.chat.view')!)['style'],
        'telegram',
      );
      final next = ProviderContainer();
      addTearDown(next.dispose);
      next.read(chatViewPrefsProvider);
      await _settle(t);
      expect(next.read(chatViewPrefsProvider).style, ChatStyle.telegram);
      final custom = const ChatViewPrefs()
          .copyWith(
            wall: ChatWall.polos,
            bubble: ChatBubbleShape.kotak,
            me: ChatMeColor.ungu,
          )
          .copyWith(style: ChatStyle.whatsapp);
      final back = ChatViewPrefs.fromJson(custom.toJson());
      expect(back.useStyleWall, isFalse);
      expect(back.useStyleBubble, isFalse);
      expect(back.useStyleMe, isFalse);
      expect(back.wall, ChatWall.polos);
      expect(back.me, ChatMeColor.ungu);
      await t.tap(find.text('Default'));
      await _settle(t);
      expect(container.read(chatViewPrefsProvider).style, ChatStyle.bawaan);
    },
  );

  test('legacy settings retain Default and all original defaults', () {
    final old = ChatViewPrefs.fromJson({
      'scale': 1.2,
      'wall': 'senja',
      'me': 'ungu',
    });
    expect(old.style, ChatStyle.bawaan);
    expect(old.scale, 1.2);
    expect(old.wall, ChatWall.senja);
    expect(old.me, ChatMeColor.ungu);
    final defaults = const ChatViewPrefs();
    expect(defaults.hasWall, isFalse);
    expect(defaults.bubble, ChatBubbleShape.kantor);
    expect(defaults.me, ChatMeColor.biru);
    expect(
      defaults
          .copyWith(style: ChatStyle.telegram)
          .copyWith(style: ChatStyle.bawaan)
          .toJson(),
      defaults.toJson(),
    );
    expect(ChatViewPrefs.fromJson({'style': 'future'}).style, ChatStyle.bawaan);
  });

  testWidgets(
    'profile QA: collapse persona, labelled previews and disabled model action',
    (t) async {
      t.view.physicalSize = const Size(390, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const title = 'Pratinjau HTML tanpa thumbnail';
      previewItems = [
        {
          'id': 'p1',
          'office': 'o',
          'sid': 's',
          'title': title,
          'mode': 'bundle',
          'files': [
            {
              'id': 'f1',
              'name': 'index.html',
              'kind': 'html',
              'url': '/pv/o/p1/index.html',
            },
          ],
        },
      ];
      SharedPreferences.setMockInitialValues({
        'kantor.chat.view': jsonEncode(
          const ChatViewPrefs(style: ChatStyle.telegram).toJson(),
        ),
      });
      final persona = List.filled(
        40,
        'Membantu pemilik merapikan berkas dan mengurus pekerjaan kantor.',
      ).join(' ');
      final session = <String, dynamic>{
        'sid': 's',
        'role': 'mesi',
        'status': 'working',
        'tmux': 'test',
        'model': 'sonnet',
        'cwd': '/workspace/media',
      };
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'roles': [
            {'id': 'mesi', 'name': 'Mesi', 'persona': persona},
          ],
          'sessions': [session],
        };
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorApiProvider.overrideWithValue(api),
            kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: KantorAgentProfilePage(
              feed: feed,
              sid: 's',
              actions: KantorActions(api),
            ),
          ),
        ),
      );
      await _settle(t);
      final personaFinder = find.byKey(const ValueKey('profile-persona'));
      expect(t.widget<Text>(personaFinder).maxLines, 3);
      expect(find.text('Selengkapnya'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('profile-persona-expand')));
      await t.pump();
      expect(t.widget<Text>(personaFinder).maxLines, isNull);
      expect(find.text('Lebih sedikit'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('profile-persona-expand')));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('profile-persona-expand')));
      await t.pump();
      expect(t.widget<Text>(personaFinder).maxLines, 3);
      final model = find.byKey(const ValueKey('profile-change-model'));
      expect(model, findsOneWidget);
      expect(t.widget<TextButton>(model).onPressed, isNull);
      feed.apply({
        't': 'session',
        'office': 'o',
        'session': {...session, 'status': 'idle'},
      });
      await t.pump();
      expect(t.widget<TextButton>(model).onPressed, isNotNull);
      final viewRow = find.byKey(const ValueKey('profile-chat-view'));
      expect(
        find.descendant(
          of: viewRow,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
      final preview = find.byKey(const ValueKey('profile-preview-p1'));
      await t.ensureVisible(preview);
      await _settle(t);
      expect(
        find.descendant(of: preview, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(Image)),
        findsNothing,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('messenger room filters use real session status and inbox', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({
      'kantor.chat.view': jsonEncode(
        const ChatViewPrefs(style: ChatStyle.telegram).toJson(),
      ),
    });
    final feed = KantorOfficeFeed('o', null)
      ..loading = false
      ..office = {
        'sessions': [
          {'sid': 'live', 'status': 'working', 'title': 'Aktif'},
          {'sid': 'wait', 'status': 'waiting', 'title': 'Perlu izin'},
          {'sid': 'ended', 'status': 'ended', 'title': 'Selesai'},
        ],
      }
      ..inbox = [
        {'sid': 'wait', 'summary': 'Membaca berkas'},
      ];
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
          kantorApiProvider.overrideWithValue(api),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: KantorAgentsTab(officeId: 'o')),
        ),
      ),
    );
    await _settle(t);
    expect(find.byKey(const ValueKey('room-ended')), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Aktif'));
    await t.pump();
    expect(find.byKey(const ValueKey('room-ended')), findsNothing);
    await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Menunggu izin'));
    await t.tap(find.widgetWithText(ChoiceChip, 'Menunggu izin'));
    await t.pump();
    expect(find.byKey(const ValueKey('room-wait')), findsOneWidget);
    expect(find.byKey(const ValueKey('room-live')), findsNothing);
    expect(find.text('Rapat'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    // the agent list prefetches chats; let that request's timeout lapse
    await t.pump(const Duration(seconds: 31));
  });

  testWidgets('messenger permission actions keep allow and deny callbacks', (
    t,
  ) async {
    final decisions = <String>[];
    await t.pumpWidget(
      MaterialApp(
        theme: GhinaTheme.light(),
        home: Scaffold(
          body: KantorPermissionCard(
            style: ChatStyle.whatsapp,
            item: {
              'id': 'i',
              'tool': 'Read',
              'summary': 'Baca file uji',
              'held': true,
            },
            onDecide: decisions.add,
            onAnswer: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('MENUNGGU IZIN'), findsOneWidget);
    await t.tap(find.text('Tolak'));
    await t.tap(find.text('Izinkan'));
    expect(decisions, ['deny', 'allow']);
    expect(t.takeException(), isNull);
  });

  for (final style in [ChatStyle.telegram, ChatStyle.whatsapp]) {
    testWidgets(
      '${style.name}: custom shapes and large text fit narrow dark chat',
      (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        for (final shape in ChatBubbleShape.values) {
          final view = ChatViewPrefs(style: style).copyWith(bubble: shape);
          await t.pumpWidget(
            MaterialApp(
              theme: GhinaTheme.dark(),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 900),
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        MessengerBubble(
                          view: view,
                          mine: true,
                          time: '10.41',
                          child: const Text(
                            'Pesan dengan ukuran teks besar tetap terbaca.',
                          ),
                        ),
                        MessengerBubble(
                          view: view,
                          mine: false,
                          time: '10.42',
                          child: const Text(
                            'Balasan agent dengan bentuk yang dipilih pemilik.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          expect(t.takeException(), isNull, reason: shape.name);
        }
      },
    );
    testWidgets(
      '${style.name}: header pushes real profile; back preserves draft',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        SharedPreferences.setMockInitialValues({
          'kantor.chat.view': jsonEncode(ChatViewPrefs(style: style).toJson()),
        });
        final feed = KantorOfficeFeed('o', null)
          ..loading = false
          ..office = {
            'name': 'Kantor uji',
            'roles': [
              {
                'id': 'mesi',
                'name': 'Mesi',
                'title': 'OB',
                'persona': 'Membantu di ruang Media',
              },
            ],
            'sessions': [
              {
                'sid': 's',
                'role': 'mesi',
                'status': 'idle',
                'tmux': 'test',
                'cwd': '/workspace/media',
              },
            ],
          };
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              kantorOfficeFeedProvider.overrideWith((ref, id) => feed),
              kantorApiProvider.overrideWithValue(api),
              kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
            ],
            child: MaterialApp(
              theme: GhinaTheme.light(),
              home: const KantorSessionPage(officeId: 'o', sid: 's'),
            ),
          ),
        );
        await _settle(t);
        await t.enterText(
          find.byKey(const ValueKey('messenger-input')),
          'Draf tetap ada',
        );
        await t.tap(find.byKey(const ValueKey('messenger-profile-header')));
        await _settle(t);
        expect(find.byType(KantorAgentProfilePage), findsOneWidget);
        expect(find.text('@mesi'), findsOneWidget);
        expect(find.text('Membantu di ruang Media'), findsOneWidget);
        expect(find.text('Pratinjau'), findsNothing);
        expect(find.text('Rapat'), findsNothing);
        expect(find.text('Bisukan'), findsNothing);
        await t.tap(find.text('Pesan'));
        await _settle(t);
        expect(find.byType(KantorAgentProfilePage), findsNothing);
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('messenger-input')))
              .controller!
              .text,
          'Draf tetap ada',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 4));
      },
    );
  }

  testWidgets('Default retains original tabs, header and composer', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final feed = KantorOfficeFeed('o', null)
      ..loading = false
      ..office = {
        'sessions': [
          {'sid': 's', 'status': 'idle', 'tmux': 'test', 'title': 'Mesi'},
        ],
      };
    await t.pumpWidget(
      ProviderScope(
        overrides: [kantorOfficeFeedProvider.overrideWith((ref, id) => feed)],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const KantorSessionPage(officeId: 'o', sid: 's'),
        ),
      ),
    );
    await _settle(t);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messenger-profile-header')),
      findsNothing,
    );
    expect(find.byType(MessengerBubble), findsNothing);
    expect(find.byType(ChunkyTextField), findsOneWidget);
    expect(find.byType(ChunkyIconButton), findsWidgets);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 4));
  });
}
