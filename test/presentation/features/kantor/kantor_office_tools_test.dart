import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_page.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_daemon_settings.dart';
import 'package:ghina/presentation/features/kantor/plan/plan_thumb.dart';
import 'package:ghina/presentation/features/kantor/search/kantor_search.dart';
import 'package:ghina/presentation/features/kantor/templates/kantor_templates.dart';
import 'package:ghina/presentation/features/kantor/wizard/kantor_wizard.dart';
import 'package:ghina/presentation/features/kantor/wizard/kantor_wizard_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _thumb =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10">'
    '<rect width="20" height="10" fill="#9DB3A6"/>'
    '<rect x="2" y="2" width="6" height="4" fill="#2A2430" opacity=".5"/></svg>';

final _plan = {
  'w': 100,
  'h': 80,
  'rooms': [
    {
      'id': 'kode',
      'name': 'Kode',
      'kind': 'kode',
      'x': 20,
      'y': 0,
      'w': 30,
      'h': 30,
      'floor': 'wood',
      'path': '',
    },
    {
      'id': 'web',
      'name': 'Web',
      'kind': 'kode',
      'x': 20,
      'y': 40,
      'w': 30,
      'h': 30,
      'floor': 'wood',
      'path': 'web',
    },
  ],
};

final _state = {
  'offices': [
    {
      'id': 'a',
      'name': 'Kantor Alpha',
      'style': 'Satu repo',
      'root': '/x/alpha',
      'sessions': [
        {
          'sid': 's1',
          'status': 'working',
          'title': 'Perbaiki login',
          'look': {
            'name': 'Dina',
            'title': 'Backend',
            'color': '#2F5D9E',
            'hair': '#2B1D14',
            'skin': '#F1C9A5',
          },
        },
      ],
      'cards': {'open': 1},
    },
    {
      'id': 'b',
      'name': 'Toko Beta',
      'style': 'Folder induk · 3 repo',
      'root': '/x/beta',
      'sessions': <dynamic>[],
      'cards': {'open': 0},
    },
  ],
  'inbox': <dynamic>[],
  'loose': <dynamic>[],
};

void main() {
  late HttpServer server;
  final posts = <String, Map<String, dynamic>>{};
  var previewWarning = false;
  var hasBackup = true;

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
      if (req.method == 'POST') posts[p] = body;
      if (p == '/api/wizard/folders') {
        out = {
          'roots': ['/Users/me/Developer'],
          'folders': [
            {
              'root': '/Users/me/Developer/lama',
              'name': 'lama',
              'base': '/Users/me/Developer',
              'git': true,
              'repos': 0,
              'stack': 'Flutter',
              'md': true,
              'mtime': 1.0,
            },
          ],
        };
      } else if (p == '/api/wizard/preview') {
        out = {
          'root': '/Users/me/Developer/${body['folder']}',
          'name': '${body['name']}',
          'plan': _plan,
          'team': [
            for (final (i, t) in (body['team'] as List).indexed)
              {...(t as Map), 'id': 'r$i', 'room': i == 0 ? 'manager' : 'kode'},
          ],
          'rooms': [
            {'id': 'kode', 'name': 'Kode', 'path': '', 'stack': ''},
            {'id': 'web', 'name': 'Web', 'path': 'web', 'stack': ''},
          ],
          'warnings': previewWarning
              ? ['Folder sudah ada. Pilih folder yang sudah ada.']
              : [],
        };
      } else if (p == '/api/wizard/create') {
        out = {'id': 'baru', 'created': [], 'card': 'c1', 'shift': null};
      } else if (p == '/api/templates') {
        out = {
          'templates': [
            {
              'id': 'zen',
              'name': 'Taman Zen',
              'desc': 'Taman di tengah.',
              'mood': 'tenang',
              'accent': '#6BAE57',
              'thumb': _thumb,
            },
            {
              'id': 'loft',
              'name': 'Loft Industri',
              'desc': 'Bata dan baja.',
              'mood': 'ramai',
              'accent': '#B98F62',
              'thumb': _thumb,
            },
          ],
        };
      } else if (p == '/api/offices/a/template') {
        out = {
          'current': null,
          'backup': hasBackup ? {'at': '2026-10-20T00:00:00Z'} : null,
        };
      } else if (p == '/api/offices/a/template/preview') {
        out = {
          'template': body['template'],
          'seed': body['seed'],
          'newRooms': [
            {'id': 'taman', 'name': 'Taman Zen'},
          ],
          'dropped': [],
          'plan': _plan,
          'problems': [],
        };
      } else if (p == '/api/offices/a/template/apply') {
        out = {'template': body['template'], 'custom': true};
      } else if (p == '/api/offices/a/template/restore') {
        out = {'plan': _plan, 'custom': false};
      } else if (p == '/api/state') {
        out = _state;
      }
      // no keep-alive: its idle timer would outlive the test
      req.response.headers.set('connection', 'close');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(out));
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  setUp(() {
    posts.clear();
    previewWarning = false;
    hasBackup = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    });
  });

  KantorApi api() => KantorApi(
    KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 't'),
  );

  /// Lets real HTTP and the wizard's preview debounce finish.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts, so the wizard's debounce timer and Dio's timeouts are gone
  /// before the test ends.
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  void apiTest(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      await body(t);
      await finish(t);
    });
  }

  Future<void> pumpApp(
    WidgetTester t,
    Widget home, {
    List<Override> overrides = const [],
    bool withApi = true,
    bool withRouter = false,
  }) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final router = withRouter
        ? GoRouter(
            initialLocation: '/kantor',
            routes: [GoRoute(path: '/kantor', builder: (_, _) => home)],
          )
        : null;
    if (router != null) addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          if (withApi) kantorApiProvider.overrideWithValue(api()),
          kantorEventsProvider.overrideWith((ref) => const Stream.empty()),
          ...overrides,
        ],
        child: router == null
            ? MaterialApp(theme: GhinaTheme.light(), home: home)
            : MaterialApp.router(
                theme: GhinaTheme.light(),
                routerConfig: router,
              ),
      ),
    );
    await settle(t);
  }

  group('search', () {
    test('finds offices, agents and sessions across offices', () {
      expect(kantorSearch(_state, '').length, 0);
      final beta = kantorSearch(_state, 'beta');
      expect(beta.single.kind, KantorHitKind.office);
      expect(beta.single.path, '/kantor/o/b');
      final dina = kantorSearch(_state, 'dina');
      expect(dina.single.kind, KantorHitKind.agent);
      expect(dina.single.path, '/kantor/o/a/s/s1');
      expect(kantorSearch(_state, 'backend').length, 1, reason: 'job title');
      final ended = kantorSearch(
        _state,
        'migrasi',
        ended: [
          {
            'sid': 'e1',
            'office': 'b',
            'office_name': 'Toko Beta',
            'title': 'Migrasi database',
            'ended_at': '2026-10-20T10:00:00Z',
          },
        ],
      );
      expect(ended.single.path, '/kantor/o/b/s/e1');
    });

    testWidgets('search page lists hits and opens one', (t) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const KantorSearchPage(),
            routes: [
              GoRoute(
                path: 'kantor/o/:id',
                builder: (_, s) =>
                    Scaffold(body: Text('office ${s.pathParameters['id']}')),
              ),
            ],
          ),
        ],
      );
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            kantorStateProvider.overrideWith((_) async => _state),
            kantorEndedProvider.overrideWith((_) async => const []),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'beta');
      await t.pumpAndSettle();
      expect(find.text('Toko Beta'), findsOneWidget);
      expect(find.text('Kantor Alpha'), findsNothing);
      await t.tap(find.text('Toko Beta'));
      await t.pumpAndSettle();
      expect(find.text('office b'), findsOneWidget);
    });

    apiTest('Kompleks has the search bar at the very top', (t) async {
      await pumpApp(
        t,
        const KantorComplexPage(),
        withRouter: true,
        overrides: [
          kantorStateProvider.overrideWith((_) async => _state),
          kantorEndedProvider.overrideWith((_) async => const []),
        ],
      );
      final bar = find.byKey(const ValueKey('kantor-search-bar'));
      expect(bar, findsOneWidget);
      expect(find.text('Kotak masuk izin'), findsOneWidget);
      expect(
        t.getTopLeft(bar).dy < t.getTopLeft(find.text('Kotak masuk izin')).dy,
        isTrue,
      );
      expect(find.text('Kantor baru'), findsOneWidget);
      await t.tap(bar);
      await t.pumpAndSettle();
      expect(find.byType(KantorSearchPage), findsOneWidget);
    });
  });

  group('plan thumb', () {
    test('reads the daemon svg and a plan', () {
      final svg = KantorPlanThumb.svg(_thumb);
      expect(svg.size, const Size(20, 10));
      expect(svg.rects.length, 2);
      expect(svg.rects[1].color.a, closeTo(.5, .01));
      expect(KantorPlanThumb.svg(null).size, Size.zero);
      expect(KantorPlanThumb.plan(_plan).rects.length, 4);
    });
  });

  group('wizard', () {
    apiTest('new project: name, team, template, create', (t) async {
      String? created;
      await pumpApp(
        t,
        KantorWizardPage(onCreated: (id) => created = id, random: Random(1)),
      );
      expect(find.text('Project apa?'), findsOneWidget);

      // empty name is refused with the server's wording kept for later steps
      await t.tap(find.text('LANJUT'));
      await t.pump();
      expect(find.text('Isi nama project dulu.'), findsOneWidget);

      await t.enterText(
        find.widgetWithText(TextField, 'mis. Toko Kopi'),
        'Toko Kopi',
      );
      await settle(t);
      expect(find.text('Folder: ~/Developer/toko-kopi'), findsOneWidget);
      await t.tap(find.text('LANJUT'));
      await settle(t);

      // team
      expect(find.text('Tim'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('preset-backend')));
      await settle(t);
      expect(find.text('Arya'), findsOneWidget);
      await t.ensureVisible(find.text('LANJUT'));
      await t.tap(find.text('LANJUT'));
      await settle(t);

      // mood
      expect(find.text('Taman Zen'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tpl-loft')));
      await settle(t);
      await t.ensureVisible(find.text('LANJUT'));
      await t.tap(find.text('LANJUT'));
      await settle(t);

      // start
      expect(find.text('Mulai'), findsWidgets);
      expect(find.textContaining('suasana Loft Industri'), findsOneWidget);
      await t.tap(find.text('BUAT KANTOR'));
      await settle(t);

      final spec = posts['/api/wizard/create']!;
      expect(spec['mode'], 'new');
      expect(spec['folder'], 'toko-kopi');
      expect(spec['template'], 'loft');
      expect(spec['gitInit'], true);
      final team = spec['team'] as List;
      expect(team.first['isMgr'], true);
      expect(team.map((m) => (m as Map)['key']), ['manager', 'backend']);
      expect(created, 'baru');
    });

    apiTest('existing folder: pick from the list', (t) async {
      await pumpApp(t, KantorWizardPage(onCreated: (_) {}));
      await t.tap(find.text('Folder ada'));
      await settle(t);
      await t.tap(find.text('LANJUT'));
      await t.pump();
      expect(find.text('Pilih foldernya dulu.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('folder-lama')));
      await settle(t);
      await t.tap(find.text('LANJUT'));
      await settle(t);
      expect(find.text('Tim'), findsWidgets);
      expect(posts['/api/wizard/preview']!['root'], '/Users/me/Developer/lama');
      expect(posts['/api/wizard/preview']!['claudeMd'], false);
    });

    apiTest('server warning blocks the next step', (t) async {
      previewWarning = true;
      await pumpApp(t, KantorWizardPage(onCreated: (_) {}));
      await t.enterText(
        find.widgetWithText(TextField, 'mis. Toko Kopi'),
        'Ada',
      );
      await settle(t);
      await t.tap(find.text('LANJUT'));
      await t.pump();
      expect(
        find.text('Folder sudah ada. Pilih folder yang sudah ada.'),
        findsWidgets,
      );
      expect(find.text('Tim'), findsNothing);
    });

    test('folder names are slugged like the web wizard', () {
      expect(kantorSlugDir('  Toko Kopi!  '), 'toko-kopi');
      expect(kantorSlugDir('a' * 80).length, 60);
      expect(kantorTilde('/Users/zz/Developer/x'), '~/Developer/x');
    });
  });

  group('template for an existing office', () {
    apiTest('preview, re-roll, apply', (t) async {
      await pumpApp(t, KantorTemplatePage(officeId: 'a', random: Random(3)));
      expect(find.text('Taman Zen'), findsOneWidget);
      expect(find.text('Pulihkan susunan lama'.toUpperCase()), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('tpl-zen')));
      await settle(t);
      expect(find.text('Pratinjau'), findsOneWidget);
      expect(find.textContaining('Ruangan baru: Taman Zen'), findsOneWidget);
      expect(posts['/api/offices/a/template/preview']!['seed'], 1);

      await t.ensureVisible(find.text('ACAK LAGI'));
      await t.tap(find.text('ACAK LAGI'));
      await settle(t);
      final seed = posts['/api/offices/a/template/preview']!['seed'] as int;
      expect(seed, isNot(1));

      await t.ensureVisible(find.text('TERAPKAN'));
      await t.tap(find.text('TERAPKAN'));
      await settle(t);
      final apply = posts['/api/offices/a/template/apply']!;
      expect(apply['template'], 'zen');
      expect(apply['seed'], seed);
    });

    apiTest('restore asks first, hidden without a backup', (t) async {
      await pumpApp(t, KantorTemplatePage(officeId: 'a'));
      await t.ensureVisible(find.text('PULIHKAN SUSUNAN LAMA'));
      await t.tap(find.text('PULIHKAN SUSUNAN LAMA'));
      await t.pumpAndSettle();
      expect(posts.containsKey('/api/offices/a/template/restore'), isFalse);
      await t.tap(find.text('PULIHKAN'));
      await settle(t);
      expect(posts.containsKey('/api/offices/a/template/restore'), isTrue);
    });

    apiTest('no restore button when there is no backup', (t) async {
      hasBackup = false;
      await pumpApp(t, KantorTemplatePage(officeId: 'a'));
      expect(find.text('PULIHKAN SUSUNAN LAMA'), findsNothing);
    });
  });

  group('daemon settings', () {
    final settingsState = {
      ..._state,
      'tmux': true,
      'claude': true,
      'hooks': false,
      'settings': {
        'approvals': {'holdKantorSec': 90, 'holdManualSec': 0},
        'roots': ['/Users/me/Developer'],
        'extraHosts': ['100.1.2.3:4317'],
        'defaultPermissionMode': 'plan',
        'musicDir': '/Users/me/Music',
        'ghinaNotify': {
          'enabled': true,
          'ready': true,
          'events': ['permission'],
          // a daemon must never send these; the UI must not show them if it does
          'token': 'SECRET-TOKEN',
          'url': 'https://secret.example/notify',
        },
      },
    };

    apiTest('shows status, saves approvals, never shows tokens', (t) async {
      await pumpApp(
        t,
        const Scaffold(
          body: SingleChildScrollView(child: KantorDaemonSettings()),
        ),
        overrides: [
          kantorStateProvider.overrideWith((_) async => settingsState),
        ],
      );
      expect(find.text('Notifikasi ke Ghina'), findsOneWidget);
      expect(find.text('AKTIF'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('/Users/me/Music'), findsOneWidget);
      expect(find.textContaining('100.1.2.3:4317'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('secret.example'), findsNothing);

      await t.enterText(find.byType(TextField).at(1), '30');
      await t.ensureVisible(find.text('SIMPAN IZIN'));
      await t.tap(find.text('SIMPAN IZIN'));
      await settle(t);
      final body = posts['/api/settings']!;
      expect(body['approvals'], {'holdKantorSec': 90, 'holdManualSec': 30});
      expect(body['defaultPermissionMode'], 'plan');
      expect(body.containsKey('token'), isFalse);
      expect(find.text('Pengaturan izin disimpan.'), findsOneWidget);
    });

    apiTest('rejects non-numbers before calling the daemon', (t) async {
      await pumpApp(
        t,
        const Scaffold(
          body: SingleChildScrollView(child: KantorDaemonSettings()),
        ),
        overrides: [
          kantorStateProvider.overrideWith((_) async => settingsState),
        ],
      );
      await t.enterText(find.byType(TextField).at(0), 'abc');
      await t.ensureVisible(find.text('SIMPAN IZIN'));
      await t.tap(find.text('SIMPAN IZIN'));
      await t.pump();
      expect(find.textContaining('angka 0 atau lebih'), findsOneWidget);
      expect(posts.containsKey('/api/settings'), isFalse);
    });

    apiTest('saves the music folder', (t) async {
      await pumpApp(
        t,
        const Scaffold(
          body: SingleChildScrollView(child: KantorDaemonSettings()),
        ),
        overrides: [
          kantorStateProvider.overrideWith((_) async => settingsState),
        ],
      );
      await t.enterText(find.byType(TextField).at(2), '/Users/me/Lagu');
      await t.ensureVisible(find.text('SIMPAN FOLDER MUSIK'));
      await t.tap(find.text('SIMPAN FOLDER MUSIK'));
      await settle(t);
      expect(posts['/api/settings'], {'musicDir': '/Users/me/Lagu'});
    });
  });
}
