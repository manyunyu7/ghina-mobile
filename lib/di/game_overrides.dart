/// Wires the gamification engine's data seams (see `lib/domain/game/README.md`).
///
/// Pass to the root scope: `ProviderScope(overrides: gameOverrides, child: App())`.
/// Without them the game providers throw `UnimplementedError`.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/dates.dart';
import '../core/streams.dart';
import '../data/game/shared_prefs_game_store.dart';
import '../domain/entities/entities.dart';
import '../domain/game/activity.dart';
import '../domain/game/game_date.dart';
import '../domain/game/game_store.dart';
import '../domain/usecases/usecases.dart';
import '../presentation/state/game/game_providers.dart';
import '../presentation/state/session_controller.dart';
import 'core_providers.dart';

/// Maps synced rows to the engine's [ActivityEvent]s. [tasks]: every task; the
/// done ones become `ActivityEvent.task` (by `doneAt`).
List<ActivityEvent> activityEventsFrom(
  List<Transaction> transactions,
  List<PrayerEntry> prayers,
  List<HealthEntry> health,
  List<FoodLog> food, {
  List<Task> tasks = const [],
}) => [
  // Balance adjustments and investment cash effects are not "logging a
  // transaction": no XP/streak/goal.
  for (final x in transactions.where((t) => !t.isBalanceOnly))
    ActivityEvent.transaction(
      id: x.id,
      createdAt: x.createdAt,
      type: TxKind.parse(x.type.wire),
      amount: x.amount,
      date: x.date,
    ),
  for (final x in prayers)
    if (GameDate.tryParse(x.date) case final d?)
      ActivityEvent.prayer(
        id: x.id,
        date: d,
        prayer: x.prayer.wire,
        status: x.status.wire,
        qobliyah: x.qobliyah,
        badiyah: x.badiyah,
        createdAt: x.createdAt,
      ),
  for (final x in health)
    ActivityEvent.health(
      id: x.id,
      createdAt: x.createdAt,
      date: x.date,
      hasWeight: x.weight != null,
    ),
  for (final x in food)
    ActivityEvent.food(id: x.id, createdAt: x.createdAt, date: x.date),
  for (final x in tasks)
    if (x.done)
      ActivityEvent.task(
        id: x.id,
        doneAt: x.doneAt ?? x.updatedAt,
        bucket: x.bucket.wire,
        seriesId: x.seriesId,
        areaId: x.areaId,
        createdAt: x.createdAt,
      ),
];

/// Content-planner milestones as [ActivityEvent]s (`lib/domain/game/README.md`
/// → Content): stages reached (from the device-only `stageReachedAt`, stages
/// after `ide` up to the current one), posted posts, weekly targets met, paid
/// sponsors. [transactions] resolve a sponsor's payment time: its linked
/// income transaction's `date`, else the device-only `sponsorPaidAt`, else the
/// item's `createdAt` — never `updatedAt`, which moves with every later edit.
List<ActivityEvent> contentActivityEventsFrom(
  List<ContentItem> items,
  List<ContentPost> posts,
  List<SocialAccount> accounts, {
  List<Transaction> transactions = const [],
}) {
  final acc = {for (final a in accounts) a.id: a};
  final txDate = {for (final t in transactions) t.id: t.date};
  return [
    for (final i in items)
      for (final s in ContentStage.values)
        if (s != ContentStage.ide && s.index <= i.stage.index)
          ActivityEvent.contentStage(
            itemId: i.id,
            stage: s.wire,
            reachedAt: i.stageReachedAt[s] ?? i.updatedAt,
            stageXp: s.xp,
            createdAt: i.createdAt,
          ),
    for (final p in posts)
      if (p.isPosted && p.postedAt != null)
        ActivityEvent.contentPosted(
          postId: p.id,
          itemId: p.contentId,
          accountId: p.accountId,
          platform: acc[p.accountId]?.platform.wire ?? 'other',
          postedAt: p.postedAt!,
          scheduledAt: p.scheduledAt,
          onSchedule: postedOnSchedule(p),
        ),
    for (final a in accounts)
      for (final w in weeklyTargetsMet(a, posts))
        ActivityEvent.contentWeeklyTarget(
          accountId: a.id,
          platform: a.platform.wire,
          weekStart: GameDate.fromDateTime(w.weekStart),
          at: w.at,
          target: a.targetPerWeek!,
        ),
    for (final i in items)
      if (i.sponsor case final s? when s.paid)
        ActivityEvent.contentSponsorPaid(
          itemId: i.id,
          at:
              (s.transactionId == null ? null : txDate[s.transactionId]) ??
              i.sponsorPaidAt ??
              i.createdAt,
          amount: s.amount,
        ),
  ];
}

/// Habit milestones as [ActivityEvent]s (`lib/domain/game/README.md` →
/// Habits): build days met, quit clean check-ins, urges resisted (one event
/// per day row) and streak milestones of every run up to [today] (only those
/// earned after the habit's creation — [habitMilestoneEarned]).
List<ActivityEvent> habitActivityEventsFrom(
  List<Habit> habits,
  List<HabitLog> logs,
  DateTime today,
) {
  final byHabit = <String, List<HabitLog>>{};
  for (final l in logs) {
    byHabit.putIfAbsent(l.habitId, () => []).add(l);
  }
  final todayKey = dateKey(today);
  final out = <ActivityEvent>[];
  for (final h in habits) {
    final rows = byHabit[h.id] ?? const <HabitLog>[];
    for (final l in rows) {
      final d = GameDate.tryParse(l.date);
      if (d == null || l.date.compareTo(todayKey) > 0) continue;
      switch (l.type) {
        case HabitLogType.done when h.isBuild && isHabitDayMet(h, l):
          out.add(
            ActivityEvent.habitDayMet(
              habitId: h.id,
              date: d,
              at: l.createdAt,
              value: l.amount,
            ),
          );
        case HabitLogType.done when h.isQuit:
          out.add(
            ActivityEvent.habitCleanCheckIn(
              habitId: h.id,
              date: d,
              at: l.createdAt,
            ),
          );
        case HabitLogType.urge when h.isQuit && l.amount >= 1:
          out.add(
            ActivityEvent.habitUrgeResisted(
              habitId: h.id,
              date: d,
              at: l.createdAt,
              count: l.amount.round(),
            ),
          );
        default:
          break;
      }
    }
    final unit = h.isBuild && h.schedule.isPerWeek ? 'week' : 'day';
    for (final m in habitMilestoneHits(h, rows, todayKey)) {
      // Backdated start dates don't pay out the milestones already passed.
      if (!habitMilestoneEarned(h, m)) continue;
      final on = GameDate.tryParse(m.reachedOn);
      final start = GameDate.tryParse(m.runStart);
      if (on == null || start == null) continue;
      out.add(
        ActivityEvent.habitMilestone(
          habitId: h.id,
          kind: h.kind.wire,
          milestone: m.milestone,
          date: on,
          runStart: start,
          unit: unit,
        ),
      );
    }
  }
  return out;
}

/// The production overrides (game progress in shared_preferences).
List<Override> get gameOverrides => buildGameOverrides();

/// [store] replaces the shared_preferences store (tests: `InMemoryGameStore()`).
List<Override> buildGameOverrides({GameStore? store}) => [
  gameStoreProvider.overrideWithValue(store ?? SharedPrefsGameStore()),
  gameClockProvider.overrideWith((ref) => ref.watch(clockProvider)),
  gameUserNameProvider.overrideWith(
    (ref) => ref.watch(currentUserProvider)?.displayName,
  ),
  activityEventsSourceProvider.overrideWith(
    (ref) => combineLatestList(
      [
        ref.watch(transactionRepositoryProvider).watch(),
        ref
            .watch(prayerRepositoryProvider)
            .watchRange('0000-01-01', '9999-12-31'),
        ref.watch(healthRepositoryProvider).watchAll(),
        ref.watch(foodRepositoryProvider).watchAll(),
        ref.watch(taskRepositoryProvider).watchAll(),
        ref.watch(contentItemRepositoryProvider).watchAll(),
        ref.watch(contentPostRepositoryProvider).watchAll(),
        ref.watch(socialAccountRepositoryProvider).watchAll(),
        ref.watch(habitRepositoryProvider).watchAll(),
        ref.watch(habitLogRepositoryProvider).watch(),
      ],
      (v) {
        final t = v[0] as List<Transaction>;
        return [
          ...activityEventsFrom(
            t,
            v[1] as List<PrayerEntry>,
            v[2] as List<HealthEntry>,
            v[3] as List<FoodLog>,
            tasks: v[4] as List<Task>,
          ),
          ...contentActivityEventsFrom(
            v[5] as List<ContentItem>,
            v[6] as List<ContentPost>,
            v[7] as List<SocialAccount>,
            transactions: t,
          ),
          ...habitActivityEventsFrom(
            v[8] as List<Habit>,
            v[9] as List<HabitLog>,
            ref.read(clockProvider).now(),
          ),
        ];
      },
    ),
  ),
  budgetStatusSourceProvider.overrideWith(
    (ref) =>
        WatchBudgetUsage(
          ref.watch(budgetRepositoryProvider),
          ref.watch(transactionRepositoryProvider),
          ref.watch(categoryRepositoryProvider),
        )().map(
          (rows) => [
            for (final r in rows)
              BudgetStatus(
                categoryId: r.budget.categoryId,
                categoryName: r.category?.name,
                year: r.budget.year,
                month: r.budget.month,
                budget: r.budget.amount,
                spent: r.spent,
              ),
          ],
        ),
  ),
];
