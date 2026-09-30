/// Pure rules of reminders and calendar events (port of the web's
/// `src/lib/reminders.ts` / `src/lib/calendar.ts`, validation =
/// `reminderSchema` / `calendarEventSchema`). No I/O.
library;

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/formatters.dart';
import '../entities/agenda.dart';
import '../entities/reminder.dart';

const reminderTitleMax = 200;
const reminderNotesMax = 2000;
const eventLocationMax = 200;

/// Longest span listed day by day (web `MAX_SPAN_DAYS`).
const maxEventSpanDays = 366;

final _hexColorRe = RegExp(r'^#[0-9a-fA-F]{6}$');

// ---------------------------------------------------------------- recurrence

/// One step of [rule] in local wall-clock time. Monthly/yearly use
/// [anchorDay] (the original day of month), clamped to the target month.
DateTime _step(DateTime w, ReminderRecurrence rule, int anchorDay) {
  switch (rule) {
    case ReminderRecurrence.daily:
      return addDays(w, 1);
    case ReminderRecurrence.weekly:
      return addDays(w, 7);
    case ReminderRecurrence.monthly:
      final first = DateTime(w.year, w.month + 1, 1);
      return _withDay(w, first.year, first.month, anchorDay);
    case ReminderRecurrence.yearly:
      return _withDay(w, w.year + 1, w.month, anchorDay);
  }
}

DateTime _withDay(DateTime w, int year, int month, int anchorDay) {
  final dim = daysInMonth(year, month);
  return DateTime(
    year,
    month,
    anchorDay > dim ? dim : anchorDay,
    w.hour,
    w.minute,
    w.second,
    w.millisecond,
  );
}

/// The next due time of a repeating reminder after completing it (web
/// `nextReminderDue`): step [dueAt] by [rule] in the device's **local wall
/// clock** (07:00 stays 07:00 across DST) at least once and until it is after
/// [now]. Monthly/yearly keep [dueAt]'s day of month, clamped to shorter
/// months (Jan 31 → Feb 28 → Mar 31; Feb 29 → Feb 28 next year).
DateTime nextReminderDue(
  DateTime dueAt,
  ReminderRecurrence rule,
  DateTime now,
) {
  final start = dueAt.toLocal();
  var w = start;
  // Bounded: ~100 years of daily steps.
  for (var i = 0; i < 40000 && (i == 0 || !w.isAfter(now)); i++) {
    w = _step(w, rule, start.day);
  }
  return w;
}

/// Completing a reminder (client rule, docs "Reminders"): a one-off becomes
/// `done: true, doneAt: now`; a repeating one stays `done: false`, gets
/// `doneAt: now` and moves `dueAt` to the next occurrence after [now].
ReminderItem completeReminder(ReminderItem r, DateTime now) {
  final rule = r.recurrence;
  if (rule == null) {
    return r.copyWith(done: true, doneAt: now, updatedAt: now);
  }
  return r.copyWith(
    done: false,
    doneAt: now,
    dueAt: nextReminderDue(r.dueAt, rule, now),
    updatedAt: now,
  );
}

// ---------------------------------------------------------------- grouping

/// Reminders split for the list: overdue (oldest first), upcoming (soonest
/// first) and done (latest completion first).
typedef ReminderGroups = ({
  List<ReminderItem> overdue,
  List<ReminderItem> upcoming,
  List<ReminderItem> done,
});

ReminderGroups groupReminders(List<ReminderItem> all, DateTime now) {
  final overdue = <ReminderItem>[];
  final upcoming = <ReminderItem>[];
  final done = <ReminderItem>[];
  for (final r in all) {
    switch (r.statusAt(now)) {
      case ReminderStatus.overdue:
        overdue.add(r);
      case ReminderStatus.upcoming:
        upcoming.add(r);
      case ReminderStatus.done:
        done.add(r);
    }
  }
  int byDue(ReminderItem a, ReminderItem b) {
    final c = a.dueAt.compareTo(b.dueAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  overdue.sort(byDue);
  upcoming.sort(byDue);
  done.sort((a, b) {
    final c = (b.doneAt ?? b.updatedAt).compareTo(a.doneAt ?? a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return (overdue: overdue, upcoming: upcoming, done: done);
}

// ---------------------------------------------------------------- notifications

/// Notification key of a reminder (stable → rescheduling replaces it).
String agendaReminderKey(String id) => 'reminder:$id';

/// Route opened when a reminder notification is tapped.
String reminderRoute(String id) => '/reminders/$id';

/// Local notifications for the reminders: one at each not-done reminder's
/// [ReminderItem.dueAt] still in the future (soonest first, ≤ [max]).
List<Reminder> computeAgendaReminders(
  List<ReminderItem> reminders,
  DateTime now, {
  int max = 60,
}) {
  final out =
      <Reminder>[
        for (final r in reminders)
          if (!r.done && r.dueAt.isAfter(now))
            Reminder(
              key: agendaReminderKey(r.id),
              title: '⏰ ${r.title}',
              body: [
                'Pengingat ${Fmt.time(r.dueAt)}',
                if (r.notes != null && r.notes!.isNotEmpty)
                  r.notes!.split('\n').first,
                if (r.recurrence != null) r.recurrence!.label,
              ].join(' · '),
              fireAt: r.dueAt,
              route: reminderRoute(r.id),
            ),
      ]..sort((a, b) {
        final c = a.fireAt.compareTo(b.fireAt);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
  return out.length > max ? out.sublist(0, max) : out;
}

// ---------------------------------------------------------------- calendar

/// Local days (midnight) an event occupies (web `eventDayKeys`): all-day →
/// its dates from start to end; timed → local days from `startAt` to
/// `endAt − 1 ms` (ending exactly at midnight doesn't spill over). At most
/// [maxEventSpanDays].
List<DateTime> eventDays(CalendarEvent e) {
  final first = startOfDay(e.startAt);
  var last = first;
  final end = e.endAt;
  if (end != null) {
    final lastDay = e.allDay
        ? startOfDay(end)
        : startOfDay(
            end.subtract(const Duration(milliseconds: 1)).isBefore(e.startAt)
                ? e.startAt
                : end.subtract(const Duration(milliseconds: 1)),
          );
    if (lastDay.isAfter(first)) last = lastDay;
  }
  final out = <DateTime>[];
  for (
    var d = first;
    !d.isAfter(last) && out.length < maxEventSpanDays;
    d = addDays(d, 1)
  ) {
    out.add(d);
  }
  return out;
}

/// Events by local day key (`YYYY-MM-DD`), each day sorted all-day first,
/// then by start time, then title.
Map<String, List<CalendarEvent>> eventsByDay(List<CalendarEvent> events) {
  final out = <String, List<CalendarEvent>>{};
  for (final e in events) {
    for (final d in eventDays(e)) {
      (out[dateKey(d)] ??= []).add(e);
    }
  }
  for (final list in out.values) {
    list.sort(compareEvents);
  }
  return out;
}

/// All-day first, then start time, then title.
int compareEvents(CalendarEvent a, CalendarEvent b) {
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final c = a.startAt.compareTo(b.startAt);
  if (c != 0) return c;
  final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return t != 0 ? t : a.id.compareTo(b.id);
}

/// The 6×7 days of a month grid, weeks starting Monday (web `monthGridKeys`).
List<DateTime> monthGridDays(YearMonth month) {
  final first = month.start;
  final start = addDays(first, -(first.weekday - 1));
  return [for (var i = 0; i < 42; i++) addDays(start, i)];
}

// ---------------------------------------------------------------- validation

String requireAgendaTitle(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) {
    throw const ValidationFailure('Judul wajib diisi', field: 'title');
  }
  if (s.length > reminderTitleMax) {
    throw const ValidationFailure(
      'Judul terlalu panjang (maks $reminderTitleMax karakter)',
      field: 'title',
    );
  }
  return s;
}

String? optionalAgendaText(
  String? v, {
  required int max,
  required String field,
  required String label,
}) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (s.length > max) {
    throw ValidationFailure(
      '$label terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

/// `#rrggbb` or null (`""` → null); anything else is a [ValidationFailure].
String? optionalEventColor(String? v) {
  if (v == null || v.isEmpty) return null;
  if (!_hexColorRe.hasMatch(v)) {
    throw const ValidationFailure('Warna tidak valid', field: 'color');
  }
  return v;
}

/// Normalizes an event's times: all-day → local midnights (dates); the end
/// must not be before the start ("Selesai nggak boleh sebelum mulai").
({DateTime startAt, DateTime? endAt}) normalizeEventTimes({
  required DateTime startAt,
  DateTime? endAt,
  required bool allDay,
}) {
  final s = allDay ? startOfDay(startAt) : startAt;
  final e = endAt == null ? null : (allDay ? startOfDay(endAt) : endAt);
  if (e != null && e.isBefore(s)) {
    throw const ValidationFailure(
      'Selesai nggak boleh sebelum mulai',
      field: 'endAt',
    );
  }
  return (startAt: s, endAt: e);
}
