import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../session/kantor_feed.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Global "Agen aktif": every unfinished session in every office, from
/// `GET /api/state` (kept live by [kantorStateProvider]).

/// One live session together with the office it belongs to.
class KantorAgentRef {
  const KantorAgentRef(this.office, this.session);

  final Json office;
  final Json session;

  String get sid => '${session['sid']}';
  String get officeId => '${office['id']}';
  bool get waiting =>
      session['waiting'] != null || session['status'] == 'waiting';
  bool get working =>
      session['status'] == 'working' || session['status'] == 'starting';

  /// 0 waiting for the owner, 1 working, 2 idle.
  int get rank => waiting ? 0 : (working ? 1 : 2);

  Json get look => session['look'] is Map
      ? asJson(session['look'])
      : KantorSprite.guestLook(sid);

  String get name {
    final look = session['look'];
    if (look is Map && look['name'] != null) return '${look['name']}';
    final t = '${session['title'] ?? ''}';
    return t.isNotEmpty && t != 'Sesi belum terhubung'
        ? kantorShort(t, 34)
        : 'Sesi manual';
  }

  bool get codex => session['engine'] == 'codex';

  String get model {
    final m = session['model'];
    return m == null || '$m'.isEmpty ? '' : modelLabel(m);
  }

  int get subs => (session['bgAgents'] as num?)?.toInt() ?? 0;

  /// What it is doing now: the permission it asks for, the tool in use, or its title.
  String get doing {
    final w = session['waiting'];
    if (w is Map) {
      final what = w['tool'] == 'AskUserQuestion' ? 'bertanya' : 'minta izin';
      return '$what: ${clip('${w['summary'] ?? w['tool'] ?? ''}', 60)}';
    }
    final t = toolFull(session['tool']);
    if (t.isNotEmpty) return clip(t, 60);
    final look = session['look'];
    final title = '${session['title'] ?? ''}';
    if (look is Map &&
        title.isNotEmpty &&
        !title.startsWith('${look['name']}') &&
        title != 'Sesi belum terhubung') {
      return clip(title, 60);
    }
    return working ? 'sedang bekerja' : 'diam';
  }

  String get meta {
    final room = '${session['room'] ?? ''}';
    final ago = agoText(session['lastSeen']);
    return [
      '${office['name']}',
      if (room.isNotEmpty) room,
      if (ago.isNotEmpty) ago,
    ].join(' · ');
  }

  String get haystack => [
    name,
    session['title'],
    (session['look'] as Map?)?['title'],
    office['name'],
    session['room'],
    session['model'],
    codex ? 'codex' : 'claude',
    toolFull(session['tool']),
    (session['waiting'] as Map?)?['summary'],
  ].join(' ').toLowerCase();
}

/// All unfinished sessions, ordered: waiting, working, idle (then most recent).
List<KantorAgentRef> kantorActiveAgents(Json state) {
  final out = <KantorAgentRef>[
    for (final o in asJsonList(state['offices']))
      for (final s in asJsonList(o['sessions']))
        if (s['status'] != 'ended') KantorAgentRef(o, s),
  ];
  out.sort((a, b) {
    final r = a.rank - b.rank;
    return r != 0
        ? r
        : '${b.session['lastSeen'] ?? ''}'.compareTo(
            '${a.session['lastSeen'] ?? ''}',
          );
  });
  return out;
}

String kantorAgentPath(String officeId, String sid, {String? tab}) =>
    '/kantor/o/${Uri.encodeComponent(officeId)}/s/${Uri.encodeComponent(sid)}'
    '${tab != null ? '?tab=$tab' : ''}';

/// Opens a session straight from anywhere (no office page in between).
/// [replace] swaps the current page, as when switching between agents.
void openKantorAgent(
  BuildContext context,
  KantorAgentRef a, {
  String? tab,
  bool replace = false,
}) {
  final path = kantorAgentPath(a.officeId, a.sid, tab: tab);
  replace ? context.go(path) : context.push(path);
}

/// Jumps to the next (+1) or previous (-1) active agent, in a stable order
/// (office order, then session order) so repeated swipes cycle predictably.
bool kantorStepAgent(
  BuildContext context, {
  required String currentSid,
  required int dir,
  String? tab,
}) {
  final state = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(kantorStateProvider).value;
  if (state == null) return false;
  final list = [
    for (final o in asJsonList(state['offices']))
      for (final s in asJsonList(o['sessions']))
        if (s['status'] != 'ended') KantorAgentRef(o, s),
  ];
  if (list.length < 2) return false;
  final i = list.indexWhere((a) => a.sid == currentSid);
  final next = list[(i < 0 ? 0 : i + dir + list.length) % list.length];
  if (next.sid == currentSid) return false;
  openKantorAgent(context, next, tab: tab, replace: true);
  return true;
}

/// Pinned session ids, kept on the device.
class KantorPinnedAgents extends Notifier<Set<String>> {
  static const _key = 'kantor.pinned_agents';

  @override
  Set<String> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    try {
      final l = (await SharedPreferences.getInstance()).getStringList(_key);
      if (l != null && ref.mounted) state = {...state, ...l};
    } catch (_) {}
  }

  Future<void> toggle(String sid) async {
    state = state.contains(sid) ? ({...state}..remove(sid)) : {...state, sid};
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        state.toList(),
      );
    } catch (_) {}
  }
}

final kantorPinnedAgentsProvider =
    NotifierProvider<KantorPinnedAgents, Set<String>>(KantorPinnedAgents.new);

Color _dotColor(BuildContext c, KantorAgentRef a) => a.waiting
    ? GhinaColors.orange.base
    : a.working
    ? GhinaColors.green.base
    : c.ghina.textMuted;

/// One agent: avatar, name, engine/model, what it does, where, with a small
/// Terminal button and a pin.
class KantorActiveAgentTile extends ConsumerWidget {
  const KantorActiveAgentTile({
    super.key,
    required this.agent,
    required this.onOpen,
    this.current = false,
  });

  final KantorAgentRef agent;
  final void Function(String? tab) onOpen;
  final bool current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final a = agent;
    final pinned = ref.watch(kantorPinnedAgentsProvider).contains(a.sid);
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: ChunkyCard(
        key: ValueKey('agent-${a.sid}'),
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.md,
          GhinaSpace.sm,
          GhinaSpace.xs,
          GhinaSpace.sm,
        ),
        depth: GhinaDepth.sm,
        tinted: current ? GhinaColors.blue : null,
        onTap: () => onOpen(null),
        semanticLabel: 'Buka ${a.name}',
        child: Row(
          children: [
            KantorSprite(look: a.look, size: 40),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        a.name,
                        style: GhinaType.body.w(800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      a.codex
                          ? const KantorCodexBadge()
                          : const ChunkyPill(
                              label: 'Claude',
                              color: GhinaColors.purple,
                              soft: true,
                              uppercase: false,
                            ),
                      if (a.model.isNotEmpty)
                        Text(
                          a.model,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    a.doing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(
                      color: a.waiting
                          ? GhinaColors.orange.edge
                          : g.textPrimary,
                    ),
                  ),
                  Text(
                    a.subs > 0 ? '${a.meta} · ${a.subs} subagent' : a.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.circle, size: 11, color: _dotColor(context, a)),
            IconButton(
              tooltip: 'Terminal',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.terminal_rounded, size: 20),
              onPressed: () => onOpen('terminal'),
            ),
            IconButton(
              key: ValueKey('pin-${a.sid}'),
              tooltip: pinned ? 'Lepas sematan' : 'Sematkan',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                pinned ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 22,
                color: pinned ? GhinaColors.orange.base : g.textMuted,
              ),
              onPressed: () =>
                  ref.read(kantorPinnedAgentsProvider.notifier).toggle(a.sid),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouped, filterable list: pinned, waiting, working, idle.
class KantorActiveAgentsList extends ConsumerWidget {
  const KantorActiveAgentsList({
    super.key,
    required this.state,
    required this.query,
    required this.onOpen,
    this.currentSid,
    this.shrinkWrap = false,
  });

  final Json state;
  final String query;
  final void Function(KantorAgentRef agent, String? tab) onOpen;
  final String? currentSid;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final pins = ref.watch(kantorPinnedAgentsProvider);
    final q = query.trim().toLowerCase();
    final all = kantorActiveAgents(
      state,
    ).where((a) => q.isEmpty || a.haystack.contains(q)).toList();
    final pinned = all.where((a) => pins.contains(a.sid)).toList();
    final rest = all.where((a) => !pins.contains(a.sid)).toList();
    final groups = <(String, List<KantorAgentRef>, Color?)>[
      ('Disematkan', pinned, null),
      (
        'Menunggu kamu',
        rest.where((a) => a.rank == 0).toList(),
        GhinaColors.orange.edge,
      ),
      ('Bekerja', rest.where((a) => a.rank == 1).toList(), null),
      ('Idle', rest.where((a) => a.rank == 2).toList(), null),
    ].where((e) => e.$2.isNotEmpty).toList();
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? null : const AlwaysScrollableScrollPhysics(),
      padding: shrinkWrap
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.xs,
              GhinaSpace.page,
              GhinaSpace.xxl,
            ),
      children: [
        if (all.isEmpty)
          EmptyState(
            title: q.isEmpty ? 'Belum ada agen aktif' : 'Tidak ada yang cocok',
            compact: true,
          ),
        for (final (title, list, color) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: GhinaSpace.md,
              bottom: GhinaSpace.xs,
            ),
            child: Text(
              '${title.toUpperCase()}  ${list.length}',
              style: GhinaType.overline.copyWith(
                color: color ?? g.textSecondary,
              ),
            ),
          ),
          for (final a in list)
            KantorActiveAgentTile(
              agent: a,
              current: a.sid == currentSid,
              onOpen: (tab) => onOpen(a, tab),
            ),
        ],
      ],
    );
  }
}

/// Full page: every active agent, searchable. Tap = open the chat.
class KantorActiveAgentsPage extends ConsumerStatefulWidget {
  const KantorActiveAgentsPage({super.key});

  @override
  ConsumerState<KantorActiveAgentsPage> createState() =>
      _KantorActiveAgentsPageState();
}

class _KantorActiveAgentsPageState
    extends ConsumerState<KantorActiveAgentsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kantorStateProvider);
    final state = async.value;
    final waiting = state == null
        ? 0
        : kantorActiveAgents(state).where((a) => a.waiting).length;
    return Scaffold(
      backgroundColor: context.ghina.background,
      appBar: AppBar(
        title: Text(
          waiting > 0 ? 'Agen aktif · $waiting menunggu' : 'Agen aktif',
        ),
      ),
      body: state == null
          ? switch (async) {
              AsyncError(:final error) => KantorErrorView(
                error: error,
                onRetry: () => ref.invalidate(kantorStateProvider),
              ),
              _ => const KantorLoading(),
            }
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.sm,
                    GhinaSpace.page,
                    0,
                  ),
                  child: ChunkyTextField(
                    hint: 'Cari agen, kantor, model…',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(kantorStateProvider);
                      await ref.read(kantorStateProvider.future);
                    },
                    child: KantorActiveAgentsList(
                      state: state,
                      query: _query,
                      onOpen: (a, tab) => openKantorAgent(context, a, tab: tab),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

void openKantorActiveAgents(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const KantorActiveAgentsPage()));

/// Top of the Kompleks page: horizontal "Agen aktif" cards (waiting first)
/// with a badge for how many wait for you, and "Lihat semua".
class KantorActiveAgentsStrip extends StatelessWidget {
  const KantorActiveAgentsStrip({super.key, required this.state});

  final Json state;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final all = kantorActiveAgents(state);
    if (all.isEmpty) return const SizedBox.shrink();
    final waiting = all.where((a) => a.waiting).length;
    return Column(
      key: const ValueKey('kantor-active-agents'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // narrow phones and large text: the label gives way, "Lihat semua" stays
            Flexible(
              child: Text(
                'AGEN AKTIF  ${all.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.overline.copyWith(color: g.textSecondary),
              ),
            ),
            if (waiting > 0) ...[
              const SizedBox(width: GhinaSpace.sm),
              Flexible(
                child: ChunkyPill(
                  label: '$waiting menunggu',
                  color: GhinaColors.orange,
                  soft: true,
                  uppercase: false,
                ),
              ),
            ],
            const Spacer(),
            TextButton(
              onPressed: () => openKantorActiveAgents(context),
              child: const Text('Lihat semua'),
            ),
          ],
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: all.length > 12 ? 12 : all.length,
            separatorBuilder: (_, _) => const SizedBox(width: GhinaSpace.sm),
            itemBuilder: (context, i) {
              final a = all[i];
              return SizedBox(
                width: 224,
                child: ChunkyCard(
                  key: ValueKey('strip-${a.sid}'),
                  padding: const EdgeInsets.all(GhinaSpace.sm),
                  depth: GhinaDepth.sm,
                  tinted: a.waiting ? GhinaColors.orange : null,
                  onTap: () => openKantorAgent(context, a),
                  semanticLabel: 'Buka ${a.name}',
                  child: Row(
                    children: [
                      KantorSprite(look: a.look, size: 40),
                      const SizedBox(width: GhinaSpace.sm),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.bodyS.w(800),
                            ),
                            Text(
                              a.doing,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption,
                            ),
                            Text(
                              '${a.office['name']}${a.codex ? ' · Codex' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: _dotColor(context, a),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: GhinaSpace.md),
      ],
    );
  }
}
