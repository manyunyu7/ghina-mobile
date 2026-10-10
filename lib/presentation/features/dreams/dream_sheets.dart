import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_list_logic.dart';
import 'dream_visuals.dart';

/// "Ubah status": the eight statuses; returns the picked one (null when
/// dismissed).
Future<DreamStatus?> showDreamStatusSheet(
  BuildContext context, {
  required DreamStatus current,
}) => showChunkyBottomSheet<DreamStatus>(
  context,
  title: 'Ubah status',
  showClose: true,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final s in DreamStatus.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            key: ValueKey('status-${s.wire}'),
            dense: true,
            leading: Text(s.emoji, style: const TextStyle(fontSize: 20)),
            title: s.label,
            tinted: s == current ? dreamStatusColor(s) : null,
            trailing: s == current ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.of(c).pop(s),
          ),
        ),
    ],
  ),
);

/// The filter sheet of the list. Returns the new filter (keeps the search
/// text), null when dismissed.
Future<DreamFilter?> showDreamFilterSheet(
  BuildContext context, {
  required DreamFilter current,
  required List<DreamCategory> categories,
  required List<String> tags,
}) => showChunkyBottomSheet<DreamFilter>(
  context,
  title: 'Filter mimpi',
  showClose: true,
  builder: (_) =>
      _DreamFilterSheet(current: current, categories: categories, tags: tags),
);

class _DreamFilterSheet extends StatefulWidget {
  const _DreamFilterSheet({
    required this.current,
    required this.categories,
    required this.tags,
  });

  final DreamFilter current;
  final List<DreamCategory> categories;
  final List<String> tags;

  @override
  State<_DreamFilterSheet> createState() => _DreamFilterSheetState();
}

class _DreamFilterSheetState extends State<_DreamFilterSheet> {
  late String? _category = widget.current.category;
  late DreamStatus? _status = widget.current.status;
  late String? _tag = widget.current.tag;
  late int? _priority = widget.current.priority;
  late bool _stale = widget.current.onlyStale;
  late bool _overdue = widget.current.onlyOverdue;

  DreamFilter get _result => DreamFilter(
    query: widget.current.query,
    category: _category,
    status: _status,
    tag: _tag,
    priority: _priority,
    onlyStale: _stale,
    onlyOverdue: _overdue,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Kategori'),
          ChunkyChoiceChips<String>(
            key: const ValueKey('filter-category'),
            scrollable: true,
            allowEmpty: true,
            options: [
              for (final c in widget.categories)
                ChunkyChoice(value: c.key, label: '${c.emoji} ${c.label}'),
            ],
            selected: {?_category},
            onChanged: (s) => setState(() => _category = s.firstOrNull),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Status'),
          ChunkyChoiceChips<String>(
            key: const ValueKey('filter-status'),
            // Eight short chips: wrap them rather than hide some sideways.
            allowEmpty: true,
            options: [
              for (final s in DreamStatus.values)
                ChunkyChoice(value: s.wire, label: dreamStatusText(s)),
            ],
            selected: {if (_status != null) _status!.wire},
            onChanged: (s) => setState(
              () => _status = DreamStatus.tryFromWire(s.firstOrNull),
            ),
          ),
          if (widget.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            const FieldLabel('Tag'),
            ChunkyChoiceChips<String>(
              key: const ValueKey('filter-tag'),
              scrollable: true,
              allowEmpty: true,
              options: [
                for (final t in widget.tags)
                  ChunkyChoice(value: t, label: '#$t'),
              ],
              selected: {?_tag},
              onChanged: (s) => setState(() => _tag = s.firstOrNull),
            ),
          ],
          const SizedBox(height: 14),
          const FieldLabel('Prioritas'),
          ChunkyChoiceChips<int>(
            key: const ValueKey('filter-priority'),
            allowEmpty: true,
            options: [
              for (var p = 1; p <= 5; p++) ChunkyChoice(value: p, label: 'P$p'),
            ],
            selected: {?_priority},
            onChanged: (s) => setState(() => _priority = s.firstOrNull),
          ),
          const SizedBox(height: 14),
          ChunkyChoiceChips<String>(
            key: const ValueKey('filter-flags'),
            multi: true,
            allowEmpty: true,
            options: const [
              ChunkyChoice(
                value: 'stale',
                label: 'Basi',
                icon: Icons.hourglass_bottom_rounded,
              ),
              ChunkyChoice(
                value: 'overdue',
                label: 'Lewat target',
                icon: Icons.event_busy_rounded,
              ),
            ],
            selected: {if (_stale) 'stale', if (_overdue) 'overdue'},
            onChanged: (s) => setState(() {
              _stale = s.contains('stale');
              _overdue = s.contains('overdue');
            }),
          ),
          const SizedBox(height: 18),
          ChunkyButton(
            key: const ValueKey('filter-apply'),
            label: 'Terapkan',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(_result),
          ),
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('filter-reset'),
            label: 'Reset filter',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(
              context,
            ).pop(DreamFilter(query: widget.current.query)),
          ),
        ],
      ),
    );
  }
}
