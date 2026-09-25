import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../investment_format.dart';
import '../widgets/portfolio_charts.dart';
import '../widgets/portfolio_widgets.dart';

/// Pull-to-refresh of the portfolio screens: fetch fresh market prices (and
/// nudge a sync so pending trades go up). Offline keeps the cached prices.
Future<void> refreshPortfolioPrices(BuildContext context, WidgetRef ref) async {
  unawaited(ref.read(syncNowProvider)().then((_) {}, onError: (_) {}));
  final r = await ref.read(refreshPricesProvider)();
  if (!context.mounted) return;
  switch (r) {
    case Ok(:final value):
      if (value.notFound.isNotEmpty) {
        final codes = value.notFound.map((k) => k.split(':').last).join(', ');
        showToastBadge(
          context,
          message: 'Kode $codes nggak ketemu di data pasar',
          icon: Icons.search_off_rounded,
          color: GhinaColors.orange,
        );
      } else if (value.updated.isNotEmpty) {
        showOkToast(
          context,
          'Harga terbaru sudah masuk 📈',
          icon: Icons.trending_up_rounded,
        );
      }
    case Err(:final failure):
      showToastBadge(
        context,
        message: failure is NetworkFailure
            ? 'Lagi offline. Pakai harga terakhir dulu 👍'
            : 'Harga belum bisa diperbarui. Coba lagi nanti ya',
        icon: Icons.cloud_off_rounded,
        color: GhinaColors.blue,
      );
  }
}

/// Portofolio: value hero, P/L stats, holdings, allocation donut, value
/// history and archived assets.
class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  bool _showArchived = false;
  HistoryRange _range = HistoryRange.quarter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchPortfolioProvider);
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Investasi'),
        actions: [
          const MoneyVisibilityToggle(key: ValueKey('invest-privacy')),
          IconButton(
            key: const ValueKey('invest-add'),
            tooltip: 'Tambah aset',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/investments/new'),
          ),
        ],
      ),
      body: switch (async) {
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => refreshPortfolioPrices(context, ref),
          child: _body(value, currency),
        ),
        AsyncError() when async.value == null => ScrollableFill(
          child: ErrorRetry(
            onRetry: () => ref.invalidate(watchPortfolioProvider),
          ),
        ),
        _ => const LoadingListView(),
      },
    );
  }

  Widget _body(PortfolioSummary s, String currency) {
    final archived = [
      for (final a
          in ref.watch(watchAllAssetsProvider).value ?? const <Asset>[])
        if (a.archived) a,
    ];
    if (s.isEmpty && archived.isEmpty) {
      return ScrollableFill(
        child: EmptyState(
          mood: MascotMood.waving,
          title: 'Pantau investasimu di sini',
          message:
              'Catat saham, reksa dana, emas atau kripto. Nilainya ikut harga pasar, '
              'jadi kekayaan bersihmu selalu update 🌱',
          actionLabel: 'Tambah aset',
          onAction: () => context.push('/investments/new'),
        ),
      );
    }
    final now = ref.watch(clockProvider).now();
    final open = s.open.toList();
    final closed = [
      for (final h in s.holdings)
        if (!h.holding.isOpen) h,
    ];
    return ListView(
      key: const PageStorageKey('portfolio-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        PortfolioHero(summary: s, currency: currency, now: now),
        GhinaSpace.gapMd,
        PortfolioStats(summary: s, currency: currency),
        if (s.unpricedCount > 0) ...[
          GhinaSpace.gapMd,
          _Notice(
            icon: Icons.info_rounded,
            color: GhinaColors.blue,
            text:
                '${s.unpricedCount} aset belum punya harga, jadi dihitung pakai nilai modal dulu.',
          ),
        ],
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Aset kamu',
          subtitle: open.isEmpty ? null : '${open.length} dimiliki',
          actionLabel: 'Tambah',
          onAction: () => context.push('/investments/new'),
        ),
        if (open.isEmpty)
          ChunkyCard(
            child: EmptyState(
              compact: true,
              mascotSize: 90,
              title: 'Belum ada yang dimiliki',
              message: 'Catat pembelian pertamamu dari halaman aset.',
            ),
          ),
        for (var i = 0; i < open.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.md),
            child: PopIn(
              delay: Duration(milliseconds: 50 * (i < 6 ? i : 6)),
              fromScale: 0.96,
              slideY: 10,
              child: HoldingTile(
                view: open[i],
                onTap: () => context.push('/investments/${open[i].asset.id}'),
              ),
            ),
          ),
        if (closed.isNotEmpty) ...[
          GhinaSpace.gapSm,
          SectionHeader(
            title: 'Dipantau / sudah dijual',
            subtitle: 'Nggak ada kepemilikan saat ini',
          ),
          for (final h in closed)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: HoldingTile(
                view: h,
                onTap: () => context.push('/investments/${h.asset.id}'),
              ),
            ),
        ],
        if (open.isNotEmpty) ...[
          GhinaSpace.gapLg,
          const SectionHeader(title: 'Alokasi'),
          AllocationCard(summary: s, currency: currency),
        ],
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Riwayat nilai',
          trailing: ChunkyChoiceChips<HistoryRange>(
            options: [
              for (final r in HistoryRange.values)
                ChunkyChoice(
                  value: r,
                  label: r.label,
                  color: GhinaColors.purple,
                ),
            ],
            selected: {_range},
            onChanged: (v) {
              if (v.isNotEmpty) setState(() => _range = v.first);
            },
          ),
        ),
        _HistoryCard(range: _range, currency: currency, now: now),
        if (archived.isNotEmpty) ...[
          GhinaSpace.gapXl,
          SectionHeader(
            title: 'Diarsipkan (${archived.length})',
            subtitle: 'Nggak dihitung di kekayaan bersih',
            actionLabel: _showArchived ? 'Tutup' : 'Lihat',
            onAction: () => setState(() => _showArchived = !_showArchived),
          ),
          if (_showArchived)
            for (final a in archived)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                child: Opacity(
                  opacity: 0.75,
                  child: ChunkyTile(
                    key: ValueKey('archived-${a.id}'),
                    leading: AssetAvatar(asset: a, size: 40),
                    title: a.symbol,
                    subtitle: a.name ?? a.kind.label,
                    dense: true,
                    showChevron: true,
                    onTap: () => context.push('/investments/${a.id}'),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

/// Purple hero: portfolio value, today's change, prices as-of + stale badge.
class PortfolioHero extends StatelessWidget {
  const PortfolioHero({
    super.key,
    required this.summary,
    required this.currency,
    required this.now,
  });

  final PortfolioSummary summary;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final white = Colors.white.withValues(alpha: 0.88);
    final hasDay = s.dayChange.abs() >= 0.005;
    return MoneyPeek(
      child: ChunkyCard(
        color: GhinaColors.purple,
        depth: GhinaDepth.lg,
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 26,
              child: Row(
                children: [
                  Text(
                    'NILAI PORTOFOLIO',
                    style: GhinaType.overline.copyWith(color: white),
                  ),
                  const SizedBox(width: 2),
                  MoneyVisibilityToggle(color: white, size: 18),
                  const Spacer(),
                  const Icon(
                    Icons.trending_up_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                key: const ValueKey('portfolio-value'),
                amount: s.marketValue,
                currency: currency,
                tone: MoneyTone.neutral,
                color: Colors.white,
                countUp: true,
                style: GhinaType.moneyXL,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('portfolio-day'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: GhinaRadii.rPill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(plIcon(s.dayChange), color: Colors.white, size: 20),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          Text(
                            'Hari ini ',
                            style: GhinaType.bodyS
                                .w(800)
                                .copyWith(color: Colors.white),
                          ),
                          if (hasDay) ...[
                            MoneyText(
                              amount: s.dayChange,
                              currency: currency,
                              tone: MoneyTone.auto,
                              color: Colors.white,
                              style: GhinaType.moneyS,
                            ),
                            if (s.dayChangePct != null)
                              Text(
                                ' (${fmtPct(s.dayChangePct)})',
                                style: GhinaType.bodyS
                                    .w(900)
                                    .copyWith(color: Colors.white),
                              ),
                          ] else
                            Text(
                              'belum ada perubahan',
                              style: GhinaType.bodyS
                                  .w(700)
                                  .copyWith(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  pricesAsOfLabel(s.pricesAsOf, now),
                  style: GhinaType.caption.w(700).copyWith(color: white),
                ),
                if (s.stale) const StaleBadge(onColor: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 2×2 stat grid (modal, unrealized, realized, dividends) + total return.
class PortfolioStats extends StatelessWidget {
  const PortfolioStats({
    super.key,
    required this.summary,
    required this.currency,
  });

  final PortfolioSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final g = context.ghina;
    Widget cell(String label, Widget value, {Key? key}) => Expanded(
      child: Container(
        key: key,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: value,
            ),
          ],
        ),
      ),
    );
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              cell(
                'Modal',
                MoneyText(
                  amount: s.cost,
                  currency: currency,
                  tone: MoneyTone.neutral,
                  style: GhinaType.moneyM,
                ),
              ),
              const SizedBox(width: 8),
              cell(
                'Belum terealisasi',
                PlMoney(
                  amount: s.unrealized,
                  pct: s.unrealizedPct,
                  currency: currency,
                  style: GhinaType.moneyM,
                ),
                key: const ValueKey('stat-unrealized'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              cell(
                'Terealisasi',
                PlMoney(
                  amount: s.realized,
                  currency: currency,
                  style: GhinaType.moneyM,
                ),
                key: const ValueKey('stat-realized'),
              ),
              const SizedBox(width: 8),
              cell(
                'Dividen',
                MoneyText(
                  amount: s.dividends,
                  currency: currency,
                  tone: s.dividends > 0 ? MoneyTone.income : MoneyTone.neutral,
                  style: GhinaType.moneyM,
                ),
                key: const ValueKey('stat-dividends'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: GhinaColors.yellow.base,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total untung/rugi',
                  style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: PlMoney(
                    key: const ValueKey('stat-total'),
                    amount: s.totalReturn,
                    currency: currency,
                    style: GhinaType.moneyM,
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

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({
    required this.range,
    required this.currency,
    required this.now,
  });

  final HistoryRange range;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final pts = ref.watch(watchPortfolioHistoryProvider(range.window(now)));
    final list = pts.value;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 10),
      child: list == null
          ? const Skeleton(height: 180, radius: 16)
          : list.length < 2
          ? Padding(
              key: const ValueKey('history-empty'),
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
              child: Row(
                children: [
                  const MascotView(
                    mood: MascotMood.thinking,
                    size: 64,
                    animate: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grafiknya lagi tumbuh 🌱',
                          style: GhinaType.body
                              .w(900)
                              .copyWith(color: g.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Nilai portofoliomu dicatat sekali sehari tiap kamu buka Ghina. '
                          'Besok titik keduanya muncul.',
                          style: GhinaType.bodyS.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 190,
                  child: ValueHistoryChart(points: list, currency: currency),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _legend(context, GhinaColors.green.base, 'Nilai'),
                    const SizedBox(width: 14),
                    _legend(context, g.textMuted, 'Modal'),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 4,
        decoration: BoxDecoration(
          color: c,
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final ChunkySwatch color;
  final String text;

  @override
  Widget build(BuildContext context) => ChunkyCard(
    tinted: color,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: color.base, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GhinaType.bodyS
                .w(700)
                .copyWith(color: context.ghina.textPrimary),
          ),
        ),
      ],
    ),
  );
}
