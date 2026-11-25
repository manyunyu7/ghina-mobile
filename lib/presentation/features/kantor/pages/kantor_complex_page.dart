import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kantor_complex_agent_switcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../session/kantor_adopt.dart';
import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../kantor_place.dart';
import '../agents/kantor_active_agents.dart';
import '../search/kantor_search.dart';
import '../session/kantor_konteks.dart';
import '../session/kantor_label.dart';
import '../shows/shows_button.dart';
import '../usage/kantor_limits_card.dart';
import '../widgets/kantor_inbox.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import '../widgets/kantor_wide.dart';

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
    final cid = ref.watch(kantorActiveComplexProvider)?.id;
    if (cid == null &&
        (ref.watch(kantorComplexProfilesProvider).isLoading ||
            ref.watch(kantorConfigProvider).isLoading)) {
      return true;
    }
    final saved = cid == null
        ? const AsyncData<KantorPlace?>(null)
        : ref.watch(kantorSavedPlaceProvider(cid));
    if (saved.isLoading) return true;
    // Saved place first; the older "last office" value is the fallback.
    final lastId = last.value;
    final place =
        saved.value ?? (lastId == null ? null : KantorPlace(office: lastId));
    if (place == null) return _resuming = false;
    final st = ref.watch(kantorStateProvider);
    if (st.isLoading) return true;
    _resuming = false;
    final paths = st.hasValue
        ? kantorResumePaths(place, st.value!)
        : const <String>[];
    if (paths.isEmpty) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(paths.first);
      if (paths.length > 1) context.push(paths[1]);
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
      canPop: ref.watch(kantorOnlyProvider) || GoRouter.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !ref.read(kantorOnlyProvider)) context.go('/home');
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
          const KantorComplexSwitcherButton(),
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
              if (v == 'remote') context.push('/kantor/remote');
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
                value: 'remote',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.desktop_mac_rounded),
                  title: Text('Remote Mac'),
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
    final d = _ComplexData(
      state: st,
      offices: offices,
      inbox: inbox,
      loose: loose,
      sess: sess,
      working: working,
      cost: cost,
      favs: favs,
      active: active,
      rest: rest,
      ended: ended,
    );

    // Ponsel (< 600dp) tetap daftar satu kolom seperti semula. Layar lebar
    // (layar dalam Fold, tablet, mendatar) memakai kartu ringkas dalam grid;
    // bila cukup lebar, halaman dibagi dua: kiri daftar kantor, kanan
    // ringkasan, izin, dan agen yang butuh perhatian.
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < kantorComplexWideBreakpoint) return _narrow(d);
        final side = math.max(
          GhinaSpace.page,
          (box.maxWidth - kantorComplexMaxContentWidth) / 2,
        );
        final inner = box.maxWidth - side * 2;
        return inner >= kantorComplexSplitMin
            ? _split(d, side, inner)
            : _stacked(d, side, inner);
      },
    );
  }

  /// Tampilan ponsel: sama persis dengan sebelum ada tata letak lebar.
  Widget _narrow(_ComplexData d) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.sm,
        GhinaSpace.page,
        96,
      ),
      children: [
        _searchBar(dense: false),
        const SizedBox(height: GhinaSpace.md),
        _limitsCard(),
        const SizedBox(height: GhinaSpace.md),
        KantorActiveAgentsStrip(state: d.state),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.groups_rounded,
                value: '${d.sess.length}',
                label: 'sesi aktif · ${d.working} bekerja',
                color: GhinaColors.blue,
              ),
            ),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: StatTile(
                icon: Icons.lock_clock_rounded,
                value: '${d.inbox.length}',
                label: 'izin menunggu',
                color: d.inbox.isEmpty ? GhinaColors.green : GhinaColors.orange,
              ),
            ),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: StatTile(
                icon: Icons.payments_rounded,
                value: kantorUsd(d.cost, 0),
                label: 'bulan ini',
                color: GhinaColors.purple,
              ),
            ),
          ],
        ),
        _costNote(),
        ..._inboxSection(d, dense: false),
        ..._officeSections(d, columns: 1),
        if (d.sess.isNotEmpty) ...[
          _header(
            false,
            title: 'Agen aktif',
            subtitle: '${d.sess.length} sesi',
          ),
          for (final (o, s) in d.sess) _SessionTile(office: o, session: s),
        ],
        ..._looseSection(d, columns: 1, dense: false),
        ..._endedSection(d, columns: 1, dense: false),
        ..._bersama(dense: false),
      ],
    );
  }

  /// Layar lebar tapi belum cukup untuk dua kolom (mis. Fold tegak ±690dp):
  /// satu kolom di tengah, isi dirapatkan dan kartu kantor jadi grid.
  Widget _stacked(_ComplexData d, double side, double inner) {
    final cols = kantorComplexColumns(inner);
    return ListView(
      key: const ValueKey('kantor-complex-stacked'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, GhinaSpace.sm, side, 96),
      children: [
        _searchBar(dense: true),
        const SizedBox(height: GhinaSpace.sm),
        _StatsCard(items: _stats(d), vertical: false),
        _costNote(),
        const SizedBox(height: GhinaSpace.sm),
        _limitsCard(),
        const SizedBox(height: GhinaSpace.sm),
        KantorActiveAgentsStrip(state: d.state),
        ..._inboxSection(d, dense: true),
        ..._officeSections(d, columns: cols),
        ..._sessionSection(d, columns: math.min(cols, 2)),
        ..._looseSection(d, columns: math.min(cols, 2), dense: true),
        ..._endedSection(d, columns: math.min(cols, 2), dense: true),
        ..._bersama(dense: true),
      ],
    );
  }

  /// Dua kolom yang bisa digulir sendiri-sendiri: kiri pencarian, agen aktif
  /// (strip) dan grid kantor; kanan ringkasan, izin, daftar agen, dan sesi lain.
  Widget _split(_ComplexData d, double side, double inner) {
    final aside = kantorComplexAsideWidth(inner);
    final main = inner - aside - GhinaSpace.lg;
    final cols = kantorComplexColumns(main);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Row(
        key: const ValueKey('kantor-complex-split'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              key: const ValueKey('kantor-complex-main'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, GhinaSpace.sm, 0, 96),
              children: [
                _searchBar(dense: true),
                const SizedBox(height: GhinaSpace.sm),
                KantorActiveAgentsStrip(state: d.state),
                ..._officeSections(d, columns: cols),
              ],
            ),
          ),
          const SizedBox(width: GhinaSpace.lg),
          SizedBox(
            width: aside,
            child: ListView(
              key: const ValueKey('kantor-complex-aside'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, GhinaSpace.sm, 0, 96),
              children: [
                _StatsCard(items: _stats(d), vertical: true),
                _costNote(),
                const SizedBox(height: GhinaSpace.sm),
                _limitsCard(),
                ..._inboxSection(d, dense: true),
                ..._sessionSection(d, columns: 1),
                ..._looseSection(d, columns: 1, dense: true),
                ..._endedSection(d, columns: 1, dense: true),
                ..._bersama(dense: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Potongan yang dipakai bersama oleh ketiga tata letak ----

  Widget _searchBar({required bool dense}) {
    final g = context.ghina;
    return ChunkyCard(
      key: const ValueKey('kantor-search-bar'),
      padding: EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: dense ? GhinaSpace.sm + 2 : GhinaSpace.md,
      ),
      onTap: _openSearch,
      semanticLabel: 'Cari kantor',
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: g.textMuted,
            size: dense ? 20 : null,
          ),
          const SizedBox(width: GhinaSpace.sm),
          Expanded(
            child: Text(
              'Cari kantor, agen, atau sesi…',
              overflow: TextOverflow.ellipsis,
              style: (dense ? GhinaType.bodyS : GhinaType.body).copyWith(
                color: g.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitsCard() => KantorLimitsCard(
    key: const ValueKey('kantor-limits-card'),
    onTap: () => context.push('/kantor/o/_kompleks?tab=pemakaian'),
  );

  Widget _costNote() => Padding(
    padding: const EdgeInsets.only(top: GhinaSpace.xs),
    child: Text(
      'Biaya = estimasi setara harga API, bukan tagihan langganan.',
      style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
    ),
  );

  List<_Stat> _stats(_ComplexData d) => [
    (
      icon: Icons.groups_rounded,
      value: '${d.sess.length}',
      label: 'sesi aktif · ${d.working} bekerja',
      color: GhinaColors.blue,
    ),
    (
      icon: Icons.lock_clock_rounded,
      value: '${d.inbox.length}',
      label: 'izin menunggu',
      color: d.inbox.isEmpty ? GhinaColors.green : GhinaColors.orange,
    ),
    (
      icon: Icons.payments_rounded,
      value: kantorUsd(d.cost, 0),
      label: 'bulan ini',
      color: GhinaColors.purple,
    ),
  ];

  /// Judul bagian: [SectionHeader] biasa di ponsel, versi kecil di layar lebar.
  Widget _header(
    bool dense, {
    required String title,
    String? subtitle,
    Widget? trailing,
    String? actionLabel,
    VoidCallback? onAction,
  }) => dense
      ? _CompactHeader(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          actionLabel: actionLabel,
          onAction: onAction,
        )
      : SectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  List<Widget> _inboxSection(_ComplexData d, {required bool dense}) => [
    _header(
      dense,
      title: 'Kotak masuk izin',
      subtitle: d.inbox.isEmpty ? null : '${d.inbox.length} menunggu',
    ),
    KantorInboxList(items: d.inbox, offices: d.offices),
  ];

  /// Favorit, Sedang aktif, Semua kantor. [columns] 1 = daftar ponsel asli
  /// (kartu penuh); lebih dari 1 = grid kartu ringkas.
  List<Widget> _officeSections(_ComplexData d, {required int columns}) {
    final dense = columns > 1;
    List<Widget> cards(Iterable<Widget> items) => dense
        ? [
            _KantorColumns(
              columns: columns,
              runSpacing: GhinaSpace.sm,
              spacing: GhinaSpace.sm,
              children: items.toList(),
            ),
          ]
        : items.toList();
    return [
      if (d.favs.isNotEmpty) ...[
        _header(dense, title: 'Favorit'),
        ...cards([
          for (final o in d.favs) _OfficeCard(office: o, dense: dense),
        ]),
      ],
      if (d.active.isNotEmpty) ...[
        _header(dense, title: 'Sedang aktif'),
        ...cards([
          for (final o in d.active) _OfficeCard(office: o, dense: dense),
        ]),
      ],
      _header(
        dense,
        title: 'Semua kantor',
        actionLabel: 'Kantor baru',
        onAction: () => context.push('/kantor/new'),
      ),
      if (d.rest.isEmpty)
        const EmptyState(title: 'Tidak ada kantor', compact: true)
      else
        ...cards([
          for (final o in d.rest)
            _OfficeCard(office: o, compact: true, dense: dense),
        ]),
    ];
  }

  /// Ubin sesi/agen yang rapat di layar lebar: grid [columns] kolom.
  List<Widget> _tiles(int columns, List<Widget> items) => [
    _KantorColumns(
      columns: columns,
      runSpacing: GhinaSpace.sm,
      spacing: GhinaSpace.sm,
      children: items,
    ),
  ];

  List<Widget> _sessionSection(_ComplexData d, {required int columns}) => [
    if (d.sess.isNotEmpty) ...[
      _header(true, title: 'Agen aktif', subtitle: '${d.sess.length} sesi'),
      ..._tiles(columns, [
        for (final (o, s) in d.sess)
          _SessionTile(office: o, session: s, dense: true),
      ]),
    ],
  ];

  List<Widget> _looseSection(
    _ComplexData d, {
    required int columns,
    required bool dense,
  }) {
    if (d.loose.isEmpty) return const [];
    final items = [
      for (final s in d.loose)
        ChunkyTile(
          dense: dense,
          onTap: () => showKantorLooseSheet(context, s),
          leading: KantorSprite(
            look: KantorSprite.guestLook('${s['sid']}'),
            size: dense ? 28 : 32,
          ),
          title: kantorShort(s['title'] ?? 'Sesi', 30),
          subtitle: '${s['cwd'] ?? ''}'.replaceFirst(
            RegExp(r'^/Users/[^/]+'),
            '~',
          ),
        ),
    ];
    return [
      _header(
        dense,
        title: 'Di luar kantor',
        subtitle: 'Sesi yang berjalan di folder induk, bukan di project.',
        trailing: Text('${d.loose.length}'),
      ),
      ...(dense ? _tiles(columns, items) : items),
    ];
  }

  List<Widget> _endedSection(
    _ComplexData d, {
    required int columns,
    required bool dense,
  }) {
    if (d.ended.isEmpty) return const [];
    final items = <Widget>[
      for (final raw in d.ended.take(8))
        Builder(
          builder: (_) {
            final x = Map<String, dynamic>.from(raw as Map);
            final t = x['title'] != null && x['title'] != 'Sesi belum terhubung'
                ? '${x['title']}'
                : '${x['first_prompt'] ?? 'Sesi tanpa judul'}';
            return ChunkyTile(
              dense: dense,
              leading: KantorSprite(
                look: KantorSprite.guestLook('${x['sid']}'),
                size: dense ? 28 : 32,
              ),
              title: kantorShort(t, 34),
              subtitle:
                  '${x['office_name'] ?? ''} · ditutup ${kantorAgo(x['ended_at'])}',
            );
          },
        ),
    ];
    return [
      _header(
        dense,
        title: 'Baru ditutup',
        subtitle: 'Percakapannya masih tersimpan; lanjutkan dari web.',
        trailing: Text('${d.ended.length}'),
      ),
      ...(dense ? _tiles(columns, items) : items),
    ];
  }

  List<Widget> _bersama({required bool dense}) {
    Widget button(String label, String tab) => Expanded(
      child: ChunkyButton(
        label: label,
        size: ChunkyButtonSize.small,
        variant: ChunkyButtonVariant.secondary,
        onPressed: () => context.push('/kantor/o/_kompleks?tab=$tab'),
      ),
    );
    return [
      _header(dense, title: 'Bersama'),
      Row(
        children: [
          button('Notes', 'notes'),
          const SizedBox(width: GhinaSpace.sm),
          button('Wiki', 'wiki'),
          const SizedBox(width: GhinaSpace.sm),
          button('Payroll', 'payroll'),
        ],
      ),
    ];
  }
}

/// Data halaman Kompleks yang sudah diolah dari `/api/state`.
class _ComplexData {
  const _ComplexData({
    required this.state,
    required this.offices,
    required this.inbox,
    required this.loose,
    required this.sess,
    required this.working,
    required this.cost,
    required this.favs,
    required this.active,
    required this.rest,
    required this.ended,
  });

  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> offices;
  final List<dynamic> inbox;
  final List<Map<String, dynamic>> loose;
  final List<(Map<String, dynamic>, Map<String, dynamic>)> sess;
  final int working;
  final double cost;
  final List<Map<String, dynamic>> favs;
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> rest;
  final List<dynamic> ended;
}

/// Mulai lebar ini (dp) halaman Kompleks memakai tata letak lebar; di bawahnya
/// tetap daftar satu kolom ponsel.
const double kantorComplexWideBreakpoint = kKantorWideMin;

/// Lebar maksimal isi halaman di layar sangat lebar, supaya kartu tidak
/// melebar penuh.
const double kantorComplexMaxContentWidth = 1280;

/// Mulai lebar isi ini halaman dibagi dua kolom (layar dalam Fold ±830dp,
/// tablet, mendatar). Di bawahnya (mis. Fold tegak ±690dp) tetap satu kolom.
const double kantorComplexSplitMin = 740;

/// Lebar kolom kanan (ringkasan, izin, agen) pada tampilan dua kolom.
double kantorComplexAsideWidth(double inner) => inner >= 1000 ? 360 : 300;

/// Lebar minimal kartu kantor ringkas di grid.
const double _kMinTile = 200;

/// Jumlah kolom grid kartu kantor untuk lebar [width] (sudah termasuk jarak
/// antarkartu): 2 di Fold, 3 di tablet, 4 di layar sangat lebar.
@visibleForTesting
int kantorComplexColumns(double width) => math.max(
  2,
  kantorGridColumns(
    width + GhinaSpace.sm,
    minTile: _kMinTile + GhinaSpace.sm,
    max: 4,
  ),
);

/// Grid sederhana: baris berisi [columns] sel rata atas, tinggi tiap baris
/// mengikuti isinya (tanpa rasio tetap, jadi tidak ada yang terpotong).
class _KantorColumns extends StatelessWidget {
  const _KantorColumns({
    required this.columns,
    required this.children,
    this.runSpacing = 0,
    this.spacing = GhinaSpace.md,
  });

  final int columns;
  final List<Widget> children;

  /// Jarak antarbaris.
  final double runSpacing;

  /// Jarak antarkolom.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: runSpacing),
            children[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i += columns)
          Padding(
            padding: EdgeInsets.only(
              bottom: i + columns < children.length ? runSpacing : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: spacing),
                  Expanded(
                    child: i + j < children.length
                        ? children[i + j]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Judul bagian versi kecil untuk layar lebar (pengganti [SectionHeader]
/// yang hurufnya besar). Teks dan aksi sama.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.lg, bottom: GhinaSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: GhinaType.caption.copyWith(color: g.textSecondary),
              child: trailing!,
            ),
          if (actionLabel != null && onAction != null)
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    actionLabel!.toUpperCase(),
                    style: GhinaType.button.copyWith(
                      color: GhinaColors.blue.base,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

typedef _Stat = ({
  IconData icon,
  String value,
  String label,
  ChunkySwatch color,
});

/// Ringkasan angka dalam satu kartu kecil (layar lebar), pengganti tiga
/// [StatTile] besar. [vertical]: satu baris per angka (kolom kanan).
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.items, required this.vertical});

  final List<_Stat> items;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget cell(_Stat s) => Row(
      children: [
        Icon(s.icon, color: s.color.base, size: 20),
        const SizedBox(width: GhinaSpace.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: s.value,
                  style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                ),
                TextSpan(
                  text: '  ${s.label}',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return ChunkyCard(
      key: const ValueKey('kantor-stats-compact'),
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.md,
        vertical: GhinaSpace.sm + 2,
      ),
      borderRadius: GhinaRadii.rLg,
      depth: GhinaDepth.sm,
      child: vertical
          ? Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: GhinaSpace.xs + 2),
                  cell(items[i]),
                ],
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: GhinaSpace.md),
                  Expanded(child: cell(items[i])),
                ],
              ],
            ),
    );
  }
}

class _OfficeCard extends ConsumerWidget {
  const _OfficeCard({
    required this.office,
    this.compact = false,
    this.dense = false,
  });

  final Map<String, dynamic> office;
  final bool compact;

  /// Versi ringkas untuk grid layar lebar: padding, teks, dan sprite lebih
  /// kecil. Tap, tombol favorit, dan tujuan navigasi tetap sama.
  final bool dense;

  Future<void> _toggleFav(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool fav,
  ) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      await api.post('/api/offices/${Uri.encodeComponent(id)}/fav', {
        'fav': !fav,
      });
      ref.invalidate(kantorStateProvider);
    } on KantorException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

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
    final favButton = IconButton(
      tooltip: fav ? 'Hapus dari favorit' : 'Jadikan favorit',
      visualDensity: dense ? VisualDensity.compact : null,
      iconSize: dense ? 20 : null,
      icon: Icon(
        fav ? Icons.star_rounded : Icons.star_border_rounded,
        color: fav ? GhinaColors.yellow.base : g.textMuted,
      ),
      onPressed: () => _toggleFav(context, ref, id, fav),
    );
    final meta =
        '${cards['open'] ?? 0} kartu · ${kantorUsd(office['monthCost'], 0)} bln ini'
        '${office['lastSeen'] != null ? ' · ${kantorAgo(office['lastSeen'])}' : ''}';
    if (dense) return _dense(context, sessions, label, color, favButton, meta);
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
                favButton,
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
              meta,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu ringkas untuk grid layar lebar.
  Widget _dense(
    BuildContext context,
    List<Map<String, dynamic>> sessions,
    String label,
    ChunkySwatch color,
    Widget favButton,
    String meta,
  ) {
    final g = context.ghina;
    final id = '${office['id']}';
    final style = '${office['style'] ?? ''}';
    return ChunkyCard(
      key: ValueKey('kantor-office-card-$id'),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.md,
        GhinaSpace.xs,
        GhinaSpace.xs,
        GhinaSpace.sm + 2,
      ),
      borderRadius: GhinaRadii.rLg,
      depth: GhinaDepth.sm,
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
                      maxLines: 1,
                      style: GhinaType.body
                          .w(800)
                          .copyWith(color: g.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (style.isNotEmpty)
                      Text(
                        style,
                        maxLines: 1,
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: GhinaSpace.xs),
              ChunkyPill(label: label, color: color, soft: true),
              favButton,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: GhinaSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sessions.isNotEmpty) ...[
                  const SizedBox(height: GhinaSpace.xs),
                  Wrap(
                    spacing: GhinaSpace.xs,
                    runSpacing: GhinaSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final s in sessions.take(6))
                        KantorSprite(look: _look(s), size: 22),
                      if (sessions.length > 6)
                        Text(
                          '+${sessions.length - 6}',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: GhinaSpace.xs),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _look(Map<String, dynamic> s) => s['look'] is Map
    ? Map<String, dynamic>.from(s['look'] as Map)
    : KantorSprite.guestLook('${s['sid']}');

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.office,
    required this.session,
    this.dense = false,
  });

  final Map<String, dynamic> office;
  final Map<String, dynamic> session;

  /// Ubin rapat untuk layar lebar.
  final bool dense;

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
    final g = context.ghina;
    return ChunkyTile(
      key: ValueKey('complex-session-${session['sid']}'),
      dense: dense,
      leading: KantorSprite(look: _look(session), size: dense ? 28 : 32),
      title: '$name',
      // stiker label (maks 2 baris) di bawah nama agen
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (dense ? GhinaType.body.w(800) : GhinaType.h3).copyWith(
              color: g.textPrimary,
            ),
          ),
          KantorSessionLabel(
            session: session,
            maxLines: 2,
            size: dense ? 13 : 14,
          ),
        ],
      ),
      onLongPress: () => showKantorLabelMenu(
        context,
        session,
        name: '$name',
        officeId: '${office['id']}',
      ),
      subtitle:
          '${office['name']} · ${kantorShort(kantorSessionLabel(session), 44)}',
      trailing: Icon(
        Icons.circle,
        size: dense ? 10 : 12,
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
