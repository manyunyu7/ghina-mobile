import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_form_sheets.dart';
import 'dream_target_input.dart';

/// What the target section holds: the stored (period end) date, its precision
/// and, while the typed text is not understood, [error].
typedef DreamTargetValue = ({
  String? date,
  TargetPrecision precision,
  String? error,
});

/// Target date with a precision: choose Tanggal / Bulan / Kuartal / Tahun, pick
/// the period, or type it ("Q1 2027", "Maret 2027", "2027").
class DreamTargetSection extends StatefulWidget {
  const DreamTargetSection({
    super.key,
    required this.initialDate,
    required this.initialPrecision,
    required this.today,
    required this.onChanged,
    this.errorText,
  });

  final String? initialDate;
  final TargetPrecision initialPrecision;
  final DateTime today;
  final ValueChanged<DreamTargetValue> onChanged;

  /// An error from the save (shown when the typed text itself is fine).
  final String? errorText;

  @override
  State<DreamTargetSection> createState() => _DreamTargetSectionState();
}

class _DreamTargetSectionState extends State<DreamTargetSection> {
  late final _text = TextEditingController(
    text: formatTarget(widget.initialDate, widget.initialPrecision),
  );
  late String? _date = widget.initialDate;
  late TargetPrecision _precision = widget.initialPrecision;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged((date: _date, precision: _precision, error: _error));

  void _set(String? date, TargetPrecision precision) {
    setState(() {
      _date = date;
      _precision = precision;
      _error = null;
      _text.text = formatTarget(date, precision);
    });
    _emit();
  }

  void _typed(String raw) {
    final r = parseTargetText(raw);
    setState(() {
      _error = r.error;
      if (r.target != null) {
        _date = r.target!.date;
        _precision = r.target!.precision;
      } else if (r.error == null) {
        _date = null;
      }
    });
    _emit();
  }

  void _choosePrecision(TargetPrecision p) {
    setState(() {
      _precision = p;
      _error = null;
      _date = resnapTarget(_date, p);
      _text.text = formatTarget(_date, p);
    });
    _emit();
  }

  Future<void> _pick() async {
    if (_precision == TargetPrecision.day) {
      final d = await showGhinaDatePicker(
        context,
        initial: dreamKeyToDate(_date) ?? widget.today,
        title: 'Target tanggal',
        today: widget.today,
      );
      if (d != null) _set(dreamDateKey(d), TargetPrecision.day);
      return;
    }
    final initial =
        periodOfTarget(_date, _precision) ??
        periodOfTarget(dreamDateKey(widget.today), _precision)!;
    final p = await showDreamPeriodSheet(
      context,
      precision: _precision,
      initial: initial,
    );
    if (p != null) _set(periodTargetDate(_precision, p), _precision);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final error = _error ?? widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Target waktu', error: error != null),
        ChunkyChoiceChips<TargetPrecision>(
          key: const ValueKey('dream-target-precision'),
          options: [
            for (final p in TargetPrecision.values)
              ChunkyChoice(value: p, label: p.label),
          ],
          selected: {_precision},
          onChanged: (s) => _choosePrecision(s.first),
        ),
        const SizedBox(height: 10),
        PickerField(
          key: const ValueKey('dream-target-picker'),
          label: 'Pilih ${_precision.label.toLowerCase()}',
          value: _date == null ? null : formatTarget(_date, _precision),
          placeholder: 'Belum ditentukan',
          trailingIcon: Icons.calendar_month_rounded,
          onTap: _pick,
        ),
        const SizedBox(height: 10),
        ChunkyTextField(
          key: const ValueKey('dream-target-text'),
          label: 'Atau ketik',
          hint: 'mis. Q1 2027, Maret 2027, 2027',
          controller: _text,
          errorText: error,
          textCapitalization: TextCapitalization.none,
          onChanged: _typed,
          suffix: _text.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('dream-target-clear'),
                  tooltip: 'Hapus target',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _set(null, _precision),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'Disimpan di akhir periodenya, jadi "Q1 2027" jatuh di 31 Maret 2027.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
      ],
    );
  }
}
