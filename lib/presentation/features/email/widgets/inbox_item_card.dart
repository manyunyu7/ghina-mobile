import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../email_state.dart';

/// The colored "🔴 Mendesak" pill of an importance.
class EmailImportancePill extends StatelessWidget {
  const EmailImportancePill({super.key, required this.importance});

  final EmailImportance importance;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: '${importance.emoji} ${importance.label}',
    color: emailImportanceSwatch(importance),
    soft: true,
    uppercase: false,
  );
}

/// One mail of "Email penting": sender, subject, time, importance, Killa's
/// summary, "Perlu dilakukan", the reply draft and "Buka di Gmail". Tapping
/// the card (or using any of its actions) opens it, which marks it read.
class EmailInboxCard extends StatelessWidget {
  const EmailInboxCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onCopyDraft,
    required this.onOpenGmail,
  });

  final EmailInboxItem item;
  final VoidCallback onOpen;
  final VoidCallback onCopyDraft;
  final VoidCallback onOpenGmail;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final i = item;
    final sw = emailImportanceSwatch(i.importance);
    final at = i.receivedAt;
    final action = i.action;
    final draft = i.replyDraft;
    return ChunkyCard(
      key: Key('inbox-item-${i.id}'),
      tinted: i.read || i.importance != EmailImportance.urgent ? null : sw,
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!i.read)
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 8),
                  child: Container(
                    key: Key('inbox-unread-${i.id}'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: g.accent.base,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  i.sender.isEmpty ? '(tanpa pengirim)' : i.sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body
                      .w(i.read ? 700 : 900)
                      .copyWith(color: g.textPrimary),
                ),
              ),
              if (at != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${Fmt.relativeDay(at)} ${Fmt.time(at)}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ],
          ),
          if (i.subject.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              i.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS
                  .w(i.read ? 600 : 800)
                  .copyWith(color: g.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              EmailImportancePill(importance: i.importance),
              if (i.notifiedAt != null)
                const ChunkyPill(
                  label: 'Sudah dikabari via WA',
                  icon: Icons.chat_rounded,
                  color: GhinaColors.green,
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
          if (i.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              i.summary,
              style: GhinaType.body.copyWith(color: g.textPrimary),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 10),
            Container(
              key: Key('inbox-action-${i.id}'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: sw.tint(g.brightness),
                borderRadius: GhinaRadii.rMd,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.task_alt_rounded,
                    size: 18,
                    color: g.isDark ? sw.base : sw.edge,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perlu dilakukan',
                          style: GhinaType.caption
                              .w(900)
                              .copyWith(color: g.isDark ? sw.base : sw.edge),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          action,
                          style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (draft != null) ...[
            const SizedBox(height: 8),
            _ReplyDraft(
              id: i.id,
              draft: draft,
              onExpand: onOpen,
              onCopy: onCopyDraft,
            ),
          ],
          if (i.gmailUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('inbox-gmail-${i.id}'),
                onPressed: onOpenGmail,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: g.textSecondary,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('Buka di Gmail', style: GhinaType.bodyS.w(700)),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// "Draf balasan": collapsed by default; expanded it shows the draft and
/// "Salin".
class _ReplyDraft extends StatefulWidget {
  const _ReplyDraft({
    required this.id,
    required this.draft,
    required this.onExpand,
    required this.onCopy,
  });

  final String id;
  final String draft;
  final VoidCallback onExpand;
  final VoidCallback onCopy;

  @override
  State<_ReplyDraft> createState() => _ReplyDraftState();
}

class _ReplyDraftState extends State<_ReplyDraft> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('inbox-draft-${widget.id}'),
            borderRadius: GhinaRadii.rMd,
            onTap: () {
              setState(() => _open = !_open);
              if (_open) widget.onExpand();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 18, color: g.accent.base),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Draf balasan',
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: g.textPrimary),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: g.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    widget.draft,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ChunkyButton(
                      key: Key('inbox-copy-${widget.id}'),
                      label: 'Salin',
                      icon: Icons.copy_rounded,
                      variant: ChunkyButtonVariant.outline,
                      size: ChunkyButtonSize.small,
                      expand: false,
                      uppercase: false,
                      onPressed: widget.onCopy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Killa nggak bisa kirim email. Salin, lalu balas dari '
                    'Gmail.',
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
