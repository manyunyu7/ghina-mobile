// Food ⇄ transaction link rules (docs/food-transaction-link.md); same cases
// as scripts/test-food-links.mjs for the TypeScript twin.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

final _t0 = DateTime(2026, 10, 1);

TxCategory _c(
  String id,
  String name, [
  CategoryType type = CategoryType.expense,
]) => TxCategory(
  id: id,
  name: name,
  type: type,
  color: '#ff9600',
  icon: 'utensils',
  createdAt: _t0,
  updatedAt: _t0,
);

FoodLog _f(
  String id,
  DateTime date, {
  String? tx,
  String? name,
  int? kcal,
  int? max,
}) => FoodLog(
  id: id,
  date: date,
  name: name ?? 'Makanan $id',
  calories: kcal,
  caloriesMax: max,
  transactionId: tx,
  createdAt: date,
  updatedAt: date,
);

Transaction _t(
  String id,
  DateTime date, {
  double amount = 20000,
  String? cat = 'food',
  TxType type = TxType.expense,
  String? note,
}) => Transaction(
  id: id,
  walletId: 'w',
  categoryId: cat,
  type: type,
  amount: amount,
  note: note,
  date: date,
  createdAt: date,
  updatedAt: date,
);

void main() {
  group('food categories', () {
    test('names and sub-categories match, look-alikes do not', () {
      for (final n in [
        'Makanan',
        'makan',
        ' KULINER ',
        'Food',
        'Makan Siang',
        'Makanan / Kopi',
        'Food & Drink',
        'Food - Snack',
        'Kuliner: Jajan',
      ]) {
        expect(isFoodCategoryName(n), isTrue, reason: n);
      }
      for (final n in ['Makeup', 'Foodpanda', 'Belanja makanan', 'Transport']) {
        expect(isFoodCategoryName(n), isFalse, reason: n);
      }
    });

    test('automatic = by name (expense only); a setting wins', () {
      final cats = [
        _c('a', 'Makanan'),
        _c('b', 'Makan Siang'),
        _c('c', 'Transport'),
        _c('d', 'Food', CategoryType.income),
      ];
      expect(resolveFoodCategoryIds(cats, null), {'a', 'b'});
      expect(resolveFoodCategoryIds(cats, ['c', 'd', 'gone']), {'c'});
      expect(resolveFoodCategoryIds(cats, []), isEmpty);
    });

    test('default category prefers an exact name', () {
      final cats = [
        _c('b', 'Makan Siang'),
        _c('a', 'Makanan'),
        _c('x', 'Lain'),
      ];
      expect(defaultFoodCategoryId(cats, {'a', 'b'}), 'a');
      expect(defaultFoodCategoryId(cats, {'b'}), 'b');
      expect(defaultFoodCategoryId(cats, {}), isNull);
    });
  });

  group('suggestions', () {
    final noon = DateTime(2026, 10, 21, 12);
    const ids = {'food'};

    test('same day within 90 minutes, closest pairs win, newest first', () {
      final s = suggestFoodLinks(
        [
          _f('f1', noon),
          _f('f2', noon.add(const Duration(minutes: 30))),
          _f('f3', DateTime(2026, 10, 21, 19)),
        ],
        [
          _t('t1', noon.add(const Duration(minutes: 25))), // 5 min to f2
          _t('t2', noon.subtract(const Duration(minutes: 89))),
          _t('t3', DateTime(2026, 10, 21, 21)), // 2 h after f3
        ],
        foodCategoryIds: ids,
      );
      expect(
        [for (final x in s) (x.food.id, x.transaction.id)],
        [('f2', 't1'), ('f1', 't2')],
      );
      expect(s.first.gap, const Duration(minutes: 5));
    });

    test('never across midnight, never non-food / non-expense / linked rows, '
        'never a dismissed pair', () {
      final late = DateTime(2026, 10, 21, 23, 50);
      final s = suggestFoodLinks(
        [
          _f('f1', late),
          _f('f2', noon),
          _f('f3', noon, tx: 'tLinked'),
          _f('f4', noon.add(const Duration(minutes: 1))),
        ],
        [
          _t('t1', DateTime(2026, 10, 22, 0, 10)), // next day, 20 min
          _t('t2', noon, cat: 'other'),
          _t('t3', noon, type: TxType.income),
          _t('tLinked', noon), // already carries f3
          _t('t5', noon.add(const Duration(minutes: 2))),
        ],
        foodCategoryIds: ids,
        dismissed: {foodLinkKey('f4', 't5')},
      );
      expect(
        [for (final x in s) (x.food.id, x.transaction.id)],
        [('f2', 't5')],
      );
    });

    test('link candidates: the day\'s food expenses first, closest first', () {
      final list = linkCandidates(noon, [
        _t('other', noon, cat: 'x'),
        _t('far', noon.add(const Duration(hours: 3))),
        _t('near', noon.add(const Duration(minutes: 10))),
        _t('yesterday', noon.subtract(const Duration(days: 1))),
        _t('income', noon, type: TxType.income),
      ], ids);
      expect([for (final t in list) t.id], ['near', 'far', 'other']);
    });
  });

  group('analytics', () {
    test('cost per meal counts a shared transaction once', () {
      final d = DateTime(2026, 10, 5, 12);
      final s = foodSpendStats(
        [
          _f('a', d, tx: 't1', name: 'Nasi goreng', kcal: 600),
          _f('b', d, tx: 't1', name: 'Es teh', kcal: 100, max: 140),
          _f('c', d, tx: 't2', name: 'nasi goreng'),
          _f('d', d, name: 'Apel'),
        ],
        [
          _t('t1', d, amount: 40000, note: 'Warung A'),
          _t('t2', d, amount: 20000, note: 'warung a'),
          _t('t3', d, amount: 15000, note: 'Kantin B'),
          _t('t4', d, amount: 99000, cat: 'other', note: 'Bensin'),
        ],
        {'food'},
      );
      expect(s.linkedMeals, 3);
      expect(s.linkedSpend, 60000);
      expect(s.costPerMeal, 20000);
      expect(s.foodSpend, 75000);
      expect(s.kcal, 720);
      expect(s.kcalLogs, 2);
      expect(s.spendPer1000Kcal, (75000 / 720 * 1000).roundToDouble());
      expect(s.topMenus.first, (name: 'Nasi goreng', count: 2));
      expect(s.topPlaces.first, (name: 'Warung A', count: 2));
      expect(s.isEmpty, isFalse);
    });

    test('nothing linked → no cost per meal', () {
      final s = foodSpendStats([_f('a', _t0)], const [], {'food'});
      expect(s.costPerMeal, isNull);
      expect(s.spendPer1000Kcal, isNull);
      expect(s.linkedMeals, 0);
    });
  });

  group('transaction-first', () {
    final at = DateTime(2026, 10, 21, 12);
    test('candidates: unlinked meals within two days, closest first', () {
      final list = foodCandidatesForTransaction(_t('t', at), [
        _f('far', at.subtract(const Duration(days: 3))),
        _f('linked', at, tx: 'x'),
        _f('yesterday', at.subtract(const Duration(days: 1))),
        _f('near', at.add(const Duration(minutes: 30))),
      ]);
      expect([for (final f in list) f.id], ['near', 'yesterday']);
    });

    test('a meal without its own photo shows its transaction\'s first one', () {
      final t = Transaction(
        id: 't',
        walletId: 'w',
        type: TxType.expense,
        amount: 1,
        date: at,
        createdAt: at,
        updatedAt: at,
        photos: const [
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.remote('/uploads/b.jpg'),
        ],
      );
      expect(sharedFoodPhoto(_f('f', at, tx: 't'), t)!.url, '/uploads/a.jpg');
      expect(sharedFoodPhoto(_f('f', at, tx: 'other'), t), isNull);
      final own = FoodLog(
        id: 'f',
        date: at,
        name: 'x',
        photoUrl: '/uploads/own.jpg',
        transactionId: 't',
        createdAt: at,
        updatedAt: at,
      );
      expect(sharedFoodPhoto(own, t), isNull);
    });
  });
}
