import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import 'chat_model.dart';
import 'chat_view_prefs.dart';
import 'teammate_message.dart';

const _tmColors = {
  'blue': Color(0xFF2F6FEB),
  'green': Color(0xFF2F9E44),
  'purple': Color(0xFF7C4DFF),
  'red': Color(0xFFE03131),
  'orange': Color(0xFFF08C00),
  'yellow': Color(0xFFE0A800),
  'pink': Color(0xFFD6336C),
  'cyan': Color(0xFF0C9DB5),
};

/// A message from another Claude session: sender, colored dot, kind, summary
/// and the full text, folded until opened. Sits on the left, never as one of
/// the owner's bubbles.
class TeammateCard extends StatefulWidget {
  const TeammateCard({
    super.key,
    required this.msg,
    required this.at,
    required this.view,
  });

  final TeammateMsg msg;
  final String at;
  final ChatViewPrefs view;

  @override
  State<TeammateCard> createState() => _TeammateCardState();
}

class _TeammateCardState extends State<TeammateCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = widget.msg;
    final view = widget.view;
    final tone = _tmColors[m.color] ?? g.textMuted;
    final w = MediaQuery.sizeOf(context).width;
    final hasBody = m.body.isNotEmpty && m.body != m.summary;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w * view.bubbleWidth.fraction),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('teammate-card'),
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
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: tone,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  m.from,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GhinaType.bodyS
                                      .w(800)
                                      .copyWith(color: g.textPrimary),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: g.surfaceAlt,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  m.kind.toUpperCase(),
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
                          if (m.summary.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              m.summary,
                              style: GhinaType.body
                                  .w(700)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ],
                          if (hasBody) ...[
                            InkWell(
                              key: const ValueKey('teammate-toggle'),
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
                                      _open ? 'Tutup isi' : 'Lihat isi',
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
