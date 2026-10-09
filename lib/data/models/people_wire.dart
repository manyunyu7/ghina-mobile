/// JSON wire format of `people`, `personCategories`, `personFields`,
/// `personDates`, `habitFields` and `habitEvents` (`docs/mobile-sync.md`,
/// `docs/people.md`, `docs/habits-food-enrichment.md`) and the drift row ⇄
/// entity mappers.
///
/// `*ToWire` builds the push `data` (full row minus id/createdAt/updatedAt).
/// `people` carries **no notes** (and not the read-only `hasNotes` /
/// `notesLength`): the server drops a pushed `notes` key and the markdown
/// never enters the local database. `*FromWire` parses a pulled row
/// leniently; a null result means "ignore the row" (a newer server).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';
import 'habits_investments_wire.dart' show scalarMapFromJson;
import 'wire.dart' show Json, isoUtc;

// ---------------------------------------------------------------- helpers

Object? _json(Object? v) {
  if (v is String) {
    if (v.isEmpty) return null;
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  return v;
}

DateTime? _dateN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
int? _intN(Object? v) => v is num && v.isFinite ? v.round() : null;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

/// `string[]` (tags, options, appliesTo); non-strings dropped.
List<String> stringListFromJson(Object? raw) {
  final x = _json(raw);
  if (x is! List) return const [];
  return List.unmodifiable([
    for (final e in x)
      if (e is String && e.isNotEmpty) e,
  ]);
}

/// `string[]` or null (options / appliesTo: null stays null).
List<String>? stringListOrNull(Object? raw) {
  if (raw == null) return null;
  final x = _json(raw);
  if (x is! List) return null;
  return List.unmodifiable([
    for (final e in x)
      if (e is String && e.isNotEmpty) e,
  ]);
}

String? _encodeListOrNull(List<String>? v) => v == null ? null : jsonEncode(v);

({DateTime created, DateTime updated})? _stamps(Json j) {
  final created = _dateN(j['createdAt']);
  if (created == null) return null;
  return (created: created, updated: _dateN(j['updatedAt']) ?? created);
}

// ---------------------------------------------------------------- people

Json personToWire(Person p) => {
  'name': p.name,
  'fullName': p.fullName,
  'category': p.category,
  'relation': p.relation,
  'vibe': p.vibe.wire,
  'status': p.status,
  'howMet': p.howMet,
  'summary': p.summary,
  'birthYear': p.birthYear,
  'birthMonth': p.birthMonth,
  'birthDay': p.birthDay,
  'phone': p.phone,
  'instagram': p.instagram,
  'email': p.email,
  'address': p.address,
  'organization': p.organization,
  'dataStatus': p.dataStatus.wire,
  'sensitive': p.sensitive,
  'tags': p.tags,
  'fields': p.fields,
};

/// A pulled person; null when the id is missing.
Person? personFromWire(Json j) {
  final id = _strN(j['id']);
  final st = _stamps(j);
  if (id == null || st == null) return null;
  return Person(
    id: id,
    name: _str(j['name']),
    fullName: _strN(j['fullName']),
    category: _strN(j['category']) ?? 'other',
    relation: _strN(j['relation']),
    vibe: PersonVibe.fromWire(j['vibe'] as String?),
    status: _strN(j['status']),
    howMet: _strN(j['howMet']),
    summary: _strN(j['summary']),
    birthYear: _intN(j['birthYear']),
    birthMonth: _intN(j['birthMonth']),
    birthDay: _intN(j['birthDay']),
    phone: _strN(j['phone']),
    instagram: _strN(j['instagram']),
    email: _strN(j['email']),
    address: _strN(j['address']),
    organization: _strN(j['organization']),
    dataStatus: PersonDataStatus.fromWire(j['dataStatus'] as String?),
    sensitive: _bool(j['sensitive']),
    tags: stringListFromJson(j['tags']),
    fields: scalarMapFromJson(j['fields']),
    hasNotes: _bool(j['hasNotes']),
    notesLength: _intN(j['notesLength']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension PersonRowX on PersonRow {
  Person toEntity() => Person(
    id: id,
    name: name,
    fullName: fullName,
    category: category,
    relation: relation,
    vibe: PersonVibe.fromWire(vibe),
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
    dataStatus: PersonDataStatus.fromWire(dataStatus),
    sensitive: sensitive,
    tags: stringListFromJson(tags),
    fields: scalarMapFromJson(fields),
    hasNotes: hasNotes,
    notesLength: notesLength,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PersonX on Person {
  PeopleCompanion toCompanion() => PeopleCompanion.insert(
    id: id,
    name: name,
    fullName: Value(fullName),
    category: Value(category),
    relation: Value(relation),
    vibe: Value(vibe.wire),
    status: Value(status),
    howMet: Value(howMet),
    summary: Value(summary),
    birthYear: Value(birthYear),
    birthMonth: Value(birthMonth),
    birthDay: Value(birthDay),
    phone: Value(phone),
    instagram: Value(instagram),
    email: Value(email),
    address: Value(address),
    organization: Value(organization),
    dataStatus: Value(dataStatus.wire),
    sensitive: Value(sensitive),
    tags: Value(jsonEncode(tags)),
    fields: Value(jsonEncode(fields)),
    hasNotes: Value(hasNotes),
    notesLength: Value(notesLength),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- categories

Json personCategoryToWire(PersonCategory c) => {
  'key': c.key,
  'label': c.label,
  'emoji': c.emoji,
  'sortOrder': c.sortOrder,
};

PersonCategory? personCategoryFromWire(Json j) {
  final id = _strN(j['id']);
  final key = _strN(j['key']);
  final st = _stamps(j);
  if (id == null || key == null || st == null) return null;
  return PersonCategory(
    id: id,
    key: key,
    label: _str(j['label'], key),
    emoji: _strN(j['emoji']) ?? '👤',
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension PersonCategoryRowX on PersonCategoryRow {
  PersonCategory toEntity() => PersonCategory(
    id: id,
    key: key,
    label: label,
    emoji: emoji,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PersonCategoryX on PersonCategory {
  PersonCategoriesCompanion toCompanion() => PersonCategoriesCompanion.insert(
    id: id,
    key: key,
    label: label,
    emoji: emoji,
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- person fields

Json personFieldToWire(PersonFieldDef d) => {
  'key': d.key,
  'label': d.label,
  'type': d.type.wire,
  'options': d.options,
  'appliesTo': d.appliesTo,
  'sortOrder': d.sortOrder,
  'showInList': d.showInList,
};

/// Null for an unknown `type` (a newer server).
PersonFieldDef? personFieldFromWire(Json j) {
  final id = _strN(j['id']);
  final key = _strN(j['key']);
  final type = PersonFieldType.tryFromWire(j['type'] as String?);
  final st = _stamps(j);
  if (id == null || key == null || type == null || st == null) return null;
  return PersonFieldDef(
    id: id,
    key: key,
    label: _str(j['label'], key),
    type: type,
    options: stringListOrNull(j['options']),
    appliesTo: stringListOrNull(j['appliesTo']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    showInList: _bool(j['showInList']),
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension PersonFieldRowX on PersonFieldRow {
  PersonFieldDef? toEntityOrNull() {
    final t = PersonFieldType.tryFromWire(type);
    if (t == null) return null;
    return PersonFieldDef(
      id: id,
      key: key,
      label: label,
      type: t,
      options: stringListOrNull(options),
      appliesTo: stringListOrNull(appliesTo),
      sortOrder: sortOrder,
      showInList: showInList,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension PersonFieldX on PersonFieldDef {
  PersonFieldsCompanion toCompanion() => PersonFieldsCompanion.insert(
    id: id,
    key: key,
    label: label,
    type: Value(type.wire),
    options: Value(_encodeListOrNull(options)),
    appliesTo: Value(_encodeListOrNull(appliesTo)),
    sortOrder: Value(sortOrder),
    showInList: Value(showInList),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- person dates

Json personDateToWire(PersonDate d) => {
  'personId': d.personId,
  'label': d.label,
  'kind': d.kind.wire,
  'month': d.month,
  'day': d.day,
  'year': d.year,
  'remindDaysBefore': d.remindDaysBefore,
};

PersonDate? personDateFromWire(Json j) {
  final id = _strN(j['id']);
  final personId = _strN(j['personId']);
  final month = _intN(j['month']);
  final day = _intN(j['day']);
  final st = _stamps(j);
  if (id == null ||
      personId == null ||
      month == null ||
      day == null ||
      st == null) {
    return null;
  }
  return PersonDate(
    id: id,
    personId: personId,
    label: _str(j['label']),
    kind: PersonDateKind.fromWire(j['kind'] as String?),
    month: month,
    day: day,
    year: _intN(j['year']),
    remindDaysBefore: _intN(j['remindDaysBefore']),
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension PersonDateRowX on PersonDateRow {
  PersonDate toEntity() => PersonDate(
    id: id,
    personId: personId,
    label: label,
    kind: PersonDateKind.fromWire(kind),
    month: month,
    day: day,
    year: year,
    remindDaysBefore: remindDaysBefore,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PersonDateX on PersonDate {
  PersonDatesCompanion toCompanion() => PersonDatesCompanion.insert(
    id: id,
    personId: personId,
    label: label,
    kind: Value(kind.wire),
    month: month,
    day: day,
    year: Value(year),
    remindDaysBefore: Value(remindDaysBefore),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- habit fields

Json habitFieldToWire(HabitFieldDef d) => {
  'habitId': d.habitId,
  'key': d.key,
  'label': d.label,
  'type': d.type.wire,
  'options': d.options,
  'min': d.min,
  'max': d.max,
  'appliesTo': d.appliesTo,
  'sortOrder': d.sortOrder,
};

/// Null for an unknown `type` (a newer server).
HabitFieldDef? habitFieldFromWire(Json j) {
  final id = _strN(j['id']);
  final key = _strN(j['key']);
  final type = HabitFieldType.tryFromWire(j['type'] as String?);
  final st = _stamps(j);
  if (id == null || key == null || type == null || st == null) return null;
  return HabitFieldDef(
    id: id,
    habitId: _strN(j['habitId']),
    key: key,
    label: _str(j['label'], key),
    type: type,
    options: stringListOrNull(j['options']),
    min: _intN(j['min']),
    max: _intN(j['max']),
    appliesTo: stringListOrNull(j['appliesTo']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension HabitFieldRowX on HabitFieldRow {
  HabitFieldDef? toEntityOrNull() {
    final t = HabitFieldType.tryFromWire(type);
    if (t == null) return null;
    return HabitFieldDef(
      id: id,
      habitId: habitId,
      key: key,
      label: label,
      type: t,
      options: stringListOrNull(options),
      min: scaleMin,
      max: scaleMax,
      appliesTo: stringListOrNull(appliesTo),
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension HabitFieldX on HabitFieldDef {
  HabitFieldsCompanion toCompanion() => HabitFieldsCompanion.insert(
    id: id,
    habitId: Value(habitId),
    key: key,
    label: label,
    type: Value(type.wire),
    options: Value(_encodeListOrNull(options)),
    scaleMin: Value(min),
    scaleMax: Value(max),
    appliesTo: Value(_encodeListOrNull(appliesTo)),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- habit events

Json habitEventToWire(HabitEvent e) => {
  'habitId': e.habitId,
  'date': e.date,
  'kind': e.kind.wire,
  'label': e.label,
  'note': e.note,
  'at': e.at == null ? null : isoUtc(e.at!),
  'extra': e.extra,
};

/// Null for an unknown `kind` (a newer server).
HabitEvent? habitEventFromWire(Json j) {
  final id = _strN(j['id']);
  final habitId = _strN(j['habitId']);
  final date = _strN(j['date']);
  final kind = HabitEventKind.tryFromWire(j['kind'] as String?);
  final st = _stamps(j);
  if (id == null ||
      habitId == null ||
      date == null ||
      kind == null ||
      st == null) {
    return null;
  }
  return HabitEvent(
    id: id,
    habitId: habitId,
    date: date.length >= 10 ? date.substring(0, 10) : date,
    kind: kind,
    label: _str(j['label']),
    note: _strN(j['note']),
    at: _dateN(j['at']),
    extra: scalarMapFromJson(j['extra']),
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension HabitEventRowX on HabitEventRow {
  HabitEvent? toEntityOrNull() {
    final k = HabitEventKind.tryFromWire(kind);
    if (k == null) return null;
    return HabitEvent(
      id: id,
      habitId: habitId,
      date: date,
      kind: k,
      label: label,
      note: note,
      at: at,
      extra: scalarMapFromJson(extra),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension HabitEventX on HabitEvent {
  HabitEventsCompanion toCompanion() => HabitEventsCompanion.insert(
    id: id,
    habitId: habitId,
    date: date,
    kind: kind.wire,
    label: label,
    note: Value(note),
    at: Value(at),
    extra: Value(jsonEncode(extra)),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
