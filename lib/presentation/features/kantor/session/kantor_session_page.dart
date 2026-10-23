import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../agents/kantor_active_agents.dart';
import '../codex/kantor_codex.dart';
import '../pages/kantor_agent_switcher.dart';
import '../pages/kantor_complex_agent_switcher.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import 'chat_tab.dart';
import 'chat_context.dart';
import 'kantor_adopt.dart';
import 'chat_view_prefs.dart';
import 'kantor_actions.dart';
import 'kantor_feed.dart';
import 'profile_tab.dart';
import 'session_pratinjau_tab.dart';
import 'stop_choice.dart';
import 'terminal_tab.dart';

/// One session: header (who, model, status, permission mode) and the tabs
/// Chat | Terminal | Profil | Subagent. Route `/kantor/o/:office/s/:sid`.
class KantorSessionPage extends ConsumerWidget {
  const KantorSessionPage({
    super.key,
    required this.officeId,
    required this.sid,
    this.tab,
  });

  final String officeId;
  final String sid;

  /// Opening tab: chat | terminal | profil | subagent (kept when switching agents).
  final String? tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(kantorOfficeFeedProvider(officeId));
    final api = ref.watch(kantorApiProvider);
    final complex = ref.watch(kantorActiveComplexProvider);
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final s = feed.session(sid);
        if (feed.loading) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                KantorComplexSwitcherButton(
                  officeId: officeId,
                  currentSid: sid,
                  tab: tab,
                ),
              ],
            ),
            body: const KantorLoading(),
          );
        }
        if (s == null) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                KantorComplexSwitcherButton(
                  officeId: officeId,
                  currentSid: sid,
                  tab: tab,
                ),
              ],
            ),
            body: feed.error != null
                ? KantorErrorView(error: feed.error!, onRetry: feed.load)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(GhinaSpace.page),
                      child: Text(
                        'Sesi tidak ditemukan. Mungkin sudah selesai.',
                        textAlign: TextAlign.center,
                        style: GhinaType.body.copyWith(
                          color: context.ghina.textSecondary,
                        ),
                      ),
                    ),
                  ),
          );
        }
        return _SessionScaffold(
          key: ValueKey(
            kantorComplexChatIdentity(
              api == null ? '' : kantorConnectionKey(api.config),
              officeId,
              sid,
            ),
          ),
          complexId: complex?.id,
          feed: feed,
          officeId: officeId,
          sid: sid,
          initialTab: _tabNames
              .indexOf(tab ?? '')
              .clamp(0, _tabNames.length - 1),
          actions: api == null ? null : KantorActions(api),
        );
      },
    );
  }
}

const _tabNames = ['chat', 'terminal', 'profil', 'subagent', 'pratinjau'];

class _SessionScaffold extends ConsumerStatefulWidget {
  const _SessionScaffold({
    super.key,
    this.complexId,
    required this.feed,
    required this.officeId,
    required this.sid,
    required this.initialTab,
    required this.actions,
  });

  final String? complexId;
  final KantorOfficeFeed feed;
  final String officeId;
  final String sid;
  final int initialTab;
  final KantorActions? actions;

  @override
  ConsumerState<_SessionScaffold> createState() => _SessionScaffoldState();
}

class _SessionScaffoldState extends ConsumerState<_SessionScaffold>
    with SingleTickerProviderStateMixin {
  static const _terminalTab = 1;

  late final TabController _tabs = TabController(
    length: _tabNames.length,
    vsync: this,
    initialIndex: widget.initialTab,
  )..addListener(_onTab);
  late final _built = <int>{widget.initialTab};

  late int _shown = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final complex = widget.complexId;
      if (mounted && complex != null) {
        ref
            .read(kantorRecentComplexChatsProvider.notifier)
            .remember(complex, widget.officeId, widget.sid);
      }
    });
  }

  void _onTab() {
    final i = _tabs.index;
    if (i == _shown) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _shown = i;
      _built.add(i);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _page(int i, Json s) {
    final ended = s['status'] == 'ended';
    return switch (i) {
      0 => KantorChatTab(feed: widget.feed, sid: widget.sid),
      1 =>
        ended
            ? const _Note(
                'Sesi selesai. Terminal sudah tertutup. Riwayatnya ada di tab Chat.',
              )
            : s['tmux'] == null
            ? _OutsideNote(
                officeId: widget.officeId,
                sid: widget.sid,
                host: s['host'] as String?,
                boss: s['boss'] as String?,
              )
            : KantorTerminalPanel.session(
                widget.sid,
                active: _shown == _terminalTab,
              ),
      2 => KantorProfileTab(feed: widget.feed, sid: widget.sid),
      3 => KantorSubsTab(feed: widget.feed, sid: widget.sid),
      _ => KantorSessionPratinjauTab(
        officeId: widget.officeId,
        sid: widget.sid,
        role: s['role'] as String?,
        actions: widget.actions,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.feed.session(widget.sid)!;
    // Only the selected tab is visible and focusable: the others stay mounted
    // (state kept) but are offstage and out of the focus tree, so the terminal
    // can never steal the keyboard from the chat field.
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 0,
        // tap the agent to switch (this office or all); swipe the header to
        // step to the previous/next active agent, staying on the same tab
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 400) return;
            kantorStepAgent(
              context,
              currentSid: widget.sid,
              dir: v < 0 ? 1 : -1,
              tab: _tabNames[_shown],
            );
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showKantorAgentSwitcher(
              context,
              officeId: widget.officeId,
              currentSid: widget.sid,
              tab: _tabNames[_shown],
            ),
            child: Row(
              children: [
                Flexible(
                  child: _Header(feed: widget.feed, sess: s),
                ),
                const Icon(Icons.expand_more_rounded, size: 20),
              ],
            ),
          ),
        ),
        actions: [
          KantorComplexSwitcherButton(
            officeId: widget.officeId,
            currentSid: widget.sid,
            tab: _tabNames[_shown],
          ),
          _Menu(feed: widget.feed, sess: s, actions: widget.actions),
        ],
        bottom: TabBar(
          controller: _tabs,
          // five tabs don't fit 360dp: scroll horizontally, compact labels
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: GhinaType.bodyS.w(800),
          unselectedLabelStyle: GhinaType.bodyS.w(700),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Terminal'),
            Tab(text: 'Profil'),
            Tab(text: 'Subagent'),
            Tab(text: 'Pratinjau'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _tabNames.length; i++)
              if (_built.contains(i))
                Offstage(
                  key: ValueKey('tab$i'),
                  offstage: _shown != i,
                  child: TickerMode(
                    enabled: _shown == i,
                    child: ExcludeFocus(
                      excluding: _shown != i,
                      child: _page(i, s),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(GhinaSpace.page),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GhinaType.body.copyWith(color: context.ghina.textSecondary),
      ),
    ),
  );
}

/// A session running in another terminal (VS Code, Terminal…): explains it and
/// offers to move it into the office's tmux.
class _OutsideNote extends ConsumerWidget {
  const _OutsideNote({
    required this.officeId,
    required this.sid,
    this.host,
    this.boss,
  });

  final String officeId, sid;
  final String? host, boss;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sesi ini jalan di terminal lain (${host ?? 'Terminal'}), bukan di tmux kantor, '
            'jadi terminalnya tidak bisa dibuka dari sini. Percakapannya bisa dibaca dan dikirimi pesan di tab Chat '
            'bila terminalnya mendukung.',
            textAlign: TextAlign.center,
            style: GhinaType.body.copyWith(color: context.ghina.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: 'Pindahkan ke kantor',
            icon: Icons.login_rounded,
            expand: false,
            onPressed: () => adoptKantorSession(
              context,
              ref,
              officeId: officeId,
              sid: sid,
              host: host,
              currentBoss: boss,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Header extends ConsumerWidget {
  const _Header({required this.feed, required this.sess});

  final KantorOfficeFeed feed;
  final Json sess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final complex = ref.watch(kantorActiveComplexProvider);
    final r = feed.role(sess['role'] as String?);
    final look = r ?? KantorSprite.guestLook('${sess['sid']}');
    final model = kantorSessionModelText(r, sess);
    final codex = kantorEngineIsCodex(sess, r);
    final sub = r != null
        ? [r['title'], model].where((e) => '$e'.isNotEmpty).join(' - ')
        : [
            'Tanpa role',
            model,
            feed.roomName(sess['room'] as String?),
          ].where((e) => e.isNotEmpty).join(' - ');
    final status = '${sess['status']}';
    final (ChunkySwatch color, String label) = switch (status) {
      'working' ||
      'starting' => (GhinaColors.green, kantorStatusLabel[status] ?? status),
      'waiting' => (GhinaColors.orange, 'Menunggu izin'),
      'ended' => (GhinaColors.gray, 'Selesai'),
      _ => (GhinaColors.blue, kantorStatusLabel[status] ?? status),
    };
    final mode = sess['permMode'] as String?;
    return Row(
      children: [
        KantorSprite(look: look, size: 36),
        const SizedBox(width: GhinaSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      sessionName(feed, sess),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChunkyPill(label: label, color: color, soft: true),
                  if (codex) ...[
                    const SizedBox(width: 4),
                    const KantorCodexBadge(),
                  ],
                  if (sess['compacting'] == true) ...[
                    const SizedBox(width: 4),
                    const ChunkyPill(
                      label: 'Meringkas',
                      color: GhinaColors.blue,
                      soft: true,
                    ),
                  ],
                  if (kantorBgAgents(sess) > 0) ...[
                    const SizedBox(width: 4),
                    ChunkyPill(
                      label: '${kantorBgAgents(sess)} sub',
                      color: GhinaColors.orange,
                      soft: true,
                    ),
                  ],
                ],
              ),
              Text(
                [
                  if (complex != null) complex.name,
                  if (feed.office?['name'] != null) '${feed.office!['name']}',
                  sub,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              if (mode != null && mode != 'default')
                Text(
                  'Izin: ${codex ? kantorCodexModeLabel(mode) : kantorModeLabel[mode] ?? mode}',
                  style: GhinaType.caption.copyWith(
                    color: mode == 'bypassPermissions'
                        ? GhinaColors.red.base
                        : g.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.feed, required this.sess, required this.actions});

  final KantorOfficeFeed feed;
  final Json sess;
  final KantorActions? actions;

  String get _sid => '${sess['sid']}';

  void _toast(BuildContext context, String m, {bool bad = false}) =>
      showToastBadge(
        context,
        message: m,
        icon: bad ? Icons.error_outline_rounded : Icons.check_rounded,
        color: bad ? GhinaColors.red : GhinaColors.green,
        tag: 'kantor-session',
      );

  Future<void> _run(BuildContext context, String action) async {
    if (action == 'esc') {
      final pick = await askStopMode(context, sess);
      if (pick == null || !context.mounted) return;
      action = pick;
    }
    const confirm = {
      'clear': (
        'Reset percakapan?',
        'Percakapan sesi ini dikosongkan (/clear). Buku catatan role tetap ada.',
        'Reset',
        false,
      ),
      'exit': (
        'Selesaikan sesi?',
        'Claude diminta keluar dengan /exit.',
        'Selesai',
        false,
      ),
      'kill': (
        'Paksa tutup sesi?',
        'Proses Claude dimatikan langsung. Pekerjaan yang belum disimpan bisa hilang.',
        'Paksa tutup',
        true,
      ),
    };
    const ok = {
      'esc': 'Esc dikirim',
      'stop-all': 'Semua dihentikan',
      'compact': 'Meminta ringkasan',
      'clear': 'Konteks direset',
      'exit': 'Sesi ditutup',
      'kill': 'Sesi dipaksa tutup',
    };
    final c = confirm[action];
    if (c != null) {
      var msg = c.$2;
      if (action == 'exit' && sess['worktree'] != null) {
        msg +=
            ' Sesi ini memakai worktree terpisah; foldernya tetap ada di disk, jadi pastikan perubahan sudah di-commit.';
      }
      final yes = await showChunkyConfirm(
        context,
        title: c.$1,
        message: msg,
        confirmLabel: c.$3,
        destructive: c.$4,
      );
      if (!yes || !context.mounted) return;
    }
    try {
      final did = await actions?.action(_sid, action) ?? true;
      if (context.mounted) {
        _toast(
          context,
          did
              ? ok[action] ?? 'Terkirim'
              : 'Sesi sedang tidak bekerja, jadi tidak ada yang dihentikan.',
        );
      }
    } catch (e) {
      if (context.mounted) _toast(context, '$e', bad: true);
    }
  }

  bool get _codex =>
      kantorEngineIsCodex(sess, feed.role(sess['role'] as String?));

  Future<void> _codexSettings(BuildContext context) async {
    final a = actions;
    if (a == null) return;
    await showKantorCodexSettingsSheet(
      context,
      actions: a,
      sess: sess,
      role: feed.role(sess['role'] as String?),
    );
  }

  Future<void> _mode(BuildContext context) async {
    final codex = _codex;
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: 'Mode izin',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            codex
                ? 'Sama dengan perintah /permissions di Codex.'
                : 'Sama dengan menekan Shift+Tab di terminalnya.',
            style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
          ),
          GhinaSpace.gapMd,
          for (final m
              in codex
                  ? [for (final c in kantorCodexModes) c.$1]
                  : kantorModeChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
              child: ChunkyTile(
                title: codex
                    ? kantorCodexModeLabel(m)
                    : kantorModeLabel[m] ?? m,
                showChevron: false,
                trailing: sess['permMode'] == m
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(c).pop(m),
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == sess['permMode'] || !context.mounted)
      return;
    try {
      await actions?.setMode(_sid, picked);
      if (context.mounted)
        _toast(
          context,
          'Mode izin: ${codex ? kantorCodexModeLabel(picked) : kantorModeLabel[picked] ?? picked}',
        );
    } catch (e) {
      if (context.mounted) _toast(context, '$e', bad: true);
    }
  }

  Future<void> _model(BuildContext context) async {
    final List<KantorModelChoice> choices;
    try {
      choices = await actions?.openModelPicker(_sid) ?? const [];
    } catch (e) {
      if (context.mounted) _toast(context, '$e', bad: true);
      return;
    }
    if (!context.mounted) return;
    if (choices.isEmpty) {
      _toast(context, 'Claude Code tidak menampilkan pilihan model', bad: true);
      await actions?.cancelModelPicker(_sid).catchError((_) {});
      return;
    }
    final picked = await showChunkyBottomSheet<int>(
      context,
      title: 'Ganti model',
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Pilihan sama dengan perintah /model di Claude Code. Berlaku untuk sesi ini saja.',
              style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
            ),
            GhinaSpace.gapMd,
            for (final o in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                child: ChunkyTile(
                  title: o.label,
                  subtitle: o.desc.isEmpty ? null : o.desc,
                  showChevron: false,
                  trailing: o.current ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(c).pop(o.index),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) {
      await actions?.cancelModelPicker(_sid).catchError((_) {});
      return;
    }
    try {
      final m = await actions?.selectModel(_sid, picked);
      if (context.mounted)
        _toast(
          context,
          'Model diganti ke ${m == null || m.isEmpty ? 'pilihan baru' : m}',
        );
    } catch (e) {
      if (context.mounted) _toast(context, '$e', bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alive = sess['status'] != 'ended';
    final tmux = sess['tmux'] != null;
    final busy = sess['status'] == 'working' || sess['status'] == 'starting';
    return PopupMenuButton<String>(
      tooltip: 'Aksi sesi',
      onSelected: (v) => v == 'view'
          ? showChatViewSheet(context)
          : v == 'mode'
          ? _mode(context)
          : v == 'codexmodel'
          ? _codexSettings(context)
          : v == 'model'
          ? _model(context)
          : _run(context, v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('Tampilan chat...')),
        if (alive) ...[
          const PopupMenuItem(value: 'esc', child: Text('Hentikan (Esc)')),
          const PopupMenuItem(
            value: 'compact',
            child: Text('Ringkas (/compact)'),
          ),
          if (tmux)
            const PopupMenuItem(value: 'mode', child: Text('Mode izin...')),
          if (tmux && _codex)
            PopupMenuItem(
              value: 'codexmodel',
              enabled: !busy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Model & effort Codex...'),
                  Text(
                    busy
                        ? 'Agen sedang bekerja; hentikan atau tunggu'
                        : kantorSessionModelText(
                            feed.role(sess['role'] as String?),
                            sess,
                          ),
                    style: GhinaType.bodyS,
                  ),
                ],
              ),
            ),
          if (tmux && !_codex)
            PopupMenuItem(
              value: 'model',
              enabled: !busy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ganti model...'),
                  if (busy)
                    Text(
                      'Agen sedang bekerja; hentikan atau tunggu',
                      style: GhinaType.bodyS,
                    ),
                ],
              ),
            ),
          const PopupMenuItem(value: 'clear', child: Text('Reset (/clear)')),
          const PopupMenuItem(
            value: 'exit',
            child: Text('Selesaikan sesi (/exit)'),
          ),
          const PopupMenuItem(value: 'kill', child: Text('Paksa tutup')),
        ],
      ],
    );
  }
}
