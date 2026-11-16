// Tata letak layar lebar (Galaxy Fold terbuka ±830dp) untuk Metrik, detail
// kartu, kalender, Pemakaian, dan Timeline. Dibandingkan 900x800 (lebar) dengan
// 400x800 (HP), dpr 1, tanpa daemon.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_data.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_lib.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_calendar.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_card_detail.dart';
import 'package:ghina/presentation/features/kantor/metrics/kantor_metrics_data.dart';
import 'package:ghina/presentation/features/kantor/metrics/kantor_metrics_tab.dart';
import 'package:ghina/presentation/features/kantor/timeline/kantor_timeline_tab.dart';
import 'package:ghina/presentation/features/kantor/usage/kantor_usage_data.dart';
import 'package:ghina/presentation/features/kantor/usage/kantor_usage_tab.dart';
import 'package:ghina/presentation/features/kantor/widgets/kantor_wide.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _id = 'o1';
const _wide = Size(900, 800);
const _narrow = Size(400, 800);

String _today() => kTodayStr();

class _FakeBoard extends KBoardNotifier {
  _FakeBoard() : super(_id);

  @override
  Future<KBoard> build() async => KBoard([
    KCard.fromJson({
      'id': 'c1',
      'title': 'Rilis fitur',
      'col': 1,
      'ord': 1,
      'start': _today(),
      'due': _today(),
    }),
  ], const []);
}

List<Override> _boardOverrides() => [
  kantorApiProvider.overrideWith((_) => null),
  kantorBoardProvider(_id).overrideWith(_FakeBoard.new),
  kantorOfficeProvider(
    _id,
  ).overrideWith((_) async => KOffice(roles: [], rooms: [], workingRoles: {})),
  kantorAllCardsProvider(_id).overrideWith(
    (ref) async => KBoard([
      KCard.fromJson({
        'id': 'c1',
        'title': 'Rilis fitur',
        'col': 1,
        'due': _today(),
      }),
    ], const []),
  ),
];

Future<void> _pump(
  WidgetTester t,
  Size size,
  Widget child,
  List<Override> overrides,
) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  // Font uji (kotak per huruf) lebih lebar dari font asli, jadi tata letak HP
  // lama bisa "overflow" beberapa piksel di 400dp. Itu bukan bagian dari uji
  // ini (layar sempit sengaja tidak diubah); layar lebar tetap harus bersih.
  final narrow = size.width < kKantorWideMin;
  final orig = FlutterError.onError;
  if (narrow) {
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      orig?.call(d);
    };
  }
  try {
    await t.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await t.pumpAndSettle();
  } finally {
    FlutterError.onError = orig;
  }
}

Offset _at(WidgetTester t, String text) =>
    t.getTopLeft(find.text(text, skipOffstage: false).first);

/// Pojok kiri atas kartu (ubin) terdekat yang memuat [text].
Offset _tile(WidgetTester t, String text) => t.getTopLeft(
  find
      .ancestor(
        of: find.text(text, skipOffstage: false).first,
        matching: find.byType(ChunkyCard),
      )
      .first,
);

Map<String, dynamic> _office() => {
  'range': {'label': 'Hari ini', 'bucket': 'hour'},
  'series': {
    'starts': [
      for (var h = 0; h < 4; h++)
        DateTime.utc(2030, 1, 10, h).toIso8601String(),
    ],
    'done': [1, 2, 3, 4],
    'commits': [0, 1, 0, 1],
  },
  'cards': {
    'done': 39,
    'created': 70,
    'cycle': {'avgH': 1.79, 'medianH': 1.1, 'p90H': 4.8},
    'stuck': {'hours': 3, 'count': 0},
    'review': {'bounces': 4, 'bouncedCards': 4},
  },
  'dm': {'total': 603},
  'git': {'total': 149, 'reverts': 0},
};

Map<String, dynamic> _complex() => {
  'total': {'cardsDone': 39, 'commits': 149, 'stuck': 2},
  'offices': [
    {'name': 'Kantor A', 'cardsDone': 1},
    {'name': 'Kantor B', 'cardsDone': 2},
  ],
};

Map<String, dynamic> _usage() => {
  'totals': {'tokens': 1500000, 'cost': 12.5, 'sessions': 3},
  'avgPerSession': {'tokens': 500000},
  'work': {'seconds': 4800, 'avgSeconds': 1600},
  'daily': [
    for (var i = 0; i < 7; i++) {'day': '2026-10-${15 + i}', 'tokens': i * 1e3},
  ],
  'byRole': [
    {'name': 'Dina', 'tokens': 900000, 'sessions': 2},
  ],
  'byModel': [
    {'label': 'sonnet', 'tokens': 900000, 'sessions': 2},
  ],
  'byMachine': [
    {'name': 'mac', 'tokens': 900000, 'sessions': 3},
  ],
  'topSessions': [
    {'title': 'Sesi boros', 'tokens': 700000},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Metrik', () {
    final office = [
      kantorMetricsProvider.overrideWith((ref, q) async => _office()),
    ];

    testWidgets('400dp: bagian ditumpuk, KPI 2 kolom (tetap seperti dulu)', (
      t,
    ) async {
      await _pump(t, _narrow, const KantorMetricsTab(officeId: _id), office);
      expect(t.takeException(), isNull);
      final kartu = _at(t, 'Kartu');
      final dm = _at(t, 'Pesan langsung');
      expect(dm.dy, greaterThan(kartu.dy));
      expect(dm.dx, closeTo(kartu.dx, 0.5));
      // KPI: dua per baris.
      expect(
        _tile(t, 'Siklus rata-rata').dy,
        closeTo(_tile(t, 'Kartu selesai').dy, 1),
      );
      expect(
        _tile(t, 'Macet > 3 jam').dy,
        greaterThan(_tile(t, 'Kartu selesai').dy),
      );
    });

    testWidgets('900dp: bagian berdampingan dalam 2 kolom', (t) async {
      await _pump(t, _wide, const KantorMetricsTab(officeId: _id), office);
      expect(t.takeException(), isNull);
      final kartu = _at(t, 'Kartu');
      final dm = _at(t, 'Pesan langsung');
      expect(dm.dy, closeTo(kartu.dy, 1));
      expect(dm.dx, greaterThan(400));
      // Bagian ketiga (Sesi) kembali ke kolom kiri, di bawah Kartu.
      final sesi = _at(t, 'Sesi');
      expect(sesi.dx, closeTo(kartu.dx, 0.5));
      expect(sesi.dy, greaterThan(kartu.dy));
      // Lebar kolom bagian tidak melebar penuh.
      final chart = t.getSize(find.byType(MetricBars).first);
      expect(chart.width, lessThan(450));
    });

    final complex = [
      kantorMetricsProvider.overrideWith((ref, q) async => _complex()),
    ];

    testWidgets('kompleks 400dp vs 900dp: KPI 2 vs 4 kolom, kantor grid', (
      t,
    ) async {
      await _pump(
        t,
        _narrow,
        const KantorMetricsTab(officeId: '_kompleks'),
        complex,
      );
      expect(
        _tile(t, 'Kartu macet').dy,
        greaterThan(_tile(t, 'Kartu selesai').dy),
      );
      expect(_tile(t, 'Kantor B').dy, greaterThan(_tile(t, 'Kantor A').dy));

      await _pump(
        t,
        _wide,
        const KantorMetricsTab(officeId: '_kompleks'),
        complex,
      );
      expect(t.takeException(), isNull);
      final y = _tile(t, 'Kartu selesai').dy;
      expect(_tile(t, 'Kartu macet').dy, closeTo(y, 1));
      expect(_tile(t, 'Commit').dy, closeTo(y, 1));
      expect(_tile(t, 'Kantor B').dy, closeTo(_tile(t, 'Kantor A').dy, 1));
      expect(
        _tile(t, 'Kantor B').dx,
        greaterThan(_tile(t, 'Kantor A').dx + 200),
      );
    });
  });

  group('Detail kartu', () {
    Widget opener(void Function(BuildContext) open) => Builder(
      builder: (c) => Center(
        child: TextButton(onPressed: () => open(c), child: const Text('buka')),
      ),
    );

    Future<Rect> openAndMeasure(
      WidgetTester t,
      Size size,
      void Function(BuildContext) open,
    ) async {
      await _pump(t, size, opener(open), _boardOverrides());
      await t.tap(find.text('buka'));
      // Kartu lama memuat (indikator berputar), jadi tidak pakai pumpAndSettle.
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      return t.getRect(find.byType(KantorCardScreen));
    }

    ModalRoute<dynamic>? routeOf(WidgetTester t) =>
        ModalRoute.of(t.element(find.byType(KantorCardScreen)));

    testWidgets('kartu baru: 400dp halaman penuh, 900dp panel kanan 600dp', (
      t,
    ) async {
      void open(BuildContext c) => openKantorNewCard(c, officeId: _id);
      final narrow = await openAndMeasure(t, _narrow, open);
      expect(narrow.width, 400);
      expect(routeOf(t), isA<MaterialPageRoute<void>>());

      final wide = await openAndMeasure(t, _wide, open);
      expect(routeOf(t), isA<KantorSidePanelRoute<void>>());
      expect(wide.width, kKantorCardPanelWidth);
      expect(wide.right, 900);
      // Halaman asal tetap terlihat di kiri panel.
      expect(find.text('buka'), findsOneWidget);
      // Ketuk di luar panel menutupnya.
      await t.tapAt(const Offset(50, 400));
      await t.pumpAndSettle();
      expect(find.byType(KantorCardScreen), findsNothing);
    });

    testWidgets('kartu lama: 900dp juga panel samping', (t) async {
      void open(BuildContext c) =>
          openKantorCard(c, officeId: _id, cardId: 'c1');
      final wide = await openAndMeasure(t, _wide, open);
      expect(routeOf(t), isA<KantorSidePanelRoute<void>>());
      expect(wide.width, kKantorCardPanelWidth);
      final narrow = await openAndMeasure(t, _narrow, open);
      expect(routeOf(t), isA<MaterialPageRoute<void>>());
      expect(narrow.width, 400);
    });
  });

  testWidgets('kalender: 400dp satu kolom, 900dp grid kiri + daftar kanan', (
    t,
  ) async {
    const cal = KantorCalendarScreen(officeId: _id);
    await _pump(t, _narrow, cal, _boardOverrides());
    expect(t.takeException(), isNull);
    final label = 'BULAN INI (1)';
    expect(_at(t, label).dx, lessThan(40));
    expect(find.text('Rilis fitur'), findsOneWidget);

    await _pump(t, _wide, cal, _boardOverrides());
    expect(t.takeException(), isNull);
    expect(_at(t, label).dx, greaterThan(900 - kantorMasterWidth(900) - 1));
    expect(_at(t, 'Sen').dx, lessThan(900 - kantorMasterWidth(900)));
    expect(find.text('Rilis fitur'), findsOneWidget);
  });

  group('Pemakaian', () {
    final o = [
      kantorUsageLimitsProvider.overrideWith((_) async => throw 'tidak ada'),
      kantorUsageSummaryProvider.overrideWith((ref, key) async => _usage()),
    ];

    testWidgets('400dp: KPI 2 kolom, bagian ditumpuk', (t) async {
      await _pump(t, _narrow, const KantorUsageTab(officeId: _id), o);
      expect(t.takeException(), isNull);
      expect(_tile(t, 'Sesi').dy, greaterThan(_tile(t, 'Total token').dy));
      // Bagian rincian tetap satu kolom penuh (rata kiri halaman).
      await t.scrollUntilVisible(
        find.text('Per model'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_at(t, 'Per model').dx, lessThan(40));
    });

    testWidgets('900dp: KPI 3 kolom, bagian 2 kolom', (t) async {
      await _pump(t, _wide, const KantorUsageTab(officeId: _id), o);
      expect(t.takeException(), isNull);
      expect(_tile(t, 'Sesi').dy, closeTo(_tile(t, 'Total token').dy, 1));
      expect(_at(t, 'Per model').dy, closeTo(_at(t, 'Per peran').dy, 1));
      expect(_at(t, 'Per model').dx, greaterThan(400));
    });
  });

  testWidgets('timeline: kolom TUGAS 128dp di HP, 200dp di layar lebar', (
    t,
  ) async {
    double nameW() => t
        .getSize(
          find
              .ancestor(
                of: find.text('TUGAS'),
                matching: find.byType(Container),
              )
              .first,
        )
        .width;
    await _pump(
      t,
      _narrow,
      const KantorTimelineTab(officeId: _id),
      _boardOverrides(),
    );
    expect(t.takeException(), isNull);
    expect(nameW(), 128);
    await _pump(
      t,
      _wide,
      const KantorTimelineTab(officeId: _id),
      _boardOverrides(),
    );
    expect(t.takeException(), isNull);
    expect(nameW(), 200);
  });
}
