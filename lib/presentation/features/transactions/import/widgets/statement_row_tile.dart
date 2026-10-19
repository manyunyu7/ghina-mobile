import 'package:flutter/material.dart';

import '../../../../../core/formatters.dart';
import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../../widgets/tx_visuals.dart';

/// One statement row of the review: a checkbox (pending rows), date, title,
/// the signed amount in the transactions-list colors, accounts and category.
/// Duplicate / uncertain rows show the matching transaction and Killa's
/// reason; approved / ignored rows are greyed with a check / strike.
class StatementRowTile extends StatelessWidget {
  const StatementRowTile({
    super.key,
    required this.row,
    required this.currency,
    this.checked = false,
    this.onChecked,
    this.onTap,
  });

  final StatementRow row;
  final String currency;
  final bool checked;
  final ValueChanged<bool>? onChecked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = row;
    final ignored = r.status == StatementRowStatus.ignored;
    final accounts = r.type == TxType.transfer
        ? '${r.wallet ?? '?'} → ${r.toWallet ?? '?'}'
        : r.wallet;
    final caption = [Fmt.date(r.date), ?accounts, ?r.category].join(' · ');
    final titleStyle = GhinaType.body
        .w(800)
        .copyWith(
          color: g.textPrimary,
          decoration: ignored ? TextDecoration.lineThrough : null,
        );
    final card = ChunkyCard(
      key: Key('statement-row-${r.id}'),
      padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
      onTap: r.pending ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.pending)
            Checkbox(
              key: Key('statement-check-${r.id}'),
              value: checked,
              onChanged: onChecked == null
                  ? null
                  : (v) => onChecked!(v ?? false),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
              child: Icon(
                ignored ? Icons.block_rounded : Icons.check_circle_rounded,
                size: 20,
                color: ignored ? g.textMuted : GhinaColors.green.base,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TxAmount(
                        type: r.type,
                        amount: r.amount,
                        currency: currency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
                if (r.note != null && r.note != r.description)
                  Text(
                    r.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                if (r.pending && r.verdict != StatementVerdict.isNew) ...[
                  const SizedBox(height: 8),
                  _MatchBox(row: r, currency: currency),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return r.pending ? card : Opacity(opacity: 0.55, child: card);
  }
}

/// "Mirip: …" (the matching transaction) + the reason, for duplicate /
/// uncertain rows.
class _MatchBox extends StatelessWidget {
  const _MatchBox({required this.row, required this.currency});

  final StatementRow row;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = row.duplicateOf;
    final uncertain = row.verdict == StatementVerdict.uncertain;
    final swatch = uncertain ? GhinaColors.orange : GhinaColors.gray;
    final match = m == null
        ? null
        : [
            if (m.note != null) '"${m.note}"',
            GhinaMoney.format(m.amount, currency: currency),
            ?m.wallet,
            if (m.date != null) Fmt.date(m.date!),
          ].join(' · ');
    return Container(
      key: Key('statement-match-${row.id}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: g.tint(swatch),
        borderRadius: GhinaRadii.rMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            uncertain ? Icons.help_outline_rounded : Icons.link_rounded,
            size: 16,
            color: uncertain ? GhinaColors.orange.edge : g.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (match != null)
                  Text(
                    'Mirip: $match',
                    style: GhinaType.caption
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                if (row.reason != null)
                  Text(
                    row.reason!,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
