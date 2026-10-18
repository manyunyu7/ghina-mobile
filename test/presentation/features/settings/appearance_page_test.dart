import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/settings/pages/appearance_page.dart';
import 'package:ghina/presentation/state/appearance_provider.dart';
import 'package:ghina/presentation/state/mascot_kind_provider.dart';

import '../transactions/_feature_harness.dart' show settle;

/// Same theme wiring as `GhinaApp` (themes, mode, text scale, mascot).
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    return MaterialApp(
      theme: GhinaTheme.light(accent: look.accent, style: look.style),
      darkTheme: GhinaTheme.dark(accent: look.accent, style: look.style),
      themeMode: look.mode,
      builder: (_, child) =>
          AppearanceScope(child: MascotKindScope(child: child!)),
      home: const AppearancePage(),
    );
  }
}

void main() {
  late InMemoryAppearancePrefs prefs;
  late ProviderContainer c;

  setUp(() {
    prefs = InMemoryAppearancePrefs();
    c = ProviderContainer(
      overrides: [
        appearancePrefsProvider.overrideWithValue(prefs),
        mascotKindPrefsProvider.overrideWithValue(InMemoryMascotKindPrefs()),
      ],
    );
  });
  tearDown(() {
    c.dispose();
    GhinaType.usesSystemFont = false;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const _App()),
    );
    await settle(tester);
  }

  /// Taps [f] (scrolled into view) and lets the theme animation finish.
  /// Never pumpAndSettle: the mascot animates forever.
  Future<void> tap(WidgetTester tester, Finder f) async {
    // Centered: a confirmation toast covers the top of the screen.
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  /// Lets the confirmation toasts leave (no pending timers).
  Future<void> toastsGone(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final previewButton = find.descendant(
    of: find.byKey(const ValueKey('appearance-preview-button')),
    matching: find.byType(ChunkySurface),
  );
  Color buttonFace(WidgetTester tester) =>
      tester.widget<ChunkySurface>(previewButton).color;

  Color incomeColor(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('appearance-preview-income')),
          matching: find.byType(Text),
        ),
      )
      .style!
      .color!;

  ThemeMode themeMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  testWidgets('defaults: system mode, original green, normal text', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Tema & warna'), findsOneWidget);
    expect(themeMode(tester), ThemeMode.system);
    expect(buttonFace(tester), GhinaColors.green.base);
    expect(incomeColor(tester), GhinaColors.green.base);
    expect(find.byKey(const ValueKey('appearance-preview-mascot')), findsOne);
    expect(
      tester
          .widget<ChunkyButton>(find.byKey(const ValueKey('appearance-reset')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('"Gelap" switches the app to dark mode and is saved', (
    tester,
  ) async {
    await pumpPage(tester);
    await tap(tester, find.text('Gelap'));
    expect(themeMode(tester), ThemeMode.dark);
    expect(prefs.value.mode, ThemeMode.dark);
    final ctx = tester.element(
      find.byKey(const ValueKey('appearance-preview')),
    );
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(ctx.ghina.isDark, isTrue);

    await tap(tester, find.text('Terang'));
    expect(themeMode(tester), ThemeMode.light);
    await toastsGone(tester);
  });

  testWidgets('"Ungu" recolors the primary button; income stays green', (
    tester,
  ) async {
    await pumpPage(tester);
    await tap(tester, find.byKey(const ValueKey('accent-ungu')));
    expect(prefs.value.accent, GhinaAccent.ungu);
    expect(buttonFace(tester), GhinaColors.purple.base);
    expect(incomeColor(tester), GhinaColors.green.base);
    final ctx = tester.element(
      find.byKey(const ValueKey('appearance-preview')),
    );
    expect(ctx.ghina.accent, GhinaColors.purple);
    expect(ctx.ghina.income, GhinaColors.green.base);
    expect(Theme.of(ctx).colorScheme.primary, GhinaColors.purple.base);
    expect(find.bySemanticsLabel('Ungu, dipakai'), findsOneWidget);

    // Back to Hijau Ghina: the exact original swatch again.
    await tap(tester, find.byKey(const ValueKey('accent-hijau')));
    expect(buttonFace(tester), GhinaColors.green.base);
    await toastsGone(tester);
  });

  testWidgets('text size multiplies the text scale', (tester) async {
    await pumpPage(tester);
    double scale() => MediaQuery.textScalerOf(
      tester.element(find.byKey(const ValueKey('appearance-preview'))),
    ).scale(10);
    expect(scale(), 10);
    await tap(tester, find.text('Besar'));
    expect(prefs.value.textSize, GhinaTextSize.besar);
    expect(scale(), closeTo(11.5, 1e-9));
    await tap(tester, find.text('Kecil'));
    expect(scale(), closeTo(9, 1e-9));
    await toastsGone(tester);
  });

  testWidgets('"Datar" drops the 3D edge; reset restores everything', (
    tester,
  ) async {
    await pumpPage(tester);
    double buttonHeight() => tester.getSize(previewButton).height;
    expect(buttonHeight(), 46 + 4); // medium face + chunky edge

    await tap(tester, find.text('Datar'));
    expect(prefs.value.style, GhinaStyle.datar);
    expect(buttonHeight(), 46);

    await tap(tester, find.byKey(const ValueKey('accent-teal')));
    await tap(tester, find.text('Gelap'));
    expect(prefs.value.isDefault, isFalse);

    await tap(tester, find.byKey(const ValueKey('appearance-reset')));
    expect(prefs.value, const GhinaAppearance());
    expect(themeMode(tester), ThemeMode.system);
    expect(buttonHeight(), 50);
    expect(buttonFace(tester), GhinaColors.green.base);
    await toastsGone(tester);
  });

  testWidgets('"Minimal": near-black button, system font, no edge', (
    tester,
  ) async {
    await pumpPage(tester);
    Text buttonLabel() => tester.widget<Text>(
      find.descendant(of: previewButton, matching: find.byType(Text)),
    );
    expect(buttonLabel().data, 'SIMPAN');
    expect(buttonLabel().style!.fontFamily, GhinaType.family);

    await tap(tester, find.text('Minimal'));
    expect(prefs.value.style, GhinaStyle.minimal);
    expect(prefs.value.accent, GhinaAccent.monokrom);
    expect(buttonFace(tester), const Color(0xFF171717));
    expect(tester.getSize(previewButton).height, 46);
    expect(buttonLabel().data, 'Simpan');
    expect(buttonLabel().style!.fontFamily, isNull);
    expect(incomeColor(tester), GhinaColors.green.base);
    final ctx = tester.element(
      find.byKey(const ValueKey('appearance-preview')),
    );
    expect(ctx.ghina.background, const Color(0xFFFFFFFF));
    expect(ctx.ghina.surface, const Color(0xFFF5F5F7));
    // The preview card: 24 radius and a soft shadow, no chunky edge.
    final card = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byKey(const ValueKey('appearance-preview')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final deco = card.decoration! as BoxDecoration;
    expect(deco.borderRadius, BorderRadius.circular(24));
    expect(deco.boxShadow, GhinaShadows.soft);

    // A picked accent stays when Minimal is on.
    await tap(tester, find.byKey(const ValueKey('accent-biru')));
    expect(buttonFace(tester), GhinaColors.blue.base);

    // Dark mode flips Monokrom to near-white.
    await tap(tester, find.byKey(const ValueKey('accent-monokrom')));
    await tap(tester, find.text('Gelap'));
    expect(buttonFace(tester), const Color(0xFFF5F5F7));

    // Back to Chunky: Hijau and Nunito again.
    await tap(tester, find.text('Chunky'));
    expect(prefs.value.accent, GhinaAccent.hijau);
    expect(buttonLabel().style!.fontFamily, GhinaType.family);
    expect(buttonLabel().data, 'SIMPAN');
    await toastsGone(tester);
  });

  testWidgets('a swatch tap clicks and confirms; fast taps replace the toast', (
    tester,
  ) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(tester);
    await tap(tester, find.byKey(const ValueKey('accent-ungu')));
    expect(find.text('Warna aksen: Ungu'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));

    await tap(tester, find.byKey(const ValueKey('accent-biru')));
    await tap(tester, find.byKey(const ValueKey('accent-pink')));
    expect(find.text('Warna aksen: Pink'), findsOneWidget);
    expect(find.text('Warna aksen: Biru'), findsNothing);
    expect(find.text('Warna aksen: Ungu'), findsNothing);

    await tap(tester, find.text('Gelap'));
    expect(find.text('Mode: Gelap'), findsOneWidget);
    await tap(tester, find.text('Besar'));
    expect(find.text('Teks: Besar'), findsOneWidget);
    await tap(tester, find.text('Minimal'));
    expect(find.text('Gaya: Minimal'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('appearance-reset')));
    expect(find.text('Kembali ke default'), findsOneWidget);
    expect(find.text('Gaya: Minimal'), findsNothing);
    await toastsGone(tester);
    expect(find.text('Kembali ke default'), findsNothing);
  });

  testWidgets('the preview button says it is only a sample', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(tester);
    expect(
      find.text('Pratinjau · perubahan langsung tersimpan'),
      findsOneWidget,
    );
    await tap(tester, previewButton);
    expect(
      find.text('Ini cuma contoh tombol — pilihanmu sudah otomatis tersimpan'),
      findsOneWidget,
    );
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
    expect(prefs.value, const GhinaAppearance());
    await toastsGone(tester);
  });
}
