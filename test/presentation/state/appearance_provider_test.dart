import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/state/appearance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => GhinaType.usesSystemFont = false);

  ProviderContainer container([List<Override> overrides = const []]) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  group('GhinaAccent', () {
    test('9 presets with unique ids; Hijau Ghina first and default', () {
      expect(GhinaAccent.values, hasLength(9));
      expect(GhinaAccent.fallback, GhinaAccent.hijau);
      expect(GhinaAccent.values.map((a) => a.id).toSet(), hasLength(9));
      for (final a in GhinaAccent.values) {
        expect(GhinaAccent.fromId(a.id), a);
        expect(a.label, isNotEmpty);
      }
      expect(GhinaAccent.fromId('neon'), GhinaAccent.hijau);
      expect(GhinaAccent.fromId(null), GhinaAccent.hijau);
    });

    test('presets reuse the palette; green keeps blue selection', () {
      expect(GhinaAccent.hijau.swatch, GhinaColors.green);
      expect(
        GhinaAccent.hijau.highlightFor(Brightness.light),
        GhinaColors.blue,
      );
      expect(GhinaAccent.ungu.swatch, GhinaColors.purple);
      expect(
        GhinaAccent.ungu.highlightFor(Brightness.dark),
        GhinaColors.purple,
      );
      expect(GhinaAccent.teal.swatch, GhinaColors.teal);
      expect(GhinaAccent.emas.swatch, GhinaColors.yellow);
    });
  });

  group('GhinaTheme', () {
    test('the default is the original green look', () {
      for (final t in [GhinaTheme.light(), GhinaTheme.dark()]) {
        final g = t.extension<GhinaTokens>()!;
        expect(t.colorScheme.primary, GhinaColors.green.base);
        expect(g.accent, GhinaColors.green);
        expect(g.highlight, GhinaColors.blue);
        expect(g.flat, isFalse);
      }
      expect(
        GhinaTheme.light().extension<GhinaTokens>(),
        same(GhinaTokens.light),
      );
    });

    test('an accent recolors the brand, never the semantic colors', () {
      final t = GhinaTheme.dark(accent: GhinaAccent.ungu);
      final g = t.extension<GhinaTokens>()!;
      expect(t.colorScheme.primary, GhinaColors.purple.base);
      expect(
        t.floatingActionButtonTheme.backgroundColor,
        GhinaColors.purple.base,
      );
      expect(g.accent, GhinaColors.purple);
      expect(g.highlight, GhinaColors.purple);
      expect(g.income, GhinaColors.green.base);
      expect(g.expense, GhinaColors.red.base);
      expect(t.colorScheme.error, GhinaColors.red.base);
    });

    test('"Datar" sets the flat token', () {
      final g = GhinaTheme.light(
        style: GhinaStyle.datar,
      ).extension<GhinaTokens>()!;
      expect(g.flat, isTrue);
      expect(g.accent, GhinaColors.green);
    });

    test('Minimal: grey neutrals, Monokrom, system font', () {
      final t = GhinaTheme.light(
        accent: GhinaAccent.monokrom,
        style: GhinaStyle.minimal,
      );
      final g = t.extension<GhinaTokens>()!;
      expect(GhinaType.usesSystemFont, isTrue);
      expect(GhinaType.h1.fontFamily, isNull);
      expect(t.colorScheme.primary, const Color(0xFF171717));
      expect(t.colorScheme.onPrimary, Colors.white);
      expect(g.minimal && g.flat, isTrue);
      expect(g.background, const Color(0xFFFFFFFF));
      expect(g.surface, const Color(0xFFF5F5F7));
      expect(g.border, const Color(0xFFE3E3E7));
      expect(g.textPrimary, const Color(0xFF171717));
      expect(g.income, GhinaColors.green.base);
      final d = GhinaTheme.dark(
        accent: GhinaAccent.monokrom,
        style: GhinaStyle.minimal,
      );
      expect(d.colorScheme.primary, const Color(0xFFF5F5F7));
      expect(d.colorScheme.onPrimary, const Color(0xFF171717));
      expect(d.extension<GhinaTokens>()!.background, const Color(0xFF0B0B0C));

      // Building the default theme switches Nunito back on.
      GhinaTheme.light();
      expect(GhinaType.usesSystemFont, isFalse);
      expect(GhinaType.h1.fontFamily, GhinaType.family);
    });

    test('Minimal radii: panels 24, controls 14, pills unchanged', () {
      expect(GhinaRadii.minimal(GhinaRadii.rXl), BorderRadius.circular(24));
      expect(GhinaRadii.minimal(GhinaRadii.rXxl), BorderRadius.circular(24));
      expect(GhinaRadii.minimal(GhinaRadii.rLg), BorderRadius.circular(14));
      expect(GhinaRadii.minimal(GhinaRadii.rMd), BorderRadius.circular(14));
      expect(GhinaRadii.minimal(GhinaRadii.rSm), GhinaRadii.rSm);
      expect(GhinaRadii.minimal(GhinaRadii.rPill), GhinaRadii.rPill);
    });

    test('tokens lerp the accent', () {
      final a = GhinaTokens.light;
      final b = a.copyWith(accent: GhinaColors.purple, style: GhinaStyle.datar);
      expect(a.lerp(b, 0).accent, GhinaColors.green);
      expect(a.lerp(b, 1).accent, GhinaColors.purple);
      expect(a.lerp(b, 1).flat, isTrue);
      expect(a.lerp(b, 0.5).accent.base, isNot(GhinaColors.green.base));
    });
  });

  group('GhinaTextSize', () {
    test('multiplies the system scale, clamped', () {
      const sys = TextScaler.linear(1.2);
      expect(GhinaTextSize.normal.apply(sys), same(sys));
      expect(GhinaTextSize.besar.apply(sys).scale(10), closeTo(13.8, 1e-9));
      expect(GhinaTextSize.kecil.apply(TextScaler.noScaling).scale(10), 9);
      expect(
        GhinaTextSize.ekstra.apply(const TextScaler.linear(1.8)).scale(10),
        GhinaTextSize.maxScale * 10,
      );
      expect(
        GhinaTextSize.kecil.apply(const TextScaler.linear(0.85)).scale(10),
        GhinaTextSize.minScale * 10,
      );
    });
  });

  group('SharedPrefsAppearancePrefs', () {
    test('defaults and round-trips', () async {
      final prefs = SharedPrefsAppearancePrefs();
      expect(await prefs.load(), const GhinaAppearance());
      const v = GhinaAppearance(
        mode: ThemeMode.dark,
        accent: GhinaAccent.teal,
        textSize: GhinaTextSize.ekstra,
        style: GhinaStyle.datar,
      );
      await prefs.save(v);
      expect(await SharedPrefsAppearancePrefs().load(), v);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(SharedPrefsAppearancePrefs.accentKey), 'teal');
      expect(raw.getString(SharedPrefsAppearancePrefs.modeKey), 'dark');
    });

    test('stale values fall back per field', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsAppearancePrefs.modeKey: 'sepia',
        SharedPrefsAppearancePrefs.accentKey: 'ungu',
        SharedPrefsAppearancePrefs.textSizeKey: 'raksasa',
      });
      expect(
        await SharedPrefsAppearancePrefs().load(),
        const GhinaAppearance(accent: GhinaAccent.ungu),
      );
    });
  });

  group('appearanceProvider', () {
    test('loads the saved value, then each setter persists', () async {
      final prefs = InMemoryAppearancePrefs(
        const GhinaAppearance(accent: GhinaAccent.pink),
      );
      final c = container([appearancePrefsProvider.overrideWithValue(prefs)]);
      expect(c.read(appearanceProvider), const GhinaAppearance());
      await _flush();
      expect(c.read(appearanceProvider).accent, GhinaAccent.pink);

      final ctrl = c.read(appearanceProvider.notifier);
      await ctrl.setMode(ThemeMode.light);
      await ctrl.setAccent(GhinaAccent.oranye);
      await ctrl.setTextSize(GhinaTextSize.besar);
      await ctrl.setStyle(GhinaStyle.datar);
      const want = GhinaAppearance(
        mode: ThemeMode.light,
        accent: GhinaAccent.oranye,
        textSize: GhinaTextSize.besar,
        style: GhinaStyle.datar,
      );
      expect(c.read(appearanceProvider), want);
      expect(prefs.value, want);

      await ctrl.reset();
      expect(c.read(appearanceProvider), const GhinaAppearance());
      expect(prefs.value.isDefault, isTrue);
    });

    test('Minimal brings Monokrom unless an accent was picked', () async {
      final c = container([
        appearancePrefsProvider.overrideWithValue(InMemoryAppearancePrefs()),
      ]);
      final ctrl = c.read(appearanceProvider.notifier);
      await ctrl.setStyle(GhinaStyle.minimal);
      expect(c.read(appearanceProvider).accent, GhinaAccent.monokrom);
      await ctrl.setStyle(GhinaStyle.datar);
      expect(c.read(appearanceProvider).accent, GhinaAccent.hijau);

      await ctrl.setAccent(GhinaAccent.ungu);
      await ctrl.setStyle(GhinaStyle.minimal);
      expect(c.read(appearanceProvider).accent, GhinaAccent.ungu);
      await ctrl.setStyle(GhinaStyle.chunky);
      expect(c.read(appearanceProvider).accent, GhinaAccent.ungu);
    });

    test('a change before the load finishes wins', () async {
      final prefs = InMemoryAppearancePrefs(
        const GhinaAppearance(accent: GhinaAccent.pink),
      );
      final c = container([appearancePrefsProvider.overrideWithValue(prefs)]);
      c.read(appearanceProvider);
      await c.read(appearanceProvider.notifier).setAccent(GhinaAccent.biru);
      await _flush();
      expect(c.read(appearanceProvider).accent, GhinaAccent.biru);
    });

    test(
      'preloaded value shows at once; preload falls back on errors',
      () async {
        final c = container([
          appearanceInitialProvider.overrideWithValue(
            const GhinaAppearance(mode: ThemeMode.dark),
          ),
          appearancePrefsProvider.overrideWithValue(InMemoryAppearancePrefs()),
        ]);
        expect(c.read(appearanceProvider).mode, ThemeMode.dark);

        SharedPreferences.setMockInitialValues({
          SharedPrefsAppearancePrefs.accentKey: 'merah',
        });
        expect((await preloadAppearance()).accent, GhinaAccent.merah);
        expect(
          await preloadAppearance(_ThrowingPrefs()),
          const GhinaAppearance(),
        );
      },
    );
  });
}

class _ThrowingPrefs implements AppearancePrefs {
  @override
  Future<GhinaAppearance> load() => Future.error(StateError('boom'));

  @override
  Future<void> save(GhinaAppearance value) async {}
}
