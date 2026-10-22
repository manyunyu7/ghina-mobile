import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/metrics/kantor_metrics_data.dart';
import 'package:ghina/presentation/features/kantor/metrics/kantor_metrics_tab.dart';

Widget _app(Widget child, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: overrides,
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: child),
  ),
);

Map<String, dynamic> _office({bool empty = false}) => {
  'office': 'shop',
  'range': {
    'key': 'night',
    'label': 'Semalam (18.00 – 08.00)',
    'bucket': 'hour',
  },
  'series': {
    'starts': [
      for (var h = 0; h < 6; h++)
        DateTime.utc(2030, 1, 10, h).toIso8601String(),
    ],
    'created': List.filled(6, 0),
    'done': empty ? List.filled(6, 0) : [0, 2, 5, 17, 7, 2],
    'commits': empty ? List.filled(6, 0) : [1, 1, 1, 0, 0, 0],
    'dm': List.filled(6, 0),
  },
  'cards': {
    'created': empty ? 0 : 70,
    'done': empty ? 0 : 39,
    'started': 35,
    'cycle': {
      'n': empty ? 0 : 28,
      'avgH': empty ? null : 1.79,
      'medianH': empty ? null : 1.16,
      'p90H': empty ? null : 4.84,
    },
    'review': {'entries': 46, 'bounces': 4, 'bouncedCards': 4},
    'stuck': {
      'hours': 3,
      'count': empty ? 0 : 1,
      'cards': empty
          ? []
          : [
              {
                'id': 'k1',
                'title': 'Uji API sandbox',
                'col': 'Dikerjakan',
                'who': 'Raka',
                'blocked': 'sandbox down',
                'hours': 5.5,
              },
            ],
    },
  },
  'dm': {
    'total': empty ? 0 : 603,
    'pesan': 337,
    'balasan': 264,
    'tanya': 2,
    'deliver': {'avgSec': empty ? null : 209, 'p90Sec': 536, 'maxSec': 3293},
    'reply': {'avgSec': 420, 'p90Sec': 1210, 'maxSec': 3936},
    'slow1': 153,
    'slow5': 78,
    'askTimeout': 1,
    'waitingNow': {'count': 0, 'oldestSec': 0},
    'perRole': empty
        ? []
        : [
            {
              'name': 'Zaya',
              'n': 53,
              'deliver': {'avgSec': 1530, 'maxSec': 3293},
            },
          ],
  },
  'sessions': {
    'totals': {'workSec': 14000, 'idleSec': 9000, 'waitSec': 100},
    'compactions': 2,
    'interrupts': 1,
    'permissions': {'total': 10, 'toTerminal': 6},
    'perRole': empty
        ? []
        : [
            {
              'name': 'Bu Ratna',
              'workSec': 13800,
              'waitSec': 107,
              'idleSec': 10505,
              'compactions': 1,
              'interrupts': 0,
            },
            // all zero: must not divide by zero
            {'name': 'Kosong', 'workSec': 0, 'waitSec': 0, 'idleSec': 0},
          ],
  },
  'cost': {
    'total': empty ? 0 : 388.38,
    'perDoneCard': empty ? null : 9.96,
    'perCommit': empty ? null : 2.61,
    'tokenOnlyTokens': empty ? 0 : 5000000,
    'perRole': empty
        ? []
        : [
            {'name': 'Fajar', 'cost': 51.09, 'tokenOnlyTokens': 0},
            {'name': 'Sinta', 'cost': 0, 'tokenOnlyTokens': 5000000},
          ],
  },
  'git': {'total': empty ? 0 : 149, 'reverts': 0},
  'friction': {
    'toolErrors': {
      'total': 3,
      'byTool': [
        {
          'tool': 'Bash',
          'n': 2,
          'reasons': [
            {'text': 'exit 1', 'n': 2},
          ],
        },
        {'tool': 'card_check', 'n': 1, 'reasons': []},
      ],
    },
    'announcements': 38,
  },
};

void main() {
  test('helper: durasi, jam, dan angka rusak', () {
    expect(metricDur(45), '45 dtk');
    expect(metricDur(720), '12 mnt');
    expect(metricDur(6480), '1,8 jam');
    expect(metricDur(null), '-');
    expect(metricDur(double.nan), '-');
    expect(metricHours(1.79), '1,79 jam');
    expect(metricHours(null), '-');
    expect(metricNum(double.infinity), isNull);
    expect(metricRows('x'), isEmpty);
  });

  test('query: sama nilainya, parameter kustom hanya saat kustom', () {
    const a = KantorMetricsQuery('shop');
    expect(a, const KantorMetricsQuery('shop'));
    expect(a.params, {'range': 'today'});
    expect(
      const KantorMetricsQuery(
        'shop',
        range: 'custom',
        from: '2030-01-01',
        stuckHours: 6,
      ).params,
      {'range': 'custom', 'from': '2030-01-01', 'stuck': '6'},
    );
    expect(const KantorMetricsQuery('_kompleks').path, '/api/metrics');
    expect(a.path, '/api/offices/shop/metrics');
  });

  testWidgets('tab metrik: kartu angka, grafik, dan bagian lengkap', (t) async {
    t.view.physicalSize = const Size(800, 9000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(const KantorMetricsTab(officeId: 'shop'), [
        kantorMetricsProvider.overrideWith((ref, q) async => _office()),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('39'), findsWidgets);
    expect(find.text('1,79 jam'), findsOneWidget);
    expect(find.textContaining('p90 4,84 jam'), findsOneWidget);
    expect(find.text('Pesan langsung'), findsOneWidget);
    expect(find.text('Zaya'), findsOneWidget);
    expect(find.textContaining('terblokir'), findsOneWidget);
    expect(find.text('Bu Ratna'), findsOneWidget);
    expect(find.text('Tanya timeout'), findsOneWidget);
    expect(find.textContaining('alasan tidak tercatat'), findsOneWidget);
    expect(
      find.textContaining(RegExp('laporan shift', caseSensitive: false)),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('tab metrik: rentang kosong tidak meledak dan memberi tahu', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 9000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(const KantorMetricsTab(officeId: 'shop'), [
        kantorMetricsProvider.overrideWith(
          (ref, q) async => _office(empty: true),
        ),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('Belum ada data di rentang ini'), findsWidgets);
    expect(find.text('Belum ada DM di rentang ini.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('kompleks: ringkasan, baris kantor, dan ganti rentang', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final seen = <String>[];
    await t.pumpWidget(
      _app(const KantorMetricsTab(officeId: '_kompleks'), [
        kantorMetricsProvider.overrideWith((ref, q) async {
          seen.add(q.range);
          return {
            'total': {
              'cardsDone': 39,
              'cardsCreated': 70,
              'cycleAvgH': 1.79,
              'stuck': 4,
              'commits': 149,
              'reverts': 0,
              'dm': 603,
              'dmWaiting': 0,
              'cost': 388.38,
              'workSec': 100,
              'idleSec': 50,
              'toolErrors': 91,
            },
            'offices': [
              {
                'name': 'envi-ops',
                'cardsDone': 39,
                'cycleAvgH': 1.79,
                'stuck': 4,
                'commits': 149,
                'cost': 380.1,
              },
            ],
          };
        }),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('Metrik kompleks'), findsOneWidget);
    expect(find.text('envi-ops'), findsOneWidget);
    expect(
      find.textContaining(RegExp('laporan shift', caseSensitive: false)),
      findsNothing,
    );
    await t.tap(find.text('Semalam'));
    await t.pumpAndSettle();
    expect(seen, containsAllInOrder(['today', 'night']));
  });
}
