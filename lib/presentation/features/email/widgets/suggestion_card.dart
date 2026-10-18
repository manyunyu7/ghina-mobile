import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// Semantic color of a suggestion kind (expense red, income green, transfer
/// blue) — never the user's accent.
ChunkySwatch emailKindSwatch(EmailSuggestionKind k) => switch (k) {
  EmailSuggestionKind.expense => GhinaColors.expense,
  EmailSuggestionKind.income => GhinaColors.income,
  EmailSuggestionKind.transfer => GhinaColors.transfer,
};

MoneyTone emailKindTone(EmailSuggestionKind k) => switch (k) {
  EmailSuggestionKind.expense => MoneyTone.expense,
  EmailSuggestionKind.income => MoneyTone.income,
  EmailSuggestionKind.transfer => MoneyTone.transfer,
};

IconData emailKindIcon(EmailSuggestionKind k) => switch (k) {
  EmailSuggestionKind.expense => Icons.arrow_upward_rounded,
  EmailSuggestionKind.income => Icons.arrow_downward_rounded,
  EmailSuggestionKind.transfer => Icons.swap_horiz_rounded,
};

/// One suggestion of the review queue: what was read from the email and
/// (for pending ones) Setujui / Edit / Abaikan.
class EmailSuggestionCard extends StatelessWidget {
  const EmailSuggestionCard({
    super.key,
    required this.suggestion,
    required this.walletName,
    this.categoryName,
    this.busy = false,
    this.onApprove,
    this.onEdit,
    this.onIgnore,
    this.onRestore,
    this.onOpenGmail,
  });

  final EmailSuggestion suggestion;

  /// The guessed wallet's name; null when the server had no guess.
  final String? walletName;
  final String? categoryName;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onIgnore;
  final VoidCallback? onRestore;
  final VoidCallback? onOpenGmail;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = suggestion;
    final kind = emailKindSwatch(s.kind);
    final dup = s.duplicateOf;
    final caption = [
      '${Fmt.date(s.occurredAt)} ${Fmt.time(s.occurredAt)}',
      ?s.method,
    ].join(' · ');
    return ChunkyCard(
      key: Key('email-suggestion-${s.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryAvatar(
                icon: emailKindIcon(s.kind),
                color: kind.base,
                size: 40,
                soft: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MoneyText(
                        amount: s.amount,
                        tone: emailKindTone(s.kind),
                      ),
                    ),
                    if (s.originalCurrency != null && s.originalAmount != null)
                      Text(
                        '${s.originalCurrency} ${Fmt.number(s.originalAmount!, decimals: 2)}',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChunkyPill(
                label: s.kind.label,
                color: kind,
                soft: true,
                uppercase: false,
              ),
              if (s.source == EmailSuggestionSource.ai)
                const ChunkyPill(
                  label: 'AI',
                  icon: Icons.auto_awesome_rounded,
                  color: GhinaColors.purple,
                  soft: true,
                  uppercase: false,
                )
              else
                const _InfoChip(icon: Icons.bolt_rounded, label: 'Otomatis'),
              _InfoChip(
                icon: Icons.account_balance_wallet_rounded,
                label: walletName ?? 'Dompet belum dipilih',
                warn: walletName == null,
              ),
              if (categoryName != null)
                _InfoChip(icon: Icons.sell_rounded, label: categoryName!),
            ],
          ),
          if (dup != null) ...[
            const SizedBox(height: 10),
            _DuplicateWarning(dup: dup),
          ],
          if (s.note.isNotEmpty && s.note != s.title) ...[
            const SizedBox(height: 8),
            Text(
              s.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ],
          if (s.gmailUrl != null && onOpenGmail != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenGmail,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  foregroundColor: g.textSecondary,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('Buka di Gmail', style: GhinaType.bodyS.w(700)),
              ),
            )
          else
            const SizedBox(height: 10),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final s = suggestion;
    switch (s.status) {
      case EmailSuggestionStatus.pending:
        return [
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: Key('email-ignore-${s.id}'),
                  expand: true,
                  label: 'Abaikan',
                  variant: ChunkyButtonVariant.ghost,
                  size: ChunkyButtonSize.small,
                  onPressed: busy ? null : onIgnore,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  key: Key('email-edit-${s.id}'),
                  expand: true,
                  label: 'Edit',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.small,
                  onPressed: busy ? null : onEdit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  key: Key('email-approve-${s.id}'),
                  expand: true,
                  label: 'Setujui',
                  size: ChunkyButtonSize.small,
                  loading: busy,
                  onPressed: busy ? null : onApprove,
                ),
              ),
            ],
          ),
        ];
      case EmailSuggestionStatus.ignored:
        return [
          Align(
            alignment: Alignment.centerRight,
            child: ChunkyButton(
              key: Key('email-restore-${s.id}'),
              label: 'Kembalikan',
              icon: Icons.undo_rounded,
              variant: ChunkyButtonVariant.outline,
              size: ChunkyButtonSize.small,
              expand: false,
              loading: busy,
              onPressed: busy ? null : onRestore,
            ),
          ),
        ];
      case EmailSuggestionStatus.approved:
        return [
          const ChunkyPill(
            label: 'Sudah dicatat',
            icon: Icons.check_circle_rounded,
            color: GhinaColors.green,
            soft: true,
            uppercase: false,
          ),
        ];
    }
  }
}

/// A neutral, ellipsized tag (wallet / category names can be long).
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.warn = false});

  final IconData icon;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = warn ? GhinaColors.orange.edge : g.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? g.tint(GhinaColors.orange) : g.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.w(700).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.dup});

  final EmailDuplicate dup;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final when = dup.date == null ? '' : ' tgl ${Fmt.date(dup.date!)}';
    final note = dup.note == null ? '' : ' ("${dup.note}")';
    return Container(
      key: const Key('email-duplicate'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: g.tint(GhinaColors.orange),
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: GhinaColors.orange.base, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: GhinaColors.orange.edge,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Mungkin dobel. ',
                    style: GhinaType.bodyS.w(800),
                  ),
                  TextSpan(
                    text:
                        'Sudah ada transaksi ${context.money(dup.amount)}'
                        '$when$note.',
                  ),
                ],
              ),
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
