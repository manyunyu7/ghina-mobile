import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_data_providers.dart';
import '../widgets/killa_common.dart';

/// `$0.42` (≥ $100 without cents).
String killaUsd(double v) => v >= 100
    ? '\$${Fmt.number(v)}'
    : '\$${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// `1,2 jt`, `45 rb`, `812`.
String killaTokens(int n) {
  if (n >= 1000000) {
    return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt';
  }
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)} rb';
  return '$n';
}

enum _Metric { cost, tokens }

/// Killa usage of the last 30 days (`/killa/usage`): daily bars, totals and
/// per-model. Cost is an API-price estimate, not a bill.
class KillaUsagePage extends ConsumerStatefulWidget {
  const KillaUsagePage({super.key});

  static const days = 30;

  @override
  ConsumerState<KillaUsagePage> createState() => _KillaUsagePageState();
}

class _KillaUsagePageState extends ConsumerState<KillaUsagePage> {
  _Metric _metric = _Metric.cost;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(killaUsageProvider(KillaUsagePage.days));
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Pemakaian Killa')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(killaUsageProvider(KillaUsagePage.days).future),
        child: switch (async) {
          AsyncData(:final value) => _content(value),
          AsyncError(:final error) => KillaErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(killaUsageProvider(KillaUsagePage.days)),
          ),
          _ => const LoadingListView(tiles: 4),
        },
      ),
    );
  }

  Widget _content(KillaUsage u) {
    final g = context.ghina;
    final models = u.byModel.entries.toList()
      ..sort((a, b) => b.value.costUsd.compareTo(a.value.costUsd));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        ChunkyCard(
          tinted: killaSwatch,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESTIMASI BIAYA · ${KillaUsagePage.days} HARI',
                style: GhinaType.overline.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(killaUsd(u.total.costUsd), style: GhinaType.moneyXL),
              const SizedBox(height: 4),
              Text(
                'Perkiraan dengan harga API — bukan tagihan.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.forum_rounded,
                value: Fmt.number(u.total.turns),
                label: 'Giliran',
                color: GhinaColors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.data_usage_rounded,
                value: killaTokens(u.total.totalTokens),
                label: 'Token',
                color: GhinaColors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TokenBreakdown(t: u.total),
        const SizedBox(height: 28),
        SectionHeader(
          title: 'Per hari',
          trailing: SizedBox(
            width: 170,
            child: ChunkySegmented<_Metric>(
              height: 38,
              segments: const [
                ChunkySegment(value: _Metric.cost, label: 'Biaya'),
                ChunkySegment(value: _Metric.tokens, label: 'Token'),
              ],
              value: _metric,
              onChanged: (m) => setState(() => _metric = m),
            ),
          ),
        ),
        ChunkyCard(
          padding: const EdgeInsets.fromLTRB(8, 18, 12, 8),
          child: u.days.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Belum ada pemakaian')),
                )
              : _DailyBars(days: u.days, metric: _metric),
        ),
        const SizedBox(height: 28),
        const SectionHeader(title: 'Per model'),
        if (models.isEmpty)
          Text(
            'Belum ada data.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          )
        else
          ChunkyCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final e in models)
                  ChunkyTile(
                    framed: false,
                    dense: true,
                    leading: CategoryAvatar(
                      icon: Icons.memory_rounded,
                      color: killaSwatch.base,
                      size: 36,
                    ),
                    title: e.key,
                    subtitle:
                        '${Fmt.number(e.value.turns)} giliran · '
                        '${killaTokens(e.value.totalTokens)} token',
                    trailing: Text(
                      killaUsd(e.value.costUsd),
                      style: GhinaType.moneyM,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TokenBreakdown extends StatelessWidget {
  const _TokenBreakdown({required this.t});

  final KillaUsageTotals t;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rows = [
      ('Input', t.inputTokens),
      ('Output', t.outputTokens),
      ('Cache baca', t.cacheReadTokens),
      ('Cache tulis', t.cacheCreationTokens),
    ];
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final (label, v) in rows)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label ',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                  TextSpan(
                    text: killaTokens(v),
                    style: GhinaType.caption
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days, required this.metric});

  final List<KillaUsageDay> days;
  final _Metric metric;

  double _v(KillaUsageDay d) => metric == _Metric.cost
      ? d.totals.costUsd
      : d.totals.totalTokens.toDouble();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final values = [for (final d in days) _v(d)];
    final maxV = values.fold<double>(0, math.max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final n = days.length;
    final swatch = metric == _Metric.cost ? killaSwatch : GhinaColors.orange;
    final axis = GhinaType.caption.copyWith(
      color: g.textSecondary,
      fontSize: 11,
    );
    String fmt(double v) =>
        metric == _Metric.cost ? killaUsd(v) : killaTokens(v.round());
    return SizedBox(
      height: 200,
      child: BarChart(
        duration: GhinaMotion.slow,
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 3,
            getDrawingHorizontalLine: (v) => FlLine(
              color: g.border,
              strokeWidth: 1.5,
              dashArray: const [6, 6],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: top / 3,
                getTitlesWidget: (v, meta) {
                  if (v == meta.max) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(fmt(v), style: axis),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= n) return const SizedBox.shrink();
                  final step = n > 14 ? 7 : (n > 7 ? 3 : 1);
                  if ((n - 1 - i) % step != 0) return const SizedBox.shrink();
                  final d = days[i].date;
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(
                      d.length >= 10 ? '${int.parse(d.substring(8, 10))}' : d,
                      style: axis,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) =>
                  g.isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.ink,
              tooltipBorderRadius: GhinaRadii.rMd,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${days[group.x].date}\n${fmt(rod.toY)}',
                GhinaType.caption.w(800).copyWith(color: Colors.white),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: swatch.base,
                    width: n > 20 ? 6 : 10,
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
