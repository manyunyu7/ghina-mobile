import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/ids.dart';
import '../../../di/di.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_form_models.dart';
import 'dream_form_sheets.dart';
import 'dream_target_input.dart';

/// Add / edit one step. [metrics] are the dream's metrics a step can hang on.
Future<DraftResult<StepDraft>?> showDreamStepSheet(
  BuildContext context, {
  StepDraft? existing,
  required List<MetricDraft> metrics,
}) => showChunkyBottomSheet<DraftResult<StepDraft>>(
  context,
  title: existing == null ? 'Langkah baru' : 'Ubah langkah',
  showClose: true,
  builder: (c) => _StepSheet(existing: existing, metrics: metrics),
);

class _StepSheet extends ConsumerStatefulWidget {
  const _StepSheet({this.existing, required this.metrics});

  final StepDraft? existing;
  final List<MetricDraft> metrics;

  @override
  ConsumerState<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends ConsumerState<_StepSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _reward = TextEditingController(text: widget.existing?.reward);
  late final _cost = TextEditingController(text: _num(widget.existing?.cost));
  late final _at = TextEditingController(text: _num(widget.existing?.atValue));
  late String? _due = widget.existing?.dueDate;
  late bool _done = widget.existing?.done ?? false;
  late String? _metricRef = widget.existing?.metricRef;
  Map<String, String> _errors = const {};

  static String _num(double? v) => v == null
      ? ''
      : v == v.roundToDouble()
      ? v.toInt().toString()
      : '$v';

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _reward.dispose();
    _cost.dispose();
    _at.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _save() {
    final errors = <String, String>{};
    double? number(TextEditingController c, String key, String msg) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      final n = parseDreamAmount(t);
      if (n == null) errors[key] = msg;
      return n;
    }

    final cost = number(_cost, 'cost', 'Biaya harus berupa angka');
    final at = number(_at, 'metricRef', 'Nilai ambang harus berupa angka');
    if (_title.text.trim().isEmpty) {
      errors['title'] = 'Judul langkah wajib diisi';
    }
    final draft = StepDraft(
      id: widget.existing?.id ?? newId(),
      title: _title.text.trim(),
      notes: _text(_notes),
      done: _done,
      dueDate: _due,
      cost: cost,
      reward: _text(_reward),
      metricRef: _metricRef,
      atValue: _metricRef == null ? null : at,
      persisted: widget.existing?.persisted ?? false,
    );
    if (errors.isEmpty) {
      // The domain rules say what is wrong (lengths, negative cost, the
      // metric/threshold pair) in their own words.
      try {
        validateDreamStep(
          id: draft.id,
          dreamId: 'draft',
          input: draft.toInput(),
          now: ref.read(clockProvider).now(),
        );
      } on ValidationFailure catch (f) {
        errors[f.field ?? 'title'] = f.message;
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(DraftResult.save(draft));
  }

  Future<void> _pickMetric() async {
    final r = await showDreamPickSheet<String>(
      context,
      title: 'Hubungkan ke metrik',
      noneLabel: 'Tanpa metrik',
      selected: _metricRef,
      items: [
        for (final m in widget.metrics)
          DreamPickItem(value: m.id, title: m.label, subtitle: m.source.label),
      ],
      emptyMessage: 'Belum ada metrik. Tambah metrik dulu di bagian Metrik.',
    );
    if (r == null || !mounted) return;
    setState(() {
      _metricRef = r.value;
      if (r.value == null) _at.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final now = ref.read(clockProvider).now();
    final metricLabel = _metricRef == null
        ? null
        : widget.metrics
                  .where((m) => m.id == _metricRef)
                  .map((m) => m.label)
                  .firstOrNull ??
              'Metrik tidak ditemukan';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('step-title'),
          label: 'Judul langkah',
          hint: 'mis. Tentukan tanggal berangkat',
          controller: _title,
          maxLength: stepTitleMax,
          errorText: _errors['title'],
        ),
        const SizedBox(height: 14),
        ChunkyTextField(
          key: const ValueKey('step-notes'),
          label: 'Catatan (opsional)',
          controller: _notes,
          maxLength: stepNotesMax,
          minLines: 2,
          maxLines: 4,
          errorText: _errors['notes'],
        ),
        const SizedBox(height: 14),
        DreamDateField(
          key: const ValueKey('step-due'),
          label: 'Tenggat (opsional)',
          value: _due,
          today: now,
          errorText: _errors['dueDate'],
          onChanged: (v) => setState(() => _due = v),
        ),
        const SizedBox(height: 6),
        ChunkyTextField(
          key: const ValueKey('step-cost'),
          label: 'Biaya (opsional)',
          hint: 'Rp',
          controller: _cost,
          prefixIcon: Icons.payments_rounded,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: _errors['cost'],
        ),
        const SizedBox(height: 14),
        ChunkyTextField(
          key: const ValueKey('step-reward'),
          label: 'Hadiah kalau selesai (opsional)',
          hint: 'mis. Makan enak',
          controller: _reward,
          maxLength: stepRewardMax,
          errorText: _errors['reward'],
        ),
        const SizedBox(height: 14),
        PickerField(
          key: const ValueKey('step-metric'),
          label: 'Metrik terkait (opsional)',
          value: metricLabel,
          placeholder: 'Tanpa metrik',
          errorText: _metricRef == null ? _errors['metricRef'] : null,
          onTap: _pickMetric,
        ),
        if (_metricRef != null) ...[
          const SizedBox(height: 14),
          ChunkyTextField(
            key: const ValueKey('step-at'),
            label: 'Selesai otomatis di nilai',
            hint: 'mis. 70',
            controller: _at,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            errorText: _errors['metricRef'],
            helperText:
                'Langkah ini dianggap selesai saat metrik mencapai nilai itu.',
          ),
        ],
        const SizedBox(height: 14),
        InkWell(
          key: const ValueKey('step-done'),
          onTap: () => setState(() => _done = !_done),
          child: Row(
            children: [
              Checkbox(
                value: _done,
                onChanged: (v) => setState(() => _done = v ?? false),
              ),
              Expanded(
                child: Text(
                  'Sudah selesai',
                  style: GhinaType.bodyL.w(700).copyWith(color: g.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ChunkyButton(
          key: const ValueKey('step-sheet-save'),
          label: 'Simpan langkah',
          icon: Icons.check_rounded,
          onPressed: _save,
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('step-sheet-delete'),
            label: 'Hapus langkah',
            variant: ChunkyButtonVariant.outline,
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(
              context,
            ).pop(const DraftResult<StepDraft>.remove()),
          ),
        ],
      ],
    );
  }
}
