import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_tab.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'chat field takes focus and text; terminal never holds focus off its tab',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final feed = KantorOfficeFeed('o', null)
        ..loading = false
        ..office = {
          'sessions': [
            {'sid': 's1', 'status': 'working', 'tmux': 'x', 'title': 'Dina'},
          ],
        };
      await t.pumpWidget(
        ProviderScope(
          overrides: [kantorOfficeFeedProvider.overrideWith((ref, id) => feed)],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: const KantorSessionPage(officeId: 'o', sid: 's1'),
          ),
        ),
      );
      await t.pump();

      // visit the terminal, focus it, then come back to Chat
      await t.tap(find.text('Terminal'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(KantorTerminalPanel), findsOneWidget);
      await t.tap(find.byType(KantorTerminalPanel));
      await t.pump();
      await t.tap(find.text('Chat'));
      await t.pump(const Duration(milliseconds: 400));

      // terminal is offstage and cannot hold focus
      expect(find.byType(KantorTerminalPanel), findsNothing);
      final hidden = find.byType(KantorTerminalPanel, skipOffstage: false);
      expect(hidden, findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.canRequestFocus ?? true,
        isTrue,
      );
      final termFocus = t
          .widget<TerminalView>(
            hidden.evaluate().isEmpty
                ? find.byType(TerminalView, skipOffstage: false)
                : find.byType(TerminalView, skipOffstage: false),
          )
          .focusNode!;
      expect(termFocus.hasFocus, isFalse);
      expect(termFocus.canRequestFocus, isFalse);

      final field = find.byType(EditableText);
      expect(field, findsOneWidget);
      await t.tap(field);
      await t.pump();
      await t.enterText(field, 'halo');
      expect(t.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      expect(t.widget<EditableText>(field).controller.text, 'halo');
    },
  );
}
