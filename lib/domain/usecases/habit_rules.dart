/// Pure rules of the habits module (`docs/habits.md`) — a port of the server's
/// `src/lib/habits.ts` (same constants, algorithms and Indonesian messages;
/// parity cases in `test/domain/habit_rules_test.dart` mirror
/// `scripts/test-habits.mjs`). Dates are local `YYYY-MM-DD` keys; weeks are
/// ISO weeks (Monday first).
library;

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../entities/entities.dart';

// ---------------------------------------------------------------- constants

const habitNameMax = 60;

/// UTF-16 units (ZWJ sequences / flags are long).
const habitEmojiMax = 32;
const habitWhyMax = 500;
const habitNoteMax = 1000;
const habitRemindersMax = 5;
const habitTriggersMax = 10;
const habitTriggerMax = 30;
const habitUnitMax = 20;
const habitCountGoalMax = 10000.0;
const habitDurationGoalMax = 1440;

/// Upper bound of a day's progress value (count/minutes).
const habitValueMax = 100000.0;

/// Upper bound of relapse/urge counts in one day.
const habitEventCountMax = 1000;

/// Build: at most this many skip days in any rolling 7-day window.
const habitSkipLimit = 2;

/// Preset trigger tags (relapse/urge); custom tags are allowed too.
const habitTriggerPresets = [
  'bosan',
  'stres',
  'sendirian',
  'malam',
  'medsos',
  'capek',
];

/// Quick actions of the emergency screen (text only).
const urgeQuickActions = [
  'Jalan sebentar',
  'Minum air',
  'Telpon teman',
  'Tarik napas dalam',
];

/// Duration of the emergency breathing screen, seconds.
const urgeBreathingSeconds = 60;

/// Gentle lines for the emergency screen (non-judgmental).
const urgeEncouragements = [
  'Rasa pengen ini akan lewat. Kamu lebih kuat dari 60 detik ini.',
  'Tarik napas pelan-pelan. Kamu nggak harus menang selamanya, cukup sekarang.',
  'Setiap kali kamu tahan, otakmu belajar jalan baru.',
  'Kamu sudah sejauh ini — itu nyata, dan itu milikmu.',
  'Nggak apa-apa merasa pengen. Yang penting kamu memilih.',
];

/// Clean-day milestones of quit habits; after 365: every 100 (400, 500, …).
const quitMilestones = [1, 3, 7, 14, 21, 30, 40, 60, 90, 120, 180, 270, 365];

/// Build streak milestones (in the streak's unit: days, or weeks for perWeek).
const buildMilestones = [7, 30, 100];

/// Gamification constants (server `HABIT_XP`, used by the mobile rules). XP
/// never decreases on relapse — rules just stop adding.
abstract final class HabitXp {
  static const buildMet = 5;

  /// Max build habits per day that earn [buildMet].
  static const buildMetDailyCap = 10;
  static const quitCleanCheckIn = 3;
  static const urgeResisted = 5;
  static const urgeResistedDailyCap = 5;

  /// Quit: clean-day streak → bonus.
  static const quitMilestoneBonus = {7: 20, 30: 50, 90: 100, 365: 365};

  /// Build: streak length (days, or weeks for perWeek) → bonus.
  static const buildStreakBonus = {7: 20, 30: 50, 100: 100};
}

/// Log types allowed per habit kind (`done` on a quit habit = the clean
/// check-in).
const habitLogTypesByKind = {
  HabitKind.build: [HabitLogType.done, HabitLogType.skip],
  HabitKind.quit: [HabitLogType.done, HabitLogType.relapse, HabitLogType.urge],
};

// ---------------------------------------------------------------- date helpers

String _plus(String key, int n) => dateKey(addDays(parseDateKey(key), n));

/// Whole days from [a] to [b] (b − a).
int habitDaysBetween(String a, String b) =>
    daysBetween(parseDateKey(b), parseDateKey(a));

/// ISO weekday (1 = Senin … 7 = Minggu) of a date key.
int isoWeekdayOf(String key) => parseDateKey(key).weekday;

/// Monday (`YYYY-MM-DD`) of the ISO week containing [key].
String isoWeekStart(String key) {
  final d = parseDateKey(key);
  return dateKey(addDays(d, 1 - d.weekday));
}

String _max(String a, String b) => a.compareTo(b) >= 0 ? a : b;
String _min(String a, String b) => a.compareTo(b) <= 0 ? a : b;

// ---------------------------------------------------------------- validation

/// One line: control characters removed, newlines → spaces, trimmed
/// (server `cleanLine`).
String cleanHabitLine(String? v) => (v ?? '')
    .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
    .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
    .replaceAll(RegExp(r' {2,}'), ' ')
    .trim();

/// Multi-line text: `\r\n` → `\n`, control characters (except tab/newline)
/// removed, trimmed (server `cleanText().trim()`).
String _cleanText(String v) => v
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
    .trim();

final _hmRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final _hexRe = RegExp(r'^#[0-9a-fA-F]{6}$');

String requireHabitName(String? v) {
  final s = cleanHabitLine(v);
  if (s.isEmpty) {
    throw const ValidationFailure('Nama wajib diisi', field: 'name');
  }
  if (s.length > habitNameMax) {
    throw const ValidationFailure(
      'Nama maksimal $habitNameMax karakter',
      field: 'name',
    );
  }
  return s;
}

/// One line ≤ 32 UTF-16 units, or null.
String? habitEmoji(String? v) {
  final s = cleanHabitLine(v);
  if (s.isEmpty) return null;
  if (s.length > habitEmojiMax) {
    throw const ValidationFailure('Emoji tidak valid', field: 'emoji');
  }
  return s;
}

String requireHabitColor(String? v) {
  if (v == null || !_hexRe.hasMatch(v)) {
    throw const ValidationFailure('Warna tidak valid', field: 'color');
  }
  return v;
}

/// ≤ 5 local `HH:mm`, deduplicated and sorted.
List<String> habitReminderTimes(List<String>? times) {
  final out = <String>{};
  for (final t in times ?? const <String>[]) {
    if (!_hmRe.hasMatch(t)) {
      throw const ValidationFailure(
        'Jam pengingat harus HH:mm',
        field: 'reminders',
      );
    }
    out.add(t);
  }
  if ((times?.length ?? 0) > habitRemindersMax) {
    throw const ValidationFailure(
      'Maksimal $habitRemindersMax pengingat',
      field: 'reminders',
    );
  }
  return List.unmodifiable(out.toList()..sort());
}

/// Throws unless [s] is valid (weekdays: ≥ 1 day 1–7; perWeek: 1–7).
HabitSchedule requireHabitSchedule(HabitSchedule s) {
  switch (s.type) {
    case HabitScheduleType.daily:
      return HabitSchedule.daily;
    case HabitScheduleType.weekdays:
      if (s.days.any((d) => d < 1 || d > 7)) {
        throw const ValidationFailure('Hari harus 1–7', field: 'schedule');
      }
      if (s.days.isEmpty) {
        throw const ValidationFailure(
          'Pilih minimal satu hari',
          field: 'schedule',
        );
      }
      return HabitSchedule.weekdays(s.days);
    case HabitScheduleType.perWeek:
      final t = s.times ?? 0;
      if (t < 1 || t > 7) {
        throw const ValidationFailure(
          'Target per minggu 1–7',
          field: 'schedule',
        );
      }
      return s;
  }
}

/// Throws unless [t] is valid (count > 0 … 10000 + unit ≤ 20, default
/// `kali`; duration whole minutes 1–1440).
HabitTarget requireHabitTarget(HabitTarget t) {
  switch (t.type) {
    case HabitTargetType.check:
      return HabitTarget.check;
    case HabitTargetType.count:
      if (!t.goal.isFinite || t.goal <= 0) {
        throw const ValidationFailure(
          'Target harus lebih dari 0',
          field: 'target',
        );
      }
      if (t.goal > habitCountGoalMax) {
        throw const ValidationFailure('Target maksimal 10000', field: 'target');
      }
      final unit = cleanHabitLine(t.unit);
      if (unit.length > habitUnitMax) {
        throw const ValidationFailure(
          'Satuan maksimal $habitUnitMax karakter',
          field: 'target',
        );
      }
      return HabitTarget.count(t.goal, unit: unit.isEmpty ? null : unit);
    case HabitTargetType.duration:
      if (t.goal != t.goal.roundToDouble()) {
        throw const ValidationFailure(
          'Durasi dalam menit (bilangan bulat)',
          field: 'target',
        );
      }
      if (t.goal < 1 || t.goal > habitDurationGoalMax) {
        throw const ValidationFailure(
          'Durasi 1–$habitDurationGoalMax menit',
          field: 'target',
        );
      }
      return HabitTarget.duration(t.goal);
  }
}

/// Trigger tags: one line 1–30, deduplicated case-insensitively (first
/// spelling kept), ≤ 10.
List<String> normalizeTriggers(Iterable<String>? tags) {
  final out = <String>[];
  final seen = <String>{};
  for (final x in tags ?? const <String>[]) {
    final t = cleanHabitLine(x);
    final k = t.toLowerCase();
    if (t.isEmpty || !seen.add(k)) continue;
    out.add(t);
  }
  if (out.any((x) => x.length > habitTriggerMax)) {
    throw const ValidationFailure(
      'Pemicu maksimal $habitTriggerMax karakter',
      field: 'triggers',
    );
  }
  if (out.length > habitTriggersMax) {
    throw const ValidationFailure(
      'Maksimal $habitTriggersMax pemicu',
      field: 'triggers',
    );
  }
  return List.unmodifiable(out);
}

/// Union of two trigger lists (case-insensitive, ≤ 10 kept).
List<String> mergeTriggers(List<String> a, Iterable<String> b) {
  final all = <String>[];
  final seen = <String>{};
  for (final t in [...a, ...b]) {
    if (seen.add(t.toLowerCase())) all.add(t);
  }
  return List.unmodifiable(all.take(habitTriggersMax));
}

/// Journal note ≤ 1000 (cleaned, empty → null).
String? habitNote(String? v) {
  if (v == null) return null;
  final s = _cleanText(v);
  if (s.isEmpty) return null;
  if (s.length > habitNoteMax) {
    throw const ValidationFailure(
      'Catatan maksimal $habitNoteMax karakter',
      field: 'note',
    );
  }
  return s;
}

String? habitWhy(String? v) {
  if (v == null) return null;
  final s = _cleanText(v);
  if (s.isEmpty) return null;
  if (s.length > habitWhyMax) {
    throw const ValidationFailure(
      'Alasan maksimal $habitWhyMax karakter',
      field: 'why',
    );
  }
  return s;
}

/// A real `YYYY-MM-DD` (throws with [field]).
String requireHabitDate(String? v, {String field = 'date'}) {
  if (v == null || !isDateKey(v) || dateKey(parseDateKey(v)) != v) {
    throw ValidationFailure('Tanggal tidak valid', field: field);
  }
  return v;
}

/// Kind/target-dependent rules of a log row (server `normalizeHabitLog`):
/// build `done` (check → 1; count/duration need a value 0–100000, duration
/// whole minutes) | `skip` (value null); quit `done` (value 1) | `relapse` /
/// `urge` (integer 1–1000, default 1). Triggers only on relapse/urge. Throws
/// a [ValidationFailure] with the server's message.
HabitLog normalizeHabitLog(Habit h, HabitLog log) {
  if (!habitLogTypesByKind[h.kind]!.contains(log.type)) {
    throw ValidationFailure(
      h.isBuild
          ? 'Kebiasaan membangun hanya bisa dicatat selesai atau libur'
          : 'Kebiasaan berhenti tidak bisa diberi hari libur',
      field: 'type',
    );
  }
  var out = log;
  if (log.type != HabitLogType.relapse && log.type != HabitLogType.urge) {
    out = out.copyWith(triggers: const []);
  }
  switch (log.type) {
    case HabitLogType.skip:
      return out.copyWith(value: null);
    case HabitLogType.done:
      if (h.isQuit || h.target.isCheck) return out.copyWith(value: 1.0);
      final v = log.value;
      if (v == null) {
        throw const ValidationFailure('Progres wajib diisi', field: 'value');
      }
      if (v < 0 || v > habitValueMax) {
        throw const ValidationFailure('Progres harus 0–100000', field: 'value');
      }
      if (h.target.isDuration && v != v.roundToDouble()) {
        throw const ValidationFailure(
          'Durasi dalam menit (bilangan bulat)',
          field: 'value',
        );
      }
      return out;
    case HabitLogType.relapse:
    case HabitLogType.urge:
      final v = log.value ?? 1;
      if (v != v.roundToDouble() || v < 1 || v > habitEventCountMax) {
        throw const ValidationFailure(
          'Jumlah harus bilangan bulat 1–$habitEventCountMax',
          field: 'value',
        );
      }
      return out.copyWith(value: v);
  }
}

// ---------------------------------------------------------------- day index

/// One day's rows (server `DayLogs`): the `done` value, skip, Σ relapse /
/// urge values.
final class HabitDayLogs {
  double? done;
  bool skip = false;
  double relapse = 0;
  double urge = 0;
}

/// A habit's rows by day, plus the rows themselves.
final class HabitLogIndex {
  HabitLogIndex(Iterable<HabitLog> logs) : logs = List.unmodifiable(logs) {
    for (final l in this.logs) {
      final d = byDay.putIfAbsent(l.date, HabitDayLogs.new);
      rows.putIfAbsent(l.date, () => {})[l.type] = l;
      switch (l.type) {
        case HabitLogType.done:
          d.done = l.value ?? 1;
        case HabitLogType.skip:
          d.skip = true;
        case HabitLogType.relapse:
          d.relapse += (l.value ?? 1) < 0 ? 0 : (l.value ?? 1);
        case HabitLogType.urge:
          d.urge += (l.value ?? 1) < 0 ? 0 : (l.value ?? 1);
      }
    }
  }

  final List<HabitLog> logs;
  final Map<String, HabitDayLogs> byDay = {};
  final Map<String, Map<HabitLogType, HabitLog>> rows = {};

  HabitDayLogs? operator [](String date) => byDay[date];
  HabitLog? row(String date, HabitLogType type) => rows[date]?[type];
}

/// Whether a build day is met: check → a `done` row exists; count/duration →
/// value ≥ goal.
bool isHabitMet(HabitTarget target, HabitDayLogs? day) {
  final v = day?.done;
  if (v == null) return false;
  if (target.isCheck) return true;
  return v >= target.goal;
}

/// Build: the `done` row [done] meets the goal (quit habits: never).
bool isHabitDayMet(Habit h, HabitLog? done) {
  if (h.isQuit || done == null) return false;
  if (h.target.isCheck) return true;
  return (done.value ?? 1) >= h.target.goal;
}

/// Daily/weekdays: whether [date] is scheduled (perWeek: every day may count).
bool isHabitScheduledDay(HabitSchedule s, String date) =>
    !s.isWeekdays || s.days.contains(isoWeekdayOf(date));

/// Status of one day of a build habit (server `buildDayStatus`).
HabitDayState buildDayStatus(
  Habit h,
  HabitLogIndex idx,
  String date,
  String today,
) {
  if (date.compareTo(h.startDate) < 0) return HabitDayState.before;
  if (date.compareTo(today) > 0) return HabitDayState.future;
  if (!isHabitScheduledDay(h.schedule, date)) return HabitDayState.off;
  final day = idx[date];
  if (isHabitMet(h.target, day)) return HabitDayState.met;
  if (day?.skip ?? false) return HabitDayState.skip;
  if (date == today) return HabitDayState.pending;
  final some = day?.done != null && day!.done! > 0;
  if (h.schedule.isPerWeek) {
    return some ? HabitDayState.partial : HabitDayState.off;
  }
  return some ? HabitDayState.partial : HabitDayState.missed;
}

bool _isMiss(HabitDayState s) =>
    s == HabitDayState.missed || s == HabitDayState.partial;

/// perWeek(n) — the ISO week starting [week] (server `weekStatus`): need =
/// min(n, available days on/after the start minus skips; future days of the
/// current week count as available); need 0 → neutral; the current week is
/// pending until met.
HabitWeek habitWeekStatus(
  Habit h,
  HabitLogIndex idx,
  String week,
  String today,
) {
  final times = h.schedule.isPerWeek ? h.schedule.times ?? 1 : 7;
  var met = 0, available = 0;
  for (var i = 0; i < 7; i++) {
    final d = _plus(week, i);
    if (d.compareTo(h.startDate) < 0) continue;
    final day = idx[d];
    if (isHabitMet(h.target, day)) {
      met++;
      available++;
    } else if (!(day?.skip ?? false)) {
      available++;
    }
  }
  final need = times < available ? times : available;
  HabitWeekState state;
  if (need <= 0 || week.compareTo(today) > 0) {
    state = HabitWeekState.neutral;
  } else if (met >= need) {
    state = HabitWeekState.met;
  } else {
    state = isoWeekStart(today) == week
        ? HabitWeekState.pending
        : HabitWeekState.missed;
  }
  return HabitWeek(week: week, met: met, need: need, state: state);
}

// ---------------------------------------------------------------- streaks

/// Earliest date that can matter for a build streak (days before the first
/// done/skip row are all misses).
String _buildScanStart(Habit h, HabitLogIndex idx) {
  String? first;
  for (final l in idx.logs) {
    if ((l.type == HabitLogType.done || l.type == HabitLogType.skip) &&
        (first == null || l.date.compareTo(first) < 0)) {
      first = l.date;
    }
  }
  return first == null ? h.startDate : _max(h.startDate, first);
}

HabitStreak _buildStreak(Habit h, HabitLogIndex idx, String today) {
  if (h.schedule.isPerWeek) {
    final cur = isoWeekStart(today);
    final startWeek = isoWeekStart(_buildScanStart(h, idx));
    var current = 0, longest = 0, run = 0;
    if (h.startDate.compareTo(today) <= 0) {
      for (var w = cur; w.compareTo(startWeek) >= 0; w = _plus(w, -7)) {
        final s = habitWeekStatus(h, idx, w, today).state;
        if (s == HabitWeekState.met) {
          current++;
        } else if (s == HabitWeekState.missed) {
          break;
        }
      }
      for (var w = startWeek; w.compareTo(cur) <= 0; w = _plus(w, 7)) {
        final s = habitWeekStatus(h, idx, w, today).state;
        if (s == HabitWeekState.met) {
          run++;
          if (run > longest) longest = run;
        } else if (s == HabitWeekState.missed) {
          run = 0;
        }
      }
    }
    return HabitStreak(
      kind: HabitKind.build,
      unit: HabitStreakUnit.week,
      current: current,
      longest: longest,
      periodMet:
          habitWeekStatus(h, idx, cur, today).state == HabitWeekState.met,
    );
  }
  final start = _buildScanStart(h, idx);
  var current = 0;
  for (var d = today; d.compareTo(start) >= 0; d = _plus(d, -1)) {
    final s = buildDayStatus(h, idx, d, today);
    if (s == HabitDayState.met) {
      current++;
    } else if (_isMiss(s)) {
      break;
    }
  }
  var longest = 0, run = 0;
  for (var d = start; d.compareTo(today) <= 0; d = _plus(d, 1)) {
    final s = buildDayStatus(h, idx, d, today);
    if (s == HabitDayState.met) {
      run++;
      if (run > longest) longest = run;
    } else if (_isMiss(s)) {
      run = 0;
    }
  }
  return HabitStreak(
    kind: HabitKind.build,
    unit: HabitStreakUnit.day,
    current: current,
    longest: longest,
    periodMet: isHabitMet(h.target, idx[today]),
  );
}

/// Sorted distinct relapse dates (value > 0) within start…today.
List<String> habitRelapseDates(Habit h, HabitLogIndex idx, String today) {
  final out = <String>{};
  for (final l in idx.logs) {
    if (l.type == HabitLogType.relapse &&
        (l.value ?? 1) > 0 &&
        l.date.compareTo(h.startDate) >= 0 &&
        l.date.compareTo(today) <= 0) {
      out.add(l.date);
    }
  }
  return out.toList()..sort();
}

HabitStreak _quitStreak(Habit h, HabitLogIndex idx, String today) {
  if (h.startDate.compareTo(today) > 0) {
    return const HabitStreak(
      kind: HabitKind.quit,
      unit: HabitStreakUnit.day,
      current: 0,
      longest: 0,
    );
  }
  final rel = habitRelapseDates(h, idx, today);
  final segments = <CleanSegment>[];
  var start = h.startDate;
  for (final r in rel) {
    if (r.compareTo(start) > 0) {
      segments.add(
        CleanSegment(
          start: start,
          end: _plus(r, -1),
          days: habitDaysBetween(start, r),
          ongoing: false,
        ),
      );
    }
    start = _plus(r, 1);
  }
  if (start.compareTo(today) <= 0) {
    segments.add(
      CleanSegment(
        start: start,
        end: today,
        days: habitDaysBetween(start, today) + 1,
        ongoing: true,
      ),
    );
  }
  final last = rel.lastOrNull;
  final relapsedToday = last == today;
  final current = relapsedToday
      ? 0
      : habitDaysBetween(last == null ? h.startDate : _plus(last, 1), today) +
            1;
  return HabitStreak(
    kind: HabitKind.quit,
    unit: HabitStreakUnit.day,
    current: current,
    longest: segments.fold(0, (m, s) => s.days > m ? s.days : m),
    lastRelapse: last,
    relapsedToday: relapsedToday,
    segments: List.unmodifiable(segments),
  );
}

HabitStreak _streakOf(Habit h, HabitLogIndex idx, String today) =>
    h.isQuit ? _quitStreak(h, idx, today) : _buildStreak(h, idx, today);

/// Current and longest streak of [h] at [today] (server `habitStreak`).
///
/// Quit: `daysBetween(max(startDate, lastRelapse + 1), today) + 1` (0 when
/// the relapse is today, 0 before the start); longest = the longest clean
/// run. Build daily/weekdays: consecutive met scheduled days (skip/off days
/// neutral, today pending doesn't break, a past partial day is a miss).
/// perWeek(n): consecutive met ISO weeks ([habitWeekStatus]).
HabitStreak habitStreak(Habit h, Iterable<HabitLog> logs, String today) =>
    _streakOf(h, HabitLogIndex(logs), today);

/// The clean streak a relapse on [date] ends ("Kamu sempat bersih 12 hari —
/// itu nyata"): clean days up to the day before, ignoring relapses on/after.
int cleanStreakBefore(Habit h, Iterable<HabitLog> logs, String date) =>
    _quitStreak(
      h,
      HabitLogIndex(logs.where((l) => l.date.compareTo(date) < 0)),
      _plus(date, -1),
    ).current;

// ---------------------------------------------------------------- milestones

bool isQuitMilestone(int days) =>
    quitMilestones.contains(days) || (days > 365 && days % 100 == 0);

/// Smallest quit milestone strictly greater than [days].
int nextQuitMilestone(int days) {
  for (final m in quitMilestones) {
    if (m > days) return m;
  }
  return (days ~/ 100 + 1) * 100;
}

/// Quit milestones reached with a streak of [days] (ascending).
List<int> quitMilestonesReached(int days) => [
  for (final m in quitMilestones)
    if (m <= days) m,
  for (var m = 400; m <= days; m += 100) m,
];

/// The next milestone above [current] (quit: unbounded; build: null past 100).
int? nextHabitMilestone(HabitKind kind, int current) {
  if (kind == HabitKind.quit) return nextQuitMilestone(current);
  for (final m in buildMilestones) {
    if (m > current) return m;
  }
  return null;
}

/// A milestone reached in one streak run (gamification events).
typedef HabitMilestoneHit = ({
  int milestone,
  String reachedOn,
  String runStart,
});

/// Whether milestone [m] of [h] is earned in the app (XP, achievements): a
/// run that began before the habit was created (a backdated start date —
/// "sudah bersih sejak…") only earns the milestones it reaches after the
/// habit's creation day; the ones it had already passed are history.
bool habitMilestoneEarned(Habit h, HabitMilestoneHit m) {
  final created = dateKey(h.createdAt.toLocal());
  return m.runStart.compareTo(created) >= 0 ||
      m.reachedOn.compareTo(created) > 0;
}

/// Every milestone reached in every run of [h] up to [today]: quit clean runs
/// (1, 3, 7, …) and build runs (7, 30, 100 in the streak unit; a perWeek run
/// reaches its milestone on the day its week got met). A later relapse/miss
/// never removes a milestone of an earlier run.
List<HabitMilestoneHit> habitMilestoneHits(
  Habit h,
  Iterable<HabitLog> logs,
  String today,
) {
  final idx = HabitLogIndex(logs);
  final out = <HabitMilestoneHit>[];
  if (h.startDate.compareTo(today) > 0) return out;
  if (h.isQuit) {
    for (final s in _quitStreak(h, idx, today).segments) {
      for (final m in quitMilestonesReached(s.days)) {
        out.add((
          milestone: m,
          reachedOn: _plus(s.start, m - 1),
          runStart: s.start,
        ));
      }
    }
    return out;
  }
  void hit(int run, String on, String start) {
    if (buildMilestones.contains(run)) {
      out.add((milestone: run, reachedOn: on, runStart: start));
    }
  }

  var run = 0;
  var runStart = '';
  if (h.schedule.isPerWeek) {
    final cur = isoWeekStart(today);
    for (
      var w = isoWeekStart(_buildScanStart(h, idx));
      w.compareTo(cur) <= 0;
      w = _plus(w, 7)
    ) {
      final st = habitWeekStatus(h, idx, w, today);
      if (st.state == HabitWeekState.met) {
        if (run == 0) runStart = w;
        run++;
        // The day the week's need was reached.
        var met = 0;
        var on = w;
        for (var i = 0; i < 7; i++) {
          final d = _plus(w, i);
          if (d.compareTo(h.startDate) < 0) continue;
          if (isHabitMet(h.target, idx[d])) met++;
          if (met >= st.need) {
            on = d;
            break;
          }
        }
        hit(run, on, runStart);
      } else if (st.state == HabitWeekState.missed) {
        run = 0;
      }
    }
    return out;
  }
  for (
    var d = _buildScanStart(h, idx);
    d.compareTo(today) <= 0;
    d = _plus(d, 1)
  ) {
    final s = buildDayStatus(h, idx, d, today);
    if (s == HabitDayState.met) {
      if (run == 0) runStart = d;
      run++;
      hit(run, d, runStart);
    } else if (_isMiss(s)) {
      run = 0;
    }
  }
  return out;
}

// ---------------------------------------------------------------- completion

HabitCompletion _completion(
  Habit h,
  HabitLogIndex idx,
  String from,
  String to,
  String today,
) {
  final a = _max(from, h.startDate), b = _min(to, today);
  if (a.compareTo(b) > 0) return const HabitCompletion(met: 0, total: 0);
  var met = 0, total = 0;
  if (h.isQuit) {
    final rel = habitRelapseDates(h, idx, today).toSet();
    for (var d = a; d.compareTo(b) <= 0; d = _plus(d, 1)) {
      total++;
      if (!rel.contains(d)) met++;
    }
  } else if (h.schedule.isPerWeek) {
    for (var w = isoWeekStart(a); w.compareTo(b) <= 0; w = _plus(w, 7)) {
      final s = habitWeekStatus(h, idx, w, today).state;
      if (s == HabitWeekState.met) {
        met++;
        total++;
      } else if (s == HabitWeekState.missed) {
        total++;
      }
    }
  } else {
    for (var d = a; d.compareTo(b) <= 0; d = _plus(d, 1)) {
      final s = buildDayStatus(h, idx, d, today);
      if (s == HabitDayState.met) {
        met++;
        total++;
      } else if (_isMiss(s)) {
        total++;
      }
    }
  }
  return HabitCompletion(met: met, total: total);
}

/// Build: met periods ÷ judged periods in [from, to] (clamped to
/// start…today; skip days / neutral weeks excluded; today / the current
/// week only once met). Quit: clean days ÷ days (server `completionRate`).
HabitCompletion habitCompletion(
  Habit h,
  Iterable<HabitLog> logs,
  String from,
  String to,
  String today,
) => _completion(h, HabitLogIndex(logs), from, to, today);

// ---------------------------------------------------------------- skips

/// Skips in the rolling 7 days ending [date] (inclusive), optionally without
/// [date] itself.
int skipsInLast7Days(
  Iterable<HabitLog> logs,
  String date, {
  bool excludeDate = false,
}) {
  final from = _plus(date, -6);
  return logs
      .where(
        (l) =>
            l.type == HabitLogType.skip &&
            l.date.compareTo(from) >= 0 &&
            l.date.compareTo(date) <= 0 &&
            !(excludeDate && l.date == date),
      )
      .length;
}

/// Whether another rest day on [date] keeps every 7-day window containing it
/// at ≤ 2 skips (an existing skip on [date] itself is not counted twice).
bool canSkipHabitDay(Iterable<HabitLog> logs, String date) {
  final skips = [
    for (final l in logs)
      if (l.type == HabitLogType.skip && l.date != date) l.date,
  ];
  for (var k = 0; k < 7; k++) {
    final from = _plus(date, -k);
    final to = _plus(from, 6);
    final n = skips
        .where((d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0)
        .length;
    if (n + 1 > habitSkipLimit) return false;
  }
  return true;
}

// ---------------------------------------------------------------- cells / today

HabitDayCell _cell(
  Habit h,
  HabitLogIndex idx,
  Set<String>? relapses,
  String d,
  String today,
) {
  final day = idx[d];
  final rows = idx.rows[d] ?? const <HabitLogType, HabitLog>{};
  final HabitDayState state;
  if (h.isQuit) {
    state = d.compareTo(h.startDate) < 0
        ? HabitDayState.before
        : d.compareTo(today) > 0
        ? HabitDayState.future
        : relapses!.contains(d)
        ? HabitDayState.relapse
        : HabitDayState.clean;
  } else {
    state = buildDayStatus(h, idx, d, today);
  }
  return HabitDayCell(
    date: d,
    state: state,
    value: day?.done,
    goal: h.isBuild && !h.target.isCheck ? h.target.goal : null,
    urges: (day?.urge ?? 0).round(),
    relapses: (day?.relapse ?? 0).round(),
    cleanCheckIn: h.isQuit && day?.done != null,
    hasNote: rows.values.any((l) => l.hasNote),
  );
}

/// The state of [date] for [h].
HabitDayCell habitDayCell(
  Habit h,
  Iterable<HabitLog> logs,
  String date,
  String today,
) {
  final idx = HabitLogIndex(logs);
  return _cell(
    h,
    idx,
    h.isQuit ? habitRelapseDates(h, idx, today).toSet() : null,
    date,
    today,
  );
}

/// [h]'s state on [today] (server `habitToday` + the day's rows). [logs] =
/// the habit's rows, any dates.
HabitToday habitToday(Habit h, Iterable<HabitLog> logs, String today) {
  final idx = HabitLogIndex(logs);
  final perWeek = h.isBuild && h.schedule.isPerWeek;
  final week = perWeek
      ? habitWeekStatus(h, idx, isoWeekStart(today), today)
      : null;
  final met = isHabitMet(h.target, idx[today]);
  final scheduled = h.isQuit
      ? true
      : perWeek
      ? week!.state != HabitWeekState.met || met
      : isHabitScheduledDay(h.schedule, today);
  return HabitToday(
    habit: h,
    date: today,
    cell: _cell(
      h,
      idx,
      h.isQuit ? habitRelapseDates(h, idx, today).toSet() : null,
      today,
      today,
    ),
    streak: _streakOf(h, idx, today),
    scheduled: scheduled && h.startDate.compareTo(today) <= 0,
    doneLog: idx.row(today, HabitLogType.done),
    skipLog: idx.row(today, HabitLogType.skip),
    relapseLog: idx.row(today, HabitLogType.relapse),
    urgeLog: idx.row(today, HabitLogType.urge),
    week: week,
    canSkip:
        h.isBuild &&
        idx.row(today, HabitLogType.skip) == null &&
        canSkipHabitDay(idx.logs, today),
    skipsLeft: h.isBuild
        ? (habitSkipLimit -
                  skipsInLast7Days(idx.logs, today, excludeDate: true))
              .clamp(0, habitSkipLimit)
        : 0,
  );
}

/// Order: unarchived first, then `sortOrder`, then creation (server
/// `compareHabits`).
int compareHabits(Habit a, Habit b) {
  if (a.archived != b.archived) return a.archived ? 1 : -1;
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
}

/// Display name outside the Habits screen: private habits are masked
/// (server `maskedHabitName`).
String maskedHabitName(Habit h) => h.isPrivate ? privateHabitTitle : h.name;

/// The today board: non-archived habits in order with their today state.
HabitBoard habitBoard(List<Habit> habits, List<HabitLog> logs, String today) {
  final byHabit = <String, List<HabitLog>>{};
  for (final l in logs) {
    byHabit.putIfAbsent(l.habitId, () => []).add(l);
  }
  final active = habits.where((h) => !h.archived).toList()..sort(compareHabits);
  return HabitBoard(
    date: today,
    items: [
      for (final h in active) habitToday(h, byHabit[h.id] ?? const [], today),
    ],
  );
}

// ---------------------------------------------------------------- insights

List<StreakPoint> _streakHistory(
  Habit h,
  HabitLogIndex idx,
  String from,
  String to,
  String today,
) {
  final out = <StreakPoint>[];
  if (h.isQuit) {
    for (var d = from; d.compareTo(to) <= 0; d = _plus(d, 1)) {
      final v = d.compareTo(today) > 0 || d.compareTo(h.startDate) < 0
          ? 0
          : _quitStreak(h, idx, d).current;
      out.add((date: d, streak: v));
    }
    return out;
  }
  // Forward runs (same result as the backward count at each day).
  final values = <String, int>{};
  final start = _buildScanStart(h, idx);
  var run = 0;
  if (h.schedule.isPerWeek) {
    for (
      var w = isoWeekStart(start);
      w.compareTo(isoWeekStart(today)) <= 0;
      w = _plus(w, 7)
    ) {
      final st = habitWeekStatus(h, idx, w, today);
      var met = 0;
      for (var i = 0; i < 7; i++) {
        final d = _plus(w, i);
        if (d.compareTo(today) > 0) break;
        if (d.compareTo(h.startDate) >= 0 && isHabitMet(h.target, idx[d])) {
          met++;
        }
        values[d] = run + (st.need > 0 && met >= st.need ? 1 : 0);
      }
      if (st.state == HabitWeekState.met) {
        run++;
      } else if (st.state == HabitWeekState.missed) {
        run = 0;
      }
    }
  } else {
    for (var d = start; d.compareTo(today) <= 0; d = _plus(d, 1)) {
      final s = buildDayStatus(h, idx, d, today);
      if (s == HabitDayState.met) {
        run++;
      } else if (_isMiss(s)) {
        run = 0;
      }
      values[d] = run;
    }
  }
  for (var d = from; d.compareTo(to) <= 0; d = _plus(d, 1)) {
    out.add((date: d, streak: values[d] ?? 0));
  }
  return out;
}

/// Aggregations for the insights screen over [from]…[to] (inclusive), server
/// `habitInsights`: heatmap, weeks (perWeek), relapse/urge totals by weekday
/// (index 0 = Senin, from the row's date) and local hour of `at` (rows
/// without `at` → `unknownHour`), weighted by `value`; top triggers (merged
/// case-insensitively, weighted); journal (newest first); clean segments
/// overlapping the range; plus the per-day streak history.
HabitInsights habitInsights(
  Habit h,
  Iterable<HabitLog> logs,
  String from,
  String to,
  String today,
) {
  final idx = HabitLogIndex(logs);
  final rel = h.isQuit ? habitRelapseDates(h, idx, today).toSet() : null;
  final heatmap = <HabitDayCell>[];
  for (var d = from; d.compareTo(to) <= 0; d = _plus(d, 1)) {
    heatmap.add(_cell(h, idx, rel, d, today));
  }
  final weeks = <HabitWeek>[];
  if (h.isBuild && h.schedule.isPerWeek) {
    for (var w = isoWeekStart(from); w.compareTo(to) <= 0; w = _plus(w, 7)) {
      weeks.add(habitWeekStatus(h, idx, w, today));
    }
  }
  final relW = List.filled(7, 0), relH = List.filled(24, 0);
  final urgeW = List.filled(7, 0), urgeH = List.filled(24, 0);
  var relTotal = 0, relUnknown = 0, urgeTotal = 0, urgeUnknown = 0;
  final relDays = <String>{};
  final trig = <String, ({String tag, int count})>{};
  final journal = <HabitJournalEntry>[];
  for (final l in idx.logs) {
    if (l.date.compareTo(from) < 0 || l.date.compareTo(to) > 0) continue;
    if (l.hasNote) {
      journal.add(
        HabitJournalEntry(
          date: l.date,
          type: l.type,
          note: l.note!,
          logId: l.id,
        ),
      );
    }
    if (l.type != HabitLogType.relapse && l.type != HabitLogType.urge) continue;
    final v = l.value ?? 1;
    final n = (v < 0 ? 0 : v).round();
    final isRel = l.type == HabitLogType.relapse;
    final wd = isoWeekdayOf(l.date) - 1;
    if (isRel) {
      relTotal += n;
      relW[wd] += n;
      if (l.at case final at?) {
        relH[at.toLocal().hour] += n;
      } else {
        relUnknown += n;
      }
      relDays.add(l.date);
    } else {
      urgeTotal += n;
      urgeW[wd] += n;
      if (l.at case final at?) {
        urgeH[at.toLocal().hour] += n;
      } else {
        urgeUnknown += n;
      }
    }
    for (final t in l.triggers) {
      final k = t.toLowerCase();
      final e = trig[k];
      trig[k] = (tag: e?.tag ?? t, count: (e?.count ?? 0) + n);
    }
  }
  journal.sort((a, b) => b.date.compareTo(a.date));
  final top = trig.values.toList()
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.tag.compareTo(b.tag);
    });
  final streak = _streakOf(h, idx, today);
  return HabitInsights(
    from: from,
    to: to,
    streak: streak,
    completion: _completion(h, idx, from, to, today),
    heatmap: List.unmodifiable(heatmap),
    weeks: List.unmodifiable(weeks),
    relapses: HabitEventStats(
      total: relTotal,
      days: relDays.length,
      byWeekday: List.unmodifiable(relW),
      byHour: List.unmodifiable(relH),
      unknownHour: relUnknown,
    ),
    urges: HabitEventStats(
      total: urgeTotal,
      byWeekday: List.unmodifiable(urgeW),
      byHour: List.unmodifiable(urgeH),
      unknownHour: urgeUnknown,
    ),
    topTriggers: List.unmodifiable(top),
    journal: List.unmodifiable(journal),
    segments: h.isQuit
        ? List.unmodifiable(
            streak.segments.where(
              (s) => s.end.compareTo(from) >= 0 && s.start.compareTo(to) <= 0,
            ),
          )
        : const [],
    streakHistory: List.unmodifiable(_streakHistory(h, idx, from, to, today)),
  );
}

// ---------------------------------------------------------------- reminders

/// App route of a habit (notification tap target).
String habitRoute(String habitId) => '/habits/$habitId';

/// Reminder key `habit-<habitId>-<YYYYMMDD>-<HHmm>` (never clashes with
/// tasks or posts).
String habitReminderKey(String habitId, String day, String hm) =>
    'habit-$habitId-${day.replaceAll('-', '')}-${hm.replaceAll(':', '')}';

/// How many days ahead habit reminders are scheduled (recomputed every minute
/// and on every change; this only matters while the app isn't opened).
const habitReminderDays = 3;

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Local notifications for habits at their `reminders` times on the next
/// [days] days (today included, past times skipped): build habits on days
/// with something to do (weekdays: scheduled; perWeek: while the week isn't
/// met) that aren't met/skipped yet; quit habits a daily check-in nudge
/// unless that day is already checked in clean or has a relapse. Private
/// habits: title [privateHabitReminderTitle], neutral body. Soonest first,
/// capped at [max].
List<Reminder> computeHabitReminders(
  List<Habit> habits,
  List<HabitLog> logs,
  DateTime now, {
  int days = habitReminderDays,
  int max = 60,
}) {
  final byHabit = <String, List<HabitLog>>{};
  for (final l in logs) {
    byHabit.putIfAbsent(l.habitId, () => []).add(l);
  }
  final today = dateKey(now);
  final out = <Reminder>[];
  for (final h in habits) {
    if (h.archived || h.reminders.isEmpty) continue;
    final idx = HabitLogIndex(byHabit[h.id] ?? const []);
    final streak = h.isQuit ? _quitStreak(h, idx, today) : null;
    for (var i = 0; i < days; i++) {
      final day = _plus(today, i);
      if (day.compareTo(h.startDate) < 0) continue;
      final dayLogs = idx[day];
      String body;
      if (h.isBuild) {
        if (isHabitMet(h.target, dayLogs) || (dayLogs?.skip ?? false)) continue;
        if (h.schedule.isPerWeek) {
          if (habitWeekStatus(h, idx, isoWeekStart(day), day).state ==
              HabitWeekState.met) {
            continue;
          }
        } else if (!isHabitScheduledDay(h.schedule, day)) {
          continue;
        }
        final t = h.target;
        final progress = dayLogs?.done ?? 0;
        body = t.isCheck
            ? 'Yuk, jangan lupa hari ini 💪'
            : progress > 0
            ? 'Baru ${_fmtNum(progress)}/${t.label} — sedikit lagi!'
            : 'Target hari ini: ${t.label}';
      } else {
        if (dayLogs?.done != null || (dayLogs?.relapse ?? 0) > 0) continue;
        final n = streak!.relapsedToday ? i : streak.current + i;
        body = n > 0
            ? 'Hari bersih ke-$n — cek in yuk, kamu hebat 💪'
            : 'Cek in hari ini yuk, pelan-pelan aja 🌱';
      }
      final base = parseDateKey(day);
      for (final hm in h.reminders) {
        final p = hm.split(':');
        final fireAt = DateTime(
          base.year,
          base.month,
          base.day,
          int.parse(p[0]),
          int.parse(p[1]),
        );
        if (fireAt.isBefore(now)) continue;
        out.add(
          Reminder(
            key: habitReminderKey(h.id, day, hm),
            title: h.isPrivate ? privateHabitReminderTitle : h.title,
            body: h.isPrivate ? 'Ketuk untuk check-in ✨' : body,
            fireAt: fireAt,
            route: habitRoute(h.id),
          ),
        );
      }
    }
  }
  out.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return out.length > max ? out.sublist(0, max) : out;
}
