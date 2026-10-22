import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import 'kantor_feed.dart';

/// Background subagents the daemon reports for a session (`bgAgents`), else the running ones in `subs`.
int kantorBgAgents(Json sess) {
  final n = sess['bgAgents'];
  if (n is num) return n.toInt();
  return asJsonList(sess['subs']).where((x) => x['status'] != 'done').length;
}

/// What "Hentikan" should send: `esc` (main agent only) or `stop-all` (also background subagents).
/// Without background subagents it is `esc` straight away; null means the user backed out.
Future<String?> askStopMode(BuildContext context, Json sess) async {
  final n = kantorBgAgents(sess);
  if (n <= 0) return 'esc';
  final busy = sess['status'] == 'working' || sess['status'] == 'starting';
  return showChunkyBottomSheet<String>(
    context,
    title: 'Hentikan sesi ini?',
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agen utama ${busy ? 'sibuk' : 'idle'} - $n subagent masih jalan di latar.',
          style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
        ),
        GhinaSpace.gapMd,
        ChunkyTile(
          title: 'Hentikan semua (termasuk subagent)',
          subtitle:
              'Efek samping: auto-reply artifact dimatikan untuk sisa sesi ini.',
          showChevron: false,
          onTap: () => Navigator.of(c).pop('stop-all'),
        ),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyTile(
          title: 'Hanya agen utama',
          showChevron: false,
          onTap: () => Navigator.of(c).pop('esc'),
        ),
      ],
    ),
  );
}
