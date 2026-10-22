// Phase C2 use cases on in-memory repositories: reorder of categories and
// custom columns, and the live steps-of-every-dream read. Invented data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'dreams_fakes.dart';
import 'fakes.dart' show FakeUnitOfWork;

void main() {
  final now = DateTime(2026, 10, 10, 9);
  late FakeDreamCategoryRepository categories;
  late FakeDreamFieldRepository fields;
  late FakeDreamRepository dreams;
  late FakeDreamStepRepository steps;
  late FakeUnitOfWork uow;

  setUp(() {
    categories = FakeDreamCategoryRepository();
    fields = FakeDreamFieldRepository();
    steps = FakeDreamStepRepository();
    dreams = FakeDreamRepository(steps: steps);
    uow = FakeUnitOfWork();
  });

  DreamCategory cat(String key, int order) => DreamCategory(
    id: 'dc-$key',
    key: key,
    label: 'Kategori $key',
    emoji: '🌟',
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );

  DreamFieldDef field(String key, int order) => DreamFieldDef(
    id: 'df-$key',
    key: key,
    label: 'Kolom $key',
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );

  Dream dream(String id, {String title = 'Mimpi contoh'}) =>
      Dream(id: id, title: title, createdAt: now, updatedAt: now);

  DreamStep step(String id, String dreamId) => DreamStep(
    id: id,
    dreamId: dreamId,
    title: 'Langkah $id',
    createdAt: now,
    updatedAt: now,
  );

  group('ReorderDreamCategories', () {
    test('writes the index as sortOrder and skips unknown ids', () async {
      await categories.save(cat('travel', 0));
      await categories.save(cat('health', 1));
      final r = await ReorderDreamCategories(categories, uow, FixedClock(now))([
        'dc-health',
        'missing',
        'dc-travel',
      ]);
      expect(r.isOk, isTrue);
      expect((await categories.getById('dc-health'))!.sortOrder, 0);
      expect((await categories.getById('dc-travel'))!.sortOrder, 2);
      expect(uow.runs, 1);
    });

    test('leaves an unchanged order alone', () async {
      await categories.save(cat('travel', 0));
      final before = await categories.getById('dc-travel');
      await ReorderDreamCategories(
        categories,
        uow,
        FixedClock(now.add(const Duration(days: 1))),
      )(['dc-travel']);
      expect(
        (await categories.getById('dc-travel'))!.updatedAt,
        before!.updatedAt,
      );
    });
  });

  group('ReorderDreamFields', () {
    test('writes the new order of the custom columns', () async {
      await fields.save(field('ukuran', 0));
      await fields.save(field('hobi', 1));
      final r = await ReorderDreamFields(fields, uow, FixedClock(now))([
        'df-hobi',
        'df-ukuran',
      ]);
      expect(r.isOk, isTrue);
      expect((await fields.getById('df-hobi'))!.sortOrder, 0);
      expect((await fields.getById('df-ukuran'))!.sortOrder, 1);
    });
  });

  group('WatchDreamSteps', () {
    test('emits the steps of every dream and follows later changes', () async {
      await dreams.save(dream('d1'));
      await dreams.save(dream('d2'));
      await steps.save(step('s1', 'd1'));

      final seen = <Map<String, List<DreamStep>>>[];
      final sub = WatchDreamSteps(dreams, steps)().listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last['d1']!.map((s) => s.id), ['s1']);
      expect(seen.last['d2'], isEmpty);

      await steps.save(step('s2', 'd2'));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last['d2']!.map((s) => s.id), ['s2']);
    });

    test('emits an empty map when there are no dreams', () async {
      final first = await WatchDreamSteps(dreams, steps)().first;
      expect(first, isEmpty);
    });

    test('a new dream shows up in the map', () async {
      final sub = WatchDreamSteps(dreams, steps)().listen((_) {});
      addTearDown(sub.cancel);
      await dreams.save(dream('d9', title: 'Mimpi sample'));
      await Future<void>.delayed(Duration.zero);
      final latest = await WatchDreamSteps(dreams, steps)().first;
      expect(latest.keys, ['d9']);
    });
  });
}
