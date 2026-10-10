import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_target_input.dart';

/// The input of one Mimpi custom column, chosen by its definition type: text
/// (single / multi line), number, phone, email, url, date picker, option chips
/// or yes/no chips. [onChanged] gets `String | num | bool`, or null when the
/// user cleared it. A number the user typed badly is passed on as the raw
/// string so the save reports "harus berupa angka".
class DreamFieldInput extends StatefulWidget {
  const DreamFieldInput({
    super.key,
    required this.def,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.today,
  });

  final DreamFieldDef def;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? errorText;
  final DateTime? today;

  @override
  State<DreamFieldInput> createState() => _DreamFieldInputState();
}

class _DreamFieldInputState extends State<DreamFieldInput> {
  late final _ctrl = TextEditingController(text: _initialText());

  String _initialText() {
    final v = widget.value;
    if (v == null) return '';
    return widget.def.type == DreamFieldType.number
        ? formatDreamFieldValue(widget.def, v)
        : '$v';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _text(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return widget.onChanged(null);
    if (widget.def.type == DreamFieldType.number) {
      final n = num.tryParse(t.replaceAll(',', '.'));
      if (n == null) return widget.onChanged(t);
      return widget.onChanged(n == n.roundToDouble() ? n.toInt() : n);
    }
    widget.onChanged(raw);
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final key = ValueKey('field-${def.key}');
    switch (def.type) {
      case DreamFieldType.text:
      case DreamFieldType.longtext:
      case DreamFieldType.phone:
      case DreamFieldType.email:
      case DreamFieldType.url:
      case DreamFieldType.number:
        final long = def.type == DreamFieldType.longtext;
        return ChunkyTextField(
          key: key,
          label: def.label,
          controller: _ctrl,
          errorText: widget.errorText,
          onChanged: _text,
          keyboardType: switch (def.type) {
            DreamFieldType.phone => TextInputType.phone,
            DreamFieldType.email => TextInputType.emailAddress,
            DreamFieldType.url => TextInputType.url,
            DreamFieldType.number => const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            DreamFieldType.longtext => TextInputType.multiline,
            _ => TextInputType.text,
          },
          inputFormatters: def.type == DreamFieldType.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
              : null,
          textCapitalization:
              def.type == DreamFieldType.email || def.type == DreamFieldType.url
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          minLines: long ? 3 : null,
          maxLines: long ? 6 : 1,
        );
      case DreamFieldType.date:
        final v = widget.value;
        final current = v is String && isDreamDateKey(v)
            ? DateTime.parse(v)
            : null;
        return PickerField(
          key: key,
          label: def.label,
          value: current == null ? null : formatDreamFieldValue(def, v),
          placeholder: 'Pilih tanggal',
          errorText: widget.errorText,
          trailingIcon: current == null
              ? Icons.calendar_month_rounded
              : Icons.edit_calendar_rounded,
          onTap: () async {
            final d = await showGhinaDatePicker(
              context,
              initial: current ?? widget.today ?? DateTime.now(),
              title: def.label,
              today: widget.today,
            );
            if (d != null) widget.onChanged(dreamDateKey(d));
          },
        );
      case DreamFieldType.select:
        final options = def.options ?? const <String>[];
        final v = widget.value;
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
      case DreamFieldType.boolean:
        final v = widget.value;
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

  Widget _err(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      text,
      style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
    ),
  );
}
