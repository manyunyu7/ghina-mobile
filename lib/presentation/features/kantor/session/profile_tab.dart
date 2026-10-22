import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import 'kantor_feed.dart';

Widget _section(BuildContext context, String title, Widget child) {
  final g = context.ghina;
  return Padding(
    padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GhinaType.overline.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapSm,
        child,
      ],
    ),
  );
}

Widget _fact(BuildContext context, String k, String v, {bool mono = false}) {
  final g = context.ghina;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(k, style: GhinaType.bodyS.copyWith(color: g.textMuted)),
        ),
        Expanded(
          child: SelectableText(
            v.isEmpty ? '-' : v,
            style: GhinaType.bodyS.copyWith(
              color: g.textPrimary,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Persona, skills and facts of the session's role (web `sessProfileHTML`).
class KantorProfileTab extends StatelessWidget {
  const KantorProfileTab({super.key, required this.feed, required this.sid});

  final KantorOfficeFeed feed;
  final String sid;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = feed.session(sid);
    if (s == null) return const SizedBox.shrink();
    final r = feed.role(s['role'] as String?);
    final skills = [for (final k in (r?['skills'] as List? ?? const [])) '$k'];
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        if (r == null)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
            child: Text(
              'Sesi ini tidak punya role.',
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          )
        else ...[
          _section(
            context,
            'Kepribadian',
            Text(
              '${r['persona'] ?? ''}'.isEmpty ? '-' : '${r['persona']}',
              style: GhinaType.body.copyWith(color: g.textPrimary, height: 1.4),
            ),
          ),
          if (skills.isNotEmpty)
            _section(
              context,
              'Skills',
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in skills)
                    ChunkyPill(
                      label: k,
                      color: GhinaColors.blue,
                      soft: true,
                      uppercase: false,
                    ),
                ],
              ),
            ),
        ],
        _section(
          context,
          'Sesi',
          ChunkyCard(
            child: Column(
              children: [
                _fact(
                  context,
                  'Status',
                  kantorStatusLabel['${s['status']}'] ?? '${s['status']}',
                ),
                if (kantorEngineIsCodex(s, r))
                  _fact(context, 'Mesin', 'OpenAI Codex'),
                _fact(context, 'Model', kantorSessionModelText(r, s)),
                _fact(context, 'Ruangan', feed.roomName(s['room'] as String?)),
                _fact(context, 'Sedang memakai', toolFull(s['tool'])),
                _fact(context, 'Mulai', agoText(s['startedAt'])),
                _fact(context, 'Folder kerja', '${s['cwd'] ?? ''}', mono: true),
                if (s['worktree'] != null)
                  _fact(context, 'Worktree', '${s['worktree']}', mono: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _elapsed(Object? started) {
  DateTime? t;
  if (started is num) t = DateTime.fromMillisecondsSinceEpoch(started.toInt());
  if (started is String) t = DateTime.tryParse(started);
  if (t == null) return '';
  final sec = DateTime.now().difference(t).inSeconds.clamp(0, 1 << 31);
  return sec < 60 ? '$sec dtk' : '${sec ~/ 60} mnt';
}

/// Workers the session called through the Agent tool (web `subsHTML`).
class KantorSubsTab extends StatelessWidget {
  const KantorSubsTab({super.key, required this.feed, required this.sid});

  final KantorOfficeFeed feed;
  final String sid;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = feed.session(sid);
    if (s == null) return const SizedBox.shrink();
    final subs = asJsonList(s['subs']);
    final running = subs.where((x) => x['status'] != 'done').length;
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        Text(
          'Subagent adalah pekerja sementara yang dipanggil sesi ini lewat tool Agent.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapLg,
        _section(
          context,
          'Subagent ($running jalan, ${subs.length} total)',
          subs.isEmpty
              ? Text(
                  'Tidak ada subagent.',
                  style: GhinaType.body.copyWith(color: g.textMuted),
                )
              : Column(
                  children: [
                    for (final x in subs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                        child: ChunkyCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${x['type'] ?? 'agent'} - ${x['status'] == 'done' ? 'selesai' : 'jalan'} - ${_elapsed(x['started'])}',
                                style: GhinaType.caption
                                    .w(800)
                                    .copyWith(
                                      color: x['status'] == 'done'
                                          ? g.textMuted
                                          : GhinaColors.green.edge,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                clip('${x['desc'] ?? ''}', 140),
                                style: GhinaType.body.copyWith(
                                  color: g.textPrimary,
                                ),
                              ),
                              if (toolText(x['tool']).isNotEmpty)
                                Text(
                                  toolText(x['tool']),
                                  style: GhinaType.caption.copyWith(
                                    color: g.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        _section(
          context,
          'Ke mana subagent pergi',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in const [
                ('Explore', 'ke Perpustakaan, membaca dan mencari di kode'),
                ('Plan', 'ke Ruang Meeting, menyusun rencana'),
                ('review / test', 'ke Lab QA'),
                ('lainnya', 'berdiri di samping meja induknya'),
              ])
                _fact(context, l.$1, l.$2),
            ],
          ),
        ),
      ],
    );
  }
}
