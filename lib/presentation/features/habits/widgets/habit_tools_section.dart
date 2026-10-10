import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

IconData toolKindIcon(HabitToolKind k) => switch (k) {
  HabitToolKind.distraction => Icons.sports_esports_rounded,
  HabitToolKind.physical => Icons.directions_run_rounded,
  HabitToolKind.mindset => Icons.self_improvement_rounded,
  HabitToolKind.social => Icons.groups_rounded,
  HabitToolKind.reward => Icons.card_giftcard_rounded,
  HabitToolKind.other => Icons.bolt_rounded,
};

/// "Alat bantu saat pengen" on the habit screen: the coping playbook grouped by
/// kind, plus the entry to edit it. The tools show on the emergency screen.
class HabitToolsSection extends StatelessWidget {
  const HabitToolsSection({
    super.key,
    required this.habit,
    required this.onEdit,
  });

  final Habit habit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tools = habit.tools;
    return Column(
      key: const ValueKey('habit-tools-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Alat bantu saat pengen',
          subtitle: 'Muncul di layar "Lagi pengen…"',
          actionLabel: tools.isEmpty ? 'Tambah' : 'Atur',
          onAction: onEdit,
        ),
        if (tools.isEmpty)
          Text(
            'Belum ada. Tulis hal-hal yang biasanya menolong: minum air, '
            'jalan sebentar, telepon teman.',
            style: GhinaType.body.copyWith(color: g.textSecondary),
          )
        else
          for (final group in groupToolsByKind(tools)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                group.kind.label,
                style: GhinaType.caption
                    .w(800)
                    .copyWith(color: g.textSecondary),
              ),
            ),
            for (final t in group.tools)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChunkyTile(
                  dense: true,
                  leading: Icon(toolKindIcon(t.kind), color: g.textSecondary),
                  title: t.title,
                  subtitle: t.detail.isEmpty ? null : t.detail,
                ),
              ),
          ],
      ],
    );
  }
}

/// Edit the coping tools: add, edit, delete, reorder. Every change is saved at
/// once (offline-first, syncs later).
class HabitToolsEditorPage extends ConsumerWidget {
  const HabitToolsEditorPage({super.key, required this.habitId});

  final String habitId;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    List<HabitTool> tools,
  ) async {
    final r = await ref.read(setHabitToolsProvider)(habitId, tools);
    if (!context.mounted) return;
    if (r case Err(:final failure)) showFailureToast(context, failure);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<HabitTool> tools,
    int? index,
  ) async {
    final r = await showChunkyBottomSheet<({HabitTool? tool, bool delete})>(
      context,
      title: index == null ? 'Alat bantu baru' : 'Ubah alat bantu',
      showClose: true,
      builder: (_) => _ToolSheet(tool: index == null ? null : tools[index]),
    );
    if (r == null || !context.mounted) return;
    final next = [...tools];
    if (r.delete && index != null) {
      next.removeAt(index);
    } else if (r.tool != null) {
      if (index == null) {
        next.add(r.tool!);
      } else {
        next[index] = r.tool!;
      }
    }
    await _save(context, ref, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final habit = ref.watch(watchHabitTodayProvider(habitId)).value?.habit;
    final tools = habit?.tools ?? const <HabitTool>[];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Alat bantu'),
        actions: [
          if (habit != null)
            IconButton(
              key: const ValueKey('tool-add'),
              tooltip: 'Alat bantu baru',
              icon: const Icon(Icons.add_circle_rounded),
              onPressed: tools.length >= habitToolsMax
                  ? null
                  : () => _edit(context, ref, tools, null),
            ),
        ],
      ),
      body: habit == null
          ? const SkeletonList(count: 3)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                8,
                GhinaSpace.page,
                32,
              ),
              children: [
                Text(
                  'Tahan dan geser untuk mengurutkan. Maksimal $habitToolsMax alat.',
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 12),
                if (tools.isEmpty)
                  Text(
                    'Belum ada alat bantu. Ketuk + untuk menambah.',
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  )
                else
                  ReorderableListView.builder(
                    key: const ValueKey('tool-list'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tools.length,
                    onReorderItem: (from, to) {
                      final next = [...tools];
                      next.insert(to, next.removeAt(from));
                      _save(context, ref, next);
                    },
                    itemBuilder: (_, i) {
                      final t = tools[i];
                      return Padding(
                        key: ValueKey('tool-$i-${t.title}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChunkyTile(
                          dense: true,
                          leading: Icon(
                            toolKindIcon(t.kind),
                            color: g.textSecondary,
                          ),
                          title: t.title,
                          subtitle: t.detail.isEmpty
                              ? t.kind.label
                              : '${t.kind.label} · ${t.detail}',
                          trailing: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: g.textMuted,
                          ),
                          onTap: () => _edit(context, ref, tools, i),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

/// Add / edit one tool: title, detail, kind (and delete when editing). The
/// sheet owns its controllers (it is still built while it animates away).
class _ToolSheet extends StatefulWidget {
  const _ToolSheet({required this.tool});

  final HabitTool? tool;

  @override
  State<_ToolSheet> createState() => _ToolSheetState();
}

class _ToolSheetState extends State<_ToolSheet> {
  late final _title = TextEditingController(text: widget.tool?.title);
  late final _detail = TextEditingController(text: widget.tool?.detail);
  late HabitToolKind _kind = widget.tool?.kind ?? HabitToolKind.other;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final tool = validateHabitTools([
        HabitTool(title: _title.text, detail: _detail.text, kind: _kind),
      ]).single;
      Navigator.of(context).pop((tool: tool, delete: false));
    } on Failure catch (e) {
      setState(() => _error = e.message);
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
              key: const ValueKey('tool-title'),
              label: 'Apa yang dilakukan?',
              hint: 'mis. Minum air',
              controller: _title,
              maxLength: habitToolTitleMax,
              autofocus: true,
              errorText: _error,
            ),
            const SizedBox(height: 12),
            ChunkyTextField(
              key: const ValueKey('tool-detail'),
              label: 'Detail (opsional)',
              hint: 'mis. Segelas penuh, pelan-pelan',
              controller: _detail,
              maxLength: habitToolDetailMax,
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            const FieldLabel('Jenis'),
            ChunkyChoiceChips<HabitToolKind>(
              options: [
                for (final k in HabitToolKind.values)
                  ChunkyChoice(value: k, label: k.label),
              ],
              selected: {_kind},
              onChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            ChunkyButton(
              key: const ValueKey('tool-save'),
              label: 'Simpan',
              icon: Icons.check_rounded,
              onPressed: _submit,
            ),
            if (widget.tool != null) ...[
              const SizedBox(height: 8),
              ChunkyButton(
                key: const ValueKey('tool-delete'),
                label: 'Hapus alat ini',
                icon: Icons.delete_outline_rounded,
                variant: ChunkyButtonVariant.ghost,
                color: GhinaColors.red,
                onPressed: () =>
                    Navigator.of(context).pop((tool: null, delete: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
