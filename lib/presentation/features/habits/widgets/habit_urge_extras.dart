import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'habit_extra_fields.dart';

/// The habit's coping tools on the emergency screen, grouped by kind. Each is
/// a tappable card: tap marks it as tried (a gentle check), the detail is
/// always visible. Shown next to the preset quick ideas.
class UrgeToolsList extends StatefulWidget {
  const UrgeToolsList({super.key, required this.tools});

  final List<HabitTool> tools;

  @override
  State<UrgeToolsList> createState() => _UrgeToolsListState();
}

class _UrgeToolsListState extends State<UrgeToolsList> {
  final Set<int> _tried = {};

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tools = widget.tools;
    if (tools.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('urge-tools'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ALAT BANTUMU:',
          style: GhinaType.overline.copyWith(color: g.textMuted),
        ),
        GhinaSpace.gapSm,
        for (final group in groupToolsByKind(tools)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              group.kind.label,
              style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
            ),
          ),
          for (final t in group.tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Builder(
                builder: (_) {
                  final i = tools.indexOf(t);
                  final done = _tried.contains(i);
                  return ChunkyTile(
                    key: ValueKey('urge-tool-$i'),
                    dense: true,
                    tinted: done ? GhinaColors.green : null,
                    leading: Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: done ? GhinaColors.green.base : g.textMuted,
                    ),
                    title: t.title,
                    subtitle: t.detail.isEmpty ? null : t.detail,
                    onTap: () => setState(() {
                      if (!_tried.remove(i)) _tried.add(i);
                    }),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}

/// Optional "catat detail" card of the emergency screen: the urge row exists
/// from the moment the screen opens, so the user's urge dimensions (e.g.
/// "Tingkat stres") are merged into it on demand. Hidden when no dimension
/// applies to `urge`.
class UrgeExtraCard extends ConsumerStatefulWidget {
  const UrgeExtraCard({super.key, required this.habitId, required this.ready});

  final String habitId;

  /// The urge row is logged (the save has something to attach to).
  final bool ready;

  @override
  ConsumerState<UrgeExtraCard> createState() => _UrgeExtraCardState();
}

class _UrgeExtraCardState extends ConsumerState<UrgeExtraCard> {
  bool _open = false;
  bool _saving = false;
  bool _saved = false;
  final Map<String, Object> _values = {};
  Map<String, String> _errors = const {};

  Future<void> _save(List<HabitFieldDef> defs) async {
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final r = await ref.read(setHabitLogExtraProvider)(
      widget.habitId,
      ref.read(clockProvider).now(),
      HabitLogType.urge,
      extraPatch(const {}, _values),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        setState(() {
          _saving = false;
          _saved = true;
          _open = false;
        });
        showOkToast(context, 'Detail tersimpan');
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(field: 'extra')) {
            _errors = extraErrorsFor(failure.message, defs);
          }
        });
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final defs = fieldsForScope(
      ref.watch(watchHabitFieldsProvider).value ?? const [],
      widget.habitId,
      'urge',
    );
    if (defs.isEmpty) return const SizedBox.shrink();
    if (!_open) {
      return ChunkyTile(
        key: const ValueKey('urge-extra-open'),
        dense: true,
        leading: Icon(
          _saved ? Icons.check_circle_rounded : Icons.tune_rounded,
          color: _saved ? GhinaColors.green.base : g.textSecondary,
        ),
        title: _saved ? 'Detail tersimpan' : 'Catat detail (opsional)',
        subtitle: _saved
            ? 'Ketuk untuk mengubah'
            : defs.map((d) => d.label).take(3).join(' · '),
        onTap: widget.ready ? () => setState(() => _open = true) : null,
      );
    }
    return ChunkyCard(
      key: const ValueKey('urge-extra-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExtraFieldsForm(
            defs: defs,
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
            key: const ValueKey('urge-extra-save'),
            label: 'Simpan detail',
            size: ChunkyButtonSize.small,
            loading: _saving,
            onPressed: _saving ? null : () => _save(defs),
          ),
        ],
      ),
    );
  }
}
