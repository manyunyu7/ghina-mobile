import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/dates.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../habit_format.dart';

/// Calendar month heatmap (Monday first) of [cells] (one per day of the
/// month, oldest first).
class MonthHeatmap extends StatelessWidget {
  const MonthHeatmap({
    super.key,
    required this.cells,
    required this.color,
    this.onTapDay,
  });

  final List<HabitDayCell> cells;
  final ChunkySwatch color;
  final ValueChanged<HabitDayCell>? onTapDay;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (cells.isEmpty) return const SizedBox.shrink();
    final lead = parseDateKey(cells.first.date).weekday - 1;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 6.0;
        final size = (c.maxWidth - gap * 6) / 7;
        return Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: size,
                    child: Text(
                      weekdaysShort[i].substring(0, 1),
                      textAlign: TextAlign.center,
                      style: GhinaType.caption
                          .w(800)
                          .copyWith(color: g.textMuted),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < lead; i++)
                  SizedBox(width: size, height: size),
                for (final cell in cells)
                  _DayCell(
                    cell: cell,
                    size: size,
                    color: color,
                    onTap: onTapDay == null ? null : () => onTapDay!(cell),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.cell,
    required this.size,
    required this.color,
    this.onTap,
  });

  final HabitDayCell cell;
  final double size;
  final ChunkySwatch color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final bg = heatmapColor(context, cell, color);
    final strong =
        cell.state == HabitDayState.met ||
        cell.state == HabitDayState.clean ||
        cell.state == HabitDayState.relapse;
    final day = parseDateKey(cell.date).day;
    return Semantics(
      label: '$day, ${heatmapStateLabel(cell.state)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(size * 0.3),
            border: cell.state == HabitDayState.pending
                ? Border.all(color: color.base, width: 2)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                textScaler: TextScaler.noScaling,
                style: GhinaType.caption
                    .w(800)
                    .copyWith(
                      fontSize: math.min(13, size * 0.36),
                      color: strong ? Colors.white : g.textSecondary,
                    ),
              ),
              if (cell.hasNote)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: strong ? Colors.white : color.base,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A year at a glance: one column per week (horizontally scrollable, ending
/// at the most recent week).
class YearHeatmap extends StatelessWidget {
  const YearHeatmap({super.key, required this.cells, required this.color});

  final List<HabitDayCell> cells;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (cells.isEmpty) return const SizedBox.shrink();
    const cell = 12.0, gap = 3.0;
    final lead = parseDateKey(cells.first.date).weekday - 1;
    final all = <HabitDayCell?>[...List.filled(lead, null), ...cells];
    final weeks = <List<HabitDayCell?>>[
      for (var i = 0; i < all.length; i += 7)
        all.sublist(i, math.min(i + 7, all.length)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              for (var d = 0; d < 7; d++)
                SizedBox(
                  height: cell + gap,
                  width: 22,
                  child: d.isEven
                      ? Text(
                          weekdaysShort[d],
                          style: GhinaType.caption.copyWith(
                            fontSize: 9,
                            color: g.textMuted,
                          ),
                          textScaler: TextScaler.noScaling,
                        )
                      : null,
                ),
            ],
          ),
          for (final w in weeks)
            Padding(
              padding: const EdgeInsets.only(right: gap),
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: gap),
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: d < w.length && w[d] != null
                              ? heatmapColor(context, w[d]!, color)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Legend under the heatmaps.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key, required this.kind, required this.color});

  final HabitKind kind;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final states = kind == HabitKind.quit
        ? const [HabitDayState.clean, HabitDayState.relapse]
        : const [
            HabitDayState.met,
            HabitDayState.partial,
            HabitDayState.missed,
            HabitDayState.skip,
          ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final s in states)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: heatmapColor(
                    context,
                    HabitDayCell(
                      date: '2026-01-01',
                      state: s,
                      value: 1,
                      goal: 2,
                    ),
                    color,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                heatmapStateLabel(s),
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Streak at the end of each day (step line).
class StreakHistoryChart extends StatelessWidget {
  const StreakHistoryChart({
    super.key,
    required this.points,
    required this.color,
  });

  final List<StreakPoint> points;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (points.length < 2) return const SizedBox.shrink();
    final maxY = points.fold<int>(1, (m, p) => math.max(m, p.streak));
    final step = math.max(1, (points.length / 4).ceil());
    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: (maxY * 1.15).ceilToDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (maxY / 3).ceilToDouble()),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: g.border, strokeWidth: 1, dashArray: [4, 4]),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: math.max(1, (maxY / 3).ceilToDouble()),
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: step.toDouble(),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final d = parseDateKey(points[i].date);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${d.day}/${d.month}',
                      style: GhinaType.caption.copyWith(
                        fontSize: 10,
                        color: g.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final (i, p) in points.indexed)
                  FlSpot(i.toDouble(), p.streak.toDouble()),
              ],
              isStepLineChart: true,
              color: color.base,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.base.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple labelled bars (weekday / hour distributions).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.height = 90,
  });

  final List<int> values;

  /// Label per bar ('' = none).
  final List<String> labels;
  final ChunkySwatch color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final maxV = values.fold<int>(0, math.max);
    final peak = maxV == 0 ? -1 : values.indexOf(maxV);
    return SizedBox(
      height: height + 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: values.length > 12 ? 1 : 4,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: maxV == 0
                          ? 3
                          : math.max(3, height * values[i] / maxV),
                      decoration: BoxDecoration(
                        color: i == peak
                            ? color.base
                            : color.base.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 16,
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        textScaler: TextScaler.noScaling,
                        style: GhinaType.caption.copyWith(
                          fontSize: 10,
                          color: g.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
