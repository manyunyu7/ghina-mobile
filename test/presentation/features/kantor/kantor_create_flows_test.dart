import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/agents/kantor_agents_tab.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_page.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_roles_tab.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dina = {
  'id': 'dina',
  'name': 'Dina',
  'title': 'Backend',
  'model': 'sonnet',
  'room': 'kode',
  'color': '#2F5D9E',
  'hair': '#2B1D14',
  'skin': '#F1C9A5',
  'hairStyle': 'hijab',
};

/// Chunky buttons upper-case their label.
Finder _btn(String label) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.toLowerCase() == label.toLowerCase(),
);

void main() {
  late HttpServer server;
  final posts = <String, Map<String, dynamic>>{};
  var roles = <Map<String, dynamic>>[];
  var failCreate = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      final body = raw.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final p = req.uri.path;
      Object out = {'ok': true};
      var status = 200;
      if (req.method == 'POST') posts[p] = body;
      if (p == '/api/offices/o') {
        out = {
          'id': 'o',
          'name': 'Kantor O',
          'roles': roles,
          'sessions': <dynamic>[],
          'plan': {
            'rooms': [
              {'id': 'kode', 'name': 'Kode', 'kind': 'kode', 'path': ''},
            ],
          },
        };
      } else if (p == '/api/offices/o/roles' && req.method == 'GET') {
        out = roles;
      } else if (p == '/api/offices/o/roles' && req.method == 'POST') {
        if (failCreate) {
          status = 400;
          out = {'error': 'Nama sudah dipakai'};
        } else {
          out = {..._dina, ...body, 'id': 'gilang'};
          roles = [...roles, out as Map<String, dynamic>];
        }
      } else if (p == '/api/inbox') {
        out = <dynamic>[];
      } else if (p == '/api/offices/o/board') {
        out = {'cards': <dynamic>[]};
      } else if (p.endsWith('/start')) {
        out = {'sid': 'sess1'};
      }
      req.response.statusCode = status;
      req.response.headers.set('connection', 'close');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(out));
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(() {
    posts.clear();
    roles = [];
    failCreate = false;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    });
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpApp(
    WidgetTester t,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: home),
        ),
        GoRoute(
          path: '/kantor/new',
          builder: (_, _) => const Scaffold(body: Text('HALAMAN WIZARD')),
        ),
        GoRoute(
          path: '/kantor/o/:id/s/:sid',
          builder: (_, s) =>
              Scaffold(body: Text('SESI ${s.pathParameters['sid']}')),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorApiProvider.overrideWithValue(
            KantorApi(
              KantorConfig(
                baseUrl: 'http://127.0.0.1:${server.port}',
                token: 't',
              ),
            ),
          ),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  testWidgets('Agen baru: FAB di tab Agen memulai shift role', (t) async {
    roles = [Map<String, dynamic>.from(_dina)];
    await pumpApp(t, const KantorAgentsTab(officeId: 'o'));
    expect(find.text('Agen baru'), findsWidgets);
    await t.tap(find.widgetWithText(FloatingActionButton, 'Agen baru'));
    await settle(t);
    expect(find.text('Role'), findsWidgets);
    expect(find.text('Dina'), findsWidgets);
    await t.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('mis. perbaiki'),
      ),
      'cek tes',
    );
    await t.ensureVisible(_btn('Mulai shift').last);
    await t.tap(_btn('Mulai shift').last);
    await settle(t);
    expect(posts.keys, contains('/api/offices/o/roles/dina/start'));
    expect(posts['/api/offices/o/roles/dina/start']?['task'], 'cek tes');
    expect(find.text('SESI sess1'), findsOneWidget);
    await finish(t);
  });

  testWidgets('Agen baru tanpa role menawarkan buat role', (t) async {
    await pumpApp(t, const KantorAgentsTab(officeId: 'o'));
    await t.tap(find.widgetWithText(FloatingActionButton, 'Agen baru'));
    await settle(t);
    expect(find.text('Belum ada role'), findsOneWidget);
    await t.tap(_btn('Buat role baru'));
    await settle(t);
    expect(find.text('Tambah role'), findsWidgets);
    await finish(t);
  });

  testWidgets('Tambah role: buat lalu mulai shift sekarang', (t) async {
    await pumpApp(t, const KantorRolesTab(officeId: 'o'));
    expect(find.text('Belum ada role'), findsOneWidget);
    await t.tap(find.widgetWithText(FloatingActionButton, 'Tambah role'));
    await settle(t);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Gilang');
    await t.enterText(fields.at(1), 'Desainer');
    await t.scrollUntilVisible(
      _btn('Buat role'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(_btn('Buat role'));
    await settle(t);
    expect(posts['/api/offices/o/roles']?['name'], 'Gilang');
    expect(posts['/api/offices/o/roles']?['title'], 'Desainer');
    expect(find.text('Mulai shift sekarang?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Mulai shift'));
    await settle(t);
    await t.tap(_btn('Mulai shift').last);
    await settle(t);
    expect(posts.containsKey('/api/offices/o/roles/gilang/start'), isTrue);
    expect(find.text('SESI sess1'), findsOneWidget);
    await finish(t);
  });

  testWidgets('Tambah role: error server tampil dan form tetap terbuka', (
    t,
  ) async {
    failCreate = true;
    await pumpApp(t, const KantorRolesTab(officeId: 'o'));
    await t.tap(find.widgetWithText(FloatingActionButton, 'Tambah role'));
    await settle(t);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Gilang');
    await t.enterText(fields.at(1), 'Desainer');
    await t.scrollUntilVisible(
      _btn('Buat role'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(_btn('Buat role'));
    await settle(t);
    expect(find.textContaining('Nama sudah dipakai'), findsWidgets);
    expect(_btn('Buat role'), findsOneWidget);
    await finish(t);
  });

  testWidgets('Kompleks: FAB Kantor baru membuka wizard', (t) async {
    await pumpApp(
      t,
      const KantorComplexPage(),
      overrides: [
        kantorStateProvider.overrideWith(
          (_) async => {'offices': [], 'inbox': [], 'loose': []},
        ),
        kantorEndedProvider.overrideWith((_) async => const []),
        kantorLastOfficeProvider.overrideWith((_) async => null),
      ],
    );
    await t.tap(find.widgetWithText(FloatingActionButton, 'Kantor baru'));
    await settle(t);
    expect(find.text('HALAMAN WIZARD'), findsOneWidget);
    await finish(t);
  });
}
