import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/app/ravel_app.dart';
import 'package:ghina/data/platform/launcher_icon_bridge.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/di/prayer_reminder_providers.dart'
    show launcherIconProvider;
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/mascot_kind_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/design_system/mascot_rig_test.dart' show paintedKind;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// Mirrors `main_ravel.dart`: preloaded mascot, no-op launcher icon.
  Future<void> pumpRavel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final mascot = await preloadMascotKind();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kantorOnlyProvider.overrideWithValue(true),
          mascotKindInitialProvider.overrideWithValue(mascot),
          launcherIconProvider.overrideWithValue(const NoopLauncherIcon()),
          tokenStoreProvider.overrideWith(
            (_) => throw StateError('Ghina auth must not initialize'),
          ),
          appDatabaseProvider.overrideWith(
            (_) => throw StateError('Finance DB must not initialize'),
          ),
        ],
        child: const RavelApp(),
      ),
    );
    await frames(tester, 20);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<Finder> reveal(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    // The settings ListView is lazy: scroll entries into existence first.
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pump();
    return f;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(await reveal(tester, key));
    await frames(tester, 10);
  }

  final welcome = find.text('Pilih maskotmu');

  testWidgets('uses the saved mascot instead of the tree', (tester) async {
    SharedPreferences.setMockInitialValues({
      SharedPrefsMascotKindPrefs.key: 'kucing',
      ravelMascotChosenKey: true,
    });
    await pumpRavel(tester);
    expect(welcome, findsNothing);
    final mascots = find.byType(MascotView);
    expect(mascots, findsWidgets);
    expect(paintedKind(tester, mascots.first), MascotKind.kucing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('settings show the mascot and open the picker', (tester) async {
    SharedPreferences.setMockInitialValues({
      SharedPrefsMascotKindPrefs.key: 'kucing',
      ravelMascotChosenKey: true,
    });
    // Without a token Ravel lands on the Kompleks settings page.
    await pumpRavel(tester);
    final tile = await reveal(tester, 'kantor-settings-mascot');
    expect(
      find.descendant(of: tile, matching: find.textContaining('Kucing Oren')),
      findsOneWidget,
    );
    await tester.tap(tile);
    await frames(tester, 10);
    expect(find.text('Pilih maskot'), findsOneWidget);
    expect(find.textContaining('nemenin kamu di kantor'), findsOneWidget);
    expect(find.textContaining('Ikon & layar pembuka'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Tampilan: switching to Gelap puts Ravel in dark mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({ravelMascotChosenKey: true});
    await pumpRavel(tester);
    ThemeMode? mode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode;
    expect(mode(), ThemeMode.system);

    await tapKey(tester, 'kantor-settings-appearance');
    expect(find.text('Tema & warna'), findsOneWidget);
    // Ravel previews Kantor content, not money.
    expect(find.text('Saldo kamu'), findsNothing);
    expect(find.text('Kantor kamu'), findsOneWidget);

    await tester.tap(find.text('Gelap'));
    await frames(tester, 10);
    expect(mode(), ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appearance.mode'), 'dark');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('first run offers the picker once; a pick sticks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpRavel(tester);
    expect(welcome, findsOneWidget);
    await tapKey(tester, 'mascot-tile-kapibara');
    expect(find.text('PAKAI KAPIBARA'), findsOneWidget);
    await tapKey(tester, 'mascot-welcome-use');
    expect(welcome, findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SharedPrefsMascotKindPrefs.key), 'kapibara');
    expect(prefs.getBool(ravelMascotChosenKey), isTrue);
    expect(
      paintedKind(tester, find.byType(MascotView).first),
      MascotKind.kapibara,
    );
    await unmount(tester);

    // Next launch: no picker, the pick is kept.
    await pumpRavel(tester);
    expect(welcome, findsNothing);
    expect(
      paintedKind(tester, find.byType(MascotView).first),
      MascotKind.kapibara,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('"Nanti saja" keeps the tree and never asks again', (
    tester,
  ) async {
    // An install from before this release (no flag yet) gets it once too.
    SharedPreferences.setMockInitialValues({'kantor.some_setting': 'x'});
    await pumpRavel(tester);
    expect(welcome, findsOneWidget);
    await tapKey(tester, 'mascot-welcome-later');
    expect(welcome, findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SharedPrefsMascotKindPrefs.key), isNull);
    expect(prefs.getBool(ravelMascotChosenKey), isTrue);
    await unmount(tester);

    await pumpRavel(tester);
    expect(welcome, findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}

/// Advances frames without pumpAndSettle (the mascots animate forever).
Future<void> frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
