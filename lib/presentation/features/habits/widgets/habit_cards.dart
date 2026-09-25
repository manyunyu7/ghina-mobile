import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../controllers/habit_actions.dart';
import '../controllers/habit_timer.dart';
import '../habit_format.dart';
import 'relapse_sheet.dart';

/// Emoji in the habit's color (a lock when [masked] and private).
class HabitAvatar extends StatelessWidget {
  const HabitAvatar({
    super.key,
    required this.habit,
    this.size = 48,
    this.masked = false,
  });

  final Habit habit;
  final double size;

  /// Outside the Habits screen: private habits show a neutral lock.
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (masked && habit.isPrivate) {
      return CategoryAvatar(
        icon: Icons.lock_rounded,
        color: GhinaColors.gray.base,
        size: size,
        soft: true,
      );
    }
    final sw = habitSwatch(habit);
    final emoji = habit.emoji;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sw.tint(g.brightness),
        shape: BoxShape.circle,
        border: Border.all(color: sw.base.withValues(alpha: 0.55), width: 2),
      ),
      child: emoji == null
          ? Icon(
              habit.isQuit ? Icons.do_not_disturb_rounded : Icons.eco_rounded,
              color: sw.base,
              size: size * 0.5,
            )
          : Text(
              emoji,
              style: TextStyle(fontSize: size * 0.46, height: 1.1),
              textScaler: TextScaler.noScaling,
            ),
    );
  }
}

/// Small "🔥 5 hari" pill.
class HabitStreakPill extends StatelessWidget {
  const HabitStreakPill({super.key, required this.streak});

  final HabitStreak streak;

  @override
  Widget build(BuildContext context) {
    final quit = streak.kind == HabitKind.quit;
    final active = streak.current > 0;
    return ChunkyPill(
      label: '${streak.current} ${streak.unit.label}',
      color: active
          ? (quit ? GhinaColors.green : GhinaColors.orange)
          : GhinaColors.gray,
      soft: true,
      uppercase: false,
      icon: quit ? Icons.park_rounded : Icons.local_fire_department_rounded,
    );
  }
}

// ---------------------------------------------------------------- build card

/// A habit to build: one-tap check / −/+ counter / stopwatch, progress ring,
/// streak and "Libur hari ini".
class BuildHabitCard extends ConsumerWidget {
  const BuildHabitCard({
    super.key,
    required this.today,
    this.linkToDetail = true,
  });

  final HabitToday today;

  /// Tapping the card opens the detail page (off on the detail page itself).
  final bool linkToDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final t = today;
    final h = t.habit;
    final sw = habitSwatch(h);
    final target = h.target;
    final week = t.week;
    final meta = [
      scheduleLabel(h.schedule),
      if (!target.isCheck) progressLabel(target, t.progress),
      if (week != null) '${week.met}/${week.need} minggu ini',
    ].join(' · ');

    return ChunkyCard(
      key: ValueKey('habit-card-${h.id}'),
      onTap: linkToDetail ? () => context.push('/habits/${h.id}') : null,
      semanticLabel: h.title,
      tinted: t.met ? sw : null,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          // The −/ring/+ counter needs ~170 px: on narrow cards it gets its
          // own row under the title.
          final stacked =
              target.isCount &&
              c.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 300;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  HabitAvatar(habit: h),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.h3.copyWith(color: g.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.bodyS.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            HabitStreakPill(streak: t.streak),
                            if (t.skipped)
                              const ChunkyPill(
                                label: 'Libur 🌴',
                                color: GhinaColors.blue,
                                soft: true,
                                uppercase: false,
                              )
                            else if (!t.scheduled && !t.met)
                              const ChunkyPill(
                                label: 'Bukan jadwal',
                                color: GhinaColors.gray,
                                soft: true,
                                uppercase: false,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: 10),
                    _BuildControl(today: t),
                  ],
                ],
              ),
              if (stacked) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _BuildControl(today: t),
                ),
              ],
              if (target.isDuration && !t.skipped) ...[
                const SizedBox(height: 10),
                _QuickMinutes(today: t),
              ],
              const SizedBox(height: 4),
              _SkipRow(today: t),
            ],
          );
        },
      ),
    );
  }
}

class _BuildControl extends ConsumerWidget {
  const _BuildControl({required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = today;
    final sw = habitSwatch(t.habit);
    final actions = HabitActions(context, ref);
    final id = t.id;
    switch (t.habit.target.type) {
      case HabitTargetType.check:
        return HabitCheckButton(
          key: ValueKey('habit-check-$id'),
          done: t.met,
          color: sw,
          onTap: () => actions.toggleCheck(t),
        );
      case HabitTargetType.count:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundIcon(
              key: ValueKey('habit-dec-$id'),
              icon: Icons.remove_rounded,
              tooltip: 'Kurangi 1',
              onTap: (t.progress ?? 0) > 0
                  ? () => actions.addProgress(t, -1)
                  : null,
            ),
            const SizedBox(width: 6),
            ProgressRing(
              value: t.fraction,
              size: 54,
              stroke: 6,
              color: sw,
              child: Text(
                fmtHabitNum(t.progress ?? 0),
                style: GhinaType.h3
                    .w(900)
                    .copyWith(color: context.ghina.textPrimary),
                textScaler: TextScaler.noScaling,
              ),
            ),
            const SizedBox(width: 6),
            _RoundIcon(
              key: ValueKey('habit-inc-$id'),
              icon: Icons.add_rounded,
              tooltip: 'Tambah 1',
              color: sw,
              onTap: () => actions.addProgress(t, 1),
            ),
          ],
        );
      case HabitTargetType.duration:
        return HabitTimerButton(today: t);
    }
  }
}

/// The round one-tap check of a `check` habit.
class HabitCheckButton extends StatelessWidget {
  const HabitCheckButton({
    super.key,
    required this.done,
    required this.color,
    required this.onTap,
    this.size = 54,
  });

  final bool done;
  final ChunkySwatch color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Batalkan centang' : 'Centang',
      child: ChunkySurface(
        color: done ? color.base : g.surface,
        edgeColor: done ? color.edge : g.borderEdge,
        borderColor: done ? null : g.border,
        depth: GhinaDepth.md,
        borderRadius: BorderRadius.circular(size),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedSwitcher(
            duration: GhinaMotion.fast,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              Icons.check_rounded,
              key: ValueKey(done),
              size: size * 0.6,
              color: done ? color.on : g.border,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final ChunkySwatch? color;

  @override
  Widget build(BuildContext context) => ChunkyIconButton(
    icon: icon,
    onPressed: onTap,
    color: color,
    size: 36,
    tooltip: tooltip,
  );
}

/// Duration: ring with minutes + start/stop stopwatch.
class HabitTimerButton extends ConsumerWidget {
  const HabitTimerButton({super.key, required this.today, this.size = 58});

  final HabitToday today;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = today;
    final g = context.ghina;
    final sw = habitSwatch(t.habit);
    final started = ref.watch(habitTimersProvider)[t.id];
    final running = started != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: running ? 'Stop timer' : 'Mulai timer',
          child: GestureDetector(
            key: ValueKey('habit-timer-${t.id}'),
            onTap: () => HabitActions(context, ref).toggleTimer(t),
            child: ProgressRing(
              value: t.fraction,
              size: size,
              stroke: 6,
              color: sw,
              child: Container(
                width: size - 22,
                height: size - 22,
                decoration: BoxDecoration(
                  color: running ? GhinaColors.red.base : sw.base,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: size * 0.42,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        if (running)
          ElapsedTicker(
            startedAt: started,
            builder: (_, d) => Text(
              formatElapsed(d),
              style: GhinaType.caption
                  .w(900)
                  .copyWith(
                    color: GhinaColors.red.base,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          )
        else
          Text(
            '${fmtHabitNum(t.progress ?? 0)}/${fmtHabitNum(t.goal ?? 0)} mnt',
            style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
          ),
      ],
    );
  }
}

class _QuickMinutes extends ConsumerWidget {
  const _QuickMinutes({required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sw = habitSwatch(today.habit);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final m in const [5, 15, 30])
          ChunkyChip(
            key: ValueKey('habit-add-$m-${today.id}'),
            label: '+$m mnt',
            selected: false,
            color: sw,
            onTap: () =>
                HabitActions(context, ref).addProgress(today, m.toDouble()),
          ),
      ],
    );
  }
}

class _SkipRow extends ConsumerWidget {
  const _SkipRow({required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = today;
    final g = context.ghina;
    if (t.met && !t.skipped) return const SizedBox(height: 4);
    if (!t.scheduled && !t.skipped) return const SizedBox(height: 4);
    return Row(
      children: [
        Expanded(
          child: Text(
            t.skipped
                ? 'Istirahat itu juga bagian dari konsisten.'
                : skipsLeftLabel(t),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ),
        TextButton.icon(
          key: ValueKey('habit-skip-${t.id}'),
          onPressed: () => HabitActions(context, ref).toggleSkip(t),
          icon: Icon(
            t.skipped ? Icons.undo_rounded : Icons.beach_access_rounded,
            size: 18,
            color: t.canSkip || t.skipped ? null : g.textMuted,
          ),
          label: Text(
            t.skipped ? 'Batal libur' : 'Libur hari ini',
            style: GhinaType.bodyS
                .w(800)
                .copyWith(
                  color: t.canSkip || t.skipped
                      ? GhinaColors.blue.base
                      : g.textMuted,
                ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- quit card

/// A habit to quit: "Hari bersih ke-N", ring to the next milestone, the clean
/// check-in, the emergency button and "Aku kalah".
class QuitHabitCard extends ConsumerWidget {
  const QuitHabitCard({super.key, required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final t = today;
    final h = t.habit;
    final s = t.streak;
    final next = nextMilestoneOf(s);
    return ChunkyCard(
      key: ValueKey('habit-card-${h.id}'),
      onTap: () => context.push('/habits/${h.id}'),
      semanticLabel: h.title,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HabitAvatar(habit: h),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.relapsedToday
                          ? 'Hari bersih barumu mulai besok 🌱'
                          : streakHeadline(s),
                      key: ValueKey('habit-clean-${h.id}'),
                      style: GhinaType.h2
                          .w(900)
                          .copyWith(
                            color: t.relapsedToday
                                ? g.textSecondary
                                : GhinaColors.green.base,
                            fontSize: t.relapsedToday ? 15 : 20,
                          ),
                    ),
                    Text(
                      t.relapsedToday
                          ? 'Terlama: ${s.longest} hari'
                          : '${s.current > 0 ? 'hari ini masih berjalan · ' : ''}${nextMilestoneLine(s)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ProgressRing(
                value: milestoneFraction(s),
                size: 62,
                stroke: 7,
                color: GhinaColors.green,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.park_rounded,
                      size: 20,
                      color: s.current > 0
                          ? GhinaColors.green.base
                          : g.textMuted,
                    ),
                    if (next != null)
                      Text(
                        '$next',
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: g.textSecondary),
                        textScaler: TextScaler.noScaling,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          QuitActions(today: t),
        ],
      ),
    );
  }
}

/// The three quit buttons (card and detail page).
class QuitActions extends ConsumerWidget {
  const QuitActions({super.key, required this.today});

  final HabitToday today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = today;
    final id = t.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!t.relapsedToday)
          ChunkyButton(
            key: ValueKey('habit-clean-check-$id'),
            label: t.cleanCheckIn ? 'Hari ini bersih ✅' : 'Hari ini bersih',
            icon: t.cleanCheckIn ? null : Icons.check_circle_outline_rounded,
            size: ChunkyButtonSize.medium,
            variant: t.cleanCheckIn
                ? ChunkyButtonVariant.primary
                : ChunkyButtonVariant.outline,
            color: t.cleanCheckIn ? GhinaColors.green : null,
            expand: true,
            uppercase: false,
            onPressed: () => HabitActions(context, ref).toggleClean(t),
          ),
        if (!t.relapsedToday) const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final narrow =
                c.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 280;
            final urge = ChunkyButton(
              key: ValueKey('habit-urge-$id'),
              label: 'Lagi pengen…',
              icon: Icons.air_rounded,
              size: ChunkyButtonSize.medium,
              variant: ChunkyButtonVariant.secondary,
              expand: true,
              uppercase: false,
              onPressed: () => context.push('/habits/$id/urge'),
            );
            final lost = ChunkyButton(
              key: ValueKey('habit-relapse-$id'),
              label: 'Aku kalah',
              size: ChunkyButtonSize.medium,
              variant: ChunkyButtonVariant.outline,
              expand: true,
              uppercase: false,
              onPressed: () => showRelapseSheet(context, today: t),
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [urge, const SizedBox(height: 10), lost],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: urge),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: lost),
              ],
            );
          },
        ),
      ],
    );
  }
}
