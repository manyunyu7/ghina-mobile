// Reminders + calendar events through the real drift database + outbox + sync
// engine against the in-memory server (docs/mobile-sync.md "Reminders" /
// "Calendar events").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/models/agenda_wire.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/repositories/agenda_repositories.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;
  late DriftReminderItemRepository reminders;
  late DriftCalendarEventRepository events;

  setUp(() {
    h = Harness();
    reminders = DriftReminderItemRepository(h.store);
    events = DriftCalendarEventRepository(h.store);
  });
  tearDown(() => h.close());

  group('wire', () {
    test('all-day: the date part is read directly, never via local time', () {
      final e = calendarEventFromWire({
        'id': 'e1',
        'title': 'Libur',
        'startAt': '2026-10-05T00:00:00.000Z',
        'endAt': '2026-10-07T00:00:00.000Z',
        'allDay': true,
        'color': '',
        'location': null,
        'notes': null,
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-01T00:00:00.000Z',
      })!;
      expect(e.startAt, DateTime(2026, 10, 5));
      expect(e.endAt, DateTime(2026, 10, 7));
      expect(e.color, isNull);
      final w = calendarEventToWire(e);
      expect(w['startAt'], '2026-10-05T00:00:00.000Z');
      expect(w['endAt'], '2026-10-07T00:00:00.000Z');
      expect(w['allDay'], isTrue);
      // Drift round trip keeps the date whatever the device zone.
      expect(
        e.toCompanion().startAt.value,
        DateTime.utc(2026, 10, 5).millisecondsSinceEpoch,
      );
    });

    test('timed events are instants; reminders map every field', () {
      final e = calendarEventFromWire({
        'id': 'e2',
        'title': 'Rapat',
        'startAt': '2026-10-05T02:00:00.000Z',
        'endAt': null,
        'allDay': false,
        'color': '#1CB0F6',
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-01T00:00:00.000Z',
      })!;
      expect(e.startAt.toUtc(), DateTime.utc(2026, 10, 5, 2));
      expect(calendarEventToWire(e)['startAt'], '2026-10-05T02:00:00.000Z');

      final r = reminderFromWire({
        'id': 'r1',
        'title': 'Obat',
        'notes': '',
        'dueAt': '2026-10-01T00:00:00.000Z',
        'recurrence': 'monthly',
        'done': false,
        'doneAt': '2026-09-01T00:00:00.000Z',
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-02T00:00:00.000Z',
      })!;
      expect(r.notes, isNull);
      expect(r.recurrence, ReminderRecurrence.monthly);
      expect(r.doneAt!.toUtc(), DateTime.utc(2026, 9, 1));
      final w = reminderToWire(r);
      expect(w, {
        'title': 'Obat',
        'notes': null,
        'dueAt': '2026-10-01T00:00:00.000Z',
        'recurrence': 'monthly',
        'done': false,
        'doneAt': '2026-09-01T00:00:00.000Z',
      });
      expect(
        reminderFromWire({...w, 'id': 'x', 'recurrence': 'none'})!.recurrence,
        isNull,
      );
      expect(reminderFromWire({'id': 'bad'}), isNull);
    });
  });

  test('create + complete a repeating reminder syncs as one upsert', () async {
    final create = CreateReminder(reminders, h.clock);
    final complete = CompleteReminder(reminders, h.clock);
    final due = h.clock.now().subtract(const Duration(hours: 2));
    final r = (await create(
      ReminderInput(
        title: '  Minum obat ',
        dueAt: due,
        recurrence: ReminderRecurrence.daily,
      ),
    )).valueOrThrow;
    expect(r.title, 'Minum obat');
    h.tick();
    final done = (await complete(r.id)).valueOrThrow;
    expect(done.done, isFalse);
    expect(
      done.dueAt,
      DateTime(
        due.year,
        due.month,
        due.day + 1,
        due.hour,
        due.minute,
        due.second,
      ),
    );
    expect(await h.outboxCount(), 1, reason: 'upserts of one id collapse');
    await h.engine.syncNow();

    final row = h.server.rows[SyncEntity.reminders]![r.id]!;
    expect(row['recurrence'], 'daily');
    expect(row['done'], isFalse);
    expect(row['doneAt'], isNotNull);
    expect(await h.outboxCount(), 0);
  });

  test('pulls, edits from the web and tombstones reach the device', () async {
    h.server.web(SyncEntity.calendarEvents, 'web-ev', {
      'title': 'Arisan',
      'startAt': '2026-10-10T00:00:00.000Z',
      'endAt': null,
      'allDay': true,
      'color': '#FF9600',
      'location': 'Rumah',
      'notes': null,
    });
    h.server.web(SyncEntity.reminders, 'web-rem', {
      'title': 'Bayar listrik',
      'notes': null,
      'dueAt': '2026-10-20T02:00:00.000Z',
      'recurrence': null,
      'done': false,
      'doneAt': null,
    });
    await h.engine.syncNow();
    final ev = await events.getById('web-ev');
    expect(ev!.startAt, DateTime(2026, 10, 10));
    expect(ev.location, 'Rumah');
    expect((await reminders.getById('web-rem'))!.title, 'Bayar listrik');

    h.server.webDelete(SyncEntity.calendarEvents, 'web-ev');
    await h.engine.syncNow();
    expect(await events.getById('web-ev'), isNull);
  });

  test('event create/update/delete round trip', () async {
    final create = CreateCalendarEvent(events, h.clock);
    final update = UpdateCalendarEvent(events, h.clock);
    final delete = DeleteCalendarEvent(events);
    final bad = await create(
      CalendarEventInput(
        title: 'X',
        startAt: DateTime(2026, 10, 5, 10),
        endAt: DateTime(2026, 10, 5, 9),
      ),
    );
    expect(bad.isOk, isFalse);
    final e = (await create(
      CalendarEventInput(
        title: 'Liburan',
        startAt: DateTime(2026, 10, 5, 13),
        endAt: DateTime(2026, 10, 7, 8),
        allDay: true,
        color: '#58CC02',
      ),
    )).valueOrThrow;
    await h.engine.syncNow();
    final row = h.server.rows[SyncEntity.calendarEvents]![e.id]!;
    expect(row['startAt'], '2026-10-05T00:00:00.000Z');
    expect(row['endAt'], '2026-10-07T00:00:00.000Z');

    h.tick();
    await update(
      e.id,
      CalendarEventInput(
        title: 'Liburan',
        startAt: DateTime(2026, 10, 5, 9),
        endAt: DateTime(2026, 10, 5, 11),
        location: ' Bali ',
      ),
    );
    await h.engine.syncNow();
    final timed = h.server.rows[SyncEntity.calendarEvents]![e.id]!;
    expect(timed['allDay'], isFalse);
    expect(timed['location'], 'Bali');

    h.tick();
    await delete(e.id);
    await h.engine.syncNow();
    expect(h.server.rows[SyncEntity.calendarEvents]![e.id], isNull);
  });
}
