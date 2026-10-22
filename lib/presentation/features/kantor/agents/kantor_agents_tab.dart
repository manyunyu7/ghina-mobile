import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import '../dm/kantor_dm_screen.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_feed.dart';
import '../session/permission_card.dart';
import '../roles/kantor_new_agent_sheet.dart';
import '../session/start_shift_sheet.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Agents of one office, grouped by what needs the user: waiting (permission
/// or question), working, idle, and roles off shift.
class KantorAgentsTab extends ConsumerWidget {
  const KantorAgentsTab({super.key, required this.officeId});

  final String officeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(kantorOfficeFeedProvider(officeId));
    final api = ref.watch(kantorApiProvider);
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        if (feed.loading) return const KantorLoading();
        if (feed.error != null && feed.office == null) {
          return KantorErrorView(error: feed.error!, onRetry: feed.load);
        }
        return RefreshIndicator(
          onRefresh: feed.load,
          child: _AgentList(
            feed: feed,
            actions: api == null ? null : KantorActions(api),
          ),
        );
      },
    );
  }
}

class _Row {
  const _Row({
    required this.look,
    required this.name,
    required this.job,
    required this.sub,
    this.session,
    this.role,
    this.boss = false,
  });
  final Json look;
  final String name;
  final String job;
  final String sub;
  final Json? session;
  final Json? role;
  final bool boss;
}

class _AgentList extends StatelessWidget {
  const _AgentList({required this.feed, required this.actions});

  final KantorOfficeFeed feed;
  final KantorActions? actions;

  void _toast(BuildContext context, String m) => showToastBadge(
    context,
    message: m,
    icon: Icons.error_outline_rounded,
    color: GhinaColors.red,
    tag: 'kantor-agents',
  );

  void _open(BuildContext context, String sid) =>
      context.push('/kantor/o/${feed.officeId}/s/$sid');

  Future<void> _decide(BuildContext context, Json item, String behavior) async {
    try {
      await actions?.decide('${item['id']}', behavior);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _answer(BuildContext context, Json item, int n) async {
    try {
      await actions?.answerAsk(item, n);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
    }
  }

  Future<void> _startShift(BuildContext context, Json role) async {
    final sid = await showStartShiftSheet(
      context,
      feed: feed,
      actions: actions,
      role: role,
    );
    if (sid != null && context.mounted) _open(context, sid);
  }

  Future<void> _newAgent(BuildContext context) =>
      showKantorNewAgentSheet(context, officeId: feed.officeId);

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final live = feed.sessions.where((s) => s['status'] != 'ended').toList();
    final waiting = <_Row>[];
    final working = <_Row>[];
    final idle = <_Row>[];
    final off = <Json>[];
    final inboxSids = {for (final i in feed.inbox) i['sid']};

    void put(
      Json s,
      Json look,
      String name,
      String job,
      bool boss,
      Json? role,
    ) {
      final w = s['waiting'] is Map ? asJson(s['waiting']) : null;
      final status = s['status'];
      final room = feed.roomName(s['room'] as String?);
      _Row row(String sub) => _Row(
        look: look,
        name: name,
        job: job,
        sub: sub,
        session: s,
        role: role,
        boss: boss,
      );
      if (w != null || status == 'waiting') {
        if (inboxSids.contains(s['sid'])) return; // shown as a card above
        final what = w?['tool'] == 'AskUserQuestion'
            ? 'bertanya'
            : 'minta izin';
        waiting.add(
          row('$what: ${clip('${w?['summary'] ?? w?['tool'] ?? ''}', 60)}'),
        );
      } else if (status == 'working' || status == 'starting') {
        final t = toolFull(s['tool']);
        working.add(
          row(
            t.isNotEmpty
                ? t
                : status == 'starting'
                ? 'baru datang'
                : 'sedang bekerja',
          ),
        );
      } else {
        final since = agoText(s['lastSeen']);
        idle.add(
          row(
            'diam ${since.isEmpty ? 'baru saja' : since}${room.isEmpty ? '' : ' - $room'}',
          ),
        );
      }
    }

    for (final r in feed.roles.where((r) => r['archived'] != true)) {
      final ss = live.where((s) => s['role'] == r['id']).toList();
      if (ss.isEmpty) {
        off.add(r);
        continue;
      }
      for (final s in ss) {
        final slot = (s['slot'] as num?)?.toInt() ?? 0;
        final boss = r['isMgr'] == true && slot == 0;
        put(
          s,
          r,
          '${r['name']}${slot > 0 ? ' #${slot + 1}' : ''}',
          boss ? '' : '${r['title'] ?? ''}',
          boss,
          r,
        );
      }
    }
    for (final s in live.where((s) => s['role'] == null)) {
      put(
        s,
        KantorSprite.guestLook('${s['sid']}'),
        sessionName(feed, s),
        '',
        false,
        null,
      );
    }

    Widget group(String title, int n, List<Widget> body, {Color? color}) =>
        n == 0
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                  child: Row(
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: GhinaType.overline.copyWith(
                          color: color ?? g.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$n',
                        style: GhinaType.overline.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                ),
                ...body,
              ],
            ),
          );

    Widget tile(_Row r) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: _AgentTile(
        row: r,
        onTap: () => _open(context, '${r.session!['sid']}'),
      ),
    );

    final waitCards = [
      for (final i in feed.inbox)
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: KantorPermissionCard(
            item: i,
            who: i['who'] as String?,
            onDecide: (b) => _decide(context, i, b),
            onAnswer: (n) => _answer(context, i, n),
            onOpen: i['tool'] == 'AskUserQuestion' && i['sid'] != null
                ? () => _open(context, '${i['sid']}')
                : null,
          ),
        ),
    ];

    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.page,
            GhinaSpace.page,
            96,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: ChunkyButton(
                label: 'Obrolan agen',
                icon: Icons.forum_outlined,
                variant: ChunkyButtonVariant.outline,
                expand: true,
                onPressed: () => openKantorDm(context, officeId: feed.officeId),
              ),
            ),
            if (live.isEmpty && feed.inbox.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
                child: EmptyState(
                  title: 'Belum ada sesi berjalan',
                  message:
                      'Mulai agen baru dari role yang ada, atau buat role.',
                  actionLabel: 'Agen baru',
                  onAction: () => _newAgent(context),
                  compact: true,
                ),
              ),
            group(
              'Menunggu kamu',
              waiting.length + feed.inbox.length,
              [...waitCards, ...waiting.map(tile)],
              color: GhinaColors.orange.edge,
            ),
            group('Bekerja', working.length, working.map(tile).toList()),
            group('Idle', idle.length, idle.map(tile).toList()),
            if (off.isNotEmpty)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(
                        'LIBUR',
                        style: GhinaType.overline.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${off.length}',
                        style: GhinaType.overline.copyWith(color: g.textMuted),
                      ),
                    ],
                  ),
                  children: [
                    for (final r in off)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                        child: _AgentTile(
                          row: _Row(
                            look: r,
                            name: '${r['name']}',
                            job: '${r['title'] ?? ''}',
                            sub:
                                'Ketuk untuk mulai shift - ${feed.roomName(r['room'] as String?)}',
                            role: r,
                            boss: r['isMgr'] == true,
                          ),
                          onTap: () => _startShift(context, r),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Positioned(
          right: GhinaSpace.page,
          bottom: GhinaSpace.page,
          child: FloatingActionButton.extended(
            heroTag: 'kantor-agent-add',
            onPressed: () => _newAgent(context),
            icon: const Icon(Icons.add),
            label: const Text('Agen baru'),
          ),
        ),
      ],
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({required this.row, required this.onTap});

  final _Row row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = row.session;
    final waiting =
        s != null && (s['waiting'] != null || s['status'] == 'waiting');
    final working =
        s != null && (s['status'] == 'working' || s['status'] == 'starting');
    final dot = s == null
        ? g.textMuted
        : waiting
        ? GhinaColors.orange.base
        : working
        ? GhinaColors.green.base
        : g.textMuted;
    return ChunkyCard(
      tinted: waiting ? GhinaColors.orange : null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: GhinaSpace.sm,
      ),
      child: Row(
        children: [
          Opacity(
            opacity: s == null ? 0.55 : 1,
            child: KantorSprite(look: row.look, size: 48),
          ),
          const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    if (row.job.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          row.job,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ),
                    ],
                    if (kantorEngineIsCodex(row.session, row.role)) ...[
                      const SizedBox(width: 6),
                      const KantorCodexBadge(),
                    ],
                    if (row.boss) ...[
                      const SizedBox(width: 6),
                      const ChunkyPill(
                        label: 'bos',
                        color: GhinaColors.purple,
                        soft: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  row.sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.sm),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
