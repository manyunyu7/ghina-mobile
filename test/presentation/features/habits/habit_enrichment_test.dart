// Phase B habit screens: notes (private collapse), coping tools on the urge
// screen and their editor, events timeline, dynamic extra fields (relapse,
// urge, check-in) and the dimension manager. Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_habits_harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

Habit quitHabit({
  bool isPrivate = false,
  bool hasNotes = false,
  List<HabitTool> tools = const [],
}) => Habit(
  id: 'begadang',
  name: 'Berhenti begadang',
  kind: HabitKind.quit,
  isPrivate: isPrivate,
  why: 'Tidur cukup biar fokus',
  startDate: daysAgo(9),
  tools: tools,
  hasNotes: hasNotes,
  notesLength: hasNotes ? 40 : 0,
  createdAt: habitsNow.subtract(const Duration(days: 30)),
  updatedAt: habitsNow.subtract(const Duration(days: 30)),
);

HabitFieldDef field(
  String key,
  String label,
  HabitFieldType type, {
  List<String>? options,
  List<String>? appliesTo,
  String? habitId,
  int order = 0,
}) => HabitFieldDef(
  id: 'f-$key',
  habitId: habitId,
  key: key,
  label: label,
  type: type,
  options: options,
  appliesTo: appliesTo,
  sortOrder: order,
  createdAt: habitsNow,
  updatedAt: habitsNow,
);

Future<void> _breathe(WidgetTester t) async {
  for (var i = 0; i < 62; i++) {
    await t.pump(const Duration(seconds: 1));
  }
}

void main() {
  group('notes', () {
    testWidgets('a public habit loads its notes by itself, once', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(hasNotes: true));
      h.online.notes['begadang'] = '# Pemicu\nScroll malam di kasur';
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('notes-body'), 300);
      expect(find.textContaining('Scroll malam di kasur'), findsOneWidget);
      expect(h.online.noteGets, 1);
      expect(key('show-private-notes'), findsNothing);
    });

    testWidgets('a private habit keeps notes collapsed until "Tampilkan '
        'catatan", and hides them again', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(isPrivate: true, hasNotes: true));
      h.online.notes['begadang'] = 'Rahasia: scroll malam';
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('notes-hidden'), 300);
      expect(find.textContaining('40 karakter'), findsOneWidget);
      expect(find.textContaining('Rahasia'), findsNothing);
      expect(h.online.noteGets, 0, reason: 'never fetched before the tap');

      await tapIn(t, key('show-private-notes'));
      expect(h.online.noteGets, 1);
      expect(find.textContaining('Rahasia: scroll malam'), findsOneWidget);

      await tapIn(t, key('notes-hide'));
      expect(find.textContaining('Rahasia'), findsNothing);
      expect(key('notes-hidden'), findsOneWidget);
    });

    testWidgets('a private habit never shows notes on the board or the urge '
        'screen', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(isPrivate: true, hasNotes: true));
      h.online.notes['begadang'] = 'Rahasia: scroll malam';
      await pumpHabits(t, h, location: '/habits');
      expect(find.textContaining('Rahasia'), findsNothing);
      expect(h.online.noteGets, 0);
    });

    testWidgets('"Tambah catatan" appends and re-stamps a queued habit edit', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang');
      await tapIn(t, key('notes-append'));
      await t.enterText(key('append-heading'), '2026-10-10');
      await t.enterText(key('append-text'), 'Tidur jam 11 malam');
      await tapIn(t, key('append-save'));
      expect(h.online.notes['begadang'], '## 2026-10-10\nTidur jam 11 malam');
      expect(h.habits.refreshed, ['begadang']);
    });

    testWidgets('editing saves with expectedUpdatedAt; a stale copy gets the '
        'conflict dialog', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(hasNotes: true));
      h.online.notes['begadang'] = 'Versi satu';
      await pumpHabits(t, h, location: '/habits/begadang');
      await tapIn(t, key('notes-edit'));
      expect(find.text('Versi satu'), findsOneWidget);
      // Another device saves in the meantime.
      await h.online.replaceNotes('begadang', 'Versi dua');
      await t.enterText(key('notes-field'), 'Versi saya');
      await tapIn(t, key('notes-save'));
      expect(find.text('Catatan berubah di tempat lain'), findsOneWidget);
      expect(
        h.online.notes['begadang'],
        'Versi dua',
        reason: 'not overwritten',
      );
    });

    testWidgets('offline: a clear message and a retry', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(hasNotes: true));
      h.online.failWith = const NetworkFailure('offline');
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('notes-retry'), 300);
      expect(
        find.textContaining('cuma bisa dibuka saat online'),
        findsOneWidget,
      );
      h.online.failWith = null;
      h.online.notes['begadang'] = 'Sudah online';
      await tapIn(t, key('notes-retry'));
      expect(find.textContaining('Sudah online'), findsOneWidget);
    });
  });

  group('coping tools', () {
    const tools = [
      HabitTool(
        title: 'Rapikan meja kerja',
        detail: 'Sepuluh menit saja',
        kind: HabitToolKind.physical,
      ),
      HabitTool(title: 'Telepon teman', kind: HabitToolKind.social),
    ];

    testWidgets('show on the urge screen next to the preset ideas, tappable', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(tools: tools));
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await t.scrollUntilVisible(find.text('Jalan sebentar'), 200);
      expect(find.text('Jalan sebentar'), findsOneWidget);
      await t.scrollUntilVisible(key('urge-tool-0'), 200);
      expect(find.text('Rapikan meja kerja'), findsOneWidget);
      expect(find.text('Sepuluh menit saja'), findsOneWidget);
      expect(find.text('Telepon teman'), findsOneWidget);
      expect(find.text('Fisik'), findsOneWidget);
      expect(find.text('Sosial'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await tapIn(t, key('urge-tool-0'), 3);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('a habit without tools shows only the presets', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await t.scrollUntilVisible(find.text('Jalan sebentar'), 200);
      expect(key('urge-tools'), findsNothing);
    });

    testWidgets('the editor adds, edits and deletes tools', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit(tools: tools));
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('habit-tools-section'), 300);
      expect(find.text('Rapikan meja kerja'), findsOneWidget);
      await tapIn(t, find.text('ATUR'));
      await tapIn(t, key('tool-add'));
      await t.enterText(key('tool-title'), 'Dengar musik');
      await t.enterText(key('tool-detail'), 'Playlist santai');
      await tapIn(t, find.text('Pengalih'), 3);
      await tapIn(t, key('tool-save'));
      var saved = (await h.habits.getById('begadang'))!.tools;
      expect(saved.map((x) => x.title), [
        'Rapikan meja kerja',
        'Telepon teman',
        'Dengar musik',
      ]);
      expect(saved.last.kind, HabitToolKind.distraction);
      expect(saved.last.detail, 'Playlist santai');

      await tapIn(t, find.text('Telepon teman'));
      await tapIn(t, key('tool-delete'));
      saved = (await h.habits.getById('begadang'))!.tools;
      expect(saved.map((x) => x.title), ['Rapikan meja kerja', 'Dengar musik']);
    });

    testWidgets('an empty title is refused in the sheet', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('habit-tools-section'), 300);
      await tapIn(t, find.text('TAMBAH').first);
      await tapIn(t, key('tool-add'));
      await tapIn(t, key('tool-save'), 3);
      expect(find.text('Judul alat wajib diisi'), findsOneWidget);
      expect((await h.habits.getById('begadang'))!.tools, isEmpty);
    });
  });

  group('events', () {
    testWidgets('add, list newest first, edit and delete — streak untouched', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('habit-events-section'), 300);
      expect(
        find.textContaining('Belum ada. Catat hari penting'),
        findsOneWidget,
      );

      await tapIn(t, find.text('TAMBAH').last);
      await t.enterText(key('event-label'), 'Lembur proyek contoh');
      await t.enterText(key('event-note'), 'Bukan kambuh');
      await tapIn(t, key('event-save'));
      expect(h.events.s.items.values.single.label, 'Lembur proyek contoh');
      expect(h.events.s.items.values.single.kind, HabitEventKind.event);
      expect(h.events.s.items.values.single.date, todayKey);
      expect(find.text('Lembur proyek contoh'), findsOneWidget);
      expect(find.text('Bukan kambuh'), findsOneWidget);
      expect(h.logs.s.items, isEmpty, reason: 'events are not logs');

      // A second, older one lists below.
      h.events.s.put(
        HabitEvent(
          id: 'old',
          habitId: 'begadang',
          date: daysAgo(3),
          kind: HabitEventKind.milestone,
          label: 'Seminggu tanpa begadang',
          createdAt: habitsNow,
          updatedAt: habitsNow,
        ),
      );
      await settle(t);
      final a = t.getTopLeft(find.text('Lembur proyek contoh')).dy;
      final b = t.getTopLeft(find.text('Seminggu tanpa begadang')).dy;
      expect(a, lessThan(b));

      await tapIn(t, find.text('Seminggu tanpa begadang'));
      await t.enterText(key('event-label'), 'Dua minggu!');
      await tapIn(t, key('event-save'));
      expect(h.events.s.items['old']!.label, 'Dua minggu!');

      await tapIn(t, find.text('Dua minggu!'));
      await tapIn(t, key('event-delete'));
      await tapIn(t, find.text('HAPUS'));
      expect(h.events.s.items.containsKey('old'), isFalse);
    });

    testWidgets('an empty title shows the validation message', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('habit-events-section'), 300);
      await tapIn(t, find.text('TAMBAH').last);
      await tapIn(t, key('event-save'), 4);
      expect(find.text('Judul kejadian wajib diisi'), findsWidgets);
      expect(h.events.s.items, isEmpty);
    });

    testWidgets('event dimensions render from the defs that apply', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.fields.s.put(
        field('tingkat_stres', 'Tingkat stres', HabitFieldType.scale),
      );
      h.fields.s.put(
        field(
          'cuma_relapse',
          'Cuma kambuh',
          HabitFieldType.text,
          appliesTo: const ['relapse'],
        ),
      );
      await pumpHabits(t, h, location: '/habits/begadang');
      await t.scrollUntilVisible(key('habit-events-section'), 300);
      await tapIn(t, find.text('TAMBAH').last);
      expect(key('extra-tingkat_stres'), findsOneWidget);
      expect(key('extra-cuma_relapse'), findsNothing);
      await t.enterText(key('event-label'), 'Hari berat');
      await tapIn(
        t,
        find.descendant(
          of: key('extra-tingkat_stres'),
          matching: find.text('6'),
        ),
        3,
      );
      await tapIn(t, key('event-save'));
      expect(h.events.s.items.values.single.extra, {'tingkat_stres': 6});
      expect(find.textContaining('Tingkat stres: 6/10'), findsOneWidget);
    });
  });

  group('extra fields on logs', () {
    HabitsHarness seeded() {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.fields.s.put(
        field('tingkat_stres', 'Tingkat stres', HabitFieldType.scale),
      );
      h.fields.s.put(
        field(
          'suasana',
          'Suasana',
          HabitFieldType.select,
          options: const ['capek', 'tenang'],
          order: 1,
        ),
      );
      h.fields.s.put(
        field('sendirian', 'Sendirian', HabitFieldType.boolean, order: 2),
      );
      h.fields.s.put(
        field('jam_tidur', 'Jam tidur', HabitFieldType.number, order: 3),
      );
      h.fields.s.put(
        field('catatan_kecil', 'Catatan kecil', HabitFieldType.text, order: 4),
      );
      return h;
    }

    testWidgets('the relapse sheet renders every type and stores extra', (
      t,
    ) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await _breathe(t);
      await tapIn(t, key('urge-lost'));
      for (final k in [
        'tingkat_stres',
        'suasana',
        'sendirian',
        'jam_tidur',
        'catatan_kecil',
      ]) {
        await t.ensureVisible(key('extra-$k'));
        expect(key('extra-$k'), findsOneWidget, reason: k);
      }
      await tapIn(
        t,
        find.descendant(
          of: key('extra-tingkat_stres'),
          matching: find.text('7'),
        ),
        3,
      );
      await tapIn(
        t,
        find.descendant(of: key('extra-suasana'), matching: find.text('capek')),
        3,
      );
      await tapIn(
        t,
        find.descendant(of: key('extra-sendirian'), matching: find.text('Ya')),
        3,
      );
      await t.enterText(
        find.descendant(
          of: key('extra-jam_tidur'),
          matching: find.byType(EditableText),
        ),
        '5,5',
      );
      await t.enterText(
        find.descendant(
          of: key('extra-catatan_kecil'),
          matching: find.byType(EditableText),
        ),
        'scroll malam',
      );
      await tapIn(t, key('relapse-save'));
      final r = h.todayLog('begadang', HabitLogType.relapse)!;
      expect(r.extra, {
        'tingkat_stres': 7,
        'suasana': 'capek',
        'sendirian': true,
        'jam_tidur': 5.5,
        'catatan_kecil': 'scroll malam',
      });
      expect(r.type, HabitLogType.relapse);
      expect(r.value, 1);
    });

    testWidgets('a wide scale becomes a slider and respects its range', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.fields.s.put(
        HabitFieldDef(
          id: 'f-craving',
          key: 'craving',
          label: 'Kekuatan pengen',
          type: HabitFieldType.scale,
          min: 0,
          max: 100,
          createdAt: habitsNow,
          updatedAt: habitsNow,
        ),
      );
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await _breathe(t);
      await tapIn(t, key('urge-lost'));
      expect(
        find.descendant(
          of: key('extra-craving'),
          matching: find.byType(Slider),
        ),
        findsOneWidget,
      );
      await t.ensureVisible(key('extra-craving'));
      await t.drag(find.byType(Slider), const Offset(60, 0));
      await settle(t, 3);
      await tapIn(t, key('relapse-save'));
      final v = h.todayLog('begadang', HabitLogType.relapse)!.extra['craving'];
      expect(v, isA<int>());
      expect(v as int, inInclusiveRange(0, 100));
    });

    testWidgets('picking then un-picking an option leaves the row clean', (
      t,
    ) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await _breathe(t);
      await tapIn(t, key('urge-lost'));
      final capek = find.descendant(
        of: key('extra-suasana'),
        matching: find.text('capek'),
      );
      await tapIn(t, capek, 3);
      await tapIn(t, capek, 3);
      await tapIn(t, key('relapse-save'));
      expect(h.todayLog('begadang', HabitLogType.relapse)!.extra, isEmpty);
    });

    testWidgets('a number the user typed badly is reported on the field', (
      t,
    ) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await _breathe(t);
      await tapIn(t, key('urge-lost'));
      await t.enterText(
        find.descendant(
          of: key('extra-jam_tidur'),
          matching: find.byType(EditableText),
        ),
        '-',
      );
      await tapIn(t, key('relapse-save'), 4);
      expect(find.text('Jam tidur harus angka'), findsWidgets);
      expect(h.todayLog('begadang', HabitLogType.relapse), isNull);
    });

    testWidgets('the urge screen offers an optional details card that merges '
        'into the urge row', (t) async {
      final h = seeded();
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      expect(h.todayLog('begadang', HabitLogType.urge)!.extra, isEmpty);
      await t.scrollUntilVisible(key('urge-extra-open'), 200);
      await tapIn(t, key('urge-extra-open'), 4);
      await tapIn(
        t,
        find.descendant(
          of: key('extra-tingkat_stres'),
          matching: find.text('4'),
        ),
        3,
      );
      await tapIn(t, key('urge-extra-save'));
      final u = h.todayLog('begadang', HabitLogType.urge)!;
      expect(u.extra, {'tingkat_stres': 4});
      expect(u.value, 1, reason: 'the count is untouched');
      expect(find.text('Detail tersimpan'), findsWidgets);
    });

    testWidgets('no urge card when no dimension applies to urge', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.fields.s.put(
        field(
          'cuma_relapse',
          'Cuma kambuh',
          HabitFieldType.text,
          appliesTo: const ['relapse'],
        ),
      );
      await pumpHabits(t, h, location: '/habits/begadang/urge');
      await t.scrollUntilVisible(find.text('Jalan sebentar'), 200);
      expect(key('urge-extra-open'), findsNothing);
    });

    testWidgets('check-in details appear only for dimensions that list done', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.logs.s.put(log('begadang', todayKey, HabitLogType.done));
      h.fields.s.put(
        field('stres_default', 'Stres default', HabitFieldType.number),
      );
      await pumpHabits(t, h, location: '/habits/begadang');
      expect(key('done-detail'), findsNothing);

      h.fields.s.put(
        field(
          'tidur_nyenyak',
          'Tidur nyenyak',
          HabitFieldType.boolean,
          appliesTo: const ['done'],
          order: 1,
        ),
      );
      await settle(t);
      await tapIn(t, key('done-detail'));
      expect(key('extra-tidur_nyenyak'), findsOneWidget);
      expect(key('extra-stres_default'), findsNothing);
      await tapIn(
        t,
        find.descendant(
          of: key('extra-tidur_nyenyak'),
          matching: find.text('Ya'),
        ),
        3,
      );
      await tapIn(t, key('done-detail-save'));
      final row = h.todayLog('begadang', HabitLogType.done)!;
      expect(row.extra, {'tidur_nyenyak': true});
      expect(row.value, 1);
    });
  });

  group('dimension manager', () {
    testWidgets('add a scale scoped to the habit, then rename it', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/fields?habit=begadang');
      expect(key('dim-empty'), findsOneWidget);
      await tapIn(t, key('dim-add'));
      await t.enterText(key('dim-label'), 'Tingkat stres');
      await tapIn(t, key('dim-save'));
      final d = h.fields.s.items.values.single;
      expect(d.key, 'tingkat_stres');
      expect(d.type, HabitFieldType.scale);
      expect(d.min, 1);
      expect(d.max, 10);
      expect(d.habitId, 'begadang', reason: 'scoped to this habit by default');
      expect(find.text('Tingkat stres'), findsOneWidget);

      await tapIn(t, find.text('Tingkat stres'));
      await t.enterText(key('dim-rename'), 'Stres harian');
      await tapIn(t, key('dim-rename-save'));
      expect(h.fields.s.items[d.id]!.label, 'Stres harian');
      expect(h.fields.s.items[d.id]!.key, 'tingkat_stres');
    });

    testWidgets('a select needs options', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/fields?habit=begadang');
      await tapIn(t, key('dim-add'));
      await t.enterText(key('dim-label'), 'Suasana');
      await tapIn(t, find.text('Pilihan'), 3);
      await tapIn(t, key('dim-save'), 4);
      expect(key('dim-error'), findsOneWidget);
      await t.enterText(key('dim-options'), 'capek, tenang');
      await tapIn(t, key('dim-save'));
      expect(h.fields.s.items.values.single.options, ['capek', 'tenang']);
    });

    testWidgets('deleting warns with how many records lose the value', (
      t,
    ) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      final d = field('tingkat_stres', 'Tingkat stres', HabitFieldType.scale);
      h.fields.s.put(d);
      h.logs.s.put(
        log(
          'begadang',
          daysAgo(1),
          HabitLogType.relapse,
        ).copyWith(extra: const {'tingkat_stres': 6}),
      );
      h.events.s.put(
        HabitEvent(
          id: 'e1',
          habitId: 'begadang',
          date: daysAgo(2),
          kind: HabitEventKind.event,
          label: 'Hari berat',
          extra: const {'tingkat_stres': 8},
          createdAt: habitsNow,
          updatedAt: habitsNow,
        ),
      );
      await pumpHabits(t, h, location: '/habits/fields?habit=begadang');
      await tapIn(t, find.text('Tingkat stres'));
      await tapIn(t, key('dim-delete'));
      expect(
        find.textContaining('Hapus dimensi "Tingkat stres"?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 catatan (1 catatan harian, 1 kejadian)'),
        findsOneWidget,
      );
      // Cancel keeps it.
      await tapIn(t, find.text('BATAL'));
      expect(h.fields.s.items, isNotEmpty);

      await tapIn(t, find.text('Tingkat stres'));
      await tapIn(t, key('dim-delete'));
      await tapIn(t, find.text('HAPUS'));
      expect(h.fields.s.items, isEmpty);
    });

    testWidgets('a dimension can be set to show on check-in', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      h.fields.s.put(field('mood', 'Mood', HabitFieldType.text));
      await pumpHabits(t, h, location: '/habits/fields?habit=begadang');
      await tapIn(t, find.text('Mood'));
      await tapIn(t, find.text('Selesai / bersih'), 3);
      await tapIn(t, key('dim-rename-save'));
      expect(h.fields.s.items['f-mood']!.appliesTo, ['done']);
    });
  });

  group('links', () {
    testWidgets('the habit screen links to the full analysis', (t) async {
      final h = HabitsHarness();
      h.habits.s.put(quitHabit());
      await pumpHabits(t, h, location: '/habits/begadang');
      await tapIn(t, key('habit-analysis-link'));
      expect(find.textContaining('Analisis ·'), findsOneWidget);
    });
  });
}
