// Daftar Mac dan layar pairing di layar sempit (cover Fold ±320dp)
// dan lebar (Fold terbuka / tablet).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/remote/remote_hosts_page.dart';
import 'package:ghina/presentation/features/remote/remote_hub_pages.dart';
import 'package:ghina/presentation/features/remote/remote_hubs.dart';
import 'package:ghina/presentation/features/remote/remote_pairing.dart';
import 'package:ghina/presentation/features/habits/lock/habit_lock.dart';
import 'package:ghina/presentation/features/remote/remote_protocol.dart';
import 'package:ghina/presentation/features/remote/remote_security.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _NoAuth implements HabitAuthenticator {
  int calls = 0;
  @override
  Future<bool> canAuthenticate() async => true;
  @override
  Future<HabitAuthOutcome> authenticate(String reason) async {
    calls++;
    return HabitAuthOutcome.cancelled;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteLock.reset();
  });

  testWidgets('cancelled biometrics keep the session closed', (t) async {
    final auth = _NoAuth();
    await _pump(
      t,
      const Size(400, 800),
      RemoteHostsPage(
        load: () async => _hosts,
        lock: RemoteLock(auth: auth),
      ),
    );
    await t.tap(find.textContaining('Mac mini kantor'));
    await t.pumpAndSettle();
    expect(auth.calls, 1);
    expect(find.text('Verifikasi dibatalkan.'), findsOneWidget);
    expect(find.text('Remote Mac'), findsOneWidget); // still on the list
  });

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

  testWidgets('pairing screen fits the Fold cover screen', (t) async {
    await _pump(
      t,
      const Size(320, 640),
      Scaffold(
        body: RemotePairingView(
          owner: KantorApi(
            const KantorConfig(baseUrl: 'http://127.0.0.1:9', token: 'x'),
          ),
          onPaired: (_) {},
          notice: 'Izin perangkat ini sudah dicabut.',
        ),
      ),
    );
    expect(find.text('Pasangkan perangkat ini'), findsOneWidget);
    expect(find.text('Minta pairing'), findsOneWidget);
    expect(find.textContaining('dicabut'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('relay hub asks for the owner token once, then pairing', (
    t,
  ) async {
    final secrets = MemoryRemoteSecrets();
    final store = RemoteHubStore(secrets: secrets);
    const relay = RemoteHub(
      id: 'r1',
      name: 'VPS',
      url: 'https://relay.example',
      kind: RemoteHubKind.relay,
    );
    await _pump(
      t,
      const Size(320, 640),
      Scaffold(
        body: RemoteHubPairing(
          hub: relay,
          store: store,
          kantorToken: 'kantor-token',
          onPaired: (_) {},
        ),
      ),
    );
    await t.pump();
    expect(find.text('Token owner relay VPS'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'salah');
    await t.tap(find.text('Lanjut'));
    await t.pump();
    expect(find.textContaining('kcowner_'), findsWidgets);
    await t.enterText(find.byType(TextField), 'kcowner_0123456789abcdef');
    await t.tap(find.text('Lanjut'));
    await t.pump();
    await t.pump();
    expect(find.text('Pasangkan perangkat ini di VPS'), findsOneWidget);
    expect(await store.ownerToken('r1'), 'kcowner_0123456789abcdef');
    expect(t.takeException(), isNull);
  });
}
