import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'kantor_feed.dart';

const _keepDoneMs = 60000;

String fmtSubTokens(num? n) => n == null
    ? ''
    : n >= 1e6
    ? '${(n / 1e6).toStringAsFixed(1)}M'
    : n >= 1e3
    ? '${(n / 1e3).toStringAsFixed(1)}k'
    : '$n';

String fmtSubElapsed(int ms) {
  final t = ms < 0 ? 0 : ms ~/ 1000;
  final h = t ~/ 3600, m = (t ~/ 60) % 60, s = t % 60;
  return h > 0
      ? '${h}h ${m}m'
      : m > 0
      ? '${m}m ${s}s'
      : '${s}s';
}

class SubRow {
  SubRow(this.type, this.desc, this.done);
  final String type;
  final String desc;
  final bool done;
  int n = 0;
  int started = 1 << 62;
  int ended = 0;
  num? tokens;
  String act = '';

  String get label => n > 1 ? '$type (+${n - 1})' : type;
  int elapsed(int now) => ((done && ended > 0) ? ended : now) - started;
}

/// Same grouping as the web (`web/js/subagents.js`): same type + desc +
/// status merge into "(+n)", running first, finished ones linger 60 s.
List<SubRow> subRows(List<Json> subs, int now) {
  final groups = <String, SubRow>{};
  for (final x in subs) {
    final done = x['status'] == 'done';
    final ended = (x['ended'] as num?)?.toInt() ?? 0;
    if (done && ended > 0 && now - ended > _keepDoneMs) continue;
    final type = '${x['type'] ?? 'agent'}';
    final desc = '${x['desc'] ?? ''}';
    final g = groups.putIfAbsent(
      '$done|$type|$desc',
      () => SubRow(type, desc, done),
    );
    g.n++;
    final st = (x['started'] as num?)?.toInt() ?? now;
    if (st < g.started) g.started = st;
    if (ended > g.ended) g.ended = ended;
    final tk = x['tokens'];
    if (tk is num) g.tokens = (g.tokens ?? 0) + tk;
    final tool = x['tool'];
    if (g.act.isEmpty && tool is Map) {
      g.act = '${tool['name'] ?? ''} ${tool['label'] ?? ''}'.trim();
    }
  }
  final out = groups.values.toList()
    ..sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return a.started.compareTo(b.started);
    });
  return out;
}

/// Compact list of the session's subagents above the message box.
class ChatSubagentsPanel extends StatefulWidget {
  const ChatSubagentsPanel({super.key, required this.subs});

  final List<Json> subs;

  @override
  State<ChatSubagentsPanel> createState() => _ChatSubagentsPanelState();
}

class _ChatSubagentsPanelState extends State<ChatSubagentsPanel> {
  Timer? _tick;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.subs.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = subRows(widget.subs, now);
    if (rows.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    final running = rows.where((r) => !r.done).fold(0, (a, r) => a + r.n);
    final small = GhinaType.caption.copyWith(color: g.textMuted);
    return Container(
      key: const ValueKey('chat-subagents'),
      margin: const EdgeInsets.fromLTRB(GhinaSpace.md, 4, GhinaSpace.md, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: g.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: g.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Subagent${running > 0 ? ' ($running jalan)' : ''}',
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final r in rows)
                      Opacity(
                        opacity: r.done ? 0.55 : 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                r.done ? Icons.check_rounded : Icons.circle,
                                size: r.done ? 14 : 8,
                                color: r.done
                                    ? GhinaColors.green.base
                                    : GhinaColors.orange.base,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.label,
                                style: GhinaType.bodyS
                                    .w(800)
                                    .copyWith(color: g.textPrimary),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  r.done
                                      ? (r.desc.isEmpty ? 'selesai' : r.desc)
                                      : (r.act.isNotEmpty ? r.act : r.desc),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GhinaType.bodyS.copyWith(
                                    color: g.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                [
                                  fmtSubElapsed(r.elapsed(now)),
                                  if (r.tokens != null)
                                    '↓ ${fmtSubTokens(r.tokens)}',
                                ].join(' · '),
                                style: small,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
