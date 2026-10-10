import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// The inputs of the user's dimensions (`habitFields`), one per def, chosen by
/// its type: text, number, scale (chips `min..max`, a slider for wide ranges),
/// select (option chips) or boolean (Ya / Tidak). [values] holds what is set
/// (`String | num | bool`); [onChanged] gets the key and the new value, or
/// null when the user cleared it. A number typed badly is passed on as the raw
/// string so the save reports "harus angka".
class ExtraFieldsForm extends StatelessWidget {
  const ExtraFieldsForm({
    super.key,
    required this.defs,
    required this.values,
    required this.onChanged,
    this.errors = const {},
  });

  final List<HabitFieldDef> defs;
  final Map<String, Object> values;
  final void Function(String key, Object? value) onChanged;

  /// Error text per def key.
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final d in defs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ExtraFieldInput(
            def: d,
            value: values[d.key],
            errorText: errors[d.key],
            onChanged: (v) => onChanged(d.key, v),
          ),
        ),
    ],
  );
}

/// One dimension input; see [ExtraFieldsForm].
class ExtraFieldInput extends StatefulWidget {
  const ExtraFieldInput({
    super.key,
    required this.def,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final HabitFieldDef def;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  @override
  State<ExtraFieldInput> createState() => _ExtraFieldInputState();
}

class _ExtraFieldInputState extends State<ExtraFieldInput> {
  late final _ctrl = TextEditingController(text: _initialText());

  String _initialText() {
    final v = widget.value;
    if (v == null) return '';
    if (v is num && v == v.roundToDouble()) return v.toInt().toString();
    return '$v';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _text(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return widget.onChanged(null);
    if (widget.def.type == HabitFieldType.number) {
      final n = num.tryParse(t.replaceAll(',', '.'));
      if (n == null) return widget.onChanged(t);
      return widget.onChanged(n == n.roundToDouble() ? n.toInt() : n);
    }
    widget.onChanged(raw);
  }

  Widget _err(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      text,
      style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final key = ValueKey('extra-${def.key}');
    final v = widget.value;
    switch (def.type) {
      case HabitFieldType.text:
      case HabitFieldType.number:
        final number = def.type == HabitFieldType.number;
        return ChunkyTextField(
          key: key,
          label: def.label,
          controller: _ctrl,
          errorText: widget.errorText,
          onChanged: _text,
          maxLength: number ? null : habitExtraTextMax,
          keyboardType: number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
              : null,
        );
      case HabitFieldType.scale:
        final lo = fieldScaleMin(def);
        final hi = fieldScaleMax(def);
        final cur = v is num ? v.round() : null;
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(
              '${def.label} ($lo–$hi)',
              error: widget.errorText != null,
            ),
            if (hi - lo <= 11)
              ChunkyChoiceChips<int>(
                allowEmpty: true,
                options: [
                  for (var i = lo; i <= hi; i++)
                    ChunkyChoice(value: i, label: '$i'),
                ],
                selected: {?cur},
                onChanged: (s) => widget.onChanged(s.firstOrNull),
              )
            else
              Slider(
                value: (cur ?? lo).clamp(lo, hi).toDouble(),
                min: lo.toDouble(),
                max: hi.toDouble(),
                divisions: hi - lo,
                label: '${cur ?? lo}',
                onChanged: (x) => widget.onChanged(x.round()),
              ),
            if (widget.errorText != null) _err(widget.errorText!),
          ],
        );
      case HabitFieldType.select:
        final options = def.options ?? const <String>[];
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(def.label, error: widget.errorText != null),
            ChunkyChoiceChips<String>(
              allowEmpty: true,
              options: [
                for (final o in options) ChunkyChoice(value: o, label: o),
                // A stored option that was edited away stays visible.
                if (v is String && !options.contains(v))
                  ChunkyChoice(value: v, label: v),
              ],
              selected: {if (v is String) v},
              onChanged: (s) => widget.onChanged(s.firstOrNull),
            ),
            if (widget.errorText != null) _err(widget.errorText!),
          ],
        );
      case HabitFieldType.boolean:
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(def.label, error: widget.errorText != null),
            ChunkyChoiceChips<bool>(
              allowEmpty: true,
              options: const [
                ChunkyChoice(
                  value: true,
                  label: 'Ya',
                  icon: Icons.check_rounded,
                ),
                ChunkyChoice(
                  value: false,
                  label: 'Tidak',
                  icon: Icons.close_rounded,
                ),
              ],
              selected: {if (v is bool) v},
              onChanged: (s) => widget.onChanged(s.firstOrNull),
            ),
            if (widget.errorText != null) _err(widget.errorText!),
          ],
        );
    }
  }
}

/// Read-only chips `Label: value` of an `extra` map (in def order).
class ExtraValueChips extends StatelessWidget {
  const ExtraValueChips({super.key, required this.extra, required this.defs});

  final Map<String, Object> extra;
  final List<HabitFieldDef> defs;

  @override
  Widget build(BuildContext context) {
    final entries = extraEntries(extra, defs);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final e in entries)
          ChunkyPill(
            label: '${e.def.label}: ${formatExtraValue(e.def, e.value)}',
            color: GhinaColors.purple,
            soft: true,
            uppercase: false,
          ),
      ],
    );
  }
}

/// The patch to send for [current] edits of a row that held [original]: keys
/// the user cleared become null (removed), the rest are the new values.
Map<String, Object?> extraPatch(
  Map<String, Object> original,
  Map<String, Object> current,
) => {for (final k in original.keys) k: null, ...current};

/// Maps a [Failure]-less validation message to the def key it is about, so the
/// form can underline the right input. The server-style messages start with the
/// def label.
Map<String, String> extraErrorsFor(String message, List<HabitFieldDef> defs) {
  for (final d in defs) {
    if (message.startsWith(d.label)) return {d.key: message};
  }
  return const {};
}
