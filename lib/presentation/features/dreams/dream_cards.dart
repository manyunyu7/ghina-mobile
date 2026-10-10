import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import 'dream_format.dart';
import 'dream_list_logic.dart';
import 'dream_visuals.dart';

/// Emoji of a dream, or the default star.
Text dreamEmojiText(String? emoji, {double size = 22}) =>
    Text(emoji ?? '🌠', style: TextStyle(fontSize: size));

/// A dream on the board: emoji, title, category, priority, target and the
/// progress bar when known. Tap opens it; the ⋮ button or a long press changes
/// its status.
class DreamBoardCard extends StatelessWidget {
  const DreamBoardCard({
    super.key,
    required this.row,
    required this.categoryLabel,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final DreamRow row;
  final String categoryLabel;
  final VoidCallback onOpen;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = row.dream;
    final target = dreamTargetText(d);
    return ChunkyCard(
      key: ValueKey('dream-card-${d.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      onTap: onOpen,
      onLongPress: onChangeStatus,
      semanticLabel: d.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              dreamEmojiText(d.emoji),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              IconButton(
                key: ValueKey('dream-menu-${d.id}'),
                tooltip: 'Ubah status',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert_rounded, color: g.textMuted),
                onPressed: onChangeStatus,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              DreamCategoryPill(label: categoryLabel),
              if (d.priority != null)
                ChunkyPill(
                  label: dreamPriorityShort(d.priority),
                  color: GhinaColors.orange,
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
          if (target.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '🎯 $target',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ],
          if (row.progressPct != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DreamProgressLine(pct: row.progressPct),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row of the table view: emoji and title, status, category, priority, target,
/// progress, and the effective cost.
class DreamTableRow extends StatelessWidget {
  const DreamTableRow({
    super.key,
    required this.row,
    required this.categoryLabel,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final DreamRow row;
  final String categoryLabel;
  final VoidCallback onOpen;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = row.dream;
    final cost = row.effectiveCost;
    final target = dreamTargetText(d);
    return ChunkyCard(
      key: ValueKey('dream-row-${d.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      onTap: onOpen,
      onLongPress: onChangeStatus,
      semanticLabel: d.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              dreamEmojiText(d.emoji, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              DreamStatusPill(status: d.status),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DreamCategoryPill(label: categoryLabel),
              if (d.priority != null)
                Text(
                  dreamPriorityText(d.priority),
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              if (target.isNotEmpty)
                Text(
                  '🎯 $target',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: DreamProgressLine(pct: row.progressPct)),
              if (cost != null) ...[
                const SizedBox(width: 10),
                Text(
                  context.money(cost),
                  key: ValueKey('dream-row-cost-${d.id}'),
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact row of the timeline view.
class DreamTimelineTile extends StatelessWidget {
  const DreamTimelineTile({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final DreamRow row;
  final VoidCallback onOpen;
  final VoidCallback onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final d = row.dream;
    final target = dreamTargetText(d);
    return ChunkyTile(
      key: ValueKey('dream-tile-${d.id}'),
      dense: true,
      leading: dreamEmojiText(d.emoji, size: 20),
      title: d.title,
      subtitle: target.isEmpty ? d.status.label : '🎯 $target',
      trailing: DreamStatusPill(status: d.status),
      onTap: onOpen,
      onLongPress: onChangeStatus,
    );
  }
}
