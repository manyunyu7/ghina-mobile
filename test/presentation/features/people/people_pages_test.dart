// Smoke tests of the People screens (list, detail, form, manage, the calendar
// overlay) on in-memory repositories behind the real use cases / providers.
// All people are invented.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/calendar/pages/calendar_page.dart';
import 'package:ghina/presentation/features/people/pages/people_manage_page.dart';
import 'package:ghina/presentation/features/people/pages/people_page.dart';
import 'package:ghina/presentation/features/people/pages/person_detail_page.dart';
import 'package:ghina/presentation/features/people/pages/person_form_page.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../di/people_test_overrides.dart';
import '../../../domain/people_fakes.dart';

final _now = DateTime(2026, 10, 10, 12);

class _Sync implements SyncService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {}
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

class Rig {
  final people = FakePersonRepository();
  final cats = FakePersonCategoryRepository();
  final defs = FakePersonFieldRepository();
  final dates = FakePersonDateRepository();
  final notes = FakePeopleNotes();
  final visited = <String>[];

  Rig() {
    cats.s
      ..put(fakeCategory('family', 'Keluarga', '👨‍👩‍👧', order: 0))
      ..put(fakeCategory('work', 'Kerja', '💼', order: 1))
      ..put(fakeCategory('other', 'Lainnya', '👤', order: 2));
  }

  List<Override> get overrides => [
    clockProvider.overrideWithValue(FixedClock(_now)),
    tickSourceProvider.overrideWithValue(() => Stream.value(_now)),
    syncServiceProvider.overrideWithValue(_Sync()),
    currentUserProvider.overrideWithValue(null),
    ...peopleFakeOverrides(
      people: people,
      categories: cats,
      fields: defs,
      dates: dates,
      notes: notes,
    ),
  ];

  /// Routes of the feature + stubs that record where a tap went.
  GoRouter router(String location) => GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/people', builder: (_, _) => const PeoplePage()),
      GoRoute(path: '/people/new', builder: (_, _) => const PersonFormPage()),
      GoRoute(
        path: '/people/manage',
        builder: (_, _) => const PeopleManagePage(),
      ),
      GoRoute(
        path: '/people/:id',
        builder: (_, s) => PersonDetailPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/people/:id/edit',
        builder: (_, s) => PersonFormPage(id: s.pathParameters['id']),
      ),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage()),
      GoRoute(
        path: '/calendar/new',
        builder: (_, s) {
          visited.add(s.uri.toString());
          return const Scaffold(body: Text('event-form'));
        },
      ),
    ],
  );

  Future<void> pump(WidgetTester t, String location) async {
    t.view.physicalSize = const Size(1080, 5200);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: ThemeMode.light,
          routerConfig: router(location),
        ),
      ),
    );
    await settle(t);
  }
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text, skipOffstage: false);
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await settle(t);
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key), skipOffstage: false);
  await t.ensureVisible(f);
  await t.pumpAndSettle(const Duration(milliseconds: 50));
  await t.tap(f);
  await settle(t);
}

Future<void> enter(WidgetTester t, String key, String text) async {
  final f = find.byKey(ValueKey(key), skipOffstage: false);
  await t.ensureVisible(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

void _seedList(Rig r) {
  r.defs.s
    ..put(fakeDef('hobi', 'Hobi', PersonFieldType.text))
    ..put(fakeDef('vegan', 'Vegan', PersonFieldType.boolean, order: 1));
  r.people.s
    ..put(
      fakePerson(
        'p1',
        'Siti Sample',
        category: 'family',
        relation: 'Ibu',
        vibe: PersonVibe.positive,
        birthYear: 1972,
        birthMonth: 2,
        birthDay: 29,
        tags: const ['inti'],
        fields: const {'hobi': 'berkebun'},
      ),
    )
    ..put(
      fakePerson(
        'p2',
        'Budi Contoh',
        category: 'work',
        relation: 'Fullstack Dev',
        vibe: PersonVibe.caution,
        birthYear: 1990,
        birthMonth: 10,
        birthDay: 12,
        tags: const ['kantor', 'inti'],
      ),
    )
    ..put(
      fakePerson(
        'p3',
        'Andi Contoh',
        category: 'family',
        vibe: PersonVibe.closed,
        birthMonth: 5,
        summary: 'Adik',
      ),
    );
  r.dates.s.put(
    fakeDate(
      'd1',
      'p2',
      'Hari jadi',
      10,
      20,
      kind: PersonDateKind.anniversary,
      year: 2015,
    ),
  );
}

void main() {
  group('list', () {
    testWidgets('groups by category with counts and emoji, vibe emoji, '
        'collapsible', (t) async {
      final r = Rig();
      _seedList(r);
      await r.pump(t, '/people');

      expect(find.text('Keluarga'), findsOneWidget);
      expect(find.text('Kerja'), findsOneWidget);
      expect(find.text('👨‍👩‍👧'), findsOneWidget);
      expect(find.text('💼'), findsOneWidget);
      // Counts: Keluarga has two people, Kerja one (pill text is uppercase-able
      // digits).
      final family = find.byKey(const ValueKey('group-family'));
      expect(
        find.descendant(of: family, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('Siti Sample'), findsOneWidget);
      expect(find.text('Budi Contoh'), findsWidgets);
      // Vibe emoji per person.
      expect(find.text('💕'), findsOneWidget);
      expect(find.text('⚠️'), findsOneWidget);
      expect(find.text('🚫'), findsOneWidget);

      await t.tap(family);
      await settle(t);
      expect(find.text('Siti Sample'), findsNothing);
      expect(find.text('Andi Contoh'), findsNothing);
      expect(find.text('Budi Contoh'), findsWidgets);
      await t.tap(family);
      await settle(t);
      expect(find.text('Siti Sample'), findsOneWidget);
    });

    testWidgets('upcoming card: birthdays and important dates within 60 days, '
        'the turning age only when the year is known', (t) async {
      final r = Rig();
      _seedList(r);
      await r.pump(t, '/people');

      final card = find.byKey(const ValueKey('upcoming-people'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.text('Ulang tahun & tanggal penting terdekat'),
        ),
        findsOneWidget,
      );
      // Budi: Oct 12 → "2 hari lagi · 36 tahun".
      expect(
        find.descendant(
          of: card,
          matching: find.text('12 Oktober · 2 hari lagi · 36 tahun'),
        ),
        findsOneWidget,
      );
      // His anniversary on Oct 20 (year 2015 → 11).
      expect(
        find.descendant(
          of: card,
          matching: find.text('💍 Hari jadi · Budi Contoh'),
        ),
        findsOneWidget,
      );
      // Siti (Feb 29, no known non-leap year) is 141 days away: outside the
      // 60-day window. Andi only has a month: never listed.
      expect(
        find.descendant(of: card, matching: find.textContaining('Siti')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Andi')),
        findsNothing,
      );
    });

    testWidgets('search (name / relation / summary / tag / field value) and '
        'the tag filter', (t) async {
      final r = Rig();
      _seedList(r);
      await r.pump(t, '/people');

      await enter(t, 'people-search', 'berkebun');
      await settle(t);
      expect(find.text('Siti Sample'), findsOneWidget);
      expect(find.text('Andi Contoh'), findsNothing);
      expect(find.text('Kerja'), findsNothing, reason: 'empty groups vanish');

      await enter(t, 'people-search', 'fullstack');
      await settle(t);
      expect(find.text('Budi Contoh'), findsWidgets);
      expect(find.text('Siti Sample'), findsNothing);

      await enter(t, 'people-search', 'adik');
      await settle(t);
      expect(find.text('Andi Contoh'), findsOneWidget);

      await enter(t, 'people-search', 'zzz');
      await settle(t);
      expect(find.text('Nggak ada yang cocok'), findsOneWidget);

      await enter(t, 'people-search', '');
      await settle(t);
      await tapText(t, '#kantor');
      expect(find.text('Andi Contoh'), findsNothing);
      expect(find.text('Siti Sample'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('group-work')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tapText(t, '#kantor'); // toggle off
      expect(find.text('Siti Sample'), findsOneWidget);
    });

    testWidgets('empty state', (t) async {
      final r = Rig();
      await r.pump(t, '/people');
      expect(find.text('Belum ada orang'), findsOneWidget);
      expect(find.text('TAMBAH ORANG'), findsOneWidget);
    });

    testWidgets('tapping a person opens the detail', (t) async {
      final r = Rig();
      _seedList(r);
      await r.pump(t, '/people');
      await tapText(t, 'Siti Sample');
      expect(find.text('Tanggal penting'), findsOneWidget);
      expect(find.text('29 Februari 1972'), findsOneWidget);
    });
  });

  group('detail', () {
    testWidgets('fields table, custom fields by their definitions, tags and '
        'important dates', (t) async {
      final r = Rig();
      r.defs.s
        ..put(fakeDef('hobi', 'Hobi', PersonFieldType.text))
        ..put(fakeDef('vegan', 'Vegan', PersonFieldType.boolean, order: 1))
        ..put(
          fakeDef(
            'golongan_darah',
            'Gol. darah',
            PersonFieldType.select,
            options: const ['A', 'B', 'AB', 'O'],
            order: 2,
          ),
        )
        ..put(
          fakeDef('lahir_anak', 'Lahir anak', PersonFieldType.date, order: 3),
        )
        ..put(fakeDef('blog', 'Blog', PersonFieldType.url, order: 4))
        ..put(
          fakeDef(
            'ukuran_sepatu',
            'Ukuran sepatu',
            PersonFieldType.number,
            order: 5,
          ),
        )
        ..put(
          fakeDef(
            'khusus_kerja',
            'Khusus kerja',
            PersonFieldType.text,
            appliesTo: const ['work'],
            order: 6,
          ),
        );
      r.people.s.put(
        Person(
          id: 'p1',
          name: 'Siti Sample',
          fullName: 'Siti Sample Contoh',
          category: 'family',
          relation: 'Ibu',
          phone: '081200000001',
          organization: 'Toko Contoh',
          vibe: PersonVibe.positive,
          birthMonth: 2,
          birthDay: 29,
          tags: const ['inti', 'keluarga'],
          fields: const {
            'hobi': 'berkebun',
            'vegan': false,
            'golongan_darah': 'O',
            'lahir_anak': '2024-02-29',
            'blog': 'https://contoh.example/siti',
            'ukuran_sepatu': 38,
            'khusus_kerja': 'tersimpan tapi tak berlaku',
          },
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      r.dates.s.put(
        fakeDate('d1', 'p1', 'Peringatan', 3, 3, kind: PersonDateKind.memorial),
      );
      r.cats.s.put(fakeCategory('family', 'Keluarga', '👨‍👩‍👧'));
      await r.pump(t, '/people/p1');

      // Info table.
      expect(find.text('Siti Sample Contoh'), findsOneWidget);
      expect(find.text('081200000001'), findsOneWidget);
      expect(find.text('Toko Contoh'), findsOneWidget);
      // Custom fields rendered by type.
      final fields = find.byKey(const ValueKey('person-fields'));
      for (final s in [
        'berkebun',
        'Tidak', // boolean
        'O', // select pill
        '29 Februari 2024', // date
        'https://contoh.example/siti',
        '38', // number
      ]) {
        expect(
          find.descendant(of: fields, matching: find.text(s)),
          findsOneWidget,
          reason: s,
        );
      }
      expect(
        find.descendant(of: fields, matching: find.text('Hobi')),
        findsOneWidget,
      );
      // A value whose def doesn't apply to the category is kept and shown.
      expect(
        find.descendant(of: fields, matching: find.text('Khusus kerja')),
        findsOneWidget,
      );
      // Tags and dates.
      final tags = find.byKey(const ValueKey('person-tags'));
      expect(
        find.descendant(of: tags, matching: find.text('#inti')),
        findsOneWidget,
      );
      final dates = find.byKey(const ValueKey('person-dates'));
      expect(
        find.descendant(of: dates, matching: find.text('Ulang tahun')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dates, matching: find.text('29 Februari')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dates, matching: find.text('Peringatan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dates, matching: find.text('3 Maret')),
        findsOneWidget,
      );
      // No notes: nothing fetched.
      expect(r.notes.gets, 0);
      expect(find.text('Belum ada catatan.'), findsOneWidget);
    });

    testWidgets('notes of a normal person are fetched and rendered as '
        'markdown', (t) async {
      final r = Rig();
      r.people.s.put(
        fakePerson('p1', 'Budi Contoh', hasNotes: true, notesLength: 40),
      );
      r.notes.notes['p1'] = '# Latar belakang\n\nSuka **kopi hitam**.';
      await r.pump(t, '/people/p1');
      expect(r.notes.gets, 1);
      expect(find.text('Latar belakang'), findsOneWidget);
      expect(find.byKey(const ValueKey('notes-body')), findsOneWidget);
      expect(find.byKey(const ValueKey('notes-edit')), findsOneWidget);
    });

    testWidgets('sensitive notes stay collapsed and are fetched only on tap', (
      t,
    ) async {
      final r = Rig();
      r.people.s.put(
        fakePerson(
          'p1',
          'Dini Contoh',
          sensitive: true,
          hasNotes: true,
          notesLength: 30,
        ),
      );
      r.notes.notes['p1'] = '# Rahasia\n\nIsi yang sensitif.';
      await r.pump(t, '/people/p1');

      expect(r.notes.gets, 0, reason: 'nothing is read before the tap');
      expect(find.byKey(const ValueKey('notes-hidden')), findsOneWidget);
      expect(find.text('Tampilkan catatan sensitif'), findsOneWidget);
      expect(find.text('Rahasia'), findsNothing);
      expect(find.textContaining('Isi yang sensitif'), findsNothing);

      await tapKey(t, 'show-sensitive-notes');
      expect(r.notes.gets, 1);
      expect(find.text('Rahasia'), findsOneWidget);
      expect(find.text('Tampilkan catatan sensitif'), findsNothing);

      // Hiding drops it again (and a second show fetches again).
      await tapKey(t, 'notes-hide');
      expect(find.text('Rahasia'), findsNothing);
      expect(find.text('Tampilkan catatan sensitif'), findsOneWidget);
      await tapKey(t, 'show-sensitive-notes');
      expect(r.notes.gets, 2);
    });

    testWidgets('offline: a clear message and a retry', (t) async {
      final r = Rig();
      r.people.s.put(
        fakePerson('p1', 'Budi Contoh', hasNotes: true, notesLength: 3),
      );
      r.notes.notes['p1'] = 'halo';
      r.notes.failWith = const NetworkFailure();
      await r.pump(t, '/people/p1');
      expect(
        find.text('Catatan cuma bisa dibuka saat online.'),
        findsOneWidget,
      );
      r.notes.failWith = null;
      await tapKey(t, 'notes-retry');
      expect(find.text('halo'), findsOneWidget);
    });

    testWidgets('edit sends the updatedAt it read; a conflict says so and '
        'offers the latest', (t) async {
      final r = Rig();
      String? clipboard;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      r.people.s.put(
        fakePerson('p1', 'Budi Contoh', hasNotes: true, notesLength: 5),
      );
      r.notes.notes['p1'] = 'versi satu';
      await r.pump(t, '/people/p1');

      await tapKey(t, 'notes-edit');
      expect(find.byKey(const ValueKey('notes-field')), findsOneWidget);
      // Someone else writes meanwhile.
      await r.notes.replace('p1', 'versi dari web');
      await t.enterText(
        find.byKey(const ValueKey('notes-field')),
        'versi dua dari HP',
      );
      await tapKey(t, 'notes-save');
      expect(find.text('Catatan berubah di tempat lain'), findsOneWidget);
      expect(
        find.textContaining('Catatan ini sudah diubah di tempat lain'),
        findsOneWidget,
      );
      expect(r.notes.notes['p1'], 'versi dari web', reason: 'not overwritten');

      await tapText(t, 'MUAT VERSI TERBARU');
      await settle(t, 20);
      expect(
        clipboard,
        'versi dua dari HP',
        reason: 'the unsaved text is kept',
      );
      final field = t.widget<TextField>(
        find.byKey(const ValueKey('notes-field')),
      );
      expect(field.controller!.text, 'versi dari web');
      await tapKey(t, 'notes-save');
      expect(
        r.notes.notes['p1'],
        'versi dari web',
        reason: 'saved the reloaded text',
      );
      // Back on the detail with the new text.
      expect(find.text('versi dari web'), findsOneWidget);
    });

    testWidgets('"Tambah catatan" appends under an optional heading', (
      t,
    ) async {
      final r = Rig();
      r.people.s.put(
        fakePerson('p1', 'Budi Contoh', hasNotes: true, notesLength: 3),
      );
      r.notes.notes['p1'] = 'awal';
      await r.pump(t, '/people/p1');
      await tapKey(t, 'notes-append');
      await enter(t, 'append-heading', '2026-10-10');
      await enter(t, 'append-text', 'janji ketemu');
      await tapKey(t, 'append-save');
      expect(r.notes.notes['p1'], 'awal\n\n## 2026-10-10\njanji ketemu');
      expect(r.notes.gets, 2, reason: 'reloaded after the append');
    });

    testWidgets('delete asks first, then removes the person and its dates', (
      t,
    ) async {
      final r = Rig();
      r.people.s.put(fakePerson('p1', 'Budi Contoh'));
      r.people.s.put(fakePerson('p2', 'Siti Sample'));
      await r.pump(t, '/people');
      await tapText(t, 'Budi Contoh');
      await t.tap(find.byTooltip('Hapus'));
      await settle(t);
      expect(find.text('Hapus Budi Contoh?'), findsOneWidget);
      await tapText(t, 'BATAL');
      expect(r.people.s.items, hasLength(2));
      await t.tap(find.byTooltip('Hapus'));
      await settle(t);
      await tapText(t, 'HAPUS');
      expect(r.people.s.items.keys, ['p2']);
    });
  });

  group('form', () {
    testWidgets('create: partial birthday, category, vibe, tags, custom '
        'fields, "Tambah kolom" and important dates', (t) async {
      final r = Rig();
      r.defs.s.put(fakeDef('hobi', 'Hobi', PersonFieldType.text));
      await r.pump(t, '/people/new');

      await enter(t, 'person-name', '  Budi Contoh ');
      await enter(t, 'person-relation', 'Rekan kerja');
      await tapText(t, '💼 Kerja');
      await tapText(t, '💕 Positif');
      // A day without a month is refused, with the reason under the field.
      await enter(t, 'person-day', '12');
      await tapKey(t, 'person-save');
      expect(r.people.s.items, isEmpty);
      expect(find.text('Tanggal butuh bulan'), findsWidgets);
      // Pick the month; year stays empty (partial birthday).
      await tapKey(t, 'person-month');
      await tapKey(t, 'month-10');
      // Tags: type + Enter, and a suggestion-less second tag.
      await enter(t, 'person-tag', 'kantor');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(find.text('#kantor'), findsOneWidget);
      await enter(t, 'person-tag', 'inti'); // pending text counts on save
      // Existing custom field.
      await enter(t, 'field-hobi', 'badminton');
      // "Tambah kolom": a number field that then appears in the form.
      await tapKey(t, 'add-field');
      await enter(t, 'field-label', 'Ukuran sepatu');
      await tapText(t, 'Angka');
      await tapKey(t, 'field-save');
      expect(
        r.defs.s.items.values.map((d) => d.key),
        contains('ukuran_sepatu'),
      );
      await enter(t, 'field-ukuran_sepatu', '42');
      // An important date.
      await tapKey(t, 'add-date');
      await enter(t, 'date-label', 'Hari jadi');
      await tapText(t, '💍 Hari jadi');
      await enter(t, 'date-day', '20');
      await tapKey(t, 'date-save');
      // The date sheet needs a month first.
      expect(find.byKey(const ValueKey('date-error')), findsOneWidget);
      final monthFields = find.text('Pilih');
      await t.tap(monthFields.first);
      await settle(t);
      await tapKey(t, 'month-6');
      await tapKey(t, 'date-save');
      expect(find.byKey(const ValueKey('date-tile-0')), findsOneWidget);

      await tapKey(t, 'person-save');
      expect(r.people.s.items, hasLength(1));
      final p = r.people.s.items.values.single;
      expect(p.name, 'Budi Contoh');
      expect(p.category, 'work');
      expect(p.vibe, PersonVibe.positive);
      expect([p.birthYear, p.birthMonth, p.birthDay], [null, 10, 12]);
      expect(p.tags, ['kantor', 'inti']);
      expect(p.fields, {'hobi': 'badminton', 'ukuran_sepatu': 42});
      final d = r.dates.s.items.values.single;
      expect(
        [d.label, d.kind, d.month, d.day],
        ['Hari jadi', PersonDateKind.anniversary, 6, 20],
      );
      expect(d.personId, p.id);
    });

    testWidgets('server-style validation: lengths, ranges and Feb 29 with a '
        'common year', (t) async {
      final r = Rig();
      await r.pump(t, '/people/new');
      await tapKey(t, 'person-save');
      expect(find.text('Nama wajib diisi'), findsWidgets);

      await enter(t, 'person-name', 'Siti Sample');
      await enter(t, 'person-day', '29');
      await tapKey(t, 'person-month');
      await tapKey(t, 'month-2');
      await enter(t, 'person-year', '2001');
      await tapKey(t, 'person-save');
      expect(find.text('Tanggal itu nggak ada di kalender'), findsWidgets);
      expect(r.people.s.items, isEmpty);
      await enter(t, 'person-year', '');
      await tapKey(t, 'person-save');
      expect(
        r.people.s.items,
        hasLength(1),
        reason: 'Feb 29 without a year is fine',
      );

      // Year range.
      final r2 = Rig();
      await r2.pump(t, '/people/new');
      await enter(t, 'person-name', 'Andi Contoh');
      await enter(t, 'person-year', '1850');
      await tapKey(t, 'person-save');
      expect(find.text('Tahun harus antara 1900 dan 2026'), findsWidgets);
    });

    testWidgets('edit: the form is filled, hidden-category values survive a '
        'category switch, notes are not part of it', (t) async {
      final r = Rig();
      r.defs.s
        ..put(
          fakeDef(
            'hobi',
            'Hobi',
            PersonFieldType.text,
            appliesTo: const ['family'],
          ),
        )
        ..put(
          fakeDef(
            'jabatan',
            'Jabatan',
            PersonFieldType.text,
            appliesTo: const ['work'],
            order: 1,
          ),
        );
      r.people.s.put(
        Person(
          id: 'p1',
          name: 'Siti Sample',
          category: 'family',
          vibe: PersonVibe.positive,
          birthYear: 1972,
          birthMonth: 2,
          birthDay: 29,
          tags: const ['inti'],
          fields: const {'hobi': 'berkebun'},
          sensitive: true,
          hasNotes: true,
          notesLength: 20,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      r.dates.s.put(
        fakeDate(
          'd1',
          'p1',
          'Hari jadi',
          6,
          12,
          kind: PersonDateKind.anniversary,
        ),
      );
      await r.pump(t, '/people/p1/edit');

      EditableText tf(String key) => t.widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(key), skipOffstage: false),
          matching: find.byType(EditableText, skipOffstage: false),
        ),
      );
      expect(tf('person-name').controller.text, 'Siti Sample');
      expect(tf('person-day').controller.text, '29');
      expect(tf('person-year').controller.text, '1972');
      expect(tf('field-hobi').controller.text, 'berkebun');
      expect(find.byKey(const ValueKey('field-jabatan')), findsNothing);
      expect(
        find.byKey(const ValueKey('date-tile-0'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('notes-field')), findsNothing);
      expect(r.notes.gets, 0);

      // Switch category: 'hobi' hides, 'jabatan' shows, the stored value stays.
      await tapText(t, '💼 Kerja');
      expect(find.byKey(const ValueKey('field-hobi')), findsNothing);
      await enter(t, 'field-jabatan', 'Manajer');
      await enter(t, 'person-name', 'Siti S.');
      await tapKey(t, 'person-save');
      final p = r.people.s.items['p1']!;
      expect(p.name, 'Siti S.');
      expect(p.category, 'work');
      expect(p.fields, {'hobi': 'berkebun', 'jabatan': 'Manajer'});
      expect(p.sensitive, isTrue);
      expect(p.hasNotes, isTrue, reason: 'the notes mirror is kept');
      expect(p.notesLength, 20);
      expect(r.dates.s.items.keys, ['d1']);
    });

    testWidgets('typed field values: number, yes/no, option and date', (
      t,
    ) async {
      final r = Rig();
      r.defs.s
        ..put(fakeDef('ukuran_sepatu', 'Ukuran sepatu', PersonFieldType.number))
        ..put(fakeDef('vegan', 'Vegan', PersonFieldType.boolean, order: 1))
        ..put(
          fakeDef(
            'gol',
            'Gol. darah',
            PersonFieldType.select,
            options: const ['A', 'O'],
            order: 2,
          ),
        );
      await r.pump(t, '/people/new');
      await enter(t, 'person-name', 'Andi Contoh');
      await enter(t, 'field-ukuran_sepatu', '41,5');
      await tapText(t, 'Ya');
      await tapText(t, 'O');
      await tapKey(t, 'person-save');
      final p = r.people.s.items.values.single;
      expect(p.fields, {'ukuran_sepatu': 41.5, 'vegan': true, 'gol': 'O'});
    });
  });

  group('manage', () {
    testWidgets('lists categories and fields; add and rename a category', (
      t,
    ) async {
      final r = Rig();
      r.defs.s.put(
        fakeDef(
          'hobi',
          'Hobi',
          PersonFieldType.text,
          appliesTo: const ['family'],
        ),
      );
      await r.pump(t, '/people/manage');
      expect(find.text('Keluarga'), findsOneWidget);
      expect(find.text('Teks · Keluarga'), findsOneWidget);

      await tapKey(t, 'add-category');
      await enter(t, 'category-emoji', '🏠');
      await enter(t, 'category-label', 'Kos');
      await tapKey(t, 'category-save');
      expect(r.cats.s.items.values.map((c) => c.key), contains('kos'));
      expect(find.text('Kos'), findsOneWidget);

      await tapText(t, 'Kos');
      await enter(t, 'category-label', 'Anak kos');
      await tapKey(t, 'category-save');
      final kos = r.cats.s.items.values.firstWhere((c) => c.key == 'kos');
      expect(kos.label, 'Anak kos');
      expect(kos.key, 'kos', reason: 'the key never changes');

      // A field can be renamed but its type stays (no destructive retype).
      await tapText(t, 'Hobi');
      expect(find.textContaining('Jenis: Teks'), findsOneWidget);
      await enter(t, 'field-rename', 'Kegemaran');
      await tapKey(t, 'field-rename-save');
      final hobi = r.defs.s.items['pf-hobi']!;
      expect(
        [hobi.label, hobi.key, hobi.type],
        ['Kegemaran', 'hobi', PersonFieldType.text],
      );
    });
  });

  group('calendar overlay', () {
    testWidgets('birthdays and important dates show read-only, without '
        'creating calendar events', (t) async {
      final r = Rig();
      _seedList(r);
      final events = _Events();
      final reminders = _Reminders();
      t.view.physicalSize = const Size(1080, 5200);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ...r.overrides,
            calendarEventRepositoryProvider.overrideWithValue(events),
            reminderItemRepositoryProvider.overrideWithValue(reminders),
          ],
          child: MaterialApp.router(
            theme: GhinaTheme.light(),
            routerConfig: r.router('/calendar'),
          ),
        ),
      );
      await settle(t);

      // Oct 12 (Budi's birthday) and Oct 20 (his anniversary) have pink dots.
      expect(
        find.byKey(const ValueKey('cal-people-2026-10-12')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cal-people-2026-10-20')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cal-people-2026-10-13')), findsNothing);

      await t.tap(find.byKey(const ValueKey('cal-day-2026-10-12')));
      await settle(t);
      expect(find.text('🎂 Budi Contoh'), findsOneWidget);
      expect(find.text('Ulang tahun ke-36'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('cal-day-2026-10-20')));
      await settle(t);
      expect(find.text('💍 Hari jadi · Budi Contoh'), findsOneWidget);

      // Nothing was stored as a calendar event.
      expect(events.items, isEmpty);

      // Tapping the entry opens the person.
      await t.tap(find.text('💍 Hari jadi · Budi Contoh'));
      await settle(t);
      expect(find.text('Tanggal penting'), findsOneWidget);
    });
  });
}

class _Events implements CalendarEventRepository {
  final items = <String, CalendarEvent>{};
  @override
  Stream<List<CalendarEvent>> watchAll() => Stream.value(items.values.toList());
  @override
  Future<List<CalendarEvent>> getAll() async => items.values.toList();
  @override
  Stream<CalendarEvent?> watchById(String id) => Stream.value(items[id]);
  @override
  Future<CalendarEvent?> getById(String id) async => items[id];
  @override
  Future<void> save(CalendarEvent e) async => items[e.id] = e;
  @override
  Future<void> delete(String id) async => items.remove(id);
}

class _Reminders implements ReminderItemRepository {
  @override
  Stream<List<ReminderItem>> watchAll() => Stream.value(const []);
  @override
  Future<List<ReminderItem>> getAll() async => const [];
  @override
  Stream<ReminderItem?> watchById(String id) => Stream.value(null);
  @override
  Future<ReminderItem?> getById(String id) async => null;
  @override
  Future<void> save(ReminderItem r) async {}
  @override
  Future<void> delete(String id) async {}
}
