import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/people_widgets.dart';

/// "Orang": contacts grouped by category (collapsible), searchable, with a tag
/// filter and the "Ulang tahun & tanggal penting terdekat" card on top.
class PeoplePage extends ConsumerStatefulWidget {
  const PeoplePage({super.key});

  @override
  ConsumerState<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends ConsumerState<PeoplePage> {
  final _search = TextEditingController();
  String _query = '';
  String? _tag;
  final _collapsed = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(String id) => context.push('/people/$id');

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(watchPeopleOverviewProvider);
    final total = async.value?.people.length ?? 0;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Orang'),
        actions: [
          IconButton(
            tooltip: 'Kategori & kolom',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push('/people/manage'),
          ),
          IconButton(
            tooltip: 'Orang baru',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => context.push('/people/new'),
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
                label: 'Orang baru',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => context.push('/people/new'),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => ScrollableFill(
            child: EmptyState(
              title: 'Belum ada orang',
              message:
                  'Simpan keluarga, teman, dan rekan penting — lengkap '
                  'dengan ulang tahun mereka 🎂',
              mood: MascotMood.waving,
              actionLabel: 'Tambah orang',
              onAction: () => context.push('/people/new'),
            ),
          ),
          AsyncData(:final value) => _list(value),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchPeopleOverviewProvider),
            ),
          ),
          _ => const LoadingListView(hero: false, tiles: 6),
        },
      ),
    );
  }

  Widget _list(PeopleOverview data) {
    final g = context.ghina;
    final upcoming =
        ref.watch(watchUpcomingPeopleProvider).value ?? const <UpcomingEvent>[];
    final tags = allTags(data.people);
    // A tag that no longer exists (deleted elsewhere) must not hide everyone.
    final tag = tags.any((t) => t.toLowerCase() == _tag?.toLowerCase())
        ? _tag
        : null;
    final groups = groupPeople(
      data.people,
      data.categories,
      defs: data.defs,
      query: _query,
      tag: tag,
    );
    final filtering = _query.trim().isNotEmpty || tag != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        ChunkyTextField(
          key: const ValueKey('people-search'),
          controller: _search,
          hint: 'Cari nama, hubungan, tag, isi kolom…',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.none,
          suffix: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          onChanged: (v) => setState(() => _query = v),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          ChunkyChoiceChips<String>(
            key: const ValueKey('people-tags'),
            scrollable: true,
            allowEmpty: true,
            options: [
              for (final t in tags) ChunkyChoice(value: t, label: '#$t'),
            ],
            selected: {?tag},
            onChanged: (s) => setState(() => _tag = s.firstOrNull),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 16),
          UpcomingPeopleCard(events: upcoming, onOpen: _open),
        ],
        const SizedBox(height: 16),
        if (groups.isEmpty)
          EmptyState(
            compact: true,
            title: 'Nggak ada yang cocok',
            message: 'Coba kata lain atau hapus filter tag.',
            mood: MascotMood.thinking,
            actionLabel: 'Reset',
            onAction: () => setState(() {
              _search.clear();
              _query = '';
              _tag = null;
            }),
          )
        else
          for (final grp in groups) ...[
            _GroupHeader(
              group: grp,
              collapsed: !filtering && _collapsed.contains(grp.categoryKey),
              onToggle: filtering
                  ? null
                  : () => setState(() {
                      if (!_collapsed.remove(grp.categoryKey)) {
                        _collapsed.add(grp.categoryKey);
                      }
                    }),
            ),
            if (filtering || !_collapsed.contains(grp.categoryKey))
              for (final (i, p) in grp.people.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PopIn(
                    delay: Duration(milliseconds: 30 * i.clamp(0, 6)),
                    child: PersonTile(person: p, onTap: () => _open(p.id)),
                  ),
                ),
            const SizedBox(height: 6),
          ],
        if (total(groups) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${total(groups)} orang',
              textAlign: TextAlign.center,
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
      ],
    );
  }

  static int total(List<PeopleGroup> groups) =>
      groups.fold(0, (n, g) => n + g.people.length);
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.onToggle,
  });

  final PeopleGroup group;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      expanded: !collapsed,
      label: '${group.label}, ${group.people.length} orang',
      child: InkWell(
        key: ValueKey('group-${group.categoryKey}'),
        onTap: onToggle,
        borderRadius: GhinaRadii.rMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(group.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.label,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              ChunkyPill(
                label: '${group.people.length}',
                color: GhinaColors.gray,
                soft: true,
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: GhinaMotion.fast,
                child: Icon(Icons.expand_more_rounded, color: g.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
