import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../investment_format.dart';

/// Orange "harga lama" pill: the cached market price couldn't be refreshed
/// (offline / source down) — values still use it.
class StaleBadge extends StatelessWidget {
  const StaleBadge({
    super.key,
    this.onColor = false,
    this.label = 'Harga lama',
  });

  /// White-on-color variant for solid cards.
  final bool onColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = onColor ? Colors.white : GhinaColors.orange.base;
    return Container(
      key: const ValueKey('stale-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onColor
            ? Colors.white.withValues(alpha: 0.22)
            : GhinaColors.orange.base.withValues(alpha: 0.14),
        borderRadius: GhinaRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: GhinaType.caption.w(900).copyWith(color: fg, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Rounded avatar of an asset: kind color with the ticker's first letters.
class AssetAvatar extends StatelessWidget {
  const AssetAvatar({super.key, required this.asset, this.size = 44});

  final Asset asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sw = kindSwatch(asset.kind);
    final code = asset.symbol.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final text = code.isEmpty
        ? '?'
        : code.substring(0, code.length < 4 ? code.length : 4).toUpperCase();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: sw.edge,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: sw.base,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: GhinaType.caption
                .w(900)
                .copyWith(
                  color: sw.on,
                  fontSize: size * 0.3,
                  letterSpacing: -0.2,
                ),
          ),
        ),
      ),
    );
  }
}

/// `▲ 1,25%` colored change (percent is not masked — it isn't an amount).
class ChangeText extends StatelessWidget {
  const ChangeText({super.key, required this.pct, this.style, this.prefix});

  final double? pct;
  final TextStyle? style;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final color = plColor(context, pct);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(plIcon(pct), size: 20, color: color),
        Flexible(
          child: Text(
            '${prefix ?? ''}${fmtPct(pct, sign: false)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style ?? GhinaType.caption.w(900)).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// One holding as a chunky row: avatar, ticker + name, quantity and average,
/// last price + day change; value and P/L on the right.
class HoldingTile extends StatelessWidget {
  const HoldingTile({super.key, required this.view, this.onTap});

  final HoldingView view;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = view.asset;
    final h = view.holding;
    final q = qtyLabel(a, h.shares);
    final price = view.valuation.price;
    final avg = h.avgPrice;
    return ChunkyCard(
      key: ValueKey('holding-${a.id}'),
      onTap: onTap,
      semanticLabel: a.displayName,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AssetAvatar(asset: a),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (view.quote.stale && h.isOpen) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 16,
                        color: GhinaColors.orange.base,
                        semanticLabel: 'Harga lama',
                      ),
                    ],
                  ],
                ),
                if (a.name != null && a.name!.isNotEmpty)
                  Text(
                    a.name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                const SizedBox(height: 4),
                Text(
                  h.isOpen
                      ? [
                          q.main,
                          if (avg != null)
                            'avg ${context.money(avg, currency: a.currency, compact: avg >= 1e6)}',
                        ].join(' · ')
                      : 'Belum punya · ${a.kind.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        price == null
                            ? 'Belum ada harga'
                            : price >= 1e6
                            ? GhinaMoney.format(
                                price,
                                currency: a.currency,
                                compact: true,
                              )
                            : fmtPrice(price, currency: a.currency),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                    if (view.quote.isManual)
                      Text(
                        ' · manual',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      )
                    else if (view.dayChangePct != null)
                      ChangeText(pct: view.dayChangePct),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: MoneyText(
                    amount: view.value,
                    currency: a.currency,
                    tone: MoneyTone.neutral,
                    style: GhinaType.moneyM,
                  ),
                ),
                if (view.unrealized != null && h.isOpen) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyText(
                      amount: view.unrealized!,
                      currency: a.currency,
                      compact: true,
                      tone: MoneyTone.auto,
                      color: plColor(context, view.unrealized),
                      style: GhinaType.moneyS,
                    ),
                  ),
                  Text(
                    fmtPct(view.unrealizedPct),
                    style: GhinaType.caption
                        .w(900)
                        .copyWith(color: plColor(context, view.unrealized)),
                  ),
                ] else if (view.unpriced)
                  Text(
                    'nilai modal',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label/value line of a breakdown card.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.emphasis = false,
  });

  final String label;
  final Widget value;
  final String? hint;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      (emphasis
                              ? GhinaType.body.w(900)
                              : GhinaType.bodyS.w(700))
                          .copyWith(
                            color: emphasis ? g.textPrimary : g.textSecondary,
                          ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: value,
            ),
          ),
        ],
      ),
    );
  }
}

/// Money with sign + color for P/L values (masked when balances are hidden).
class PlMoney extends StatelessWidget {
  const PlMoney({
    super.key,
    required this.amount,
    required this.currency,
    this.pct,
    this.style,
    this.compact = false,
  });

  final double? amount;
  final String currency;
  final double? pct;
  final TextStyle? style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = amount;
    if (a == null) {
      return Text(
        '–',
        style: (style ?? GhinaType.moneyS).copyWith(
          color: context.ghina.textMuted,
        ),
      );
    }
    final color = plColor(context, a);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MoneyText(
          amount: a.abs() < 0.005 ? 0 : a,
          currency: currency,
          compact: compact,
          tone: MoneyTone.auto,
          color: color,
          style: style ?? GhinaType.moneyS,
        ),
        if (pct != null) ...[
          const SizedBox(width: 4),
          Text(
            '(${fmtPct(pct)})',
            style: GhinaType.caption.w(900).copyWith(color: color),
          ),
        ],
      ],
    );
  }
}
