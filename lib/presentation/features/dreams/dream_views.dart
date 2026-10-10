import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import 'dream_cards.dart';
import 'dream_list_logic.dart';
import 'dream_visuals.dart';

/// Papan: one column per status, scrolled sideways. Every status has a column,
/// empty ones included.
class DreamBoardView extends StatelessWidget {
  const DreamBoardView({
    super.key,
    required this.rows,
    required this.categoryLabel,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final List<DreamRow> rows;
  final String Function(String key) categoryLabel;
  final ValueChanged<DreamRow> onOpen;
  final ValueChanged<DreamRow> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final columns = boardColumns(rows);
    // Eager columns (eight at most): a lazy list would leave the statuses
    // beyond the screen unbuilt, and a card moved there would vanish.
    return SingleChildScrollView(
      key: const ValueKey('dreams-board'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        4,
        GhinaSpace.page,
        24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final col in columns) _column(context, col)],
      ),
    );
  }

  Widget _column(BuildContext context, DreamBoardColumn col) {
    final g = context.ghina;
    final color = dreamStatusColor(col.status);
    return SizedBox(
      key: ValueKey('board-${col.status.wire}'),
      width: 264,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dreamStatusText(col.status),
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ChunkyPill(
                    label: '${col.rows.length}',
                    color: color,
                    soft: true,
                    uppercase: false,
                  ),
                ],
              ),
            ),
            Expanded(
              child: col.rows.isEmpty
                  ? Center(
                      child: Text(
                        'Belum ada',
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: col.rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, j) {
                        final r = col.rows[j];
                        return DreamBoardCard(
                          row: r,
                          categoryLabel: categoryLabel(r.dream.category),
                          onOpen: () => onOpen(r),
                          onChangeStatus: () => onChangeStatus(r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabel: compact sortable rows. The sort menu is the caller's (see
/// [DreamSortButton]); [rows] arrive already sorted.
class DreamTableView extends StatelessWidget {
  const DreamTableView({
    super.key,
    required this.rows,
    required this.categoryLabel,
    required this.sort,
    required this.onSort,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final List<DreamRow> rows;
  final String Function(String key) categoryLabel;
  final DreamSort sort;
  final ValueChanged<DreamSort> onSort;
  final ValueChanged<DreamRow> onOpen;
  final ValueChanged<DreamRow> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ListView(
      key: const ValueKey('dreams-table'),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        4,
        GhinaSpace.page,
        24,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Urut: ${sort.label}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
            DreamSortButton(sort: sort, onSelected: onSort),
          ],
        ),
        const SizedBox(height: 4),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DreamTableRow(
              row: r,
              categoryLabel: categoryLabel(r.dream.category),
              onOpen: () => onOpen(r),
              onChangeStatus: () => onChangeStatus(r),
            ),
          ),
      ],
    );
  }
}

/// The sort menu of the table.
class DreamSortButton extends StatelessWidget {
  const DreamSortButton({
    super.key,
    required this.sort,
    required this.onSelected,
  });

  final DreamSort sort;
  final ValueChanged<DreamSort> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<DreamSort>(
    key: const ValueKey('dreams-sort'),
    tooltip: 'Urutkan',
    icon: const Icon(Icons.sort_rounded),
    initialValue: sort,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final s in DreamSort.values)
        PopupMenuItem<DreamSort>(
          key: ValueKey('sort-${s.name}'),
          value: s,
          child: Text(s.label),
        ),
    ],
  );
}

/// Garis waktu: sections by target year / quarter, then horizon, undated last.
class DreamTimelineView extends StatelessWidget {
  const DreamTimelineView({
    super.key,
    required this.rows,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final List<DreamRow> rows;
  final ValueChanged<DreamRow> onOpen;
  final ValueChanged<DreamRow> onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final groups = timelineGroups(rows);
    return ListView(
      key: const ValueKey('dreams-timeline'),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        4,
        GhinaSpace.page,
        24,
      ),
      children: [
        for (final grp in groups) ...[
          Padding(
            key: ValueKey('timeline-${grp.key}'),
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    grp.label,
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                ),
                ChunkyPill(
                  label: '${grp.rows.length}',
                  color: GhinaColors.gray,
                  soft: true,
                  uppercase: false,
                ),
              ],
            ),
          ),
          for (final r in grp.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DreamTimelineTile(
                row: r,
                onOpen: () => onOpen(r),
                onChangeStatus: () => onChangeStatus(r),
              ),
            ),
        ],
      ],
    );
  }
}
