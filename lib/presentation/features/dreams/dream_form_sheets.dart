import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_target_input.dart';

/// Red caption under a field.
class DreamFormError extends StatelessWidget {
  const DreamFormError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      text,
      style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
    ),
  );
}

/// A day field: the picker plus a "Hapus" link once a day is set.
class DreamDateField extends StatelessWidget {
  const DreamDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.today,
    this.errorText,
    this.placeholder = 'Pilih tanggal',
  });

  final String label;

  /// `YYYY-MM-DD` or null.
  final String? value;
  final ValueChanged<String?> onChanged;
  final DateTime today;
  final String? errorText;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final current = dreamKeyToDate(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PickerField(
          label: label,
          value: value == null ? null : formatTarget(value),
          placeholder: placeholder,
          errorText: errorText,
          trailingIcon: current == null
              ? Icons.calendar_month_rounded
              : Icons.edit_calendar_rounded,
          onTap: () async {
            final d = await showGhinaDatePicker(
              context,
              initial: current ?? today,
              title: label,
              today: today,
            );
            if (d != null) onChanged(dreamDateKey(d));
          },
        ),
        if (current != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Hapus tanggal'),
            ),
          ),
      ],
    );
  }
}

/// Year (and month or quarter) picker of a month / quarter / year target.
/// Returns the picked [DreamPeriod], or null when dismissed.
Future<DreamPeriod?> showDreamPeriodSheet(
  BuildContext context, {
  required TargetPrecision precision,
  required DreamPeriod initial,
}) => showChunkyBottomSheet<DreamPeriod>(
  context,
  title: switch (precision) {
    TargetPrecision.quarter => 'Pilih kuartal',
    TargetPrecision.year => 'Pilih tahun',
    _ => 'Pilih bulan',
  },
  showClose: true,
  builder: (c) => _PeriodGrid(precision: precision, initial: initial),
);

class _PeriodGrid extends StatefulWidget {
  const _PeriodGrid({required this.precision, required this.initial});

  final TargetPrecision precision;
  final DreamPeriod initial;

  @override
  State<_PeriodGrid> createState() => _PeriodGridState();
}

class _PeriodGridState extends State<_PeriodGrid> {
  late int _year = widget.initial.year;

  Widget _cell(String key, String label, bool selected, DreamPeriod p) {
    final g = context.ghina;
    return ChunkySurface(
      key: ValueKey(key),
      color: selected ? GhinaColors.blue.light : g.surfaceAlt,
      edgeColor: selected ? GhinaColors.blue.base : g.border,
      borderColor: selected ? GhinaColors.blue.base : g.border,
      depth: 0,
      borderRadius: GhinaRadii.rLg,
      onTap: () => Navigator.of(context).pop(p),
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: GhinaType.bodyL
              .w(800)
              .copyWith(
                color: selected ? GhinaColors.blue.base : g.textPrimary,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final precision = widget.precision;
    final sameYear = _year == widget.initial.year;
    final cells = switch (precision) {
      TargetPrecision.quarter => [
        for (var q = 1; q <= 4; q++)
          _cell('period-q$q', 'Q$q', sameYear && q == widget.initial.index, (
            year: _year,
            index: q,
          )),
      ],
      TargetPrecision.year => [
        for (var y = _year - 4; y <= _year + 7; y++)
          _cell('period-y$y', '$y', y == widget.initial.year, (
            year: y,
            index: 1,
          )),
      ],
      _ => [
        for (var m = 1; m <= 12; m++)
          _cell(
            'period-m$m',
            dreamMonthShort[m - 1],
            sameYear && m == widget.initial.index,
            (year: _year, index: m),
          ),
      ],
    };
    final columns = precision == TargetPrecision.quarter ? 4 : 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ChunkyIconButton(
              icon: Icons.chevron_left_rounded,
              size: 40,
              tooltip: 'Sebelumnya',
              onPressed: () => setState(
                () => _year -= precision == TargetPrecision.year ? 12 : 1,
              ),
            ),
            Expanded(
              child: Text(
                precision == TargetPrecision.year
                    ? '${_year - 4} - ${_year + 7}'
                    : '$_year',
                textAlign: TextAlign.center,
                style: GhinaType.h2.w(900).copyWith(color: g.textPrimary),
              ),
            ),
            ChunkyIconButton(
              icon: Icons.chevron_right_rounded,
              size: 40,
              tooltip: 'Berikutnya',
              onPressed: () => setState(
                () => _year += precision == TargetPrecision.year ? 12 : 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: precision == TargetPrecision.quarter ? 1.8 : 2.2,
          children: cells,
        ),
      ],
    );
  }
}

/// One row of [showDreamPickSheet].
class DreamPickItem<T> {
  const DreamPickItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final T value;
  final String title;
  final String? subtitle;
  final String? leading;
}

/// A plain list sheet. The result wraps the choice so "none" (value null) can
/// be told from a dismissal (the whole result null).
Future<({T? value})?> showDreamPickSheet<T>(
  BuildContext context, {
  required String title,
  required List<DreamPickItem<T>> items,
  T? selected,
  String? noneLabel,
  String emptyMessage = 'Belum ada pilihan.',
}) => showChunkyBottomSheet<({T? value})>(
  context,
  title: title,
  showClose: true,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (noneLabel != null)
        _PickRow(
          key: const ValueKey('pick-none'),
          selected: selected == null,
          title: noneLabel,
          onTap: () => Navigator.of(c).pop((value: null)),
        ),
      for (final (i, it) in items.indexed)
        _PickRow(
          key: ValueKey('pick-$i'),
          selected: it.value == selected,
          title: it.title,
          subtitle: it.subtitle,
          leading: it.leading,
          onTap: () => Navigator.of(c).pop((value: it.value)),
        ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            emptyMessage,
            style: GhinaType.bodyS.copyWith(color: c.ghina.textSecondary),
          ),
        ),
    ],
  ),
);

class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final String? leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ChunkyTile(
      dense: true,
      tinted: selected ? GhinaColors.blue : null,
      leading: leading == null
          ? null
          : Text(leading!, style: const TextStyle(fontSize: 22)),
      title: title,
      subtitle: subtitle,
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: GhinaColors.blue.base)
          : null,
      onTap: onTap,
    ),
  );
}

/// Searchable sheet of the local notes. Returns the note id, `''` for "no
/// link", null when dismissed.
Future<String?> showDreamNoteSheet(
  BuildContext context, {
  String? selectedId,
}) => showChunkyBottomSheet<String>(
  context,
  title: 'Hubungkan catatan',
  showClose: true,
  builder: (c) => _NoteSheet(selectedId: selectedId),
);

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchNotesProvider(NoteFilter.all));
    final q = _q.trim().toLowerCase();
    final notes = [
      for (final n in async.value ?? const <NoteView>[])
        if (q.isEmpty || n.note.displayTitle.toLowerCase().contains(q)) n,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('note-search'),
          hint: 'Cari judul catatan',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 12),
        if (widget.selectedId != null)
          _PickRow(
            key: const ValueKey('note-none'),
            selected: false,
            title: 'Lepas tautan catatan',
            onTap: () => Navigator.of(context).pop(''),
          ),
        if (async.isLoading && !async.hasValue)
          const SkeletonList(count: 3)
        else if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              q.isEmpty
                  ? 'Belum ada catatan.'
                  : 'Nggak ada catatan dengan judul itu.',
              style: GhinaType.bodyS.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
          ),
        for (final n in notes)
          _PickRow(
            key: ValueKey('note-${n.id}'),
            selected: n.id == widget.selectedId,
            title: n.note.displayTitle,
            onTap: () => Navigator.of(context).pop(n.id),
          ),
      ],
    );
  }
}
