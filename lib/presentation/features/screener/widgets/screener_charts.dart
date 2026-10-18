import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../screener_format.dart';

/// The line / bar colour of "fewer shareholders" (the signal).
Color screenerPrimary(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// Range of the ticker charts.
enum ChartRange {
  year('1 thn', 12),
  threeYears('3 thn', 36),
  all('Semua', null);

  const ChartRange(this.label, this.months);
  final String label;
  final int? months;

  /// First day shown when the newest report is [newest]; null = no limit.
  DateTime? start(DateTime newest) {
    final m = months;
    if (m == null) return null;
    final total = newest.year * 12 + newest.month - 1 - m;
    final y = total ~/ 12;
    final mo = total % 12 + 1;
    final last = DateTime(y, mo + 1, 0).day;
    return DateTime(y, mo, math.min(newest.day, last));
  }
}

/// Points on or after [start] (all when null).
List<ShareholderPoint> clampHolders(
  List<ShareholderPoint> all,
  DateTime? start,
) => start == null
    ? all
    : [
        for (final p in all)
          if (!p.date.isBefore(start)) p,
      ];

List<PricePoint> clampPrices(List<PricePoint> all, DateTime? start) =>
    start == null
    ? all
    : [
        for (final p in all)
          if (!p.date.isBefore(start)) p,
      ];

/// A tick label of a date axis: months with the year when the span is a year
/// or more (`Mar 2025`), else `12 Mar`.
String axisDateLabel(DateTime d, {required bool withYear}) => withYear
    ? '${Fmt.monthShort(d.month)} ${d.year}'
    : '${d.day} ${Fmt.monthShort(d.month)}';

FlTitlesData _titles({
  required Color muted,
  required double minX,
  required double maxX,
  required DateTime origin,
  required bool withYear,
  Widget Function(double, TitleMeta)? left,
  double leftSize = 0,
  Widget Function(double, TitleMeta)? right,
  double rightSize = 0,
  double? leftInterval,
}) {
  final style = GhinaType.caption.copyWith(color: muted, fontSize: 10);
  final span = math.max(1.0, maxX - minX);
  return FlTitlesData(
    topTitles: const AxisTitles(),
    leftTitles: left == null
        ? const AxisTitles()
        : AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftSize,
              interval: leftInterval,
              getTitlesWidget: left,
            ),
          ),
    rightTitles: right == null
        ? const AxisTitles()
        : AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: rightSize,
              interval: leftInterval,
              getTitlesWidget: right,
            ),
          ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: span / 3,
        getTitlesWidget: (v, meta) {
          // Only the interior ticks: the edge ones would overflow.
          if (v <= minX + 1e-6 || v >= maxX - 1e-6) {
            return const SizedBox.shrink();
          }
          final d = origin.add(Duration(days: v.round()));
          return SideTitleWidget(
            meta: meta,
            child: Text(axisDateLabel(d, withYear: withYear), style: style),
          );
        },
      ),
    ),
  );
}

/// Tiny shareholder-count trend of a list row. Nothing under 2 points.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.width = 56});

  final List<double> values;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(width: width);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final pad = math.max(1.0, (hi - lo) * 0.1);
    final color = screenerPrimary(context);
    return SizedBox(
      key: const ValueKey('screener-sparkline'),
      width: width,
      height: 28,
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minY: lo - pad,
            maxY: hi + pad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < values.length; i++)
                    FlSpot(i.toDouble(), values[i]),
                ],
                isCurved: false,
                barWidth: 2,
                color: color,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shareholder count (left axis) with an optional closing-price line (right
/// axis) over the same dates. Prices are drawn on the count scale and their
/// axis labels are mapped back.
class HoldersPriceChart extends StatelessWidget {
  const HoldersPriceChart({
    super.key,
    required this.holders,
    this.prices = const [],
  });

  final List<ShareholderPoint> holders;
  final List<PricePoint> prices;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final blue = GhinaColors.blue.base;
    final showPrices = prices.length >= 2;
    final dates = [
      for (final h in holders) h.date,
      if (showPrices) ...[for (final p in prices) p.date],
    ]..sort();
    final origin = dates.first;
    double dx(DateTime d) => d.difference(origin).inDays.toDouble();
    final maxX = math.max(1.0, dx(dates.last));

    final counts = [for (final h in holders) h.count.toDouble()];
    var hLo = counts.reduce(math.min);
    var hHi = counts.reduce(math.max);
    final hPad = math.max(1.0, (hHi - hLo) * 0.12);
    hLo -= hPad;
    hHi += hPad;

    var pLo = 0.0, pHi = 1.0;
    if (showPrices) {
      final cl = [for (final p in prices) p.close];
      pLo = cl.reduce(math.min);
      pHi = cl.reduce(math.max);
      final pPad = math.max(1e-6, (pHi - pLo) * 0.12);
      pLo -= pPad;
      pHi += pPad;
    }
    double toChart(double price) =>
        hLo + (price - pLo) / (pHi - pLo) * (hHi - hLo);
    double toPrice(double y) => pLo + (y - hLo) / (hHi - hLo) * (pHi - pLo);

    final style = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 10,
    );
    final interval = (hHi - hLo) / 4;
    final withYear = maxX >= 360;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey('holders-price-chart'),
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: hLo,
              maxY: hHi,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: g.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: _titles(
                muted: g.textSecondary,
                minX: 0,
                maxX: maxX,
                origin: origin,
                withYear: withYear,
                leftInterval: interval,
                leftSize: 44,
                left: (v, meta) =>
                    (v - hLo).abs() < 1e-6 || (v - hHi).abs() < 1e-6
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(screenerCount(v), style: style),
                      ),
                rightSize: showPrices ? 44 : 0,
                right: showPrices
                    ? (v, meta) =>
                          (v - hLo).abs() < 1e-6 || (v - hHi).abs() < 1e-6
                          ? const SizedBox.shrink()
                          : SideTitleWidget(
                              meta: meta,
                              child: Text(
                                screenerNum(toPrice(v).round()),
                                style: style.copyWith(color: blue),
                              ),
                            )
                    : null,
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final h in holders)
                      FlSpot(dx(h.date), h.count.toDouble()),
                  ],
                  isCurved: false,
                  barWidth: 3,
                  color: primary,
                  dotData: FlDotData(show: holders.length <= 24),
                  belowBarData: BarAreaData(
                    show: true,
                    color: primary.withValues(alpha: 0.12),
                  ),
                ),
                if (showPrices)
                  LineChartBarData(
                    spots: [
                      for (final p in prices)
                        FlSpot(dx(p.date), toChart(p.close)),
                    ],
                    isCurved: false,
                    barWidth: 2,
                    color: blue,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _Legend(color: primary, label: 'Pemegang'),
            if (showPrices) _Legend(color: blue, label: 'Harga'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
      ),
    ],
  );
}

/// Change of each report vs the one before it. Falls in the primary colour,
/// rises muted; the axis carries signed numbers.
class ChangeBarsChart extends StatelessWidget {
  const ChangeBarsChart({super.key, required this.history});

  /// Oldest first, already clamped to the range.
  final List<ShareholderPoint> history;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final steps = <({DateTime date, int delta})>[
      for (var i = 1; i < history.length; i++)
        (date: history[i].date, delta: history[i].count - history[i - 1].count),
    ];
    if (steps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Belum cukup laporan untuk dibandingkan',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ),
      );
    }
    final maxAbs = steps.map((s) => s.delta.abs()).reduce(math.max).toDouble();
    final bound = math.max(1.0, maxAbs * 1.15);
    final style = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 10,
    );
    final labelEvery = math.max(1, (steps.length / 4).ceil());
    return SizedBox(
      key: const ValueKey('change-bars-chart'),
      height: 170,
      child: BarChart(
        BarChartData(
          minY: -bound,
          maxY: bound,
          alignment: BarChartAlignment.spaceBetween,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: bound,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: v == 0 ? g.textMuted : g.border, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: bound,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    v == 0
                        ? '0'
                        : '${v < 0 ? '−' : '+'}${screenerCount(v.abs())}',
                    style: style,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= steps.length || i % labelEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = steps[i].date;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      axisDateLabel(d, withYear: steps.length > 20),
                      style: style,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < steps.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: steps[i].delta.toDouble(),
                    width: steps.length > 40 ? 3 : 8,
                    color: steps[i].delta < 0
                        ? primary
                        : g.textMuted.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Stacked bars per month: tickers whose count fell (primary) vs rose
/// (muted).
class BreadthChart extends StatelessWidget {
  const BreadthChart({super.key, required this.months});

  final List<BreadthMonth> months;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final muted = g.textMuted.withValues(alpha: 0.55);
    final maxY = months
        .map((m) => (m.declining + m.rising).toDouble())
        .fold<double>(1, math.max);
    final style = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 10,
    );
    final every = math.max(1, (months.length / 5).ceil());
    return SizedBox(
      key: const ValueKey('breadth-chart'),
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.1,
          alignment: BarChartAlignment.spaceBetween,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: g.border, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(screenerCount(v), style: style),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= months.length || i % every != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = months[i].month;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      '${Fmt.monthShort(d.month)} ${d.year % 100}',
                      style: style,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (months[i].declining + months[i].rising).toDouble(),
                    width: months.length > 18 ? 6 : 10,
                    borderRadius: BorderRadius.circular(2),
                    rodStackItems: [
                      BarChartRodStackItem(
                        0,
                        months[i].declining.toDouble(),
                        primary,
                      ),
                      BarChartRodStackItem(
                        months[i].declining.toDouble(),
                        (months[i].declining + months[i].rising).toDouble(),
                        muted,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Buckets of the decline (|changePercent|) across the screen results.
const histogramBuckets = ['0–5%', '5–10%', '10–20%', '20–40%', '40%+'];

/// Count of [rows] per bucket of [histogramBuckets]; only declines count.
List<int> declineHistogram(List<ScreenerRow> rows) {
  final out = List<int>.filled(histogramBuckets.length, 0);
  for (final r in rows) {
    if (r.changePercent >= 0) continue;
    final d = -r.changePercent;
    final i = d < 5 ? 0 : (d < 10 ? 1 : (d < 20 ? 2 : (d < 40 ? 3 : 4)));
    out[i]++;
  }
  return out;
}

class DeclineHistogram extends StatelessWidget {
  const DeclineHistogram({super.key, required this.rows});

  final List<ScreenerRow> rows;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final counts = declineHistogram(rows);
    final maxC = counts.fold<int>(1, math.max).toDouble();
    final style = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 10,
    );
    return SizedBox(
      key: const ValueKey('decline-histogram'),
      height: 120,
      child: BarChart(
        BarChartData(
          maxY: maxC * 1.1,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${counts[v.toInt()]}',
                        style: style.w(900).copyWith(color: g.textPrimary),
                      ),
                      Text(histogramBuckets[v.toInt()], style: style),
                    ],
                  ),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < counts.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    width: 22,
                    color: primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
