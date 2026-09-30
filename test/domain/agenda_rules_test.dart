// Reminders + calendar pure rules (port of the web's src/lib/reminders.ts and
// src/lib/calendar.ts; docs/mobile-sync.md "Reminders" / "Calendar events").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

ReminderItem _r(
  String id,
  DateTime due, {
  ReminderRecurrence? rec,
  bool done = false,
  DateTime? doneAt,
  String? notes,
}) => ReminderItem(
  id: id,
  title: 'R $id',
  dueAt: due,
  recurrence: rec,
  done: done,
  doneAt: doneAt,
  notes: notes,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

CalendarEvent _e(
  String id,
  DateTime start, {
  DateTime? end,
  bool allDay = false,
  String title = 'E',
}) => CalendarEvent(
  id: id,
  title: title,
  startAt: start,
  endAt: end,
  allDay: allDay,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('nextReminderDue', () {
    test('daily: steps at least once, keeps the wall-clock time', () {
      final due = DateTime(2026, 10, 1, 7);
      // Completed before it was due → still the next day.
      expect(
        nextReminderDue(
          due,
          ReminderRecurrence.daily,
          DateTime(2026, 10, 1, 6),
        ),
        DateTime(2026, 10, 2, 7),
      );
    });

    test('daily: overdue for days → the first occurrence after now', () {
      final due = DateTime(2026, 9, 25, 7, 30);
      final now = DateTime(2026, 10, 1, 9);
      expect(
        nextReminderDue(due, ReminderRecurrence.daily, now),
        DateTime(2026, 10, 2, 7, 30),
      );
      // Exactly at an occurrence: must be strictly after now.
      expect(
        nextReminderDue(
          due,
          ReminderRecurrence.daily,
          DateTime(2026, 10, 1, 7, 30),
        ),
        DateTime(2026, 10, 2, 7, 30),
      );
    });

    test('weekly: 7 days, same weekday and time', () {
      final due = DateTime(2026, 10, 1, 20); // Thursday
      final next = nextReminderDue(
        due,
        ReminderRecurrence.weekly,
        DateTime(2026, 10, 1, 21),
      );
      expect(next, DateTime(2026, 10, 8, 20));
      expect(next.weekday, DateTime.thursday);
      expect(
        nextReminderDue(due, ReminderRecurrence.weekly, DateTime(2026, 10, 20)),
        DateTime(2026, 10, 22, 20),
      );
    });

    test('monthly keeps the anchor day, clamped to short months', () {
      final jan31 = DateTime(2026, 1, 31, 9);
      final feb = nextReminderDue(
        jan31,
        ReminderRecurrence.monthly,
        DateTime(2026, 1, 31, 10),
      );
      expect(feb, DateTime(2026, 2, 28, 9));
      // Stepping from the original due keeps day 31 for March (no drift to 28).
      expect(
        nextReminderDue(
          jan31,
          ReminderRecurrence.monthly,
          DateTime(2026, 3, 1),
        ),
        DateTime(2026, 3, 31, 9),
      );
      // Leap year: Jan 31 2028 → Feb 29.
      expect(
        nextReminderDue(
          DateTime(2028, 1, 31, 9),
          ReminderRecurrence.monthly,
          DateTime(2028, 2, 1),
        ),
        DateTime(2028, 2, 29, 9),
      );
      // Across the year boundary.
      expect(
        nextReminderDue(
          DateTime(2026, 12, 15, 8),
          ReminderRecurrence.monthly,
          DateTime(2026, 12, 16),
        ),
        DateTime(2027, 1, 15, 8),
      );
    });

    test('yearly: Feb 29 → Feb 28, back to 29 in a leap year', () {
      final leap = DateTime(2028, 2, 29, 6);
      expect(
        nextReminderDue(leap, ReminderRecurrence.yearly, DateTime(2028, 3, 1)),
        DateTime(2029, 2, 28, 6),
      );
      expect(
        nextReminderDue(leap, ReminderRecurrence.yearly, DateTime(2031, 3, 1)),
        DateTime(2032, 2, 29, 6),
      );
    });

    test('a UTC dueAt is stepped in local time', () {
      final local = DateTime(2026, 10, 1, 7);
      expect(
        nextReminderDue(
          local.toUtc(),
          ReminderRecurrence.daily,
          DateTime(2026, 10, 1, 8),
        ),
        DateTime(2026, 10, 2, 7),
      );
    });
  });

  group('completeReminder', () {
    final now = DateTime(2026, 10, 1, 12);

    test('one-off → done, doneAt now, dueAt unchanged', () {
      final r = completeReminder(_r('a', DateTime(2026, 10, 1, 9)), now);
      expect(r.done, isTrue);
      expect(r.doneAt, now);
      expect(r.dueAt, DateTime(2026, 10, 1, 9));
      expect(r.updatedAt, now);
    });

    test(
      'repeating → stays not done, doneAt now, moves to next occurrence',
      () {
        final r = completeReminder(
          _r('b', DateTime(2026, 10, 1, 9), rec: ReminderRecurrence.daily),
          now,
        );
        expect(r.done, isFalse);
        expect(r.doneAt, now);
        expect(r.dueAt, DateTime(2026, 10, 2, 9));
        expect(r.recurrence, ReminderRecurrence.daily);
      },
    );
  });

  test(
    'groupReminders: overdue oldest first, upcoming soonest, done latest',
    () {
      final now = DateTime(2026, 10, 1, 12);
      final g = groupReminders([
        _r('u2', DateTime(2026, 10, 3)),
        _r('o1', DateTime(2026, 9, 30)),
        _r(
          'd1',
          DateTime(2026, 9, 1),
          done: true,
          doneAt: DateTime(2026, 9, 2),
        ),
        _r('u1', DateTime(2026, 10, 1, 13)),
        _r('o0', DateTime(2026, 9, 29)),
        _r(
          'd2',
          DateTime(2026, 9, 5),
          done: true,
          doneAt: DateTime(2026, 9, 6),
        ),
      ], now);
      expect(g.overdue.map((r) => r.id), ['o0', 'o1']);
      expect(g.upcoming.map((r) => r.id), ['u1', 'u2']);
      expect(g.done.map((r) => r.id), ['d2', 'd1']);
      expect(
        _r('x', DateTime(2026, 10, 1, 11)).statusAt(now),
        ReminderStatus.overdue,
      );
    },
  );

  test('computeAgendaReminders: future, not-done ones at dueAt', () {
    final now = DateTime(2026, 10, 1, 12);
    final list = computeAgendaReminders([
      _r('past', DateTime(2026, 10, 1, 11)),
      _r('done', DateTime(2026, 10, 2), done: true),
      _r('b', DateTime(2026, 10, 3, 8), rec: ReminderRecurrence.weekly),
      _r('a', DateTime(2026, 10, 2, 7), notes: 'Setelah makan\nbaris 2'),
    ], now);
    expect(list.map((r) => r.key), ['reminder:a', 'reminder:b']);
    expect(list.first.fireAt, DateTime(2026, 10, 2, 7));
    expect(list.first.route, '/reminders/a');
    expect(list.first.title, contains('R a'));
    expect(list.first.body, contains('Setelah makan'));
    expect(list.first.body, isNot(contains('baris 2')));
    expect(list.last.body, contains('Setiap minggu'));
  });

  group('eventDays', () {
    test('all-day: date parts from start to end, inclusive', () {
      final e = _e(
        'a',
        DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 7),
        allDay: true,
      );
      expect(eventDays(e).map(dateKey), [
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
      ]);
      expect(
        eventDays(_e('b', DateTime(2026, 10, 5), allDay: true)).map(dateKey),
        ['2026-10-05'],
      );
    });

    test('timed: ending exactly at midnight does not spill over', () {
      final e = _e('a', DateTime(2026, 10, 5, 22), end: DateTime(2026, 10, 6));
      expect(eventDays(e).map(dateKey), ['2026-10-05']);
      final overnight = _e(
        'b',
        DateTime(2026, 10, 5, 22),
        end: DateTime(2026, 10, 6, 1),
      );
      expect(eventDays(overnight).map(dateKey), ['2026-10-05', '2026-10-06']);
      // End equal to start (zero length) stays on its day.
      final zero = _e('c', DateTime(2026, 10, 6), end: DateTime(2026, 10, 6));
      expect(eventDays(zero).map(dateKey), ['2026-10-06']);
    });

    test('eventsByDay sorts all-day first, then by start', () {
      final byDay = eventsByDay([
        _e('late', DateTime(2026, 10, 5, 18), title: 'Makan malam'),
        _e('early', DateTime(2026, 10, 5, 8), title: 'Rapat'),
        _e(
          'all',
          DateTime(2026, 10, 4),
          end: DateTime(2026, 10, 5),
          allDay: true,
          title: 'Liburan',
        ),
      ]);
      expect(byDay['2026-10-04']!.map((e) => e.id), ['all']);
      expect(byDay['2026-10-05']!.map((e) => e.id), ['all', 'early', 'late']);
    });

    test('monthGridDays: 42 days starting on the Monday on/before the 1st', () {
      final days = monthGridDays(const YearMonth(2026, 10)); // Oct 1 = Thu
      expect(days, hasLength(42));
      expect(days.first, DateTime(2026, 9, 28));
      expect(days.first.weekday, DateTime.monday);
      expect(days[3], DateTime(2026, 10, 1));
    });
  });

  group('validation', () {
    test('title required, ≤ 200', () {
      expect(requireAgendaTitle('  Rapat  '), 'Rapat');
      expect(
        () => requireAgendaTitle('   '),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => requireAgendaTitle('x' * 201),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('notes/location limits, empty → null', () {
      expect(
        optionalAgendaText('  ', max: 2000, field: 'notes', label: 'Catatan'),
        isNull,
      );
      expect(
        () => optionalAgendaText(
          'x' * 201,
          max: eventLocationMax,
          field: 'location',
          label: 'Lokasi',
        ),
        throwsA(
          isA<ValidationFailure>().having((f) => f.field, 'field', 'location'),
        ),
      );
    });

    test('color: #rrggbb or null', () {
      expect(optionalEventColor(''), isNull);
      expect(optionalEventColor('#1CB0F6'), '#1CB0F6');
      expect(
        () => optionalEventColor('blue'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('end not before start; all-day compares days', () {
      expect(
        () => normalizeEventTimes(
          startAt: DateTime(2026, 10, 5, 10),
          endAt: DateTime(2026, 10, 5, 9),
          allDay: false,
        ),
        throwsA(
          isA<ValidationFailure>().having((f) => f.field, 'field', 'endAt'),
        ),
      );
      final t = normalizeEventTimes(
        startAt: DateTime(2026, 10, 5, 15),
        endAt: DateTime(2026, 10, 5, 9),
        allDay: true,
      );
      expect(t.startAt, DateTime(2026, 10, 5));
      expect(t.endAt, DateTime(2026, 10, 5));
    });
  });
}
