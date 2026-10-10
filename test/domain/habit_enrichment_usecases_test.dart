// Habit enrichment use cases over in-memory repositories: tools, events,
// dimensions, extra on logs, relapse extras and the online-only notes. Invented
// data only ("Berhenti begadang").
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../presentation/features/tasks/_tasks_harness.dart'
    show FakeSyncService;
import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 10);
  late FixedClock clock;
  late FakeHabitRepository habits;
  late FakeHabitLogRepository logs;
  late FakeHabitFieldRepository fields;
  late FakeHabitEventRepository events;
  late FakeHabitOnline online;
  late Habit quit;

  setUp(() {
    clock = FixedClock(now);
    habits = FakeHabitRepository();
    logs = FakeHabitLogRepository();
    fields = FakeHabitFieldRepository();
    events = FakeHabitEventRepository();
    online = FakeHabitOnline();
    quit = Habit(
      id: 'h1',
      name: 'Berhenti begadang',
      kind: HabitKind.quit,
      startDate: '2026-09-01',
      createdAt: now,
      updatedAt: now,
    );
    habits.s.put(quit);
  });

  Future<HabitFieldDef> makeField(
    String label,
    HabitFieldType type, {
    String? habitId,
    List<String>? options,
    List<String>? appliesTo,
    int? min,
    int? max,
  }) async => (await CreateHabitField(fields, habits, clock)(
    HabitFieldInput(
      label: label,
      type: type,
      habitId: habitId,
      options: options,
      appliesTo: appliesTo,
      min: min,
      max: max,
    ),
  )).valueOrThrow;

  group('tools', () {
    test('saved whole and validated', () async {
      final set = SetHabitTools(habits, clock);
      clock.advance(const Duration(minutes: 5));
      final r = await set('h1', const [
        HabitTool(title: ' Minum air ', kind: HabitToolKind.physical),
      ]);
      final h = r.valueOrThrow;
      expect(h.tools.single.title, 'Minum air');
      expect(h.updatedAt, clock.now());
      expect((await habits.getById('h1'))!.tools, h.tools);
      expect(
        (await set('h1', const [HabitTool(title: '')])).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await set('nope', const [])).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });

    test('editing the habit keeps the tools', () async {
      await SetHabitTools(habits, clock)('h1', const [
        HabitTool(title: 'Jalan'),
      ]);
      await UpdateHabit(habits, clock)(
        'h1',
        const HabitInput(name: 'Berhenti begadang', kind: HabitKind.quit),
      );
      expect((await habits.getById('h1'))!.tools.single.title, 'Jalan');
    });
  });

  group('dimensions', () {
    test('key is a unique slug of the label; order appends', () async {
      final a = await makeField('Tingkat stres', HabitFieldType.scale);
      final b = await makeField('Tingkat stres', HabitFieldType.number);
      expect(a.key, 'tingkat_stres');
      expect(b.key, 'tingkat_stres_2');
      expect(a.min, 1);
      expect(a.max, 10);
      expect(b.min, isNull);
      expect(b.sortOrder, a.sortOrder + 1);
    });

    test(
      'select needs options; scale needs min < max; appliesTo is checked',
      () async {
        final create = CreateHabitField(fields, habits, clock);
        Future<Failure?> fail(HabitFieldInput i) async =>
            (await create(i)).failureOrNull;
        expect(
          await fail(
            const HabitFieldInput(label: 'S', type: HabitFieldType.select),
          ),
          isA<ValidationFailure>(),
        );
        expect(
          await fail(
            const HabitFieldInput(
              label: 'S',
              type: HabitFieldType.scale,
              min: 5,
              max: 5,
            ),
          ),
          isA<ValidationFailure>(),
        );
        expect(
          await fail(const HabitFieldInput(label: 'S', appliesTo: ['bogus'])),
          isA<ValidationFailure>(),
        );
        expect(
          await fail(const HabitFieldInput(label: ' ')),
          isA<ValidationFailure>(),
        );
        expect(
          await fail(const HabitFieldInput(label: 'S', habitId: 'ghost')),
          isA<NotFoundFailure>(),
        );
        final ok = await makeField(
          'Suasana',
          HabitFieldType.select,
          options: [' capek ', 'tenang', 'capek', ''],
          appliesTo: ['urge', 'relapse'],
        );
        expect(ok.options, ['capek', 'tenang']);
        expect(ok.appliesTo, ['relapse', 'urge']);
      },
    );

    test('rename and scope change keep key, type and options', () async {
      final d = await makeField(
        'Suasana',
        HabitFieldType.select,
        options: ['a'],
      );
      final r = (await UpdateHabitField(fields, clock)(
        d.id,
        label: 'Perasaan',
        appliesTo: const ['done'],
      )).valueOrThrow;
      expect(r.label, 'Perasaan');
      expect(r.appliesTo, ['done']);
      expect(r.key, 'suasana');
      expect(r.type, HabitFieldType.select);
      final cleared = (await UpdateHabitField(fields, clock)(
        d.id,
        clearAppliesTo: true,
      )).valueOrThrow;
      expect(cleared.appliesTo, isNull);
    });

    test('reorder writes the new sortOrder', () async {
      final a = await makeField('A', HabitFieldType.text);
      final b = await makeField('B', HabitFieldType.text);
      await ReorderHabitFields(fields, FakeUnitOfWork(), clock)([b.id, a.id]);
      expect((await fields.getAll()).map((d) => d.key), ['b', 'a']);
    });

    test('usage count and delete', () async {
      final d = await makeField('Stres', HabitFieldType.number);
      logs.s.put(
        HabitLog(
          id: 'l1',
          habitId: 'h1',
          date: '2026-10-09',
          type: HabitLogType.relapse,
          extra: const {'stres': 3},
          createdAt: now,
          updatedAt: now,
        ),
      );
      events.s.put(
        HabitEvent(
          id: 'e1',
          habitId: 'h1',
          date: '2026-10-09',
          kind: HabitEventKind.event,
          label: 'x',
          extra: const {'stres': 3},
          createdAt: now,
          updatedAt: now,
        ),
      );
      final u = (await CountHabitFieldUsage(fields, logs, events)(
        d.id,
      )).valueOrThrow;
      expect((u.logs, u.events), (1, 1));
      expect((await DeleteHabitField(fields)(d.id)).isOk, isTrue);
      expect(await fields.getAll(), isEmpty);
      expect(
        (await DeleteHabitField(fields)(d.id)).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });
  });

  group('events', () {
    test('create, edit and delete; extra follows the kind', () async {
      await makeField('Stres', HabitFieldType.scale, appliesTo: ['event']);
      final save = SaveHabitEvent(events, habits, fields, clock);
      final created = (await save(
        HabitEventInput(
          habitId: 'h1',
          date: DateTime(2026, 10, 9, 23),
          label: ' Lembur proyek contoh ',
          note: 'Bukan kambuh',
          extra: const {'stres': 6},
        ),
      )).valueOrThrow;
      expect(created.label, 'Lembur proyek contoh');
      expect(created.date, '2026-10-09');
      expect(created.extra, {'stres': 6});

      clock.advance(const Duration(hours: 1));
      final edited = (await save(
        HabitEventInput(
          id: created.id,
          habitId: 'h1',
          date: DateTime(2026, 10, 8),
          kind: HabitEventKind.milestone,
          label: 'Seminggu bersih',
        ),
      )).valueOrThrow;
      expect(edited.id, created.id);
      expect(edited.createdAt, created.createdAt);
      expect(edited.updatedAt, clock.now());
      expect(edited.extra, isEmpty);
      expect(events.s.items, hasLength(1));

      // The scale only applies to `event`, so a milestone refuses it.
      final bad = await save(
        HabitEventInput(
          habitId: 'h1',
          date: now,
          kind: HabitEventKind.milestone,
          label: 'x',
          extra: const {'stres': 6},
        ),
      );
      expect(bad.failureOrNull, isA<ValidationFailure>());

      expect((await DeleteHabitEvent(events)(created.id)).isOk, isTrue);
      expect(events.s.items, isEmpty);
      expect(
        (await DeleteHabitEvent(events)('zzz')).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });

    test(
      'a real date and a label are required; events never touch logs',
      () async {
        final save = SaveHabitEvent(events, habits, fields, clock);
        expect(
          (await save(
            HabitEventInput(habitId: 'h1', date: now, label: ''),
          )).failureOrNull,
          isA<ValidationFailure>(),
        );
        await save(HabitEventInput(habitId: 'h1', date: now, label: 'Ok'));
        expect(logs.s.items, isEmpty);
        expect(
          (await save(
            HabitEventInput(habitId: 'ghost', date: now, label: 'Ok'),
          )).failureOrNull,
          isA<NotFoundFailure>(),
        );
      },
    );
  });

  group('extra on logs', () {
    test(
      'a relapse carries validated extra and merges into the day row',
      () async {
        await makeField('Tingkat stres', HabitFieldType.scale);
        await makeField(
          'Suasana',
          HabitFieldType.select,
          options: ['capek', 'tenang'],
        );
        final relapse = LogRelapse(habits, logs, clock, fields);
        final first = (await relapse(
          'h1',
          const RelapseInput(extra: {'tingkat_stres': 7}),
        )).valueOrThrow.log;
        expect(first.extra, {'tingkat_stres': 7});
        final second = (await relapse(
          'h1',
          const RelapseInput(extra: {'suasana': 'capek'}),
        )).valueOrThrow.log;
        expect(second.extra, {'tingkat_stres': 7, 'suasana': 'capek'});
        expect(second.amount, 2);
        expect(logs.s.items, hasLength(1));
      },
    );

    test('a bad extra refuses the relapse and writes nothing', () async {
      await makeField('Tingkat stres', HabitFieldType.scale);
      final relapse = LogRelapse(habits, logs, clock, fields);
      for (final extra in <Map<String, Object?>>[
        {'tingkat_stres': 99},
        {'hantu': 1},
      ]) {
        final r = await relapse('h1', RelapseInput(extra: extra));
        expect(r.failureOrNull, isA<ValidationFailure>());
      }
      expect(logs.s.items, isEmpty);
      // Without the field repository a non-empty extra is refused too.
      expect(
        (await LogRelapse(habits, logs, clock)(
          'h1',
          const RelapseInput(extra: {'tingkat_stres': 3}),
        )).failureOrNull,
        isA<ValidationFailure>(),
      );
      // No extra needs no field repository (old call sites keep working).
      expect((await LogRelapse(habits, logs, clock)('h1')).isOk, isTrue);
    });

    test('converting an urge with a bad extra keeps the urge', () async {
      await makeField('Tingkat stres', HabitFieldType.scale);
      await LogUrge(habits, logs, clock)('h1');
      final r = await ConvertUrgeToRelapse(
        habits,
        logs,
        FakeUnitOfWork(),
        clock,
        fields,
      )('h1', const RelapseInput(extra: {'tingkat_stres': 0}));
      expect(r.failureOrNull, isA<ValidationFailure>());
      final urge = await logs.findByKey('h1', '2026-10-10', HabitLogType.urge);
      expect(urge!.amount, 1);
      expect(
        await logs.findByKey('h1', '2026-10-10', HabitLogType.relapse),
        isNull,
      );
    });

    test('details on the urge row: set, change and clear a key', () async {
      await makeField('Tingkat stres', HabitFieldType.scale);
      await makeField('Catatan', HabitFieldType.text);
      await LogUrge(habits, logs, clock)('h1');
      final setExtra = SetHabitLogExtra(habits, logs, fields, clock);
      final day = DateTime(2026, 10, 10);
      var row = (await setExtra('h1', day, HabitLogType.urge, {
        'tingkat_stres': 8,
        'catatan': 'scroll malam',
      })).valueOrThrow;
      expect(row.extra, {'tingkat_stres': 8, 'catatan': 'scroll malam'});
      expect(row.amount, 1, reason: 'the count is untouched');
      row = (await setExtra('h1', day, HabitLogType.urge, {
        'tingkat_stres': 5,
        'catatan': null,
      })).valueOrThrow;
      expect(row.extra, {'tingkat_stres': 5});
      expect(
        (await setExtra('h1', day, HabitLogType.urge, {
          'tingkat_stres': 40,
        })).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await setExtra('h1', day, HabitLogType.relapse, {
          'tingkat_stres': 3,
        })).failureOrNull,
        isA<ValidationFailure>(),
        reason: 'no relapse row that day to attach to',
      );
    });

    test('check-in details only for dimensions that list done', () async {
      await makeField('Stres', HabitFieldType.number); // default scopes
      await makeField(
        'Tidur nyenyak',
        HabitFieldType.boolean,
        appliesTo: ['done'],
      );
      await ConfirmCleanDay(habits, logs, clock)('h1');
      final setExtra = SetHabitLogExtra(habits, logs, fields, clock);
      final day = DateTime(2026, 10, 10);
      expect(
        (await setExtra('h1', day, HabitLogType.done, {
          'stres': 3,
        })).failureOrNull,
        isA<ValidationFailure>(),
      );
      final ok = (await setExtra('h1', day, HabitLogType.done, {
        'tidur_nyenyak': true,
      })).valueOrThrow;
      expect(ok.extra, {'tidur_nyenyak': true});
      expect(ok.type, HabitLogType.done);
      expect(ok.value, 1);
    });
  });

  group('notes (online-only)', () {
    late FakeSyncService sync;
    setUp(() => sync = FakeSyncService());

    test(
      'replace sends expectedUpdatedAt and re-stamps a queued edit',
      () async {
        final get = GetHabitNotes(online);
        final replace = ReplaceHabitNotes(online, habits, sync);
        final read = (await get('h1')).valueOrThrow;
        expect(read.notes, '');
        final w = (await replace(
          'h1',
          '# Pemicu\nscroll malam',
          expectedUpdatedAt: read.updatedAt,
        )).valueOrThrow;
        expect(w.notesLength, 21);
        expect(habits.refreshed, ['h1']);
        // The notes never enter the habit row.
        expect((await habits.getById('h1'))!.hasNotes, isFalse);

        final stale = await replace(
          'h1',
          'x',
          expectedUpdatedAt: read.updatedAt,
        );
        expect(stale.failureOrNull, isA<ConflictFailure>());
        expect(habits.refreshed, [
          'h1',
        ], reason: 'a refused write re-stamps nothing');
      },
    );

    test('append adds under a heading; empty text is refused', () async {
      final append = AppendHabitNotes(online, habits, sync);
      expect(
        (await append('h1', '  ')).failureOrNull,
        isA<ValidationFailure>(),
      );
      await append('h1', 'Pertama');
      await append('h1', 'Kedua', heading: '2026-10-10');
      expect(online.notes['h1'], 'Pertama\n\n## 2026-10-10\nKedua');
    });

    test(
      'over the cap is refused before any request; offline passes through',
      () async {
        final replace = ReplaceHabitNotes(online, habits, sync);
        final r = await replace('h1', 'a' * (habitNotesMarkdownMax + 1));
        expect(r.failureOrNull, isA<ValidationFailure>());
        expect(online.noteGets, 0);
        online.failWith = const NetworkFailure('offline');
        expect(
          (await GetHabitNotes(online)('h1')).failureOrNull,
          isA<NetworkFailure>(),
        );
      },
    );
  });

  group('analysis', () {
    test('asks for the window and surfaces offline', () async {
      final fetch = FetchHabitAnalysis(online, clock);
      expect((await fetch('h1', days: 30)).isOk, isTrue);
      expect(online.analysisGets, 1);
      expect(
        (await fetch('h1', days: 0)).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(online.analysisGets, 1);
      online.failWith = const NetworkFailure('offline');
      expect((await fetch('h1')).failureOrNull, isA<NetworkFailure>());
    });
  });
}
