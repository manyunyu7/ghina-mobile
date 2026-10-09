// Dart port of src/lib/people.ts: birthdays (Feb 29, partial, year-only),
// next occurrence, upcoming / calendar ranges, validation, custom fields,
// search / grouping and the notification schedule. Invented people only.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';
import 'people_fakes.dart';

void main() {
  group('calendar basics', () {
    test('leap years and month lengths (Feb 29 without a year is allowed)', () {
      expect(isLeapYear(2024), isTrue);
      expect(isLeapYear(1900), isFalse);
      expect(isLeapYear(2000), isTrue);
      expect(isLeapYear(2026), isFalse);
      expect(daysInMonthOf(2), 29, reason: 'no year: Feb 29 is possible');
      expect(daysInMonthOf(2, 2026), 28);
      expect(daysInMonthOf(2, 2028), 29);
      expect(daysInMonthOf(4), 30);
      expect(daysInMonthOf(12), 31);
    });

    test('real date keys', () {
      expect(isRealDateKey('2026-02-28'), isTrue);
      expect(isRealDateKey('2026-02-29'), isFalse);
      expect(isRealDateKey('2028-02-29'), isTrue);
      expect(isRealDateKey('2026-13-01'), isFalse);
      expect(isRealDateKey('2026-4-1'), isFalse);
    });
  });

  group('birthdayError', () {
    String? err({int? y, int? m, int? d}) =>
        birthdayError(year: y, month: m, day: d, currentYear: 2026);

    test('partial birthdays are fine', () {
      expect(err(), isNull, reason: 'nothing known');
      expect(err(y: 1990), isNull, reason: 'year only');
      expect(err(m: 5), isNull, reason: 'month only');
      expect(err(y: 1990, m: 5), isNull, reason: 'month + year');
      expect(err(m: 5, d: 17), isNull, reason: 'no year');
      expect(err(y: 1990, m: 5, d: 17), isNull);
    });

    test('a day without a month is rejected', () {
      expect(err(d: 17), 'Tanggal butuh bulan');
      expect(err(y: 1990, d: 17), 'Tanggal butuh bulan');
    });

    test(
      'Feb 29: ok without a year or in a leap year, not in a common one',
      () {
        expect(err(m: 2, d: 29), isNull);
        expect(err(y: 2000, m: 2, d: 29), isNull);
        expect(err(y: 1996, m: 2, d: 29), isNull);
        expect(err(y: 2001, m: 2, d: 29), 'Tanggal itu nggak ada di kalender');
        expect(err(y: 1900, m: 2, d: 29), 'Tanggal itu nggak ada di kalender');
        expect(err(m: 2, d: 30), 'Tanggal itu nggak ada di kalender');
      },
    );

    test('ranges', () {
      expect(err(m: 0), 'Bulan harus 1–12');
      expect(err(m: 13), 'Bulan harus 1–12');
      expect(err(m: 4, d: 31), 'Tanggal itu nggak ada di kalender');
      expect(err(m: 4, d: 30), isNull);
      expect(err(m: 1, d: 0), 'Tanggal harus 1–31');
      expect(err(m: 1, d: 32), 'Tanggal harus 1–31');
      expect(err(y: 1899), 'Tahun harus antara 1900 dan 2026');
      expect(err(y: 2027), 'Tahun harus antara 1900 dan 2026');
      expect(err(y: 1900), isNull);
      expect(err(y: 2026), isNull);
    });
  });

  group('birthdayInYear / nextAnnualOccurrence', () {
    test('Feb 29 falls on Feb 28 in common years', () {
      expect(birthdayInYear(2, 29, 2026), '2026-02-28');
      expect(birthdayInYear(2, 29, 2027), '2027-02-28');
      expect(birthdayInYear(2, 29, 2028), '2028-02-29');
      expect(birthdayInYear(2, 29, 2100), '2100-02-28');
      expect(birthdayInYear(5, 17, 2026), '2026-05-17');
    });

    test('today counts, a passed date rolls to next year', () {
      final today = nextAnnualOccurrence(10, 10, 1990, '2026-10-10');
      expect(
        (today.nextDate, today.daysUntil, today.yearsSince),
        ('2026-10-10', 0, 36),
      );
      final passed = nextAnnualOccurrence(10, 9, 1990, '2026-10-10');
      expect(
        (passed.nextDate, passed.daysUntil, passed.yearsSince),
        ('2027-10-09', 364, 37),
      );
      final soon = nextAnnualOccurrence(10, 11, null, '2026-10-10');
      expect(soon.daysUntil, 1);
      expect(
        soon.yearsSince,
        isNull,
        reason: 'age only when the year is known',
      );
    });

    test('Feb 29: counted to Feb 28 until a leap year', () {
      final a = nextAnnualOccurrence(2, 29, 2000, '2026-10-10');
      expect(a.nextDate, '2027-02-28');
      expect(a.yearsSince, 27);
      final b = nextAnnualOccurrence(2, 29, 2000, '2027-03-01');
      expect(b.nextDate, '2028-02-29');
      expect(b.yearsSince, 28);
      final c = nextAnnualOccurrence(2, 29, 2000, '2028-02-29');
      expect(c.daysUntil, 0);
      // Feb 28 itself in a common year is the day.
      expect(nextAnnualOccurrence(2, 29, null, '2027-02-28').daysUntil, 0);
    });

    test('across the year boundary and DST-free day math', () {
      expect(nextAnnualOccurrence(1, 1, null, '2026-12-31').daysUntil, 1);
      expect(nextAnnualOccurrence(12, 31, null, '2026-01-01').daysUntil, 364);
      expect(nextAnnualOccurrence(3, 1, null, '2027-02-27').daysUntil, 2);
    });
  });

  group('upcomingEvents', () {
    final people = [
      fakePerson(
        'p1',
        'Budi Contoh',
        birthYear: 1990,
        birthMonth: 10,
        birthDay: 12,
      ),
      fakePerson('p2', 'Siti Sample', birthMonth: 2, birthDay: 29),
      fakePerson('p3', 'Andi Contoh', birthYear: 1985, birthMonth: 5),
      fakePerson('p4', 'Tanpa Tanggal', birthYear: 1970),
      fakePerson('p5', 'Dini Contoh', birthMonth: 10, birthDay: 10),
    ];
    final dates = [
      fakeDate(
        'd1',
        'p1',
        'Hari jadi',
        10,
        20,
        kind: PersonDateKind.anniversary,
        year: 2015,
      ),
      fakeDate('d2', 'p1', 'Peringatan', 12, 1, kind: PersonDateKind.memorial),
      fakeDate('dX', 'ghost', 'Yatim', 10, 11),
    ];

    test('birthdays + important dates within the window, soonest first; '
        'partial birthdays and orphans are left out', () {
      final u = upcomingEvents(people, dates, '2026-10-10', 60);
      expect(
        [for (final e in u) '${e.name}|${e.kind.name}|${e.daysUntil}'],
        [
          'Dini Contoh|birthday|0',
          'Budi Contoh|birthday|2',
          'Budi Contoh|anniversary|10',
          'Budi Contoh|memorial|52',
        ],
      );
      final budi = u.firstWhere(
        (e) => e.kind == EventKind.birthday && e.personId == 'p1',
      );
      expect(budi.yearsSince, 36);
      expect(u.first.yearsSince, isNull, reason: 'Dini has no birth year');
      expect(u.firstWhere((e) => e.dateId == 'd1').yearsSince, 11);
    });

    test('window edges and Feb 29', () {
      expect(
        upcomingEvents(people, dates, '2026-10-10', 0).map((e) => e.name),
        ['Dini Contoh'],
      );
      final long = upcomingEvents(people, dates, '2026-10-10', 200);
      final siti = long.firstWhere((e) => e.personId == 'p2');
      expect(siti.nextDate, '2027-02-28');
      expect(siti.daysUntil, 141);
    });
  });

  group('eventsInRange (calendar overlay)', () {
    final people = [
      fakePerson(
        'p1',
        'Budi Contoh',
        birthYear: 1990,
        birthMonth: 1,
        birthDay: 2,
      ),
      fakePerson('p2', 'Siti Sample', birthMonth: 2, birthDay: 29),
      fakePerson('p3', 'Andi Contoh', birthMonth: 12, birthDay: 30),
    ];
    final dates = [
      fakeDate('d1', 'p3', 'Wafat', 1, 5, kind: PersonDateKind.memorial),
    ];

    test('spans December → January', () {
      final r = eventsInRange(people, dates, '2026-12-28', '2027-01-10');
      expect(
        [for (final o in r) '${o.dateKey} ${o.kind.emoji} ${o.name}'],
        [
          '2026-12-30 🎂 Andi Contoh',
          '2027-01-02 🎂 Budi Contoh',
          '2027-01-05 🕊️ Andi Contoh',
        ],
      );
      expect(r[1].yearsSince, 37);
      expect(r[0].yearsSince, isNull);
    });

    test(
      'Feb 29 lands on Feb 28 in a common year and Feb 29 in a leap year',
      () {
        final common = eventsInRange(people, dates, '2027-02-01', '2027-03-05');
        expect(common.single.dateKey, '2027-02-28');
        final leap = eventsInRange(people, dates, '2028-02-01', '2028-03-05');
        expect(leap.single.dateKey, '2028-02-29');
      },
    );

    test('inclusive bounds; grouped by day', () {
      final r = eventsInRange(people, dates, '2027-01-02', '2027-01-02');
      expect(r, hasLength(1));
      expect(
        occurrencesByDay(
          eventsInRange(people, dates, '2026-12-01', '2027-03-01'),
        ).keys,
        containsAll(['2026-12-30', '2027-01-02', '2027-01-05', '2027-02-28']),
      );
    });
  });

  group('formatting', () {
    test('formatBirthday handles every partial shape', () {
      expect(formatBirthday(year: 1990, month: 5, day: 17), '17 Mei 1990');
      expect(formatBirthday(month: 5, day: 17), '17 Mei');
      expect(formatBirthday(year: 1990, month: 5), 'Mei 1990');
      expect(formatBirthday(year: 1990), '1990');
      expect(formatBirthday(month: 5), 'Mei');
      expect(formatBirthday(), isNull);
      expect(formatBirthday(day: 17), isNull, reason: 'a day alone is invalid');
    });

    test('labels', () {
      expect(daysUntilLabel(0), 'Hari ini');
      expect(daysUntilLabel(1), 'Besok');
      expect(daysUntilLabel(9), '9 hari lagi');
      expect(yearsLabel(EventKind.birthday, 35), 'Ke-35');
      expect(yearsLabel(EventKind.anniversary, 10), '10 tahun');
      expect(yearsLabel(EventKind.birthday, null), isNull);
    });
  });

  group('tags', () {
    test(
      'trim, drop empties, dedupe case-insensitively (first spelling wins)',
      () {
        expect(normalizeTags(['  inti ', 'Inti', '', 'kantor', 'KANTOR ']), [
          'inti',
          'kantor',
        ]);
      },
    );

    test('limits', () {
      expect(
        () => normalizeTags(['x' * 41]),
        throwsA(
          isA<ValidationFailure>().having((f) => f.field, 'field', 'tags'),
        ),
      );
      expect(normalizeTags(['x' * 40]), hasLength(1));
      expect(
        () => normalizeTags([for (var i = 0; i < 21; i++) 't$i']),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        normalizeTags([for (var i = 0; i < 20; i++) 't$i']),
        hasLength(20),
      );
    });
  });

  group('custom fields', () {
    final number = fakeDef(
      'ukuran_sepatu',
      'Ukuran sepatu',
      PersonFieldType.number,
    );
    final select = fakeDef(
      'golongan_darah',
      'Gol. darah',
      PersonFieldType.select,
      options: const ['A', 'B', 'AB', 'O'],
    );

    test('values are validated against the def type', () {
      expect(checkFieldValue(number, 38), 38);
      expect(
        () => checkFieldValue(number, '38'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => checkFieldValue(number, double.nan),
        throwsA(isA<ValidationFailure>()),
      );
      expect(checkFieldValue(select, ' O '), 'O');
      expect(
        () => checkFieldValue(select, 'C'),
        throwsA(isA<ValidationFailure>()),
      );
      final date = fakeDef('lahir_anak', 'Lahir anak', PersonFieldType.date);
      expect(checkFieldValue(date, '2024-02-29'), '2024-02-29');
      expect(
        () => checkFieldValue(date, '2025-02-29'),
        throwsA(isA<ValidationFailure>()),
      );
      final url = fakeDef('blog', 'Blog', PersonFieldType.url);
      expect(
        checkFieldValue(url, 'https://contoh.example/budi'),
        startsWith('https'),
      );
      expect(
        () => checkFieldValue(url, 'javascript:alert(1)'),
        throwsA(isA<ValidationFailure>()),
      );
      final email = fakeDef('email2', 'Email 2', PersonFieldType.email);
      expect(
        () => checkFieldValue(email, 'budi@'),
        throwsA(isA<ValidationFailure>()),
      );
      final yes = fakeDef('vegan', 'Vegan', PersonFieldType.boolean);
      expect(checkFieldValue(yes, false), false);
      expect(
        () => checkFieldValue(yes, 'ya'),
        throwsA(isA<ValidationFailure>()),
      );
      final text = fakeDef('hobi', 'Hobi', PersonFieldType.text);
      expect(
        () => checkFieldValue(text, '   '),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => checkFieldValue(text, 'x' * 2001),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'a whole map: unknown keys fail, nulls are dropped, hidden defs keep values',
      () {
        expect(
          validateFields(
            {'ukuran_sepatu': 38, 'golongan_darah': null},
            [number, select],
          ),
          {'ukuran_sepatu': 38},
        );
        expect(
          () => validateFields({'nope': 1}, [number]),
          throwsA(isA<ValidationFailure>()),
        );
        final family = fakeDef(
          'hobi',
          'Hobi',
          PersonFieldType.text,
          appliesTo: const ['family'],
        );
        expect(family.appliesToCategory('family'), isTrue);
        expect(family.appliesToCategory('work'), isFalse);
        expect(defsFor([family, number], 'work').map((d) => d.key), [
          'ukuran_sepatu',
        ]);
        // Values of a def that doesn't apply to the category still validate/keep.
        expect(validateFields({'hobi': 'berkebun'}, [family]), {
          'hobi': 'berkebun',
        });
      },
    );

    test('defStillFits: the retype / options safety check', () {
      expect(defStillFits(select, ['A', 'O']), isTrue);
      expect(defStillFits(select.copyWith(), ['AB', 'Z']), isFalse);
      expect(defStillFits(number, [1, 2.5]), isTrue);
      expect(defStillFits(number, [1, 'x']), isFalse);
    });

    test('keys and display', () {
      expect(slugifyKey('Ukuran Sepatu'), 'ukuran_sepatu');
      expect(slugifyKey('  Golongan-Darah!! '), 'golongan_darah');
      expect(slugifyKey('Café'), 'cafe');
      expect(slugifyKey('2 anak'), 'f_2_anak');
      expect(slugifyKey('???'), isNull);
      expect(slugifyKey('x' * 60), hasLength(40));
      expect(prettifyKey('ukuran_sepatu'), 'Ukuran sepatu');
      expect(
        formatFieldValue(fakeDef('v', 'V', PersonFieldType.boolean), true),
        'Ya',
      );
      expect(
        formatFieldValue(fakeDef('v', 'V', PersonFieldType.boolean), false),
        'Tidak',
      );
      expect(
        formatFieldValue(fakeDef('d', 'D', PersonFieldType.date), '2024-02-29'),
        '29 Februari 2024',
      );
      expect(formatFieldValue(number, 38.0), '38');
      expect(formatFieldValue(number, 38.5), '38.5');
    });
  });

  group('validatePerson / validatePersonDate', () {
    final now = DateTime(2026, 10, 10);
    Person ok(PersonInput i, {List<String> cats = const ['family', 'other']}) =>
        validatePerson(
          id: 'p',
          input: i,
          categoryKeys: cats,
          defs: const [],
          currentYear: 2026,
          createdAt: now,
          updatedAt: now,
        );

    Matcher failsOn(String field) => throwsA(
      isA<ValidationFailure>().having((f) => f.field, 'field', field),
    );

    test('trims, nulls empties and enforces the server lengths', () {
      final p = ok(
        const PersonInput(
          name: '  Budi Contoh ',
          relation: ' ',
          category: 'family',
          phone: ' 0812 ',
          tags: ['a', 'A'],
        ),
      );
      expect(p.name, 'Budi Contoh');
      expect(p.relation, isNull);
      expect(p.phone, '0812');
      expect(p.tags, ['a']);
      expect(() => ok(const PersonInput(name: ' ')), failsOn('name'));
      expect(() => ok(PersonInput(name: 'x' * 121)), failsOn('name'));
      expect(ok(PersonInput(name: 'x' * 120)).name, hasLength(120));
      expect(
        () => ok(PersonInput(name: 'a', summary: 'x' * 1001)),
        failsOn('summary'),
      );
      expect(
        () => ok(PersonInput(name: 'a', address: 'x' * 301)),
        failsOn('address'),
      );
      expect(
        () => ok(PersonInput(name: 'a', phone: 'x' * 41)),
        failsOn('phone'),
      );
      expect(
        () => ok(PersonInput(name: 'a', instagram: 'x' * 61)),
        failsOn('instagram'),
      );
      expect(
        () => ok(const PersonInput(name: 'a', email: 'budi@')),
        failsOn('email'),
      );
    });

    test('birthday: day needs a month; Feb 29 with a common year fails', () {
      expect(
        () => ok(const PersonInput(name: 'a', birthDay: 5)),
        failsOn('birthday'),
      );
      expect(
        () => ok(
          const PersonInput(
            name: 'a',
            birthYear: 2001,
            birthMonth: 2,
            birthDay: 29,
          ),
        ),
        failsOn('birthday'),
      );
      expect(
        ok(
          const PersonInput(name: 'a', birthMonth: 2, birthDay: 29),
        ).hasBirthday,
        isTrue,
      );
      expect(
        ok(const PersonInput(name: 'a', birthYear: 1990)).hasBirthday,
        isFalse,
      );
      expect(
        () => ok(const PersonInput(name: 'a', birthYear: 2027)),
        failsOn('birthday'),
      );
    });

    test('category must exist (other always ok); fields must fit', () {
      expect(
        () => ok(const PersonInput(name: 'a', category: 'kos')),
        failsOn('category'),
      );
      expect(
        ok(const PersonInput(name: 'a', category: 'other')).category,
        'other',
      );
      expect(
        () => validatePerson(
          id: 'p',
          input: const PersonInput(name: 'a', fields: {'zzz': 1}),
          categoryKeys: const [],
          defs: const [],
          currentYear: 2026,
          createdAt: now,
          updatedAt: now,
        ),
        failsOn('fields'),
      );
    });

    test('important dates: same date rules, label, remind range', () {
      PersonDate d(PersonDateInput i) => validatePersonDate(
        id: 'd',
        personId: 'p',
        input: i,
        currentYear: 2026,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        d(
          const PersonDateInput(
            label: ' Hari jadi ',
            month: 6,
            day: 12,
            remindDaysBefore: 7,
          ),
        ).label,
        'Hari jadi',
      );
      expect(
        () => d(const PersonDateInput(label: '', month: 6, day: 12)),
        failsOn('label'),
      );
      expect(
        () => d(const PersonDateInput(label: 'x', month: 6, day: 31)),
        failsOn('date'),
      );
      expect(
        () =>
            d(const PersonDateInput(label: 'x', month: 2, day: 29, year: 2023)),
        failsOn('date'),
      );
      expect(d(const PersonDateInput(label: 'x', month: 2, day: 29)).day, 29);
      expect(
        () => d(
          const PersonDateInput(
            label: 'x',
            month: 6,
            day: 1,
            remindDaysBefore: 366,
          ),
        ),
        failsOn('remindDaysBefore'),
      );
      expect(
        d(
          const PersonDateInput(
            label: 'x',
            month: 6,
            day: 1,
            remindDaysBefore: 365,
          ),
        ).remindDaysBefore,
        365,
      );
      expect(
        () => d(PersonDateInput(label: 'x' * 81, month: 6, day: 1)),
        failsOn('label'),
      );
    });
  });

  group('search + grouping', () {
    final cats = [
      fakeCategory('family', 'Keluarga', '👨‍👩‍👧', order: 0),
      fakeCategory('work', 'Kerja', '💼', order: 1),
      fakeCategory('other', 'Lainnya', '👤', order: 2),
    ];
    final defs = [
      fakeDef('hobi', 'Hobi', PersonFieldType.text),
      fakeDef('vegan', 'Vegan', PersonFieldType.boolean),
    ];
    final people = [
      fakePerson(
        'p1',
        'Siti Sample',
        category: 'family',
        relation: 'Ibu',
        tags: ['inti'],
        fields: {'hobi': 'berkebun', 'vegan': true},
      ),
      fakePerson(
        'p2',
        'Budi Contoh',
        category: 'work',
        relation: 'Fullstack Dev',
        tags: ['kantor', 'inti'],
      ),
      fakePerson(
        'p3',
        'Andi Contoh',
        category: 'family',
        summary: 'Adik, kuliah di luar kota',
      ),
      fakePerson('p4', 'Dini Contoh', category: 'ghost-cat'),
    ];

    test('groups follow the category order; unknown categories come last', () {
      final g = groupPeople(people, cats, defs: defs);
      expect(g.map((x) => x.categoryKey), ['family', 'work', 'ghost-cat']);
      expect(g.first.people.map((p) => p.name), ['Andi Contoh', 'Siti Sample']);
      expect(g.first.emoji, '👨‍👩‍👧');
      expect(g.last.label, 'Ghost cat');
    });

    test('search covers name, relation, summary, tags and field values '
        '(all words, case-insensitive)', () {
      List<String> names(String q) => [
        for (final g in groupPeople(people, cats, defs: defs, query: q))
          for (final p in g.people) p.name,
      ];
      expect(names('siti'), ['Siti Sample']);
      expect(names('IBU'), ['Siti Sample']);
      expect(names('fullstack'), ['Budi Contoh']);
      expect(names('kuliah luar'), ['Andi Contoh']);
      expect(names('berkebun'), ['Siti Sample'], reason: 'field value');
      expect(names('ya'), ['Siti Sample'], reason: 'formatted boolean value');
      expect(names('inti'), ['Siti Sample', 'Budi Contoh']);
      expect(names('tidak ada'), isEmpty);
      expect(names('   '), hasLength(4));
    });

    test('tag filter and the tag list', () {
      final g = groupPeople(people, cats, tag: 'INTI');
      expect(
        [for (final x in g) ...x.people.map((p) => p.name)],
        ['Siti Sample', 'Budi Contoh'],
      );
      expect(allTags(people), ['inti', 'kantor']);
    });
  });

  group(
    'computePeopleReminders (09:00 local, cap shared with the scheduler)',
    () {
      List<String> keys(List<Reminder> r) => [for (final x in r) x.key];

      test(
        'day-of 09:00 plus remindDaysBefore; only birthdays with day + month',
        () {
          final people = [
            fakePerson(
              'p1',
              'Budi Contoh',
              birthYear: 1990,
              birthMonth: 10,
              birthDay: 12,
            ),
            fakePerson('p2', 'Andi Contoh', birthYear: 1985, birthMonth: 5),
            fakePerson('p3', 'Tanpa Hari', birthYear: 1970),
          ];
          final dates = [
            fakeDate(
              'd1',
              'p1',
              'Hari jadi',
              10,
              20,
              kind: PersonDateKind.anniversary,
              year: 2015,
              remind: 7,
            ),
            fakeDate('dX', 'ghost', 'Yatim', 10, 11),
          ];
          final r = computePeopleReminders(
            people,
            dates,
            DateTime(2026, 10, 10, 8),
          );
          r.sort((a, b) => a.fireAt.compareTo(b.fireAt));
          expect(r.map((x) => (x.key, x.fireAt)), [
            ('person:birthday:p1:20261012', DateTime(2026, 10, 12, 9)),
            ('person:date:d1:20261020:b7', DateTime(2026, 10, 13, 9)),
            ('person:date:d1:20261020', DateTime(2026, 10, 20, 9)),
          ]);
          expect(r.first.title, '🎂 Ulang tahun Budi Contoh');
          expect(r.first.body, 'Hari ini ulang tahunnya yang ke-36 🎉');
          expect(r.first.route, '/people/p1');
          expect(r[1].title, '💍 Hari jadi · Budi Contoh');
          expect(r[1].body, '7 hari lagi: Hari jadi');
          expect(r[2].body, 'Hari ini · 11 tahun');
        },
      );

      test('no birth year → no age; 1 day before reads "Besok"', () {
        final people = [
          fakePerson('p1', 'Siti Sample', birthMonth: 10, birthDay: 12),
        ];
        final dates = [
          fakeDate(
            'd1',
            'p1',
            'Peringatan',
            10,
            14,
            kind: PersonDateKind.memorial,
            remind: 1,
          ),
        ];
        final r = computePeopleReminders(people, dates, DateTime(2026, 10, 10));
        r.sort((a, b) => a.fireAt.compareTo(b.fireAt));
        expect(r.first.body, 'Hari ini ulang tahunnya 🎉');
        expect(r.map((x) => x.body).toList()[1], 'Besok: Peringatan');
        expect(r.last.body, 'Hari ini');
      });

      test(
        'times in the past are skipped: today 10:00 is gone, today 08:00 is not',
        () {
          final people = [
            fakePerson('p1', 'Budi Contoh', birthMonth: 10, birthDay: 10),
          ];
          expect(
            keys(
              computePeopleReminders(
                people,
                const [],
                DateTime(2026, 10, 10, 8),
              ),
            ),
            ['person:birthday:p1:20261010'],
          );
          expect(
            computePeopleReminders(
              people,
              const [],
              DateTime(2026, 10, 10, 10),
            ),
            isEmpty,
            reason: 'next year is beyond the window',
          );
          expect(
            computePeopleReminders(people, const [], DateTime(2026, 10, 10, 9)),
            isEmpty,
            reason: 'exactly 09:00 is not after now',
          );
        },
      );

      test('Feb 29 → Feb 28 in common years, Feb 29 in leap years', () {
        final people = [
          fakePerson(
            'p1',
            'Siti Sample',
            birthYear: 2000,
            birthMonth: 2,
            birthDay: 29,
          ),
        ];
        final common = computePeopleReminders(
          people,
          const [],
          DateTime(2027, 2, 1),
        );
        expect(common.single.fireAt, DateTime(2027, 2, 28, 9));
        expect(common.single.body, contains('ke-27'));
        final leap = computePeopleReminders(
          people,
          const [],
          DateTime(2028, 2, 1),
        );
        expect(leap.single.fireAt, DateTime(2028, 2, 29, 9));
      });

      test(
        'window: 90 days ahead; early-January events seen from late December',
        () {
          final people = [
            fakePerson('p1', 'Budi Contoh', birthMonth: 1, birthDay: 3),
            fakePerson('p2', 'Andi Contoh', birthMonth: 6, birthDay: 1),
          ];
          final r = computePeopleReminders(
            people,
            const [],
            DateTime(2026, 12, 28),
          );
          expect(r.map((x) => x.fireAt), [DateTime(2027, 1, 3, 9)]);
          expect(r.single.key, 'person:birthday:p1:20270103');
        },
      );

      test(
        'WatchReminders merges them with the other reminders under one cap',
        () async {
          final people = FakePersonRepository();
          final dates = FakePersonDateRepository();
          for (var i = 0; i < 70; i++) {
            people.s.put(
              fakePerson(
                'p$i',
                'Orang $i',
                birthMonth: 10,
                birthDay: 11 + (i % 17),
              ),
            );
          }
          final w = WatchReminders(
            FakeTaskRepository(),
            FakeTaskAreaRepository(),
            () => Stream.value(DateTime(2026, 10, 10, 8)),
            people: people,
            personDates: dates,
          );
          final r = await w().first;
          expect(r, hasLength(maxTaskNotifications));
          expect(
            r.map((x) => x.fireAt).toList(),
            ([...r.map((x) => x.fireAt)]..sort()),
            reason: 'soonest first',
          );
          // Without the people repositories nothing changes.
          final plain = await WatchReminders(
            FakeTaskRepository(),
            FakeTaskAreaRepository(),
            () => Stream.value(DateTime(2026, 10, 10, 8)),
          )().first;
          expect(plain, isEmpty);
        },
      );
    },
  );

  group('use cases', () {
    late FakePersonRepository people;
    late FakePersonCategoryRepository cats;
    late FakePersonFieldRepository fields;
    late FakePersonDateRepository dates;
    late FakeUnitOfWork uow;
    late FixedClock clock;
    late SavePerson save;

    setUp(() {
      people = FakePersonRepository();
      cats = FakePersonCategoryRepository();
      fields = FakePersonFieldRepository();
      dates = FakePersonDateRepository();
      uow = FakeUnitOfWork();
      clock = FixedClock(DateTime(2026, 10, 10, 12));
      save = SavePerson(people, cats, fields, dates, uow, clock);
      cats.s.put(fakeCategory('family', 'Keluarga', '👨‍👩‍👧'));
      fields.s.put(
        fakeDef('ukuran_sepatu', 'Ukuran sepatu', PersonFieldType.number),
      );
    });

    test(
      'create → edit keeps the notes mirror; dates are diffed in one unit of work',
      () async {
        final created = (await save(
          input: const PersonInput(
            name: 'Budi Contoh',
            category: 'family',
            fields: {'ukuran_sepatu': 42},
          ),
          dates: const [
            PersonDateInput(label: 'Hari jadi', month: 6, day: 12),
            PersonDateInput(
              label: 'Peringatan',
              kind: PersonDateKind.memorial,
              month: 1,
              day: 5,
            ),
          ],
        )).valueOrThrow;
        expect(uow.runs, 1);
        expect((await dates.getForPerson(created.id)), hasLength(2));
        // The server says there are notes.
        people.s.put(
          Person(
            id: created.id,
            name: created.name,
            category: 'family',
            fields: created.fields,
            hasNotes: true,
            notesLength: 12,
            createdAt: created.createdAt,
            updatedAt: created.updatedAt,
          ),
        );
        clock.advance(const Duration(hours: 1));
        final existing = await dates.getForPerson(created.id);
        final keep = existing.firstWhere((d) => d.label == 'Hari jadi');
        final edited = (await save(
          id: created.id,
          input: const PersonInput(name: 'Budi C.', category: 'family'),
          dates: [
            PersonDateInput.of(keep).let(
              (d) => PersonDateInput(
                id: d.id,
                label: d.label,
                month: d.month,
                day: 13,
              ),
            ),
            const PersonDateInput(label: 'Baru', month: 3, day: 3),
          ],
        )).valueOrThrow;
        expect(edited.hasNotes, isTrue);
        expect(edited.notesLength, 12);
        expect(edited.createdAt, created.createdAt);
        final now = await dates.getForPerson(created.id);
        expect(now.map((d) => d.label).toSet(), {'Hari jadi', 'Baru'});
        expect(now.firstWhere((d) => d.label == 'Hari jadi').day, 13);
        expect(now.firstWhere((d) => d.label == 'Hari jadi').id, keep.id);
      },
    );

    test('invalid input writes nothing', () async {
      final r = await save(
        input: const PersonInput(name: 'Budi Contoh', birthDay: 5),
        dates: const [PersonDateInput(label: 'ok', month: 6, day: 12)],
      );
      expect(r.failureOrNull, isA<ValidationFailure>());
      expect(people.s.items, isEmpty);
      expect(dates.s.items, isEmpty);
      final r2 = await save(
        input: const PersonInput(name: 'Budi Contoh'),
        dates: const [PersonDateInput(label: 'rusak', month: 2, day: 30)],
      );
      expect(r2.failureOrNull, isA<ValidationFailure>());
      expect(
        people.s.items,
        isEmpty,
        reason: 'dates validated before any write',
      );
    });

    test('delete removes the person; unknown id is NotFound', () async {
      final p = (await save(
        input: const PersonInput(name: 'Budi Contoh'),
      )).valueOrThrow;
      expect((await DeletePerson(people)(p.id)).isOk, isTrue);
      expect(people.s.items, isEmpty);
      expect(
        (await DeletePerson(people)(p.id)).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });

    test(
      'categories and fields: unique keys, append order, rename keeps the key',
      () async {
        final create = CreatePersonCategory(cats, clock);
        final a = (await create(label: 'Kos', emoji: '🏠')).valueOrThrow;
        final b = (await create(label: 'Kos!', emoji: '🏘️')).valueOrThrow;
        expect([a.key, b.key], ['kos', 'kos_2']);
        expect(b.sortOrder, a.sortOrder + 1);
        expect((await create(label: '  ', emoji: '🏠')).isOk, isFalse);
        expect((await create(label: 'x', emoji: '')).isOk, isFalse);
        final renamed = (await UpdatePersonCategory(cats, clock)(
          a.id,
          label: 'Anak kos',
          emoji: '🏠',
        )).valueOrThrow;
        expect(renamed.key, 'kos');
        expect(renamed.label, 'Anak kos');
        await ReorderPersonCategories(cats, uow, clock)([
          b.id,
          a.id,
          'pc_u1_family',
        ]);
        expect((await cats.getAll()).map((c) => c.key), [
          'kos_2',
          'kos',
          'family',
        ]);

        final createField = CreatePersonField(fields, clock);
        final f = (await createField(
          const PersonFieldInput(
            label: 'Golongan darah',
            type: PersonFieldType.select,
            options: ['A', 'B', 'A', ' '],
          ),
        )).valueOrThrow;
        expect(f.key, 'golongan_darah');
        expect(f.options, ['A', 'B']);
        expect(
          (await createField(
            const PersonFieldInput(
              label: 'Pilihan',
              type: PersonFieldType.select,
            ),
          )).isOk,
          isFalse,
        );
        final f2 = (await createField(
          const PersonFieldInput(label: 'Golongan Darah'),
        )).valueOrThrow;
        expect(f2.key, 'golongan_darah_2');
        final upd = (await UpdatePersonField(fields, clock)(
          f.id,
          label: 'Gol. darah',
          showInList: true,
        )).valueOrThrow;
        expect(
          [upd.key, upd.type, upd.options, upd.label, upd.showInList],
          [
            'golongan_darah',
            PersonFieldType.select,
            ['A', 'B'],
            'Gol. darah',
            true,
          ],
        );
      },
    );

    test(
      'notes use cases: size cap, empty append, success refreshes the pending edit',
      () async {
        final notes = FakePeopleNotes();
        final sync = _NoSync();
        final p = (await save(
          input: const PersonInput(name: 'Budi Contoh'),
        )).valueOrThrow;
        final replace = ReplacePersonNotes(notes, people, sync);
        final append = AppendPersonNotes(notes, people, sync);
        expect(
          (await replace(p.id, 'x' * 300001)).failureOrNull,
          isA<ValidationFailure>(),
        );
        expect(
          (await append(p.id, '  ')).failureOrNull,
          isA<ValidationFailure>(),
        );
        expect(notes.notes, isEmpty);
        expect((await replace(p.id, '# Hai')).isOk, isTrue);
        expect(people.refreshed, [p.id]);
        expect(sync.syncs, 1);
        expect((await append(p.id, 'tambah', heading: 'H')).isOk, isTrue);
        expect(notes.notes[p.id], '# Hai\n\n## H\ntambah');
      },
    );
  });
}

class _NoSync implements SyncService {
  int syncs = 0;
  @override
  Future<void> syncNow() async => syncs++;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Stream<SyncStatus> watchStatus() => const Stream.empty();
  @override
  Future<void> resetLocalData() async {}
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
