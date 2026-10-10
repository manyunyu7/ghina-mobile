import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../presentation/features/profile/_harness.dart' show FakeFoodRepository;

void main() {
  final clock = FixedClock(DateTime(2026, 10, 10, 10));
  late FakeFoodRepository repo;
  late CreateFoodLog create;
  late UpdateFoodLog update;

  setUp(() {
    repo = FakeFoodRepository();
    create = CreateFoodLog(repo, clock);
    update = UpdateFoodLog(repo, clock);
  });

  FoodInput input({
    MealType? meal,
    String? label,
    bool clearLabel = false,
    num? kcal,
    num? max,
    bool clearMax = false,
    List<String>? tags,
  }) => FoodInput(
    date: DateTime(2026, 10, 10, 12),
    name: 'Nasi campur contoh',
    meal: meal,
    mealLabel: label,
    clearMealLabel: clearLabel,
    calories: kcal,
    caloriesMax: max,
    clearCaloriesMax: clearMax,
    tags: tags,
  );

  test('create stores a range, a free label and tags', () async {
    final r = await create(
      input(
        label: 'makan malam',
        kcal: 700,
        max: 900,
        tags: ['pedas', 'Pedas'],
      ),
    );
    final f = r.valueOrThrow;
    expect((f.calories, f.caloriesMax), (700, 900));
    expect(f.meal, isNull);
    expect(f.mealLabel, 'makan malam');
    expect(f.tags, ['pedas']);
  });

  test('max below min or without min is refused', () async {
    expect((await create(input(kcal: 900, max: 700))).failureOrNull, isNotNull);
    expect((await create(input(max: 700))).failureOrNull, isNotNull);
  });

  test('too long label, too many or too long tags are refused', () async {
    expect((await create(input(label: 'x' * 25))).failureOrNull, isNotNull);
    expect(
      (await create(input(tags: [for (var i = 0; i < 11; i++) 't$i']))).isOk,
      isFalse,
    );
    expect((await create(input(tags: ['x' * 31]))).isOk, isFalse);
  });

  test(
    'update: null keeps the stored max / label / tags, flags clear',
    () async {
      final id = (await create(
        input(label: 'brunch', kcal: 500, max: 600, tags: ['a']),
      )).valueOrThrow.id;

      final kept = (await update(
        id,
        input(label: 'brunch', kcal: 500),
      )).valueOrThrow;
      expect(kept.caloriesMax, 600);
      expect(kept.tags, ['a']);

      final noLabel = (await update(id, input(kcal: 500))).valueOrThrow;
      expect(noLabel.mealLabel, 'brunch'); // null keeps the label

      final cleared = (await update(
        id,
        input(clearLabel: true, kcal: 500, clearMax: true, tags: const []),
      )).valueOrThrow;
      expect(cleared.mealLabel, isNull);
      expect(cleared.caloriesMax, isNull);
      expect(cleared.tags, isEmpty);
    },
  );

  test('a canonical meal drops the stored free label', () async {
    final id = (await create(input(label: 'brunch', kcal: 1))).valueOrThrow.id;
    final f = (await update(
      id,
      input(meal: MealType.lunch, kcal: 1),
    )).valueOrThrow;
    expect(f.meal, MealType.lunch);
    expect(f.mealLabel, isNull);
  });
}
