import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/usage/kantor_limits_card.dart';
import 'package:ghina/presentation/features/kantor/usage/kantor_usage_data.dart';
import 'package:ghina/presentation/features/kantor/usage/kantor_usage_tab.dart';

final _now = DateTime.fromMillisecondsSinceEpoch(1800000000000);
int _at(Duration d) => _now.add(d).millisecondsSinceEpoch;

Map<String, dynamic> _limits() => {
  'claude': {
    'available': true,
    'updatedAt': _at(const Duration(minutes: -5)),
    'windows': [
      {
        'key': 'five_hour',
        'label': '5 jam',
        'usedPercent': 85.0,
        'resetsAt': _at(const Duration(hours: 2, minutes: 10)),
        'expired': false,
      },
      {
        'key': 'seven_day',
        'label': 'Mingguan',
        'usedPercent': 41.5,
        'resetsAt': _at(const Duration(days: 3, hours: 4)),
        'expired': false,
      },
    ],
  },
  'codex': {
    'available': true,
    'plan': 'prolite',
    'updatedAt': _at(const Duration(hours: -1)),
    'windows': [
      {
        'key': 'primary',
        'label': 'Mingguan',
        'usedPercent': 25.0,
        'resetsAt': _at(const Duration(days: 1)),
        'expired': true,
      },
    ],
  },
};

Widget _app(Widget child, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: overrides,
  child: MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(body: child),
  ),
);

void main() {
  test('helper: warna, sisa waktu, dan nilai rusak', () {
    expect(usageColor(10), GhinaColors.green);
    expect(usageColor(80), GhinaColors.orange);
    expect(usageColor(95), GhinaColors.red);
    expect(
      untilReset(_now.add(const Duration(hours: 2, minutes: 10)), _now),
      'reset 2j 10m lagi',
    );
    expect(
      untilReset(_now.add(const Duration(days: 3, hours: 4)), _now),
      'reset 3h 4j lagi',
    );
    expect(
      untilReset(_now.subtract(const Duration(seconds: 1)), _now),
      'sudah reset',
    );
    expect(untilReset(null, _now), '');
    expect(agoText(double.nan, _now), '');
    expect(agoText(_at(const Duration(minutes: -5)), _now), '5 menit lalu');
    expect(UsageWindow.parse({'usedPercent': double.nan}), isNull);
    expect(UsageWindow.parse({'usedPercent': 140})!.usedPercent, 100);
    expect(usageWindows(null), isEmpty);
    expect(durText(double.nan), '0m');
    expect(durText(4800), '1j 20m');
  });

  testWidgets('kartu batas: bar Claude dan Codex, kadaluarsa jadi reset', (
    t,
  ) async {
    await t.pumpWidget(
      _app(KantorLimitsCard(now: _now), [
        kantorUsageLimitsProvider.overrideWith((_) async => _limits()),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('5 jam'), findsOneWidget);
    expect(find.text('85% terpakai'), findsOneWidget);
    expect(find.text('reset 2j 10m lagi'), findsOneWidget);
    expect(find.text('42% terpakai'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('sudah reset'), findsOneWidget);
    expect(find.text('5 menit lalu'), findsOneWidget);
  });

  testWidgets('kartu batas: belum ada data dan galat tidak meledak', (t) async {
    await t.pumpWidget(
      _app(const KantorLimitsCard(), [
        kantorUsageLimitsProvider.overrideWith(
          (_) async => {
            'claude': {'available': false, 'windows': []},
            'codex': {'available': false, 'windows': []},
          },
        ),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Belum ada laporan'), findsOneWidget);
    expect(find.textContaining('Belum ada sesi Codex'), findsOneWidget);

    await t.pumpWidget(
      _app(const KantorLimitsCard(), [
        kantorUsageLimitsProvider.overrideWith(
          (_) async => throw Exception('x'),
        ),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('belum bisa dibaca'), findsOneWidget);
  });

  testWidgets('tab pemakaian: statistik, grafik, dan data kosong aman', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Map<String, dynamic> summary(bool empty) => {
      'range': '7d',
      'totals': {
        'tokens': empty ? 0 : 1500000,
        'input': 1000,
        'output': 2000,
        'cacheW': 0,
        'cacheR': 0,
        'cost': empty ? 0 : 12.5,
        'sessions': empty ? 0 : 3,
      },
      'avgPerSession': {'tokens': 500000},
      'work': {'seconds': 4800, 'avgSeconds': 1600},
      'engines': {
        'claude': {'tokens': 1000000},
        'codex': {'tokens': 500000},
      },
      'daily': [
        for (var i = 0; i < 7; i++)
          {
            'day': '2026-10-${15 + i}',
            'tokens': empty ? 0 : i * 1000.0,
            'cost': empty ? 0 : i * 1.0,
          },
      ],
      'byOffice': [
        {
          'name': 'Kantor A',
          'tokens': 900000,
          'output': 10,
          'cost': 5,
          'sessions': 2,
        },
      ],
      'byRole': [
        {
          'name': 'Dina',
          'officeName': 'Kantor A',
          'tokens': 900000,
          'output': 10,
          'cost': 5,
          'sessions': 2,
        },
      ],
      'byModel': [
        {
          'label': 'sonnet 4.6',
          'model': 'x',
          'tokens': 900000,
          'output': 10,
          'cost': 5,
          'sessions': 2,
        },
      ],
      'byMachine': [
        {
          'name': 'mac',
          'tokens': 900000,
          'output': 10,
          'cost': 5,
          'sessions': 3,
        },
      ],
      'topSessions': [
        {
          'title': 'Sesi boros',
          'roleName': 'Dina',
          'engine': 'claude',
          'tokens': 700000,
          'cost': 4.2,
          'days': 2,
        },
      ],
      'costNote': 'Catatan biaya.',
    };
    for (final empty in [false, true]) {
      await t.pumpWidget(
        _app(const KantorUsageTab(officeId: '_kompleks'), [
          kantorUsageLimitsProvider.overrideWith((_) async => _limits()),
          kantorUsageSummaryProvider.overrideWith(
            (ref, key) async => summary(empty),
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('Pemakaian kompleks'), findsOneWidget);
      expect(find.text('Batas pemakaian'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (!empty) {
        expect(find.text('1.5M'), findsWidgets);
        expect(find.text('Per kantor'), findsOneWidget);
        expect(find.text('Sesi boros'), findsOneWidget);
        expect(find.text('Per mesin'), findsOneWidget);
      } else {
        expect(find.text('Belum ada pemakaian.'), findsOneWidget);
        expect(find.text('Sesi terboros'), findsNothing);
      }
    }
    await t.tap(find.text('30 hari'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
