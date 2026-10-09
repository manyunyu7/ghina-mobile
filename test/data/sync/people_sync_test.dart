// People + habit enrichment through the real drift database + outbox + sync
// engine against the in-memory server (docs/mobile-sync.md "People", "Habit
// enrichment"). All people are invented.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/habits_investments_mappers.dart';
import 'package:ghina/data/models/people_wire.dart';
import 'package:ghina/data/models/wire.dart';
import 'package:ghina/data/repositories/people_repositories.dart';
import 'package:ghina/data/sync/people_sync.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/people_notes_repository.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/data/datasources/local/app_database.dart';

import '../fake_server.dart';
import '../harness.dart';

/// [PeopleNotesRepository] over the [FakeServer]'s notes endpoints.
class ServerPeopleNotes implements PeopleNotesRepository {
  ServerPeopleNotes(this.s);
  final FakeServer s;
  var gets = 0;

  @override
  Future<PersonNotes> fetch(String personId) async {
    gets++;
    final (notes, updated) = s.notesGet(personId);
    return PersonNotes(notes: notes, updatedAt: DateTime.parse(updated));
  }

  @override
  Future<PersonNotesWrite> replace(
    String personId,
    String notes, {
    DateTime? expectedUpdatedAt,
  }) async {
    final (updated, len) = s.notesPut(
      personId,
      notes,
      expectedUpdatedAt: expectedUpdatedAt?.toUtc().toIso8601String(),
    );
    return PersonNotesWrite(
      updatedAt: DateTime.parse(updated),
      notesLength: len,
    );
  }

  @override
  Future<PersonNotesWrite> append(
    String personId,
    String text, {
    String? heading,
  }) async {
    final (updated, len) = s.notesAppend(personId, text, heading: heading);
    return PersonNotesWrite(
      updatedAt: DateTime.parse(updated),
      notesLength: len,
    );
  }
}

void main() {
  late Harness h;
  late DriftPersonRepository people;
  late DriftPersonCategoryRepository categories;
  late DriftPersonFieldRepository fields;
  late DriftPersonDateRepository dates;
  late DriftHabitFieldRepository habitFields;
  late DriftHabitEventRepository habitEvents;
  late SavePerson savePerson;
  late CreatePersonCategory createCategory;
  late UpdatePersonCategory updateCategory;
  late CreatePersonField createField;

  setUp(() {
    h = Harness();
    people = DriftPersonRepository(h.store);
    categories = DriftPersonCategoryRepository(h.store);
    fields = DriftPersonFieldRepository(h.store);
    dates = DriftPersonDateRepository(h.store);
    habitFields = DriftHabitFieldRepository(h.store);
    habitEvents = DriftHabitEventRepository(h.store);
    savePerson = SavePerson(people, categories, fields, dates, h.uow, h.clock);
    createCategory = CreatePersonCategory(categories, h.clock);
    updateCategory = UpdatePersonCategory(categories, h.clock);
    createField = CreatePersonField(fields, h.clock);
  });
  tearDown(() => h.close());

  /// The web's seeded built-in category.
  void seedFamily() => h.server.web(
    SyncEntity.personCategories,
    'pc_u1_family',
    {'key': 'family', 'label': 'Keluarga', 'emoji': '👨‍👩‍👧', 'sortOrder': 0},
  );

  Iterable<String> pushedEntities() => h.server.pushed.map((m) => m.entity);

  group('wire', () {
    test('a person goes out without notes, hasNotes or notesLength', () {
      final now = DateTime(2026, 10, 10);
      final p = Person(
        id: 'p1',
        name: 'Siti Sample',
        category: 'family',
        relation: 'Ibu',
        vibe: PersonVibe.positive,
        birthMonth: 2,
        birthDay: 29,
        tags: const ['inti'],
        fields: const {'ukuran_sepatu': 38, 'hobi': 'berkebun', 'vegan': false},
        hasNotes: true,
        notesLength: 35,
        createdAt: now,
        updatedAt: now,
      );
      final w = personToWire(p);
      expect(w.containsKey('notes'), isFalse);
      expect(w.containsKey('hasNotes'), isFalse);
      expect(w.containsKey('notesLength'), isFalse);
      expect(w['birthYear'], isNull, reason: 'partial birthday: year unknown');
      expect(w['birthMonth'], 2);
      expect(w['fields'], {
        'ukuran_sepatu': 38,
        'hobi': 'berkebun',
        'vegan': false,
      });
      expect(w['vibe'], 'positive');
    });

    test('pulled rows parse leniently; unknown types are ignored', () {
      final p = personFromWire({
        'id': 'p1',
        'name': 'Budi Contoh',
        'vibe': 'something-new',
        'dataStatus': null,
        'tags': '["a","b"]',
        'fields': {
          'x': 1,
          'y': [1],
          'z': 'ok',
        },
        'hasNotes': true,
        'notesLength': 12,
        'createdAt': '2026-10-09T18:59:17.460Z',
        'updatedAt': '2026-10-09T18:59:24.764Z',
      })!;
      expect(p.vibe, PersonVibe.unknown);
      expect(p.dataStatus, PersonDataStatus.sparse);
      expect(p.tags, ['a', 'b']);
      expect(p.fields, {'x': 1, 'z': 'ok'});
      expect(p.hasNotes, isTrue);
      expect(p.category, 'other');
      expect(
        personFieldFromWire({
          'id': 'f',
          'key': 'k',
          'label': 'K',
          'type': 'hologram',
          'createdAt': '2026-10-09T18:59:17.460Z',
        }),
        isNull,
      );
      expect(
        habitFieldFromWire({
          'id': 'f',
          'key': 'k',
          'label': 'K',
          'type': 'hologram',
          'createdAt': '2026-10-09T18:59:17.460Z',
        }),
        isNull,
      );
    });

    test('enrichment keys are left out until the first aware pull', () {
      final data = {'name': 'x', 'tools': [], 'extra': {}, 'tags': []};
      expect(PeopleSync.withoutEnrichment(SyncEntity.habits, data), {
        'name': 'x',
        'extra': {},
        'tags': [],
      });
      expect(PeopleSync.withoutEnrichment(SyncEntity.habitLogs, data), {
        'name': 'x',
        'tools': [],
        'tags': [],
      });
      expect(
        PeopleSync.withoutEnrichment(SyncEntity.people, data),
        data,
        reason: 'other entities are untouched',
      );
    });
  });

  group('push order', () {
    test(
      'categories → fields → people → dates, whatever the queue order',
      () async {
        seedFamily();
        await h.engine.syncNow();
        h.server.pushed.clear();

        h.tick();
        final cat = (await createCategory(
          label: 'Sahabat',
          emoji: '🫂',
        )).valueOrThrow;
        h.tick();
        final def = (await createField(
          const PersonFieldInput(
            label: 'Ukuran sepatu',
            type: PersonFieldType.number,
          ),
        )).valueOrThrow;
        h.tick();
        final p = (await savePerson(
          input: PersonInput(
            name: 'Budi Contoh',
            category: cat.key,
            fields: {def.key: 42},
          ),
          dates: const [
            PersonDateInput(label: 'Hari jadi', month: 6, day: 12, year: 2015),
          ],
        )).valueOrThrow;
        // Re-saving the category and the field moves their entries to the END
        // of the outbox queue: the fixed ranks still send them first.
        h.tick();
        await updateCategory(cat.id, label: 'Sahabat dekat', emoji: '🫂');
        h.tick();
        await UpdatePersonField(fields, h.clock)(
          def.id,
          label: 'Ukuran sepatu (EU)',
        );
        expect((await h.outbox.all()).map((e) => e.entity), [
          SyncEntity.people,
          SyncEntity.personDates,
          SyncEntity.personCategories,
          SyncEntity.personFields,
        ]);

        await h.engine.syncNow();
        expect(h.server.rejected, isEmpty);
        expect(pushedEntities().toList(), [
          SyncEntity.personCategories,
          SyncEntity.personFields,
          SyncEntity.people,
          SyncEntity.personDates,
        ]);
        expect(await h.outboxCount(), 0);
        final row = h.server.rows[SyncEntity.people]![p.id]!;
        expect(row['category'], 'sahabat');
        expect(row['fields'], {'ukuran_sepatu': 42});
        expect(row.containsKey('notes'), isFalse);
        expect(
          h.server.rows[SyncEntity.personCategories]![cat.id]!['label'],
          'Sahabat dekat',
        );
        final d = h.server.rows[SyncEntity.personDates]!.values.single;
        expect(d['personId'], p.id);
        expect([d['month'], d['day'], d['year']], [6, 12, 2015]);
      },
    );

    test('habit fields go before the logs and events that use them', () async {
      h.tick();
      final habit = (await h.createHabit(
        HabitInput(
          name: 'Berhenti begadang',
          kind: HabitKind.quit,
          startDate: DateTime(2026, 7, 1),
        ),
      )).valueOrThrow;
      await h.engine.syncNow();
      h.server.pushed.clear();

      final t = h.clock.now();
      // Events first, the dimension they use last in the queue.
      h.tick();
      await habitEvents.save(
        HabitEvent(
          id: 'ev1',
          habitId: habit.id,
          date: '2026-09-15',
          kind: HabitEventKind.event,
          label: 'Lembur proyek contoh',
          extra: const {'tingkat_stres': 6},
          createdAt: t,
          updatedAt: h.clock.now(),
        ),
      );
      h.tick();
      await h.habitLogs.save(
        HabitLog(
          id: 'lg1',
          habitId: habit.id,
          date: '2026-09-16',
          type: HabitLogType.relapse,
          value: 1,
          extra: const {'tingkat_stres': 8},
          createdAt: t,
          updatedAt: h.clock.now(),
        ),
      );
      h.tick();
      await habitFields.save(
        HabitFieldDef(
          id: 'hf1',
          key: 'tingkat_stres',
          label: 'Tingkat stres',
          type: HabitFieldType.scale,
          min: 1,
          max: 10,
          createdAt: t,
          updatedAt: h.clock.now(),
        ),
      );
      await h.engine.syncNow();
      expect(h.server.rejected, isEmpty);
      final order = pushedEntities().toList();
      expect(order.indexOf(SyncEntity.habitFields), 0);
      expect(h.server.rows[SyncEntity.habitEvents]!['ev1']!['extra'], {
        'tingkat_stres': 6,
      });
      expect(h.server.rows[SyncEntity.habitLogs]!['lg1']!['extra'], {
        'tingkat_stres': 8,
      });
      expect(h.server.rows[SyncEntity.habitFields]!['hf1']!['max'], 10);
      // Pulled back unchanged.
      final ev = await habitEvents.getById('ev1');
      expect(ev!.extra, {'tingkat_stres': 6});
      expect((await h.habitLogs.getById('lg1'))!.extra, {'tingkat_stres': 8});
    });
  });

  group('pull', () {
    test('people, categories, defs and dates arrive; notes never do', () async {
      seedFamily();
      h.server.web(SyncEntity.personFields, 'pf1', {
        'key': 'hobi',
        'label': 'Hobi',
        'type': 'text',
        'options': null,
        'appliesTo': null,
        'sortOrder': 0,
        'showInList': true,
      });
      h.server.web(SyncEntity.people, 'p1', {
        'name': 'Siti Sample',
        'category': 'family',
        'relation': 'Ibu',
        'vibe': 'positive',
        'birthYear': null,
        'birthMonth': 2,
        'birthDay': 29,
        'tags': ['inti'],
        'fields': {'hobi': 'berkebun'},
        'sensitive': true,
        'dataStatus': 'good',
      });
      h.server.personNotes['p1'] = '# Rahasia\nisi catatan';
      h.server.web(SyncEntity.personDates, 'pd1', {
        'personId': 'p1',
        'label': 'Hari jadi',
        'kind': 'anniversary',
        'month': 6,
        'day': 12,
        'year': 1998,
        'remindDaysBefore': 3,
      });
      await h.engine.syncNow();

      final p = (await people.getById('p1'))!;
      expect(p.name, 'Siti Sample');
      expect(p.fields, {'hobi': 'berkebun'});
      expect(p.sensitive, isTrue);
      expect(p.hasNotes, isTrue);
      expect(p.notesLength, '# Rahasia\nisi catatan'.length);
      expect(p.birthYear, isNull);
      expect((await categories.getAll()).single.emoji, '👨‍👩‍👧');
      expect((await fields.getAll()).single.showInList, isTrue);
      final d = (await dates.getForPerson('p1')).single;
      expect(d.kind, PersonDateKind.anniversary);
      expect(d.remindDaysBefore, 3);

      // The notes text is nowhere in the local database.
      final rows = await h.db.customSelect('SELECT * FROM people').get();
      expect(
        rows.single.data.values.whereType<String>().join(' '),
        isNot(contains('Rahasia')),
      );
      expect(rows.single.data.keys, isNot(contains('notes')));
      // Pushing the person back never sends them either.
      h.tick();
      await savePerson(
        id: 'p1',
        input: PersonInput.of(p).withTags(['inti', 'baru']),
      );
      await h.engine.syncNow();
      expect(h.server.personNotes['p1'], '# Rahasia\nisi catatan');
      expect(h.server.rows[SyncEntity.people]!['p1']!['tags'], [
        'inti',
        'baru',
      ]);
    });

    test('rows the v7 app skipped are downloaded after the v8 upgrade '
        '(full pull flag, cursor already at "now")', () async {
      seedFamily();
      h.server.web(SyncEntity.people, 'old1', {
        'name': 'Andi Contoh',
        'category': 'family',
        'tags': <String>[],
        'fields': <String, Object?>{},
      });
      // The device has synced up to now (v7 pulled past people).
      await h.engine.syncNow();
      expect(await people.getById('old1'), isNotNull);
      await people.delete('old1');
      await h.engine.syncNow(); // gone on both sides, tombstone applied
      // Simulate the v7 database: nothing stored for people, cursor advanced,
      // then the v8 migration flags a full pull.
      h.server.web(SyncEntity.people, 'old2', {
        'name': 'Siti Sample',
        'category': 'family',
        'tags': <String>[],
        'fields': <String, Object?>{},
      });
      await h.db.wipe(); // tables empty like a v7 device
      await h.db.updateMeta(
        SyncMetaCompanion(
          cursor: Value(h.server.now + 1000000),
          fullPullRequired: const Value(false),
        ),
      );
      await h.engine.pullOnly();
      expect(
        await people.getById('old2'),
        isNull,
        reason: 'an incremental pull misses it',
      );
      await h.db.updateMeta(
        const SyncMetaCompanion(fullPullRequired: Value(true)),
      );
      await h.engine.pullOnly();
      expect((await people.getById('old2'))!.name, 'Siti Sample');
    });
  });

  group('tombstones and cascades', () {
    test(
      'web deletes: person → dates, category → other, field → key stripped',
      () async {
        seedFamily();
        h.server.web(SyncEntity.personCategories, 'pc-kos', {
          'key': 'kos',
          'label': 'Kos',
          'emoji': '🏠',
          'sortOrder': 1,
        });
        h.server.web(SyncEntity.personCategories, 'pc_u1_other', {
          'key': 'other',
          'label': 'Lainnya',
          'emoji': '👤',
          'sortOrder': 2,
        });
        h.server.web(SyncEntity.personFields, 'pf1', {
          'key': 'hobi',
          'label': 'Hobi',
          'type': 'text',
          'options': null,
          'appliesTo': null,
          'sortOrder': 0,
          'showInList': false,
        });
        for (final (id, name, cat) in [
          ('a', 'Budi Contoh', 'kos'),
          ('b', 'Siti Sample', 'family'),
        ]) {
          h.server.web(SyncEntity.people, id, {
            'name': name,
            'category': cat,
            'tags': <String>[],
            'fields': {'hobi': 'renang'},
          });
        }
        h.server.web(SyncEntity.personDates, 'd1', {
          'personId': 'b',
          'label': 'Hari jadi',
          'kind': 'anniversary',
          'month': 6,
          'day': 12,
          'year': null,
          'remindDaysBefore': null,
        });
        await h.engine.syncNow();
        expect((await dates.getAll()), hasLength(1));

        h.tick();
        h.server.webDelete(SyncEntity.personCategories, 'pc-kos');
        h.server.webDelete(SyncEntity.personFields, 'pf1');
        h.server.webDelete(SyncEntity.people, 'b');
        await h.engine.syncNow();

        expect(await people.getById('b'), isNull);
        expect(
          await dates.getAll(),
          isEmpty,
          reason: 'dates of a deleted person',
        );
        final a = (await people.getById('a'))!;
        expect(a.category, 'other');
        expect(a.fields, isEmpty, reason: 'the def is gone, its key stripped');
        expect(
          (await categories.getAll()).map((c) => c.key),
          isNot(contains('kos')),
        );
      },
    );

    test(
      'deleting a person offline sends one delete and drops its dates',
      () async {
        seedFamily();
        await h.engine.syncNow();
        h.tick();
        final p = (await savePerson(
          input: const PersonInput(name: 'Budi Contoh', category: 'family'),
          dates: const [PersonDateInput(label: 'Hari jadi', month: 6, day: 12)],
        )).valueOrThrow;
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.personDates]!, hasLength(1));
        h.tick();
        expect((await DeletePerson(people)(p.id)).isOk, isTrue);
        expect(await dates.getAll(), isEmpty);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.people]!, isEmpty);
        expect(
          h.server.rows[SyncEntity.personDates]!,
          isEmpty,
          reason: 'the server cascades the dates',
        );
        expect(await h.outboxCount(), 0);
      },
    );

    test('web deleting a habit removes its events and habit-scoped fields; '
        'deleting a dimension strips the key', () async {
      h.server.web(SyncEntity.habits, 'hab1', {
        'name': 'Berhenti begadang',
        'emoji': null,
        'color': '#58CC02',
        'kind': 'quit',
        'schedule': {'type': 'daily'},
        'target': {'type': 'check'},
        'reminders': <String>[],
        'private': false,
        'why': null,
        'startDate': '2026-07-01',
        'archived': false,
        'sortOrder': 0,
        'tools': [
          {'title': 'Minum air', 'detail': 'Segelas', 'kind': 'physical'},
        ],
      });
      h.server.web(SyncEntity.habitFields, 'hf-all', {
        'habitId': null,
        'key': 'suasana',
        'label': 'Suasana',
        'type': 'text',
        'options': null,
        'min': null,
        'max': null,
        'appliesTo': null,
        'sortOrder': 0,
      });
      h.server.web(SyncEntity.habitFields, 'hf-own', {
        'habitId': 'hab1',
        'key': 'tingkat_stres',
        'label': 'Tingkat stres',
        'type': 'number',
        'options': null,
        'min': null,
        'max': null,
        'appliesTo': ['relapse'],
        'sortOrder': 1,
      });
      h.server.web(SyncEntity.habitLogs, 'lg1', {
        'habitId': 'hab1',
        'date': '2026-09-16',
        'type': 'relapse',
        'value': 1,
        'note': null,
        'triggers': <String>[],
        'at': null,
        'extra': {'suasana': 'capek', 'tingkat_stres': 8},
      });
      h.server.web(SyncEntity.habitEvents, 'ev1', {
        'habitId': 'hab1',
        'date': '2026-09-15',
        'kind': 'milestone',
        'label': 'Seminggu bersih',
        'note': null,
        'at': null,
        'extra': {'suasana': 'tenang'},
      });
      await h.engine.syncNow();
      final habit = (await h.habits.getById('hab1'))!;
      expect(habit.tools.single.title, 'Minum air');
      expect(habit.tools.single.kind, HabitToolKind.physical);

      h.tick();
      h.server.webDelete(SyncEntity.habitFields, 'hf-all');
      await h.engine.syncNow();
      expect((await h.habitLogs.getById('lg1'))!.extra, {'tingkat_stres': 8});
      expect((await habitEvents.getById('ev1'))!.extra, isEmpty);

      h.tick();
      h.server.webDelete(SyncEntity.habits, 'hab1');
      await h.engine.syncNow();
      expect(await habitEvents.getById('ev1'), isNull);
      expect(await habitFields.getAll(), isEmpty);
      expect(await h.habitLogs.getById('lg1'), isNull);
    });
  });

  group('rejected, skipped, duplicate', () {
    test('a person in a category the server does not have is rejected, '
        'surfaced and reverted', () async {
      // The server has no personCategories yet (e.g. never seeded).
      h.tick();
      await savePerson(
        input: const PersonInput(name: 'Budi Contoh', category: 'other'),
      );
      await h.engine.syncNow();
      expect(h.server.rejected, hasLength(1));
      expect(h.server.rejected.single.$2, contains('Unknown category'));
      expect(await h.outboxCount(), 0);
      expect(await people.getAll(), isEmpty, reason: 'reverted by the pull');
      final meta = await h.db.getMeta();
      expect(meta.lastError, contains('Unknown category'));
    });

    test(
      'same category key under another id is a duplicate: the local row is '
      'dropped, the server one arrives, people keep working by key',
      () async {
        h.tick();
        final local = (await createCategory(
          label: 'Kos',
          emoji: '🏠',
        )).valueOrThrow;
        expect(local.key, 'kos');
        h.tick();
        await savePerson(
          input: const PersonInput(name: 'Siti Sample', category: 'kos'),
        );
        // Another device created "kos" first.
        h.server.web(SyncEntity.personCategories, 'pc-from-web', {
          'key': 'kos',
          'label': 'Kos',
          'emoji': '🏠',
          'sortOrder': 0,
        });
        await h.engine.syncNow();
        final cats = await categories.getAll();
        expect(cats.map((c) => c.id), ['pc-from-web']);
        expect(h.server.rejected, isEmpty);
        expect(
          h.server.rows[SyncEntity.people]!.values.single['category'],
          'kos',
        );
        expect(await h.outboxCount(), 0);
      },
    );

    test('a field def with a taken key is a duplicate too', () async {
      h.tick();
      await createField(const PersonFieldInput(label: 'Hobi'));
      h.server.web(SyncEntity.personFields, 'pf-web', {
        'key': 'hobi',
        'label': 'Hobi',
        'type': 'text',
        'options': null,
        'appliesTo': null,
        'sortOrder': 0,
        'showInList': false,
      });
      await h.engine.syncNow();
      expect((await fields.getAll()).map((f) => f.id), ['pf-web']);
      expect(h.server.rejected, isEmpty);
    });

    test(
      'an offline edit older than a web edit is skipped: the server wins',
      () async {
        seedFamily();
        await h.engine.syncNow();
        h.tick();
        final p = (await savePerson(
          input: const PersonInput(name: 'Budi Contoh', category: 'family'),
        )).valueOrThrow;
        await h.engine.syncNow();
        // Offline edit, then the web edits the same person (newer).
        h.tick();
        await savePerson(
          id: p.id,
          input: const PersonInput(name: 'Budi (offline)', category: 'family'),
        );
        h.server.now += 3600 * 1000 * 3;
        h.server.web(SyncEntity.people, p.id, {
          'name': 'Budi Contoh Web',
          'category': 'family',
          'tags': <String>[],
          'fields': <String, Object?>{},
        });
        await h.engine.syncNow();
        expect(
          h.server.rows[SyncEntity.people]![p.id]!['name'],
          'Budi Contoh Web',
        );
        expect((await people.getById(p.id))!.name, 'Budi Contoh Web');
        expect(await h.outboxCount(), 0);
      },
    );
  });

  group('notes (online-only)', () {
    test('a notes write does not make a queued metadata edit lose '
        'last-write-wins', () async {
      seedFamily();
      await h.engine.syncNow();
      h.tick();
      final p = (await savePerson(
        input: const PersonInput(name: 'Budi Contoh', category: 'family'),
      )).valueOrThrow;
      await h.engine.syncNow();

      final notes = ServerPeopleNotes(h.server);
      final replace = ReplacePersonNotes(notes, people, h.engine);
      final append = AppendPersonNotes(notes, people, h.engine);

      // Offline-ish edit of the metadata, then a notes write (server updatedAt
      // jumps ahead of the edit's timestamp).
      h.tick();
      await savePerson(
        id: p.id,
        input: const PersonInput(
          name: 'Budi Contoh (edit)',
          category: 'family',
        ),
      );
      // Three hours pass on both clocks: the notes write outdates the edit.
      h.server.now += 3 * 3600 * 1000;
      h.clock.advance(const Duration(hours: 3));
      final r = await replace(p.id, '# Catatan\nsuka kopi');
      expect(r.isOk, isTrue);
      await h.engine.syncNow();

      final row = h.server.rows[SyncEntity.people]![p.id]!;
      expect(
        row['name'],
        'Budi Contoh (edit)',
        reason: 'the edit was not skipped',
      );
      expect(h.server.personNotes[p.id], '# Catatan\nsuka kopi');
      expect((await people.getById(p.id))!.hasNotes, isTrue);

      expect(
        (await append(p.id, 'dengar lagu', heading: '2026-10-10')).isOk,
        isTrue,
      );
      expect(
        h.server.personNotes[p.id],
        '# Catatan\nsuka kopi\n\n## 2026-10-10\ndengar lagu',
      );
    });

    test(
      'replace with a stale expectedUpdatedAt is a clear ConflictFailure',
      () async {
        seedFamily();
        await h.engine.syncNow();
        h.tick();
        final p = (await savePerson(
          input: const PersonInput(name: 'Budi Contoh', category: 'family'),
        )).valueOrThrow;
        await h.engine.syncNow();
        final notes = ServerPeopleNotes(h.server);
        final get = GetPersonNotes(notes);
        final replace = ReplacePersonNotes(notes, people, h.engine);

        final read = (await get(p.id)).valueOrThrow;
        h.server.notesPut(p.id, 'ditulis di web');
        final r = await replace(
          p.id,
          'dari HP',
          expectedUpdatedAt: read.updatedAt,
        );
        expect(r.failureOrNull, isA<ConflictFailure>());
        expect(h.server.personNotes[p.id], 'ditulis di web');
        final fresh = (await get(p.id)).valueOrThrow;
        expect(
          (await replace(
            p.id,
            'dari HP',
            expectedUpdatedAt: fresh.updatedAt,
          )).isOk,
          isTrue,
        );
      },
    );
  });

  group('habit + food enrichment', () {
    Json habitRow({List<Object?>? tools}) => {
      'name': 'Berhenti begadang',
      'emoji': null,
      'color': '#58CC02',
      'kind': 'quit',
      'schedule': {'type': 'daily'},
      'target': {'type': 'check'},
      'reminders': <String>[],
      'private': false,
      'why': 'Tidur cukup',
      'startDate': '2026-07-01',
      'archived': false,
      'sortOrder': 0,
      'tools': tools ?? <Object?>[],
    };

    test('an upgraded device that edits before its first re-pull never wipes '
        'the server\'s tools / extra / tags / caloriesMax', () async {
      final tools = [
        {'title': 'Minum air', 'detail': 'Segelas', 'kind': 'physical'},
      ];
      h.server.web(SyncEntity.habits, 'hab1', habitRow(tools: tools));
      h.server.web(SyncEntity.habitFields, 'hf1', {
        'habitId': null,
        'key': 'suasana',
        'label': 'Suasana',
        'type': 'text',
        'options': null,
        'min': null,
        'max': null,
        'appliesTo': null,
        'sortOrder': 0,
      });
      h.server.web(SyncEntity.habitLogs, 'lg1', {
        'habitId': 'hab1',
        'date': '2026-09-16',
        'type': 'relapse',
        'value': 1,
        'note': null,
        'triggers': <String>[],
        'at': null,
        'extra': {'suasana': 'capek'},
      });
      h.server.web(SyncEntity.food, 'f1', {
        'date': '2026-09-20T05:00:00.000Z',
        'name': 'Nasi campur',
        'meal': 'makan malam',
        'calories': 700,
        'caloriesMax': 900,
        'tags': ['pedas'],
        'photoUrl': null,
        'note': null,
      });
      // The v7 device: rows stored without the new data (defaults), a full
      // pull pending, and the user edits all three before it ever syncs.
      final t = h.clock.now();
      await h.db
          .into(h.db.habits)
          .insert(
            Habit(
              id: 'hab1',
              name: 'Berhenti begadang',
              kind: HabitKind.quit,
              why: 'Tidur cukup',
              startDate: '2026-07-01',
              createdAt: t,
              updatedAt: t.subtract(const Duration(days: 30)),
            ).toCompanion(),
          );
      await h.db.updateMeta(
        const SyncMetaCompanion(fullPullRequired: Value(true)),
      );
      h.tick();
      await UpdateHabit(h.habits, h.clock)(
        'hab1',
        HabitInput(
          name: 'Berhenti begadang!',
          kind: HabitKind.quit,
          why: 'Tidur cukup',
          startDate: DateTime(2026, 7, 1),
        ),
      );
      await h.engine.syncNow();

      final pushed = h.server.pushed
          .where((m) => m.entity == SyncEntity.habits)
          .single;
      expect(
        pushed.data!.containsKey('tools'),
        isFalse,
        reason: 'absent = unchanged on the server',
      );
      expect(
        h.server.rows[SyncEntity.habits]!['hab1']!['name'],
        'Berhenti begadang!',
      );
      expect(h.server.rows[SyncEntity.habits]!['hab1']!['tools'], tools);
      // The pull then refreshed the local row with the server's data...
      final habit = (await h.habits.getById('hab1'))!;
      expect(habit.tools.single.title, 'Minum air');
      expect((await h.db.getMeta()).enrichmentSeen, isTrue);

      // ...from now on edits carry the full value.
      h.tick();
      await UpdateHabit(h.habits, h.clock)(
        'hab1',
        HabitInput(
          name: 'Berhenti begadang',
          kind: HabitKind.quit,
          why: 'Tidur cukup',
          startDate: DateTime(2026, 7, 1),
        ),
      );
      await h.engine.syncNow();
      final again = h.server.pushed
          .where((m) => m.entity == SyncEntity.habits)
          .last;
      expect(
        again.data!['tools'],
        tools,
        reason: 'unchanged tools survive an edit',
      );
      expect(h.server.rows[SyncEntity.habits]!['hab1']!['tools'], tools);
    });

    test(
      'food: an edit keeps the free-text meal, the calorie range and the tags',
      () async {
        h.server.web(SyncEntity.food, 'f1', {
          'date': '2026-09-20T05:00:00.000Z',
          'name': 'Nasi campur',
          'meal': 'makan malam',
          'calories': 700,
          'caloriesMax': 900,
          'tags': ['pedas', 'warung'],
          'photoUrl': null,
          'note': null,
        });
        await h.engine.syncNow();
        var f = (await h.food.getById('f1'))!;
        expect(f.meal, isNull);
        expect(f.mealLabel, 'makan malam');
        expect(f.caloriesMax, 900);
        expect(f.tags, ['pedas', 'warung']);

        h.tick();
        // The existing form only knows the canonical meals and calories.
        final r = await UpdateFoodLog(h.food, h.clock)(
          'f1',
          FoodInput(
            date: f.date,
            name: 'Nasi campur enak',
            calories: 700,
            note: 'ok',
          ),
        );
        expect(r.isOk, isTrue);
        await h.engine.syncNow();
        var row = h.server.rows[SyncEntity.food]!['f1']!;
        expect(row['meal'], 'makan malam');
        expect(row['caloriesMax'], 900);
        expect(row['tags'], ['pedas', 'warung']);
        expect(row['name'], 'Nasi campur enak');

        // Lowering the calories below the max is fine; raising above drops it
        // (kept ranges that no longer fit are dropped like the server does).
        h.tick();
        await UpdateFoodLog(h.food, h.clock)(
          'f1',
          FoodInput(date: f.date, name: 'Nasi campur enak', calories: 1000),
        );
        await h.engine.syncNow();
        row = h.server.rows[SyncEntity.food]!['f1']!;
        expect(row['caloriesMax'], isNull);
        f = (await h.food.getById('f1'))!;
        expect(f.caloriesMax, isNull);

        // An explicit range and tags are validated and sent.
        h.tick();
        final bad = await UpdateFoodLog(h.food, h.clock)(
          'f1',
          FoodInput(date: f.date, name: 'x', calories: 500, caloriesMax: 400),
        );
        expect(bad.failureOrNull, isA<ValidationFailure>());
        h.tick();
        await UpdateFoodLog(h.food, h.clock)(
          'f1',
          FoodInput(
            date: f.date,
            name: 'Nasi campur enak',
            mealLabel: 'brunch',
            calories: 500,
            caloriesMax: 650,
            tags: [' manis ', 'Manis', 'ringan'],
          ),
        );
        await h.engine.syncNow();
        row = h.server.rows[SyncEntity.food]!['f1']!;
        expect(
          [row['meal'], row['calories'], row['caloriesMax']],
          ['brunch', 500, 650],
        );
        expect(row['tags'], ['manis', 'ringan']);
      },
    );

    test(
      'a v7-era server (no enrichment keys) still syncs habits and food',
      () async {
        h.server.preEnrichment = true;
        h.tick();
        final habit = (await h.createHabit(
          HabitInput(name: 'Minum air', startDate: DateTime(2026, 9, 1)),
        )).valueOrThrow;
        await h.createFood(
          FoodInput(date: h.clock.now(), name: 'Soto', calories: 400),
        );
        await h.engine.syncNow();
        expect(h.server.rejected, isEmpty);
        expect(h.server.rows[SyncEntity.habits]![habit.id], isNotNull);
        final pushed = h.server.pushed.map((m) => m.data).whereType<Json>();
        expect(
          pushed.any((d) => d.containsKey('tools') || d.containsKey('tags')),
          isFalse,
        );
        expect((await h.db.getMeta()).enrichmentSeen, isFalse);
      },
    );

    test(
      'habit log extra / event round trip incl. a tombstoned event',
      () async {
        h.tick();
        final habit = (await h.createHabit(
          HabitInput(name: 'Minum air', startDate: DateTime(2026, 9, 1)),
        )).valueOrThrow;
        final t = h.clock.now();
        await habitFields.save(
          HabitFieldDef(
            id: 'hf1',
            key: 'mood',
            label: 'Mood',
            type: HabitFieldType.select,
            options: const ['tenang', 'capek'],
            appliesTo: const ['done', 'journal'],
            createdAt: t,
            updatedAt: t,
          ),
        );
        await habitEvents.save(
          HabitEvent(
            id: 'ev1',
            habitId: habit.id,
            date: '2026-09-02',
            kind: HabitEventKind.journal,
            label: 'Hari baik',
            note: 'Lancar',
            at: DateTime.utc(2026, 9, 2, 3),
            extra: const {'mood': 'tenang'},
            createdAt: t,
            updatedAt: t,
          ),
        );
        await h.engine.syncNow();
        var row = h.server.rows[SyncEntity.habitEvents]!['ev1']!;
        expect(row['at'], '2026-09-02T03:00:00.000Z');
        expect(row['extra'], {'mood': 'tenang'});
        expect(h.server.rows[SyncEntity.habitFields]!['hf1']!['options'], [
          'tenang',
          'capek',
        ]);
        expect(h.server.rows[SyncEntity.habitFields]!['hf1']!['appliesTo'], [
          'done',
          'journal',
        ]);

        h.tick();
        await habitEvents.delete('ev1');
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.habitEvents]!['ev1'], isNull);
        expect(
          h.server.tombstones.any(
            (x) => x.entity == SyncEntity.habitEvents && x.id == 'ev1',
          ),
          isTrue,
        );
        expect(await habitEvents.getById('ev1'), isNull);
      },
    );
  });
}

extension on PersonInput {
  PersonInput withTags(List<String> t) => PersonInput(
    name: name,
    fullName: fullName,
    category: category,
    relation: relation,
    vibe: vibe,
    status: status,
    howMet: howMet,
    summary: summary,
    birthYear: birthYear,
    birthMonth: birthMonth,
    birthDay: birthDay,
    phone: phone,
    instagram: instagram,
    email: email,
    address: address,
    organization: organization,
    dataStatus: dataStatus,
    sensitive: sensitive,
    tags: t,
    fields: fields,
  );
}
