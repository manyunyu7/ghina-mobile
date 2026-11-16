import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_office_switcher.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_shell_page.dart';
import 'package:ghina/presentation/features/kantor/session/kantor_feed.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('switcher sheet filters, and picking keeps the tab', (t) async {
    t.view.physicalSize = const Size(400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/kantor/o/a?tab=agen',
      routes: [
        GoRoute(
          path: '/kantor/o/:office',
          builder: (_, s) => KantorShellPage(
            officeId: s.pathParameters['office']!,
            tab: s.uri.queryParameters['tab'],
          ),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorStateProvider.overrideWith(
            (_) async => {
              'offices': [
                {
                  'id': 'a',
                  'name': 'Alfa',
                  'fav': true,
                  'style': 'Folder induk',
                  'sessions': [],
                },
                {
                  'id': 'b',
                  'name': 'Bravo',
                  'sessions': [
                    {'sid': 's', 'status': 'working'},
                  ],
                },
              ],
              'inbox': [],
            },
          ),
          kantorOfficeProvider.overrideWith(
            (ref, id) async => {
              'name': id == 'a' ? 'Alfa' : 'Bravo',
              'sessions': [],
            },
          ),
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Alfa').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah kantor'), findsOneWidget);
    expect(find.text('Sedang aktif'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'brav');
    await t.pump(const Duration(milliseconds: 600));
    expect(
      find.descendant(
        of: find.byType(ChunkyBottomSheet),
        matching: find.text('Alfa'),
      ),
      findsNothing,
    );
    await t.tap(find.text('Bravo').last);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Pindah kantor'), findsNothing);
    expect(router.state.uri.toString(), '/kantor/o/b?tab=agen');
    expect(t.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });

  group('sheet ringkas + favorit', () {
    late HttpServer server;
    final calls = <String>[];
    final bodies = <String, Map<String, dynamic>>{};
    // kantor yang POST favoritnya dijawab 500 oleh "daemon"
    final failIds = <String>{};
    // state kantor yang dikirim kantorStateProvider (ikut berubah setelah POST)
    late List<Map<String, dynamic>> offices;
    final built = <String>{};

    List<Map<String, dynamic>> seed() => [
      {
        'id': 'a',
        'name': 'Alfa',
        'fav': true,
        'style': 'Folder induk',
        'sessions': [],
      },
      {
        'id': 'b',
        'name': 'Bravo',
        'sessions': [
          {'sid': 's1', 'status': 'working'},
          {
            'sid': 's2',
            'status': 'idle',
            'waiting': {'tool': 'Bash'},
          },
        ],
      },
      {
        'id': 'c',
        'name': 'Charlie dengan nama kantor yang panjang sekali sampai elipsis',
        'sessions': [],
      },
      {'id': 'd', 'name': 'Delta', 'sessions': []},
    ];

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
        final m = RegExp(r'^/api/offices/([^/]+)/fav$').firstMatch(p);
        if (m != null && failIds.contains(m.group(1))) {
          req.response.statusCode = 500;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'error': 'disk penuh'}));
          await req.response.close();
          return;
        }
        if (m != null) {
          final id = m.group(1);
          final fav = bodies[p]?['fav'] == true;
          offices = [
            for (final o in offices)
              if (o['id'] == id) {...o, 'fav': fav} else o,
          ];
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': true}));
        await req.response.close();
      });
    });

    tearDownAll(() => server.close(force: true));

    setUp(() {
      calls.clear();
      bodies.clear();
      failIds.clear();
      built.clear();
      offices = seed();
    });

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    /// Halaman kosong dengan tombol yang membuka sheet "Pindah kantor".
    Future<GoRouter> open(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () =>
                      showKantorOfficeSwitcher(c, currentId: 'd', tab: 'agen'),
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/kantor/o/:office',
            builder: (_, s) => Text('kantor ${s.pathParameters['office']}'),
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
            kantorStateProvider.overrideWith(
              (_) async => {'offices': offices, 'inbox': []},
            ),
            kantorOfficeFeedProvider.overrideWith((ref, id) {
              built.add(id);
              final f = KantorOfficeFeed(id, null)..loading = false;
              ref.onDispose(f.dispose);
              return f;
            }),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await settle(t);
      await t.tap(find.text('buka'));
      await settle(t);
      expect(find.text('Pindah kantor'), findsOneWidget);
      return router;
    }

    Finder row(String id) => find.byKey(ValueKey('office-row-$id'));

    testWidgets('baris padat, tanpa overflow di layar luar 360dp', (t) async {
      await open(t, const Size(360, 780));
      expect(t.takeException(), isNull);
      for (final id in ['_kompleks', 'a', 'b', 'c', 'd']) {
        final h = t.getSize(row(id)).height;
        expect(h, lessThanOrEqualTo(56), reason: 'baris $id');
        expect(h, greaterThanOrEqualTo(44), reason: 'baris $id');
      }
      // ikon kecil, status singkat, badge pil, centang kantor aktif
      expect(
        t.getSize(
          find.descendant(
            of: row('a'),
            matching: find.byIcon(Icons.apartment_rounded),
          ),
        ),
        const Size(20, 20),
      );
      expect(find.text('2 sesi · 1 bekerja'), findsOneWidget);
      expect(
        find.descendant(
          of: row('b'),
          matching: find.byKey(const ValueKey('office-chip-badge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('d'),
          matching: find.byKey(const ValueKey('office-row-current')),
        ),
        findsOneWidget,
      );
      // satu kolom di layar sempit
      expect(t.getTopLeft(row('c')).dx, t.getTopLeft(row('d')).dx);
      // pencarian tetap di bawah daftar
      expect(
        t.getTopLeft(find.byType(TextField)).dy,
        greaterThan(t.getBottomLeft(row('d')).dy),
      );
      // prefetch tetap: favorit + kantor yang sedang ada agen
      expect(built, containsAll(['a', 'b']));
      expect(built.contains('c'), isFalse);
      // ketuk baris tetap pindah kantor dengan tab yang sama
      await t.tap(row('b'));
      await settle(t);
      expect(find.text('Pindah kantor'), findsNothing);
      expect(find.text('kantor b'), findsOneWidget);
    });

    testWidgets('layar dalam 830dp: dua kolom, tanpa overflow', (t) async {
      double top(Finder f) => t.getTopLeft(f).dy;
      await open(t, const Size(830, 900));
      expect(t.takeException(), isNull);
      // "Lainnya": c dan d bersebelahan dalam satu baris grid
      expect(top(row('c')), top(row('d')));
      expect(t.getTopLeft(row('d')).dx, greaterThan(t.getTopLeft(row('c')).dx));
      for (final id in ['a', 'b', 'c', 'd']) {
        expect(t.getSize(row(id)).height, lessThanOrEqualTo(56));
      }
    });

    testWidgets('bintang: POST fav, langsung pindah ke Favorit', (t) async {
      double top(Finder f) => t.getTopLeft(f).dy;
      await open(t, const Size(360, 780));
      // urutan awal: Favorit (Alfa) > Sedang aktif (Bravo) > Lainnya
      expect(top(find.text('Favorit')), lessThan(top(row('a'))));
      expect(top(row('a')), lessThan(top(find.text('Sedang aktif'))));
      expect(top(find.text('Sedang aktif')), lessThan(top(row('b'))));
      expect(top(row('b')), lessThan(top(find.text('Lainnya'))));
      expect(top(find.text('Lainnya')), lessThan(top(row('c'))));

      await t.tap(find.byKey(const ValueKey('office-fav-c')));
      await t.pump();
      // optimistis: sebelum server menjawab, Charlie sudah di bagian Favorit
      expect(top(row('c')), lessThan(top(find.text('Sedang aktif'))));
      expect(
        find.descendant(
          of: row('c'),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsOneWidget,
      );
      await settle(t);
      expect(calls, contains('POST /api/offices/c/fav'));
      expect(bodies['/api/offices/c/fav'], {'fav': true});
      // setelah state dimuat ulang (invalidate) tetap di Favorit
      expect(offices.firstWhere((o) => o['id'] == 'c')['fav'], isTrue);
      expect(top(find.text('Favorit')), lessThan(top(row('c'))));
      expect(top(row('c')), lessThan(top(find.text('Sedang aktif'))));

      // tahan lama Alfa = hapus dari favorit; Alfa turun ke "Lainnya"
      await t.longPress(row('a'));
      await t.pump();
      expect(top(row('a')), greaterThan(top(find.text('Lainnya'))));
      await settle(t);
      expect(calls, contains('POST /api/offices/a/fav'));
      expect(bodies['/api/offices/a/fav'], {'fav': false});
      expect(top(row('a')), greaterThan(top(find.text('Lainnya'))));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('POST gagal: bintang dikembalikan + toast', (t) async {
      double top(Finder f) => t.getTopLeft(f).dy;
      failIds.add('d');
      await open(t, const Size(360, 780));
      await t.tap(find.byKey(const ValueKey('office-fav-d')));
      await t.pump();
      expect(top(row('d')), lessThan(top(find.text('Lainnya'))));
      await settle(t);
      expect(calls, contains('POST /api/offices/d/fav'));
      // kembali ke "Lainnya", bintang kosong lagi
      expect(top(row('d')), greaterThan(top(find.text('Lainnya'))));
      expect(
        find.descendant(
          of: row('d'),
          matching: find.byIcon(Icons.star_border_rounded),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Gagal memfavoritkan Delta'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });
  });
}
