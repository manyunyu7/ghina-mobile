/// Reminders + calendar use cases. Mutations return `Result<T>` and never
/// throw; watch use cases re-evaluate "now" every minute (ticks).
library;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'agenda_rules.dart';
import 'task_usecases.dart' show TickSource;

// ================================================================ reminders

/// Create/edit form of a reminder.
final class ReminderInput {
  const ReminderInput({
    required this.title,
    required this.dueAt,
    this.notes,
    this.recurrence,
  });

  final String title;
  final String? notes;
  final DateTime dueAt;
  final ReminderRecurrence? recurrence;
}

({String title, String? notes}) _validateReminder(ReminderInput i) => (
  title: requireAgendaTitle(i.title),
  notes: optionalAgendaText(
    i.notes,
    max: reminderNotesMax,
    field: 'notes',
    label: 'Catatan',
  ),
);

Future<ReminderItem> _requireReminder(
  ReminderItemRepository repo,
  String id,
) async {
  final r = await repo.getById(id);
  if (r == null) throw const NotFoundFailure('Pengingat tidak ditemukan');
  return r;
}

final class CreateReminder {
  const CreateReminder(this._repo, this._clock);
  final ReminderItemRepository _repo;
  final Clock _clock;

  Future<Result<ReminderItem>> call(ReminderInput input) => guard(() async {
    final v = _validateReminder(input);
    final now = _clock.now();
    final r = ReminderItem(
      id: newId(),
      title: v.title,
      notes: v.notes,
      dueAt: input.dueAt,
      recurrence: input.recurrence,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(r);
    return r;
  });
}

/// Edits title/notes/due/recurrence. A done one-off moved into the future is
/// reopened (otherwise nothing would ever remind about it); a one-off that
/// isn't done has no `doneAt` (server rule).
final class UpdateReminder {
  const UpdateReminder(this._repo, this._clock);
  final ReminderItemRepository _repo;
  final Clock _clock;

  Future<Result<ReminderItem>> call(String id, ReminderInput input) =>
      guard(() async {
        final v = _validateReminder(input);
        final old = await _requireReminder(_repo, id);
        final now = _clock.now();
        var done = old.done;
        if (done && input.dueAt != old.dueAt && input.dueAt.isAfter(now)) {
          done = false;
        }
        // Repeating reminders are never `done`.
        if (input.recurrence != null) done = false;
        final r = old.copyWith(
          title: v.title,
          notes: v.notes,
          dueAt: input.dueAt,
          recurrence: input.recurrence,
          done: done,
          doneAt: done || input.recurrence != null ? old.doneAt : null,
          updatedAt: now,
        );
        await _repo.save(r);
        return r;
      });
}

/// "Selesai": one-off → done; repeating → moves to the next occurrence (one
/// plain upsert, see [completeReminder]).
final class CompleteReminder {
  const CompleteReminder(this._repo, this._clock);
  final ReminderItemRepository _repo;
  final Clock _clock;

  Future<Result<ReminderItem>> call(String id) => guard(() async {
    final old = await _requireReminder(_repo, id);
    final r = completeReminder(old, _clock.now());
    await _repo.save(r);
    return r;
  });
}

/// "Belum selesai" on a done one-off (undo).
final class ReopenReminder {
  const ReopenReminder(this._repo, this._clock);
  final ReminderItemRepository _repo;
  final Clock _clock;

  Future<Result<ReminderItem>> call(String id) => guard(() async {
    final old = await _requireReminder(_repo, id);
    if (!old.done) return old;
    final r = old.copyWith(
      done: false,
      doneAt: old.repeats ? old.doneAt : null,
      updatedAt: _clock.now(),
    );
    await _repo.save(r);
    return r;
  });
}

/// Restores a reminder exactly as it was (undo of a completion).
final class RestoreReminder {
  const RestoreReminder(this._repo, this._clock);
  final ReminderItemRepository _repo;
  final Clock _clock;

  Future<Result<ReminderItem>> call(ReminderItem previous) => guard(() async {
    final r = previous.copyWith(updatedAt: _clock.now());
    await _repo.save(r);
    return r;
  });
}

final class DeleteReminder {
  const DeleteReminder(this._repo);
  final ReminderItemRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

/// The reminders list: overdue / upcoming / done, re-evaluated every minute.
final class WatchReminderGroups {
  const WatchReminderGroups(this._repo, this._ticks);
  final ReminderItemRepository _repo;
  final TickSource _ticks;

  Stream<ReminderGroups> call() => combineLatest2(
    _repo.watchAll(),
    _ticks(),
    (List<ReminderItem> all, DateTime now) => groupReminders(all, now),
  );
}

final class WatchReminderItem {
  const WatchReminderItem(this._repo);
  final ReminderItemRepository _repo;

  Stream<ReminderItem?> call(String id) => _repo.watchById(id);
}

// ================================================================ calendar

/// Create/edit form of an event. All-day: [startAt]/[endAt] are days (time of
/// day ignored); [endAt] is the last day, inclusive.
final class CalendarEventInput {
  const CalendarEventInput({
    required this.title,
    required this.startAt,
    this.endAt,
    this.allDay = false,
    this.color,
    this.location,
    this.notes,
  });

  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final String? color;
  final String? location;
  final String? notes;
}

CalendarEvent _buildEvent(
  String id,
  CalendarEventInput i, {
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  final title = requireAgendaTitle(i.title);
  final times = normalizeEventTimes(
    startAt: i.startAt,
    endAt: i.endAt,
    allDay: i.allDay,
  );
  return CalendarEvent(
    id: id,
    title: title,
    startAt: times.startAt,
    endAt: times.endAt,
    allDay: i.allDay,
    color: optionalEventColor(i.color),
    location: optionalAgendaText(
      i.location,
      max: eventLocationMax,
      field: 'location',
      label: 'Lokasi',
    ),
    notes: optionalAgendaText(
      i.notes,
      max: reminderNotesMax,
      field: 'notes',
      label: 'Catatan',
    ),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

final class CreateCalendarEvent {
  const CreateCalendarEvent(this._repo, this._clock);
  final CalendarEventRepository _repo;
  final Clock _clock;

  Future<Result<CalendarEvent>> call(CalendarEventInput input) =>
      guard(() async {
        final now = _clock.now();
        final e = _buildEvent(newId(), input, createdAt: now, updatedAt: now);
        await _repo.save(e);
        return e;
      });
}

final class UpdateCalendarEvent {
  const UpdateCalendarEvent(this._repo, this._clock);
  final CalendarEventRepository _repo;
  final Clock _clock;

  Future<Result<CalendarEvent>> call(String id, CalendarEventInput input) =>
      guard(() async {
        final old = await _repo.getById(id);
        if (old == null) throw const NotFoundFailure('Acara tidak ditemukan');
        final e = _buildEvent(
          id,
          input,
          createdAt: old.createdAt,
          updatedAt: _clock.now(),
        );
        await _repo.save(e);
        return e;
      });
}

final class DeleteCalendarEvent {
  const DeleteCalendarEvent(this._repo);
  final CalendarEventRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

final class WatchCalendarEvents {
  const WatchCalendarEvents(this._repo);
  final CalendarEventRepository _repo;

  Stream<List<CalendarEvent>> call() => _repo.watchAll();
}

final class WatchCalendarEvent {
  const WatchCalendarEvent(this._repo);
  final CalendarEventRepository _repo;

  Stream<CalendarEvent?> call(String id) => _repo.watchById(id);
}
