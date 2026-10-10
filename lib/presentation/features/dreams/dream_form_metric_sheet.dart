import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../core/ids.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_form_models.dart';
import 'dream_form_sheets.dart';
import 'dream_target_input.dart';

/// Add / edit one metric of a dream.
Future<DraftResult<MetricDraft>?> showDreamMetricSheet(
  BuildContext context, {
  MetricDraft? existing,
}) => showChunkyBottomSheet<DraftResult<MetricDraft>>(
  context,
  title: existing == null ? 'Metrik baru' : 'Ubah metrik',
  showClose: true,
  builder: (c) => _MetricSheet(existing: existing),
);

class _MetricSheet extends ConsumerStatefulWidget {
  const _MetricSheet({this.existing});

  final MetricDraft? existing;

  @override
  ConsumerState<_MetricSheet> createState() => _MetricSheetState();
}

class _MetricSheetState extends ConsumerState<_MetricSheet> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _unit = TextEditingController(text: widget.existing?.unit);
  late final _start = TextEditingController(
    text: _num(widget.existing?.startValue),
  );
  late final _target = TextEditingController(
    text: widget.existing == null ? '' : _num(widget.existing!.targetValue),
  );
  late final _manual = TextEditingController(
    text: _num(widget.existing?.manualValue),
  );
  late MetricSource _source = widget.existing?.source ?? MetricSource.manual;
  late String? _refId = readSourceRef(
    _source,
    widget.existing?.sourceRef,
  ).refId;
  late SpendPeriod _period = readSourceRef(
    _source,
    widget.existing?.sourceRef,
  ).period;
  late MetricDirection? _direction = widget.existing?.direction;
  late String? _startDate = widget.existing?.startDate;
  late String? _targetDate = widget.existing?.targetDate;
  late String? _manualDay = widget.existing?.manualAt == null
      ? null
      : dreamDateKey(widget.existing!.manualAt!);
  Map<String, String> _errors = const {};

  static String _num(double? v) => v == null
      ? ''
      : v == v.roundToDouble()
      ? v.toInt().toString()
      : '$v';

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _start.dispose();
    _target.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    final r = await showDreamPickSheet<MetricSource>(
      context,
      title: 'Sumber nilai',
      selected: _source,
      items: [
        for (final s in MetricSource.values)
          DreamPickItem(
            value: s,
            title: s.label,
            subtitle: s.isManual ? 'Kamu catat sendiri' : 'Dihitung otomatis',
          ),
      ],
    );
    final v = r?.value;
    if (v == null || !mounted || v == _source) return;
    setState(() {
      _source = v;
      _refId = null;
      _errors = const {};
    });
  }

  /// Name + id rows of what the current source can point at.
  List<DreamPickItem<String>> _refItems() => switch (_source.refKind) {
    MetricRefKind.habit => [
      for (final h in ref.read(watchAllHabitsProvider).value ?? const <Habit>[])
        DreamPickItem(value: h.id, title: h.name),
    ],
    MetricRefKind.wallet => [
      for (final w
          in ref.read(watchAllWalletsProvider).value ?? const <Wallet>[])
        DreamPickItem(value: w.id, title: w.name),
    ],
    MetricRefKind.category => [
      for (final c
          in ref.read(watchCategoriesProvider(CategoryType.expense)).value ??
              const <TxCategory>[])
        DreamPickItem(value: c.id, title: c.name),
    ],
    MetricRefKind.none => const [],
  };

  Future<void> _pickRef() async {
    final items = _refItems();
    final r = await showDreamPickSheet<String>(
      context,
      title: switch (_source.refKind) {
        MetricRefKind.habit => 'Pilih kebiasaan',
        MetricRefKind.wallet => 'Pilih dompet',
        _ => 'Pilih kategori',
      },
      items: items,
      selected: _refId,
      emptyMessage: 'Belum ada pilihan di sini.',
    );
    final v = r?.value;
    if (v == null || !mounted) return;
    setState(() => _refId = v);
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

    final start = number(_start, 'startValue', 'Nilai awal harus berupa angka');
    final manual = _source.isManual
        ? number(_manual, 'manualValue', 'Nilai saat ini harus berupa angka')
        : null;
    double target = 0;
    if (_target.text.trim().isEmpty) {
      errors['targetValue'] = 'Nilai target wajib diisi';
    } else {
      target =
          number(_target, 'targetValue', 'Nilai target harus berupa angka') ??
          0;
    }
    if (_label.text.trim().isEmpty) errors['label'] = 'Label wajib diisi';
    if (_source.refKind != MetricRefKind.none && _refId == null) {
      errors['sourceRef'] = 'Pilih dulu yang mau dipantau';
    }
    final existing = widget.existing;
    DateTime? manualAt;
    if (manual != null && _manualDay != null) {
      final prev = existing?.manualAt;
      manualAt = prev != null && dreamDateKey(prev) == _manualDay
          ? prev
          : dreamKeyToDate(_manualDay);
    }
    final unit = _unit.text.trim();
    final draft = MetricDraft(
      id: existing?.id ?? newId(),
      label: _label.text.trim(),
      source: _source,
      sourceRef: buildSourceRef(_source, refId: _refId, period: _period),
      direction: _direction,
      unit: unit.isEmpty ? null : unit,
      startValue: start,
      startDate: _startDate,
      targetValue: target,
      targetDate: _targetDate,
      manualValue: manual,
      manualAt: manualAt,
      persisted: existing?.persisted ?? false,
    );
    if (errors.isEmpty) {
      try {
        validateDreamMetric(
          id: draft.id,
          dreamId: 'draft',
          input: draft.toInput(),
          now: ref.read(clockProvider).now(),
        );
      } on ValidationFailure catch (f) {
        errors[f.field ?? 'label'] = f.message;
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.of(context).pop(DraftResult.save(draft));
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider).now();
    // Watched so the lists are loaded (and kept) by the time a picker opens.
    switch (_source.refKind) {
      case MetricRefKind.habit:
        ref.watch(watchAllHabitsProvider);
      case MetricRefKind.wallet:
        ref.watch(watchAllWalletsProvider);
      case MetricRefKind.category:
        ref.watch(watchCategoriesProvider(CategoryType.expense));
      case MetricRefKind.none:
        break;
    }
    String? refName;
    if (_refId != null) {
      refName =
          _refItems()
              .where((i) => i.value == _refId)
              .map((i) => i.title)
              .firstOrNull ??
          'Tidak ditemukan';
    }
    final refLabel = switch (_source.refKind) {
      MetricRefKind.habit => 'Kebiasaan',
      MetricRefKind.wallet => 'Dompet',
      _ => 'Kategori pengeluaran',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerField(
          key: const ValueKey('metric-source'),
          label: 'Sumber nilai',
          value: _source.label,
          onTap: _pickSource,
        ),
        if (_source.refKind != MetricRefKind.none) ...[
          const SizedBox(height: 14),
          PickerField(
            key: const ValueKey('metric-ref'),
            label: refLabel,
            value: refName,
            placeholder: 'Pilih',
            errorText: _errors['sourceRef'],
            onTap: _pickRef,
          ),
        ],
        if (_source.refKind == MetricRefKind.category) ...[
          const SizedBox(height: 14),
          const FieldLabel('Periode'),
          ChunkyChoiceChips<SpendPeriod>(
            key: const ValueKey('metric-period'),
            options: [
              for (final p in SpendPeriod.values)
                ChunkyChoice(value: p, label: p.label),
            ],
            selected: {_period},
            onChanged: (s) => setState(() => _period = s.first),
          ),
        ],
        const SizedBox(height: 14),
        ChunkyTextField(
          key: const ValueKey('metric-label'),
          label: 'Label',
          hint: 'mis. Berat badan',
          controller: _label,
          maxLength: metricLabelMax,
          errorText: _errors['label'],
        ),
        const SizedBox(height: 14),
        const FieldLabel('Arah (opsional)'),
        ChunkyChoiceChips<MetricDirection>(
          key: const ValueKey('metric-direction'),
          allowEmpty: true,
          options: const [
            ChunkyChoice(
              value: MetricDirection.down,
              label: 'Turun',
              icon: Icons.south_rounded,
            ),
            ChunkyChoice(
              value: MetricDirection.up,
              label: 'Naik',
              icon: Icons.north_rounded,
            ),
          ],
          selected: {?_direction},
          onChanged: (s) => setState(() => _direction = s.firstOrNull),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'Kosong berarti otomatis: turun kalau target di bawah nilai awal.',
            style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          ),
        ),
        const SizedBox(height: 14),
        ChunkyTextField(
          key: const ValueKey('metric-unit'),
          label: 'Satuan (opsional)',
          hint: _source.defaultUnit.isEmpty ? 'mis. kg' : _source.defaultUnit,
          controller: _unit,
          maxLength: metricUnitMax,
          textCapitalization: TextCapitalization.none,
          errorText: _errors['unit'],
        ),
        const SizedBox(height: 14),
        ChunkyTextField(
          key: const ValueKey('metric-start'),
          label: 'Nilai awal (opsional)',
          controller: _start,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          errorText: _errors['startValue'],
        ),
        const SizedBox(height: 6),
        DreamDateField(
          key: const ValueKey('metric-start-date'),
          label: 'Tanggal mulai (opsional)',
          value: _startDate,
          today: now,
          errorText: _errors['startDate'],
          onChanged: (v) => setState(() => _startDate = v),
        ),
        const SizedBox(height: 6),
        ChunkyTextField(
          key: const ValueKey('metric-target'),
          label: 'Nilai target',
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          errorText: _errors['targetValue'],
        ),
        const SizedBox(height: 6),
        DreamDateField(
          key: const ValueKey('metric-target-date'),
          label: 'Tanggal target (opsional)',
          value: _targetDate,
          today: now,
          errorText: _errors['targetDate'],
          onChanged: (v) => setState(() => _targetDate = v),
        ),
        if (_source.isManual) ...[
          const SizedBox(height: 6),
          ChunkyTextField(
            key: const ValueKey('metric-manual'),
            label: 'Nilai saat ini (opsional)',
            controller: _manual,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            errorText: _errors['manualValue'],
          ),
          const SizedBox(height: 6),
          DreamDateField(
            key: const ValueKey('metric-manual-date'),
            label: 'Dicatat pada (opsional)',
            value: _manualDay,
            today: now,
            placeholder: 'Hari ini',
            onChanged: (v) => setState(() => _manualDay = v),
          ),
        ],
        const SizedBox(height: 14),
        ChunkyButton(
          key: const ValueKey('metric-sheet-save'),
          label: 'Simpan metrik',
          icon: Icons.check_rounded,
          onPressed: _save,
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('metric-sheet-delete'),
            label: 'Hapus metrik',
            variant: ChunkyButtonVariant.outline,
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(
              context,
            ).pop(const DraftResult<MetricDraft>.remove()),
          ),
        ],
      ],
    );
  }
}
