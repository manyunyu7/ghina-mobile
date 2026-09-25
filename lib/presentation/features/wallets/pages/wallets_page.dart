import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../../../shared/widgets/widgets.dart';
import '../../transactions/widgets/tx_visuals.dart';
import '../widgets/adjust_balance_sheet.dart';

/// All wallets: total balance hero, colored wallet cards, archived section and a
/// transfer shortcut.
class WalletsPage extends ConsumerStatefulWidget {
  const WalletsPage({super.key});

  @override
  ConsumerState<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends ConsumerState<WalletsPage> {
  bool _showArchived = false;

  void _transfer({String? fromId}) {
    ref
        .read(txFormPresetProvider.notifier)
        .set(TxFormPreset(type: TxType.transfer, walletId: fromId));
    context.push('/transactions/new');
  }

  Future<void> _setArchived(Wallet w, bool archived) async {
    final r = await ref.read(setWalletArchivedProvider)(w.id, archived);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          archived ? '${w.name} diarsipkan' : '${w.name} aktif lagi 🎉',
          icon: archived ? Icons.archive_rounded : Icons.unarchive_rounded,
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _actions(Wallet w, bool canTransfer) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: w.name,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyButton(
            label: 'Edit dompet',
            icon: Icons.edit_rounded,
            variant: ChunkyButtonVariant.secondary,
            onPressed: () => Navigator.of(c).pop('edit'),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Sesuaikan saldo',
            icon: Icons.tune_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () => Navigator.of(c).pop('adjust'),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: 'Riwayat',
            icon: Icons.history_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () => Navigator.of(c).pop('history'),
          ),
          if (canTransfer && !w.archived) ...[
            const SizedBox(height: GhinaSpace.sm),
            ChunkyButton(
              label: 'Transfer dari sini',
              icon: Icons.swap_horiz_rounded,
              variant: ChunkyButtonVariant.outline,
              onPressed: () => Navigator.of(c).pop('transfer'),
            ),
          ],
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            label: w.archived ? 'Aktifkan lagi' : 'Arsipkan',
            icon: w.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () => Navigator.of(c).pop('archive'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        context.push('/wallets/${w.id}');
      case 'adjust':
        await showAdjustBalanceSheet(context, ref, w);
      case 'history':
        context.push('/wallets/${w.id}/history');
      case 'transfer':
        _transfer(fromId: w.id);
      case 'archive':
        await _setArchived(w, !w.archived);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final async = ref.watch(watchAllWalletsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dompet'),
        actions: [
          const MoneyVisibilityToggle(key: ValueKey('wallet-privacy')),
          IconButton(
            key: const ValueKey('wallet-add'),
            tooltip: 'Tambah dompet',
            icon: const Icon(Icons.add_circle_rounded),
            color: GhinaColors.green.base,
            onPressed: () => context.push('/wallets/new'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncValue(:final value?) => _content(value, currency),
          AsyncValue(hasError: true) => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchAllWalletsProvider),
            ),
          ),
          _ => ListView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            children: const [
              Skeleton(height: 150, radius: GhinaRadii.xl),
              SizedBox(height: GhinaSpace.lg),
              SkeletonList(count: 3),
            ],
          ),
        },
      ),
    );
  }

  Widget _content(List<Wallet> all, String currency) {
    final active = all.where((w) => !w.archived).toList();
    final archived = all.where((w) => w.archived).toList();
    if (all.isEmpty) {
      return ScrollableFill(
        child: EmptyState(
          mood: MascotMood.waving,
          title: 'Belum ada dompet',
          message:
              'Dompet itu tempat uangmu: tunai, rekening, e-wallet. Tambah yang pertama, yuk!',
          actionLabel: 'Tambah dompet',
          onAction: () => context.push('/wallets/new'),
        ),
      );
    }
    final total = active.fold<double>(0, (s, w) => s + w.balance);
    final pending = active.where((w) => w.hasPendingChanges).length;
    // Portfolio value per investment wallet (RDN): "+ portofolio Rp X".
    final portfolio = ref.watch(watchPortfolioProvider).value;
    final byWallet = <String, double>{};
    for (final h in portfolio?.open ?? const <HoldingView>[]) {
      final id = h.asset.walletId;
      if (id != null) byWallet[id] = (byWallet[id] ?? 0) + h.value;
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.lg,
        GhinaSpace.page,
        GhinaSpace.xxxl,
      ),
      children: [
        _TotalHero(
          total: total,
          currency: currency,
          count: active.length,
          pending: pending,
          onTransfer: active.length >= 2 ? () => _transfer() : null,
        ),
        const SizedBox(height: GhinaSpace.md),
        PortfolioEntryTile(summary: portfolio, currency: currency),
        const SizedBox(height: GhinaSpace.xl),
        if (active.isEmpty)
          const EmptyState(
            compact: true,
            title: 'Semua dompet diarsipkan',
            message: 'Aktifkan lagi dari bagian arsip di bawah.',
          ),
        for (var i = 0; i < active.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.md),
            child: PopIn(
              delay: Duration(milliseconds: 50 * (i < 6 ? i : 6)),
              fromScale: 0.95,
              slideY: 10,
              child: WalletCard(
                wallet: active[i],
                portfolioValue: byWallet[active[i].id],
                onHistory: () =>
                    context.push('/wallets/${active[i].id}/history'),
                onTap: () => context.push('/wallets/${active[i].id}'),
                onLongPress: () => _actions(active[i], active.length >= 2),
              ),
            ),
          ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: GhinaSpace.md),
          SectionHeader(
            title: 'Diarsipkan (${archived.length})',
            subtitle: 'Nggak dihitung di total saldo',
            actionLabel: _showArchived ? 'Tutup' : 'Lihat',
            onAction: () => setState(() => _showArchived = !_showArchived),
          ),
          if (_showArchived)
            for (final w in archived)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                child: Opacity(
                  opacity: 0.75,
                  child: ChunkyTile(
                    key: ValueKey('archived-${w.id}'),
                    leading: WalletAvatar(wallet: w, size: 40),
                    title: w.name,
                    subtitle: w.type.label,
                    dense: true,
                    trailing: MoneyText(
                      amount: w.balance,
                      currency: w.currency,
                      tone: MoneyTone.neutral,
                    ),
                    onTap: () => context.push('/wallets/${w.id}'),
                    onLongPress: () => _actions(w, false),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _TotalHero extends StatelessWidget {
  const _TotalHero({
    required this.total,
    required this.currency,
    required this.count,
    required this.pending,
    required this.onTransfer,
  });

  final double total;
  final String currency;
  final int count;
  final int pending;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    const sw = GhinaColors.green;
    // Long-press the total to peek while balances are hidden.
    return MoneyPeek(
      child: ChunkyCard(
        color: sw,
        depth: GhinaDepth.lg,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'TOTAL SALDO',
                    style: GhinaType.overline.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                key: const ValueKey('wallet-total'),
                amount: total,
                currency: currency,
                tone: MoneyTone.neutral,
                color: Colors.white,
                countUp: true,
                style: GhinaType.moneyXL,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pending > 0
                  ? '$count dompet aktif · $pending belum tersinkron'
                  : '$count dompet aktif',
              style: GhinaType.bodyS
                  .w(800)
                  .copyWith(color: Colors.white.withValues(alpha: 0.9)),
            ),
            if (onTransfer != null) ...[
              const SizedBox(height: GhinaSpace.md),
              ChunkySurface(
                color: Colors.white,
                edgeColor: sw.edge,
                depth: GhinaDepth.sm,
                borderRadius: GhinaRadii.rMd,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                onTap: onTransfer,
                semanticLabel: 'Transfer antar dompet',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: sw.edge, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'TRANSFER',
                      style: GhinaType.button.copyWith(color: sw.edge),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A wallet as a chunky card in its own color.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.wallet,
    this.onTap,
    this.onLongPress,
    this.onHistory,
    this.portfolioValue,
  });

  final Wallet wallet;

  /// Value of the portfolio assets held in this wallet (RDN), shown as
  /// "+ portofolio Rp X" next to the cash balance.
  final double? portfolioValue;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Shows a "Riwayat" pill (the wallet's transaction history).
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final sw = CategoryColors.swatch(w.color);
    final on = sw.on;
    final soft = on.withValues(alpha: 0.85);
    return ChunkyCard(
      color: sw,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: w.name,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: on.withValues(alpha: 0.2),
                  borderRadius: GhinaRadii.rMd,
                ),
                child: Icon(walletIcon(w), color: on, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: on),
                    ),
                    Text(
                      '${w.type.label} · ${w.currency}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS.w(700).copyWith(color: soft),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: soft, size: 26),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    amount: w.balance,
                    currency: w.currency,
                    tone: MoneyTone.neutral,
                    color: on,
                    style: GhinaType.moneyL,
                  ),
                ),
              ),
              if (onHistory != null) ...[
                const SizedBox(width: 8),
                ChunkySurface(
                  key: ValueKey('wallet-history-${w.id}'),
                  color: on.withValues(alpha: 0.2),
                  edgeColor: sw.edge,
                  depth: GhinaDepth.sm,
                  borderRadius: GhinaRadii.rPill,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  onTap: onHistory,
                  semanticLabel: 'Riwayat ${w.name}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, color: on, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'RIWAYAT',
                        style: GhinaType.caption.w(900).copyWith(color: on),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (portfolioValue case final v? when v > 0) ...[
            const SizedBox(height: 6),
            Row(
              key: ValueKey('wallet-portfolio-${w.id}'),
              children: [
                Icon(Icons.trending_up_rounded, color: on, size: 18),
                const SizedBox(width: 6),
                Text(
                  '+ portofolio ',
                  style: GhinaType.bodyS.w(800).copyWith(color: soft),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MoneyText(
                      amount: v,
                      currency: w.currency,
                      tone: MoneyTone.neutral,
                      color: on,
                      style: GhinaType.moneyS,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (w.hasPendingChanges) ...[
            const SizedBox(height: 8),
            Container(
              key: ValueKey('pending-${w.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: on.withValues(alpha: 0.18),
                borderRadius: GhinaRadii.rPill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_upload_rounded, color: on, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Menunggu sinkron · di server ${context.money(w.syncedBalance, currency: w.currency)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(color: on),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Entry to the portfolio from the wallets page: value + today's change, or
/// an invitation to start.
class PortfolioEntryTile extends StatelessWidget {
  const PortfolioEntryTile({
    super.key,
    required this.summary,
    required this.currency,
  });

  final PortfolioSummary? summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = summary;
    final has = s != null && !s.isEmpty;
    final pct = s?.dayChangePct;
    return ChunkyCard(
      key: const ValueKey('wallets-portfolio'),
      tinted: GhinaColors.purple,
      onTap: () => context.push('/investments'),
      semanticLabel: 'Portofolio investasi',
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          CategoryAvatar(
            icon: Icons.trending_up_rounded,
            color: GhinaColors.purple.base,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portofolio investasi',
                  style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                ),
                if (has)
                  Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MoneyText(
                            amount: s.marketValue,
                            currency: currency,
                            tone: MoneyTone.neutral,
                            style: GhinaType.moneyS,
                          ),
                        ),
                      ),
                      if (pct != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${pct >= 0 ? '+' : '−'}${Fmt.number(pct.abs(), decimals: 2)}% hari ini',
                          style: GhinaType.caption
                              .w(900)
                              .copyWith(
                                color: pct >= 0
                                    ? GhinaColors.income.base
                                    : GhinaColors.expense.base,
                              ),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    'Saham, reksa dana, emas, kripto — pantau di sini',
                    maxLines: 2,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: g.textMuted, size: 28),
        ],
      ),
    );
  }
}
