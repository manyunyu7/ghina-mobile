import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/widgets/kantor_wide.dart';
import 'package:ghina/presentation/features/kantor/wiki/kantor_wiki_tab.dart';
import 'package:ghina/presentation/features/kantor/wiki/wiki_page_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pages = [
  {
    'slug': 'beranda',
    'title': 'Beranda',
    'parent': null,
    'ord': 0,
    'updated_at': '2026-11-01T10:00:00Z',
  },
  {
    'slug': 'panduan',
    'title': 'Panduan',
    'parent': null,
    'ord': 10,
    'updated_at': '2026-11-01T10:00:00Z',
  },
];

Map<String, dynamic> _page(String slug) => {
  'slug': slug,
  'title': slug == 'beranda' ? 'Beranda' : 'Panduan',
  'body': 'Isi halaman $slug yang cukup panjang untuk dibaca.',
  'author': 'Dina',
  'updatedAt': '2026-11-01T10:00:00Z',
  'revs': 1,
};

void main() {
  late HttpServer server;
  final calls = <String>[];

  setUpAll(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      final p = req.uri.path;
      calls.add('${req.method} $p');
      Object out = {'ok': true};
      if (p == '/api/offices/a/wiki') {
        out = _pages;
      } else if (p == '/api/offices/a/wiki-sources') {
        out = <dynamic>[];
      } else if (p == '/api/offices/a/wiki/page') {
        out = _page(req.uri.queryParameters['ref'] ?? 'beranda');
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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    });
  });

  KantorApi api() => KantorApi(
    KantorConfig(baseUrl: 'http://127.0.0.1:${server.port}', token: 't'),
  );

  int listLoads() => calls.where((c) => c == 'GET /api/offices/a/wiki').length;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester t, Size size, Widget home) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
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

  const tab = Scaffold(body: KantorWikiTab(officeId: 'a'));

  Finder highlighted() =>
      find.byWidgetPredicate((w) => w is Ink && w.decoration != null);

  testWidgets('layar lebar: pohon di kiri, halaman terbuka di kanan', (
    t,
  ) async {
    await pump(t, const Size(900, 800), tab);
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.byType(KantorPaneEmpty), findsOneWidget);
    expect(find.byType(WikiPageScreen), findsNothing);

    await t.tap(find.text('Panduan'));
    await settle(t);
    // dua panel: daftar (dengan pencarian) tetap terlihat, halaman di kanan
    expect(find.byType(WikiPageScreen), findsOneWidget);
    expect(find.byType(ChunkyTextField), findsOneWidget);
    expect(find.byType(KantorPaneEmpty), findsNothing);
    expect(
      find.textContaining('Isi halaman panduan', findRichText: true),
      findsOneWidget,
    );
    expect(highlighted(), findsOneWidget);
    // panel kanan berada di sebelah kanan daftar
    expect(t.getTopLeft(find.byType(WikiPageScreen)).dx, greaterThan(300));

    // ganti halaman: detail diganti dan daftar dimuat ulang diam-diam
    final before = listLoads();
    await t.tap(find.text('Beranda').first);
    await settle(t);
    expect(find.byType(WikiPageScreen), findsOneWidget);
    expect(
      find.textContaining('Isi halaman beranda', findRichText: true),
      findsOneWidget,
    );
    expect(highlighted(), findsOneWidget);
    expect(listLoads(), greaterThan(before));
    await finish(t);
  });

  testWidgets('layar sempit: satu panel, halaman dibuka penuh', (t) async {
    await pump(t, const Size(400, 800), tab);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(KantorPaneEmpty), findsNothing);

    await t.tap(find.text('Panduan'));
    await settle(t);
    expect(find.byType(WikiPageScreen), findsOneWidget);
    // halaman penuh menutupi daftar
    expect(find.byType(ChunkyTextField), findsNothing);
    expect(t.getTopLeft(find.byType(WikiPageScreen)).dx, 0);
    expect(highlighted(), findsNothing);

    final before = listLoads();
    await t.pageBack();
    await settle(t);
    expect(find.byType(WikiPageScreen), findsNothing);
    expect(find.byType(ChunkyTextField), findsOneWidget);
    // perilaku lama: kembali dari halaman = daftar dimuat ulang diam-diam
    expect(listLoads(), greaterThan(before));
    await finish(t);
  });

  testWidgets('halaman penuh di layar lebar: isi dibatasi lebar baca', (
    t,
  ) async {
    await pump(
      t,
      const Size(1400, 900),
      const WikiPageScreen(officeId: 'a', pageRef: 'panduan'),
    );
    final col = find
        .descendant(
          of: find.byType(KantorReadable),
          matching: find.byType(Column),
        )
        .first;
    expect(t.getSize(col).width, kKantorReadableMax);
    // di tengah layar
    expect(t.getCenter(col).dx, closeTo(700, 1));
    await finish(t);
  });

  testWidgets('halaman penuh di layar sempit: lebar isi tidak berubah', (
    t,
  ) async {
    await pump(
      t,
      const Size(400, 800),
      const WikiPageScreen(officeId: 'a', pageRef: 'panduan'),
    );
    final col = find
        .descendant(
          of: find.byType(KantorReadable),
          matching: find.byType(Column),
        )
        .first;
    expect(t.getSize(col).width, 400 - 2 * GhinaSpace.page);
    await finish(t);
  });
}
