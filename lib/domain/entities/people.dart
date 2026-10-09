/// People ("Orang", `docs/people.md`): contacts with partial birthdays, tags,
/// custom fields and important dates. Notes (markdown) are **not** part of
/// these entities: they live on the server only (online-only, see
/// `PeopleNotesRepository`).
library;

import 'value_equality.dart';

/// How the user feels about the relationship. Wire values never grow here;
/// an unknown future value reads as [unknown].
enum PersonVibe {
  positive('positive', 'Positif', '💕'),
  neutral('neutral', 'Netral', '😐'),
  negative('negative', 'Negatif', '😤'),
  caution('caution', 'Hati-hati', '⚠️'),
  closed('closed', 'Tertutup', '🚫'),
  unknown('unknown', 'Belum tahu', '❓');

  const PersonVibe(this.wire, this.label, this.emoji);
  final String wire;
  final String label;
  final String emoji;

  static PersonVibe fromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return unknown;
  }
}

/// How complete the user's knowledge of the person is.
enum PersonDataStatus {
  sparse('sparse', 'Minim'),
  partial('partial', 'Sebagian'),
  good('good', 'Lengkap');

  const PersonDataStatus(this.wire, this.label);
  final String wire;
  final String label;

  static PersonDataStatus fromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return sparse;
  }
}

/// Type of a custom field (`personFields`).
enum PersonFieldType {
  text('text', 'Teks'),
  longtext('longtext', 'Teks panjang'),
  number('number', 'Angka'),
  date('date', 'Tanggal'),
  url('url', 'Tautan'),
  phone('phone', 'Telepon'),
  email('email', 'Email'),
  select('select', 'Pilihan'),
  boolean('boolean', 'Ya/Tidak');

  const PersonFieldType(this.wire, this.label);
  final String wire;
  final String label;

  /// Null for a type this app doesn't know (a newer server).
  static PersonFieldType? tryFromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return null;
  }
}

/// Kind of an important date (the birthday is not one: it lives on the person).
enum PersonDateKind {
  anniversary('anniversary'),
  memorial('memorial'),
  custom('custom');

  const PersonDateKind(this.wire);
  final String wire;

  static PersonDateKind fromWire(String? v) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
    return custom;
  }

  EventKind get eventKind => switch (this) {
    anniversary => EventKind.anniversary,
    memorial => EventKind.memorial,
    custom => EventKind.custom,
  };
}

/// What an upcoming/calendar entry is: the birthday or an important date.
enum EventKind {
  birthday('Ulang tahun', '🎂'),
  anniversary('Hari jadi', '💍'),
  memorial('Peringatan', '🕊️'),
  custom('Lainnya', '📌');

  const EventKind(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// A custom field value: `String`, `num` or `bool`.
typedef FieldValue = Object;

/// A category of people (`personCategories`). [key] is immutable; [label] and
/// [emoji] can be renamed.
final class PersonCategory with ValueEquality {
  const PersonCategory({
    required this.id,
    required this.key,
    required this.label,
    required this.emoji,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String key;
  final String label;
  final String emoji;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonCategory copyWith({
    String? label,
    String? emoji,
    int? sortOrder,
    DateTime? updatedAt,
  }) => PersonCategory(
    id: id,
    key: key,
    label: label ?? this.label,
    emoji: emoji ?? this.emoji,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    label,
    emoji,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'PersonCategory($key)';
}

/// A custom-field definition (`personFields`): a column every person can fill.
final class PersonFieldDef with ValueEquality {
  const PersonFieldDef({
    required this.id,
    required this.key,
    required this.label,
    this.type = PersonFieldType.text,
    this.options,
    this.appliesTo,
    this.sortOrder = 0,
    this.showInList = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Slug `^[a-z][a-z0-9_]{0,39}$`, immutable.
  final String key;
  final String label;
  final PersonFieldType type;

  /// `select` only.
  final List<String>? options;

  /// Category keys; null/empty = every category.
  final List<String>? appliesTo;
  final int sortOrder;
  final bool showInList;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the def is shown for a person of [category].
  bool appliesToCategory(String category) =>
      appliesTo == null || appliesTo!.isEmpty || appliesTo!.contains(category);

  PersonFieldDef copyWith({
    String? label,
    List<String>? appliesTo,
    int? sortOrder,
    bool? showInList,
    DateTime? updatedAt,
  }) => PersonFieldDef(
    id: id,
    key: key,
    label: label ?? this.label,
    type: type,
    options: options,
    appliesTo: appliesTo ?? this.appliesTo,
    sortOrder: sortOrder ?? this.sortOrder,
    showInList: showInList ?? this.showInList,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    label,
    type,
    options,
    appliesTo,
    sortOrder,
    showInList,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'PersonFieldDef($key, ${type.wire})';
}

/// An important date of a person (`personDates`): anniversary, memorial, custom.
final class PersonDate with ValueEquality {
  const PersonDate({
    required this.id,
    required this.personId,
    required this.label,
    this.kind = PersonDateKind.custom,
    required this.month,
    required this.day,
    this.year,
    this.remindDaysBefore,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String personId;
  final String label;
  final PersonDateKind kind;
  final int month;
  final int day;

  /// Start year (anniversary year); null = unknown.
  final int? year;

  /// 0–365; null = no extra reminder (the day itself always notifies).
  final int? remindDaysBefore;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonDate copyWith({
    String? label,
    PersonDateKind? kind,
    int? month,
    int? day,
    Object? year = _unset,
    Object? remindDaysBefore = _unset,
    DateTime? updatedAt,
  }) => PersonDate(
    id: id,
    personId: personId,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    month: month ?? this.month,
    day: day ?? this.day,
    year: identical(year, _unset) ? this.year : year as int?,
    remindDaysBefore: identical(remindDaysBefore, _unset)
        ? this.remindDaysBefore
        : remindDaysBefore as int?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    personId,
    label,
    kind,
    month,
    day,
    year,
    remindDaysBefore,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'PersonDate($personId, $label $day/$month)';
}

const Object _unset = Object();

/// A person. No notes: those are fetched online (`GET /api/mobile/people/{id}`).
final class Person with ValueEquality {
  const Person({
    required this.id,
    required this.name,
    this.fullName,
    this.category = 'other',
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
    this.hasNotes = false,
    this.notesLength = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? fullName;

  /// A [PersonCategory.key].
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

  /// The notes stay collapsed behind a button; they are only fetched on tap.
  final bool sensitive;
  final List<String> tags;

  /// Custom-field values by [PersonFieldDef.key] (`String | num | bool`).
  final Map<String, FieldValue> fields;

  /// Read-only server mirrors (never pushed).
  final bool hasNotes;
  final int notesLength;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Both month and day known → birthday reminders / upcoming list.
  bool get hasBirthday => birthMonth != null && birthDay != null;

  Person copyWith({
    String? name,
    Object? fullName = _unset,
    String? category,
    Object? relation = _unset,
    PersonVibe? vibe,
    Object? status = _unset,
    Object? howMet = _unset,
    Object? summary = _unset,
    Object? birthYear = _unset,
    Object? birthMonth = _unset,
    Object? birthDay = _unset,
    Object? phone = _unset,
    Object? instagram = _unset,
    Object? email = _unset,
    Object? address = _unset,
    Object? organization = _unset,
    PersonDataStatus? dataStatus,
    bool? sensitive,
    List<String>? tags,
    Map<String, FieldValue>? fields,
    DateTime? updatedAt,
  }) => Person(
    id: id,
    name: name ?? this.name,
    fullName: identical(fullName, _unset) ? this.fullName : fullName as String?,
    category: category ?? this.category,
    relation: identical(relation, _unset) ? this.relation : relation as String?,
    vibe: vibe ?? this.vibe,
    status: identical(status, _unset) ? this.status : status as String?,
    howMet: identical(howMet, _unset) ? this.howMet : howMet as String?,
    summary: identical(summary, _unset) ? this.summary : summary as String?,
    birthYear: identical(birthYear, _unset)
        ? this.birthYear
        : birthYear as int?,
    birthMonth: identical(birthMonth, _unset)
        ? this.birthMonth
        : birthMonth as int?,
    birthDay: identical(birthDay, _unset) ? this.birthDay : birthDay as int?,
    phone: identical(phone, _unset) ? this.phone : phone as String?,
    instagram: identical(instagram, _unset)
        ? this.instagram
        : instagram as String?,
    email: identical(email, _unset) ? this.email : email as String?,
    address: identical(address, _unset) ? this.address : address as String?,
    organization: identical(organization, _unset)
        ? this.organization
        : organization as String?,
    dataStatus: dataStatus ?? this.dataStatus,
    sensitive: sensitive ?? this.sensitive,
    tags: tags ?? this.tags,
    fields: fields ?? this.fields,
    hasNotes: hasNotes,
    notesLength: notesLength,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    fullName,
    category,
    relation,
    vibe,
    status,
    howMet,
    summary,
    birthYear,
    birthMonth,
    birthDay,
    phone,
    instagram,
    email,
    address,
    organization,
    dataStatus,
    sensitive,
    tags,
    fields,
    hasNotes,
    notesLength,
    createdAt,
    updatedAt,
  ];

  @override
  String toString() => 'Person($id, $name)';
}

/// A person's notes as the server has them (online-only).
final class PersonNotes with ValueEquality {
  const PersonNotes({required this.notes, required this.updatedAt});

  /// Markdown, ≤ 300 000 characters.
  final String notes;

  /// Server `updatedAt` of the row when read — the `expectedUpdatedAt` of a
  /// following replace.
  final DateTime updatedAt;

  @override
  List<Object?> get props => [notes, updatedAt];
}

/// Result of a notes write.
final class PersonNotesWrite with ValueEquality {
  const PersonNotesWrite({required this.updatedAt, required this.notesLength});
  final DateTime updatedAt;
  final int notesLength;

  @override
  List<Object?> get props => [updatedAt, notesLength];
}

// ---------------------------------------------------------------- read models

/// A birthday or important date coming up (`upcoming` card).
final class UpcomingEvent with ValueEquality {
  const UpcomingEvent({
    required this.dateId,
    required this.personId,
    required this.name,
    required this.label,
    required this.kind,
    required this.month,
    required this.day,
    required this.year,
    required this.nextDate,
    required this.daysUntil,
    required this.yearsSince,
  });

  /// [PersonDate.id]; null for the birthday.
  final String? dateId;
  final String personId;
  final String name;
  final String label;
  final EventKind kind;
  final int month;
  final int day;
  final int? year;

  /// `YYYY-MM-DD` of the next occurrence (today counts, [daysUntil] 0).
  final String nextDate;
  final int daysUntil;

  /// Age turned (birthday) / years since the start year; null when [year] is
  /// unknown. Show it only then.
  final int? yearsSince;

  @override
  List<Object?> get props => [
    dateId,
    personId,
    name,
    label,
    kind,
    month,
    day,
    year,
    nextDate,
    daysUntil,
    yearsSince,
  ];
}

/// One occurrence of a birthday/important date on a given day (calendar overlay).
final class EventOccurrence with ValueEquality {
  const EventOccurrence({
    required this.dateId,
    required this.personId,
    required this.name,
    required this.label,
    required this.kind,
    required this.dateKey,
    required this.yearsSince,
  });

  final String? dateId;
  final String personId;
  final String name;
  final String label;
  final EventKind kind;
  final String dateKey;
  final int? yearsSince;

  /// `🎂 Budi Contoh` style title.
  String get title => '${kind.emoji} $name';

  @override
  List<Object?> get props => [
    dateId,
    personId,
    name,
    label,
    kind,
    dateKey,
    yearsSince,
  ];
}

/// People grouped by category for the list screen.
final class PeopleGroup with ValueEquality {
  const PeopleGroup({
    required this.categoryKey,
    required this.label,
    required this.emoji,
    required this.people,
  });

  final String categoryKey;
  final String label;
  final String emoji;
  final List<Person> people;

  @override
  List<Object?> get props => [categoryKey, label, emoji, people];
}

/// Everything the People list needs, in one stream: filtering, grouping and
/// the field columns are done in memory (`groupPeople`).
final class PeopleOverview with ValueEquality {
  const PeopleOverview({
    required this.people,
    required this.categories,
    required this.defs,
    required this.dates,
  });

  /// By name.
  final List<Person> people;

  /// In category order.
  final List<PersonCategory> categories;

  /// In field order.
  final List<PersonFieldDef> defs;

  /// Important dates of every person.
  final List<PersonDate> dates;

  bool get isEmpty => people.isEmpty;

  PersonCategory? category(String key) {
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }

  @override
  List<Object?> get props => [people, categories, defs, dates];
}

/// One person with what the detail screen shows around it.
final class PersonDetail with ValueEquality {
  const PersonDetail({
    required this.person,
    required this.category,
    required this.defs,
    required this.dates,
  });

  final Person person;

  /// Null when the key is unknown (shown as "Lainnya").
  final PersonCategory? category;

  /// The defs that apply to the person's category, in field order.
  final List<PersonFieldDef> defs;

  /// The person's important dates (month/day order).
  final List<PersonDate> dates;

  @override
  List<Object?> get props => [person, category, defs, dates];
}
