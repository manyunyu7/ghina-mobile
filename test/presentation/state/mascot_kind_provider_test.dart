import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/mascot/mascot_kind.dart';
import 'package:ghina/presentation/state/mascot_kind_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container([List<Override> overrides = const []]) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  group('MascotKind', () {
    test('15 mascots with unique ids, names and pitches; tree first', () {
      expect(MascotKind.values, hasLength(15));
      expect(MascotKind.values.first, MascotKind.pohon);
      expect(MascotKind.fallback, MascotKind.pohon);
      expect(MascotKind.values.map((k) => k.id).toSet(), hasLength(15));
      for (final k in MascotKind.values) {
        expect(k.label, isNotEmpty);
        expect(k.pitch.length, greaterThan(20));
        expect(MascotKind.fromId(k.id), k);
      }
    });

    test('unknown or missing id falls back to the tree', () {
      expect(MascotKind.fromId(null), MascotKind.pohon);
      expect(MascotKind.fromId('naga'), MascotKind.pohon);
    });
  });

  group('SharedPrefsMascotKindPrefs', () {
    test('defaults to the tree and round-trips', () async {
      final prefs = SharedPrefsMascotKindPrefs();
      expect(await prefs.load(), MascotKind.pohon);
      await prefs.save(MascotKind.komodo);
      expect(await SharedPrefsMascotKindPrefs().load(), MascotKind.komodo);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(SharedPrefsMascotKindPrefs.key), 'komodo');
    });

    test('a stale stored id falls back to the tree', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsMascotKindPrefs.key: 'dinosaurus',
      });
      expect(await SharedPrefsMascotKindPrefs().load(), MascotKind.pohon);
    });
  });

  group('mascotKindProvider', () {
    test('defaults to the tree', () async {
      final c = container();
      expect(c.read(mascotKindProvider), MascotKind.pohon);
      await _flush();
      expect(c.read(mascotKindProvider), MascotKind.pohon);
    });

    test('select updates state and writes the prefs', () async {
      final prefs = InMemoryMascotKindPrefs();
      final c = container([mascotKindPrefsProvider.overrideWithValue(prefs)]);
      c.read(mascotKindProvider);
      await _flush();
      await c.read(mascotKindProvider.notifier).select(MascotKind.beluga);
      expect(c.read(mascotKindProvider), MascotKind.beluga);
      expect(prefs.value, MascotKind.beluga);
    });

    test('loads the saved choice asynchronously', () async {
      final prefs = InMemoryMascotKindPrefs(MascotKind.kucing);
      final c = container([mascotKindPrefsProvider.overrideWithValue(prefs)]);
      expect(c.read(mascotKindProvider), MascotKind.pohon);
      await _flush();
      expect(c.read(mascotKindProvider), MascotKind.kucing);
    });

    test('a pick made before the load finished wins', () async {
      final prefs = InMemoryMascotKindPrefs(MascotKind.kucing);
      final c = container([mascotKindPrefsProvider.overrideWithValue(prefs)]);
      c.read(mascotKindProvider);
      final pick = c
          .read(mascotKindProvider.notifier)
          .select(MascotKind.orangutan);
      await pick;
      await _flush();
      expect(c.read(mascotKindProvider), MascotKind.orangutan);
    });

    test('persists across restarts; preload is synchronous', () async {
      final a = container();
      a.read(mascotKindProvider);
      await _flush();
      await a.read(mascotKindProvider.notifier).select(MascotKind.hiuPaus);
      a.dispose();

      final b = container();
      b.read(mascotKindProvider);
      await _flush();
      await _flush();
      expect(b.read(mascotKindProvider), MascotKind.hiuPaus);

      final pre = await preloadMascotKind();
      final d = container([mascotKindInitialProvider.overrideWithValue(pre)]);
      expect(d.read(mascotKindProvider), MascotKind.hiuPaus);
    });
  });
}
