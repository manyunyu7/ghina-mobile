import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../investment_format.dart';

enum AllocationMode { asset, kind }

/// Allocation donut with a "Per aset / Per jenis" switch and a legend.
class AllocationCard extends StatefulWidget {
  const AllocationCard({
    super.key,
    required this.summary,
    required this.currency,
  });

  final PortfolioSummary summary;
  final String currency;

  @override
  State<AllocationCard> createState() => _AllocationCardState();
}

class _AllocationCardState extends State<AllocationCard> {
  AllocationMode _mode = AllocationMode.asset;
  int? _touched;

  List<({String label, double value, double pct, Color color})> get _slices {
    final s = widget.summary;
    if (_mode == AllocationMode.kind) {
      return [
        for (final x in s.byKind)
          (
            label: x.label,
            value: x.value,
            pct: x.pct,
            color: kindSwatch(AssetKind.fromWire(x.key)).base,
          ),
      ];
    }
    return [
      for (var i = 0; i < s.byAsset.length; i++)
        (
          label: s.byAsset[i].label,
          value: s.byAsset[i].value,
          pct: s.byAsset[i].pct,
          color: assetSlicePalette[i % assetSlicePalette.length].base,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final slices = _slices;
    final total = slices.fold(0.0, (s, x) => s + x.value);
    final t = _touched != null && _touched! < slices.length ? _touched : null;
    final focus = t == null ? null : slices[t];
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkySegmented<AllocationMode>(
            height: 38,
            segments: const [
              ChunkySegment(
                value: AllocationMode.asset,
                label: 'Per aset',
                color: GhinaColors.purple,
              ),
              ChunkySegment(
                value: AllocationMode.kind,
                label: 'Per jenis',
                color: GhinaColors.purple,
              ),
            ],
            value: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _touched = null;
            }),
          ),
          const SizedBox(height: 12),
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Belum ada aset yang dimiliki.',
                textAlign: TextAlign.center,
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            )
          else ...[
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    duration: GhinaMotion.medium,
                    PieChartData(
                      centerSpaceRadius: 56,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (e, r) {
                          if (!e.isInterestedForInteractions) return;
                          setState(
                            () => _touched =
                                r?.touchedSection?.touchedSectionIndex,
                          );
                        },
                      ),
                      sections: [
                        for (var i = 0; i < slices.length; i++)
                          PieChartSectionData(
                            value: slices[i].value,
                            color: slices[i].color,
                            radius: i == t ? 40 : 32,
                            showTitle: false,
                            borderSide: BorderSide(color: g.surface, width: 2),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          focus?.label ?? 'Total',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            context.money(
                              focus?.value ?? total,
                              currency: widget.currency,
                              compact: true,
                            ),
                            style: GhinaType.h3
                                .w(900)
                                .copyWith(color: g.textPrimary),
                          ),
                        ),
                        if (focus != null)
                          Text(
                            '${Fmt.number(focus.pct, decimals: 1)}%',
                            style: GhinaType.caption
                                .w(900)
                                .copyWith(color: focus.color),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < slices.length; i++)
              InkWell(
                borderRadius: GhinaRadii.rMd,
                onTap: () =>
                    setState(() => _touched = _touched == i ? null : i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: slices[i].color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          slices[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS
                              .w(i == t ? 900 : 700)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.money(
                          slices[i].value,
                          currency: widget.currency,
                          compact: true,
                        ),
                        style: GhinaType.moneyS.copyWith(color: g.textPrimary),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${Fmt.number(slices[i].pct, decimals: slices[i].pct < 10 ? 1 : 0)}%',
                          textAlign: TextAlign.right,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// History window of the value chart.
enum HistoryRange {
  month('1B', 30),
  quarter('3B', 90),
  year('1T', 365);

  const HistoryRange(this.label, this.days);
  final String label;
  final int days;

  ({String from, String to}) window(DateTime now) =>
      (from: dateKey(addDays(now, -days)), to: dateKey(now));
}

/// Portfolio value (thick line) vs cost basis (dashed) over the device's
/// daily snapshots.
class ValueHistoryChart extends StatelessWidget {
  const ValueHistoryChart({
    super.key,
    required this.points,
    required this.currency,
  });

  final List<PortfolioPoint> points;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final hidden = context.moneyHidden;
    final values = [
      for (final p in points) ...[p.value, p.cost],
    ];
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = maxV - minV;
    final pad = span == 0 ? (maxV.abs() * 0.1 + 1000) : span * 0.15;
    final up = points.last.value >= points.last.cost;
    final sw = up ? GhinaColors.green : GhinaColors.red;
    final labelStyle = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 11,
    );
    final n = points.length;
    String dayLabel(int i) {
      final d = parseDateKey(points[i].date);
      return '${d.day} ${Fmt.monthShort(d.month)}';
    }

    return LineChart(
      duration: GhinaMotion.slow,
      LineChartData(
        minX: 0,
        maxX: (n - 1).toDouble(),
        minY: minV - pad,
        maxY: maxV + pad,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: g.border, strokeWidth: 1.5, dashArray: [6, 6]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !hidden,
              reservedSize: hidden ? 0 : 46,
              getTitlesWidget: (v, meta) {
                if (v == meta.min || v == meta.max) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    GhinaMoney.format(
                      v,
                      currency: currency,
                      compact: true,
                    ).replaceFirst('Rp ', ''),
                    style: labelStyle,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: math.max(1, (n - 1) / 3).floorToDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= n || v != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(dayLabel(i), style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => g.surface,
            tooltipBorder: BorderSide(color: g.border, width: 2),
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  s.barIndex == 0
                      ? '${dayLabel(s.x.round())}\n${context.money(s.y, currency: currency)}'
                      : 'Modal ${context.money(s.y, currency: currency)}',
                  GhinaType.caption
                      .w(800)
                      .copyWith(
                        color: s.barIndex == 0 ? sw.base : g.textSecondary,
                      ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < n; i++) FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: sw.base,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(show: n <= 2),
            belowBarData: BarAreaData(
              show: true,
              color: sw.base.withValues(alpha: 0.12),
            ),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < n; i++) FlSpot(i.toDouble(), points[i].cost),
            ],
            color: g.textMuted,
            barWidth: 2,
            dashArray: [6, 5],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
