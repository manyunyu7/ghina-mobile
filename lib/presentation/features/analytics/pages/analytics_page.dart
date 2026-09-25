import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/analytics_spending.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/analytics_common.dart';
import '../widgets/analytics_filters.dart';

/// Route of a category drill-down (`__none` / `__transfer` included).
String analyticsCategoryRoute(String key) =>
    '/analytics/category/${Uri.encodeComponent(key)}';

/// "Analitik Pengeluaran": KPIs, category donut, trend, calendar heatmap,
/// weekday/hour patterns, budgets, wallets, income vs expense and the
/// largest expenses for a chosen period.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  SpendingAnalytics? _last;

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(spendingAnalyticsProvider);
    if (v.hasValue) _last = v.value;
    final a = _last;
    final refreshing = v.isLoading && a != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Analitik Pengeluaran')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          key: const ValueKey('analytics-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
          children: [
            const AnalyticsFilterBar(),
            SizedBox(
              height: 12,
              child: refreshing
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: LinearProgressIndicator(minHeight: 3),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
              child: a == null
                  ? (v.hasError
                        ? ErrorRetry(
                            onRetry: () =>
                                ref.invalidate(spendingAnalyticsProvider),
                          )
                        : const _LoadingBody())
                  : !a.hasData
                  ? Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        title: 'Belum ada pengeluaran di periode ini',
                        message:
                            'Nggak ada transaksi di "${a.period.label}". Coba periode lain, atau catat pengeluaran dulu, yuk.',
                        actionLabel: 'Catat transaksi',
                        onAction: () => context.push('/transactions/new'),
                      ),
                    )
                  : _AnalyticsBody(a: a),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) => const Column(
    key: ValueKey('analytics-loading'),
    children: [
      Skeleton(height: 150, radius: GhinaRadii.xl),
      SizedBox(height: 12),
      Skeleton(height: 90, radius: GhinaRadii.lg),
      SizedBox(height: 12),
      Skeleton(height: 280, radius: GhinaRadii.xl),
      SizedBox(height: 12),
      Skeleton(height: 240, radius: GhinaRadii.xl),
    ],
  );
}

class _AnalyticsBody extends ConsumerStatefulWidget {
  const _AnalyticsBody({required this.a});
  final SpendingAnalytics a;

  @override
  ConsumerState<_AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends ConsumerState<_AnalyticsBody> {
  bool _stacked = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final currency = ref.watch(currencyProvider);
    final now = ref.watch(clockProvider).now();
    final k = a.kpis;
    final hasSpend = a.hasSpending;
    final stackKeys = [for (final c in a.categories.take(5)) c.info];
    final peakDay = a.weekdays.reduce((x, y) => y.average > x.average ? y : x);
    final peakHour = a.hours.peakHour;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopIn(
          child: _Hero(a: a, currency: currency),
        ),
        const SizedBox(height: 12),
        KpiGrid(
          children: [
            KpiTile(
              label: 'Rata-rata harian',
              icon: Icons.today_rounded,
              color: GhinaColors.orange,
              currency: currency,
              amount: k.avgPerDay,
              note: '${k.elapsedDays} hari berjalan',
            ),
            KpiTile(
              label: 'Hari paling boros',
              icon: Icons.local_fire_department_rounded,
              color: GhinaColors.red,
              currency: currency,
              amount: k.biggestDay == null ? null : k.biggestDayAmount,
              text: k.biggestDay == null ? '–' : null,
              note: k.biggestDay == null
                  ? 'Belum ada'
                  : Fmt.dateShortWeekday(k.biggestDay!),
            ),
            KpiTile(
              label: 'Jumlah transaksi',
              icon: Icons.receipt_long_rounded,
              color: GhinaColors.blue,
              currency: currency,
              text: '${k.count}×',
              note: k.elapsedDays > 0
                  ? '${(k.count / k.elapsedDays).toStringAsFixed(1).replaceAll('.', ',')} per hari'
                  : null,
            ),
            KpiTile(
              label: 'Rata-rata transaksi',
              icon: Icons.shopping_basket_rounded,
              color: GhinaColors.purple,
              currency: currency,
              amount: k.avgPerTx,
            ),
            if (k.deltaPct != null)
              KpiTile(
                key: const ValueKey('kpi-delta'),
                label: 'vs ${a.previousPeriod.label.toLowerCase()}',
                icon: Icons.compare_arrows_rounded,
                color: GhinaColors.gray,
                currency: currency,
                amount: k.delta,
                tone: MoneyTone.auto,
                amountColor: k.delta! > 0
                    ? GhinaColors.red.base
                    : k.delta! < 0
                    ? GhinaColors.green.base
                    : null,
                note: k.deltaPct == null
                    ? 'Belum ada pembanding'
                    : '${pctLabel(k.deltaPct!)} dari ${aMoney(context, k.previousToDate!, currency, compact: true)}',
              ),
            if (k.projectedMonthEnd != null)
              KpiTile(
                key: const ValueKey('kpi-projection'),
                label: 'Proyeksi akhir bulan',
                icon: Icons.insights_rounded,
                color: GhinaColors.yellow,
                currency: currency,
                amount: k.projectedMonthEnd,
                note: 'Kalau temponya tetap',
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (hasSpend) _Insights(a: a, peakDay: peakDay, peakHour: peakHour),
        AnalyticsCard(
          key: const ValueKey('card-categories'),
          title: 'Per kategori',
          subtitle: hasSpend
              ? '${a.categories.length} kategori · ketuk untuk detail'
              : null,
          icon: Icons.donut_large_rounded,
          child: hasSpend
              ? SpendDonut(
                  rows: a.categories,
                  currency: currency,
                  onOpen: (key) => context.push(analyticsCategoryRoute(key)),
                )
              : const NoChartData('Belum ada pengeluaran di periode ini.'),
        ),
        AnalyticsCard(
          key: const ValueKey('card-trend'),
          title: 'Tren pengeluaran',
          subtitle: a.granularity.label,
          icon: Icons.show_chart_rounded,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChunkySegmented<bool>(
                height: 40,
                segments: const [
                  ChunkySegment(
                    value: false,
                    label: 'Total',
                    icon: Icons.show_chart_rounded,
                  ),
                  ChunkySegment(
                    value: true,
                    label: 'Per kategori',
                    icon: Icons.stacked_bar_chart_rounded,
                  ),
                ],
                value: _stacked,
                onChanged: (v) => setState(() => _stacked = v),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: _stacked
                    ? [
                        for (final c in stackKeys)
                          LegendDot(
                            label: c.name,
                            color: CategoryColors.parse(c.color),
                          ),
                        if (a.categories.length > stackKeys.length)
                          LegendDot(
                            label: 'Lainnya',
                            color: context.ghina.isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFFB8C2CF),
                          ),
                      ]
                    : [
                        LegendDot(
                          label: a.period.label,
                          color: GhinaColors.red.base,
                        ),
                        if (a.compare)
                          LegendDot(
                            label: a.previousPeriod.label,
                            color: context.ghina.textMuted,
                            dashed: true,
                          ),
                      ],
              ),
            ],
          ),
          child: SpendTrendChart(
            buckets: a.trend,
            granularity: a.granularity,
            currency: currency,
            stacked: _stacked,
            stackKeys: stackKeys,
            cutoff: now,
          ),
        ),
        AnalyticsCard(
          key: const ValueKey('card-heatmap'),
          title: 'Kalender pengeluaran',
          subtitle: 'Makin merah, makin boros. Ketuk tanggal.',
          icon: Icons.calendar_month_rounded,
          child: SpendHeatmap(
            period: a.period,
            daily: a.daily,
            currency: currency,
            now: now,
          ),
        ),
        AnalyticsCard(
          key: const ValueKey('card-weekday'),
          title: 'Pola hari',
          subtitle: hasSpend
              ? 'Rata-rata per hari · paling boros ${peakDay.name}'
              : 'Rata-rata per hari',
          icon: Icons.view_week_rounded,
          child: PatternBarChart(
            values: [for (final w in a.weekdays) w.average],
            labels: [for (final w in a.weekdays) w.short],
            currency: currency,
            tooltip: (i) {
              final w = a.weekdays[i];
              return (
                '${w.name} · ${w.count} transaksi',
                'Rata-rata ${aMoney(context, w.average, currency)}',
              );
            },
          ),
        ),
        AnalyticsCard(
          key: const ValueKey('card-hour'),
          title: 'Pola jam',
          subtitle: peakHour == null
              ? 'Dari jam transaksi dicatat'
              : 'Paling sering jam ${_hour(peakHour)}–${_hour((peakHour + 1) % 24)}',
          icon: Icons.schedule_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a.hours.hasData)
                PatternBarChart(
                  values: a.hours.totals,
                  labels: [
                    for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0'),
                  ],
                  maxLabels: 8,
                  currency: currency,
                  color: GhinaColors.orange,
                  tooltip: (h) => (
                    'Jam ${_hour(h)} · ${a.hours.counts[h]} transaksi',
                    aMoney(context, a.hours.totals[h], currency),
                  ),
                )
              else
                const NoChartData('Belum ada transaksi yang dicatat jamnya.'),
              if (a.hours.untimed > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${a.hours.untimed} transaksi tanpa jam tidak dihitung.',
                  style: GhinaType.caption.copyWith(
                    color: context.ghina.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        _BudgetCard(a: a, currency: currency),
        AnalyticsCard(
          key: const ValueKey('card-wallets'),
          title: 'Per dompet',
          subtitle: 'Dari dompet mana uangnya keluar',
          icon: Icons.account_balance_wallet_rounded,
          child: a.wallets.isEmpty
              ? const NoChartData('Belum ada pengeluaran.')
              : Column(
                  children: [
                    for (final w in a.wallets)
                      HBarRow(
                        leading: w.wallet != null
                            ? WalletAvatar(
                                wallet: w.wallet!,
                                size: 34,
                                soft: true,
                              )
                            : const CategoryAvatar(
                                iconName: 'wallet',
                                colorHex: '#94a3b8',
                                size: 34,
                                soft: true,
                              ),
                        title: w.name,
                        subtitle:
                            '${pctLabel(w.pct, signed: false)} · ${w.count} transaksi',
                        amount: w.total,
                        fraction: a.wallets.first.total > 0
                            ? w.total / a.wallets.first.total
                            : 0,
                        color: CategoryColors.parse(w.color),
                        currency: currency,
                      ),
                  ],
                ),
        ),
        _IncomeExpenseCard(a: a, currency: currency, now: now),
        _LargestCard(a: a, currency: currency),
      ],
    );
  }
}

String _hour(int h) => '${h.toString().padLeft(2, '0')}.00';

class _Hero extends StatelessWidget {
  const _Hero({required this.a, required this.currency});
  final SpendingAnalytics a;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final k = a.kpis;
    return ChunkyCard(
      key: const ValueKey('analytics-hero'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL PENGELUARAN',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '${a.period.label} · ${rangeLabel(a.period)}',
            style: GhinaType.bodyS.w(700).copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              key: const ValueKey('hero-total'),
              amount: k.total,
              currency: currency,
              tone: MoneyTone.neutral,
              style: GhinaType.moneyL,
              countUp: true,
            ),
          ),
          if (a.compare) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (k.deltaPct != null) DeltaPill(pct: k.deltaPct!),
                Text(
                  k.deltaPct == null
                      ? 'Belum ada data ${a.previousPeriod.label.toLowerCase()} untuk dibandingkan'
                      : k.previousToDate == k.previousTotal
                      ? 'vs ${a.previousPeriod.label.toLowerCase()}'
                      : 'vs ${k.elapsedDays} hari pertama ${a.previousPeriod.label.toLowerCase()}',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ],
          if (a.filter.walletIds.isNotEmpty || a.filter.includeTransfers) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (a.filter.walletIds.isNotEmpty)
                  '${a.filter.walletIds.length} dompet dipilih',
                if (a.filter.includeTransfers) 'termasuk transfer keluar',
              ].join(' · '),
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plain-language takeaways next to the mascot.
class _Insights extends StatelessWidget {
  const _Insights({
    required this.a,
    required this.peakDay,
    required this.peakHour,
  });

  final SpendingAnalytics a;
  final WeekdayStat peakDay;
  final int? peakHour;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final top = a.categories.first;
    final lines = <String>[
      '${top.name} paling banyak makan budget: ${pctLabel(top.pct, signed: false)} dari total.',
      if (peakDay.average > 0) 'Hari paling boros biasanya ${peakDay.name}.',
      if (peakHour != null) 'Jam rawan jajan: sekitar ${_hour(peakHour!)}.',
    ];
    if (a.compare) {
      CategorySpend? jump;
      for (final c in a.categories) {
        final d = c.total - c.previous;
        if (c.previous > 0 &&
            d > 0 &&
            (jump == null || d > jump.total - jump.previous)) {
          jump = c;
        }
      }
      if (jump != null) {
        lines.add(
          '${jump.name} naik ${pctLabel((jump.total - jump.previous) / jump.previous * 100)} dibanding sebelumnya.',
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
      child: ChunkyCard(
        key: const ValueKey('card-insights'),
        tinted: GhinaColors.blue,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MascotView(
              mood: MascotMood.thinking,
              size: 56,
              animate: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan Ghina',
                    style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  for (final l in lines.take(4))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '• $l',
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.a, required this.currency});
  final SpendingAnalytics a;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final now = ref.watch(clockProvider).now();
    final bm = ref.watch(analyticsBudgetProvider).value;
    final month = budgetMonthFor(a.period, now);
    final pace = monthPace(month, now);
    final items = [...?bm?.items]
      ..sort((x, y) {
        if (x.over != y.over) return x.over ? -1 : 1;
        return y.pct.compareTo(x.pct);
      });
    final running = pace > 0 && pace < 1;
    return AnalyticsCard(
      key: const ValueKey('card-budgets'),
      title: 'Anggaran vs realisasi',
      subtitle:
          '${Fmt.monthYear(month.start)}${running ? ' · hari ke-${now.day} dari ${month.end.day}' : ''}${a.filter.walletIds.isNotEmpty ? ' · semua dompet' : ''}',
      icon: Icons.savings_rounded,
      trailing: bm != null && bm.overCount > 0
          ? ChunkyPill(
              label: '${bm.overCount} lewat',
              color: GhinaColors.red,
              soft: true,
              icon: Icons.warning_amber_rounded,
            )
          : null,
      child: bm == null
          ? const Skeleton(height: 80)
          : items.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NoChartData('Belum ada anggaran untuk bulan ini.'),
                ChunkyButton(
                  label: 'Atur anggaran',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.medium,
                  onPressed: () => context.push('/budgets'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Terpakai ${pctLabel(bm.totalPct, signed: false)}',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoneyText(
                              amount: bm.totalSpent,
                              currency: currency,
                              tone: MoneyTone.neutral,
                              style: GhinaType.moneyS,
                            ),
                            Text(
                              ' / ',
                              style: GhinaType.caption.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                            MoneyText(
                              amount: bm.totalBudgeted,
                              currency: currency,
                              tone: MoneyTone.neutral,
                              style: GhinaType.moneyS,
                              color: g.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _PacedBar(used: bm.totalPct / 100, pace: running ? pace : null),
                const SizedBox(height: 16),
                for (final b in items)
                  _BudgetRow(
                    b: b,
                    currency: currency,
                    pace: running ? pace : null,
                  ),
                if (running)
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 12,
                        decoration: BoxDecoration(
                          color: g.textPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Garis = batas wajar sampai hari ini',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _PacedBar extends StatelessWidget {
  const _PacedBar({required this.used, this.pace, this.height = 12});
  final double used;
  final double? pace;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.none,
        children: [
          ChunkyProgressBar.budget(used: used, height: height),
          if (pace != null)
            Positioned(
              left: (box.maxWidth * pace!).clamp(2, box.maxWidth - 2) - 1.5,
              top: -3,
              bottom: -3,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: g.textPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.b, required this.currency, this.pace});
  final BudgetView b;
  final String currency;
  final double? pace;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = b.category;
    final ahead = !b.over && pace != null && b.pct / 100 > pace! + 0.1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: b.over ? const EdgeInsets.all(10) : EdgeInsets.zero,
      decoration: b.over
          ? BoxDecoration(
              color: g.tint(GhinaColors.red),
              borderRadius: GhinaRadii.rMd,
              border: Border.all(
                color: GhinaColors.red.tintBorder(g.brightness),
                width: 1.5,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(
                iconName: c?.icon ?? 'circle',
                colorHex: c?.color ?? CategoryTotal.uncategorizedColor,
                size: 32,
                soft: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c?.name ?? 'Kategori terhapus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pctLabel(b.pct, signed: false),
                style: GhinaType.caption
                    .w(900)
                    .copyWith(
                      color: b.over
                          ? GhinaColors.red.base
                          : ahead
                          ? GhinaColors.orange.base
                          : g.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PacedBar(used: b.pct / 100, pace: pace, height: 10),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MoneyText(
                        amount: b.spent,
                        currency: currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyS.copyWith(fontSize: 12),
                      ),
                      Text(
                        ' dari ',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                      MoneyText(
                        amount: b.budget.amount,
                        currency: currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyS.copyWith(fontSize: 12),
                        color: g.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        b.over ? 'Lewat ' : 'Sisa ',
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(
                              color: b.over
                                  ? GhinaColors.red.base
                                  : g.textMuted,
                            ),
                      ),
                      MoneyText(
                        amount: b.remaining.abs(),
                        currency: currency,
                        tone: MoneyTone.neutral,
                        style: GhinaType.moneyS.copyWith(fontSize: 12),
                        color: b.over ? GhinaColors.red.base : g.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  const _IncomeExpenseCard({
    required this.a,
    required this.currency,
    required this.now,
  });
  final SpendingAnalytics a;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final ie = a.incomeExpense;
    final rate = ie.savingsRate;
    final sw = rate == null
        ? GhinaColors.gray
        : rate >= 20
        ? GhinaColors.green
        : rate >= 0
        ? GhinaColors.orange
        : GhinaColors.red;
    Widget fig(String label, double v, MoneyTone tone) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              amount: v,
              currency: currency,
              tone: tone,
              style: GhinaType.moneyS.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
    return AnalyticsCard(
      key: const ValueKey('card-income'),
      title: 'Pemasukan vs pengeluaran',
      subtitle: 'Tanpa transfer & penyesuaian saldo',
      icon: Icons.bar_chart_rounded,
      trailing: ChunkyPill(
        label: rate == null
            ? 'Rasio –'
            : 'Nabung ${pctLabel(rate, signed: false)}',
        color: sw,
        soft: true,
        uppercase: false,
        icon: Icons.savings_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              fig('Pemasukan', ie.income, MoneyTone.income),
              const SizedBox(width: 8),
              fig('Pengeluaran', ie.expense, MoneyTone.expense),
              const SizedBox(width: 8),
              fig('Selisih', ie.net, MoneyTone.auto),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              LegendDot(label: 'Pemasukan', color: GhinaColors.green.base),
              LegendDot(label: 'Pengeluaran', color: GhinaColors.red.base),
            ],
          ),
          const SizedBox(height: 14),
          IncomeExpenseBars(
            buckets: a.flow,
            granularity: a.granularity,
            currency: currency,
          ),
          const SizedBox(height: 18),
          Text(
            'Arus kas kumulatif',
            style: GhinaType.bodyS.w(900).copyWith(color: g.textPrimary),
          ),
          Text(
            'Sisa uang berjalan sepanjang periode',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 10),
          CumulativeFlowLine(
            buckets: a.flow,
            granularity: a.granularity,
            currency: currency,
            cutoff: now,
          ),
        ],
      ),
    );
  }
}

class _LargestCard extends ConsumerWidget {
  const _LargestCard({required this.a, required this.currency});
  final SpendingAnalytics a;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final wallets = {
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        w.id: w,
    };
    final cats = {
      for (final c
          in ref.watch(watchCategoriesProvider(null)).value ??
              const <TxCategory>[])
        c.id: c,
    };
    return AnalyticsCard(
      key: const ValueKey('card-largest'),
      title: 'Pengeluaran terbesar',
      subtitle: 'Top ${math.min(10, a.largest.length)} di periode ini',
      icon: Icons.format_list_numbered_rounded,
      child: a.largest.isEmpty
          ? const NoChartData('Belum ada pengeluaran.')
          : Column(
              children: [
                for (var i = 0; i < a.largest.length; i++)
                  SpendItemTile(
                    key: ValueKey('largest-${a.largest[i].tx.id}'),
                    item: a.largest[i],
                    rank: i + 1,
                    info: categoryInfo(a.largest[i].key, cats),
                    wallets: wallets,
                    currency: currency,
                    dividerColor: g.border,
                    showDivider: i < a.largest.length - 1,
                  ),
              ],
            ),
    );
  }
}

/// One spending row (top list, drill-down list) → opens the transaction.
class SpendItemTile extends ConsumerWidget {
  const SpendItemTile({
    super.key,
    required this.item,
    required this.info,
    required this.wallets,
    required this.currency,
    required this.dividerColor,
    this.rank,
    this.showDivider = true,
  });

  final SpendItem item;
  final CategoryInfo info;
  final Map<String, Wallet> wallets;
  final String currency;
  final Color dividerColor;
  final int? rank;
  final bool showDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final t = item.tx;
    final now = ref.watch(clockProvider).now();
    final note = t.note?.trim();
    final title = note != null && note.isNotEmpty
        ? note
        : t.type == TxType.transfer
        ? 'Transfer ke ${wallets[t.toWalletId]?.name ?? 'dompet'}'
        : info.name;
    final sub = [
      if (title != info.name) info.name,
      Fmt.relativeDay(t.date, now: now),
      if (wallets[t.walletId] != null) wallets[t.walletId]!.name,
    ].join(' · ');
    return InkWell(
      onTap: () => context.push('/transactions/${t.id}'),
      borderRadius: GhinaRadii.rMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(bottom: BorderSide(color: dividerColor)),
              )
            : null,
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: GhinaType.caption.w(900).copyWith(color: g.textMuted),
                ),
              ),
            CategoryAvatar(
              iconName: info.icon,
              colorHex: info.color,
              size: 36,
              soft: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(
              amount: t.amount,
              currency: currency,
              tone: t.type == TxType.transfer
                  ? MoneyTone.transfer
                  : MoneyTone.expense,
              style: GhinaType.moneyS,
            ),
          ],
        ),
      ),
    );
  }
}
