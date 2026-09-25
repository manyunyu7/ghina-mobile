/// Habits use cases (`docs/habits.md`). Mutations return `Result<T>` and never
/// throw; watch use cases re-evaluate "today" every minute (ticks).
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'habit_rules.dart';
import 'task_usecases.dart' show TickSource;

// ---------------------------------------------------------------- inputs

/// Create/edit form of a habit. Quit habits ignore [schedule]/[target]
/// (always daily / check).
final class HabitInput {
  const HabitInput({
    required this.name,
    this.emoji,
    this.color = defaultHabitColor,
    this.kind = HabitKind.build,
    this.schedule = HabitSchedule.daily,
    this.target = HabitTarget.check,
    this.reminders = const [],
    this.isPrivate = false,
    this.why,
    this.startDate,
  });

  final String name;
  final String? emoji;
  final String color;
  final HabitKind kind;
  final HabitSchedule schedule;
  final HabitTarget target;

  /// Local `HH:mm`, ≤ 5.
  final List<String> reminders;
  final bool isPrivate;

  /// "Alasan berhenti" (≤ 500).
  final String? why;

  /// Day streaks start (quit: "sudah bersih sejak…"). Null = today on create,
  /// unchanged on edit.
  final DateTime? startDate;
}

/// A relapse ("Aku kalah kali ini" / relapse sheet). Everything optional.
final class RelapseInput {
  const RelapseInput({
    this.day,
    this.at,
    this.triggers = const [],
    this.note,
    this.count = 1,
  });

  /// Day (default: today, or the day of [at]).
  final DateTime? day;

  /// When it happened (default: now) — for the by-hour insight.
  final DateTime? at;
  final List<String> triggers;
  final String? note;

  /// How many times (≥ 1), added to the day's row.
  final int count;
}

/// An inclusive day range (`YYYY-MM-DD`) for insights.
typedef HabitRange = ({String from, String to});

/// The last [days] days ending [today] (e.g. 30 → today and the 29 before).
HabitRange habitRangeLastDays(DateTime today, int days) =>
    (from: dateKey(addDays(startOfDay(today), 1 - days)), to: dateKey(today));

/// A calendar month.
HabitRange habitRangeOfMonth(YearMonth m) =>
    (from: dateKey(m.start), to: dateKey(m.end));

// ---------------------------------------------------------------- helpers

Future<Habit> _requireHabit(HabitRepository repo, String id) async {
  final h = await repo.getById(id);
  if (h == null) throw const NotFoundFailure('Kebiasaan tidak ditemukan');
  return h;
}

/// A day the user may log: not after today.
String _logDay(DateTime? day, DateTime now) {
  final d = dateKey(day ?? now);
  if (d.compareTo(dateKey(now)) > 0) {
    throw const ValidationFailure(
      'Belum bisa mencatat hari esok',
      field: 'date',
    );
  }
  return d;
}

void _requireKind(Habit h, HabitKind kind) {
  if (h.kind != kind) {
    throw ValidationFailure(
      kind == HabitKind.build
          ? 'Hanya untuk kebiasaan yang dibangun'
          : 'Hanya untuk kebiasaan yang ingin dihentikan',
      field: 'kind',
    );
  }
}

Habit _buildHabit(
  String id,
  HabitInput input, {
  required DateTime createdAt,
  required DateTime now,
  required String startDate,
  bool archived = false,
  int sortOrder = 0,
}) {
  final quit = input.kind == HabitKind.quit;
  return Habit(
    id: id,
    name: requireHabitName(input.name),
    emoji: habitEmoji(input.emoji),
    color: requireHabitColor(input.color),
    kind: input.kind,
    schedule: quit ? HabitSchedule.daily : requireHabitSchedule(input.schedule),
    target: quit ? HabitTarget.check : requireHabitTarget(input.target),
    reminders: habitReminderTimes(input.reminders),
    isPrivate: input.isPrivate,
    why: habitWhy(input.why),
    startDate: requireHabitDate(startDate, field: 'startDate'),
    archived: archived,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: now,
  );
}

/// Upserts the (habit, day, type) row: [change] gets the current row (or
/// null) and returns the new one (null = delete).
Future<HabitLog?> _upsertLog(
  HabitLogRepository logs,
  Habit h,
  String day,
  HabitLogType type,
  DateTime now,
  HabitLog? Function(HabitLog? current, HabitLog blank) change,
) async {
  final current = await logs.findByKey(h.id, day, type);
  final blank = HabitLog(
    id: newId(),
    habitId: h.id,
    date: day,
    type: type,
    createdAt: now,
    updatedAt: now,
  );
  final next = change(current, blank);
  if (next == null) {
    if (current != null) await logs.delete(current.id);
    return null;
  }
  final saved = normalizeHabitLog(h, next.copyWith(updatedAt: now));
  await logs.save(saved);
  return saved;
}

// ---------------------------------------------------------------- habit CRUD

/// Creates a habit at the end of the order. `ValidationFailure(field:)`:
/// name, emoji, color, schedule, target, reminders, why, startDate.
final class CreateHabit {
  const CreateHabit(this._habits, this._clock);
  final HabitRepository _habits;
  final Clock _clock;

  Future<Result<Habit>> call(HabitInput input) => guard(() async {
    final now = _clock.now();
    final all = await _habits.getAll();
    final order = all.fold(-1, (m, h) => h.sortOrder > m ? h.sortOrder : m);
    final h = _buildHabit(
      newId(),
      input,
      createdAt: now,
      now: now,
      startDate: dateKey(input.startDate ?? now),
      sortOrder: order + 1,
    );
    await _habits.save(h);
    return h;
  });
}

/// Full edit; keeps archived/sortOrder (and the start date when
/// `input.startDate` is null).
final class UpdateHabit {
  const UpdateHabit(this._habits, this._clock);
  final HabitRepository _habits;
  final Clock _clock;

  Future<Result<Habit>> call(String id, HabitInput input) => guard(() async {
    final e = await _requireHabit(_habits, id);
    final h = _buildHabit(
      id,
      input,
      createdAt: e.createdAt,
      now: _clock.now(),
      startDate: input.startDate == null
          ? e.startDate
          : dateKey(input.startDate!),
      archived: e.archived,
      sortOrder: e.sortOrder,
    );
    await _habits.save(h);
    return h;
  });
}

/// `sortOrder` = index of each id (drag & drop).
final class ReorderHabits {
  const ReorderHabits(this._habits, this._uow, this._clock);
  final HabitRepository _habits;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final h = await _habits.getById(id);
        if (h == null || h.sortOrder == i) continue;
        await _habits.save(h.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

final class SetHabitArchived {
  const SetHabitArchived(this._habits, this._clock);
  final HabitRepository _habits;
  final Clock _clock;

  Future<Result<Habit>> call(String id, bool archived) => guard(() async {
    final h = await _requireHabit(_habits, id);
    if (h.archived == archived) return h;
    final u = h.copyWith(archived: archived, updatedAt: _clock.now());
    await _habits.save(u);
    return u;
  });
}

/// Deletes the habit and all its logs (confirm in the UI).
final class DeleteHabit {
  const DeleteHabit(this._habits);
  final HabitRepository _habits;

  Future<Result<void>> call(String id) => guard(() async {
    await _requireHabit(_habits, id);
    await _habits.delete(id);
  });
}

// ---------------------------------------------------------------- build check-in

/// Build habits: records progress for [day] (default today).
/// - check target: the `done` row (value 1); calling again is a no-op.
/// - count/duration: adds [value] (default 1 count / the goal in minutes for
///   duration — a finished timer passes its minutes) to the day's value, or
///   sets it when [add] is false (0 → removes the row).
/// Returns the day's `done` row (null when removed).
final class CheckInHabit {
  const CheckInHabit(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<HabitLog?>> call(
    String habitId, {
    DateTime? day,
    double? value,
    bool add = true,
    String? note,
  }) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    _requireKind(h, HabitKind.build);
    final now = _clock.now();
    final d = _logDay(day, now);
    final n = habitNote(note);
    if (value != null && (!value.isFinite || value < 0)) {
      throw const ValidationFailure('Nilai tidak valid', field: 'value');
    }
    return _upsertLog(_logs, h, d, HabitLogType.done, now, (cur, blank) {
      final base = cur ?? blank;
      if (h.target.isCheck) {
        if (!add && value == 0) return null;
        return base.copyWith(value: 1, note: n ?? base.note);
      }
      var delta = value ?? (h.target.isDuration ? h.target.goal : 1);
      // Durations are whole minutes (a timer rounds to the nearest minute).
      if (h.target.isDuration) delta = delta.roundToDouble();
      final next = add ? (cur?.value ?? 0) + delta : delta;
      if (!add && next == 0) return null;
      return base.copyWith(value: next, note: n ?? base.note);
    });
  });
}

/// Build: removes the day's `done` row (un-check).
final class UndoHabitCheckIn {
  const UndoHabitCheckIn(this._habits, this._logs);
  final HabitRepository _habits;
  final HabitLogRepository _logs;

  Future<Result<void>> call(String habitId, DateTime day) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    final row = await _logs.findByKey(h.id, dateKey(day), HabitLogType.done);
    if (row != null) await _logs.delete(row.id);
  });
}

/// Build: an intentional rest day (sakit, libur) — neutral for streaks, at
/// most 2 per rolling 7 days (`ValidationFailure(field: 'skip')`).
final class SkipHabitDay {
  const SkipHabitDay(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<HabitLog>> call(
    String habitId, {
    DateTime? day,
    String? note,
  }) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    _requireKind(h, HabitKind.build);
    final now = _clock.now();
    final d = _logDay(day, now);
    final existing = await _logs.findByKey(h.id, d, HabitLogType.skip);
    final n = habitNote(note);
    if (existing != null) {
      if (n == null || n == existing.note) return existing;
      final u = existing.copyWith(note: n, updatedAt: now);
      await _logs.save(u);
      return u;
    }
    final all = await _logs.getAll(habitId: h.id);
    if (!canSkipHabitDay(all, d)) {
      throw const ValidationFailure(
        'Maksimal $habitSkipLimit hari libur dalam 7 hari',
        field: 'skip',
      );
    }
    final row = HabitLog(
      id: newId(),
      habitId: h.id,
      date: d,
      type: HabitLogType.skip,
      note: n,
      createdAt: now,
      updatedAt: now,
    );
    await _logs.save(row);
    return row;
  });
}

final class UnskipHabitDay {
  const UnskipHabitDay(this._habits, this._logs);
  final HabitRepository _habits;
  final HabitLogRepository _logs;

  Future<Result<void>> call(String habitId, DateTime day) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    final row = await _logs.findByKey(h.id, dateKey(day), HabitLogType.skip);
    if (row != null) await _logs.delete(row.id);
  });
}

// ---------------------------------------------------------------- quit

/// Quit: "Hari ini bersih ✅" — the explicit clean check-in (a `done` row with
/// value 1; streak math ignores it). Refused on a day with a relapse.
final class ConfirmCleanDay {
  const ConfirmCleanDay(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<HabitLog>> call(
    String habitId, {
    DateTime? day,
    String? note,
  }) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    _requireKind(h, HabitKind.quit);
    final now = _clock.now();
    final d = _logDay(day, now);
    if (await _logs.findByKey(h.id, d, HabitLogType.relapse) != null) {
      throw const ValidationFailure(
        'Hari ini sudah tercatat kambuh',
        field: 'date',
      );
    }
    final n = habitNote(note);
    return (await _upsertLog(
      _logs,
      h,
      d,
      HabitLogType.done,
      now,
      (cur, blank) =>
          (cur ?? blank).copyWith(value: 1, note: n ?? (cur ?? blank).note),
    ))!;
  });
}

/// Quit: removes the day's clean check-in.
final class UndoCleanDay {
  const UndoCleanDay(this._habits, this._logs);
  final HabitRepository _habits;
  final HabitLogRepository _logs;

  Future<Result<void>> call(String habitId, DateTime day) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    final row = await _logs.findByKey(h.id, dateKey(day), HabitLogType.done);
    if (row != null) await _logs.delete(row.id);
  });
}

/// Quit: "Lagi pengen, tapi tahan" — the day's urge count +1 (triggers are
/// merged, [at] = the latest urge). Returns the urge row.
final class LogUrge {
  const LogUrge(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<HabitLog>> call(
    String habitId, {
    DateTime? at,
    List<String> triggers = const [],
    String? note,
  }) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    _requireKind(h, HabitKind.quit);
    final now = _clock.now();
    final when = at ?? now;
    final d = _logDay(when, now);
    final tags = normalizeTriggers(triggers);
    final n = habitNote(note);
    return (await _upsertLog(_logs, h, d, HabitLogType.urge, now, (cur, blank) {
      final base = cur ?? blank;
      return base.copyWith(
        value: (cur?.amount ?? 0) + 1,
        triggers: mergeTriggers(base.triggers, tags),
        note: n ?? base.note,
        at: when,
      );
    }))!;
  });
}

/// Records a relapse (no shaming): the day's relapse count += `count`,
/// triggers merged, note replaced when given, `at` = when it happened.
/// Returns the relapse row and the clean streak it ended ("Kamu sempat
/// bersih 12 hari — itu nyata", server `cleanStreakBefore`).
final class LogRelapse {
  const LogRelapse(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<({HabitLog log, int previousStreak})>> call(
    String habitId, [
    RelapseInput input = const RelapseInput(),
  ]) => guard(() => relapse(_habits, _logs, _clock, habitId, input));

  static Future<({HabitLog log, int previousStreak})> relapse(
    HabitRepository habits,
    HabitLogRepository logs,
    Clock clock,
    String habitId,
    RelapseInput input,
  ) async {
    final h = await _requireHabit(habits, habitId);
    _requireKind(h, HabitKind.quit);
    final now = clock.now();
    final when = input.at ?? now;
    final d = _logDay(input.day ?? when, now);
    if (input.count < 1 || input.count > 1000) {
      throw const ValidationFailure('Jumlah tidak valid', field: 'count');
    }
    final tags = normalizeTriggers(input.triggers);
    final n = habitNote(input.note);
    final before = cleanStreakBefore(h, await logs.getAll(habitId: h.id), d);
    final log = (await _upsertLog(logs, h, d, HabitLogType.relapse, now, (
      cur,
      blank,
    ) {
      final base = cur ?? blank;
      return base.copyWith(
        value: (cur?.amount ?? 0) + input.count,
        triggers: mergeTriggers(base.triggers, tags),
        note: n ?? base.note,
        at: when,
      );
    }))!;
    return (log: log, previousStreak: before);
  }
}

/// Emergency screen "Aku kalah kali ini": the urge just logged turns into a
/// relapse (urge −1, row removed at 0; relapse +1). All-or-nothing.
final class ConvertUrgeToRelapse {
  const ConvertUrgeToRelapse(this._habits, this._logs, this._uow, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<({HabitLog log, int previousStreak})>> call(
    String habitId, [
    RelapseInput input = const RelapseInput(),
  ]) => guard(
    () => _uow.run(() async {
      final h = await _requireHabit(_habits, habitId);
      _requireKind(h, HabitKind.quit);
      final now = _clock.now();
      final d = _logDay(input.day ?? input.at ?? now, now);
      await _upsertLog(_logs, h, d, HabitLogType.urge, now, (cur, _) {
        if (cur == null) return null;
        final left = cur.amount - 1;
        return left <= 0 ? null : cur.copyWith(value: left);
      });
      return LogRelapse.relapse(_habits, _logs, _clock, habitId, input);
    }),
  );
}

// ---------------------------------------------------------------- journal & rows

/// Journal: sets the note of the day's row of [type], or — when [type] is
/// null — of the first existing row among relapse, done, skip, urge.
/// Without a row to attach it to → `ValidationFailure(field: 'note')` (log
/// the day first). Empty [note] clears it.
final class SetHabitJournal {
  const SetHabitJournal(this._habits, this._logs, this._clock);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final Clock _clock;

  Future<Result<HabitLog>> call(
    String habitId,
    DateTime day,
    String? note, {
    HabitLogType? type,
  }) => guard(() async {
    final h = await _requireHabit(_habits, habitId);
    final d = dateKey(day);
    HabitLog? row;
    for (final t
        in type == null
            ? const [
                HabitLogType.relapse,
                HabitLogType.done,
                HabitLogType.skip,
                HabitLogType.urge,
              ]
            : [type]) {
      row = await _logs.findByKey(h.id, d, t);
      if (row != null) break;
    }
    if (row == null) {
      throw const ValidationFailure(
        'Catat kebiasaan hari itu dulu, baru tulis jurnal',
        field: 'note',
      );
    }
    final u = row.copyWith(note: habitNote(note), updatedAt: _clock.now());
    await _logs.save(u);
    return u;
  });
}

/// Deletes one row (undo a relapse/urge/skip/check-in from the journal).
final class DeleteHabitLog {
  const DeleteHabitLog(this._logs);
  final HabitLogRepository _logs;

  Future<Result<void>> call(String logId) => guard(() async {
    if (await _logs.getById(logId) == null) {
      throw const NotFoundFailure('Catatan tidak ditemukan');
    }
    await _logs.delete(logId);
  });
}

// ---------------------------------------------------------------- watch

/// Habits in order (`sortOrder`, `createdAt`); archived ones only with
/// [includeArchived].
final class WatchHabits {
  const WatchHabits(this._habits);
  final HabitRepository _habits;

  Stream<List<Habit>> call({bool includeArchived = false}) =>
      _habits.watchAll().map(
        (all) => [
          for (final h in all)
            if (includeArchived || !h.archived) h,
        ]..sort(compareHabits),
      );
}

/// The today board: every non-archived habit with its today state (streak,
/// progress, skip/relapse/urge rows). Re-evaluated at midnight (ticks).
final class WatchHabitBoard {
  const WatchHabitBoard(this._habits, this._logs, this._ticks);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final TickSource _ticks;

  Stream<HabitBoard> call() => combineLatest3(
    _habits.watchAll(),
    _logs.watch(),
    _ticks().map(dateKey).distinct(),
    (List<Habit> h, List<HabitLog> l, String today) => habitBoard(h, l, today),
  ).distinct();
}

/// One habit today (null when deleted).
final class WatchHabitToday {
  const WatchHabitToday(this._habits, this._logs, this._ticks);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final TickSource _ticks;

  Stream<HabitToday?> call(String id) => combineLatest3(
    _habits.watchById(id),
    _logs.watch(habitId: id),
    _ticks().map(dateKey).distinct(),
    (Habit? h, List<HabitLog> l, String today) =>
        h == null ? null : habitToday(h, l, today),
  ).distinct();
}

/// Habit detail: today state + streak, insights (heatmap, completion / clean
/// days, triggers, by weekday/hour, streak history) for [range] and the rows
/// of the range, newest first. Null when deleted.
final class WatchHabitDetail {
  const WatchHabitDetail(this._habits, this._logs, this._ticks);
  final HabitRepository _habits;
  final HabitLogRepository _logs;
  final TickSource _ticks;

  Stream<HabitDetail?> call(String id, HabitRange range) => combineLatest3(
    _habits.watchById(id),
    _logs.watch(habitId: id),
    _ticks().map(dateKey).distinct(),
    (Habit? h, List<HabitLog> l, String today) {
      if (h == null) return null;
      final inRange =
          [
            for (final x in l)
              if (x.date.compareTo(range.from) >= 0 &&
                  x.date.compareTo(range.to) <= 0)
                x,
          ]..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
          });
      return HabitDetail(
        today: habitToday(h, l, today),
        insights: habitInsights(h, l, range.from, range.to, today),
        logs: List.unmodifiable(inRange),
      );
    },
  ).distinct();
}
