/// Reminders ("Pengingat") and calendar events ("Kalender") — synced entities
/// `reminders` / `calendarEvents` (`docs/mobile-sync.md` → "Reminders",
/// "Calendar events").
///
/// Not to be confused with [Reminder] (`reminder.dart`), which is a local
/// notification the app wants scheduled. A [ReminderItem] produces one of those
/// at its `dueAt`.
library;

import 'value_equality.dart';

/// `reminders.recurrence`: null = one-off.
enum ReminderRecurrence {
  daily('daily', 'Setiap hari'),
  weekly('weekly', 'Setiap minggu'),
  monthly('monthly', 'Setiap bulan'),
  yearly('yearly', 'Setiap tahun');

  const ReminderRecurrence(this.wire, this.label);
  final String wire;
  final String label;

  /// Null for one-off (`null`, `""`, `"none"`) and unknown values.
  static ReminderRecurrence? fromWire(String? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return null;
  }
}

/// Label of an optional recurrence ("Sekali" for one-off).
String recurrenceLabel(ReminderRecurrence? r) => r?.label ?? 'Sekali';

/// UI status of a reminder.
enum ReminderStatus { overdue, upcoming, done }

/// A synced reminder: something to be reminded of at [dueAt] (local
/// notification), optionally repeating.
final class ReminderItem with ValueEquality {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.recurrence,
    this.done = false,
    this.doneAt,
  });

  final String id;

  /// 1–200 chars (trimmed).
  final String title;

  /// ≤ 2000 chars, null when empty.
  final String? notes;

  /// Instant (local DateTime).
  final DateTime dueAt;
  final ReminderRecurrence? recurrence;
  final bool done;

  /// Done one-off: when it was completed. Repeating: its last completion.
  final DateTime? doneAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get repeats => recurrence != null;

  /// Overdue = not done and [dueAt] before [now].
  ReminderStatus statusAt(DateTime now) => done
      ? ReminderStatus.done
      : (dueAt.isBefore(now)
            ? ReminderStatus.overdue
            : ReminderStatus.upcoming);

  ReminderItem copyWith({
    String? title,
    Object? notes = _keep,
    DateTime? dueAt,
    Object? recurrence = _keep,
    bool? done,
    Object? doneAt = _keep,
    DateTime? updatedAt,
  }) => ReminderItem(
    id: id,
    title: title ?? this.title,
    notes: identical(notes, _keep) ? this.notes : notes as String?,
    dueAt: dueAt ?? this.dueAt,
    recurrence: identical(recurrence, _keep)
        ? this.recurrence
        : recurrence as ReminderRecurrence?,
    done: done ?? this.done,
    doneAt: identical(doneAt, _keep) ? this.doneAt : doneAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    notes,
    dueAt,
    recurrence,
    done,
    doneAt,
    createdAt,
    updatedAt,
  ];
}

const Object _keep = Object();

/// UI default of an event without a color (web `DEFAULT_EVENT_COLOR`).
const defaultEventColor = '#6366f1';

/// Event colors offered by the form (web `EVENT_COLORS`).
const eventColors = [
  '#6366f1',
  '#1CB0F6',
  '#58CC02',
  '#FF9600',
  '#FF4B4B',
  '#CE82FF',
  '#64748b',
];

/// A synced calendar event.
///
/// Timed ([allDay] false): [startAt]/[endAt] are instants (local DateTimes).
/// All-day: [startAt]/[endAt] are **dates** — local midnight of the wire's date
/// part (never converted through a time zone); [endAt] is the last day,
/// inclusive; null = a single day.
final class CalendarEvent with ValueEquality {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.createdAt,
    required this.updatedAt,
    this.endAt,
    this.allDay = false,
    this.color,
    this.location,
    this.notes,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;

  /// `#rrggbb` or null (UI default [defaultEventColor]).
  final String? color;
  final String? location;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayColor => color ?? defaultEventColor;

  CalendarEvent copyWith({
    String? title,
    DateTime? startAt,
    Object? endAt = _keep,
    bool? allDay,
    Object? color = _keep,
    Object? location = _keep,
    Object? notes = _keep,
    DateTime? updatedAt,
  }) => CalendarEvent(
    id: id,
    title: title ?? this.title,
    startAt: startAt ?? this.startAt,
    endAt: identical(endAt, _keep) ? this.endAt : endAt as DateTime?,
    allDay: allDay ?? this.allDay,
    color: identical(color, _keep) ? this.color : color as String?,
    location: identical(location, _keep) ? this.location : location as String?,
    notes: identical(notes, _keep) ? this.notes : notes as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    startAt,
    endAt,
    allDay,
    color,
    location,
    notes,
    createdAt,
    updatedAt,
  ];
}
