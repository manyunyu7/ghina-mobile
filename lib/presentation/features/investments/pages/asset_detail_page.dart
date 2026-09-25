import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../investment_format.dart';
import '../widgets/invest_fields.dart';
import '../widgets/portfolio_widgets.dart';
import '../widgets/trade_row.dart';
import 'portfolio_page.dart' show refreshPortfolioPrices;

/// One asset: quote header, position & P/L breakdown, buy/sell shortcuts,
/// dividends and the trade history (edit / delete).
class AssetDetailPage extends ConsumerStatefulWidget {
  const AssetDetailPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends ConsumerState<AssetDetailPage> {
  bool _deleting = false;

  void _trade(TradeType type) =>
      context.push('/investments/${widget.id}/trade?type=${type.wire}');

  Future<void> _archive(Asset a) async {
    final r = await ref.read(setAssetArchivedProvider)(a.id, !a.archived);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          a.archived ? '${a.symbol} aktif lagi 🎉' : '${a.symbol} diarsipkan',
          icon: a.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
        );
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _deleteAsset(AssetDetail d) async {
    final linked = d.trades.where((t) => t.transaction != null).length;
    final choice = await showChunkyDialog<String>(
      context,
      builder: (c) => ChunkyDialog(
        title: 'Hapus ${d.asset.symbol}?',
        mood: MascotMood.sad,
        message: [
          if (d.trades.isEmpty)
            'Aset ini dihapus permanen.'
          else
            'Semua ${d.trades.length} transaksi aset ini ikut terhapus permanen.',
          if (linked > 0)
            '$linked transaksi kasnya juga dihapus, jadi saldo dompet balik seperti sebelum dicatat.',
          'Kalau cuma mau disembunyikan, arsipkan saja.',
        ].join(' '),
        actions: [
          ChunkyButton(
            key: const ValueKey('asset-delete-confirm'),
            label: 'Hapus permanen',
            variant: ChunkyButtonVariant.danger,
            onPressed: () => Navigator.of(c).pop('delete'),
          ),
          if (!d.asset.archived)
            ChunkyButton(
              label: 'Arsipkan saja',
              variant: ChunkyButtonVariant.secondary,
              onPressed: () => Navigator.of(c).pop('archive'),
            ),
          ChunkyButton(
            label: 'Batal',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'archive') return _archive(d.asset);
    if (choice != 'delete') return;
    setState(() => _deleting = true);
    final r = await ref.read(deleteAssetProvider)(d.asset.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(
          context,
          '${d.asset.symbol} dihapus',
          icon: Icons.delete_rounded,
        );
        popOr(context, '/investments');
      case Err(:final failure):
        setState(() => _deleting = false);
        showFailureToast(context, failure);
    }
  }

  Future<void> _tradeActions(AssetDetail d, TradeView v, String? wallet) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: tradeTitle(v.trade, d.asset),
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyButton(
            label: 'Edit',
            icon: Icons.edit_rounded,
            variant: ChunkyButtonVariant.secondary,
            onPressed: () => Navigator.of(c).pop('edit'),
          ),
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            key: const ValueKey('trade-delete'),
            label: 'Hapus',
            icon: Icons.delete_rounded,
            variant: ChunkyButtonVariant.danger,
            onPressed: () => Navigator.of(c).pop('delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        context.push('/investments/${d.asset.id}/trade/${v.id}');
      case 'delete':
        await confirmDeleteTrade(context, ref, d, v, walletName: wallet);
    }
  }

  Future<void> _updatePrice(Asset a) async {
    final ctrl = TextEditingController(
      text: numberToInput(a.manualPrice, decimals: 4),
    );
    final price = await showChunkyBottomSheet<double>(
      context,
      title: 'Perbarui harga ${a.symbol}',
      builder: (c) {
        String? error;
        return StatefulBuilder(
          builder: (c, set) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NumberField(
                key: const ValueKey('manual-price'),
                controller: ctrl,
                label: 'Harga per ${a.unit}',
                decimals: 4,
                prefix: GhinaMoney.symbolFor(a.currency),
                errorText: error,
                autofocus: true,
                helperText: 'Dicatat per hari ini.',
              ),
              const SizedBox(height: GhinaSpace.lg),
              ChunkyButton(
                key: const ValueKey('manual-price-save'),
                label: 'Simpan harga',
                color: GhinaColors.purple,
                onPressed: () {
                  final v = parseNumber(ctrl.text);
                  if (v == null || v < 0) {
                    set(() => error = 'Angkanya belum pas');
                    return;
                  }
                  Navigator.of(c).pop(v);
                },
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (price == null || !mounted) return;
    final r = await ref.read(updateManualPriceProvider)(a.id, price);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Harga ${a.symbol} diperbarui 👍');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchAssetDetailProvider(widget.id));
    final d = async.value;
    final title = d?.asset.symbol ?? 'Aset';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          const MoneyVisibilityToggle(key: ValueKey('asset-privacy')),
          if (d != null && !_deleting) ...[
            IconButton(
              key: const ValueKey('asset-edit'),
              tooltip: 'Edit aset',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.push('/investments/${d.asset.id}/edit'),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('asset-menu'),
              tooltip: 'Lainnya',
              onSelected: (v) =>
                  v == 'archive' ? _archive(d.asset) : _deleteAsset(d),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(d.asset.archived ? 'Aktifkan lagi' : 'Arsipkan'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Hapus aset')),
              ],
            ),
          ],
        ],
      ),
      body: switch (async) {
        _ when _deleting => const LoadingListView(),
        AsyncData(value: null) => const Center(
          child: EmptyState(
            mood: MascotMood.thinking,
            title: 'Asetnya nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
          ),
        ),
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => refreshPortfolioPrices(context, ref),
          child: _body(value),
        ),
        AsyncError() when d == null => ScrollableFill(
          child: ErrorRetry(
            onRetry: () => ref.invalidate(watchAssetDetailProvider(widget.id)),
          ),
        ),
        _ => const LoadingListView(),
      },
    );
  }

  Widget _body(AssetDetail d) {
    final g = context.ghina;
    final a = d.asset;
    final h = d.holding;
    final now = ref.watch(clockProvider).now();
    final wallets = {
      for (final w
          in ref.watch(watchAllWalletsProvider).value ?? const <Wallet>[])
        w.id: w,
    };
    final dividends = d.dividends.toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        if (a.archived) ...[
          ChunkyCard(
            tinted: GhinaColors.gray,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.archive_rounded, color: g.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Diarsipkan — nggak dihitung di kekayaan bersih.',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          GhinaSpace.gapMd,
        ],
        _QuoteHeader(
          detail: d,
          now: now,
          onUpdatePrice: a.isManual ? () => _updatePrice(a) : null,
        ),
        GhinaSpace.gapMd,
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('asset-buy'),
                label: 'Beli',
                icon: Icons.add_shopping_cart_rounded,
                color: GhinaColors.blue,
                size: ChunkyButtonSize.medium,
                expand: true,
                onPressed: () => _trade(TradeType.buy),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('asset-sell'),
                label: 'Jual',
                icon: Icons.sell_rounded,
                color: GhinaColors.orange,
                size: ChunkyButtonSize.medium,
                expand: true,
                onPressed: h.isOpen ? () => _trade(TradeType.sell) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ChunkyButton(
          key: const ValueKey('asset-other'),
          label: 'Dividen · split · biaya',
          icon: Icons.more_horiz_rounded,
          variant: ChunkyButtonVariant.outline,
          size: ChunkyButtonSize.medium,
          expand: true,
          onPressed: () => _trade(TradeType.dividend),
        ),
        for (final issue in h.issues) ...[
          GhinaSpace.gapMd,
          ChunkyCard(
            tinted: GhinaColors.red,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: GhinaColors.red.base),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${issue.sequenceError}. Cek lagi transaksi jualnya, ya.',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
        GhinaSpace.gapXl,
        const SectionHeader(title: 'Posisi'),
        _PositionCard(view: d.view),
        if (dividends.isNotEmpty) ...[
          GhinaSpace.gapXl,
          SectionHeader(
            title: 'Dividen',
            subtitle: '${dividends.length}× diterima',
          ),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: InfoRow(
                    label: 'Total dividen',
                    emphasis: true,
                    value: MoneyText(
                      key: const ValueKey('dividend-total'),
                      amount: h.dividends,
                      currency: a.currency,
                      tone: MoneyTone.income,
                      style: GhinaType.moneyM,
                    ),
                  ),
                ),
                for (final v in dividends.take(5))
                  TradeRow(
                    view: v,
                    asset: a,
                    walletName: wallets[v.transaction?.walletId]?.name,
                    onTap: () =>
                        context.push('/investments/${a.id}/trade/${v.id}'),
                  ),
              ],
            ),
          ),
        ],
        GhinaSpace.gapXl,
        SectionHeader(
          title: 'Riwayat transaksi',
          subtitle: d.trades.isEmpty ? null : 'Tahan untuk edit / hapus',
        ),
        if (d.trades.isEmpty)
          ChunkyCard(
            child: EmptyState(
              compact: true,
              mascotSize: 90,
              title: 'Belum ada transaksi',
              message:
                  'Catat pembelian pertamamu biar kepemilikannya kehitung.',
              actionLabel: 'Catat beli',
              onAction: () => _trade(TradeType.buy),
            ),
          )
        else
          ChunkyCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final v in d.trades)
                  TradeRow(
                    view: v,
                    asset: a,
                    walletName: wallets[v.transaction?.walletId]?.name,
                    onTap: () =>
                        context.push('/investments/${a.id}/trade/${v.id}'),
                    onLongPress: () => _tradeActions(
                      d,
                      v,
                      wallets[v.transaction?.walletId]?.name,
                    ),
                  ),
              ],
            ),
          ),
        if (a.walletId != null && wallets[a.walletId] != null) ...[
          GhinaSpace.gapLg,
          Center(
            child: Text(
              'Dompet: ${wallets[a.walletId]!.name}',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// Confirms and deletes a trade, spelling out the cash reversal. Returns true
/// when deleted.
Future<bool> confirmDeleteTrade(
  BuildContext context,
  WidgetRef ref,
  AssetDetail d,
  TradeView v, {
  String? walletName,
}) async {
  final t = v.trade;
  final effect = tradeCashEffect(t);
  final current = [for (final x in d.trades) x.trade];
  final seqError = tradeChangeError(current, t.id, null);
  final cash = v.transaction;
  final parts = <String>[
    '${tradeTitle(t, d.asset)} (${Fmt.date(t.date)}) dihapus permanen.',
    if (cash != null && effect != null)
      'Transaksi kasnya di ${walletName ?? 'dompet'} '
          '(${context.money(effect.amount, currency: d.asset.currency, showSign: true)}) '
          'ikut dihapus, jadi saldonya balik lagi.',
    if (seqError != null)
      'Perhatian: tanpa transaksi ini, $seqError — kepemilikan akan dihitung 0.',
  ];
  final ok = await showChunkyConfirm(
    context,
    title: 'Hapus transaksi ini?',
    message: parts.join(' '),
    confirmLabel: 'Hapus',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final r = await ref.read(deleteTradeProvider)(t.id);
  if (!context.mounted) return false;
  switch (r) {
    case Ok():
      showOkToast(
        context,
        cash != null
            ? 'Dihapus, saldo dompet dikembalikan'
            : 'Transaksi dihapus',
        icon: Icons.delete_rounded,
      );
      return true;
    case Err(:final failure):
      showFailureToast(context, failure);
      return false;
  }
}

class _QuoteHeader extends StatelessWidget {
  const _QuoteHeader({
    required this.detail,
    required this.now,
    this.onUpdatePrice,
  });

  final AssetDetail detail;
  final DateTime now;
  final VoidCallback? onUpdatePrice;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = detail.asset;
    final q = detail.view.quote;
    final price = q.price;
    final p = detail.price;
    final change = q.isManual ? null : p?.change;
    final pct = q.isManual ? null : detail.view.dayChangePct ?? p?.changePct;
    final sw = kindSwatch(a.kind);
    return ChunkyCard(
      tinted: sw,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AssetAvatar(asset: a, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name == null || a.name!.isEmpty ? a.symbol : a.name!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    Text(
                      '${a.kind.label} · ${a.symbol}',
                      style: GhinaType.caption
                          .w(800)
                          .copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    price == null
                        ? 'Belum ada harga'
                        : fmtPrice(price, currency: a.currency),
                    key: const ValueKey('asset-price'),
                    style: price == null
                        ? GhinaType.h2.copyWith(color: g.textMuted)
                        : GhinaType.moneyL.copyWith(color: g.textPrimary),
                  ),
                ),
              ),
              if (price != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/${a.unit}',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          if (pct != null)
            Row(
              children: [
                if (change != null)
                  Text(
                    '${change >= 0 ? '+' : '-'}${fmtPrice(change.abs(), currency: a.currency)} ',
                    style: GhinaType.bodyS
                        .w(900)
                        .copyWith(color: plColor(context, change)),
                  ),
                ChangeText(pct: pct, style: GhinaType.bodyS.w(900), prefix: ''),
                Text(
                  ' hari ini',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                q.isManual
                    ? (q.asOf == null
                          ? 'Harga manual'
                          : 'Harga manual per ${Fmt.date(q.asOf!)}')
                    : q.updatedAt == null
                    ? 'Tarik ke bawah buat ambil harga pasar'
                    : 'Terakhir diperbarui ${fmtWhen(q.updatedAt!, now)}',
                style: GhinaType.caption
                    .w(700)
                    .copyWith(color: g.textSecondary),
              ),
              if (q.stale && !q.isManual) const StaleBadge(),
            ],
          ),
          if (onUpdatePrice != null) ...[
            const SizedBox(height: 12),
            ChunkyButton(
              key: const ValueKey('asset-update-price'),
              label: 'Perbarui harga',
              icon: Icons.edit_rounded,
              size: ChunkyButtonSize.small,
              color: GhinaColors.purple,
              onPressed: onUpdatePrice,
            ),
          ],
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.view});

  final HoldingView view;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = view.asset;
    final h = view.holding;
    final cur = a.currency;
    final q = qtyLabel(a, h.shares);
    Widget money(double? v) => v == null
        ? Text('–', style: GhinaType.moneyS.copyWith(color: g.textMuted))
        : MoneyText(
            amount: v,
            currency: cur,
            tone: MoneyTone.neutral,
            style: GhinaType.moneyS.copyWith(fontSize: 15),
          );
    return MoneyPeek(
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            InfoRow(
              label: 'Jumlah',
              hint: q.sub,
              value: Text(
                h.isOpen ? q.main : '0 ${a.kind.usesLots ? 'lot' : a.unit}',
                key: const ValueKey('position-qty'),
                style: GhinaType.moneyS.copyWith(
                  fontSize: 15,
                  color: g.textPrimary,
                ),
              ),
            ),
            InfoRow(label: 'Harga rata-rata', value: money(h.avgPrice)),
            InfoRow(label: 'Modal', value: money(h.cost)),
            InfoRow(
              label: 'Nilai pasar',
              hint: view.unpriced ? 'belum ada harga' : null,
              value: money(view.marketValue),
            ),
            InfoRow(
              label: 'Belum terealisasi',
              value: PlMoney(
                amount: view.unrealized,
                pct: view.unrealizedPct,
                currency: cur,
              ),
            ),
            if (!view.quote.isManual)
              InfoRow(
                label: 'Hari ini',
                value: PlMoney(amount: view.dayChange, currency: cur),
              ),
            Divider(color: g.border, height: 16, thickness: 1.5),
            InfoRow(
              label: 'Terealisasi',
              value: PlMoney(
                key: const ValueKey('position-realized'),
                amount: h.realized,
                currency: cur,
              ),
            ),
            InfoRow(
              label: 'Dividen',
              value: MoneyText(
                amount: h.dividends,
                currency: cur,
                tone: h.dividends > 0 ? MoneyTone.income : MoneyTone.neutral,
                style: GhinaType.moneyS.copyWith(fontSize: 15),
              ),
            ),
            InfoRow(label: 'Total biaya', value: money(h.fees)),
            Divider(color: g.border, height: 16, thickness: 1.5),
            InfoRow(
              label: 'Total untung/rugi',
              emphasis: true,
              value: PlMoney(
                amount: view.totalReturn,
                currency: cur,
                style: GhinaType.moneyM,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
