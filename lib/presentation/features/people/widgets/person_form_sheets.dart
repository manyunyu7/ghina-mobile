import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'people_widgets.dart' show SwitchRow;

/// Bottom sheet that picks a month (1–12) or clears it.
Future<int?> pickMonth(BuildContext context, {int? current}) async {
  final r = await showChunkyBottomSheet<int>(
    context,
    title: 'Pilih bulan',
    showClose: true,
    builder: (c) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var m = 1; m <= 12; m++)
          ChunkyChip(
            key: ValueKey('month-$m'),
            label: monthNameId(m),
            selected: current == m,
            onTap: () => Navigator.of(c).pop(m),
          ),
        ChunkyChip(
          key: const ValueKey('month-none'),
          label: 'Kosongkan',
          icon: Icons.clear_rounded,
          color: GhinaColors.gray,
          selected: false,
          onTap: () => Navigator.of(c).pop(0),
        ),
      ],
    ),
  );
  return r;
}

/// Add / edit one important date. Returns the validated input (the person's
/// save re-validates it) or null when dismissed. [delete] true = remove.
Future<({PersonDateInput? input, bool delete})?> showPersonDateSheet(
  BuildContext context, {
  PersonDateInput? existing,
  required int currentYear,
}) => showChunkyBottomSheet<({PersonDateInput? input, bool delete})>(
  context,
  title: existing == null ? 'Tanggal penting baru' : 'Ubah tanggal penting',
  showClose: true,
  builder: (c) => _PersonDateForm(existing: existing, currentYear: currentYear),
);

class _PersonDateForm extends StatefulWidget {
  const _PersonDateForm({required this.existing, required this.currentYear});

  final PersonDateInput? existing;
  final int currentYear;

  @override
  State<_PersonDateForm> createState() => _PersonDateFormState();
}

class _PersonDateFormState extends State<_PersonDateForm> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _day = TextEditingController(
    text: widget.existing?.day.toString() ?? '',
  );
  late final _year = TextEditingController(
    text: widget.existing?.year?.toString() ?? '',
  );
  late PersonDateKind _kind = widget.existing?.kind ?? PersonDateKind.custom;
  late int? _month = widget.existing?.month;
  late int? _remind = widget.existing?.remindDaysBefore;
  String? _error;

  static const _remindPresets = [1, 3, 7, 14, 30];

  @override
  void dispose() {
    _label.dispose();
    _day.dispose();
    _year.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    final day = int.tryParse(_day.text.trim());
    final year = _year.text.trim().isEmpty
        ? null
        : int.tryParse(_year.text.trim());
    String? err;
    if (label.isEmpty) {
      err = 'Kasih label dulu, ya';
    } else if (label.length > dateLabelMax) {
      err = 'Label terlalu panjang (maks $dateLabelMax)';
    } else if (_month == null || day == null) {
      err = 'Isi tanggal dan bulannya';
    } else if (_year.text.trim().isNotEmpty && year == null) {
      err = 'Tahun harus berupa angka';
    } else {
      err = dateError(
        month: _month!,
        day: day,
        year: year,
        currentYear: widget.currentYear,
      );
    }
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop((
      input: PersonDateInput(
        id: widget.existing?.id,
        label: label,
        kind: _kind,
        month: _month!,
        day: day!,
        year: year,
        remindDaysBefore: _remind,
      ),
      delete: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final remindOptions = {
      ..._remindPresets,
      if (_remind != null && _remind! > 0) _remind!,
    }.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChunkyTextField(
              key: const ValueKey('date-label'),
              label: 'Label',
              hint: 'mis. Hari jadi',
              controller: _label,
              maxLength: dateLabelMax,
            ),
            const SizedBox(height: 12),
            const FieldLabel('Jenis'),
            ChunkyChoiceChips<PersonDateKind>(
              options: [
                for (final k in PersonDateKind.values)
                  ChunkyChoice(
                    value: k,
                    label: '${k.eventKind.emoji} ${k.eventKind.label}',
                  ),
              ],
              selected: {_kind},
              onChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ChunkyTextField(
                    key: const ValueKey('date-day'),
                    label: 'Tanggal',
                    controller: _day,
                    keyboardType: TextInputType.number,
                    maxLength: 2,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PickerField(
                    label: 'Bulan',
                    value: _month == null ? null : monthNameId(_month!),
                    placeholder: 'Pilih',
                    onTap: () async {
                      final m = await pickMonth(context, current: _month);
                      if (m != null) setState(() => _month = m == 0 ? null : m);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChunkyTextField(
                    key: const ValueKey('date-year'),
                    label: 'Tahun',
                    hint: 'opsional',
                    controller: _year,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const FieldLabel('Ingatkan sebelumnya'),
            ChunkyChoiceChips<int>(
              options: [
                const ChunkyChoice(value: 0, label: 'Hari-H saja'),
                for (final d in remindOptions)
                  ChunkyChoice(value: d, label: '$d hari'),
              ],
              selected: {_remind ?? 0},
              onChanged: (s) =>
                  setState(() => _remind = s.first == 0 ? null : s.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Notifikasi selalu muncul jam 09.00 di hari-H.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  key: const ValueKey('date-error'),
                  style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
                ),
              ),
            const SizedBox(height: 16),
            ChunkyButton(
              key: const ValueKey('date-save'),
              label: 'Simpan tanggal',
              icon: Icons.check_rounded,
              onPressed: _save,
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              ChunkyButton(
                key: const ValueKey('date-delete'),
                label: 'Hapus tanggal ini',
                variant: ChunkyButtonVariant.ghost,
                color: GhinaColors.red,
                icon: Icons.delete_outline_rounded,
                onPressed: () =>
                    Navigator.of(context).pop((input: null, delete: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Tambah kolom": creates a custom-field definition (`personFields`) and
/// returns it.
Future<PersonFieldDef?> showAddFieldSheet(BuildContext context) =>
    showChunkyBottomSheet<PersonFieldDef>(
      context,
      title: 'Tambah kolom',
      showClose: true,
      builder: (c) => const AddFieldForm(),
    );

class AddFieldForm extends ConsumerStatefulWidget {
  const AddFieldForm({super.key});

  @override
  ConsumerState<AddFieldForm> createState() => _AddFieldFormState();
}

class _AddFieldFormState extends ConsumerState<AddFieldForm> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  PersonFieldType _type = PersonFieldType.text;
  bool _showInList = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(createPersonFieldProvider)(
      PersonFieldInput(
        label: _label.text,
        type: _type,
        options: _type == PersonFieldType.select
            ? _options.text.split(RegExp(r'[,\n]'))
            : null,
        showInList: _showInList,
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() {
          _saving = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChunkyTextField(
              key: const ValueKey('field-label'),
              label: 'Nama kolom',
              hint: 'mis. Ukuran sepatu',
              controller: _label,
              maxLength: fieldLabelMax,
            ),
            const SizedBox(height: 12),
            const FieldLabel('Jenis isi'),
            ChunkyChoiceChips<PersonFieldType>(
              options: [
                for (final t in PersonFieldType.values)
                  ChunkyChoice(value: t, label: t.label),
              ],
              selected: {_type},
              onChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == PersonFieldType.select) ...[
              const SizedBox(height: 12),
              ChunkyTextField(
                key: const ValueKey('field-options'),
                label: 'Pilihan',
                hint: 'Pisahkan dengan koma: A, B, AB, O',
                controller: _options,
                minLines: 1,
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 8),
            SwitchRow(
              title: 'Tampilkan di daftar',
              value: _showInList,
              onChanged: (v) => setState(() => _showInList = v),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('field-error'),
                style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
              ),
            const SizedBox(height: 12),
            ChunkyButton(
              key: const ValueKey('field-save'),
              label: 'Buat kolom',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
