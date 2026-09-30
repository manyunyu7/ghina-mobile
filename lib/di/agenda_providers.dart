/// Composition root, part 5: reminders ("Pengingat") and calendar events
/// ("Kalender") — `docs/mobile-sync.md` → "Reminders", "Calendar events".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';

// ================================================================ reminders

/// `(ReminderInput(...))` → [ReminderItem].
final createReminderProvider = Provider<CreateReminder>(
  (ref) => CreateReminder(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, ReminderInput)` → [ReminderItem].
final updateReminderProvider = Provider<UpdateReminder>(
  (ref) => UpdateReminder(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — one-off → done; repeating → next occurrence.
final completeReminderProvider = Provider<CompleteReminder>(
  (ref) => CompleteReminder(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — a done one-off back to not done.
final reopenReminderProvider = Provider<ReopenReminder>(
  (ref) => ReopenReminder(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(previous)` — undo of a completion.
final restoreReminderProvider = Provider<RestoreReminder>(
  (ref) => RestoreReminder(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteReminderProvider = Provider<DeleteReminder>(
  (ref) => DeleteReminder(ref.watch(reminderItemRepositoryProvider)),
);

/// Overdue / upcoming / done, re-evaluated every minute.
final watchReminderGroupsProvider = StreamProvider.autoDispose<ReminderGroups>(
  (ref) => WatchReminderGroups(
    ref.watch(reminderItemRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(),
);

final watchReminderItemProvider = StreamProvider.autoDispose
    .family<ReminderItem?, String>(
      (ref, id) =>
          WatchReminderItem(ref.watch(reminderItemRepositoryProvider))(id),
    );

// ================================================================ calendar

final createCalendarEventProvider = Provider<CreateCalendarEvent>(
  (ref) => CreateCalendarEvent(
    ref.watch(calendarEventRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final updateCalendarEventProvider = Provider<UpdateCalendarEvent>(
  (ref) => UpdateCalendarEvent(
    ref.watch(calendarEventRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final deleteCalendarEventProvider = Provider<DeleteCalendarEvent>(
  (ref) => DeleteCalendarEvent(ref.watch(calendarEventRepositoryProvider)),
);

/// Every event, sorted by start.
final watchCalendarEventsProvider =
    StreamProvider.autoDispose<List<CalendarEvent>>(
      (ref) =>
          WatchCalendarEvents(ref.watch(calendarEventRepositoryProvider))(),
    );

final watchCalendarEventProvider = StreamProvider.autoDispose
    .family<CalendarEvent?, String>(
      (ref, id) =>
          WatchCalendarEvent(ref.watch(calendarEventRepositoryProvider))(id),
    );
