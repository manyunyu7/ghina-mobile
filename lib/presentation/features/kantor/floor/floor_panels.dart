// Panels under the floor plan and the info sheets (room, person, start shift).
// Mirrors the web side panel: inbox, "Suruh <manager>", announcements.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'floor_pixel.dart';

String ago(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

Map<String, dynamic> asMap(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};
List<Map<String, dynamic>> asMaps(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map<String, dynamic>) x,
];

/// Pixel character picture for sheets.
class FloorAvatar extends StatelessWidget {
  const FloorAvatar({super.key, required this.look, this.scale = 2.4});
  final Look look;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ui.Image img = personImage(look, const PersonPose());
    return SizedBox(
      width: kPersonW * scale,
      height: kPersonH * scale,
      child: RawImage(
        image: img,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
    );
  }
}

/// The pull-up panel: inbox, manager form, announcements.
class FloorPanel extends StatelessWidget {
  const FloorPanel({
    super.key,
    required this.scroll,
    required this.inbox,
    required this.news,
    required this.manager,
    required this.mgrBusy,
    required this.onDecide,
    required this.onAsk,
    required this.onPost,
    required this.onDeleteNews,
    required this.mgrController,
    required this.newsController,
    required this.onOpenSession,
  });

  final ScrollController scroll;
  final List<Map<String, dynamic>> inbox;
  final List<Map<String, dynamic>> news;
  final Map<String, dynamic>? manager;
  final bool mgrBusy;
  final void Function(String id, bool allow) onDecide;
  final VoidCallback onAsk;
  final VoidCallback onPost;
  final void Function(Object id) onDeleteNews;
  final TextEditingController mgrController;
  final TextEditingController newsController;
  final void Function(String sid) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: g.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  inbox.isEmpty
                      ? 'Kotak masuk kosong'
                      : '${inbox.length} izin menunggu',
                  style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                ),
              ),
              if (inbox.isNotEmpty)
                ChunkyPill(label: '${inbox.length}', color: GhinaColors.orange),
            ],
          ),
          const SizedBox(height: 10),
          if (inbox.isEmpty)
            Text(
              'Tidak ada yang menunggu izin.',
              style: GhinaType.bodyS.copyWith(color: g.textMuted),
            )
          else
            for (final it in inbox)
              _InboxItem(
                item: it,
                onDecide: onDecide,
                onOpenSession: onOpenSession,
              ),
          if (manager != null) ...[
            const SizedBox(height: 18),
            Text(
              'Suruh ${manager!['name']}',
              style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 8),
            ChunkyTextField(
              controller: mgrController,
              hint: 'mis. rapikan alur pembayaran lalu siapkan rilis',
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 8),
            ChunkyButton(
              label: 'Kirim',
              size: ChunkyButtonSize.small,
              expand: false,
              loading: mgrBusy,
              onPressed: onAsk,
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Papan pengumuman',
            style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 8),
          if (news.isEmpty)
            Text('Kosong', style: GhinaType.bodyS.copyWith(color: g.textMuted))
          else
            for (final n in news)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ChunkyCard(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${n['text'] ?? ''}'),
                              if (n['author'] != null &&
                                  n['author'] != 'Kamu' &&
                                  n['author'] != 'Sistem')
                                TextSpan(
                                  text: '  ${n['author']}',
                                  style: TextStyle(color: g.textMuted),
                                ),
                            ],
                          ),
                          style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Lepas',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: g.textMuted,
                        ),
                        onPressed: () => onDeleteNews(n['id']),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChunkyTextField(
                  controller: newsController,
                  hint: 'Tempel pengumuman',
                  onSubmitted: (_) => onPost(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              ChunkyIconButton(
                icon: Icons.send_rounded,
                color: GhinaColors.blue,
                onPressed: onPost,
                tooltip: 'Tempel',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxItem extends StatelessWidget {
  const _InboxItem({
    required this.item,
    required this.onDecide,
    required this.onOpenSession,
  });
  final Map<String, dynamic> item;
  final void Function(String id, bool allow) onDecide;
  final void Function(String sid) onOpenSession;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final held = item['held'] == true;
    final id = '${item['id']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyCard(
        tinted: GhinaColors.orange,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item['who'] ?? 'Sesi'}',
                    style: GhinaType.body.w(900),
                  ),
                  TextSpan(
                    text:
                        '  ${item['tool'] ?? ''} · ${ago(item['created_at'])}',
                    style: TextStyle(color: g.textSecondary),
                  ),
                ],
              ),
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '${item['summary'] ?? ''}',
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(
                color: g.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 10),
            if (held)
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: 'Izinkan',
                      size: ChunkyButtonSize.small,
                      onPressed: () => onDecide(id, true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChunkyButton(
                      label: 'Tolak',
                      size: ChunkyButtonSize.small,
                      variant: ChunkyButtonVariant.outline,
                      onPressed: () => onDecide(id, false),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Sudah pindah ke terminal sesinya. Jawab dari sana.',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

Widget fact(BuildContext context, String label, Widget value) {
  final g = context.ghina;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GhinaType.overline.copyWith(color: g.textMuted),
        ),
        const SizedBox(height: 2),
        value,
      ],
    ),
  );
}
