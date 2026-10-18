import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_list_logic.dart';
import 'dream_list_rows.dart';
import 'dream_sheets.dart';
import 'dream_views.dart';
import 'dream_visuals.dart';

/// "Mimpi": the dreams as a board, a table or a timeline. Search, filters, a
/// summary strip and "Segarkan" for the stale or tagged ones. All of it is
/// local, so it works offline.
class DreamsPage extends ConsumerStatefulWidget {
  const DreamsPage({super.key});

  @override
  ConsumerState<DreamsPage> createState() => _DreamsPageState();
}

class _DreamsPageState extends ConsumerState<DreamsPage> {
  final _search = TextEditingController();
  DreamView _view = DreamView.board;
  DreamSort _sort = DreamSort.list;
  DreamFilter _filter = DreamFilter.none;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(DreamRow r) => context.push('/dreams/${r.id}');

  void _reset() => setState(() {
    _search.clear();
    _filter = DreamFilter.none;
  });

  Future<void> _changeStatus(DreamRow r) async {
    final s = await showDreamStatusSheet(context, current: r.dream.status);
    if (s == null || s == r.dream.status || !mounted) return;
    final res = await ref.read(setDreamStatusProvider)(r.id, s);
    if (!mounted) return;
    switch (res) {
      case Ok():
        showOkToast(context, '${r.dream.title} → ${s.label}');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _filterSheet(List<DreamCategory> cats, List<String> tags) async {
    final f = await showDreamFilterSheet(
      context,
      current: _filter,
      categories: cats,
      tags: tags,
    );
    if (f == null || !mounted) return;
    setState(() => _filter = f);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(dreamRowsProvider);
    final total = async.value?.length ?? 0;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Mimpi'),
        actions: [
          IconButton(
            tooltip: 'Kategori & kolom',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push('/dreams/manage'),
          ),
          IconButton(
            tooltip: 'Mimpi baru',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => context.push('/dreams/new'),
          ),
        ],
      ),
      bottomNavigationBar: total > 0
          ? Container(
              decoration: BoxDecoration(
                color: g.background,
                border: Border(top: BorderSide(color: g.border, width: 2)),
              ),
              padding: EdgeInsets.fromLTRB(
                GhinaSpace.page,
                12,
                GhinaSpace.page,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: ChunkyButton(
                key: const ValueKey('dreams-new'),
                label: 'Mimpi baru',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => context.push('/dreams/new'),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ScrollableFill(
            child: EmptyState(
              title: 'Belum ada mimpi',
              message:
                  'Tulis mimpi, cita-cita, atau daftar keinginanmu. Tambah '
                  'target dan langkah kecil supaya terasa dekat ✨',
              mood: MascotMood.waving,
              actionLabel: 'Tulis mimpi pertama',
              onAction: () => context.push('/dreams/new'),
            ),
          ),
          AsyncData(:final value) => _content(value),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () {
                ref
                  ..invalidate(watchDreamsProvider)
                  ..invalidate(watchDreamStepsProvider)
                  ..invalidate(watchDreamMetricsProvider);
              },
            ),
          ),
          _ => const LoadingListView(hero: false, tiles: 6),
        },
      ),
    );
  }

  Widget _content(List<DreamRow> rows) {
    final cats = ref.watch(watchDreamCategoriesProvider).value ?? const [];
    String labelOf(String key) => dreamCategoryLabel(key, cats);
    final stats = dreamStats(rows);
    final tags = allDreamTags(rows);
    // A tag or category that no longer exists must not hide everything.
    final filter = _filter.tag != null && !tags.contains(_filter.tag)
        ? _filter.copyWith(clearTag: true)
        : _filter;
    final filtered = applyDreamFilter(rows, filter);
    final sorted = sortDreamRows(filtered, _sort);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: ChunkyTextField(
                  key: const ValueKey('dreams-search'),
                  controller: _search,
                  hint: 'Cari judul, alasan, tag, langkah…',
                  prefixIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.none,
                  suffix: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(
                              () => _filter = _filter.copyWith(query: ''),
                            );
                          },
                        ),
                  onChanged: (v) =>
                      setState(() => _filter = _filter.copyWith(query: v)),
                ),
              ),
              IconButton(
                key: const ValueKey('dreams-filter'),
                tooltip: 'Filter',
                icon: Icon(
                  _filter.isActive
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                  color: _filter.isActive ? context.ghina.accent.base : null,
                ),
                onPressed: () => _filterSheet(cats, tags),
              ),
            ],
          ),
        ),
        _SummaryStrip(stats: stats),
        if (stats.review > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              0,
            ),
            child: ChunkyButton(
              key: const ValueKey('dreams-review'),
              label: 'Segarkan (${stats.review})',
              icon: Icons.refresh_rounded,
              variant: ChunkyButtonVariant.secondary,
              size: ChunkyButtonSize.medium,
              onPressed: () => context.push('/dreams/review'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            10,
            GhinaSpace.page,
            6,
          ),
          child: ChunkySegmented<DreamView>(
            key: const ValueKey('dreams-view'),
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            segments: [
              for (final v in DreamView.values)
                ChunkySegment(value: v, label: v.label),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _noMatch()
              : switch (_view) {
                  DreamView.board => DreamBoardView(
                    rows: filtered,
                    categoryLabel: labelOf,
                    onOpen: _open,
                    onChangeStatus: _changeStatus,
                  ),
                  DreamView.table => DreamTableView(
                    rows: sorted,
                    categoryLabel: labelOf,
                    sort: _sort,
                    onSort: (s) => setState(() => _sort = s),
                    onOpen: _open,
                    onChangeStatus: _changeStatus,
                  ),
                  DreamView.timeline => DreamTimelineView(
                    rows: filtered,
                    onOpen: _open,
                    onChangeStatus: _changeStatus,
                  ),
                },
        ),
      ],
    );
  }

  Widget _noMatch() => ListView(
    padding: const EdgeInsets.all(GhinaSpace.page),
    children: [
      EmptyState(
        key: const ValueKey('dreams-no-match'),
        compact: true,
        title: 'Nggak ada yang cocok',
        message: 'Coba kata lain atau hapus filter.',
        mood: MascotMood.thinking,
        actionLabel: 'Reset',
        onAction: _reset,
      ),
    ],
  );
}

/// Counts per status, the open cost, stale and overdue counts, as chips.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.stats});

  final DreamStats stats;

  @override
  Widget build(BuildContext context) {
    final cost = stats.estimatedCostOpen;
    return SingleChildScrollView(
      key: const ValueKey('dreams-summary'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
      child: Row(
        children: [
          for (final s in DreamStatus.values)
            if ((stats.counts[s] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChunkyPill(
                  label: '${s.emoji} ${stats.counts[s]}',
                  color: dreamStatusColor(s),
                  soft: true,
                  uppercase: false,
                ),
              ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChunkyPill(
              label: 'Terbuka ${stats.open}',
              color: GhinaColors.blue,
              soft: true,
              uppercase: false,
            ),
          ),
          if (cost != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChunkyPill(
                label: 'Biaya terbuka ${context.money(cost)}',
                color: GhinaColors.purple,
                soft: true,
                uppercase: false,
              ),
            ),
          if (stats.stale > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChunkyPill(
                label: 'Basi ${stats.stale}',
                color: GhinaColors.yellow,
                soft: true,
                uppercase: false,
              ),
            ),
          if (stats.overdue > 0)
            ChunkyPill(
              label: 'Lewat target ${stats.overdue}',
              color: GhinaColors.red,
              soft: true,
              uppercase: false,
            ),
        ],
      ),
    );
  }
}
