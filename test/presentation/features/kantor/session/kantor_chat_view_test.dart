import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/chat_tab.dart';
import 'package:ghina/presentation/features/kantor/session/chat_view_prefs.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpChat(
    WidgetTester t, {
    double systemScale = 1,
  }) async {
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
    final c = ProviderContainer(
      overrides: [kantorOfficeFeedProvider.overrideWith((ref, id) => feed)],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(systemScale)),
            child: child!,
          ),
          home: Scaffold(
            body: KantorChatTab(feed: feed, sid: 's1'),
          ),
        ),
      ),
    );
    await t.pump();
    return c;
  }

  double hintSize(WidgetTester t) {
    // ChatScope supplies the scaled MediaQuery below KantorChatTab.
    final ctx = t.element(find.byType(EditableText));
    return MediaQuery.of(ctx).textScaler.scale(10);
  }

  testWidgets('scale multiplies the system text scale and is capped', (
    t,
  ) async {
    final c = await pumpChat(t, systemScale: 1.2);
    expect(hintSize(t), closeTo(12, 0.01));
    c.read(chatViewPrefsProvider.notifier).setScale(1.5);
    await t.pump();
    expect(hintSize(t), closeTo(18, 0.01));
    // huge system scale: product stays under the cap (2.2x)
    final c2 = ChatTextScaler(const TextScaler.linear(2), 1.5);
    expect(c2.scale(10), closeTo(22, 0.01));
  });

  testWidgets('settings persist and load back', (t) async {
    final c = await pumpChat(t);
    final n = c.read(chatViewPrefsProvider.notifier);
    n.update(
      (p) => p.copyWith(
        scale: 1.3,
        density: ChatDensity.loose,
        tools: ChatToolMode.hidden,
        flatClaude: true,
      ),
    );
    await t.pump();
    final stored = (await SharedPreferences.getInstance()).getString(
      'kantor.chat.view',
    );
    expect(stored, isNotNull);
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(chatViewPrefsProvider);
    await t.pump(const Duration(milliseconds: 50));
    final p = c2.read(chatViewPrefsProvider);
    expect(p.scale, 1.3);
    expect(p.density, ChatDensity.loose);
    expect(p.tools, ChatToolMode.hidden);
    expect(p.flatClaude, isTrue);
  });

  testWidgets('sheet slider changes the size', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: const Scaffold(body: ChatViewSheet()),
        ),
      ),
    );
    final slider = find.byKey(const ValueKey('chat-scale'));
    await t.drag(slider, const Offset(400, 0));
    await t.pump();
    expect(c.read(chatViewPrefsProvider).scale, chatScaleMax);
    await t.drag(slider, const Offset(-800, 0));
    await t.pump();
    expect(c.read(chatViewPrefsProvider).scale, chatScaleMin);
  });

  testWidgets('pinch on the chat scales text and saves once released', (
    t,
  ) async {
    final c = await pumpChat(t);
    final list = find.byType(Listener).first;
    final center = t.getCenter(find.byType(KantorChatTab));
    final a = await t.startGesture(center - const Offset(40, 0));
    final b = await t.startGesture(center + const Offset(40, 0));
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await t.pump();
    // span 80 -> 120: x1.5
    expect(c.read(chatViewPrefsProvider).scale, closeTo(1.5, 0.01));
    expect(
      (await SharedPreferences.getInstance()).getString('kantor.chat.view'),
      isNull,
    );
    await a.up();
    await b.up();
    await t.pump();
    expect(
      (await SharedPreferences.getInstance()).getString('kantor.chat.view'),
      isNotNull,
    );
    expect(list, findsWidgets);
  });
}
