import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import 'kantor_board_data.dart';
import 'kantor_board_lib.dart';

ChunkySwatch kPrioSwatch(String p) => switch (p) {
  'P0' => GhinaColors.red,
  'P1' => GhinaColors.orange,
  'P3' => GhinaColors.gray,
  _ => GhinaColors.blue,
};

ChunkySwatch kColSwatch(int col) => switch (col) {
  0 => GhinaColors.gray,
  1 => GhinaColors.blue,
  2 => GhinaColors.orange,
  3 => GhinaColors.purple,
  _ => GhinaColors.green,
};

/// Swatch of a column kind (antre/siap/dikerjakan/review/selesai).
ChunkySwatch kKindSwatch(String kind) =>
    kColSwatch(kantorKinds.indexOf(kind).clamp(0, 4));

Color kHex(String hex) => CategoryColors.parse(hex);

/// Color of a board (its hex), blue when unset.
Color kBoardColor(KBoardDef? b) => b == null || b.color.isEmpty
    ? GhinaColors.blue.base
    : kHex(b.color);

/// Cover image of a card (`coverUrl`), fetched with the office token.
class KCardCover extends ConsumerWidget {
  const KCardCover({super.key, required this.url, this.height = 120});
  final String url;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(kantorApiProvider);
    if (api == null) return const SizedBox.shrink();
    final abs = url.startsWith('http') ? Uri.parse(url) : _rel(api, url);
    return ClipRRect(
      borderRadius: GhinaRadii.rMd,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Image.network(
          abs.toString(),
          headers: api.authHeaders,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  static Uri _rel(KantorApi api, String u) {
    final i = u.indexOf('?');
    if (i < 0) return api.url(u);
    return api.url(u.substring(0, i), Uri.splitQueryString(u.substring(i + 1)));
  }
}

/// Horizontally scrollable row of chips. Height follows the tallest child, so
/// it grows with the system font scale instead of clipping like a fixed box.
class KChipStrip extends StatelessWidget {
  const KChipStrip({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.gap = 8,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(SizedBox(width: gap));
      items.add(children[i]);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: items,
      ),
    );
  }
}

/// Pixel sprite of a role, or a plain guest.
class KWhoAvatar extends StatelessWidget {
  const KWhoAvatar({
    super.key,
    required this.office,
    required this.who,
    this.size = 28,
  });
  final KOffice? office;
  final String who;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = office?.role(who);
    final look = r?.raw ?? KantorSprite.guestLook(who.isEmpty ? '_' : who);
    return KantorSprite(look: look, size: size);
  }
}

class KLabelChip extends StatelessWidget {
  const KLabelChip({
    super.key,
    required this.label,
    this.selected = true,
    this.onTap,
  });
  final KLabel label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = kHex(label.color);
    final ink = kInkIsDark(label.color)
        ? const Color(0xFF1F1628)
        : Colors.white;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? c : c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Text(
        label.name,
        style: GhinaType.caption
            .w(700)
            .copyWith(color: selected ? ink : context.ghina.textPrimary),
      ),
    );
    return onTap == null ? chip : GestureDetector(onTap: onTap, child: chip);
  }
}

class KDueChip extends StatelessWidget {
  const KDueChip({super.key, required this.card});
  final KCard card;

  @override
  Widget build(BuildContext context) {
    final st = kDueState(card);
    if (st == KDue.none) return const SizedBox.shrink();
    final sw = switch (st) {
      KDue.over => GhinaColors.red,
      KDue.soon => GhinaColors.orange,
      KDue.done => GhinaColors.green,
      _ => GhinaColors.gray,
    };
    return ChunkyPill(
      label: kFmtDay(card.due),
      color: sw,
      soft: true,
      icon: Icons.event_rounded,
      uppercase: false,
    );
  }
}

class KPrioPill extends StatelessWidget {
  const KPrioPill(this.prio, {super.key});
  final String prio;
  @override
  Widget build(BuildContext context) =>
      ChunkyPill(label: prio, color: kPrioSwatch(prio));
}

/// One card on the board.
class KCardTile extends StatelessWidget {
  const KCardTile({
    super.key,
    required this.card,
    required this.board,
    required this.office,
    required this.onTap,
    this.onMore,
    this.compact = false,
  });

  final KCard card;
  final KBoard board;
  final KOffice? office;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final pending = kPendingDeps(card, board.map);
    final pct = card.percent;
    final epic = card.epicId.isEmpty ? null : board.map[card.epicId];
    final live =
        card.who.isNotEmpty &&
        (office?.workingRoles.contains(card.who) ?? false);
    final labels = [for (final l in card.labels) ?board.label(l)];
    final def = board.all ? board.boardDef(card.board) : null;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.coverUrl != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: KCardCover(
                url: card.coverUrl!,
                height: compact ? 72 : 120,
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (def != null) KBoardChip(board: def),
                    KPrioPill(card.prio),
                    if (isKDate(card.publishAt))
                      Text(
                        'Tayang ${kFmtDay(card.publishAt)}',
                        style: GhinaType.caption
                            .w(700)
                            .copyWith(color: GhinaColors.purple.base),
                      ),
                    if (card.repo.isNotEmpty)
                      Text(
                        office?.repoName(card.repo) ?? card.repo,
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    if (card.milestone)
                      Text('◆', style: TextStyle(color: g.warning)),
                  ],
                ),
              ),
              if (onMore != null)
                InkResponse(
                  onTap: onMore,
                  radius: 20,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: g.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              card.title,
              maxLines: compact ? 2 : 4,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.body.w(700).copyWith(color: g.textPrimary),
            ),
          ),
          if (epic != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.layers_rounded, size: 13, color: g.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    epic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                ),
              ],
            ),
          ],
          if (card.epic) ...[
            const SizedBox(height: 4),
            Text(
              'Epic · ${board.kids(card.id).where((k) => k.done).length}/${board.kids(card.id).length} sub-kartu selesai',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
          if (labels.isNotEmpty && !compact) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final l in labels) KLabelChip(label: l)],
            ),
          ],
          if (card.blocked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 14,
                  color: GhinaColors.red.base,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Terblokir: ${card.blocked}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption
                        .w(700)
                        .copyWith(color: GhinaColors.red.base),
                  ),
                ),
              ],
            ),
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded, size: 14, color: g.warning),
                const SizedBox(width: 4),
                Text(
                  'Menunggu ${pending.length} kartu',
                  style: GhinaType.caption.w(700).copyWith(color: g.warning),
                ),
              ],
            ),
          ],
          if (pct != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChunkyProgressBar(
                    value: pct / 100,
                    color: GhinaColors.green,
                    height: 8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  card.checksTotal > 0 && card.progress == null
                      ? '${card.checksDone}/${card.checksTotal}'
                      : '$pct%',
                  style: GhinaType.caption
                      .w(700)
                      .copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              KWhoAvatar(office: office, who: card.who, size: 26),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  live
                      ? '${office!.whoName(card.who)} sedang bekerja'
                      : office?.whoName(card.who) ?? card.who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(
                    color: live ? GhinaColors.green.base : g.textSecondary,
                    fontWeight: live ? FontWeight.w700 : null,
                  ),
                ),
              ),
              if (card.comments > 0) ...[
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: g.textMuted,
                ),
                const SizedBox(width: 2),
                Text(
                  '${card.comments}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
                const SizedBox(width: 6),
              ],
              if (card.attachments > 0) ...[
                Icon(Icons.attach_file_rounded, size: 14, color: g.textMuted),
                Text(
                  '${card.attachments}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
                const SizedBox(width: 6),
              ],
              KDueChip(card: card),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled row that opens a picker; used by the detail screen and sheets.
class KFieldRow extends StatelessWidget {
  const KFieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.leading,
    this.onClear,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? leading;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return InkWell(
      onTap: onTap,
      borderRadius: GhinaRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ),
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body.w(600).copyWith(color: g.textPrimary),
              ),
            ),
            if (onClear != null)
              InkResponse(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 18, color: g.textMuted),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that picks one value; returns the chosen value (or null).
Future<T?> kPickOne<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label, Widget? leading})> options,
  T? current,
}) {
  return showChunkyBottomSheet<T>(
    context,
    title: title,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final o in options)
            ListTile(
              leading: o.leading,
              title: Text(o.label, style: GhinaType.body.w(600)),
              trailing: o.value == current
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(ctx).pop(o.value),
            ),
        ],
      ),
    ),
  );
}

void kToast(BuildContext context, String msg, {bool bad = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bad ? GhinaColors.red.base : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Small colored chip with a board name.
class KBoardChip extends StatelessWidget {
  const KBoardChip({super.key, required this.board});
  final KBoardDef board;

  @override
  Widget build(BuildContext context) {
    final c = kBoardColor(board);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        board.icon.isEmpty ? board.name : '${board.icon} ${board.name}',
        style: GhinaType.caption.w(700).copyWith(color: c),
      ),
    );
  }
}
