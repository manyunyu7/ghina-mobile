/// JSON wire format of `reminders` and `calendarEvents`
/// (`docs/mobile-sync.md` → "Reminders", "Calendar events") and the drift
/// row ⇄ entity mappers.
///
/// All-day events: the wire carries UTC midnight of the date
/// (`2026-10-05T00:00:00.000Z`). The **date part** is read directly (never
/// converted to local time) and becomes a local-midnight `DateTime`; the local
/// table stores the UTC-midnight epoch ms, read back in UTC.
library;

import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';
import 'wire.dart' show Json, isoUtc;

// ---------------------------------------------------------------- helpers

String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
DateTime? _instantN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// Local midnight of the date part of an ISO string (`2026-10-05T…` → Oct 5).
DateTime? allDayDateFromWire(Object? v) {
  if (v is! String || v.length < 10) return null;
  final key = v.substring(0, 10);
  return isDateKey(key) ? parseDateKey(key) : null;
}

/// `YYYY-MM-DDT00:00:00.000Z` of a local day.
String allDayToWire(DateTime day) => '${dateKey(day)}T00:00:00.000Z';

/// UTC-midnight epoch ms of a local day (all-day storage).
int _allDayMs(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch;

/// Local midnight of the UTC date of [ms] (all-day storage).
DateTime _allDayFromMs(int ms) {
  final u = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}

// ---------------------------------------------------------------- reminders

Json reminderToWire(ReminderItem r) => {
  'title': r.title,
  'notes': r.notes,
  'dueAt': isoUtc(r.dueAt),
  'recurrence': r.recurrence?.wire,
  'done': r.done,
  'doneAt': r.doneAt == null ? null : isoUtc(r.doneAt!),
};

/// A pulled reminder; null when a required field is missing/invalid.
ReminderItem? reminderFromWire(Json j) {
  final dueAt = _instantN(j['dueAt']);
  final id = _strN(j['id']);
  if (id == null || dueAt == null) return null;
  final created = _instantN(j['createdAt']) ?? dueAt;
  return ReminderItem(
    id: id,
    title: j['title'] is String ? j['title'] as String : '',
    notes: _strN(j['notes']),
    dueAt: dueAt,
    recurrence: ReminderRecurrence.fromWire(j['recurrence'] as String?),
    done: j['done'] == true,
    doneAt: _instantN(j['doneAt']),
    createdAt: created,
    updatedAt: _instantN(j['updatedAt']) ?? created,
  );
}

extension ReminderRowX on ReminderRow {
  ReminderItem toEntity() => ReminderItem(
    id: id,
    title: title,
    notes: notes,
    dueAt: dueAt,
    recurrence: ReminderRecurrence.fromWire(recurrence),
    done: done,
    doneAt: doneAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ReminderItemX on ReminderItem {
  ReminderItemsCompanion toCompanion() => ReminderItemsCompanion.insert(
    id: id,
    title: title,
    notes: Value(notes),
    dueAt: dueAt,
    recurrence: Value(recurrence?.wire),
    done: Value(done),
    doneAt: Value(doneAt),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- calendar

Json calendarEventToWire(CalendarEvent e) => {
  'title': e.title,
  'notes': e.notes,
  'startAt': e.allDay ? allDayToWire(e.startAt) : isoUtc(e.startAt),
  'endAt': e.endAt == null
      ? null
      : (e.allDay ? allDayToWire(e.endAt!) : isoUtc(e.endAt!)),
  'allDay': e.allDay,
  'color': e.color,
  'location': e.location,
};

/// A pulled event; null when a required field is missing/invalid.
CalendarEvent? calendarEventFromWire(Json j) {
  final id = _strN(j['id']);
  final allDay = j['allDay'] == true;
  final start = allDay
      ? allDayDateFromWire(j['startAt'])
      : _instantN(j['startAt']);
  if (id == null || start == null) return null;
  final end = allDay ? allDayDateFromWire(j['endAt']) : _instantN(j['endAt']);
  final created = _instantN(j['createdAt']) ?? DateTime.now();
  final color = _strN(j['color']);
  return CalendarEvent(
    id: id,
    title: j['title'] is String ? j['title'] as String : '',
    startAt: start,
    endAt: end,
    allDay: allDay,
    color: color != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)
        ? color
        : null,
    location: _strN(j['location']),
    notes: _strN(j['notes']),
    createdAt: created,
    updatedAt: _instantN(j['updatedAt']) ?? created,
  );
}

extension CalendarEventRowX on CalendarEventRow {
  CalendarEvent toEntity() => CalendarEvent(
    id: id,
    title: title,
    startAt: allDay
        ? _allDayFromMs(startAt)
        : DateTime.fromMillisecondsSinceEpoch(startAt),
    endAt: endAt == null
        ? null
        : (allDay
              ? _allDayFromMs(endAt!)
              : DateTime.fromMillisecondsSinceEpoch(endAt!)),
    allDay: allDay,
    color: color,
    location: location,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension CalendarEventX on CalendarEvent {
  CalendarEventsCompanion toCompanion() => CalendarEventsCompanion.insert(
    id: id,
    title: title,
    startAt: allDay ? _allDayMs(startAt) : startAt.millisecondsSinceEpoch,
    endAt: Value(
      endAt == null
          ? null
          : (allDay ? _allDayMs(endAt!) : endAt!.millisecondsSinceEpoch),
    ),
    allDay: Value(allDay),
    color: Value(color),
    location: Value(location),
    notes: Value(notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
