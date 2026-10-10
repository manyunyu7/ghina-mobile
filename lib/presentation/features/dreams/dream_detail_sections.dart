import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dates.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_cards.dart';
import 'dream_format.dart';

/// A titled block of the detail screen.
class DreamSection extends StatelessWidget {
  const DreamSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          padding: const EdgeInsets.only(top: 4, bottom: 8),
        ),
        child,
      ],
    ),
  );
}

/// Why / condition / summary as text cards.
class DreamTextCard extends StatelessWidget {
  const DreamTextCard({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return DreamSection(
      title: title,
      child: ChunkyCard(
        padding: const EdgeInsets.all(14),
        child: Text(text, style: GhinaType.body.copyWith(color: g.textPrimary)),
      ),
    );
  }
}

/// The checklist: a checkbox per step. Editing happens on the form screen.
class DreamStepsSection extends ConsumerWidget {
  const DreamStepsSection({super.key, required this.steps});

  final List<DreamStep> steps;

  Future<void> _toggle(BuildContext context, WidgetRef ref, String id) async {
    final r = await ref.read(toggleDreamStepProvider)(id);
    if (!context.mounted) return;
    if (r case Err(:final failure)) showFailureToast(context, failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    final today = dateKey(ref.watch(clockProvider).now());
    final done = steps.where((s) => s.done).length;
    return DreamSection(
      title: 'Langkah ($done/${steps.length})',
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        child: Column(
          children: [
            for (final s in steps)
              _StepRow(
                key: ValueKey('step-${s.id}'),
                step: s,
                today: today,
                onToggle: () => _toggle(context, ref, s.id),
                color: g,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.today,
    required this.onToggle,
    required this.color,
  });

  final DreamStep step;
  final String today;
  final VoidCallback onToggle;
  final GhinaTokens color;

  @override
  Widget build(BuildContext context) {
    final g = color;
    final s = step;
    final meta = <String>[
      if (!s.done && s.dueDate != null)
        '${formatTarget(s.dueDate)} · '
            '${dreamDueText(daysUntilTarget(s.dueDate, today))}',
      if (s.done && s.dueDate != null) formatTarget(s.dueDate),
      if (s.cost != null) context.money(s.cost!),
      if (s.metricRef != null && s.atValue != null)
        'saat metrik ${s.metricRef} ≥ ${dreamNumberText(s.atValue!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('step-check-${s.id}'),
            value: s.done,
            onChanged: (_) => onToggle(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: GhinaType.body
                        .w(700)
                        .copyWith(
                          color: s.done ? g.textMuted : g.textPrimary,
                          decoration: s.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta.join(' · '),
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                    ),
                  if (s.done && s.reward != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ChunkyPill(
                        key: ValueKey('step-reward-${s.id}'),
                        label: '🎁 ${s.reward}',
                        color: GhinaColors.yellow,
                        soft: true,
                        uppercase: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estimate, steps' sum, done / remaining, difference, effective value.
class DreamCostPanel extends StatelessWidget {
  const DreamCostPanel({super.key, required this.cost, required this.hasSteps});

  final DreamCost cost;
  final bool hasSteps;

  @override
  Widget build(BuildContext context) {
    if (cost.estimate == null && cost.stepsWithCost == 0) {
      return const SizedBox.shrink();
    }
    String m(double? v) => v == null ? '—' : context.money(v);
    final withSteps = cost.stepsWithCost > 0;
    return DreamSection(
      title: 'Biaya',
      child: ChunkyCard(
        key: const ValueKey('dream-cost'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          children: [
            _KeyValue('Perkiraan', m(cost.estimate)),
            _KeyValue('Total langkah', withSteps ? m(cost.stepsTotal) : '—'),
            _KeyValue('Sudah dibayar', withSteps ? m(cost.stepsDone) : '—'),
            _KeyValue('Sisa', withSteps ? m(cost.stepsRemaining) : '—'),
            _KeyValue('Selisih', m(cost.diff)),
            _KeyValue('Dipakai', m(cost.effective), bold: true),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
          Text(
            value,
            style: (bold ? GhinaType.body.w(800) : GhinaType.body.w(700))
                .copyWith(color: g.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The linked note: its title and a button to open it.
class DreamNoteSection extends ConsumerWidget {
  const DreamNoteSection({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(watchNoteProvider(noteId));
    final view = async.value;
    final loading = async.isLoading && view == null;
    final title = loading
        ? '…'
        : (view == null ? 'Catatan tidak ditemukan' : view.note.displayTitle);
    return DreamSection(
      title: 'Catatan',
      child: ChunkyCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '📝 $title',
              key: const ValueKey('dream-note-title'),
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            if (view != null) ...[
              const SizedBox(height: 10),
              ChunkyButton(
                key: const ValueKey('dream-note-open'),
                label: 'Buka catatan',
                icon: Icons.open_in_new_rounded,
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.secondary,
                onPressed: () => context.push('/notes/$noteId'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Custom-column values that apply to this dream's category.
class DreamFieldsSection extends StatelessWidget {
  const DreamFieldsSection({
    super.key,
    required this.dream,
    required this.defs,
  });

  final Dream dream;
  final List<DreamFieldDef> defs;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final d in defs)
        if (d.appliesToCategory(dream.category) &&
            dream.fields.containsKey(d.key))
          d,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return DreamSection(
      title: 'Kolom khusus',
      child: ChunkyCard(
        key: const ValueKey('dream-fields'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          children: [
            for (final d in shown)
              _KeyValue(d.label, formatDreamFieldValue(d, dream.fields[d.key])),
          ],
        ),
      ),
    );
  }
}

/// Parent and sub-dreams, each a tile to its own detail.
class DreamRelationsSection extends StatelessWidget {
  const DreamRelationsSection({
    super.key,
    required this.dream,
    required this.all,
  });

  final Dream dream;
  final List<Dream> all;

  Widget _tile(BuildContext context, Dream d, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ChunkyTile(
      key: ValueKey(key),
      dense: true,
      leading: dreamEmojiText(d.emoji, size: 20),
      title: d.title,
      subtitle: d.status.label,
      showChevron: true,
      onTap: () => context.push('/dreams/${d.id}'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Dream? parent;
    for (final d in all) {
      if (d.id == dream.parentId) parent = d;
    }
    final children = [
      for (final d in all)
        if (d.parentId == dream.id) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parent != null)
          DreamSection(
            title: 'Bagian dari',
            child: _tile(context, parent, 'dream-parent'),
          ),
        if (children.isNotEmpty)
          DreamSection(
            title: 'Mimpi turunan',
            child: Column(
              children: [
                for (final c in children)
                  _tile(context, c, 'dream-child-${c.id}'),
              ],
            ),
          ),
      ],
    );
  }
}

/// Created / changed / started / done as small captions.
class DreamTimestamps extends StatelessWidget {
  const DreamTimestamps({super.key, required this.dream});

  final Dream dream;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final lines = <String>[
      'Dibuat ${formatTarget(dateKey(dream.createdAt))}',
      'Diubah ${formatTarget(dateKey(dream.updatedAt))}',
      if (dream.startedAt != null) 'Mulai ${formatTarget(dream.startedAt)}',
      if (dream.completedAt != null)
        'Selesai ${formatTarget(dream.completedAt)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        key: const ValueKey('dream-timestamps'),
        spacing: 14,
        runSpacing: 4,
        children: [
          for (final l in lines)
            Text(l, style: GhinaType.caption.copyWith(color: g.textMuted)),
        ],
      ),
    );
  }
}
