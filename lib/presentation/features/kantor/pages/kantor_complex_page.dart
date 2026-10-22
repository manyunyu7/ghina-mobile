import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../session/kantor_adopt.dart';
import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../agents/kantor_active_agents.dart';
import '../search/kantor_search.dart';
import '../shows/shows_button.dart';
import '../usage/kantor_limits_card.dart';
import '../widgets/kantor_inbox.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

/// Home of Kantor ("Kompleks"): every office, the combined permission inbox,
/// active agents and the monthly cost.
class KantorComplexPage extends ConsumerStatefulWidget {
  const KantorComplexPage({super.key});

  @override
  ConsumerState<KantorComplexPage> createState() => _KantorComplexPageState();
}

class _KantorComplexPageState extends ConsumerState<KantorComplexPage> {
  /// Whether the "reopen the last office" decision is still pending.
  late bool _resuming;

  @override
  void initState() {
    super.initState();
    final skip = ref.read(kantorSkipResumeProvider);
    _resuming = !skip;
    if (skip) {
      Future(() => ref.read(kantorSkipResumeProvider.notifier).set(false));
    }
  }

  /// Resolves the resume decision; true while the page should show a spinner.
  bool _resolveResume() {
    if (!_resuming) return false;
    final last = ref.watch(kantorLastOfficeProvider);
    if (last.isLoading) return true;
    final id = last.value;
    if (id == null) return _resuming = false;
    final st = ref.watch(kantorStateProvider);
    if (st.isLoading) return true;
    final known = (st.value?['offices'] as List? ?? const []).any(
      (o) => (o as Map)['id'] == id,
    );
    _resuming = false;
    if (!known) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/kantor/o/${Uri.encodeComponent(id)}');
    });
    return true;
  }

  void _openSearch() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const KantorSearchPage()));

  @override
  Widget build(BuildContext context) {
    // Opened with go() (resume, Kompleks button, deep link) there is nothing under /kantor:
    // back would close the app, so send it home instead.
    return PopScope(
      canPop: GoRouter.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final g = context.ghina;
    if (_resolveResume()) {
      return Scaffold(
        backgroundColor: g.background,
        body: const KantorLoading(),
      );
    }
    final api = ref.watch(kantorApiProvider);
    final config = ref.watch(kantorConfigProvider);
    // No token yet: go to settings instead of showing an error.
    if (api == null && config.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/kantor/settings');
      });
    }
    final async = ref.watch(kantorStateProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Kompleks'),
        actions: [
          IconButton(
            tooltip: 'Cari',
            icon: const Icon(Icons.search_rounded),
            onPressed: _openSearch,
          ),
          const KantorShowsButton(hideWhenIdle: true),
          // "Kantor baru" sudah ada di FAB; sisanya di ⋮ agar app bar ponsel lega.
          PopupMenuButton<String>(
            tooltip: 'Menu kompleks',
            onSelected: (v) {
              if (v == 'baru') context.push('/kantor/new');
              if (v == 'dibuka') showKantorShows(context);
              if (v == 'pc') context.push('/kantor/pc');
              if (v == 'set') context.push('/kantor/settings');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'baru',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_business_rounded),
                  title: Text('Kantor baru'),
                ),
              ),
              PopupMenuItem(
                value: 'dibuka',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Dibuka untukmu'),
                ),
              ),
              PopupMenuItem(
                value: 'pc',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.monitor_heart_rounded),
                  title: Text('Performa PC'),
                ),
              ),
              PopupMenuItem(
                value: 'set',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_rounded),
                  title: Text('Pengaturan Kantor'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'kantor-office-add',
        onPressed: () => context.push('/kantor/new'),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Kantor baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(kantorEndedProvider);
          ref.invalidate(kantorStateProvider);
          await ref.read(kantorStateProvider.future);
        },
        child: switch (async) {
          AsyncData(:final value) => _content(value),
          AsyncError(:final error) => KantorErrorView(
            error: error,
            onRetry: () => ref.invalidate(kantorStateProvider),
          ),
          _ => const KantorLoading(),
        },
      ),
    );
  }

  Widget _content(Map<String, dynamic> st) {
    final g = context.ghina;
    final offices = (st['offices'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final inbox = st['inbox'] as List? ?? const [];
    final loose = (st['loose'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final sess = <(Map<String, dynamic>, Map<String, dynamic>)>[
      for (final o in offices)
        for (final s in (o['sessions'] as List? ?? const []))
          if ((s as Map)['status'] != 'ended')
            (o, Map<String, dynamic>.from(s)),
    ]..sort((a, b) => kantorSessionRank(a.$2) - kantorSessionRank(b.$2));
    final working = sess.where((e) => e.$2['status'] == 'working').length;
    final cost = offices.fold<double>(
      0,
      (a, o) => a + ((o['monthCost'] as num?)?.toDouble() ?? 0),
    );
    int sessCount(Map<String, dynamic> o) =>
        (o['sessions'] as List? ?? const [])
            .where((s) => (s as Map)['status'] != 'ended')
            .length;
    final favs = offices.where((o) => o['fav'] == true).toList();
    final active =
        offices.where((o) => o['fav'] != true && sessCount(o) > 0).toList()
          ..sort((a, b) => sessCount(b) - sessCount(a));
    final rest = [...offices]
      ..sort((a, b) {
        final f = (b['fav'] == true ? 1 : 0) - (a['fav'] == true ? 1 : 0);
        return f != 0
            ? f
            : '${b['lastSeen'] ?? ''}'.compareTo('${a['lastSeen'] ?? ''}');
      });
    final ended = ref.watch(kantorEndedProvider).value ?? const [];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.sm,
        GhinaSpace.page,
        96,
      ),
      children: [
        ChunkyCard(
          key: const ValueKey('kantor-search-bar'),
          padding: const EdgeInsets.symmetric(
            horizontal: GhinaSpace.md,
            vertical: GhinaSpace.md,
          ),
          onTap: _openSearch,
          semanticLabel: 'Cari kantor',
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: g.textMuted),
              const SizedBox(width: GhinaSpace.sm),
              Expanded(
                child: Text(
                  'Cari kantor, agen, atau sesi…',
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.copyWith(color: g.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GhinaSpace.md),
        KantorLimitsCard(
          key: const ValueKey('kantor-limits-card'),
          onTap: () => context.push('/kantor/o/_kompleks?tab=pemakaian'),
        ),
        const SizedBox(height: GhinaSpace.md),
        KantorActiveAgentsStrip(state: st),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.groups_rounded,
                value: '${sess.length}',
                label: 'sesi aktif · $working bekerja',
                color: GhinaColors.blue,
              ),
            ),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: StatTile(
                icon: Icons.lock_clock_rounded,
                value: '${inbox.length}',
                label: 'izin menunggu',
                color: inbox.isEmpty ? GhinaColors.green : GhinaColors.orange,
              ),
            ),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: StatTile(
                icon: Icons.payments_rounded,
                value: kantorUsd(cost, 0),
                label: 'bulan ini',
                color: GhinaColors.purple,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: GhinaSpace.xs),
          child: Text(
            'Biaya = estimasi setara harga API, bukan tagihan langganan.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
        SectionHeader(
          title: 'Kotak masuk izin',
          subtitle: inbox.isEmpty ? null : '${inbox.length} menunggu',
        ),
        KantorInboxList(items: inbox, offices: offices),
        if (favs.isNotEmpty) ...[
          const SectionHeader(title: 'Favorit'),
          for (final o in favs) _OfficeCard(office: o),
        ],
        if (active.isNotEmpty) ...[
          const SectionHeader(title: 'Sedang aktif'),
          for (final o in active) _OfficeCard(office: o),
        ],
        SectionHeader(
          title: 'Semua kantor',
          actionLabel: 'Kantor baru',
          onAction: () => context.push('/kantor/new'),
        ),
        if (rest.isEmpty)
          const EmptyState(title: 'Tidak ada kantor', compact: true)
        else
          for (final o in rest) _OfficeCard(office: o, compact: true),
        if (sess.isNotEmpty) ...[
          SectionHeader(title: 'Agen aktif', subtitle: '${sess.length} sesi'),
          for (final (o, s) in sess) _SessionTile(office: o, session: s),
        ],
        if (loose.isNotEmpty) ...[
          SectionHeader(
            title: 'Di luar kantor',
            subtitle: 'Sesi yang berjalan di folder induk, bukan di project.',
            trailing: Text('${loose.length}'),
          ),
          for (final s in loose)
            ChunkyTile(
              onTap: () => showKantorLooseSheet(context, s),
              leading: KantorSprite(
                look: KantorSprite.guestLook('${s['sid']}'),
                size: 32,
              ),
              title: kantorShort(s['title'] ?? 'Sesi', 30),
              subtitle: '${s['cwd'] ?? ''}'.replaceFirst(
                RegExp(r'^/Users/[^/]+'),
                '~',
              ),
            ),
        ],
        if (ended.isNotEmpty) ...[
          SectionHeader(
            title: 'Baru ditutup',
            subtitle: 'Percakapannya masih tersimpan; lanjutkan dari web.',
            trailing: Text('${ended.length}'),
          ),
          for (final raw in ended.take(8))
            Builder(
              builder: (_) {
                final x = Map<String, dynamic>.from(raw as Map);
                final t =
                    x['title'] != null && x['title'] != 'Sesi belum terhubung'
                    ? '${x['title']}'
                    : '${x['first_prompt'] ?? 'Sesi tanpa judul'}';
                return ChunkyTile(
                  leading: KantorSprite(
                    look: KantorSprite.guestLook('${x['sid']}'),
                    size: 32,
                  ),
                  title: kantorShort(t, 34),
                  subtitle:
                      '${x['office_name'] ?? ''} · ditutup ${kantorAgo(x['ended_at'])}',
                );
              },
            ),
        ],
        const SectionHeader(title: 'Bersama'),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                label: 'Notes',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () => context.push('/kantor/o/_kompleks?tab=notes'),
              ),
            ),
            const SizedBox(width: GhinaSpace.sm),
            Expanded(
              child: ChunkyButton(
                label: 'Wiki',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () => context.push('/kantor/o/_kompleks?tab=wiki'),
              ),
            ),
            const SizedBox(width: GhinaSpace.sm),
            Expanded(
              child: ChunkyButton(
                label: 'Payroll',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () =>
                    context.push('/kantor/o/_kompleks?tab=payroll'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OfficeCard extends ConsumerWidget {
  const _OfficeCard({required this.office, this.compact = false});

  final Map<String, dynamic> office;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final id = '${office['id']}';
    final sessions = (office['sessions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => s['status'] != 'ended')
        .toList();
    final cards = office['cards'] as Map? ?? const {};
    final fav = office['fav'] == true;
    final waiting = sessions.any((s) => s['waiting'] != null);
    final (label, color) = waiting
        ? ('izin', GhinaColors.orange)
        : sessions.any((s) => s['status'] == 'working')
        ? ('bekerja', GhinaColors.green)
        : sessions.isNotEmpty
        ? ('ada sesi', GhinaColors.blue)
        : ('sepi', GhinaColors.gray);
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: ChunkyCard(
        padding: const EdgeInsets.all(GhinaSpace.md),
        onTap: () => context.push('/kantor/o/${Uri.encodeComponent(id)}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${office['name']}',
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ('${office['style'] ?? ''}'.isNotEmpty)
                        Text(
                          '${office['style']}',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                ChunkyPill(label: label, color: color, soft: true),
                IconButton(
                  tooltip: fav ? 'Hapus dari favorit' : 'Jadikan favorit',
                  icon: Icon(
                    fav ? Icons.star_rounded : Icons.star_border_rounded,
                    color: fav ? GhinaColors.yellow.base : g.textMuted,
                  ),
                  onPressed: () async {
                    final api = ref.read(kantorApiProvider);
                    if (api == null) return;
                    try {
                      await api.post(
                        '/api/offices/${Uri.encodeComponent(id)}/fav',
                        {'fav': !fav},
                      );
                      ref.invalidate(kantorStateProvider);
                    } on KantorException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
              ],
            ),
            if (!compact || sessions.isNotEmpty) ...[
              const SizedBox(height: GhinaSpace.sm),
              Row(
                children: [
                  for (final s in sessions.take(6))
                    Padding(
                      padding: const EdgeInsets.only(right: GhinaSpace.xs),
                      child: KantorSprite(look: _look(s), size: 28),
                    ),
                  if (sessions.length > 6)
                    Text(
                      '+${sessions.length - 6}',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  if (sessions.isEmpty)
                    Text(
                      'Belum ada sesi berjalan.',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                ],
              ),
            ],
            const SizedBox(height: GhinaSpace.sm),
            Text(
              '${cards['open'] ?? 0} kartu · ${kantorUsd(office['monthCost'], 0)} bln ini'
              '${office['lastSeen'] != null ? ' · ${kantorAgo(office['lastSeen'])}' : ''}',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _look(Map<String, dynamic> s) => s['look'] is Map
    ? Map<String, dynamic>.from(s['look'] as Map)
    : KantorSprite.guestLook('${s['sid']}');

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.office, required this.session});

  final Map<String, dynamic> office;
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final look = session['look'] as Map?;
    final title = '${session['title'] ?? ''}';
    final name =
        look?['name'] ??
        (title.isNotEmpty && title != 'Sesi belum terhubung'
            ? kantorShort(title, 30)
            : 'Sesi manual');
    final waiting = session['waiting'] != null;
    final working = session['status'] == 'working';
    return ChunkyTile(
      leading: KantorSprite(look: _look(session), size: 32),
      title: '$name',
      subtitle:
          '${office['name']} · ${kantorShort(kantorSessionLabel(session), 44)}',
      trailing: Icon(
        Icons.circle,
        size: 12,
        color: waiting
            ? GhinaColors.orange.base
            : working
            ? GhinaColors.green.base
            : context.ghina.textMuted,
      ),
      onTap: () => context.push(
        '/kantor/o/${Uri.encodeComponent('${office['id']}')}/s/${Uri.encodeComponent('${session['sid']}')}',
      ),
    );
  }
}
