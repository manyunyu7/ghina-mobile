import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../investment_format.dart';

/// `1:2` for a 2-for-1 split, `2:1` for a reverse split (ratio 0.5).
String splitLabel(double ratio) =>
    ratio >= 1 ? '1:${fmtQty(ratio)}' : '${fmtQty(1 / ratio)}:1';

/// Headline of a trade: `Beli 10 lot @ Rp 9.500`, `Dividen`, `Stock split 1:2`.
String tradeTitle(AssetTrade t, Asset a) {
  switch (t.type) {
    case TradeType.buy:
    case TradeType.sell:
      final q = t.quantity ?? 0;
      final qty = a.kind.usesLots && isWholeLots(q)
          ? '${fmtQty(sharesToLots(q))} lot'
          : '${fmtQty(q, maxFrac: 8)} ${a.unit}';
      return '${t.type.label} $qty @ ${fmtPrice(t.price ?? 0, currency: a.currency)}';
    case TradeType.split:
      return 'Stock split ${splitLabel(t.ratio ?? 1)}';
    case TradeType.dividend:
    case TradeType.fee:
      return t.type.label;
  }
}

/// Flat row of a trade in the asset's history.
class TradeRow extends StatelessWidget {
  const TradeRow({
    super.key,
    required this.view,
    required this.asset,
    this.walletName,
    this.onTap,
    this.onLongPress,
  });

  final TradeView view;
  final Asset asset;

  /// Wallet of the linked transaction (null = no cash effect).
  final String? walletName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final t = view.trade;
    final sw = tradeSwatch(t.type);
    final effect = tradeCashEffect(t);
    final linked = view.transaction != null;
    final sub = <String>[
      Fmt.date(t.date),
      if (t.fee > 0) 'biaya ${context.money(t.fee, currency: asset.currency)}',
      if (t.note case final n? when n.isNotEmpty) n,
    ];
    return ChunkyTile(
      key: ValueKey('trade-${t.id}'),
      framed: false,
      dense: true,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CategoryAvatar(
        icon: tradeIcon(t.type),
        color: sw.base,
        size: 40,
        soft: t.type == TradeType.fee,
      ),
      title: tradeTitle(t, asset),
      subtitle: sub.join(' · '),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (effect != null)
            MoneyText(
              amount: effect.amount,
              currency: asset.currency,
              tone: t.type == TradeType.dividend
                  ? MoneyTone.income
                  : MoneyTone.neutral,
              color: t.type == TradeType.dividend ? null : g.textPrimary,
              style: GhinaType.moneyS,
            )
          else
            Text('—', style: GhinaType.moneyS.copyWith(color: g.textMuted)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                linked
                    ? Icons.account_balance_wallet_rounded
                    : Icons.link_off_rounded,
                size: 12,
                color: g.textMuted,
              ),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  linked ? (walletName ?? 'Dompet') : 'tanpa kas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(
                    color: g.textMuted,
                    fontSize: 11,
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
