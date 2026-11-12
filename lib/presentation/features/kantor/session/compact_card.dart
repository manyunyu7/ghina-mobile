import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import 'chat_model.dart';
import 'chat_view_prefs.dart';
import 'compact_summary.dart';

/// Ringkasan kompaksi ("percakapan dilanjutkan"): pratinjau terlihat,
/// ringkasan lengkap dilipat. Kartu lebar, bukan gelembung pemilik.
class CompactCard extends StatefulWidget {
  const CompactCard({
    super.key,
    required this.msg,
    this.pasted = false,
    required this.at,
    required this.view,
  });

  final CompactSummary msg;

  /// Ditempel pemilik (bukan kompaksi otomatis dari Claude Code).
  final bool pasted;
  final String at;
  final ChatViewPrefs view;

  @override
  State<CompactCard> createState() => _CompactCardState();
}

class _CompactCardState extends State<CompactCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = widget.msg;
    final view = widget.view;
    final tone = GhinaColors.green.base;
    final w = MediaQuery.sizeOf(context).width;
    final hasBody = m.body.isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w * view.bubbleWidth.fraction),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('compact-card'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: g.surface,
                borderRadius: GhinaRadii.rMd,
                border: Border.all(color: g.border, width: 2),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: ColoredBox(color: tone),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        GhinaSpace.md + 4,
                        GhinaSpace.md,
                        GhinaSpace.md,
                        GhinaSpace.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: tone,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Percakapan dilanjutkan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GhinaType.bodyS
                                      .w(800)
                                      .copyWith(color: g.textPrimary),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.pasted
                                      ? 'RINGKASAN YANG KAMU TEMPEL'
                                      : 'KONTEKS DIRINGKAS OTOMATIS',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GhinaType.caption
                                      .w(800)
                                      .copyWith(
                                        color: g.textMuted,
                                        fontSize: 10.5,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          if (m.preview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              m.preview,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.bodyS.copyWith(
                                color: g.textSecondary,
                              ),
                            ),
                          ],
                          if (hasBody) ...[
                            InkWell(
                              key: const ValueKey('compact-toggle'),
                              borderRadius: GhinaRadii.rSm,
                              onTap: () => setState(() => _open = !_open),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 6,
                                  bottom: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _open
                                          ? Icons.expand_less_rounded
                                          : Icons.chevron_right_rounded,
                                      size: 18,
                                      color: g.textMuted,
                                    ),
                                    Text(
                                      _open
                                          ? 'Tutup ringkasan'
                                          : 'Lihat ringkasan',
                                      style: GhinaType.bodyS
                                          .w(800)
                                          .copyWith(color: g.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_open)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * 0.5,
                                ),
                                child: SingleChildScrollView(
                                  child: KantorMarkdown(
                                    m.body,
                                    selectable: true,
                                    lineHeight: view.lineHeight.value,
                                    codeScale: view.codeScale,
                                    wrapCode: view.wrapCode,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (view.showTime && hhmm(widget.at).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  hhmm(widget.at),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
