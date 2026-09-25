import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/analytics_spending.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/analytics_controller.dart';
import 'analytics_common.dart';

/// Period chips (scrolling row) + wallet / transfer / compare chips.
class AnalyticsFilterBar extends ConsumerWidget {
  const AnalyticsFilterBar({super.key, this.showToggles = true});

  final bool showToggles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(analyticsQueryProvider);
    final period = ref.watch(analyticsPeriodProvider);
    final ctl = ref.read(analyticsQueryProvider.notifier);
    final wallets = ref.watch(watchWalletsProvider).value ?? const <Wallet>[];
    Widget chip(
      String label,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
      Key? key,
      ChunkySwatch color = GhinaColors.blue,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChunkyChip(
        key: key,
        label: label,
        selected: selected,
        onTap: onTap,
        icon: icon,
        color: color,
      ),
    );

    final walletLabel = q.walletIds.isEmpty
        ? 'Semua dompet'
        : q.walletIds.length == 1
        ? (wallets.where((w) => w.id == q.walletIds.first).firstOrNull?.name ??
              '1 dompet')
        : '${q.walletIds.length} dompet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: GhinaSpace.page,
            vertical: 4,
          ),
          child: Row(
            children: [
              for (final p in AnalyticsPreset.values)
                if (p != AnalyticsPreset.custom)
                  chip(
                    p.label,
                    q.preset == p,
                    () => ctl.setPreset(p),
                    key: ValueKey('preset-${p.name}'),
                  ),
              chip(
                q.preset == AnalyticsPreset.custom
                    ? rangeLabel(period)
                    : 'Pilih tanggal',
                q.preset == AnalyticsPreset.custom,
                () => _pickRange(context, ref, period),
                icon: Icons.date_range_rounded,
                key: const ValueKey('preset-custom'),
              ),
            ],
          ),
        ),
        if (showToggles)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              6,
              GhinaSpace.page,
              4,
            ),
            child: Row(
              children: [
                chip(
                  walletLabel,
                  q.walletIds.isNotEmpty,
                  () => _pickWallets(context, ref, wallets),
                  icon: Icons.account_balance_wallet_rounded,
                  key: const ValueKey('filter-wallets'),
                  color: GhinaColors.purple,
                ),
                chip(
                  'Termasuk transfer',
                  q.includeTransfers,
                  ctl.toggleTransfers,
                  icon: q.includeTransfers
                      ? Icons.check_rounded
                      : Icons.swap_horiz_rounded,
                  key: const ValueKey('filter-transfers'),
                  color: GhinaColors.purple,
                ),
                chip(
                  'Bandingkan',
                  q.compare,
                  ctl.toggleCompare,
                  icon: q.compare
                      ? Icons.check_rounded
                      : Icons.compare_arrows_rounded,
                  key: const ValueKey('filter-compare'),
                  color: GhinaColors.purple,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    AnalyticsPeriod current,
  ) async {
    final today = ref.read(clockProvider).now();
    var from = current.start;
    var to = current.end;
    final r = await showChunkyBottomSheet<(DateTime, DateTime)>(
      context,
      title: 'Pilih rentang tanggal',
      showClose: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DateField(
              label: 'Dari',
              value: from,
              today: today,
              onChanged: (d) => set(() => from = d),
            ),
            const SizedBox(height: 12),
            DateField(
              label: 'Sampai',
              value: to,
              today: today,
              onChanged: (d) => set(() => to = d),
            ),
            const SizedBox(height: 20),
            ChunkyButton(
              key: const ValueKey('range-apply'),
              label: 'Terapkan',
              size: ChunkyButtonSize.large,
              onPressed: () => Navigator.of(c).pop((from, to)),
            ),
          ],
        ),
      ),
    );
    if (r != null) {
      ref.read(analyticsQueryProvider.notifier).setCustom(r.$1, r.$2);
    }
  }

  Future<void> _pickWallets(
    BuildContext context,
    WidgetRef ref,
    List<Wallet> wallets,
  ) async {
    var sel = {...ref.read(analyticsQueryProvider).walletIds};
    final r = await showChunkyBottomSheet<Set<String>>(
      context,
      title: 'Pilih dompet',
      showClose: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final g = c.ghina;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kosongkan pilihan untuk melihat semua dompet.',
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 12),
              if (wallets.isEmpty)
                const NoChartData('Belum ada dompet.')
              else
                ChunkyChoiceChips<String>(
                  multi: true,
                  allowEmpty: true,
                  options: [
                    for (final w in wallets)
                      ChunkyChoice(
                        value: w.id,
                        label: w.name,
                        icon: walletIcon(w),
                        color: GhinaColors.purple,
                      ),
                  ],
                  selected: sel,
                  onChanged: (s) => set(() => sel = s),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: 'Semua',
                      variant: ChunkyButtonVariant.outline,
                      onPressed: () => Navigator.of(c).pop(<String>{}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChunkyButton(
                      key: const ValueKey('wallets-apply'),
                      label: 'Terapkan',
                      onPressed: () => Navigator.of(c).pop(sel),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (r != null) ref.read(analyticsQueryProvider.notifier).setWallets(r);
  }
}
