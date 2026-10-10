import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'habit_extra_fields.dart';

/// "Tambah detail" after a check-in: only when the user's dimensions list
/// `done` explicitly in `appliesTo` (so the one-tap check-in stays one tap) and
/// today's `done` row exists. Opens a sheet with the inputs; the values are
/// merged into that row.
class HabitDoneDetailTile extends ConsumerWidget {
  const HabitDoneDetailTile({
    super.key,
    required this.habit,
    required this.logs,
  });

  final Habit habit;

  /// The rows the screen already has (newest first).
  final List<HabitLog> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateKey(ref.watch(clockProvider).now());
    final row = logs
        .where(
          (l) =>
              l.date == today &&
              l.type == HabitLogType.done &&
              l.habitId == habit.id,
        )
        .firstOrNull;
    final defs = fieldsForScope(
      ref.watch(watchHabitFieldsProvider).value ?? const [],
      habit.id,
      'done',
    );
    if (row == null || defs.isEmpty) return const SizedBox.shrink();
    final filled = row.extra.keys.any((k) => defs.any((d) => d.key == k));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ChunkyTile(
        key: const ValueKey('done-detail'),
        dense: true,
        leading: Icon(
          filled ? Icons.check_circle_rounded : Icons.tune_rounded,
          color: filled ? GhinaColors.green.base : context.ghina.textSecondary,
        ),
        title: filled ? 'Detail hari ini' : 'Tambah detail hari ini',
        subtitle: defs.map((d) => d.label).take(3).join(' · '),
        showChevron: true,
        onTap: () => showChunkyBottomSheet<void>(
          context,
          title: 'Detail hari ini',
          showClose: true,
          builder: (_) => _DoneDetailForm(habit: habit, row: row, defs: defs),
        ),
      ),
    );
  }
}

class _DoneDetailForm extends ConsumerStatefulWidget {
  const _DoneDetailForm({
    required this.habit,
    required this.row,
    required this.defs,
  });

  final Habit habit;
  final HabitLog row;
  final List<HabitFieldDef> defs;

  @override
  ConsumerState<_DoneDetailForm> createState() => _DoneDetailFormState();
}

class _DoneDetailFormState extends ConsumerState<_DoneDetailForm> {
  late final Map<String, Object> _values = _original();

  Map<String, Object> _original() => {
    for (final d in widget.defs)
      if (widget.row.extra.containsKey(d.key)) d.key: widget.row.extra[d.key]!,
  };
  Map<String, String> _errors = const {};
  bool _saving = false;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final original = _original();
    final r = await ref.read(setHabitLogExtraProvider)(
      widget.habit.id,
      parseDateKey(widget.row.date),
      HabitLogType.done,
      extraPatch(original, _values),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(field: 'extra')) {
            _errors = extraErrorsFor(failure.message, widget.defs);
          }
        });
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExtraFieldsForm(
            defs: widget.defs,
            values: _values,
            errors: _errors,
            onChanged: (k, v) => setState(() {
              if (v == null) {
                _values.remove(k);
              } else {
                _values[k] = v;
              }
            }),
          ),
          ChunkyButton(
            key: const ValueKey('done-detail-save'),
            label: 'Simpan',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );
}
