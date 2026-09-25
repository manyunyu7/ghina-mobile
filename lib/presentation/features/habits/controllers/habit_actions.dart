/// The writes behind the habit cards (list, detail and the home card), each
/// with its reward moment: XP toast + pending celebrations through the shared
/// [RewardTracker], then the habit's own streak-milestone celebration.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show XpRules;
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/game/game_providers.dart';
import '../habit_format.dart';
import 'habit_timer.dart';

/// Habit actions for one screen. Create per call: `HabitActions(context, ref)`.
class HabitActions {
  HabitActions(this.context, this.ref, {this.masked = false});

  final BuildContext context;
  final WidgetRef ref;

  /// Outside the Habits screen (home): celebrations hide private names.
  final bool masked;

  DateTime get _now => ref.read(clockProvider).now();

  Future<bool> _run<T>(
    Future<Result<T>> Function() write, {
    String Function(int xp)? xpToast,
    String? doneToast,
    HabitToday? celebrateFor,
  }) async {
    final rewards = await RewardTracker.startLoaded(ref);
    final r = await write();
    if (!context.mounted) {
      rewards.cancel();
      return r.isOk;
    }
    switch (r) {
      case Ok():
        await rewards.finish(
          context,
          xpToast: xpToast,
          doneToast: doneToast,
          goalHint: true,
        );
        if (celebrateFor != null && context.mounted) {
          await celebrateHabitMilestones(
            context,
            ref,
            only: celebrateFor.habit.id,
            masked: masked,
          );
        }
        return true;
      case Err(:final failure):
        rewards.cancel();
        showFailureToast(context, failure);
        return false;
    }
  }

  /// Build `check`: toggles today's check-in.
  Future<bool> toggleCheck(HabitToday t) {
    HapticFeedback.lightImpact();
    if (t.met) {
      return _run(() => ref.read(undoHabitCheckInProvider)(t.id, _now));
    }
    return _run(
      () => ref.read(checkInHabitProvider)(t.id, day: _now),
      xpToast: (xp) => 'Mantap! +$xp XP',
      doneToast: 'Tercentang ✅',
      celebrateFor: t,
    );
  }

  /// Build `count` / `duration`: adds [delta] (count or minutes; negative
  /// subtracts, never below 0).
  Future<bool> addProgress(HabitToday t, double delta) {
    HapticFeedback.selectionClick();
    final current = t.progress ?? 0;
    final next = current + delta;
    final wasMet = t.met;
    final goal = t.goal ?? 1;
    final willMeet = !wasMet && next >= goal;
    if (next <= 0) {
      return _run(
        () => ref.read(checkInHabitProvider)(
          t.id,
          day: _now,
          value: 0,
          add: false,
        ),
      );
    }
    return _run(
      () => ref.read(checkInHabitProvider)(
        t.id,
        day: _now,
        value: next,
        add: false,
      ),
      xpToast: (xp) => 'Target tercapai! +$xp XP',
      doneToast: willMeet ? 'Target tercapai 🎯' : null,
      celebrateFor: willMeet ? t : null,
    );
  }

  /// Duration: starts the stopwatch, or stops it and logs the minutes.
  Future<void> toggleTimer(HabitToday t) async {
    final timers = ref.read(habitTimersProvider.notifier);
    if (!timers.isRunning(t.id)) {
      HapticFeedback.mediumImpact();
      timers.start(t.id);
      return;
    }
    final elapsed = timers.stop(t.id) ?? Duration.zero;
    final minutes = timerMinutes(elapsed);
    if (minutes < 1) {
      showToastBadge(
        context,
        message: 'Belum semenit, jadi nggak dicatat. Lanjut lagi, yuk!',
        icon: Icons.timer_rounded,
        color: GhinaColors.blue,
      );
      return;
    }
    await addProgress(t, minutes.toDouble());
  }

  /// "Libur hari ini" / "Batal libur".
  Future<bool> toggleSkip(HabitToday t) async {
    if (t.skipped) {
      return _run(() => ref.read(unskipHabitDayProvider)(t.id, _now));
    }
    if (!t.canSkip) {
      showToastBadge(
        context,
        message: '$skipLimitMessage. Semangat, sedikit lagi! 💪',
        icon: Icons.beach_access_rounded,
        color: GhinaColors.orange,
        duration: const Duration(milliseconds: 3000),
      );
      return false;
    }
    return _run(
      () => ref.read(skipHabitDayProvider)(t.id, day: _now),
      doneToast: 'Libur dulu hari ini 🌴 Streak-mu aman.',
    );
  }

  /// Quit: "Hari ini bersih ✅" (toggle).
  Future<bool> toggleClean(HabitToday t) {
    HapticFeedback.lightImpact();
    if (t.cleanCheckIn) {
      return _run(() => ref.read(undoCleanDayProvider)(t.id, _now));
    }
    return _run(
      () => ref.read(confirmCleanDayProvider)(t.id, day: _now),
      xpToast: (xp) => 'Hari bersih tercatat! +$xp XP',
      doneToast: 'Hari ini bersih ✅',
      celebrateFor: t,
    );
  }
}

/// Celebration key of a habit milestone (pruned after 30 days by the game).
String habitMilestoneKey(String today, String habitId, int milestone) =>
    'habit:$today:$habitId:$milestone';

/// The milestone to celebrate for [t] today, or null. Quit: clean-day
/// milestones from 7 up (7, 14, 21, 30, …, 365, every 100); build: 7/30/100
/// once today's (this week's) period is met.
int? habitMilestoneToday(HabitToday t) {
  final s = t.streak;
  if (s.current <= 0) return null;
  if (t.habit.isQuit) {
    return s.current >= 7 && isQuitMilestone(s.current) ? s.current : null;
  }
  return s.periodMet && buildMilestones.contains(s.current) ? s.current : null;
}

/// Shows the milestone celebration of every habit on the board (or only
/// [only]) that reached one today and wasn't celebrated on this device yet.
Future<void> celebrateHabitMilestones(
  BuildContext context,
  WidgetRef ref, {
  String? only,
  bool masked = false,
}) async {
  final HabitBoard board;
  try {
    board = await ref.read(watchHabitBoardProvider.future);
  } catch (_) {
    return;
  }
  for (final t in board.items) {
    if (only != null && t.id != only) continue;
    final m = habitMilestoneToday(t);
    if (m == null) continue;
    final claimed = await ref
        .read(gameActionsProvider)
        .claimCelebration(habitMilestoneKey(t.date, t.id, m));
    if (!claimed || !context.mounted) continue;
    // A run older than the habit (backdated start) reaching a milestone on
    // the creation day earns no XP (habitMilestoneEarned) — no "+XP" promise.
    final earned = t.date.compareTo(dateKey(t.habit.createdAt.toLocal())) > 0;
    final bonus = earned
        ? XpRules.habitMilestoneBonus(t.habit.kind.wire, m)
        : 0;
    await showCelebration(
      context,
      title: milestoneTitle(t.habit.kind, m, t.streak.unit),
      subtitle: milestoneSubtitle(t.habit, m, masked: masked),
      xp: bonus > 0 ? bonus : null,
      stats: [
        CelebrationStat(
          label: t.habit.isQuit ? 'Hari bersih' : 'Streak',
          value: '$m ${t.streak.unit.label}',
          icon: t.habit.isQuit
              ? Icons.park_rounded
              : Icons.local_fire_department_rounded,
          color: t.habit.isQuit ? GhinaColors.green : GhinaColors.orange,
        ),
      ],
      buttonLabel: 'Lanjut',
    );
    if (!context.mounted) return;
  }
}
