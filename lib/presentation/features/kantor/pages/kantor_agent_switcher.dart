import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import 'kantor_complex_agent_switcher.dart';
import '../codex/kantor_codex.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_agent_rank.dart';
import '../session/kantor_feed.dart';
import '../session/kantor_konteks.dart';
import '../session/kantor_label.dart';
import '../session/start_shift_sheet.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Pencari cepat agen (tahan/ketuk judul chat, atau tombol "Pindah agen" di
/// kantor). Satu daftar gabungan semua agen dari semua kantor dan koneksi
/// server tersimpan, dibagi: "Perlu tindakan", "Terakhir dibuka", "Bekerja",
/// "Semua agen · N", lalu "Libur" (role kantor ini yang belum shift; ketuk
/// untuk mulai shift). Kolom cari ada di bawah (zona jempol); ketik untuk
/// menyaring nama agen / kantor / mesin / label, Enter membuka hasil teratas.
/// Agen berlabel menampilkan stiker label; tahan baris agen untuk memberi atau
/// mengubah label.
Future<void> showKantorAgentSwitcher(
  BuildContext context, {
  required String officeId,
  String? currentSid,
  String? tab,
}) {
  return showChunkyBottomSheet<void>(
    context,
    title: 'Pindah agen',
    builder: (sheet) => _AgentSwitcher(
      officeId: officeId,
      currentSid: currentSid,
      tab: tab,
      onClose: () => Navigator.pop(sheet),
    ),
  );
}

/// Satu baris daftar: agen hidup, atau role libur (belum shift).
typedef _Item = ({KantorRankedAgent? agent, Json? role});

class _AgentSwitcher extends ConsumerStatefulWidget {
  const _AgentSwitcher({
    required this.officeId,
    required this.currentSid,
    required this.onClose,
    this.tab,
  });

  final String officeId;
  final String? currentSid;
  final String? tab;
  final VoidCallback onClose;

  @override
  ConsumerState<_AgentSwitcher> createState() => _AgentSwitcherState();
}

class _AgentSwitcherState extends ConsumerState<_AgentSwitcher> {
  String _query = '';
  String? _opening;
  String? _error;

  /// Hasil teratas saat ini, untuk Enter.
  _Item? _top;

  bool _isCurrent(KantorRankedAgent a) =>
      a.active && a.officeId == widget.officeId && a.sid == widget.currentSid;

  Future<void> _open(KantorRankedAgent a) async {
    if (_opening != null) return;
    if (_isCurrent(a)) return widget.onClose();
    setState(() {
      _opening = a.identity;
      _error = null;
    });
    try {
      await kantorOpenRankedAgent(
        context,
        a,
        tab: widget.tab,
        beforeGo: widget.onClose,
      );
    } catch (_) {
      if (!mounted) return;
      final where = a.connectionName.isEmpty ? a.officeName : a.connectionName;
      setState(
        () => _error =
            'Tidak bisa membuka $where. Periksa koneksi lalu coba lagi.',
      );
      if (!a.active) ref.invalidate(kantorComplexStateProvider(a.connection));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _startShift(KantorOfficeFeed feed, Json role) async {
    final api = ref.read(kantorApiProvider);
    final sid = await showStartShiftSheet(
      context,
      feed: feed,
      actions: api == null ? null : KantorActions(api),
      role: role,
    );
    if (sid == null || !mounted) return;
    final active = ref.read(kantorActiveComplexProvider);
    await _open(
      KantorRankedAgent(
        connection: active?.id ?? '',
        connectionName: active?.name ?? '',
        active: true,
        office: {'id': widget.officeId, 'name': feed.office?['name']},
        session: {'sid': sid, 'status': 'starting'},
      ),
    );
  }

  void _tap(KantorOfficeFeed feed, _Item item) {
    if (item.agent != null) {
      _open(item.agent!);
    } else if (item.role != null) {
      _startShift(feed, item.role!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(kantorOfficeFeedProvider(widget.officeId));
    final mq = MediaQuery.of(context);
    // tinggi tetap: daftar bisa digulir sampai bawah dan kolom cari tetap di
    // bawah, juga saat keyboard terbuka
    final height = math.max(
      220.0,
      (mq.size.height - mq.viewInsets.bottom - mq.padding.top) * .78 - 72,
    );
    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: feed,
        builder: (context, _) => _body(context, feed),
      ),
    );
  }

  /// Agen: peringkat semua koneksi, ditambah sesi kantor ini dari feed bila
  /// state koneksi aktif belum ada (mis. baru dibuka atau gagal dimuat).
  List<KantorRankedAgent> _agents(KantorOfficeFeed feed) {
    final ranking = ref.watch(kantorAgentRankProvider);
    final recent = ref.watch(kantorRecentComplexChatsProvider);
    final active = ref.watch(kantorActiveComplexProvider);
    final hasOffice = ranking.sources.any(
      (s) =>
          s.active &&
          asJsonList(
            s.state['offices'],
          ).any((o) => '${o['id']}' == widget.officeId),
    );
    if (hasOffice || feed.office == null) return ranking.agents;
    final sessions = [
      for (final s in feed.sessions)
        if (s['status'] != 'ended')
          {
            ...s,
            if (s['look'] is! Map && feed.role(s['role'] as String?) != null)
              'look': {
                ...feed.role(s['role'] as String?)!,
                'name': sessionName(feed, s),
              },
          },
    ];
    final extra = (
      connection: active?.id ?? '',
      connectionName: active?.name ?? '',
      active: true,
      state: <String, dynamic>{
        'offices': [
          {
            'id': widget.officeId,
            'name': feed.office?['name'] ?? widget.officeId,
            'sessions': sessions,
          },
        ],
      },
    );
    return kantorRankAgents([...ranking.sources, extra], recent);
  }

  Widget _body(BuildContext context, KantorOfficeFeed feed) {
    final g = context.ghina;
    final ranking = ref.watch(kantorAgentRankProvider);
    final agents = _agents(feed);
    final live = feed.sessions.where((s) => s['status'] != 'ended');
    final off = [
      for (final r in feed.roles)
        if (r['archived'] != true && !live.any((s) => s['role'] == r['id'])) r,
    ];

    if (agents.isEmpty && off.isEmpty) {
      if (feed.loading || ranking.loading) return const KantorLoading();
      if (feed.error != null && feed.office == null) {
        return KantorErrorView(error: feed.error!, onRetry: feed.load);
      }
    }

    final q = _query.trim().toLowerCase();
    final sections = <(String, List<_Item>, Color?)>[];
    if (q.isEmpty) {
      final action = agents.where((a) => a.needsAction).toList();
      final recent =
          agents.where((a) => !a.needsAction && a.recent >= 0).toList()
            ..sort((a, b) => a.recent - b.recent);
      final recentTop = recent.take(5).toList();
      final working = agents
          .where((a) => a.working && !recentTop.contains(a))
          .toList();
      final shown = {...action, ...recentTop, ...working};
      final rest = agents.where((a) => !shown.contains(a)).toList();
      _Item it(KantorRankedAgent a) => (agent: a, role: null);
      sections.addAll([
        (
          'PERLU TINDAKAN  ${action.length}',
          action.map(it).toList(),
          Theme.of(context).colorScheme.error,
        ),
        (
          'TERAKHIR DIBUKA  ${recentTop.length}',
          recentTop.map(it).toList(),
          null,
        ),
        ('BEKERJA  ${working.length}', working.map(it).toList(), null),
        ('SEMUA AGEN · ${agents.length}', rest.map(it).toList(), null),
        (
          'LIBUR  ${off.length}',
          [for (final r in off) (agent: null, role: r)],
          null,
        ),
      ]);
    } else {
      // pencarian: satu daftar, nama yang cocok di depan, lalu urutan peringkat
      int score(KantorRankedAgent a) {
        final n = a.name.toLowerCase();
        return n.startsWith(q) ? 0 : (n.contains(q) ? 1 : 2);
      }

      final hits =
          [
            for (final (i, a) in agents.indexed)
              if (a.haystack.contains(q) ||
                  a.officeName.toLowerCase().contains(q))
                (i, a),
          ]..sort((x, y) {
            final s = score(x.$2) - score(y.$2);
            return s != 0 ? s : x.$1 - y.$1;
          });
      final offHits = off.where(
        (r) => '${r['name']} ${r['title'] ?? ''}'.toLowerCase().contains(q),
      );
      final items = <_Item>[
        for (final (_, a) in hits) (agent: a, role: null),
        for (final r in offHits) (agent: null, role: r),
      ];
      sections.add(('HASIL  ${items.length}', items, null));
    }
    _top = sections.expand((s) => s.$2).firstOrNull;

    final rows = <Widget>[];
    for (final (title, items, color) in sections) {
      if (items.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(
            top: GhinaSpace.md,
            bottom: GhinaSpace.xs,
          ),
          child: Text(
            title,
            style: GhinaType.overline.copyWith(color: color ?? g.textSecondary),
          ),
        ),
      );
      for (final item in items) {
        rows.add(
          item.agent != null
              ? _AgentRow(
                  agent: item.agent!,
                  current: _isCurrent(item.agent!),
                  opening: _opening == item.agent!.identity,
                  onTap: _opening != null ? null : () => _tap(feed, item),
                  onLongPress: () => showKantorLabelMenu(
                    context,
                    item.agent!.session,
                    name: item.agent!.name,
                    officeId: item.agent!.officeId,
                    connection: item.agent!.active
                        ? null
                        : item.agent!.connection,
                    feed:
                        item.agent!.active &&
                            item.agent!.officeId == widget.officeId
                        ? feed
                        : null,
                  ),
                )
              : _OffRow(
                  role: item.role!,
                  onTap: _opening != null ? null : () => _tap(feed, item),
                ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('agent-switcher-list'),
            children: [
              if (rows.isEmpty)
                EmptyState(
                  title: q.isEmpty ? 'Belum ada agen' : 'Tidak ada yang cocok',
                  compact: true,
                ),
              ...rows,
              for (final p in ranking.offline)
                Padding(
                  padding: const EdgeInsets.only(top: GhinaSpace.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 18,
                        color: g.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${p.name} tidak terhubung',
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(kantorComplexStateProvider(p.id)),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: GhinaSpace.sm),
            ],
          ),
        ),
        if (_opening != null) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _error!,
              style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
            ),
          ),
        const SizedBox(height: GhinaSpace.sm),
        // kolom cari di bawah: dekat jempol; Enter = buka hasil teratas
        ChunkyTextField(
          key: const ValueKey('agent-switcher-search'),
          hint: 'Ketik nama agen / kantor…',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.go,
          textCapitalization: TextCapitalization.none,
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (_) {
            final top = _top;
            if (top != null) _tap(feed, top);
          },
        ),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.current,
    required this.opening,
    required this.onTap,
    this.onLongPress,
  });

  final KantorRankedAgent agent;
  final bool current;
  final bool opening;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final a = agent;
    final job = '${a.look['title'] ?? ''}';
    final ago = agoText(a.lastSeen);
    final what = a.needsAction && !a.waiting
        ? (a.actionLabel == 'login' ? 'perlu login' : 'perlu tindakan')
        : a.doing == 'diam' && ago.isNotEmpty
        ? 'diam $ago'
        : a.doing;
    final title = job.isEmpty ? a.name : '${a.name} · $job';
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: ChunkyTile(
        key: ValueKey('switch-${a.identity}'),
        leading: KantorSprite(look: a.look, size: 36),
        title: title,
        // stiker label (maks 2 baris) di bawah nama agen
        titleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.h3.copyWith(color: context.ghina.textPrimary),
            ),
            KantorSessionLabel(session: a.session, maxLines: 2, size: 14),
          ],
        ),
        subtitle: [
          a.officeName,
          if (!a.active && a.connectionName.isNotEmpty) a.connectionName,
          kantorKonteksSubtitle(a.session, what, withLabel: false),
        ].join(' · '),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.codex) ...[
              const KantorCodexBadge(),
              const SizedBox(width: 4),
            ],
            if (opening)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (current)
              const Icon(Icons.check_rounded)
            else if (a.needsAction)
              ChunkyPill(
                label: a.actionLabel,
                color: a.actionLabel == 'login'
                    ? GhinaColors.yellow
                    : GhinaColors.red,
                soft: true,
              )
            else if (a.working)
              Icon(
                Icons.circle,
                size: 10,
                color: GhinaColors.blue.base,
                semanticLabel: 'bekerja',
              ),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

/// Role kantor ini yang belum shift: ketuk untuk mulai shift.
class _OffRow extends StatelessWidget {
  const _OffRow({required this.role, required this.onTap});

  final Json role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final job = '${role['title'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: ChunkyTile(
        key: ValueKey('switch-off-${role['id']}'),
        leading: Opacity(
          opacity: 0.55,
          child: KantorSprite(look: role, size: 36),
        ),
        title: job.isEmpty ? '${role['name']}' : '${role['name']} · $job',
        subtitle: 'libur · ketuk untuk mulai shift',
        trailing: kantorEngineIsCodex(null, role)
            ? const KantorCodexBadge()
            : null,
        onTap: onTap,
      ),
    );
  }
}
