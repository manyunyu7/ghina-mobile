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
import 'analytics_page.dart' show SpendItemTile;

/// One category drilled in: trend, pattern, frequent notes and its
/// transactions, for the Analitik page's period and filters.
class CategoryAnalyticsPage extends ConsumerStatefulWidget {
  const CategoryAnalyticsPage({super.key, required this.categoryKey});

  /// A category id, `__none` (Tanpa kategori) or `__transfer`.
  final String categoryKey;

  @override
  ConsumerState<CategoryAnalyticsPage> createState() =>
      _CategoryAnalyticsPageState();
}

class _CategoryAnalyticsPageState extends ConsumerState<CategoryAnalyticsPage> {
  CategoryAnalytics? _last;
  int _shown = 30;

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(categoryAnalyticsProvider(widget.categoryKey));
    if (v.hasValue) _last = v.value;
    final c = _last;
    final currency = ref.watch(currencyProvider);
    final compare = ref.watch(analyticsQueryProvider.select((q) => q.compare));
    final g = context.ghina;
    return Scaffold(
      appBar: AppBar(title: Text(c?.info.name ?? 'Kategori')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
          children: [
            const AnalyticsFilterBar(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
              child: c == null
                  ? (v.hasError
                        ? ErrorRetry(
                            onRetry: () => ref.invalidate(
                              categoryAnalyticsProvider(widget.categoryKey),
                            ),
                          )
                        : const Column(
                            children: [
                              Skeleton(height: 140, radius: GhinaRadii.xl),
                              SizedBox(height: 12),
                              Skeleton(height: 240, radius: GhinaRadii.xl),
                            ],
                          ))
                  : c.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        title: 'Belum ada pengeluaran ${c.info.name}',
                        message:
                            'Nggak ada transaksi kategori ini di "${c.period.label}". Coba periode lain, yuk.',
                        actionLabel: 'Kembali',
                        onAction: () => context.pop(),
                      ),
                    )
                  : _body(context, c, currency, compare, g),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CategoryAnalytics c,
    String currency,
    bool compare,
    GhinaTokens g,
  ) {
    final color = CategoryColors.parse(c.info.color);
    final sw = CategoryColors.swatch(c.info.color);
    final wallets = {
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        w.id: w,
    };
    final peak = c.weekdays.reduce((x, y) => y.average > x.average ? y : x);
    final shown = c.items.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopIn(
          child: ChunkyCard(
            key: const ValueKey('category-hero'),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CategoryAvatar(
                  iconName: c.info.icon,
                  colorHex: c.info.color,
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.period.label} · ${rangeLabel(c.period)}',
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MoneyText(
                          amount: c.total,
                          currency: currency,
                          tone: MoneyTone.neutral,
                          style: GhinaType.moneyL,
                          countUp: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ChunkyPill(
                            label:
                                '${pctLabel(c.share, signed: false)} dari total',
                            color: sw,
                            soft: true,
                            uppercase: false,
                          ),
                          if (c.deltaPct != null) DeltaPill(pct: c.deltaPct!),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        KpiGrid(
          children: [
            KpiTile(
              label: 'Jumlah transaksi',
              icon: Icons.receipt_long_rounded,
              color: GhinaColors.blue,
              currency: currency,
              text: '${c.count}×',
            ),
            KpiTile(
              label: 'Rata-rata transaksi',
              icon: Icons.shopping_basket_rounded,
              color: GhinaColors.purple,
              currency: currency,
              amount: c.avgTicket,
            ),
            KpiTile(
              label: 'Paling besar',
              icon: Icons.local_fire_department_rounded,
              color: GhinaColors.red,
              currency: currency,
              amount: c.largest?.amount ?? 0,
              note: c.largest == null ? null : Fmt.date(c.largest!.date),
            ),
            KpiTile(
              label: 'Periode sebelumnya',
              icon: Icons.history_rounded,
              color: GhinaColors.gray,
              currency: currency,
              amount: c.previousTotal ?? 0,
              note: c.deltaPct == null
                  ? 'Belum ada pembanding'
                  : '${pctLabel(c.deltaPct!)} sekarang',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnalyticsCard(
          key: const ValueKey('category-trend'),
          title: 'Tren',
          subtitle: c.granularity.label,
          icon: Icons.show_chart_rounded,
          header: compare
              ? Wrap(
                  spacing: 14,
                  children: [
                    LegendDot(label: c.period.label, color: color),
                    LegendDot(
                      label: 'Sebelumnya',
                      color: g.textMuted,
                      dashed: true,
                    ),
                  ],
                )
              : null,
          child: SpendTrendChart(
            buckets: c.trend,
            granularity: c.granularity,
            currency: currency,
            color: color,
            height: 190,
            cutoff: ref.watch(clockProvider).now(),
          ),
        ),
        AnalyticsCard(
          key: const ValueKey('category-weekday'),
          title: 'Pola hari',
          subtitle: 'Rata-rata per hari · paling sering ${peak.name}',
          icon: Icons.view_week_rounded,
          child: PatternBarChart(
            values: [for (final w in c.weekdays) w.average],
            labels: [for (final w in c.weekdays) w.short],
            currency: currency,
            color: sw,
            tooltip: (i) {
              final w = c.weekdays[i];
              return (
                '${w.name} · ${w.count} transaksi',
                'Rata-rata ${aMoney(context, w.average, currency)}',
              );
            },
          ),
        ),
        AnalyticsCard(
          key: const ValueKey('category-notes'),
          title: 'Paling sering',
          subtitle: 'Dari catatan transaksi (tempat / merchant)',
          icon: Icons.storefront_rounded,
          child: c.notes.isEmpty
              ? const NoChartData(
                  'Belum ada catatan. Tulis nama tempat saat mencatat, biar kelihatan polanya.',
                )
              : Column(
                  children: [
                    for (final n in c.notes)
                      HBarRow(
                        leading: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: g.tint(sw),
                            borderRadius: GhinaRadii.rMd,
                          ),
                          child: Text(
                            '${n.count}×',
                            style: GhinaType.caption
                                .w(900)
                                .copyWith(color: g.textPrimary),
                          ),
                        ),
                        title: n.note,
                        subtitle:
                            'Rata-rata ${aMoney(context, n.total / n.count, currency)}',
                        amount: n.total,
                        fraction:
                            n.total /
                            c.notes
                                .map((x) => x.total)
                                .reduce((a, b) => a > b ? a : b),
                        color: color,
                        currency: currency,
                      ),
                  ],
                ),
        ),
        AnalyticsCard(
          key: const ValueKey('category-transactions'),
          title: 'Transaksi',
          subtitle: '${c.count} transaksi · terbaru dulu',
          icon: Icons.receipt_long_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < shown.length; i++)
                SpendItemTile(
                  item: shown[i],
                  info: c.info,
                  wallets: wallets,
                  currency: currency,
                  dividerColor: g.border,
                  showDivider: i < shown.length - 1,
                ),
              if (c.items.length > shown.length) ...[
                const SizedBox(height: 10),
                ChunkyButton(
                  label: 'Tampilkan lagi',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.medium,
                  onPressed: () => setState(() => _shown += 30),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
