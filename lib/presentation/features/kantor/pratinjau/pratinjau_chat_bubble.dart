import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../session/chat_model.dart';
import 'pratinjau_actions.dart';
import 'pratinjau_widgets.dart';

/// Pratinjau this session sent, placed among the chat [entries] by
/// `createdAt` (items without a time go last).
List<ChatEntry> mergePratinjau(
  List<ChatEntry> entries,
  List<PratinjauItem> items,
) {
  if (items.isEmpty) return entries;
  final sorted = [...items]
    ..sort((a, b) {
      final x = DateTime.tryParse(a.createdAt ?? '');
      final y = DateTime.tryParse(b.createdAt ?? '');
      if (x == null || y == null) {
        return x == null && y == null ? 0 : (x == null ? 1 : -1);
      }
      return x.compareTo(y);
    });
  final out = <ChatEntry>[];
  var i = 0;
  for (final e in entries) {
    final t = DateTime.tryParse(e.at);
    if (t != null) {
      while (i < sorted.length) {
        final at = DateTime.tryParse(sorted[i].createdAt ?? '');
        if (at == null || at.isAfter(t)) break;
        out.add(PratinjauEntry(sorted[i++]));
      }
    }
    out.add(e);
  }
  while (i < sorted.length) {
    out.add(PratinjauEntry(sorted[i++]));
  }
  return out;
}

/// Chat bubble for one pratinjau: carousel of thumbnails, title, jenis and
/// status, reactions and the buttons per jenis. Tap → detail page.
class PratinjauChatBubble extends StatefulWidget {
  const PratinjauChatBubble({super.key, required this.item, required this.api});
  final PratinjauItem item;
  final KantorApi? api;

  @override
  State<PratinjauChatBubble> createState() => _BubbleState();
}

class _BubbleState extends State<PratinjauChatBubble> {
  PratinjauItem? _fresh;
  int _page = 0;

  @override
  void didUpdateWidget(PratinjauChatBubble old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) _fresh = null;
  }

  void _open([String? fileId]) {
    final it = _fresh ?? widget.item;
    final r = pratinjauRoute(it.office, it.id);
    context.push(fileId == null ? r : '$r?f=${Uri.encodeComponent(fileId)}');
  }

  void _set(PratinjauItem n) {
    if (mounted) setState(() => _fresh = n);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final it = _fresh ?? widget.item;
    final api = widget.api;
    final files = it.files;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ChunkyCard(
          padding: const EdgeInsets.all(GhinaSpace.sm),
          onTap: _open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.preview_rounded, size: 16, color: g.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Pratinjau · ${pratinjauJenisLabel(it.jenis)}',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                  PratinjauVersionBadge(it.version),
                  const SizedBox(width: GhinaSpace.xs),
                  PratinjauStatusPill(it.status),
                ],
              ),
              const SizedBox(height: GhinaSpace.xs),
              Text(
                it.title.isEmpty ? '(tanpa judul)' : it.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
              if (it.note != null)
                Text(
                  it.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              if (files.isNotEmpty && api != null) ...[
                const SizedBox(height: GhinaSpace.sm),
                ClipRRect(
                  borderRadius: GhinaRadii.rMd,
                  child: SizedBox(
                    height: 170,
                    child: Stack(
                      children: [
                        PageView.builder(
                          itemCount: files.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () => _open(files[i].id),
                            child: PratinjauThumb(
                              api: api,
                              file: files[i],
                              purged: it.filesPurged,
                            ),
                          ),
                        ),
                        if (files.length > 1)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: GhinaRadii.rSm,
                              ),
                              child: Text(
                                '${_page + 1}/${files.length}',
                                style: GhinaType.caption.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (it.filesPurged) ...[
                const SizedBox(height: GhinaSpace.xs),
                const PratinjauPurgedHint(),
              ],
              if (it.comments.isNotEmpty) ...[
                const SizedBox(height: GhinaSpace.xs),
                Text(
                  '💬 ${it.comments.last.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
              const SizedBox(height: GhinaSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: PratinjauReactions(item: it, onItem: _set),
                    ),
                  ),
                  PratinjauMenuButton(item: it, onItem: _set),
                ],
              ),
              PratinjauActionBar(
                item: it,
                onItem: _set,
                compact: true,
                file: it.isPilihan && files.length == 1 ? files.first : null,
                onOpen: () => _open(files.isEmpty ? null : files[_page].id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
