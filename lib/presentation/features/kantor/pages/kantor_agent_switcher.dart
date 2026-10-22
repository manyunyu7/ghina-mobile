import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../agents/kantor_active_agents.dart';
import '../codex/kantor_codex.dart';
import '../kantor_data.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_feed.dart';
import '../session/start_shift_sheet.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Agent picker for one office: jump to another agent's session (replacing the
/// current page), or start a shift for a role that is off duty. A second tab
/// "Semua" lists the active agents of every office.
Future<void> showKantorAgentSwitcher(
  BuildContext context, {
  required String officeId,
  String? currentSid,
  String? tab,
}) {
  final router = GoRouter.of(context);
  return showChunkyBottomSheet<void>(
    context,
    title: 'Pindah agen',
    builder: (sheet) => _AgentSwitcher(
      officeId: officeId,
      currentSid: currentSid,
      onOpen: (sid) {
        Navigator.pop(sheet);
        router.go(kantorAgentPath(officeId, sid, tab: tab));
      },
      onOpenAgent: (a, t) {
        Navigator.pop(sheet);
        router.go(kantorAgentPath(a.officeId, a.sid, tab: t ?? tab));
      },
    ),
  );
}

class _Entry {
  const _Entry({
    required this.look,
    required this.name,
    required this.job,
    required this.sub,
    this.session,
    this.role,
  });
  final Json look;
  final String name;
  final String job;
  final String sub;
  final Json? session;
  final Json? role;
  String? get sid => session == null ? null : '${session!['sid']}';
}

class _AgentSwitcher extends ConsumerStatefulWidget {
  const _AgentSwitcher({
    required this.officeId,
    required this.currentSid,
    required this.onOpen,
    required this.onOpenAgent,
  });

  final String officeId;
  final String? currentSid;
  final void Function(String sid) onOpen;
  final void Function(KantorAgentRef agent, String? tab) onOpenAgent;

  @override
  ConsumerState<_AgentSwitcher> createState() => _AgentSwitcherState();
}

class _AgentSwitcherState extends ConsumerState<_AgentSwitcher> {
  String _query = '';
  bool _all = false;

  Future<void> _startShift(KantorOfficeFeed feed, Json role) async {
    final api = ref.read(kantorApiProvider);
    final sid = await showStartShiftSheet(
      context,
      feed: feed,
      actions: api == null ? null : KantorActions(api),
      role: role,
    );
    if (sid != null && mounted) widget.onOpen(sid);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Kantor ini')),
              ButtonSegment(value: true, label: Text('Semua')),
            ],
            selected: {_all},
            onSelectionChanged: (v) => setState(() {
              _all = v.first;
              _query = '';
            }),
          ),
        ),
        Flexible(child: _all ? _everyOffice() : _thisOffice()),
      ],
    );
  }

  Widget _everyOffice() {
    final state = ref.watch(kantorStateProvider).value;
    if (state == null) {
      return const SizedBox(height: 160, child: KantorLoading());
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChunkyTextField(
          hint: 'Cari agen, kantor, model…',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) => setState(() => _query = v),
        ),
        Flexible(
          child: KantorActiveAgentsList(
            state: state,
            query: _query,
            currentSid: widget.currentSid,
            shrinkWrap: true,
            onOpen: widget.onOpenAgent,
          ),
        ),
      ],
    );
  }

  Widget _thisOffice() {
    final feed = ref.watch(kantorOfficeFeedProvider(widget.officeId));
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        if (feed.loading) {
          return const SizedBox(height: 160, child: KantorLoading());
        }
        if (feed.error != null && feed.office == null) {
          return KantorErrorView(error: feed.error!, onRetry: feed.load);
        }
        return _list(context, feed);
      },
    );
  }

  Widget _list(BuildContext context, KantorOfficeFeed feed) {
    final g = context.ghina;
    final live = feed.sessions.where((s) => s['status'] != 'ended').toList();
    final waiting = <_Entry>[], working = <_Entry>[], idle = <_Entry>[];
    final off = <_Entry>[];

    void put(Json s, Json look, String name, String job, Json? role) {
      _Entry e(String sub) => _Entry(
        look: look,
        name: name,
        job: job,
        sub: sub,
        session: s,
        role: role,
      );
      final w = s['waiting'] is Map ? asJson(s['waiting']) : null;
      final status = s['status'];
      if (w != null || status == 'waiting') {
        final what = w?['tool'] == 'AskUserQuestion'
            ? 'bertanya'
            : 'minta izin';
        waiting.add(
          e('$what: ${clip('${w?['summary'] ?? w?['tool'] ?? ''}', 40)}'),
        );
      } else if (status == 'working' || status == 'starting') {
        final t = toolFull(s['tool']);
        working.add(e(t.isNotEmpty ? t : 'sedang bekerja'));
      } else {
        final since = agoText(s['lastSeen']);
        idle.add(e('diam ${since.isEmpty ? 'baru saja' : since}'));
      }
    }

    for (final r in feed.roles.where((r) => r['archived'] != true)) {
      final ss = live.where((s) => s['role'] == r['id']).toList();
      if (ss.isEmpty) {
        off.add(
          _Entry(
            look: r,
            name: '${r['name']}',
            job: '${r['title'] ?? ''}',
            sub: 'libur · ketuk untuk mulai shift',
            role: r,
          ),
        );
        continue;
      }
      for (final s in ss) {
        final slot = (s['slot'] as num?)?.toInt() ?? 0;
        put(
          s,
          r,
          '${r['name']}${slot > 0 ? ' #${slot + 1}' : ''}',
          '${r['title'] ?? ''}',
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
        null,
      );
    }

    final total = waiting.length + working.length + idle.length + off.length;
    final q = _query.trim().toLowerCase();
    List<_Entry> f(List<_Entry> l) => q.isEmpty
        ? l
        : l
              .where((e) => '${e.name} ${e.job}'.toLowerCase().contains(q))
              .toList();

    Widget group(String title, List<_Entry> l, {Color? color}) => l.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: GhinaSpace.md,
                  bottom: GhinaSpace.xs,
                ),
                child: Text(
                  '${title.toUpperCase()}  ${l.length}',
                  style: GhinaType.overline.copyWith(
                    color: color ?? g.textSecondary,
                  ),
                ),
              ),
              for (final e in l)
                _AgentRow(
                  entry: e,
                  current: e.sid != null && e.sid == widget.currentSid,
                  onTap: () => e.sid != null
                      ? widget.onOpen(e.sid!)
                      : _startShift(feed, e.role!),
                ),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 8)
          ChunkyTextField(
            hint: 'Cari agen…',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _query = v),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (total == 0)
                const EmptyState(title: 'Belum ada agen', compact: true),
              group(
                'Menunggu kamu',
                f(waiting),
                color: GhinaColors.orange.edge,
              ),
              group('Bekerja', f(working)),
              group('Idle', f(idle)),
              group('Libur', f(off)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.entry,
    required this.current,
    required this.onTap,
  });

  final _Entry entry;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = entry.session;
    final waiting =
        s != null && (s['waiting'] != null || s['status'] == 'waiting');
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: ChunkyTile(
        leading: Opacity(
          opacity: s == null ? 0.55 : 1,
          child: KantorSprite(look: entry.look, size: 36),
        ),
        title: entry.job.isEmpty ? entry.name : '${entry.name} · ${entry.job}',
        subtitle: entry.sub,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kantorEngineIsCodex(s, entry.role)) ...[
              const KantorCodexBadge(),
              const SizedBox(width: 4),
            ],
            if (current)
              const Icon(Icons.check_rounded)
            else if (waiting)
              const ChunkyPill(
                label: 'izin',
                color: GhinaColors.orange,
                soft: true,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
