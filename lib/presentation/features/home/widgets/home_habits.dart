import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../habits/controllers/habit_actions.dart';
import '../../habits/controllers/habit_timer.dart';
import '../../habits/habit_format.dart';

/// Beranda → "Kebiasaan hari ini": one-tap check / +1 / timer for build
/// habits, the clean-days counter for quit habits. Private habits show
/// `publicTitle` ("Kebiasaan pribadi") and no emoji. Hidden without habits.
class HomeHabitsCard extends ConsumerWidget {
  const HomeHabitsCard({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  /// Rows shown before "Lihat semua".
  static const maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(watchHabitBoardProvider).value;
    if (board == null || board.isEmpty) return const SizedBox.shrink();
    // Due build habits first, then quit habits, then the rest.
    final items = [
      ...board.build.where((t) => t.isDue),
      ...board.quit,
      ...board.build.where((t) => !t.isDue),
    ];
    final shown = items.take(maxRows).toList();
    final g = context.ghina;
    final due = board.dueCount;
    return Padding(
      padding: padding,
      child: Column(
        key: const ValueKey('home-habits'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Kebiasaan hari ini',
            subtitle: due > 0 ? '${board.metCount}/$due tercapai' : null,
            actionLabel: 'Lihat semua',
            onAction: () => context.push('/habits'),
          ),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, t) in shown.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: g.border,
                    ),
                  _HabitRow(today: t),
                ],
                if (items.length > shown.length)
                  TextButton(
                    onPressed: () => context.push('/habits'),
                    child: Text('+${items.length - shown.length} lainnya'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final t = today;
    final h = t.habit;
    final masked = h.isPrivate;
    final sw = masked ? GhinaColors.gray : habitSwatch(h);
    final actions = HabitActions(context, ref, masked: true);
    final subtitle = h.isQuit
        ? (t.relapsedToday
              ? 'Mulai lagi besok 🌱'
              : 'Hari bersih ke-${t.streak.current}')
        : t.skipped
        ? 'Libur hari ini 🌴'
        : h.target.isCheck
        ? (t.met ? 'Selesai ✅' : '🔥 ${t.streak.label}')
        : masked && h.target.isCount
        // The unit ("batang", "gelas") can give a private habit away.
        ? '${fmtHabitNum(t.progress ?? 0)}/${fmtHabitNum(h.target.goal)}'
        : progressLabel(h.target, t.progress);

    return InkWell(
      key: ValueKey('home-habit-${h.id}'),
      onTap: () => context.push('/habits/${h.id}'),
      borderRadius: GhinaRadii.rLg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _Avatar(habit: h, masked: masked),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // The avatar already shows the emoji.
                    masked ? t.publicTitle : h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(h.isQuit ? 800 : 600)
                        .copyWith(
                          color: h.isQuit && !t.relapsedToday
                              ? GhinaColors.green.base
                              : g.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (h.isQuit)
              _QuitControl(today: t, actions: actions)
            else if (!t.skipped)
              _BuildControl(today: t, actions: actions, color: sw),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.habit, required this.masked});

  final Habit habit;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (masked) {
      return CategoryAvatar(
        icon: Icons.lock_rounded,
        color: GhinaColors.gray.base,
        size: 40,
        soft: true,
      );
    }
    final sw = habitSwatch(habit);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sw.tint(g.brightness),
        shape: BoxShape.circle,
      ),
      child: habit.emoji == null
          ? Icon(
              habit.isQuit ? Icons.park_rounded : Icons.eco_rounded,
              color: sw.base,
              size: 22,
            )
          : Text(
              habit.emoji!,
              style: const TextStyle(fontSize: 20),
              textScaler: TextScaler.noScaling,
            ),
    );
  }
}

class _BuildControl extends ConsumerWidget {
  const _BuildControl({
    required this.today,
    required this.actions,
    required this.color,
  });

  final HabitToday today;
  final HabitActions actions;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = today;
    final g = context.ghina;
    switch (t.habit.target.type) {
      case HabitTargetType.check:
        return _Round(
          key: ValueKey('home-habit-check-${t.id}'),
          label: t.met ? 'Batalkan centang' : 'Centang',
          filled: t.met,
          color: color,
          icon: Icons.check_rounded,
          onTap: () => actions.toggleCheck(t),
        );
      case HabitTargetType.count:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(
              value: t.fraction,
              size: 34,
              stroke: 4,
              color: color,
              child: const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            _Round(
              key: ValueKey('home-habit-inc-${t.id}'),
              label: 'Tambah 1',
              filled: t.met,
              color: color,
              icon: Icons.add_rounded,
              onTap: () => actions.addProgress(t, 1),
            ),
          ],
        );
      case HabitTargetType.duration:
        final started = ref.watch(habitTimersProvider)[t.id];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (started != null)
              ElapsedTicker(
                startedAt: started,
                builder: (_, d) => Text(
                  formatElapsed(d),
                  style: GhinaType.bodyS
                      .w(900)
                      .copyWith(color: GhinaColors.red.base),
                ),
              )
            else
              ProgressRing(
                value: t.fraction,
                size: 34,
                stroke: 4,
                color: color,
                child: const SizedBox.shrink(),
              ),
            const SizedBox(width: 8),
            _Round(
              key: ValueKey('home-habit-timer-${t.id}'),
              label: started != null ? 'Stop timer' : 'Mulai timer',
              filled: started != null || t.met,
              color: started != null ? GhinaColors.red : color,
              icon: started != null
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              onTap: () => actions.toggleTimer(t),
              borderColor: g.border,
            ),
          ],
        );
    }
  }
}

class _QuitControl extends StatelessWidget {
  const _QuitControl({required this.today, required this.actions});

  final HabitToday today;
  final HabitActions actions;

  @override
  Widget build(BuildContext context) {
    final t = today;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreakFlame(
          count: t.streak.current,
          active: t.streak.current > 0,
          size: 22,
          showCount: false,
          animate: false,
        ),
        const SizedBox(width: 6),
        if (!t.relapsedToday)
          _Round(
            key: ValueKey('home-habit-clean-${t.id}'),
            label: t.cleanCheckIn ? 'Batalkan bersih' : 'Hari ini bersih',
            filled: t.cleanCheckIn,
            color: GhinaColors.green,
            icon: Icons.check_rounded,
            onTap: () => actions.toggleClean(t),
          ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    super.key,
    required this.label,
    required this.filled,
    required this.color,
    required this.icon,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final bool filled;
  final ChunkySwatch color;
  final IconData icon;
  final VoidCallback onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      label: label,
      child: ChunkySurface(
        color: filled ? color.base : g.surface,
        edgeColor: filled ? color.edge : g.borderEdge,
        borderColor: filled ? null : (borderColor ?? g.border),
        depth: GhinaDepth.sm,
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 24, color: filled ? color.on : color.base),
        ),
      ),
    );
  }
}
