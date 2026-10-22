/// Pure food ⇄ transaction link rules (`docs/food-transaction-link.md`),
/// mirror of `src/lib/food-links.ts`: food categories, "Ini makanan yang
/// sama?" suggestions and the Food page analytics.
library;

import '../../core/dates.dart';
import '../entities/entities.dart';

/// Expense categories with one of these names (case-insensitive) — and their
/// sub-categories — count as food unless the user picked a list.
const foodCategoryNames = ['makanan', 'makan', 'kuliner', 'food'];

/// A food log and an unlinked food expense this close (same local day) are
/// suggested as one meal.
const foodLinkWindow = Duration(minutes: 90);

final _sep = RegExp(r'^[\s/\-:&>|,.()]');

String _norm(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// `true` for "Makanan", "Food", and sub-categories: the keyword followed by a
/// separator and more text ("Makan Siang", "Makanan / Kopi", "Food & Drink").
/// "Makeup" or "Foodpanda" don't match.
bool isFoodCategoryName(String name) {
  final n = _norm(name);
  for (final k in foodCategoryNames) {
    if (n == k) return true;
    if (n.startsWith(k) && _sep.hasMatch(n.substring(k.length))) return true;
  }
  return false;
}

/// The ids counted as food: the user's explicit choice ([setting], expense
/// categories that still exist), else by name. `null` setting = automatic.
Set<String> resolveFoodCategoryIds(
  List<TxCategory> categories,
  List<String>? setting,
) {
  final expense = categories.where((c) => c.type == CategoryType.expense);
  if (setting != null) {
    final chosen = setting.toSet();
    return {
      for (final c in expense)
        if (chosen.contains(c.id)) c.id,
    };
  }
  return {
    for (final c in expense)
      if (isFoodCategoryName(c.name)) c.id,
  };
}

/// The default category of "Catat juga sebagai pengeluaran": an exact
/// "Makanan"/"Makan"/… first, then the shortest name.
String? defaultFoodCategoryId(List<TxCategory> categories, Set<String> ids) {
  final list = [
    for (final c in categories)
      if (ids.contains(c.id)) c,
  ];
  if (list.isEmpty) return null;
  int exact(TxCategory c) => foodCategoryNames.contains(_norm(c.name)) ? 0 : 1;
  list.sort((a, b) {
    final e = exact(a) - exact(b);
    if (e != 0) return e;
    final l = a.name.length - b.name.length;
    return l != 0 ? l : a.name.compareTo(b.name);
  });
  return list.first.id;
}

/// Whether [t] is an expense in one of [foodIds].
bool isFoodExpense(Transaction t, Set<String> foodIds) =>
    t.type == TxType.expense &&
    t.categoryId != null &&
    foodIds.contains(t.categoryId);

/// Key of a dismissed pair ("Bukan"), as stored on the device.
String foodLinkKey(String foodId, String transactionId) =>
    '$foodId:$transactionId';

/// One "Ini makanan yang sama?" pair.
final class FoodLinkSuggestion {
  const FoodLinkSuggestion({
    required this.food,
    required this.transaction,
    required this.gap,
  });

  final FoodLog food;
  final Transaction transaction;
  final Duration gap;

  String get key => foodLinkKey(food.id, transaction.id);

  @override
  bool operator ==(Object other) =>
      other is FoodLinkSuggestion &&
      other.food == food &&
      other.transaction == transaction &&
      other.gap == gap;

  @override
  int get hashCode => Object.hash(food, transaction, gap);
}

/// Unlinked food logs and food-category expenses that carry no food log yet,
/// same local day and at most [foodLinkWindow] apart. Closest pairs win; each
/// row appears once. Newest meal first. Imported transactions are ordinary
/// expenses, so they're covered too.
List<FoodLinkSuggestion> suggestFoodLinks(
  List<FoodLog> foods,
  List<Transaction> txs, {
  required Set<String> foodCategoryIds,
  Set<String> dismissed = const {},
}) {
  final linkedTx = {
    for (final f in foods)
      if (f.transactionId != null) f.transactionId!,
  };
  final freeTxs = [
    for (final t in txs)
      if (isFoodExpense(t, foodCategoryIds) && !linkedTx.contains(t.id)) t,
  ];
  final pairs = <FoodLinkSuggestion>[];
  for (final f in foods) {
    if (f.transactionId != null) continue;
    for (final t in freeTxs) {
      if (!isSameDay(f.date, t.date)) continue;
      final gap = f.date.difference(t.date).abs();
      if (gap > foodLinkWindow) continue;
      if (dismissed.contains(foodLinkKey(f.id, t.id))) continue;
      pairs.add(FoodLinkSuggestion(food: f, transaction: t, gap: gap));
    }
  }
  pairs.sort((a, b) {
    final g = a.gap.compareTo(b.gap);
    if (g != 0) return g;
    final d = b.food.date.compareTo(a.food.date);
    return d != 0 ? d : a.food.id.compareTo(b.food.id);
  });
  final usedF = <String>{};
  final usedT = <String>{};
  final out = <FoodLinkSuggestion>[];
  for (final p in pairs) {
    if (usedF.contains(p.food.id) || usedT.contains(p.transaction.id)) continue;
    usedF.add(p.food.id);
    usedT.add(p.transaction.id);
    out.add(p);
  }
  return out..sort((a, b) => b.food.date.compareTo(a.food.date));
}

/// Expenses a food log may be linked to by hand: the same day's food
/// expenses first (closest in time), then the day's other expenses.
List<Transaction> linkCandidates(
  DateTime at,
  List<Transaction> txs,
  Set<String> foodCategoryIds,
) {
  final day = [
    for (final t in txs)
      if (t.type == TxType.expense && isSameDay(t.date, at)) t,
  ];
  int rank(Transaction t) => isFoodExpense(t, foodCategoryIds) ? 0 : 1;
  return day..sort((a, b) {
    final r = rank(a) - rank(b);
    if (r != 0) return r;
    return a.date.difference(at).abs().compareTo(b.date.difference(at).abs());
  });
}

// ---------------------------------------------------------------- analytics

/// One name with how often it occurs.
typedef NameCount = ({String name, int count});

/// Food page analytics for one period (mirror of `foodSpendStats`).
final class FoodSpendStats {
  const FoodSpendStats({
    required this.linkedMeals,
    required this.linkedSpend,
    required this.costPerMeal,
    required this.foodSpend,
    required this.kcal,
    required this.kcalLogs,
    required this.spendPer1000Kcal,
    required this.topMenus,
    required this.topPlaces,
  });

  /// Food logs linked to an expense.
  final int linkedMeals;

  /// Sum of those expenses, each transaction once.
  final double linkedSpend;

  /// [linkedSpend] ÷ [linkedMeals], rounded; null without links.
  final double? costPerMeal;

  /// Every food-category expense of the period.
  final double foodSpend;

  /// Calories (range midpoints) and how many logs had them.
  final int kcal;
  final int kcalLogs;

  /// [foodSpend] per 1000 kcal, rounded; null when either is 0.
  final double? spendPer1000Kcal;

  /// Top 3 food names / expense notes ("tempat"), case-insensitive.
  final List<NameCount> topMenus;
  final List<NameCount> topPlaces;

  bool get isEmpty => linkedMeals == 0 && foodSpend == 0 && kcalLogs == 0;
}

List<NameCount> _top(Iterable<String?> values, [int n = 3]) {
  final m = <String, ({String name, int count})>{};
  for (final v in values) {
    final t = v?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t == null || t.isEmpty) continue;
    final k = t.toLowerCase();
    final e = m[k];
    m[k] = (name: e?.name ?? t, count: (e?.count ?? 0) + 1);
  }
  final list = m.values.toList()
    ..sort((a, b) {
      final c = b.count - a.count;
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return list.take(n).toList();
}

/// [foods] = food logs of the period; [txs] = expenses of the period plus any
/// transaction one of those logs links to (it may fall just outside).
FoodSpendStats foodSpendStats(
  List<FoodLog> foods,
  List<Transaction> txs,
  Set<String> foodCategoryIds,
) {
  final byId = {for (final t in txs) t.id: t};
  final linked = [
    for (final f in foods)
      if (f.transactionId != null &&
          byId[f.transactionId]?.type == TxType.expense)
        f,
  ];
  final linkedIds = {for (final f in linked) f.transactionId!};
  final linkedSpend = linkedIds.fold<double>(
    0,
    (s, id) => s + byId[id]!.amount,
  );
  final foodTxs = [
    for (final t in txs)
      if (isFoodExpense(t, foodCategoryIds)) t,
  ];
  final foodSpend = foodTxs.fold<double>(0, (s, t) => s + t.amount);
  var kcal = 0;
  var kcalLogs = 0;
  for (final f in foods) {
    final lo = f.calories;
    if (lo == null) continue;
    kcal += ((lo + (f.caloriesMax ?? lo)) / 2).round();
    kcalLogs++;
  }
  final foodTxIds = {for (final t in foodTxs) t.id};
  return FoodSpendStats(
    linkedMeals: linked.length,
    linkedSpend: linkedSpend,
    costPerMeal: linked.isEmpty
        ? null
        : (linkedSpend / linked.length).roundToDouble(),
    foodSpend: foodSpend,
    kcal: kcal,
    kcalLogs: kcalLogs,
    spendPer1000Kcal: foodSpend > 0 && kcal > 0
        ? (foodSpend / kcal * 1000).roundToDouble()
        : null,
    topMenus: _top(foods.map((f) => f.name)),
    topPlaces: _top([
      for (final t in foodTxs) t.note,
      for (final id in linkedIds)
        if (!foodTxIds.contains(id)) byId[id]!.note,
    ]),
  );
}

/// Unlinked food logs that could belong to [t]: at most two days away,
/// closest in time first (same day naturally comes first).
List<FoodLog> foodCandidatesForTransaction(Transaction t, List<FoodLog> foods) {
  const span = Duration(days: 2);
  final list = [
    for (final f in foods)
      if (f.transactionId == null && f.date.difference(t.date).abs() <= span) f,
  ];
  return list..sort(
    (a, b) =>
        a.date.difference(t.date).abs().compareTo(b.date.difference(t.date).abs()),
  );
}

/// The photo a food log shows: its own, else the first photo of its linked
/// transaction (the receipt/food shot taken with the expense) — referenced,
/// never copied (`docs/food-transaction-link.md`).
TransactionPhoto? sharedFoodPhoto(FoodLog log, Transaction? linked) {
  if (log.hasPhoto || linked == null || linked.id != log.transactionId) {
    return null;
  }
  return linked.photos.firstOrNull;
}
