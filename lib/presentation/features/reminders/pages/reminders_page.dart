import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../reminder_actions.dart';

/// "Pengingat": synced reminders grouped Terlambat / Mendatang / Selesai.
/// Each fires a local notification at its due time.
class RemindersPage extends ConsumerStatefulWidget {
  const RemindersPage({super.key});

  @override
  ConsumerState<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends ConsumerState<RemindersPage> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(watchReminderGroupsProvider);
    final total = switch (async) {
      AsyncData(:final value) =>
        value.overdue.length + value.upcoming.length + value.done.length,
      _ => 0,
    };
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Pengingat'),
        actions: [
          IconButton(
            tooltip: 'Pengingat baru',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/reminders/new'),
          ),
        ],
      ),
      bottomNavigationBar: total > 0 ? const _AddBar() : null,
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: switch (async) {
          AsyncData() when total == 0 => ScrollableFill(
            child: EmptyState(
              title: 'Belum ada pengingat',
              message:
                  'Minum obat, bayar tagihan, telepon ibu… Ghina bakal '
                  'ngingetin tepat waktu 🔔',
              mood: MascotMood.waving,
              actionLabel: 'Buat pengingat',
              onAction: () => context.push('/reminders/new'),
            ),
          ),
          AsyncData(:final value) => _list(value),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchReminderGroupsProvider),
            ),
          ),
          _ => const LoadingListView(hero: false, tiles: 5),
        },
      ),
    );
  }

  Widget _list(ReminderGroups groups) {
    final now = ref.watch(clockProvider).now();
    final g = context.ghina;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        _SummaryCard(groups: groups, now: now),
        if (groups.overdue.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Terlambat',
            trailing: ChunkyPill(
              label: '${groups.overdue.length}',
              color: GhinaColors.red,
            ),
          ),
          for (final (i, r) in groups.overdue.indexed)
            _entry(r, now, i, ReminderStatus.overdue),
        ],
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Mendatang',
          subtitle: groups.upcoming.isEmpty ? 'Semua beres 🎉' : null,
        ),
        for (final (i, r) in groups.upcoming.indexed)
          _entry(r, now, i, ReminderStatus.upcoming),
        if (groups.done.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Selesai',
            subtitle: '${groups.done.length} pengingat',
            actionLabel: _showDone ? 'Sembunyikan' : 'Tampilkan',
            onAction: () => setState(() => _showDone = !_showDone),
          ),
          if (_showDone)
            for (final (i, r) in groups.done.take(50).indexed)
              _entry(r, now, i, ReminderStatus.done)
          else
            Text(
              'Pengingat yang sudah selesai disimpan di sini.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
        ],
      ],
    );
  }

  Widget _entry(ReminderItem r, DateTime now, int i, ReminderStatus status) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PopIn(
          delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
          child: Dismissible(
            key: ValueKey('reminder-${r.id}'),
            direction: DismissDirection.endToStart,
            background: const _DeleteBackground(),
            onDismissed: (_) => deleteReminderWithUndo(context, ref, r),
            child: ReminderTile(
              reminder: r,
              now: now,
              status: status,
              onToggle: () async {
                if (r.done) {
                  await ref.read(reopenReminderProvider)(r.id);
                } else {
                  HapticFeedback.mediumImpact();
                  await completeReminderWithUndo(context, ref, r);
                }
              },
              onTap: () => context.push('/reminders/${r.id}'),
            ),
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.groups, required this.now});

  final ReminderGroups groups;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final overdue = groups.overdue.length;
    final next = groups.upcoming.firstOrNull;
    final (mood, title, message) = overdue > 0
        ? (
            MascotMood.thinking,
            '$overdue pengingat kelewat',
            'Selesaikan atau geser waktunya, yuk.',
          )
        : next == null
        ? (
            MascotMood.happy,
            'Nggak ada yang ditunggu',
            'Tambah pengingat baru kapan aja.',
          )
        : (
            MascotMood.happy,
            'Berikutnya: ${next.title}',
            reminderDueLabel(next.dueAt, now),
          );
    return ChunkyCard(
      tinted: overdue > 0 ? GhinaColors.red : GhinaColors.blue,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          MascotView(mood: mood, size: 64, animate: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One reminder: check circle, title, due + recurrence, notes preview.
class ReminderTile extends StatelessWidget {
  const ReminderTile({
    super.key,
    required this.reminder,
    required this.now,
    required this.status,
    required this.onToggle,
    this.onTap,
  });

  final ReminderItem reminder;
  final DateTime now;
  final ReminderStatus status;
  final Future<void> Function() onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = reminder;
    final overdue = status == ReminderStatus.overdue;
    final done = status == ReminderStatus.done;
    final accent = overdue ? GhinaColors.red : GhinaColors.blue;
    final dueColor = overdue
        ? GhinaColors.red.base
        : done
        ? g.textMuted
        : g.textSecondary;
    return ChunkySurface(
      color: g.surface,
      edgeColor: overdue
          ? GhinaColors.red.base.withValues(alpha: 0.55)
          : g.borderEdge,
      borderColor: overdue
          ? GhinaColors.red.base.withValues(alpha: 0.55)
          : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      semanticLabel: r.title,
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: done ? 'Tandai belum selesai' : 'Tandai selesai',
            child: InkResponse(
              key: ValueKey('reminder-check-${r.id}'),
              onTap: onToggle,
              radius: 26,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedContainer(
                  duration: GhinaMotion.fast,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? GhinaColors.green.base : Colors.transparent,
                    border: Border.all(
                      color: done ? GhinaColors.green.edge : accent.base,
                      width: 2.5,
                    ),
                  ),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(
                    color: done ? g.textMuted : g.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: g.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Meta(
                      icon: done
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                      label: done && r.doneAt != null
                          ? 'Selesai ${reminderDueLabel(r.doneAt!, now)}'
                          : reminderDueLabel(r.dueAt, now),
                      color: dueColor,
                    ),
                    if (r.recurrence != null)
                      _Meta(
                        icon: Icons.repeat_rounded,
                        label: r.recurrence!.label,
                        color: g.textSecondary,
                      ),
                    if (overdue)
                      const ChunkyPill(
                        label: 'Terlambat',
                        color: GhinaColors.red,
                        soft: true,
                      ),
                  ],
                ),
                if (r.notes != null && r.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    r.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: GhinaType.bodyS.w(700).copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: GhinaColors.red.base,
      borderRadius: GhinaRadii.rLg,
    ),
    child: const Icon(Icons.delete_rounded, color: Colors.white),
  );
}

class _AddBar extends StatelessWidget {
  const _AddBar();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      decoration: BoxDecoration(
        color: g.background,
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(
        GhinaSpace.page,
        12,
        GhinaSpace.page,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: ChunkyButton(
        label: 'Pengingat baru',
        icon: Icons.add_alarm_rounded,
        onPressed: () => context.push('/reminders/new'),
      ),
    );
  }
}
