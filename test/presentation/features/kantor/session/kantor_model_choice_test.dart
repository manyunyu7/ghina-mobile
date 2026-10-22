import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_actions.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_session_page.dart';

Future<void> _open(WidgetTester t, String status) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final feed = KantorOfficeFeed('o', null)
    ..loading = false
    ..office = {
      'sessions': [
        {'sid': 's1', 'status': status, 'tmux': 'x', 'title': 'Dina'},
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
  await t.tap(find.byTooltip('Aksi sesi'));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('KantorModelChoice reads the daemon rows', () {
    final c = KantorModelChoice.fromJson({
      'index': 4,
      'label': 'Sonnet 5.5',
      'desc': 'Efisien',
      'current': true,
    });
    expect(
      (c.index, c.label, c.desc, c.current),
      (4, 'Sonnet 5.5', 'Efisien', true),
    );
    final d = KantorModelChoice.fromJson({'index': 1, 'label': 'X'});
    expect((d.desc, d.current), ('', false));
  });

  testWidgets(
    'menu: Ganti model is disabled with a reason while the agent works',
    (t) async {
      await _open(t, 'working');
      expect(find.text('Ganti model...'), findsOneWidget);
      expect(
        find.text('Agen sedang bekerja; hentikan atau tunggu'),
        findsOneWidget,
      );
      final item = t.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Ganti model...'),
      );
      expect(item.enabled, isFalse);
    },
  );

  testWidgets('menu: Ganti model is enabled when idle', (t) async {
    await _open(t, 'idle');
    expect(
      find.text('Agen sedang bekerja; hentikan atau tunggu'),
      findsNothing,
    );
    final item = t.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Ganti model...'),
    );
    expect(item.enabled, isTrue);
  });
}
