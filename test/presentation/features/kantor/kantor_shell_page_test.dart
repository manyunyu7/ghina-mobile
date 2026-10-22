import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_shell_page.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'horizontal swipe on the floor tab does not change tab; tab bar does',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorStateProvider.overrideWith(
              (_) async => {'offices': [], 'inbox': []},
            ),
            kantorOfficeProvider.overrideWith(
              (ref, id) async => {'name': 'Kantor', 'sessions': []},
            ),
          ],
          child: MaterialApp(
            theme: GhinaTheme.light(),
            home: const KantorShellPage(officeId: 'o', tab: 'kantor'),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(
        t.widget<TabBarView>(find.byType(TabBarView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      final bar = t.widget<TabBar>(find.byType(TabBar));
      // the floor is the fourth tab on the phone (agents, wiki and files come first)
      expect(bar.controller!.index, 3);
      await t.fling(find.byType(TabBarView), const Offset(-300, 0), 1500);
      await t.pump(const Duration(milliseconds: 500));
      expect(bar.controller!.index, 3);
      await t.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Board')),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(bar.controller!.index, 4);
      // elsewhere the page view swipes again
      expect(t.widget<TabBarView>(find.byType(TabBarView)).physics, isNull);
    },
  );
}
