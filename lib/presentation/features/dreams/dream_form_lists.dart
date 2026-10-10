import 'package:flutter/material.dart';

import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_form_models.dart';
import 'dream_form_sheets.dart';

/// The steps part of the dream form: a checklist you can reorder; a tap opens
/// the step sheet.
class DreamStepsEditor extends StatelessWidget {
  const DreamStepsEditor({
    super.key,
    required this.steps,
    required this.metrics,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onReorder,
    this.errorText,
  });

  final List<StepDraft> steps;
  final List<MetricDraft> metrics;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onToggle;
  final void Function(int oldIndex, int newIndex) onReorder;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Langkah', error: errorText != null),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pecah mimpimu jadi langkah-langkah kecil. Boleh dikosongkan dulu.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
        ReorderableListView(
          key: const ValueKey('dream-steps'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: onReorder,
          children: [
            for (final (i, s) in steps.indexed)
              Padding(
                key: ValueKey('step-${s.id}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: ChunkyTile(
                  key: ValueKey('step-tile-$i'),
                  dense: true,
                  leading: Checkbox(
                    key: ValueKey('step-check-$i'),
                    value: s.done,
                    onChanged: (_) => onToggle(i),
                  ),
                  title: s.title,
                  subtitle: _subtitle(s),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: g.textMuted,
                      semanticLabel: 'Geser langkah',
                    ),
                  ),
                  onTap: () => onEdit(i),
                ),
              ),
          ],
        ),
        if (errorText != null) DreamFormError(errorText!),
        if (steps.length < stepsPerDreamMax)
          ChunkyButton(
            key: const ValueKey('add-step'),
            label: 'Tambah langkah',
            size: ChunkyButtonSize.small,
            expand: false,
            variant: ChunkyButtonVariant.outline,
            icon: Icons.add_rounded,
            onPressed: onAdd,
          )
        else
          Text(
            'Sudah $stepsPerDreamMax langkah, itu batasnya.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
      ],
    );
  }

  String? _subtitle(StepDraft s) {
    final parts = [
      if (s.dueDate != null) 'sampai ${formatTarget(s.dueDate)}',
      if (s.cost != null) 'Rp ${_amount(s.cost!)}',
      if (s.metricRef != null)
        'metrik ${metrics.where((m) => m.id == s.metricRef).map((m) => m.label).firstOrNull ?? '?'}'
            '${s.atValue == null ? '' : ' di ${_amount(s.atValue!)}'}',
      if (s.done && (s.reward ?? '').isNotEmpty) '🎁 ${s.reward}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

String _amount(double v) => v == v.roundToDouble()
    ? v.toInt().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      )
    : '$v';

/// The metrics part of the dream form.
class DreamMetricsEditor extends StatelessWidget {
  const DreamMetricsEditor({
    super.key,
    required this.metrics,
    required this.onAdd,
    required this.onEdit,
    this.errorText,
  });

  final List<MetricDraft> metrics;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Metrik', error: errorText != null),
        if (metrics.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Ukur kemajuan dengan angka: berat badan, saldo dompet, hari '
              'bersih dari kebiasaan, atau catatan manual.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
        for (final (i, m) in metrics.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: ValueKey('metric-tile-$i'),
              dense: true,
              leading: Icon(Icons.show_chart_rounded, color: g.textMuted),
              title: m.label,
              subtitle:
                  '${m.source.label} · target ${_amount(m.targetValue)}'
                  '${(m.unit ?? '').isEmpty ? '' : ' ${m.unit}'}',
              trailing: Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
              onTap: () => onEdit(i),
            ),
          ),
        if (errorText != null) DreamFormError(errorText!),
        if (metrics.length < metricsPerDreamMax)
          ChunkyButton(
            key: const ValueKey('add-metric'),
            label: 'Tambah metrik',
            size: ChunkyButtonSize.small,
            expand: false,
            variant: ChunkyButtonVariant.outline,
            icon: Icons.add_chart_rounded,
            onPressed: onAdd,
          )
        else
          Text(
            'Sudah $metricsPerDreamMax metrik, itu batasnya.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
      ],
    );
  }
}
