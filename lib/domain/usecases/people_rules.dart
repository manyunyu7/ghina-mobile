/// Pure rules of People ("Orang"): a Dart port of the server's
/// `src/lib/people.ts` (`docs/people.md`) — birthday / next-occurrence math
/// (Feb 29, partial birthdays), validation, custom-field typing, search,
/// grouping and the local notification schedule. No Flutter, no I/O. Messages
/// are Indonesian; limits and algorithms match the server.
library;

import '../../core/failure.dart';
import '../entities/entities.dart';

// ---------------------------------------------------------------- limits

const personNameMax = 120;
const personFullNameMax = 200;
const personRelationMax = 120;
const personStatusMax = 300;
const personHowMetMax = 300;
const personSummaryMax = 1000;
const personPhoneMax = 40;
const personInstagramMax = 60;
const personEmailMax = 200;
const personAddressMax = 300;
const personOrganizationMax = 200;
const personNotesMax = 300000;

const minBirthYear = 1900;
const personTagsMax = 20;
const personTagMax = 40;
const personFieldsMaxKeys = 60;
const personFieldValueMax = 2000;
const fieldLabelMax = 80;
const fieldOptionMax = 80;
const fieldOptionsMax = 50;
const dateLabelMax = 80;
const personCategoryLabelMax = 60;
const personCategoryEmojiMax = 8;

/// Key shape of categories and custom fields.
final keyRe = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// The category every person falls back to; it cannot be deleted.
const otherCategoryKey = 'other';

/// How many days ahead the "Ulang tahun & tanggal penting terdekat" card looks.
const upcomingPeopleDays = 60;

/// Local time of the birthday / important-date notifications.
const peopleReminderHour = 9;

/// How far ahead notifications are computed (shares the 60-notification cap).
const peopleReminderWindowDays = 90;

String peopleRoute(String id) => '/people/$id';

// ---------------------------------------------------------------- dates

bool isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

/// Days in [month] (1–12); February has 29 when [year] is null (so Feb 29 is a
/// valid birthday).
int daysInMonthOf(int month, [int? year]) {
  if (month == 2) return year == null || isLeapYear(year) ? 29 : 28;
  return const [4, 6, 9, 11].contains(month) ? 30 : 31;
}

String _pad(int n) => n.toString().padLeft(2, '0');
String _keyOf(int y, int m, int d) => '$y-${_pad(m)}-${_pad(d)}';

int _dayNumber(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ 86400000;
}

/// `YYYY-MM-DD` of a local day.
String peopleDateKey(DateTime d) => _keyOf(d.year, d.month, d.day);

/// A real calendar date `YYYY-MM-DD`.
bool isRealDateKey(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  return mo >= 1 && mo <= 12 && d >= 1 && d <= daysInMonthOf(mo, y);
}

/// First problem with a (possibly partial) birthday, or null. Rules: the day
/// needs a month; month 1–12; the day a real day of that month (Feb 29 is
/// allowed, but not with a known non-leap year); year [minBirthYear]..
/// [currentYear].
String? birthdayError({
  int? year,
  int? month,
  int? day,
  required int currentYear,
}) {
  if (year != null && (year < minBirthYear || year > currentYear)) {
    return 'Tahun harus antara $minBirthYear dan $currentYear';
  }
  if (month != null && (month < 1 || month > 12)) {
    return 'Bulan harus 1–12';
  }
  if (day != null) {
    if (month == null) return 'Tanggal butuh bulan';
    if (day < 1 || day > 31) return 'Tanggal harus 1–31';
    if (day > daysInMonthOf(month, year)) {
      return 'Tanggal itu nggak ada di kalender';
    }
  }
  return null;
}

/// Month/day/year of an important date: problem or null (same rules as the
/// birthday, but month and day are both required).
String? dateError({
  required int month,
  required int day,
  int? year,
  required int currentYear,
}) =>
    birthdayError(year: year, month: month, day: day, currentYear: currentYear);

/// The day a birthday falls on in [year]: Feb 29 becomes Feb 28 in non-leap
/// years.
String birthdayInYear(int month, int day, int year) {
  final d = month == 2 && day == 29 && !isLeapYear(year) ? 28 : day;
  return _keyOf(year, month, d);
}

/// Next occurrence of a month/day on or after [todayKey] (`YYYY-MM-DD`, the
/// user's local date). [yearsSince] is the age turned / years since the start
/// year, null when [year] is unknown.
({String nextDate, int daysUntil, int? yearsSince}) nextAnnualOccurrence(
  int month,
  int day,
  int? year,
  String todayKey,
) {
  final ty = int.parse(todayKey.substring(0, 4));
  var next = birthdayInYear(month, day, ty);
  if (next.compareTo(todayKey) < 0) next = birthdayInYear(month, day, ty + 1);
  return (
    nextDate: next,
    daysUntil: _dayNumber(next) - _dayNumber(todayKey),
    yearsSince: year == null ? null : int.parse(next.substring(0, 4)) - year,
  );
}

typedef _Src = ({
  String? dateId,
  String personId,
  String name,
  String label,
  EventKind kind,
  int month,
  int day,
  int? year,
});

List<_Src> _sources(Iterable<Person> people, Iterable<PersonDate> dates) {
  final out = <_Src>[];
  final names = {for (final p in people) p.id: p.name};
  for (final p in people) {
    if (p.birthMonth == null || p.birthDay == null) continue;
    out.add((
      dateId: null,
      personId: p.id,
      name: p.name,
      label: EventKind.birthday.label,
      kind: EventKind.birthday,
      month: p.birthMonth!,
      day: p.birthDay!,
      year: p.birthYear,
    ));
  }
  for (final d in dates) {
    final name = names[d.personId];
    if (name == null) continue;
    out.add((
      dateId: d.id,
      personId: d.personId,
      name: name,
      label: d.label,
      kind: d.kind.eventKind,
      month: d.month,
      day: d.day,
      year: d.year,
    ));
  }
  return out;
}

/// Birthdays AND important dates whose next occurrence is within [days]
/// (0 = today only), soonest first.
List<UpcomingEvent> upcomingEvents(
  Iterable<Person> people,
  Iterable<PersonDate> dates,
  String todayKey,
  int days,
) {
  final out = <UpcomingEvent>[];
  for (final s in _sources(people, dates)) {
    final n = nextAnnualOccurrence(s.month, s.day, s.year, todayKey);
    if (n.daysUntil > days) continue;
    out.add(
      UpcomingEvent(
        dateId: s.dateId,
        personId: s.personId,
        name: s.name,
        label: s.label,
        kind: s.kind,
        month: s.month,
        day: s.day,
        year: s.year,
        nextDate: n.nextDate,
        daysUntil: n.daysUntil,
        yearsSince: n.yearsSince,
      ),
    );
  }
  out.sort((a, b) {
    var c = a.daysUntil.compareTo(b.daysUntil);
    if (c == 0) c = a.name.compareTo(b.name);
    if (c == 0) c = a.label.compareTo(b.label);
    return c;
  });
  return out;
}

/// Every birthday / important date landing in [fromKey]..[toKey] (inclusive) —
/// the calendar overlay. Spans year boundaries.
List<EventOccurrence> eventsInRange(
  Iterable<Person> people,
  Iterable<PersonDate> dates,
  String fromKey,
  String toKey,
) {
  final out = <EventOccurrence>[];
  final y0 = int.parse(fromKey.substring(0, 4));
  final y1 = int.parse(toKey.substring(0, 4));
  for (final s in _sources(people, dates)) {
    for (var y = y0; y <= y1; y++) {
      final key = birthdayInYear(s.month, s.day, y);
      if (key.compareTo(fromKey) < 0 || key.compareTo(toKey) > 0) continue;
      out.add(
        EventOccurrence(
          dateId: s.dateId,
          personId: s.personId,
          name: s.name,
          label: s.label,
          kind: s.kind,
          dateKey: key,
          yearsSince: s.year == null ? null : y - s.year!,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = a.dateKey.compareTo(b.dateKey);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}

/// Occurrences grouped by day key (for the calendar grid).
Map<String, List<EventOccurrence>> occurrencesByDay(
  Iterable<EventOccurrence> list,
) {
  final out = <String, List<EventOccurrence>>{};
  for (final o in list) {
    (out[o.dateKey] ??= []).add(o);
  }
  return out;
}

const _monthNames = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String monthNameId(int month) => _monthNames[month - 1];

/// "5 Mei 1990" / "5 Mei" (no year) / "Mei 1990" (no day) / "1990" (year only)
/// / "Mei"; null when nothing is set.
String? formatBirthday({int? year, int? month, int? day}) {
  final m = month != null ? _monthNames[month - 1] : null;
  final parts = [
    if (day != null && m != null) '$day',
    ?m,
    if (year != null) '$year',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// "5 Mei" / "5 Mei 2010" of an important date.
String formatDayMonth(int month, int day, [int? year]) =>
    '$day ${_monthNames[month - 1]}${year == null ? '' : ' $year'}';

/// "Hari ini", "Besok", "5 hari lagi".
String daysUntilLabel(int daysUntil) => switch (daysUntil) {
  0 => 'Hari ini',
  1 => 'Besok',
  _ => '$daysUntil hari lagi',
};

/// "Ulang tahun ke-35" (birthday) / "Tahun ke-10" (others); null without year.
String? yearsLabel(EventKind kind, int? yearsSince) {
  if (yearsSince == null || yearsSince < 0) return null;
  if (kind == EventKind.birthday) return 'Ke-$yearsSince';
  return '$yearsSince tahun';
}

// ---------------------------------------------------------------- tags

/// Trim, drop empties, dedupe case-insensitively (the first spelling wins).
/// Throws [ValidationFailure] (`tags`) past the limits.
List<String> normalizeTags(Iterable<String> raw) {
  final seen = <String>{};
  final tags = <String>[];
  for (final t in raw) {
    final v = t.trim();
    if (v.isEmpty) continue;
    if (v.length > personTagMax) {
      throw const ValidationFailure(
        'Tag terlalu panjang (maks $personTagMax karakter)',
        field: 'tags',
      );
    }
    if (!seen.add(v.toLowerCase())) continue;
    tags.add(v);
  }
  if (tags.length > personTagsMax) {
    throw const ValidationFailure(
      'Terlalu banyak tag (maks $personTagsMax)',
      field: 'tags',
    );
  }
  return tags;
}

// ---------------------------------------------------------------- custom fields

final _urlRe = RegExp(r'^https?://[^\s]+$', caseSensitive: false);
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// "ukuran sepatu" / "Ukuran-Sepatu" → "ukuran_sepatu" (a valid key), or null
/// when nothing usable is left.
String? slugifyKey(String raw) {
  // Strip diacritics for the common Latin letters (no `unorm` in pure Dart).
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  var k = raw.toLowerCase();
  final b = StringBuffer();
  for (final r in k.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  k = b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (k.isEmpty) return null;
  if (!RegExp(r'^[a-z]').hasMatch(k)) k = 'f_$k';
  if (k.length > 40) k = k.substring(0, 40);
  k = k.replaceAll(RegExp(r'_+$'), '');
  return keyRe.hasMatch(k) ? k : null;
}

/// "ukuran_sepatu" → "Ukuran sepatu".
String prettifyKey(String key) {
  final s = key.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return s.isEmpty ? key : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Validates and normalizes one value for [def]; returns the value to store
/// (trimmed text / number / bool) or throws a [ValidationFailure] (`fields`).
Object checkFieldValue(PersonFieldDef def, Object? value) {
  final label = def.label;
  ValidationFailure fail(String m) => ValidationFailure(m, field: 'fields');
  String str([int max = personFieldValueMax]) {
    if (value is! String) throw fail('$label harus berupa teks');
    final v = value.trim();
    if (v.isEmpty) throw fail('$label nggak boleh kosong');
    if (v.length > max) throw fail('$label terlalu panjang (maks $max)');
    return v;
  }

  switch (def.type) {
    case PersonFieldType.text:
    case PersonFieldType.longtext:
      return str();
    case PersonFieldType.phone:
      return str(personPhoneMax);
    case PersonFieldType.email:
      final v = str(personEmailMax);
      if (!_emailRe.hasMatch(v)) throw fail('$label harus berupa email');
      return v;
    case PersonFieldType.url:
      final v = str();
      if (!_urlRe.hasMatch(v)) throw fail('$label harus berupa tautan http(s)');
      return v;
    case PersonFieldType.date:
      final v = str(10);
      if (!isRealDateKey(v)) throw fail('$label harus berupa tanggal');
      return v;
    case PersonFieldType.number:
      if (value is num && value.isFinite) return value;
      throw fail('$label harus berupa angka');
    case PersonFieldType.boolean:
      if (value is bool) return value;
      throw fail('$label harus Ya atau Tidak');
    case PersonFieldType.select:
      final v = str(fieldOptionMax);
      if (!(def.options ?? const []).contains(v)) {
        throw fail(
          '$label harus salah satu: ${(def.options ?? []).join(', ')}',
        );
      }
      return v;
  }
}

/// Validates a whole fields map against the defs: every key needs a def and
/// every value must fit its type; ≤ 60 keys. Null values are dropped. Values
/// of defs that don't apply to the person's category are kept (switching
/// category never loses data).
Map<String, FieldValue> validateFields(
  Map<String, Object?> fields,
  Iterable<PersonFieldDef> defs,
) {
  if (fields.length > personFieldsMaxKeys) {
    throw const ValidationFailure(
      'Terlalu banyak kolom ($personFieldsMaxKeys maks)',
      field: 'fields',
    );
  }
  final byKey = {for (final d in defs) d.key: d};
  final out = <String, FieldValue>{};
  for (final e in fields.entries) {
    final def = byKey[e.key];
    if (def == null) {
      throw ValidationFailure('Kolom "${e.key}" belum ada', field: 'fields');
    }
    if (e.value == null) continue;
    out[e.key] = checkFieldValue(def, e.value);
  }
  return out;
}

/// Whether [def] (with its current type/options) still accepts every value —
/// the retype / options-edit safety check.
bool defStillFits(PersonFieldDef def, Iterable<Object?> values) {
  for (final v in values) {
    try {
      checkFieldValue(def, v);
    } on ValidationFailure {
      return false;
    }
  }
  return true;
}

/// Display text of a stored value ("Ya", "5 Mei 1990", "38").
String formatFieldValue(PersonFieldDef def, FieldValue? value) {
  if (value == null) return '';
  if (def.type == PersonFieldType.boolean) {
    return value == true ? 'Ya' : 'Tidak';
  }
  if (def.type == PersonFieldType.date &&
      value is String &&
      isRealDateKey(value)) {
    final p = value.split('-').map(int.parse).toList();
    return '${p[2]} ${_monthNames[p[1] - 1]} ${p[0]}';
  }
  if (value is num && value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return '$value';
}

/// Defs shown for a person of [category] (appliesTo null/empty = all), in
/// definition order.
List<PersonFieldDef> defsFor(Iterable<PersonFieldDef> defs, String category) =>
    [
      for (final d in sortedFieldDefs(defs))
        if (d.appliesToCategory(category)) d,
    ];

List<PersonFieldDef> sortedFieldDefs(Iterable<PersonFieldDef> defs) => [...defs]
  ..sort((a, b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    return c != 0 ? c : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });

// ---------------------------------------------------------------- person input

/// The editable metadata of a person (the form). Notes are not part of it.
final class PersonInput {
  const PersonInput({
    required this.name,
    this.fullName,
    this.category = otherCategoryKey,
    this.relation,
    this.vibe = PersonVibe.unknown,
    this.status,
    this.howMet,
    this.summary,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.phone,
    this.instagram,
    this.email,
    this.address,
    this.organization,
    this.dataStatus = PersonDataStatus.sparse,
    this.sensitive = false,
    this.tags = const [],
    this.fields = const {},
  });

  final String name;
  final String? fullName;
  final String category;
  final String? relation;
  final PersonVibe vibe;
  final String? status;
  final String? howMet;
  final String? summary;
  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;
  final String? phone;
  final String? instagram;
  final String? email;
  final String? address;
  final String? organization;
  final PersonDataStatus dataStatus;
  final bool sensitive;
  final List<String> tags;
  final Map<String, Object?> fields;

  /// A form seeded from an existing person.
  factory PersonInput.of(Person p) => PersonInput(
    name: p.name,
    fullName: p.fullName,
    category: p.category,
    relation: p.relation,
    vibe: p.vibe,
    status: p.status,
    howMet: p.howMet,
    summary: p.summary,
    birthYear: p.birthYear,
    birthMonth: p.birthMonth,
    birthDay: p.birthDay,
    phone: p.phone,
    instagram: p.instagram,
    email: p.email,
    address: p.address,
    organization: p.organization,
    dataStatus: p.dataStatus,
    sensitive: p.sensitive,
    tags: p.tags,
    fields: p.fields,
  );
}

/// An important date being edited (the form). [id] null = new.
final class PersonDateInput {
  const PersonDateInput({
    this.id,
    required this.label,
    this.kind = PersonDateKind.custom,
    required this.month,
    required this.day,
    this.year,
    this.remindDaysBefore,
  });

  final String? id;
  final String label;
  final PersonDateKind kind;
  final int month;
  final int day;
  final int? year;
  final int? remindDaysBefore;

  factory PersonDateInput.of(PersonDate d) => PersonDateInput(
    id: d.id,
    label: d.label,
    kind: d.kind,
    month: d.month,
    day: d.day,
    year: d.year,
    remindDaysBefore: d.remindDaysBefore,
  );
}

String _required(String? v, int max, String what, String field) {
  final s = (v ?? '').trim();
  if (s.isEmpty) throw ValidationFailure('$what wajib diisi', field: field);
  if (s.length > max) {
    throw ValidationFailure(
      '$what terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

String? _optional(String? v, int max, String what, String field) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (s.length > max) {
    throw ValidationFailure(
      '$what terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

/// Validated, normalized form of [input] (mirrors `personSchema`): lengths,
/// the partial birthday, tags, the category (must be one of [categoryKeys],
/// `other` always passes) and the custom fields (must fit [defs]).
Person validatePerson({
  required String id,
  required PersonInput input,
  required Iterable<String> categoryKeys,
  required Iterable<PersonFieldDef> defs,
  required int currentYear,
  required DateTime createdAt,
  required DateTime updatedAt,
  bool hasNotes = false,
  int notesLength = 0,
}) {
  final name = _required(input.name, personNameMax, 'Nama', 'name');
  final err = birthdayError(
    year: input.birthYear,
    month: input.birthMonth,
    day: input.birthDay,
    currentYear: currentYear,
  );
  if (err != null) throw ValidationFailure(err, field: 'birthday');
  final category = input.category.trim().isEmpty
      ? otherCategoryKey
      : input.category.trim();
  if (category != otherCategoryKey && !categoryKeys.contains(category)) {
    throw const ValidationFailure('Kategori nggak ketemu', field: 'category');
  }
  final email = _optional(input.email, personEmailMax, 'Email', 'email');
  if (email != null && !_emailRe.hasMatch(email)) {
    throw const ValidationFailure('Email nggak valid', field: 'email');
  }
  return Person(
    id: id,
    name: name,
    fullName: _optional(
      input.fullName,
      personFullNameMax,
      'Nama lengkap',
      'fullName',
    ),
    category: category,
    relation: _optional(
      input.relation,
      personRelationMax,
      'Hubungan',
      'relation',
    ),
    vibe: input.vibe,
    status: _optional(input.status, personStatusMax, 'Status', 'status'),
    howMet: _optional(input.howMet, personHowMetMax, 'Kenal dari', 'howMet'),
    summary: _optional(input.summary, personSummaryMax, 'Ringkasan', 'summary'),
    birthYear: input.birthYear,
    birthMonth: input.birthMonth,
    birthDay: input.birthDay,
    phone: _optional(input.phone, personPhoneMax, 'Telepon', 'phone'),
    instagram: _optional(
      input.instagram,
      personInstagramMax,
      'Instagram',
      'instagram',
    ),
    email: email,
    address: _optional(input.address, personAddressMax, 'Alamat', 'address'),
    organization: _optional(
      input.organization,
      personOrganizationMax,
      'Organisasi',
      'organization',
    ),
    dataStatus: input.dataStatus,
    sensitive: input.sensitive,
    tags: normalizeTags(input.tags),
    fields: validateFields(input.fields, defs),
    hasNotes: hasNotes,
    notesLength: notesLength,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Validated important date (mirrors `personDateSchema`).
PersonDate validatePersonDate({
  required String id,
  required String personId,
  required PersonDateInput input,
  required int currentYear,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  final label = _required(input.label, dateLabelMax, 'Label', 'label');
  final err = dateError(
    month: input.month,
    day: input.day,
    year: input.year,
    currentYear: currentYear,
  );
  if (err != null) throw ValidationFailure(err, field: 'date');
  final r = input.remindDaysBefore;
  if (r != null && (r < 0 || r > 365)) {
    throw const ValidationFailure(
      'Pengingat harus 0–365 hari sebelumnya',
      field: 'remindDaysBefore',
    );
  }
  return PersonDate(
    id: id,
    personId: personId,
    label: label,
    kind: input.kind,
    month: input.month,
    day: input.day,
    year: input.year,
    remindDaysBefore: r,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Validated category label/emoji; throws on a bad label or emoji.
({String label, String emoji}) validateCategoryText(
  String? label,
  String? emoji,
) {
  final l = _required(label, personCategoryLabelMax, 'Nama kategori', 'label');
  final e = (emoji ?? '').trim();
  if (e.isEmpty) {
    throw const ValidationFailure('Emoji wajib diisi', field: 'emoji');
  }
  if (e.length > personCategoryEmojiMax) {
    throw const ValidationFailure('Emoji terlalu panjang', field: 'emoji');
  }
  return (label: l, emoji: e);
}

/// Validated custom-field label.
String validateFieldLabel(String? label) =>
    _required(label, fieldLabelMax, 'Nama kolom', 'label');

/// Validated, deduplicated select options (1–50 × ≤ 80).
List<String> validateOptions(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final o in raw) {
    final v = o.trim();
    if (v.isEmpty || !seen.add(v)) continue;
    if (v.length > fieldOptionMax) {
      throw const ValidationFailure(
        'Pilihan terlalu panjang (maks $fieldOptionMax karakter)',
        field: 'options',
      );
    }
    out.add(v);
  }
  if (out.isEmpty) {
    throw const ValidationFailure(
      'Kolom pilihan butuh minimal satu pilihan',
      field: 'options',
    );
  }
  if (out.length > fieldOptionsMax) {
    throw const ValidationFailure(
      'Terlalu banyak pilihan (maks $fieldOptionsMax)',
      field: 'options',
    );
  }
  return out;
}

// ---------------------------------------------------------------- search + grouping

/// Case-insensitive text a search runs over: name, full name, relation,
/// summary, status, how met, organization, address, tags and the displayed
/// custom-field values.
String personSearchText(Person p, [Iterable<PersonFieldDef> defs = const []]) {
  final byKey = {for (final d in defs) d.key: d};
  return [
    p.name,
    p.fullName,
    p.relation,
    p.summary,
    p.status,
    p.howMet,
    p.organization,
    p.address,
    ...p.tags,
    for (final e in p.fields.entries)
      byKey[e.key] == null
          ? '${e.value}'
          : formatFieldValue(byKey[e.key]!, e.value),
  ].whereType<String>().join('\n').toLowerCase();
}

/// Every whitespace-separated word of [query] must appear (empty matches all).
bool personMatches(
  Person p,
  String query, [
  Iterable<PersonFieldDef> defs = const [],
]) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final hay = personSearchText(p, defs);
  return words.every(hay.contains);
}

/// All tags of [people], most used first then alphabetical (case-insensitive
/// dedupe, first spelling wins).
List<String> allTags(Iterable<Person> people) {
  final counts = <String, int>{};
  final spelling = <String, String>{};
  for (final p in people) {
    for (final t in p.tags) {
      final k = t.toLowerCase();
      spelling.putIfAbsent(k, () => t);
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final k in keys) spelling[k]!];
}

/// Filters by [query] and [tag], then groups by category in category order
/// (unknown category keys get their own group after the known ones). Empty
/// groups are left out; people are sorted by name.
List<PeopleGroup> groupPeople(
  Iterable<Person> people,
  Iterable<PersonCategory> categories, {
  Iterable<PersonFieldDef> defs = const [],
  String query = '',
  String? tag,
}) {
  final tagKey = tag?.toLowerCase();
  final list = [
    for (final p in people)
      if ((tagKey == null || p.tags.any((t) => t.toLowerCase() == tagKey)) &&
          personMatches(p, query, defs))
        p,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final cats = [...categories]
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
  final known = {for (final c in cats) c.key};
  final groups = <PeopleGroup>[];
  for (final c in cats) {
    final ps = [
      for (final p in list)
        if (p.category == c.key) p,
    ];
    if (ps.isNotEmpty) {
      groups.add(
        PeopleGroup(
          categoryKey: c.key,
          label: c.label,
          emoji: c.emoji,
          people: ps,
        ),
      );
    }
  }
  final unknownKeys = {
    for (final p in list)
      if (!known.contains(p.category)) p.category,
  }.toList()..sort();
  for (final k in unknownKeys) {
    groups.add(
      PeopleGroup(
        categoryKey: k,
        label: k == otherCategoryKey ? 'Lainnya' : prettifyKey(k),
        emoji: '👤',
        people: [
          for (final p in list)
            if (p.category == k) p,
        ],
      ),
    );
  }
  return groups;
}

// ---------------------------------------------------------------- notifications

String _stamp(String dateKey) => dateKey.replaceAll('-', '');

/// Local notifications for birthdays and important dates: 09:00 local on the
/// day, plus 09:00 [PersonDate.remindDaysBefore] days earlier when set. Only
/// people with both month and day (important dates always have both);
/// Feb 29 falls on Feb 28 in non-leap years. Only times after [now] and within
/// [peopleReminderWindowDays]; the caller merges and caps them with the other
/// reminders.
List<Reminder> computePeopleReminders(
  Iterable<Person> people,
  Iterable<PersonDate> dates,
  DateTime now,
) {
  final out = <Reminder>[];
  final limit = now.add(const Duration(days: peopleReminderWindowDays));
  final byId = {for (final p in people) p.id: p};
  final dateById = {for (final d in dates) d.id: d};
  for (final s in _sources(people, dates)) {
    final person = byId[s.personId];
    if (person == null) continue;
    final remind = s.dateId == null
        ? null
        : dateById[s.dateId]?.remindDaysBefore;
    for (var y = now.year; y <= now.year + 1; y++) {
      final key = birthdayInYear(s.month, s.day, y);
      final p = key.split('-').map(int.parse).toList();
      final dayFire = DateTime(p[0], p[1], p[2], peopleReminderHour);
      final years = s.year == null ? null : y - s.year!;
      final base = s.dateId == null
          ? 'birthday:${s.personId}'
          : 'date:${s.dateId}';
      final route = peopleRoute(s.personId);
      final title = s.kind == EventKind.birthday
          ? '${s.kind.emoji} Ulang tahun ${s.name}'
          : '${s.kind.emoji} ${s.label} · ${s.name}';

      void add(DateTime fireAt, String suffix, String body) {
        if (!fireAt.isAfter(now) || fireAt.isAfter(limit)) return;
        out.add(
          Reminder(
            key: 'person:$base:${_stamp(key)}$suffix',
            title: title,
            body: body,
            fireAt: fireAt,
            route: route,
          ),
        );
      }

      final age = yearsLabel(s.kind, years);
      add(
        dayFire,
        '',
        s.kind == EventKind.birthday
            ? (years != null && years >= 0
                  ? 'Hari ini ulang tahunnya yang ke-$years 🎉'
                  : 'Hari ini ulang tahunnya 🎉')
            : (age == null ? 'Hari ini' : 'Hari ini · $age'),
      );
      if (remind != null && remind > 0) {
        final before = DateTime(p[0], p[1], p[2] - remind, peopleReminderHour);
        add(
          before,
          ':b$remind',
          remind == 1 ? 'Besok: ${s.label}' : '$remind hari lagi: ${s.label}',
        );
      }
    }
  }
  return out;
}
