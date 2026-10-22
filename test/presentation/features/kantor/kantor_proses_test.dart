import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/proses/kantor_proses_data.dart';
import 'package:ghina/presentation/features/kantor/roles/kantor_role.dart'
    show kantorRolesProvider;
import 'package:ghina/presentation/features/kantor/proses/kantor_proses_log.dart';
import 'package:ghina/presentation/features/kantor/proses/kantor_proses_page.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_adopt.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _office = {
  'id': 'a',
  'name': 'Kantor Alpha',
  'plan': {
    'rooms': [
      {'id': 'kode', 'name': 'Kode', 'path': ''},
      {'id': 'web', 'name': 'Web', 'path': 'web'},
    ],
  },
  'sessions': <dynamic>[],
};

void main() {
  late HttpServer server;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  var logText = 'mulai\n\x1B[32mSiap di :5173\x1B[0m\n';

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      final p = req.uri.path;
      calls.add('${req.method} $p');
      if (raw.isNotEmpty) {
        bodies[p] = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
      Object out = {'ok': true};
      if (p == '/api/offices/a') {
        out = _office;
      } else if (p == '/api/offices/a/roles') {
        out = [
          {'id': 'r1', 'name': 'Dina', 'title': 'Backend'},
        ];
      } else if (p == '/api/offices/a/procs' && req.method == 'GET') {
        out = {
          'procs': [
            {
              'id': 'p1',
              'room': 'web',
              'roomName': 'Web',
              'name': 'Dev server',
              'cmd': 'npm run dev',
              'status': 'jalan',
              'since': DateTime.now()
                  .subtract(const Duration(minutes: 5))
                  .toIso8601String(),
              'port': 5173,
              'url': 'http://localhost:5173',
            },
            {
              'id': 'p2',
              'room': 'kode',
              'roomName': 'Kode',
              'name': 'Watcher',
              'cmd': 'make watch',
              'status': 'gagal',
              'code': 2,
              'auto': true,
            },
            {
              'id': 'p3',
              'room': 'kode',
              'roomName': 'Kode',
              'name': 'Seed',
              'cmd': 'php artisan db:seed',
              'status': 'berhenti',
              'pending': true,
            },
          ],
          'suggestions': {
            'web': [
              {'name': 'vite', 'cmd': 'npm run preview', 'why': 'package.json'},
            ],
          },
        };
      } else if (p == '/api/offices/a/procs/p1/log') {
        out = {
          'from': 0,
          'next': logText.length,
          'size': logText.length,
          'text': logText,
        };
      }
      req.response.headers.set('connection', 'close');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(out));
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(() {
    calls.clear();
    bodies.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    });
  });

  KantorApi api() => KantorApi(
    KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 't'),
  );

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorApiProvider.overrideWithValue(api()),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(theme: GhinaTheme.light(), home: home),
      ),
    );
    await settle(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  test('kantorCleanLog strips colour codes and folds carriage returns', () {
    expect(kantorCleanLog('\x1B[32mok\x1B[0m\n'), 'ok\n');
    expect(kantorCleanLog('10%\r50%\r100%\ndone'), '100%\ndone');
  });

  test('kantorDuration', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(
      kantorDuration(now.subtract(const Duration(minutes: 5)), now),
      '5 mnt',
    );
    expect(
      kantorDuration(now.subtract(const Duration(minutes: 130)), now),
      '2 jam 10 mnt',
    );
  });

  testWidgets('lists processes with status, origin and duration', (t) async {
    await pump(t, const KantorProsesPage(officeId: 'a'));
    expect(find.text('Dev server'), findsOneWidget);
    expect(find.text('Jalan'), findsOneWidget);
    expect(find.textContaining('jalan 5 mnt'), findsOneWidget);
    expect(find.text('Gagal · kode 2'), findsOneWidget);
    expect(find.textContaining('Saran otomatis'), findsOneWidget);
    expect(find.text('Menunggu persetujuan'), findsOneWidget);
    expect(find.text('Hentikan'), findsOneWidget);
    await finish(t);
  });

  testWidgets('stop asks for confirmation before calling the API', (t) async {
    await pump(t, const KantorProsesPage(officeId: 'a'));
    await t.tap(find.text('Hentikan'));
    await t.pump(const Duration(milliseconds: 400));
    expect(calls, isNot(contains('POST /api/offices/a/procs/p1/stop')));
    await t.tap(find.text('HENTIKAN'));
    await settle(t);
    expect(calls, contains('POST /api/offices/a/procs/p1/stop'));
    await finish(t);
  });

  testWidgets('approve and start from a pending proposal', (t) async {
    await pump(t, const KantorProsesPage(officeId: 'a'));
    await t.ensureVisible(find.text('Setujui & jalankan'));
    await t.tap(find.text('Setujui & jalankan'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('SETUJUI & JALANKAN'));
    await settle(t);
    expect(bodies['/api/offices/a/procs/p3/approve'], {'start': true});
    await finish(t);
  });

  testWidgets('log page shows cleaned live output', (t) async {
    await pump(t, const KantorProcLogPage(officeId: 'a', procId: 'p1'));
    expect(
      find.textContaining('Siap di :5173', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('\x1B', findRichText: true), findsNothing);
    expect(find.text('Dev server'), findsOneWidget);
    await finish(t);
  });

  testWidgets('adopt posts new role with boss after warning', (t) async {
    await pump(
      t,
      Consumer(
        builder: (c, ref, _) {
          ref.watch(kantorRolesProvider('a')); // keep the roles loaded
          return Scaffold(
            body: TextButton(
              onPressed: () => adoptKantorSession(
                c,
                ref,
                officeId: 'a',
                sid: 's9',
                host: 'vscode',
              ),
              child: const Text('pindah'),
            ),
          );
        },
      ),
    );
    await t.tap(find.text('pindah'));
    await settle(t);
    expect(find.textContaining('salinan resume'), findsWidgets);
    await t.tap(find.text('Tetap sesi tanpa role'));
    await settle(t);
    await t.tap(find.text('+ Role baru'));
    await settle(t);
    await t.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'mis. Gilang',
      ),
      'Gilang',
    );
    await t.tap(find.text('LANJUT'));
    await settle(t);
    // confirmation dialog repeats the warning; nothing was sent yet
    expect(calls.where((c) => c.contains('/adopt')), isEmpty);
    await t.tap(find.text('PINDAHKAN'));
    await settle(t);
    final b = bodies['/api/sessions/s9/adopt']!;
    expect((b['newRole'] as Map)['name'], 'Gilang');
    expect(b['role'], isNull);
    await finish(t);
  });
}
