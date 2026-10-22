// Every fl_chart widget against edge data: empty list, one point, all zero,
// negatives, a one-day range, huge values and NaN / Infinity from a
// division by zero. A chart that throws while building / laying out /
// painting is the grey ErrorWidget screen in release.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/formatters.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/analytics_spending.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/analytics/widgets/analytics_charts.dart';
import 'package:ghina/presentation/features/content/widgets/report_charts.dart'
    as content;
import 'package:ghina/presentation/features/forecast/forecast_state.dart';
import 'package:ghina/presentation/features/forecast/widgets/balance_chart.dart';
import 'package:ghina/presentation/features/habits/widgets/habit_insight_widgets.dart';
import 'package:ghina/presentation/features/health/widgets/trend_chart.dart';
import 'package:ghina/presentation/features/home/widgets/home_sections.dart';
import 'package:ghina/presentation/features/investments/widgets/portfolio_charts.dart';
import 'package:ghina/presentation/features/killa/pages/killa_usage_page.dart';
import 'package:ghina/presentation/features/reports/widgets/report_charts.dart'
    as reports;
import 'package:ghina/presentation/features/screener/widgets/screener_charts.dart';

const _nan = double.nan;
const _inf = double.infinity;

/// Pumps [child] in a phone-size, Ghina-themed app and fails on any exception
/// raised while building, laying out or painting (animations included).
Future<void> _render(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: GhinaTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 340, child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  final ex = tester.takeException();
  if (ex != null) {
    final line = '$ex'.split('\n').first;
    fail(
      'EX: ${ex.runtimeType}: ${line.length > 140 ? line.substring(0, 140) : line}',
    );
  }
}

/// Same widget type, new data: fl_chart tweens between the two (period
/// switch, compare toggle, pull to refresh).
Future<void> _transition(WidgetTester tester, Widget a, Widget b) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget app(Widget c) => MaterialApp(
    theme: GhinaTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 340, child: c)),
    ),
  );
  await tester.pumpWidget(app(a));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(app(b));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump(const Duration(seconds: 2));
  final ex = tester.takeException();
  if (ex != null) {
    final line = '$ex'.split('\n').first;
    fail(
      'EX: ${ex.runtimeType}: ${line.length > 140 ? line.substring(0, 140) : line}',
    );
  }
}

void _chart(String name, Map<String, Widget Function()> cases) {
  group(name, () {
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) => _render(tester, e.value()));
    }
  });
}

CategoryInfo _info(String k) =>
    CategoryInfo(key: k, name: 'Kat $k', color: '#f97316', icon: 'circle');
CategorySpend _spend(String k, double total, {double pct = 0}) =>
    CategorySpend(info: _info(k), total: total, pct: pct, count: 1);

final _d = DateTime(2026, 10, 5);
TrendBucket _tb(int i, double total, {double? previous}) => TrendBucket(
  start: DateTime(2026, 10, 5 + i),
  end: DateTime(2026, 10, 5 + i),
  total: total,
  byKey: {'a': total},
  previous: previous,
);
FlowBucket _fb(int i, double inc, double exp) =>
    FlowBucket(start: DateTime(2026, 10, 5 + i), income: inc, expense: exp);

void main() {
  setUpAll(() async {
    await Fmt.initFormatting();
  });

  const ks = [CategoryInfo.uncategorized];
  _chart('SpendDonut', {
    'empty': () => SpendDonut(rows: const [], currency: 'IDR', onOpen: (_) {}),
    'one zero row': () =>
        SpendDonut(rows: [_spend('a', 0)], currency: 'IDR', onOpen: (_) {}),
    'all zero rows': () => SpendDonut(
      rows: [_spend('a', 0), _spend('b', 0), _spend('c', 0)],
      currency: 'IDR',
      onOpen: (_) {},
    ),
    'one row': () => SpendDonut(
      rows: [_spend('a', 5000, pct: 100)],
      currency: 'IDR',
      onOpen: (_) {},
    ),
    'huge + NaN pct': () => SpendDonut(
      rows: [
        _spend('a', 1e18, pct: _nan),
        _spend('b', 1, pct: _inf),
      ],
      currency: 'IDR',
      onOpen: (_) {},
    ),
    'negative total': () => SpendDonut(
      rows: [_spend('a', -5), _spend('b', 10)],
      currency: 'IDR',
      onOpen: (_) {},
    ),
  });

  for (final stacked in [false, true]) {
    _chart('SpendTrendChart ${stacked ? 'stacked' : 'line'}', {
      'empty': () => SpendTrendChart(
        buckets: const [],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
      ),
      'one bucket': () => SpendTrendChart(
        buckets: [_tb(0, 1000)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
        stackKeys: ks,
      ),
      'one zero bucket': () => SpendTrendChart(
        buckets: [_tb(0, 0)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
      ),
      'all zero + previous': () => SpendTrendChart(
        buckets: [for (var i = 0; i < 7; i++) _tb(i, 0, previous: 0)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
      ),
      'cutoff before all buckets': () => SpendTrendChart(
        buckets: [for (var i = 0; i < 7; i++) _tb(i, 100)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
        cutoff: DateTime(2020),
      ),
      'huge values': () => SpendTrendChart(
        buckets: [_tb(0, 1e15), _tb(1, 3e15)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
      ),
      'NaN / Infinity': () => SpendTrendChart(
        buckets: [_tb(0, _nan), _tb(1, _inf), _tb(2, 5)],
        granularity: Granularity.day,
        currency: 'IDR',
        stacked: stacked,
      ),
    });
  }

  _chart('PatternBarChart', {
    'empty': () => PatternBarChart(
      values: const [],
      labels: const [],
      currency: 'IDR',
      tooltip: (_) => ('', ''),
    ),
    'all zero': () => PatternBarChart(
      values: const [0, 0, 0, 0, 0, 0, 0],
      labels: const ['S', 'S', 'R', 'K', 'J', 'S', 'M'],
      currency: 'IDR',
      tooltip: (_) => ('', ''),
    ),
    'single': () => PatternBarChart(
      values: const [5],
      labels: const ['A'],
      currency: 'IDR',
      tooltip: (_) => ('', ''),
    ),
    'negative': () => PatternBarChart(
      values: const [-5, 3, -1],
      labels: const ['A', 'B', 'C'],
      currency: 'IDR',
      tooltip: (_) => ('', ''),
    ),
    'NaN': () => PatternBarChart(
      values: const [_nan, 3],
      labels: const ['A', 'B'],
      currency: 'IDR',
      tooltip: (_) => ('', ''),
    ),
  });

  _chart('IncomeExpenseBars / CumulativeFlowLine', {
    'bars empty': () => const IncomeExpenseBars(
      buckets: [],
      granularity: Granularity.month,
      currency: 'IDR',
    ),
    'bars zero': () => IncomeExpenseBars(
      buckets: [_fb(0, 0, 0)],
      granularity: Granularity.month,
      currency: 'IDR',
    ),
    'line empty': () => const CumulativeFlowLine(
      buckets: [],
      granularity: Granularity.day,
      currency: 'IDR',
    ),
    'line one zero': () => CumulativeFlowLine(
      buckets: [_fb(0, 0, 0)],
      granularity: Granularity.day,
      currency: 'IDR',
    ),
    'line all zero': () => CumulativeFlowLine(
      buckets: [for (var i = 0; i < 5; i++) _fb(i, 0, 0)],
      granularity: Granularity.day,
      currency: 'IDR',
    ),
    'line only negative': () => CumulativeFlowLine(
      buckets: [for (var i = 0; i < 5; i++) _fb(i, 0, 100)],
      granularity: Granularity.day,
      currency: 'IDR',
    ),
    'line huge': () => CumulativeFlowLine(
      buckets: [_fb(0, 1e16, 0), _fb(1, 0, 3e16)],
      granularity: Granularity.day,
      currency: 'IDR',
    ),
    'line cutoff before all': () => CumulativeFlowLine(
      buckets: [for (var i = 0; i < 5; i++) _fb(i, 10, 0)],
      granularity: Granularity.day,
      currency: 'IDR',
      cutoff: DateTime(2020),
    ),
  });

  _chart('SpendHeatmap / HBarRow', {
    'heatmap one-day period, no data': () => SpendHeatmap(
      period: AnalyticsPeriod(
        start: _d,
        end: _d,
        preset: AnalyticsPreset.custom,
        label: 'x',
      ),
      daily: const {},
      currency: 'IDR',
      now: _d,
    ),
    'heatmap NaN day': () => SpendHeatmap(
      period: AnalyticsPeriod(
        start: DateTime(2026, 10),
        end: DateTime(2026, 10, 31),
        preset: AnalyticsPreset.thisMonth,
        label: 'x',
      ),
      daily: const {'2026-10-05': _nan, '2026-10-06': 5},
      currency: 'IDR',
      now: _d,
    ),
    'hbar NaN fraction': () => HBarRow(
      leading: const SizedBox(),
      title: 't',
      amount: 0,
      fraction: _nan,
      color: Colors.red,
      currency: 'IDR',
    ),
  });

  MonthTotals mt(double i, double e) =>
      MonthTotals(month: const YearMonth(2026, 10), income: i, expense: e);
  CategoryTotal ct(double t, {double pct = 0}) =>
      CategoryTotal(category: null, total: t, pct: pct);

  _chart('reports charts', {
    'income/expense empty': () => const SizedBox(
      height: 200,
      child: reports.IncomeExpenseChart(months: [], currency: 'IDR'),
    ),
    'income/expense zero': () => SizedBox(
      height: 200,
      child: reports.IncomeExpenseChart(months: [mt(0, 0)], currency: 'IDR'),
    ),
    'income/expense NaN': () => SizedBox(
      height: 200,
      child: reports.IncomeExpenseChart(months: [mt(_nan, 1)], currency: 'IDR'),
    ),
    'cashflow empty': () => const SizedBox(
      height: 200,
      child: reports.CashflowChart(months: [], currency: 'IDR'),
    ),
    'cashflow zero': () => SizedBox(
      height: 200,
      child: reports.CashflowChart(months: [mt(0, 0)], currency: 'IDR'),
    ),
    'cashflow only negative': () => SizedBox(
      height: 200,
      child: reports.CashflowChart(
        months: [mt(0, 50), mt(0, 70)],
        currency: 'IDR',
      ),
    ),
    'donut empty': () => const reports.CategoryDonut(
      rows: [],
      currency: 'IDR',
      centerLabel: 'Total',
    ),
    'donut all zero': () => reports.CategoryDonut(
      rows: [ct(0), ct(0)],
      currency: 'IDR',
      centerLabel: 'Total',
    ),
    'donut NaN': () => reports.CategoryDonut(
      rows: [ct(_nan), ct(5)],
      currency: 'IDR',
      centerLabel: 'Total',
    ),
  });

  content.BarDatum bd(double v) => (label: 'a', value: v, tooltip: 't');
  _chart('content charts', {
    'bar empty': () => content.SimpleBarChart(
      data: const [],
      color: GhinaColors.blue,
      formatAxis: (v) => '$v',
    ),
    'bar zero': () => content.SimpleBarChart(
      data: [bd(0), bd(0)],
      color: GhinaColors.blue,
      formatAxis: (v) => '$v',
    ),
    'bar negative': () => content.SimpleBarChart(
      data: [bd(-3), bd(-1)],
      color: GhinaColors.blue,
      formatAxis: (v) => '$v',
    ),
    'bar NaN': () => content.SimpleBarChart(
      data: [bd(_nan), bd(2)],
      color: GhinaColors.blue,
      formatAxis: (v) => '$v',
    ),
    'hbar zero': () => const content.HBarList(
      rows: [(label: 'a', value: 0, display: '0', dot: null)],
      color: GhinaColors.blue,
    ),
    'hbar NaN': () => const content.HBarList(
      rows: [
        (label: 'a', value: _nan, display: '-', dot: null),
        (label: 'b', value: 1, display: '1', dot: null),
      ],
      color: GhinaColors.blue,
    ),
    'sharebar empty': () => const content.ShareBar(parts: []),
    'sharebar NaN share': () => const content.ShareBar(
      parts: [(label: 'a', share: _nan, color: Colors.red, count: 0)],
    ),
    'sharebar Infinity share': () => const content.ShareBar(
      parts: [(label: 'a', share: _inf, color: Colors.red, count: 0)],
    ),
  });

  BalancePoint bp(int day, double b) => (day: day, balance: b, event: false);
  _chart('BalanceChart', {
    'single point': () => SizedBox(
      height: 190,
      child: BalanceChart(
        points: [bp(0, 100)],
        currency: 'IDR',
        monthShort: 'Okt',
      ),
    ),
    'flat zero': () => SizedBox(
      height: 190,
      child: BalanceChart(
        points: [for (var i = 0; i < 31; i++) bp(i, 0)],
        currency: 'IDR',
        monthShort: 'Okt',
      ),
    ),
    'negative': () => SizedBox(
      height: 190,
      child: BalanceChart(
        points: [for (var i = 0; i < 31; i++) bp(i, -1000.0 * i)],
        currency: 'IDR',
        monthShort: 'Okt',
      ),
    ),
    'empty': () => SizedBox(
      height: 190,
      child: BalanceChart(points: const [], currency: 'IDR', monthShort: 'Okt'),
    ),
    'huge': () => SizedBox(
      height: 190,
      child: BalanceChart(
        points: [bp(0, 1e17), bp(1, 2e17)],
        currency: 'IDR',
        monthShort: 'Okt',
      ),
    ),
  });

  AllocationSlice sl(double v, double pct) =>
      AllocationSlice(key: 'k$v', label: 'L', value: v, pct: pct);
  PortfolioPoint pp(int i, double v, double c) => PortfolioPoint(
    date: dateKey(DateTime(2026, 10, 1 + i)),
    value: v,
    cost: c,
  );
  _chart('portfolio charts', {
    'allocation empty': () =>
        const AllocationCard(summary: PortfolioSummary.empty, currency: 'IDR'),
    'allocation all zero': () => AllocationCard(
      summary: PortfolioSummary(
        holdings: const [],
        byAsset: [sl(0, 0), sl(0, 0)],
        byKind: const [],
      ),
      currency: 'IDR',
    ),
    'allocation NaN pct': () => AllocationCard(
      summary: PortfolioSummary(
        holdings: const [],
        byAsset: [sl(0, _nan)],
        byKind: const [],
      ),
      currency: 'IDR',
    ),
    'history empty': () => const SizedBox(
      height: 190,
      child: ValueHistoryChart(points: [], currency: 'IDR'),
    ),
    'history single': () => SizedBox(
      height: 190,
      child: ValueHistoryChart(points: [pp(0, 100, 80)], currency: 'IDR'),
    ),
    'history flat zero': () => SizedBox(
      height: 190,
      child: ValueHistoryChart(
        points: [pp(0, 0, 0), pp(1, 0, 0)],
        currency: 'IDR',
      ),
    ),
    'history huge': () => SizedBox(
      height: 190,
      child: ValueHistoryChart(
        points: [pp(0, 1e18, 0), pp(1, 3e18, 1e18)],
        currency: 'IDR',
      ),
    ),
  });

  HabitDayCell hc(int day) => HabitDayCell(
    date: dateKey(DateTime(2026, 10, day)),
    state: HabitDayState.met,
    value: 1,
    goal: 0,
  );
  _chart('habit charts', {
    'streak two zero': () => const StreakHistoryChart(
      points: [
        (date: '2026-10-01', streak: 0),
        (date: '2026-10-02', streak: 0),
      ],
      color: GhinaColors.green,
    ),
    'streak empty': () =>
        const StreakHistoryChart(points: [], color: GhinaColors.green),
    'minibars all zero': () => const MiniBars(
      values: [0, 0, 0],
      labels: ['a', 'b', 'c'],
      color: GhinaColors.green,
    ),
    'minibars empty': () =>
        const MiniBars(values: [], labels: [], color: GhinaColors.green),
    'minibars short labels': () => const MiniBars(
      values: [1, 2, 3],
      labels: ['a'],
      color: GhinaColors.green,
    ),
    'month heatmap one day': () =>
        MonthHeatmap(cells: [hc(1)], color: GhinaColors.green),
    'year heatmap one day': () =>
        YearHeatmap(cells: [hc(1)], color: GhinaColors.green),
  });

  _chart('TrendChart', {
    'empty': () => const TrendChart(labels: [], series: []),
    'single point': () => const TrendChart(
      labels: ['a'],
      series: [
        TrendSeries(label: 's', values: [70], color: GhinaColors.blue),
      ],
    ),
    'all null': () => const TrendChart(
      labels: ['a', 'b'],
      series: [
        TrendSeries(label: 's', values: [null, null], color: GhinaColors.blue),
      ],
    ),
    'flat': () => const TrendChart(
      labels: ['a', 'b', 'c'],
      series: [
        TrendSeries(label: 's', values: [70, 70, 70], color: GhinaColors.blue),
      ],
    ),
    'labels shorter than values': () => const TrendChart(
      labels: ['a'],
      series: [
        TrendSeries(label: 's', values: [70, 71, 72], color: GhinaColors.blue),
      ],
    ),
    'NaN': () => const TrendChart(
      labels: ['a', 'b'],
      series: [
        TrendSeries(label: 's', values: [_nan, 70], color: GhinaColors.blue),
      ],
    ),
  });

  final t0 = DateTime(2026, 1, 1);
  ShareholderPoint sp(int d, int c) => ShareholderPoint(
    date: t0.add(Duration(days: d)),
    count: c,
  );
  PricePoint pr(int d, double c) => PricePoint(
    date: t0.add(Duration(days: d)),
    close: c,
  );
  BreadthMonth bm(int dec, int ris) => BreadthMonth(
    month: DateTime(2026, 1),
    declining: dec,
    rising: ris,
    flat: 0,
  );
  _chart('screener charts', {
    'sparkline flat': () => const Sparkline(values: [5, 5, 5]),
    'sparkline NaN': () => const Sparkline(values: [_nan, 5]),
    'holders empty': () => const HoldersPriceChart(holders: []),
    'holders single': () => HoldersPriceChart(holders: [sp(0, 100)]),
    'holders same day': () =>
        HoldersPriceChart(holders: [sp(0, 100), sp(0, 90)]),
    'holders flat + flat prices': () => HoldersPriceChart(
      holders: [sp(0, 100), sp(30, 100)],
      prices: [pr(0, 50), pr(30, 50)],
    ),
    'holders price 0': () => HoldersPriceChart(
      holders: [sp(0, 100), sp(30, 120)],
      prices: [pr(0, 0), pr(30, 0)],
    ),
    'change bars empty': () => const ChangeBarsChart(history: []),
    'change bars flat': () =>
        ChangeBarsChart(history: [sp(0, 5), sp(30, 5), sp(60, 5)]),
    'breadth empty': () => const BreadthChart(months: []),
    'breadth zero': () => BreadthChart(months: [bm(0, 0)]),
    'decline histogram empty': () => const DeclineHistogram(rows: []),
  });

  _chart('home spending card', {
    'empty': () => const SpendingCard(items: [], currency: 'IDR'),
    'all zero': () => SpendingCard(
      items: [
        ct(0, pct: _nan),
        ct(0, pct: _nan),
      ],
      currency: 'IDR',
    ),
    'NaN pct': () => SpendingCard(
      items: [ct(10, pct: _nan)],
      currency: 'IDR',
    ),
  });

  KillaUsageDay kd(String date, double cost, int tokens) => KillaUsageDay(
    date: date,
    totals: KillaUsageTotals(costUsd: cost, inputTokens: tokens),
  );
  _chart('killa usage bars', {
    'empty': () => const KillaDailyBars(days: [], costMetric: true),
    'zero': () =>
        KillaDailyBars(days: [kd('2026-10-01', 0, 0)], costMetric: true),
    'tiny cost': () => KillaDailyBars(
      days: [kd('2026-10-01', 1e-9, 0), kd('2026-10-02', 0, 0)],
      costMetric: true,
    ),
    'bad date': () =>
        KillaDailyBars(days: [kd('2026-10-xx', 1, 1)], costMetric: false),
  });

  group('data changes while on screen', () {
    SpendTrendChart trend(
      List<TrendBucket> b, {
      bool stacked = false,
      List<CategoryInfo> keys = const [],
    }) => SpendTrendChart(
      buckets: b,
      granularity: Granularity.day,
      currency: 'IDR',
      stacked: stacked,
      stackKeys: keys,
    );
    List<TrendBucket> tbs(int n, {double? prev}) => [
      for (var i = 0; i < n; i++) _tb(i, 1000.0 * (i + 1), previous: prev),
    ];
    final cases = <String, (Widget, Widget)>{
      'line: 7 -> 30 buckets': (trend(tbs(7)), trend(tbs(30))),
      'line: 30 -> 1 bucket': (trend(tbs(30)), trend(tbs(1))),
      'line: 7 -> 0 buckets': (trend(tbs(7)), trend(const [])),
      'line: 0 -> 7 buckets': (trend(const []), trend(tbs(7))),
      'line: compare on': (trend(tbs(7)), trend(tbs(7, prev: 500))),
      'line: compare off': (trend(tbs(7, prev: 500)), trend(tbs(7))),
      'stacked: 7 -> 30': (
        trend(tbs(7), stacked: true, keys: ks),
        trend(tbs(30), stacked: true, keys: ks),
      ),
      'stacked: keys 1 -> 0': (
        trend(tbs(7), stacked: true, keys: ks),
        trend(tbs(7), stacked: true),
      ),
      'stacked: 7 -> 0': (
        trend(tbs(7), stacked: true, keys: ks),
        trend(const [], stacked: true),
      ),
      'line <-> stacked': (trend(tbs(7)), trend(tbs(7), stacked: true)),
      'donut: 3 -> 12 rows': (
        SpendDonut(
          rows: [for (var i = 0; i < 3; i++) _spend('$i', 100.0 + i)],
          currency: 'IDR',
          onOpen: (_) {},
        ),
        SpendDonut(
          rows: [for (var i = 0; i < 12; i++) _spend('$i', 100.0 + i)],
          currency: 'IDR',
          onOpen: (_) {},
        ),
      ),
      'donut: 5 -> 0 rows': (
        SpendDonut(
          rows: [for (var i = 0; i < 5; i++) _spend('$i', 100.0 + i)],
          currency: 'IDR',
          onOpen: (_) {},
        ),
        SpendDonut(rows: const [], currency: 'IDR', onOpen: (_) {}),
      ),
      'flow bars: 12 -> 3': (
        IncomeExpenseBars(
          buckets: [for (var i = 0; i < 12; i++) _fb(i, 10, 5)],
          granularity: Granularity.month,
          currency: 'IDR',
        ),
        IncomeExpenseBars(
          buckets: [for (var i = 0; i < 3; i++) _fb(i, 10, 5)],
          granularity: Granularity.month,
          currency: 'IDR',
        ),
      ),
      'cumulative: 10 -> 1': (
        CumulativeFlowLine(
          buckets: [for (var i = 0; i < 10; i++) _fb(i, 10, 5)],
          granularity: Granularity.day,
          currency: 'IDR',
        ),
        CumulativeFlowLine(
          buckets: [_fb(0, 10, 5)],
          granularity: Granularity.day,
          currency: 'IDR',
        ),
      ),
      'reports donut: 8 -> 2 rows': (
        reports.CategoryDonut(
          rows: [for (var i = 0; i < 8; i++) ct(10.0 + i)],
          currency: 'IDR',
          centerLabel: 'T',
        ),
        reports.CategoryDonut(
          rows: [ct(5), ct(6)],
          currency: 'IDR',
          centerLabel: 'T',
        ),
      ),
      'reports bars: 12 -> 1 month': (
        SizedBox(
          height: 200,
          child: reports.IncomeExpenseChart(
            months: [for (var i = 0; i < 12; i++) mt(10, 5)],
            currency: 'IDR',
          ),
        ),
        SizedBox(
          height: 200,
          child: reports.IncomeExpenseChart(
            months: [mt(10, 5)],
            currency: 'IDR',
          ),
        ),
      ),
      'portfolio history: 30 -> 2': (
        SizedBox(
          height: 190,
          child: ValueHistoryChart(
            points: [for (var i = 0; i < 30; i++) pp(i, 100.0 + i, 90)],
            currency: 'IDR',
          ),
        ),
        SizedBox(
          height: 190,
          child: ValueHistoryChart(
            points: [pp(0, 100, 90), pp(1, 110, 90)],
            currency: 'IDR',
          ),
        ),
      ),
      'balance: up -> down': (
        SizedBox(
          height: 190,
          child: BalanceChart(
            points: [for (var i = 0; i < 31; i++) bp(i, 1000.0 * i)],
            currency: 'IDR',
            monthShort: 'Okt',
          ),
        ),
        SizedBox(
          height: 190,
          child: BalanceChart(
            points: [for (var i = 0; i < 28; i++) bp(i, -1000.0 * i)],
            currency: 'IDR',
            monthShort: 'Okt',
          ),
        ),
      ),
      'allocation: slices 5 -> 1': (
        AllocationCard(
          summary: PortfolioSummary(
            holdings: const [],
            byAsset: [for (var i = 0; i < 5; i++) sl(10.0 + i, 20)],
            byKind: const [],
          ),
          currency: 'IDR',
        ),
        AllocationCard(
          summary: PortfolioSummary(
            holdings: const [],
            byAsset: [sl(10, 100)],
            byKind: const [],
          ),
          currency: 'IDR',
        ),
      ),
      'home donut: 5 -> 1': (
        SpendingCard(
          items: [for (var i = 0; i < 5; i++) ct(10.0 + i, pct: 20)],
          currency: 'IDR',
        ),
        SpendingCard(items: [ct(10, pct: 100)], currency: 'IDR'),
      ),
    };
    for (final e in cases.entries) {
      testWidgets(
        e.key,
        (tester) => _transition(tester, e.value.$1, e.value.$2),
      );
    }
  });

  group('empty data says so', () {
    final empties = <String, Widget>{
      'trend': const SpendTrendChart(
        buckets: [],
        granularity: Granularity.day,
        currency: 'IDR',
      ),
      'balance': const BalanceChart(
        points: [],
        currency: 'IDR',
        monthShort: 'Okt',
      ),
      'portfolio history': const ValueHistoryChart(points: [], currency: 'IDR'),
      'holders': const HoldersPriceChart(holders: []),
      'cumulative flow': const CumulativeFlowLine(
        buckets: [],
        granularity: Granularity.day,
        currency: 'IDR',
      ),
    };
    for (final e in empties.entries) {
      testWidgets(e.key, (tester) async {
        await _render(tester, e.value);
        expect(find.text('Belum ada data'), findsOneWidget);
      });
    }
  });
}
