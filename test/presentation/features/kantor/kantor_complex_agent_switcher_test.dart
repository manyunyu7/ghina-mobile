import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart'
    show KantorConfigStore;
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_agent_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  const profiles = [
    KantorComplexProfile(
      id: 'mac',
      name: 'Mac Mini',
      baseUrl: 'https://mac.test',
      token: 'mac-token',
    ),
    KantorComplexProfile(
      id: 'vps',
      name: 'VPS',
      baseUrl: 'https://vps.test',
      token: 'vps-token',
    ),
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.complexes.v1': jsonEncode({
        'activeId': 'mac',
        'profiles': profiles.map((p) => p.toJson()).toList(),
      }),
    });
  });

  Map<String, dynamic> state(String name) => {
    'offices': [
      {
        'id': 'same-office',
        'name': 'buddget',
        'sessions': [
          {
            'sid': 'same-session',
            'status': name == 'Sari' ? 'waiting' : 'working',
            'look': {'name': name},
          },
        ],
      },
    ],
  };

  testWidgets('search spans complexes and same session IDs remain distinct', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorComplexStateProvider(
            'mac',
          ).overrideWith((_) async => state('Sari')),
          kantorComplexStateProvider(
            'vps',
          ).overrideWith((_) async => state('Budi')),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: KantorComplexAgentPicker(
              officeId: 'same-office',
              currentSid: 'same-session',
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Sari'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.enterText(find.byType(TextField), 'vps');
    await t.pumpAndSettle();
    expect(find.text('Sari'), findsNothing);
    expect(find.text('Budi'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'buddget');
    await t.pumpAndSettle();
    expect(find.text('Sari'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);
  });

  testWidgets('offline complex does not hide reachable agents', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorComplexStateProvider(
            'mac',
          ).overrideWith((_) async => state('Sari')),
          kantorComplexStateProvider(
            'vps',
          ).overrideWith((_) async => throw Exception('offline')),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(body: KantorComplexAgentPicker(onNavigate: (_) {})),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Sari'), findsOneWidget);
    expect(find.text('Tidak terhubung'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test(
    'successful cross-complex activation verifies and persists target credentials',
    () async {
      final savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = savedOverrides);
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        String? receivedToken;
        String? receivedPath;
        final listener = server.listen((request) async {
          receivedToken = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          receivedPath = request.uri.path;
          request.response.headers.contentType = ContentType.json;
          request.response.headers.set(HttpHeaders.connectionHeader, 'close');
          request.response.write(jsonEncode(state('Budi')));
          await request.response.close();
        });
        addTearDown(listener.cancel);
        final target = KantorComplexProfile(
          id: 'vps',
          name: 'VPS',
          baseUrl: 'http://127.0.0.1:' + server.port.toString(),
          token: 'vps-token',
        );
        FlutterSecureStorage.setMockInitialValues({
          'kantor.complexes.v1': jsonEncode({
            'activeId': 'mac',
            'profiles': [profiles.first.toJson(), target.toJson()],
          }),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(kantorConfigProvider.future);
        expect(container.read(kantorConfigProvider).value?.token, 'mac-token');
        await container
            .read(kantorConfigProvider.notifier)
            .activate('vps')
            .timeout(const Duration(seconds: 5));
        expect(receivedPath, '/api/state');
        expect(receivedToken, 'Bearer vps-token');
        final persisted = await KantorConfigStore().load();
        expect(persisted.baseUrl, target.baseUrl);
        expect(persisted.token, 'vps-token');
        expect(
          container.read(kantorConfigProvider).value?.baseUrl,
          target.baseUrl,
        );
        expect(container.read(kantorConfigProvider).value?.token, 'vps-token');
        expect(container.read(kantorActiveComplexProvider)?.id, 'vps');
      }, _RealHttpOverrides());
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('global switch sheet fits phone width ' + width.toString(), (
      t,
    ) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              appBar: AppBar(
                title: const Text('Bu Sari'),
                actions: [
                  const KantorComplexSwitcherButton(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorComplexStateProvider(
              'mac',
            ).overrideWith((_) async => state('Sari')),
            kantorComplexStateProvider(
              'vps',
            ).overrideWith((_) async => state('Budi')),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('all-complex-agents')));
      await t.pumpAndSettle();
      expect(find.text('Semua agen · semua kompleks'), findsOneWidget);
      expect(find.text('Sari'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.enterText(find.byType(TextField), 'vps');
      await t.pumpAndSettle();
      expect(find.text('Budi'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('failed destination keeps active config and current chat', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? navigated;
    final container = ProviderContainer(
      overrides: [
        kantorComplexStateProvider(
          'mac',
        ).overrideWith((_) async => state('Sari')),
        kantorComplexStateProvider(
          'vps',
        ).overrideWith((_) async => state('Budi')),
        kantorComplexApiProvider('vps').overrideWith(
          (_) =>
              throw const KantorException(KantorFailure.unreachable, 'offline'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(kantorConfigProvider.future);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: KantorComplexAgentPicker(
              onNavigate: (path) => navigated = path,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Budi'));
    await t.pumpAndSettle();
    expect(navigated, isNull);
    expect(
      container.read(kantorConfigProvider).value?.baseUrl,
      'https://mac.test',
    );
    expect(find.textContaining('Tidak bisa membuka VPS'), findsOneWidget);
  });

  test(
    'recent identity includes complex and office; only session tabs transfer',
    () {
      expect(
        kantorComplexChatIdentity('mac', 'office', 'sid'),
        isNot(kantorComplexChatIdentity('vps', 'office', 'sid')),
      );
      expect(
        kantorComplexChatIdentity('mac', 'office', 'sid'),
        isNot(kantorComplexChatIdentity('mac', 'other', 'sid')),
      );
      expect(kantorSwitchSessionTab('terminal'), 'terminal');
      expect(kantorSwitchSessionTab('board'), isNull);
    },
  );
}
