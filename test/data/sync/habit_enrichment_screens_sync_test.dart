// What the phase B screens rely on, through real drift + outbox + sync engine
// against the in-memory server: deleting a dimension strips its key locally and
// on the server, and a notes write can't make a queued habit edit lose.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/repositories/people_repositories.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;
  late DriftHabitFieldRepository fields;
  late DriftHabitEventRepository events;

  setUp(() {
    h = Harness();
    fields = DriftHabitFieldRepository(h.store);
    events = DriftHabitEventRepository(h.store);
  });
  tearDown(() => h.close());

  Future<Habit> newHabit() async => (await h.createHabit(
    HabitInput(
      name: 'Berhenti begadang',
      kind: HabitKind.quit,
      startDate: DateTime(2026, 7, 1),
    ),
  )).valueOrThrow;

  test('deleting a dimension strips its key from logs and events, locally and '
      'on the server', () async {
    h.tick();
    final habit = await newHabit();
    // One pull from an enrichment-aware server first: only then do `extra`
    // values go out (see SyncMeta.enrichmentSeen).
    await h.engine.syncNow();
    h.tick();
    final stres = (await CreateHabitField(fields, h.habits, h.clock)(
      const HabitFieldInput(label: 'Tingkat stres', type: HabitFieldType.scale),
    )).valueOrThrow;
    h.tick();
    await CreateHabitField(fields, h.habits, h.clock)(
      const HabitFieldInput(label: 'Suasana'),
    );
    h.tick();
    await LogRelapse(h.habits, h.habitLogs, h.clock, fields)(
      habit.id,
      RelapseInput(
        day: DateTime(2026, 9, 16),
        at: DateTime(2026, 9, 16, 22),
        extra: const {'tingkat_stres': 8, 'suasana': 'capek'},
      ),
    );
    h.tick();
    await SaveHabitEvent(events, h.habits, fields, h.clock)(
      HabitEventInput(
        id: 'ev1',
        habitId: habit.id,
        date: DateTime(2026, 9, 15),
        label: 'Lembur proyek contoh',
        extra: const {'tingkat_stres': 6},
      ),
    );
    await h.engine.syncNow();
    expect(h.server.rejected, isEmpty);
    final logId = (await h.habitLogs.getAll()).single.id;
    expect(h.server.rows[SyncEntity.habitLogs]![logId]!['extra'], {
      'tingkat_stres': 8,
      'suasana': 'capek',
    });

    h.tick();
    expect((await DeleteHabitField(fields)(stres.id)).isOk, isTrue);
    // Local rows lost the key at once.
    expect((await h.habitLogs.getById(logId))!.extra, {'suasana': 'capek'});
    expect((await events.getById('ev1'))!.extra, isEmpty);
    expect(await fields.getById(stres.id), isNull);

    h.server.pushed.clear();
    await h.engine.syncNow();
    expect(h.server.rejected, isEmpty);
    expect(
      h.server.rows[SyncEntity.habitFields]!.containsKey(stres.id),
      isFalse,
    );
    expect(h.server.rows[SyncEntity.habitLogs]![logId]!['extra'], {
      'suasana': 'capek',
    });
    expect(h.server.rows[SyncEntity.habitEvents]!['ev1']!['extra'], isEmpty);
    // And it stays that way after pulling again.
    await h.engine.syncNow();
    expect((await h.habitLogs.getById(logId))!.extra, {'suasana': 'capek'});
  });

  test('a notes write moves the server updatedAt: refreshPending keeps the '
      'queued tools edit from losing last-write-wins', () async {
    h.tick();
    final habit = await newHabit();
    await h.engine.syncNow();

    h.tick();
    await SetHabitTools(h.habits, h.clock)(habit.id, const [
      HabitTool(title: 'Minum air', kind: HabitToolKind.physical),
    ]);
    // The notes write (online) bumps the habit's updatedAt past the edit.
    final bumped = h.clock.now().add(const Duration(minutes: 5));
    h.server.rows[SyncEntity.habits]![habit.id]!['updatedAt'] = h.server.iso(
      bumped.millisecondsSinceEpoch,
    );
    h.clock.advance(const Duration(minutes: 10));
    await h.habits.refreshPending(habit.id);
    final entry = await h.outbox.pendingEntry(SyncEntity.habits, habit.id);
    expect(entry, isNotNull);
    expect(
      entry!.clientUpdatedAt,
      h.clock.now().millisecondsSinceEpoch,
      reason: 're-stamped with the current time',
    );

    await h.engine.syncNow();
    expect(h.server.rejected, isEmpty);
    final tools = h.server.rows[SyncEntity.habits]![habit.id]!['tools'] as List;
    expect((tools.single as Map)['title'], 'Minum air');
  });

  test('refreshPending is a no-op without a queued edit', () async {
    h.tick();
    final habit = await newHabit();
    await h.engine.syncNow();
    await h.habits.refreshPending(habit.id);
    expect(await h.outbox.pendingEntry(SyncEntity.habits, habit.id), isNull);
  });
}
