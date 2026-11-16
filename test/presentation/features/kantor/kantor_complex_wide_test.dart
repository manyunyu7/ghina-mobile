import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/kantor_data.dart';
import 'package:ghina/presentation/features/kantor/pages/kantor_complex_page.dart';

// Tata letak Kompleks per lebar layar: ponsel (360/400), Fold tegak (690),
// layar dalam Fold (830), tablet (900/1200), dan layar sangat lebar (1400).

Map<String, dynamic> _session(String sid, {String status = 'idle'}) => {
  'sid': sid,
  'status': status,
  'title': 'Agen $sid dengan judul sesi yang cukup panjang sekali',
  'look': {
    'name': 'Agen $sid',
    'color': '#2F5D9E',
    'hair': '#2B1D14',
    'skin': '#F1C9A5',
  },
};

Map<String, dynamic> _office(
  String id, {
  bool fav = false,
  int sessions = 0,
  String? style,
}) => {
  'id': id,
  'name': 'Kantor $id dengan nama yang sangat panjang sekali',
  'fav': fav,
  'style': ?style,
  'sessions': [
    for (var i = 0; i < sessions; i++)
      _session('$id$i', status: i == 0 ? 'working' : 'idle'),
  ],
  'cards': {'open': 12},
  'monthCost': 123.45,
  'lastSeen': '2026-11-16T10:00:00Z',
};

final _state = <String, dynamic>{
  'offices': [
    _office('A', fav: true, sessions: 8, style: 'Folder induk · 3 repo'),
    _office('B', fav: true, sessions: 1),
    _office('C', sessions: 2, style: 'Satu repo'),
    _office('D'),
    _office('E'),
  ],
  'inbox': [
    {
      'id': 'i1',
      'office': 'A',
      'who': 'Agen A0',
      'tool': 'Bash',
      'summary':
          'flutter test --reporter expanded test/presentation/a_b_c.dart',
      'held': true,
    },
  ],
  'loose': [
    {
      'sid': 'l1',
      'title': 'Sesi di folder induk yang panjang',
      'cwd': '/Users/me/Developer',
    },
  ],
};

final _ended = [
  {
    'sid': 'x1',
    'title': 'Sesi lama yang sudah ditutup dengan judul panjang',
    'office_name': 'Kantor A',
    'ended_at': '2026-11-16T09:00:00Z',
  },
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'kantor.url': 'https://example.test',
      'kantor.token': 't',
    }),
  );

  Future<void> pumpAt(
    WidgetTester t,
    double width, {
    double height = 800,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final router = GoRouter(
      initialLocation: '/kantor',
      routes: [
        GoRoute(
          path: '/kantor',
          builder: (_, _) => const KantorComplexPage(),
          routes: [
            GoRoute(
              path: 'o/:id',
              builder: (_, s) => Text('office ${s.pathParameters['id']}'),
              routes: [
                GoRoute(
                  path: 's/:sid',
                  builder: (_, s) => Text('session ${s.pathParameters['sid']}'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          kantorStateProvider.overrideWith((_) async => _state),
          kantorEndedProvider.overrideWith((_) async => _ended),
        ],
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  final split = find.byKey(const ValueKey('kantor-complex-split'));
  final stacked = find.byKey(const ValueKey('kantor-complex-stacked'));
  final aside = find.byKey(const ValueKey('kantor-complex-aside'));
  final main = find.byKey(const ValueKey('kantor-complex-main'));
  final compactStats = find.byKey(const ValueKey('kantor-stats-compact'));

  // Tanpa overflow di semua lebar (tinggi besar supaya semua isi dibangun).
  for (final w in [360.0, 400.0, 600.0, 690.0, 760.0, 830.0, 1200.0, 1400.0]) {
    testWidgets('no overflow at ${w.toInt()}dp', (t) async {
      await pumpAt(t, w, height: 5000);
      expect(t.takeException(), isNull);
      expect(find.text('Kotak masuk izin'), findsOneWidget);
      expect(find.text('Baru ditutup'), findsOneWidget);
      expect(find.text('Di luar kantor'), findsOneWidget);
      expect(find.text('Bersama'), findsOneWidget);
    });
  }

  testWidgets('360dp: phone layout unchanged (full cards, 3 StatTiles)', (
    t,
  ) async {
    await pumpAt(t, 360, height: 3000);
    expect(split, findsNothing);
    expect(stacked, findsNothing);
    expect(compactStats, findsNothing);
    expect(find.byType(StatTile), findsNWidgets(3));
    final search = t.getRect(find.byKey(const ValueKey('kantor-search-bar')));
    expect(search.left, GhinaSpace.page);
    expect(search.right, 360 - GhinaSpace.page);
    // Kartu favorit tetap selebar halaman, satu kolom.
    final a = t.getRect(find.text('Favorit'));
    expect(a.left, GhinaSpace.page);
  });

  testWidgets('690dp (Fold tegak): satu kolom, grid kartu ringkas', (t) async {
    await pumpAt(t, 690, height: 3000);
    expect(stacked, findsOneWidget);
    expect(split, findsNothing);
    expect(compactStats, findsOneWidget);
    expect(find.byType(StatTile), findsNothing);
    final a = t.getRect(
      find.byKey(const ValueKey('kantor-office-card-A')).first,
    );
    final b = t.getRect(
      find.byKey(const ValueKey('kantor-office-card-B')).first,
    );
    expect(b.top, a.top);
    expect(b.left, greaterThan(a.right));
    expect(a.width, lessThan(330));
  });

  testWidgets('830dp (layar dalam Fold): dua kolom, kantor kiri, izin kanan', (
    t,
  ) async {
    await pumpAt(t, 830);
    expect(split, findsOneWidget);
    final left = t.getRect(main);
    final right = t.getRect(aside);
    expect(right.width, 300);
    expect(right.left, greaterThan(left.right));
    // Ringkasan dan kotak izin ada di kolom kanan.
    expect(
      find.descendant(of: aside, matching: find.text('Kotak masuk izin')),
      findsOneWidget,
    );
    expect(find.descendant(of: aside, matching: compactStats), findsOneWidget);
    // Kartu kantor di kiri: 2 kolom, ringkas.
    final a = t.getRect(
      find.byKey(const ValueKey('kantor-office-card-A')).first,
    );
    final b = t.getRect(
      find.byKey(const ValueKey('kantor-office-card-B')).first,
    );
    expect(a.top, b.top);
    expect(a.left, greaterThanOrEqualTo(left.left));
    expect(b.right, lessThanOrEqualTo(left.right));
    expect(a.width, lessThan(260));
  });

  testWidgets('1200dp: tiga kolom kartu kantor + kolom kanan', (t) async {
    await pumpAt(t, 1200, height: 3000);
    expect(t.getRect(aside).width, 360);
    // Semua kantor: A, B, C, D, E -> 3 kolom; C sebaris dengan A, D di
    // baris berikutnya.
    Rect card(String id) =>
        t.getRect(find.byKey(ValueKey('kantor-office-card-$id')).last);
    expect(card('C').top, card('A').top);
    expect(card('C').left, greaterThan(card('B').right));
    expect(card('D').top, greaterThan(card('A').bottom));
    expect(card('D').left, card('A').left);
    expect(card('C').right, lessThanOrEqualTo(t.getRect(main).right));
  });

  testWidgets('navigasi tetap: tap kartu kantor & agen, tombol favorit ada', (
    t,
  ) async {
    await pumpAt(t, 830);
    expect(find.byTooltip('Hapus dari favorit'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('kantor-office-card-B')).first);
    await t.pumpAndSettle();
    expect(find.text('office B'), findsOneWidget);
  });

  testWidgets('tap agen di kolom kanan membuka sesinya', (t) async {
    await pumpAt(t, 1200, height: 3000);
    final tile = find.descendant(of: aside, matching: find.text('Agen B0'));
    expect(tile, findsOneWidget);
    await t.tap(tile);
    await t.pumpAndSettle();
    expect(find.text('session B0'), findsOneWidget);
  });
}
