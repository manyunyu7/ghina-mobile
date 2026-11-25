// Daftar Mac dan baris tombol keyboard di layar sempit (cover Fold ±320dp)
// dan lebar (Fold terbuka / tablet).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_hosts_page.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_keys.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_protocol.dart';
import 'package:ghina/presentation/features/kantor/remote/remote_widgets.dart';

final _hosts = RemoteHost.listFromJson([
  {
    'machine': 'mini',
    'name': 'Mac mini kantor dengan nama yang sangat panjang sekali',
    'online': true,
    'version': '1.0.0',
    'displays': [
      {'id': 1, 'name': 'Studio Display', 'w': 5120, 'h': 2880, 'scale': 2},
      {'id': 2, 'name': 'Built-in', 'w': 3024, 'h': 1964, 'scale': 2},
    ],
  },
  {'machine': 'mbp', 'name': 'MacBook Pro', 'online': false},
]);

Future<void> _pump(WidgetTester t, Size size, Widget child) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [kantorApiProvider.overrideWith((_) => null)],
      child: MaterialApp(theme: GhinaTheme.light(), home: child),
    ),
  );
  await t.pump();
}

void main() {
  for (final size in const [Size(320, 700), Size(900, 800)]) {
    testWidgets('hosts list at ${size.width.toInt()}dp', (t) async {
      await _pump(t, size, RemoteHostsPage(load: () async => _hosts));
      expect(find.textContaining('Mac mini kantor'), findsOneWidget);
      expect(find.text('MacBook Pro'), findsOneWidget);
      expect(find.textContaining('2 layar'), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(t.takeException(), isNull);

      // offline Mac: explains instead of opening a session
      await t.tap(find.text('MacBook Pro'));
      await t.pump();
      expect(find.textContaining('MacBook Pro offline'), findsOneWidget);
    });
  }

  testWidgets('empty list explains how to add a Mac', (t) async {
    await _pump(t, const Size(400, 800), RemoteHostsPage(load: () async => []));
    expect(find.text('Belum ada Mac terdaftar'), findsOneWidget);
  });

  testWidgets('key bar fits a narrow screen and reports taps', (t) async {
    final sticky = StickyModifiers();
    final keys = <String>[];
    final mods = <RemoteMod>[];
    final shortcuts = <String>[];
    var pasted = 0;
    await _pump(
      t,
      const Size(320, 600),
      Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: RemoteKeyBar(
          sticky: sticky,
          onKey: keys.add,
          onMod: mods.add,
          onShortcut: (code, m) =>
              shortcuts.add('$code${m.map((e) => e.wire)}'),
          onPaste: () => pasted++,
          onClose: () {},
        ),
      ),
    );
    expect(t.takeException(), isNull);
    await t.tap(find.text('esc'));
    await t.tap(find.text('⌘'));
    // the row scrolls sideways on a narrow screen
    await t.scrollUntilVisible(
      find.text('⌘V'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('⌘C'));
    await t.tap(find.text('⌘V'));
    expect(keys, ['Escape']);
    expect(mods, [RemoteMod.meta]);
    expect(shortcuts, ['KeyC(meta)']);
    expect(pasted, 1);
  });
}
