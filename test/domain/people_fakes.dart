import 'dart:async';

import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';

/// In-memory People repositories (use-case and widget tests). Invented data
/// only: Budi Contoh, Siti Sample, Andi Contoh.
class _Store<T> {
  _Store(this.idOf);
  final String Function(T) idOf;
  final items = <String, T>{};
  final _changes = StreamController<void>.broadcast();

  void put(T v) {
    items[idOf(v)] = v;
    _changes.add(null);
  }

  void remove(String id) {
    items.remove(id);
    _changes.add(null);
  }

  Stream<R> watch<R>(R Function() read) => Stream<R>.multi((c) {
    c.add(read());
    final sub = _changes.stream.listen((_) => c.add(read()));
    c.onCancel = sub.cancel;
  });
}

class FakePersonRepository implements PersonRepository {
  final s = _Store<Person>((p) => p.id);
  final refreshed = <String>[];

  List<Person> get _sorted =>
      s.items.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Stream<List<Person>> watchAll() => s.watch(() => _sorted);
  @override
  Future<List<Person>> getAll() async => _sorted;
  @override
  Stream<Person?> watchById(String id) => s.watch(() => s.items[id]);
  @override
  Future<Person?> getById(String id) async => s.items[id];
  @override
  Future<void> save(Person p) async => s.put(p);
  @override
  Future<void> delete(String id) async => s.remove(id);
  @override
  Future<void> refreshPending(String id) async => refreshed.add(id);
}

class FakePersonCategoryRepository implements PersonCategoryRepository {
  final s = _Store<PersonCategory>((c) => c.id);

  List<PersonCategory> get _sorted =>
      s.items.values.toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<PersonCategory>> watchAll() => s.watch(() => _sorted);
  @override
  Future<List<PersonCategory>> getAll() async => _sorted;
  @override
  Future<PersonCategory?> getById(String id) async => s.items[id];
  @override
  Future<void> save(PersonCategory c) async => s.put(c);
}

class FakePersonFieldRepository implements PersonFieldRepository {
  final s = _Store<PersonFieldDef>((d) => d.id);

  List<PersonFieldDef> get _sorted =>
      s.items.values.toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<PersonFieldDef>> watchAll() => s.watch(() => _sorted);
  @override
  Future<List<PersonFieldDef>> getAll() async => _sorted;
  @override
  Future<PersonFieldDef?> getById(String id) async => s.items[id];
  @override
  Future<void> save(PersonFieldDef d) async => s.put(d);
}

class FakePersonDateRepository implements PersonDateRepository {
  final s = _Store<PersonDate>((d) => d.id);

  List<PersonDate> get _all => s.items.values.toList();

  @override
  Stream<List<PersonDate>> watchAll() => s.watch(() => _all);
  @override
  Future<List<PersonDate>> getAll() async => _all;
  @override
  Stream<List<PersonDate>> watchForPerson(String personId) => s.watch(
    () => [
      for (final d in _all)
        if (d.personId == personId) d,
    ],
  );
  @override
  Future<List<PersonDate>> getForPerson(String personId) async => [
    for (final d in _all)
      if (d.personId == personId) d,
  ];
  @override
  Future<PersonDate?> getById(String id) async => s.items[id];
  @override
  Future<void> save(PersonDate d) async => s.put(d);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

/// Notes of a few fake people; counts every network read.
class FakePeopleNotes implements PeopleNotesRepository {
  final notes = <String, String>{};
  final updatedAt = <String, DateTime>{};
  int gets = 0;
  Failure? failWith;
  var _ticks = 0;

  DateTime _stamp(String id) =>
      updatedAt[id] = DateTime.utc(2026, 10, 10, 9, 0, _ticks++);

  @override
  Future<PersonNotes> fetch(String personId) async {
    gets++;
    if (failWith != null) throw failWith!;
    return PersonNotes(
      notes: notes[personId] ?? '',
      updatedAt: updatedAt[personId] ?? _stamp(personId),
    );
  }

  @override
  Future<PersonNotesWrite> replace(
    String personId,
    String text, {
    DateTime? expectedUpdatedAt,
  }) async {
    if (failWith != null) throw failWith!;
    final current = updatedAt[personId];
    if (expectedUpdatedAt != null &&
        current != null &&
        expectedUpdatedAt != current) {
      throw const ConflictFailure(
        'Catatan ini sudah diubah di tempat lain. Muat ulang dulu, lalu coba lagi.',
      );
    }
    notes[personId] = text;
    return PersonNotesWrite(
      updatedAt: _stamp(personId),
      notesLength: text.length,
    );
  }

  @override
  Future<PersonNotesWrite> append(
    String personId,
    String text, {
    String? heading,
  }) async {
    if (failWith != null) throw failWith!;
    final cur = notes[personId] ?? '';
    notes[personId] =
        '$cur${cur.isEmpty ? '' : '\n\n'}${heading == null ? '' : '## $heading\n'}$text';
    return PersonNotesWrite(
      updatedAt: _stamp(personId),
      notesLength: notes[personId]!.length,
    );
  }
}

/// Builders with invented people.
final _t0 = DateTime(2026, 10, 1);

PersonCategory fakeCategory(
  String key,
  String label,
  String emoji, {
  int order = 0,
}) => PersonCategory(
  id: 'pc_u1_$key',
  key: key,
  label: label,
  emoji: emoji,
  sortOrder: order,
  createdAt: _t0,
  updatedAt: _t0,
);

Person fakePerson(
  String id,
  String name, {
  String category = 'other',
  String? relation,
  PersonVibe vibe = PersonVibe.unknown,
  int? birthYear,
  int? birthMonth,
  int? birthDay,
  List<String> tags = const [],
  Map<String, Object> fields = const {},
  bool sensitive = false,
  bool hasNotes = false,
  int notesLength = 0,
  String? summary,
}) => Person(
  id: id,
  name: name,
  category: category,
  relation: relation,
  vibe: vibe,
  summary: summary,
  birthYear: birthYear,
  birthMonth: birthMonth,
  birthDay: birthDay,
  tags: tags,
  fields: fields,
  sensitive: sensitive,
  hasNotes: hasNotes,
  notesLength: notesLength,
  createdAt: _t0,
  updatedAt: _t0,
);

PersonDate fakeDate(
  String id,
  String personId,
  String label,
  int month,
  int day, {
  PersonDateKind kind = PersonDateKind.custom,
  int? year,
  int? remind,
}) => PersonDate(
  id: id,
  personId: personId,
  label: label,
  kind: kind,
  month: month,
  day: day,
  year: year,
  remindDaysBefore: remind,
  createdAt: _t0,
  updatedAt: _t0,
);

PersonFieldDef fakeDef(
  String key,
  String label,
  PersonFieldType type, {
  List<String>? options,
  List<String>? appliesTo,
  int order = 0,
}) => PersonFieldDef(
  id: 'pf-$key',
  key: key,
  label: label,
  type: type,
  options: options,
  appliesTo: appliesTo,
  sortOrder: order,
  createdAt: _t0,
  updatedAt: _t0,
);
