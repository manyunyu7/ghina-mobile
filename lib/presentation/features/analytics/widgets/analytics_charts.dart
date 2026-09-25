import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../domain/usecases/analytics_spending.dart';
import '../../../design_system/design_system.dart';
import 'analytics_common.dart';

// ------------------------------------------------------------------ helpers

TextStyle _axis(GhinaTokens g) =>
    GhinaType.caption.copyWith(color: g.textSecondary, fontSize: 11);

Color _tooltipBg(GhinaTokens g) =>
    g.isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.ink;

TextStyle get _tipTitle =>
    GhinaType.caption.copyWith(color: Colors.white70, fontSize: 11);
TextStyle get _tipValue =>
    GhinaType.moneyS.copyWith(color: Colors.white, fontSize: 13);

/// Compact amount without the currency symbol for axes (`250 rb`, `1,5 jt`).
String axisMoney(BuildContext context, num v, String currency) {
  final s = aMoney(context, v, currency, compact: true);
  final sym = '${GhinaMoney.symbolFor(currency)} ';
  return s.replaceFirst(sym, '');
}

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

/// Scale for a max value: (interval, maxY).
({double interval, double maxY}) _scale(double maxV, {int ticks = 3}) {
  final interval = niceStep((maxV <= 0 ? 1 : maxV) / ticks);
  final maxY = maxV <= 0
      ? interval * ticks
      : (maxV / interval).ceil() * interval;
  return (interval: interval, maxY: maxY);
}

FlGridData _grid(GhinaTokens g, double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (v) => FlLine(
    color: v == 0 ? g.textMuted.withValues(alpha: 0.6) : g.border,
    strokeWidth: v == 0 ? 1.5 : 1,
    dashArray: v == 0 ? null : [4, 5],
  ),
);

AxisTitles _leftMoney(BuildContext context, double interval, String currency) {
  final g = context.ghina;
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 40 * _textScale(context),
      interval: interval,
      getTitlesWidget: (v, meta) {
        if (v == meta.max && v != 0 && meta.max != meta.min + interval) {
          return const SizedBox.shrink();
        }
        return SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(axisMoney(context, v, currency), style: _axis(g)),
        );
      },
    ),
  );
}

AxisTitles _bottomLabels(
  BuildContext context,
  List<String> labels, {
  int? maxLabels,
}) {
  final g = context.ghina;
  final n = labels.length;
  final cap = maxLabels ?? 6;
  final step = n <= cap ? 1 : (n / cap).ceil();
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 22 * _textScale(context),
      interval: 1,
      getTitlesWidget: (v, meta) {
        if ((v - v.roundToDouble()).abs() > 0.01) {
          return const SizedBox.shrink();
        }
        final i = v.round();
        if (i < 0 || i >= n) return const SizedBox.shrink();
        if (i % step != 0) return const SizedBox.shrink();
        return SideTitleWidget(
          meta: meta,
          space: 6,
          child: Text(labels[i], style: _axis(g), maxLines: 1),
        );
      },
    ),
  );
}

const _noTitles = AxisTitles();

/// Axis label of a bucket start.
String bucketLabel(DateTime d, Granularity g) => switch (g) {
  Granularity.day => '${d.day}',
  Granularity.week => '${d.day}/${d.month}',
  Granularity.month =>
    d.month == 1
        ? "${Fmt.monthShort(1)} '${d.year % 100}"
        : Fmt.monthShort(d.month),
};

/// Tooltip title of a bucket.
String bucketTitle(DateTime start, DateTime end, Granularity g) => switch (g) {
  Granularity.day => Fmt.dateShortWeekday(start),
  Granularity.week =>
    isSameDay(start, end)
        ? Fmt.dateShortWeekday(start)
        : '${start.day} ${Fmt.monthShort(start.month)} – ${end.day} ${Fmt.monthShort(end.month)}',
  Granularity.month => Fmt.monthYear(start),
};

Color _catColor(String hex) => CategoryColors.parse(hex);

// ------------------------------------------------------------------ donut

/// Donut by category with tap-to-highlight and a legend (amount + %).
/// Legend rows open the category ([onOpen]); "Lainnya" expands the rest.
class SpendDonut extends StatefulWidget {
  const SpendDonut({
    super.key,
    required this.rows,
    required this.currency,
    required this.onOpen,
    this.top = 8,
  });

  /// All categories, largest first.
  final List<CategorySpend> rows;
  final String currency;
  final ValueChanged<String> onOpen;
  final int top;

  @override
  State<SpendDonut> createState() => _SpendDonutState();
}

class _SpendDonutState extends State<SpendDonut> {
  int? _touched;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final slices = topWithOther(widget.rows, top: widget.top);
    final total = slices.fold<double>(0, (s, r) => s + r.total);
    final t = _touched;
    final focus = t != null && t < slices.length ? slices[t] : null;
    final legend = _showAll ? widget.rows : slices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                duration: GhinaMotion.medium,
                curve: GhinaMotion.standard,
                PieChartData(
                  centerSpaceRadius: 62,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (e, r) {
                      if (e is! FlTapUpEvent && e is! FlLongPressEnd) return;
                      final i = r?.touchedSection?.touchedSectionIndex;
                      if (i == null || i < 0) return;
                      setState(() => _touched = _touched == i ? null : i);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].total,
                        color: t == null || t == i
                            ? _catColor(slices[i].color)
                            : _catColor(
                                slices[i].color,
                              ).withValues(alpha: 0.35),
                        radius: i == t ? 40 : 32,
                        showTitle: false,
                        borderSide: BorderSide(color: g.surface, width: 2),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      focus?.name ?? 'Total keluar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MoneyText(
                        amount: focus?.total ?? total,
                        currency: widget.currency,
                        tone: MoneyTone.neutral,
                        compact: true,
                        style: GhinaType.h3.w(900),
                      ),
                    ),
                    if (focus != null)
                      Text(
                        pctLabel(focus.pct, signed: false),
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < legend.length; i++)
          _LegendRow(
            key: ValueKey('donut-row-${legend[i].key}'),
            row: legend[i],
            currency: widget.currency,
            highlighted: !_showAll && i == t,
            dimmed: !_showAll && t != null && i != t,
            onTap: legend[i].key == kOtherKey
                ? () => setState(() => _showAll = true)
                : () => widget.onOpen(legend[i].key),
          ),
        if (_showAll && widget.rows.length > slices.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = false),
              child: const Text('Ringkas'),
            ),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    super.key,
    required this.row,
    required this.currency,
    required this.highlighted,
    required this.dimmed,
    required this.onTap,
  });

  final CategorySpend row;
  final String currency;
  final bool highlighted;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final isOther = row.key == kOtherKey;
    return InkWell(
      borderRadius: GhinaRadii.rMd,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: GhinaMotion.fast,
        opacity: dimmed ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _catColor(row.color),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isOther ? 'Lainnya' : row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS
                      .w(highlighted ? 900 : 700)
                      .copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              MoneyText(
                amount: row.total,
                currency: currency,
                tone: MoneyTone.neutral,
                compact: row.total >= 10000000,
                style: GhinaType.moneyS,
              ),
              SizedBox(
                width: 42,
                child: Text(
                  pctLabel(row.pct, signed: false),
                  textAlign: TextAlign.right,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
              Icon(
                isOther
                    ? Icons.expand_more_rounded
                    : Icons.chevron_right_rounded,
                size: 20,
                color: g.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ trend

/// Spending over time: an area line (with the previous period as a dashed
/// ghost line) or bars stacked by the top categories.
class SpendTrendChart extends StatelessWidget {
  const SpendTrendChart({
    super.key,
    required this.buckets,
    required this.granularity,
    required this.currency,
    this.stacked = false,
    this.stackKeys = const [],
    this.color,
    this.height = 210,
    this.cutoff,
  });

  /// Buckets starting after this day (the future of a running period) are
  /// left off the line.
  final DateTime? cutoff;

  final List<TrendBucket> buckets;
  final Granularity granularity;
  final String currency;
  final bool stacked;

  /// Series of the stacked mode, bottom first (the rest = "Lainnya").
  final List<CategoryInfo> stackKeys;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: stacked ? _stacked(context) : _line(context),
  );

  List<String> get _labels => [
    for (final b in buckets) bucketLabel(b.start, granularity),
  ];

  Widget _line(BuildContext context) {
    final g = context.ghina;
    final c = color ?? GhinaColors.red.base;
    final n = buckets.length;
    final hasPrev = buckets.any((b) => b.previous != null);
    final maxV = buckets.fold<double>(
      0,
      (m, b) => math.max(m, math.max(b.total, b.previous ?? 0)),
    );
    final s = _scale(maxV);
    final cut = cutoff;
    final main = LineChartBarData(
      spots: [
        for (var i = 0; i < n; i++)
          if (cut == null || !buckets[i].start.isAfter(cut))
            FlSpot(i.toDouble(), buckets[i].total),
      ],
      isCurved: n > 2,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      color: c,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: n <= 16,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 3.5,
          color: c,
          strokeWidth: 2,
          strokeColor: g.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0.02)],
        ),
      ),
    );
    final ghost = LineChartBarData(
      spots: [
        for (var i = 0; i < n; i++)
          FlSpot(i.toDouble(), buckets[i].previous ?? 0),
      ],
      isCurved: n > 2,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      color: g.textMuted,
      barWidth: 2,
      dashArray: [5, 5],
      dotData: const FlDotData(show: false),
    );
    return LineChart(
      duration: GhinaMotion.slow,
      curve: GhinaMotion.standard,
      LineChartData(
        minX: n == 1 ? -0.5 : 0,
        maxX: n == 1 ? 0.5 : (n - 1).toDouble(),
        minY: 0,
        maxY: s.maxY,
        borderData: FlBorderData(show: false),
        gridData: _grid(g, s.interval),
        titlesData: FlTitlesData(
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: _leftMoney(context, s.interval, currency),
          bottomTitles: _bottomLabels(context, _labels),
        ),
        lineTouchData: LineTouchData(
          touchSpotThreshold: 24,
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(color: g.textMuted, strokeWidth: 1, dashArray: [3, 3]),
                FlDotData(
                  getDotPainter: (s, _, b, _) => FlDotCirclePainter(
                    radius: 5,
                    color: b.color ?? c,
                    strokeWidth: 2,
                    strokeColor: g.surface,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _tooltipBg(g),
            tooltipBorderRadius: GhinaRadii.rMd,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final sp in spots)
                () {
                  final b = buckets[sp.x.round().clamp(0, n - 1)];
                  final isGhost = hasPrev && sp.barIndex == 0;
                  if (isGhost) {
                    return LineTooltipItem(
                      'Sebelumnya ',
                      _tipTitle,
                      children: [
                        TextSpan(
                          text: aMoney(context, b.previous ?? 0, currency),
                          style: _tipValue.copyWith(color: Colors.white70),
                        ),
                      ],
                    );
                  }
                  return LineTooltipItem(
                    '${bucketTitle(b.start, b.end, granularity)}\n',
                    _tipTitle,
                    children: [
                      TextSpan(
                        text: aMoney(context, b.total, currency),
                        style: _tipValue,
                      ),
                    ],
                  );
                }(),
            ],
          ),
        ),
        lineBarsData: [if (hasPrev) ghost, main],
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    final g = context.ghina;
    final n = buckets.length;
    final keys = stackKeys.map((k) => k.key).toList();
    final colors = [for (final k in stackKeys) _catColor(k.color)];
    final otherColor = g.isDark
        ? const Color(0xFF64748B)
        : const Color(0xFFB8C2CF);
    final maxV = buckets.fold<double>(0, (m, b) => math.max(m, b.total));
    final s = _scale(maxV);
    return LayoutBuilder(
      builder: (context, box) {
        final plotW = math.max(40.0, box.maxWidth - 44 * _textScale(context));
        final rodW = (plotW / math.max(n, 1) * 0.62).clamp(3.0, 28.0);
        return BarChart(
          duration: GhinaMotion.slow,
          curve: GhinaMotion.standard,
          BarChartData(
            minY: 0,
            maxY: s.maxY,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: _grid(g, s.interval),
            titlesData: FlTitlesData(
              topTitles: _noTitles,
              rightTitles: _noTitles,
              leftTitles: _leftMoney(context, s.interval, currency),
              bottomTitles: _bottomLabels(context, _labels),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => _tooltipBg(g),
                tooltipBorderRadius: GhinaRadii.rMd,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, r, ri) {
                  final b = buckets[gi];
                  final parts = b.byKey.entries.toList()
                    ..sort((a, c) => c.value.compareTo(a.value));
                  return BarTooltipItem(
                    '${bucketTitle(b.start, b.end, granularity)}\n',
                    _tipTitle,
                    textAlign: TextAlign.left,
                    children: [
                      TextSpan(
                        text: aMoney(context, b.total, currency),
                        style: _tipValue,
                      ),
                      for (final p in parts.take(3))
                        TextSpan(
                          text:
                              '\n${_nameOf(p.key)} · ${aMoney(context, p.value, currency, compact: true)}',
                          style: _tipTitle,
                        ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < n; i++)
                () {
                  final b = buckets[i];
                  var from = 0.0;
                  final items = <BarChartRodStackItem>[];
                  for (var k = 0; k < keys.length; k++) {
                    final v = b.byKey[keys[k]] ?? 0;
                    if (v <= 0) continue;
                    items.add(BarChartRodStackItem(from, from + v, colors[k]));
                    from += v;
                  }
                  final rest = b.total - from;
                  if (rest > 0.0001) {
                    items.add(BarChartRodStackItem(from, b.total, otherColor));
                  }
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: b.total,
                        width: rodW,
                        color: otherColor,
                        rodStackItems: items,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(math.min(4, rodW / 2)),
                        ),
                      ),
                    ],
                  );
                }(),
            ],
          ),
        );
      },
    );
  }

  String _nameOf(String key) {
    for (final k in stackKeys) {
      if (k.key == key) return k.name;
    }
    return key == kTransferKey
        ? 'Transfer'
        : key == kUncategorizedKey
        ? 'Tanpa kategori'
        : 'Lainnya';
  }
}

// ------------------------------------------------------------------ patterns

/// Single-series bars (weekday / hour patterns); the peak is solid, the rest
/// lighter.
class PatternBarChart extends StatelessWidget {
  const PatternBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.currency,
    required this.tooltip,
    this.maxLabels = 7,
    this.height = 170,
    this.color,
  });

  final List<double> values;
  final List<String> labels;
  final String currency;

  /// Tooltip text lines for bar i: (title, value line).
  final (String, String) Function(int i) tooltip;
  final int maxLabels;
  final double height;
  final ChunkySwatch? color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = color ?? GhinaColors.red;
    final n = values.length;
    final maxV = values.fold<double>(0, math.max);
    final peak = maxV > 0 ? values.indexOf(maxV) : -1;
    final s = _scale(maxV);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plotW = math.max(40.0, box.maxWidth - 44 * _textScale(context));
          final rodW = (plotW / math.max(n, 1) * 0.6).clamp(3.0, 26.0);
          return BarChart(
            duration: GhinaMotion.slow,
            curve: GhinaMotion.standard,
            BarChartData(
              minY: 0,
              maxY: s.maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: _grid(g, s.interval),
              titlesData: FlTitlesData(
                topTitles: _noTitles,
                rightTitles: _noTitles,
                leftTitles: _leftMoney(context, s.interval, currency),
                bottomTitles: _bottomLabels(
                  context,
                  labels,
                  maxLabels: maxLabels,
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => _tooltipBg(g),
                  tooltipBorderRadius: GhinaRadii.rMd,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, r, ri) {
                    final (title, line) = tooltip(gi);
                    return BarTooltipItem(
                      '$title\n',
                      _tipTitle,
                      children: [TextSpan(text: line, style: _tipValue)],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        width: rodW,
                        color: i == peak
                            ? sw.base
                            : sw.base.withValues(alpha: g.isDark ? 0.55 : 0.42),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(math.min(4, rodW / 2)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ flow

/// Grouped income (green) vs expense (red) bars per bucket.
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars({
    super.key,
    required this.buckets,
    required this.granularity,
    required this.currency,
    this.height = 190,
  });

  final List<FlowBucket> buckets;
  final Granularity granularity;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final n = buckets.length;
    final maxV = buckets.fold<double>(
      0,
      (m, b) => math.max(m, math.max(b.income, b.expense)),
    );
    final s = _scale(maxV);
    final labels = [for (final b in buckets) bucketLabel(b.start, granularity)];
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plotW = math.max(40.0, box.maxWidth - 44 * _textScale(context));
          final rodW = (plotW / math.max(n, 1) * 0.32).clamp(2.0, 16.0);
          BarChartRodData rod(double v, Color c) => BarChartRodData(
            toY: v,
            width: rodW,
            color: c,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(math.min(4, rodW / 2)),
            ),
          );
          return BarChart(
            duration: GhinaMotion.slow,
            curve: GhinaMotion.standard,
            BarChartData(
              minY: 0,
              maxY: s.maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: _grid(g, s.interval),
              titlesData: FlTitlesData(
                topTitles: _noTitles,
                rightTitles: _noTitles,
                leftTitles: _leftMoney(context, s.interval, currency),
                bottomTitles: _bottomLabels(context, labels),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => _tooltipBg(g),
                  tooltipBorderRadius: GhinaRadii.rMd,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, r, ri) {
                    final b = buckets[gi];
                    final end = gi + 1 < n
                        ? DateTime(
                            buckets[gi + 1].start.year,
                            buckets[gi + 1].start.month,
                            buckets[gi + 1].start.day - 1,
                          )
                        : b.start;
                    return BarTooltipItem(
                      '${bucketTitle(b.start, granularity == Granularity.day ? b.start : end, granularity)}\n',
                      _tipTitle,
                      textAlign: TextAlign.left,
                      children: [
                        TextSpan(
                          text:
                              'Masuk ${aMoney(context, b.income, currency)}\n',
                          style: _tipValue,
                        ),
                        TextSpan(
                          text:
                              'Keluar ${aMoney(context, b.expense, currency)}',
                          style: _tipValue,
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: math.min(3, rodW / 3),
                    barRods: [
                      rod(buckets[i].income, GhinaColors.green.base),
                      rod(buckets[i].expense, GhinaColors.red.base),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Running net cash flow (income − expense) over the period.
class CumulativeFlowLine extends StatelessWidget {
  const CumulativeFlowLine({
    super.key,
    required this.buckets,
    required this.granularity,
    required this.currency,
    this.height = 130,
    this.cutoff,
  });

  final DateTime? cutoff;
  final List<FlowBucket> buckets;
  final Granularity granularity;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final n = buckets.length;
    final cum = <double>[];
    var run = 0.0;
    for (final b in buckets) {
      run += b.net;
      cum.add(run);
    }
    final maxV = cum.fold<double>(0, math.max);
    final minV = cum.fold<double>(0, math.min);
    final interval = niceStep(math.max(1, maxV - minV) / 2);
    final maxY = maxV <= 0 ? interval : (maxV / interval).ceil() * interval;
    final minY = minV >= 0 ? 0.0 : (minV / interval).floor() * interval;
    final c = run >= 0 ? GhinaColors.green.base : GhinaColors.red.base;
    final labels = [for (final b in buckets) bucketLabel(b.start, granularity)];
    return SizedBox(
      height: height,
      child: LineChart(
        duration: GhinaMotion.slow,
        LineChartData(
          minX: n == 1 ? -0.5 : 0,
          maxX: n == 1 ? 0.5 : (n - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: _grid(g, interval),
          titlesData: FlTitlesData(
            topTitles: _noTitles,
            rightTitles: _noTitles,
            leftTitles: _leftMoney(context, interval, currency),
            bottomTitles: _bottomLabels(context, labels),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _tooltipBg(g),
              tooltipBorderRadius: GhinaRadii.rMd,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final sp in spots)
                  LineTooltipItem(
                    'Sampai ${bucketLabel(buckets[sp.x.round().clamp(0, n - 1)].start, granularity)}\n',
                    _tipTitle,
                    children: [
                      TextSpan(
                        text: context.money(
                          sp.y,
                          currency: currency,
                          showSign: true,
                        ),
                        style: _tipValue,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < n; i++)
                  if (cutoff == null || !buckets[i].start.isAfter(cutoff!))
                    FlSpot(i.toDouble(), cum[i]),
              ],
              isCurved: n > 2,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: c,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: GhinaColors.green.base.withValues(alpha: 0.14),
              ),
              aboveBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: GhinaColors.red.base.withValues(alpha: 0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ heatmap

/// Monday-first month grid colored by daily spend (one red hue, light →
/// dark), with a month switcher for multi-month periods and a tap detail.
class SpendHeatmap extends StatefulWidget {
  const SpendHeatmap({
    super.key,
    required this.period,
    required this.daily,
    required this.currency,
    required this.now,
  });

  final AnalyticsPeriod period;
  final Map<String, double> daily;
  final String currency;
  final DateTime now;

  @override
  State<SpendHeatmap> createState() => _SpendHeatmapState();
}

class _SpendHeatmapState extends State<SpendHeatmap> {
  late YearMonth _month = _initialMonth();
  DateTime? _selected;

  YearMonth _initialMonth() => widget.period.contains(widget.now)
      ? YearMonth.of(widget.now)
      : YearMonth.of(widget.period.end);

  @override
  void didUpdateWidget(SpendHeatmap old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _month = _initialMonth();
      _selected = null;
    }
  }

  YearMonth get _first => YearMonth.of(widget.period.start);
  YearMonth get _last => YearMonth.of(widget.period.end);

  /// 0 = none, 1–4 = intensity (square-root scale so small days still show).
  static int level(double v, double max) {
    if (v <= 0 || max <= 0) return 0;
    return (math.sqrt(v / max) * 4).ceil().clamp(1, 4);
  }

  static Color levelColor(int l, GhinaTokens g) {
    if (l == 0) return g.surfaceAlt;
    const alphas = <double>[0, 0.22, 0.45, 0.72, 1.0];
    return Color.alphaBlend(
      GhinaColors.red.base.withValues(alpha: alphas[l]),
      g.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = _month;
    final max = widget.daily.values.fold<double>(0, math.max);
    final monthTotal = widget.daily.entries
        .where((e) => e.key.startsWith('$m'))
        .fold<double>(0, (s, e) => s + e.value);
    final lead = m.start.weekday - 1;
    final dim = daysInMonth(m.year, m.month);
    final cells = lead + dim;
    final rows = (cells / 7).ceil();
    final multi = _first != _last;
    final sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (multi)
              _NavBtn(
                icon: Icons.chevron_left_rounded,
                onTap: m.compareTo(_first) > 0
                    ? () => setState(() {
                        _month = m.previous;
                        _selected = null;
                      })
                    : null,
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    Fmt.monthYear(m.start),
                    textAlign: TextAlign.center,
                    style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                  ),
                  MoneyText(
                    amount: monthTotal,
                    currency: widget.currency,
                    tone: MoneyTone.neutral,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                    color: g.textSecondary,
                  ),
                ],
              ),
            ),
            if (multi)
              _NavBtn(
                icon: Icons.chevron_right_rounded,
                onTap: m.compareTo(_last) < 0
                    ? () => setState(() {
                        _month = m.next;
                        _selected = null;
                      })
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final d in WeekdayStat.shortNames)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GhinaType.caption.copyWith(
                    color: g.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(context, r * 7 + c - lead + 1, m, max)),
            ],
          ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: GhinaMotion.fast,
          child: sel == null
              ? Row(
                  key: const ValueKey('legend'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Sedikit',
                      style: GhinaType.caption.copyWith(
                        color: g.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    for (var l = 0; l <= 4; l++)
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: levelColor(l, g),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      'Banyak',
                      style: GhinaType.caption.copyWith(
                        color: g.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                )
              : Container(
                  key: ValueKey(sel),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: g.surfaceAlt,
                    borderRadius: GhinaRadii.rMd,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          Fmt.dateShortWeekday(sel),
                          style: GhinaType.bodyS
                              .w(800)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                      MoneyText(
                        amount: widget.daily[dateKey(sel)] ?? 0,
                        currency: widget.currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyS,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, YearMonth m, double max) {
    final g = context.ghina;
    final dim = daysInMonth(m.year, m.month);
    if (day < 1 || day > dim) return const SizedBox(height: 40);
    final d = DateTime(m.year, m.month, day);
    final inPeriod = widget.period.contains(d);
    final v = widget.daily[dateKey(d)] ?? 0;
    final l = inPeriod ? level(v, max) : 0;
    final selected = _selected != null && isSameDay(_selected!, d);
    final today = isSameDay(d, widget.now);
    final fg = l >= 3 ? Colors.white : (inPeriod ? g.textPrimary : g.textMuted);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        label: '${Fmt.date(d)}: ${aMoney(context, v, widget.currency)}',
        button: true,
        child: GestureDetector(
          onTap: inPeriod
              ? () => setState(() => _selected = selected ? null : d)
              : null,
          child: AnimatedContainer(
            duration: GhinaMotion.fast,
            height: 36,
            decoration: BoxDecoration(
              color: inPeriod ? levelColor(l, g) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: g.textPrimary, width: 2)
                  : today
                  ? Border.all(color: GhinaColors.blue.base, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$day',
                style: GhinaType.caption
                    .w(l > 0 ? 800 : 600)
                    .copyWith(
                      color: inPeriod ? fg : g.textMuted.withValues(alpha: 0.5),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon),
    visualDensity: VisualDensity.compact,
    color: context.ghina.textSecondary,
  );
}

// ------------------------------------------------------------------ h-bars

/// A labelled horizontal bar row (wallet breakdown).
class HBarRow extends StatelessWidget {
  const HBarRow({
    super.key,
    required this.leading,
    required this.title,
    required this.amount,
    required this.fraction,
    required this.color,
    required this.currency,
    this.subtitle,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final double amount;

  /// 0–1 relative to the largest row.
  final double fraction;
  final Color color;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return InkWell(
      onTap: onTap,
      borderRadius: GhinaRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(800)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MoneyText(
                        amount: amount,
                        currency: currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyS,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, box) => Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: g.surfaceAlt,
                            borderRadius: GhinaRadii.rPill,
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: fraction.clamp(0.0, 1.0)),
                          duration: GhinaMotion.progress,
                          curve: GhinaMotion.standard,
                          builder: (context, f, _) => Container(
                            height: 10,
                            width: math.max(
                              f > 0 ? 6.0 : 0.0,
                              box.maxWidth * f,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: GhinaRadii.rPill,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(
                        color: g.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
