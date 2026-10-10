import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/food/pages/food_form_page.dart';
import 'package:ghina/presentation/features/food/pages/food_page.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

const _tall = Size(390, 2200);

final _routes = [
  GoRoute(path: '/food', builder: (_, _) => const FoodPage()),
  GoRoute(path: '/food/new', builder: (_, _) => const FoodFormPage()),
  GoRoute(
    path: '/food/:id',
    builder: (_, s) => FoodFormPage(id: s.pathParameters['id']),
  ),
];

FoodLog _log(
  String id,
  String name,
  DateTime date, {
  MealType? meal,
  int? kcal,
  int? kcalMax,
  String? label,
  List<String> tags = const [],
  String? note,
}) => FoodLog(
  id: id,
  date: date,
  name: name,
  meal: meal,
  mealLabel: label,
  calories: kcal,
  caloriesMax: kcalMax,
  tags: tags,
  note: note,
  createdAt: date,
  updatedAt: date,
);

void main() {
  testWidgets('empty state invites the first log', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/food',
      routes: _routes,
      size: _tall,
    );
    expect(find.text('Belum ada catatan makan'), findsOneWidget);
    await tester.tap(find.text('CATAT MAKANAN'));
    await settle(tester);
    expect(find.text('Catat makanan'), findsOneWidget); // form app bar
    await drain(tester);
  });

  testWidgets('list groups days with calories and meal chips', (tester) async {
    final h = Harness();
    h.food.s.put(
      _log(
        'a',
        'Nasi goreng',
        harnessNow.subtract(const Duration(hours: 3)),
        meal: MealType.breakfast,
        kcal: 450,
      ),
    );
    h.food.s.put(
      _log(
        'b',
        'Soto ayam',
        harnessNow.subtract(const Duration(hours: 1)),
        meal: MealType.lunch,
        kcal: 350,
        note: 'Enak banget',
      ),
    );
    h.food.s.put(
      _log(
        'c',
        'Martabak',
        harnessNow.subtract(const Duration(days: 1)),
        meal: MealType.snack,
        kcal: 600,
      ),
    );
    await pumpScreen(
      tester,
      h,
      location: '/food',
      routes: _routes,
      size: _tall,
    );

    expect(find.text('Nasi goreng'), findsOneWidget);
    expect(find.text('Soto ayam'), findsOneWidget);
    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('800 kkal'), findsWidgets); // today total
    expect(find.text('Enak banget'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('form shows a friendly error when the name is empty', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/food/new',
      routes: _routes,
      size: _tall,
    );
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 3);
    expect(find.text('Isi nama makanannya dulu ya'), findsOneWidget);
    expect(h.food.s.items, isEmpty);
    await drain(tester);
  });

  testWidgets('submitting the form logs food and pops back', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/food/new',
      routes: _routes,
      size: _tall,
    );
    await tester.enterText(
      find.byKey(const ValueKey('name')).first,
      'Gado-gado',
    );
    await tester.enterText(find.byKey(const ValueKey('calories')).first, '420');
    await tester.tap(find.text('SIMPAN'));
    await settle(tester, 20);
    await drain(tester);
    expect(h.food.s.items.values.single.name, 'Gado-gado');
    expect(h.food.s.items.values.single.calories, 420);
    expect(h.food.s.items.values.single.meal, MealType.lunch); // noon guess
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('edit mode loads the log and deletes after confirming', (
    tester,
  ) async {
    final h = Harness();
    h.food.s.put(
      _log('x', 'Bakso', harnessNow, meal: MealType.dinner, kcal: 500),
    );
    await pumpScreen(
      tester,
      h,
      location: '/food/x',
      routes: _routes,
      size: _tall,
    );
    expect(find.text('Ubah catatan makan'), findsOneWidget);
    expect(find.text('Bakso'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);

    await tester.tap(find.byTooltip('Hapus'));
    await settle(tester, 5);
    expect(find.text('Hapus catatan makan?'), findsOneWidget);
    await tester.tap(find.text('HAPUS'));
    await settle(tester, 5);
    expect(h.food.s.items, isEmpty);
    await drain(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  group('calorie ranges, labels and tags', () {
    Future<void> enter(WidgetTester t, String key, String text) async {
      await t.enterText(find.byKey(ValueKey(key)).first, text);
    }

    testWidgets('form saves a range, a custom label and tags', (tester) async {
      final h = Harness();
      await pumpScreen(
        tester,
        h,
        location: '/food/new',
        routes: _routes,
        size: _tall,
      );
      await enter(tester, 'name', 'Sate contoh');
      await enter(tester, 'calories', '700');
      await enter(tester, 'calories-max', '900');
      await enter(tester, 'meal-label', 'makan malam');
      await enter(tester, 'tag-input', 'Pedas');
      await tester.tap(find.byKey(const ValueKey('tag-add')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('tag-Pedas')), findsOneWidget);
      await tester.tap(find.text('SIMPAN'));
      await settle(tester, 20);
      await drain(tester);
      final f = h.food.s.items.values.single;
      expect((f.calories, f.caloriesMax), (700, 900));
      expect(f.meal, MealType.dinner); // typed canonical name
      expect(f.tags, ['Pedas']);
    });

    testWidgets('max below min shows an error and saves nothing', (
      tester,
    ) async {
      final h = Harness();
      await pumpScreen(
        tester,
        h,
        location: '/food/new',
        routes: _routes,
        size: _tall,
      );
      await enter(tester, 'name', 'Bakso contoh');
      await enter(tester, 'calories', '900');
      await enter(tester, 'calories-max', '700');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester, 3);
      expect(
        find.text('Kalori maksimum harus ≥ kalori minimum'),
        findsOneWidget,
      );
      expect(h.food.s.items, isEmpty);
      await drain(tester);
    });

    testWidgets('free label is saved and offered again as a suggestion', (
      tester,
    ) async {
      final h = Harness();
      h.food.s.put(
        _log('p', 'Roti', harnessNow, label: 'brunch akhir pekan', kcal: 300),
      );
      await pumpScreen(
        tester,
        h,
        location: '/food/new',
        routes: _routes,
        size: _tall,
      );
      expect(
        find.byKey(const ValueKey('meal-chip-brunch akhir pekan')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('meal-chip-brunch akhir pekan')),
      );
      await settle(tester, 3);
      await enter(tester, 'name', 'Nasi uduk contoh');
      await tester.tap(find.text('SIMPAN'));
      await settle(tester, 20);
      await drain(tester);
      final f = h.food.s.items['p'] == null
          ? null
          : h.food.s.items.values.firstWhere((l) => l.id != 'p');
      expect(f!.meal, isNull);
      expect(f.mealLabel, 'brunch akhir pekan');
    });

    testWidgets('editing: emptying max and label clears them', (tester) async {
      final h = Harness();
      h.food.s.put(
        _log(
          'x',
          'Bakso',
          harnessNow,
          label: 'brunch',
          kcal: 500,
          kcalMax: 600,
          tags: ['a'],
        ),
      );
      await pumpScreen(
        tester,
        h,
        location: '/food/x',
        routes: _routes,
        size: _tall,
      );
      expect(find.text('600'), findsOneWidget);
      await enter(tester, 'calories-max', '');
      await enter(tester, 'meal-label', '');
      await tester.tap(find.byKey(const ValueKey('tag-a')));
      await settle(tester, 3);
      await tester.tap(find.text('SIMPAN PERUBAHAN'));
      await settle(tester, 20);
      await drain(tester);
      final f = h.food.s.items['x']!;
      expect(f.caloriesMax, isNull);
      expect(f.mealLabel, isNull);
      expect(f.tags, isEmpty);
    });

    testWidgets('tags are limited to ten', (tester) async {
      final h = Harness();
      await pumpScreen(
        tester,
        h,
        location: '/food/new',
        routes: _routes,
        size: _tall,
      );
      for (var i = 0; i < 11; i++) {
        await enter(tester, 'tag-input', 't$i');
        await tester.tap(find.byKey(const ValueKey('tag-add')));
        await settle(tester, 2);
      }
      expect(find.byKey(const ValueKey('tag-t9')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-t10')), findsNothing);
      await drain(tester);
    });

    testWidgets('list shows ranges, totals with midpoint and tag chips', (
      tester,
    ) async {
      final h = Harness();
      h.food.s.put(
        _log(
          'a',
          'Sate',
          harnessNow.subtract(const Duration(hours: 3)),
          meal: MealType.lunch,
          kcal: 700,
          kcalMax: 900,
          tags: ['pedas'],
        ),
      );
      h.food.s.put(
        _log(
          'b',
          'Es teh',
          harnessNow.subtract(const Duration(hours: 1)),
          label: 'makan malam',
          kcal: 1000,
          tags: ['segar'],
        ),
      );
      await pumpScreen(
        tester,
        h,
        location: '/food',
        routes: _routes,
        size: _tall,
      );
      expect(find.text('· 700–900 kkal'), findsOneWidget);
      expect(find.text('1.700–1.900 kkal'), findsWidgets); // today card + day
      expect(find.byKey(const ValueKey('today-mid')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('today-mid'))).data,
        'tengah 1.800 kkal',
      );
      expect(find.text('makan malam'), findsOneWidget); // free label pill
      expect(find.text('#pedas'), findsOneWidget);
      expect(find.byKey(const ValueKey('food-weekly')), findsOneWidget);
      expect(find.textContaining('Rata-rata 1.700–1.900'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('tag filter narrows the list', (tester) async {
      final h = Harness();
      h.food.s.put(_log('a', 'Sate', harnessNow, kcal: 700, tags: ['pedas']));
      h.food.s.put(
        _log(
          'b',
          'Es teh',
          harnessNow.subtract(const Duration(minutes: 5)),
          kcal: 100,
          tags: ['segar'],
        ),
      );
      await pumpScreen(
        tester,
        h,
        location: '/food',
        routes: _routes,
        size: _tall,
      );
      expect(find.text('Sate'), findsOneWidget);
      expect(find.text('Es teh'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('tag-filter-segar')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-filter-segar')));
      await settle(tester, 3);
      expect(find.text('Sate'), findsNothing);
      expect(find.text('Es teh'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('tag-filter-all')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-filter-all')));
      await settle(tester, 3);
      expect(find.text('Sate'), findsOneWidget);
      await drain(tester);
    });
  });
}
