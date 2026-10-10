import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

FoodLog _f(
  String id,
  DateTime date, {
  MealType? meal,
  String? label,
  int? kcal,
  int? max,
  List<String> tags = const [],
}) => FoodLog(
  id: id,
  date: date,
  name: 'Makanan $id',
  meal: meal,
  mealLabel: label,
  calories: kcal,
  caloriesMax: max,
  tags: tags,
  createdAt: date,
  updatedAt: date,
);

void main() {
  final d9 = DateTime(2026, 10, 9, 12);
  final d10 = DateTime(2026, 10, 10, 8);

  group('FoodTotals', () {
    test('adds min and max, entries without calories only count', () {
      final t = foodTotals([
        _f('a', d9, kcal: 700, max: 900),
        _f('b', d9, kcal: 450),
        _f('c', d9),
      ]);
      expect((t.min, t.max, t.count, t.noCalories), (1150, 1350, 3, 1));
      expect(t.mid, 1250);
      expect(t.isRange, isTrue);
      expect(t.hasCalories, isTrue);
    });

    test('mid rounds half up like the server', () {
      expect(const FoodTotals(min: 1, max: 2).mid, 2);
      expect(const FoodTotals(min: 700, max: 701).mid, 701);
      expect(const FoodTotals().mid, 0);
    });

    test('labels', () {
      expect(calorieNumbers(_f('a', d9, kcal: 700, max: 900)), '700–900');
      expect(calorieNumbers(_f('a', d9, kcal: 700, max: 700)), '700');
      expect(calorieNumbers(_f('a', d9, kcal: 450)), '450');
      expect(calorieNumbers(_f('a', d9)), isNull);
      expect(
        formatCalorieSpan(const FoodTotals(min: 1, max: 3), (n) => '<$n>'),
        '<1>–<3>',
      );
      expect(
        formatCalorieSpan(const FoodTotals(min: 5, max: 5), (n) => '<$n>'),
        '<5>',
      );
    });
  });

  group('summarizeFood', () {
    final logs = [
      _f('1', d9, meal: MealType.lunch, kcal: 1000),
      _f('2', d9, label: 'makan malam', kcal: 700, max: 900, tags: ['Pedas']),
      _f('3', d10, meal: MealType.lunch, kcal: 301, max: 400, tags: ['pedas']),
      _f('4', d10, kcal: null, tags: ['Segar', 'porsi besar']),
      _f('5', DateTime(2026, 9, 1), kcal: 5000), // outside the window
    ];
    final s = summarizeFood(logs, from: '2026-10-04', to: '2026-10-10');

    test('days, oldest first, with entries only', () {
      expect(s.daysLogged, 2);
      expect(s.days.map((d) => d.date), ['2026-10-09', '2026-10-10']);
      expect(s.days.first.totals.min, 1700);
      expect(s.days.first.totals.max, 1900);
      expect(s.days.first.totals.mid, 1800);
      expect(s.days.last.totals.count, 2);
    });

    test('byMeal keys: wire, free label as stored, (none); by count', () {
      expect(s.byMeal.keys.toList(), ['lunch', 'makan malam', '(none)']);
      expect(s.byMeal['lunch']!.count, 2);
      expect(s.byMeal['makan malam']!.mid, 800);
    });

    test('avgPerDay rounds like the server', () {
      // sums: min 2001, max 2300 over 2 days -> 1000.5 / 1150
      final a = s.avgPerDay!;
      expect(a.min, 1001);
      expect(a.max, 1150);
      expect(a.mid, 1075); // round((1000.5 + 1150) / 2) = round(1075.25)
    });

    test('topTags are case-insensitive, first spelling wins', () {
      expect(s.topTags.first.tag, 'Pedas');
      expect(s.topTags.first.count, 2);
      expect(s.topTags.map((t) => t.tag), ['Pedas', 'porsi besar', 'Segar']);
    });

    test('no entries -> no average', () {
      final e = summarizeFood(const [], from: '2026-10-04', to: '2026-10-10');
      expect(e.avgPerDay, isNull);
      expect(e.daysLogged, 0);
    });

    test('weekly window is the last 7 days', () {
      final w = weeklyFoodSummary(logs, DateTime(2026, 10, 10, 20));
      expect(w.from, '2026-10-04');
      expect(w.to, '2026-10-10');
      expect(w.daysLogged, 2);
    });
  });

  group('parseCalorieRange', () {
    test('blank is null, valid numbers parse', () {
      final r = parseCalorieRange('700', '900');
      expect((r.min, r.max), (700, 900));
      expect(r.errors, isEmpty);
      final b = parseCalorieRange('', '');
      expect((b.min, b.max), (null, null));
      expect(b.errors, isEmpty);
    });

    test('max below min and max without min are errors', () {
      expect(
        parseCalorieRange('900', '700').errors['caloriesMax'],
        contains('≥'),
      );
      expect(
        parseCalorieRange('', '700').errors['caloriesMax'],
        contains('minimum'),
      );
    });

    test('out of range', () {
      expect(parseCalorieRange('25000', '').errors, contains('calories'));
      expect(parseCalorieRange('1', '30000').errors, contains('caloriesMax'));
    });

    test('max equal to min is fine', () {
      expect(parseCalorieRange('500', '500').errors, isEmpty);
    });
  });

  group('meal labels', () {
    test('resolveMealText maps canonical names, keeps free text', () {
      expect(resolveMealText('Sarapan').meal, MealType.breakfast);
      expect(resolveMealText(' lunch ').meal, MealType.lunch);
      expect(resolveMealText('MAKAN MALAM').meal, MealType.dinner);
      final free = resolveMealText('  brunch   akhir pekan ');
      expect((free.meal, free.label), (null, 'brunch akhir pekan'));
      expect(resolveMealText('  ').label, isNull);
    });

    test('recentMealLabels: newest first, distinct, limited', () {
      final logs = [
        _f('1', d10, label: 'Brunch'),
        _f('2', d10, meal: MealType.lunch),
        _f('3', d9, label: 'brunch'),
        _f('4', d9, label: 'Ngemil malam'),
      ];
      expect(recentMealLabels(logs), ['Brunch', 'Ngemil malam']);
      expect(recentMealLabels(logs, limit: 1), ['Brunch']);
    });
  });

  group('tags', () {
    test('addFoodTag trims, dedupes, caps length and count', () {
      expect(addFoodTag(['pedas'], '  segar '), ['pedas', 'segar']);
      expect(addFoodTag(['pedas'], 'PEDAS'), ['pedas']);
      expect(addFoodTag(['a'], ''), ['a']);
      expect(addFoodTag(const [], 'x' * 31), isEmpty);
      expect(addFoodTag(const [], 'x' * 30), hasLength(1));
      final ten = [for (var i = 0; i < 10; i++) 't$i'];
      expect(addFoodTag(ten, 'baru'), ten);
    });

    test('foodTagCounts and filterFoodByTag', () {
      final logs = [
        _f('1', d10, tags: ['Pedas', 'segar']),
        _f('2', d9, tags: ['pedas']),
        _f('3', d9),
      ];
      final c = foodTagCounts(logs);
      expect((c.first.tag, c.first.count), ('Pedas', 2));
      expect(filterFoodByTag(logs, 'PEDAS').map((l) => l.id), ['1', '2']);
      expect(filterFoodByTag(logs, 'segar').map((l) => l.id), ['1']);
      expect(filterFoodByTag(logs, null), hasLength(3));
    });
  });
}
