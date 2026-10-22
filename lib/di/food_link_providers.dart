/// Composition root, food log ⇄ transaction links
/// (`docs/food-transaction-link.md`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import '../presentation/state/food_link_dismissed.dart';
import '../presentation/state/session_controller.dart' show currentUserProvider;
import 'core_providers.dart';
import 'usecase_providers.dart';

export '../presentation/state/food_link_dismissed.dart'
    show foodLinkDismissedProvider;

final linkFoodToTransactionProvider = Provider<LinkFoodToTransaction>(
  (ref) => LinkFoodToTransaction(
    ref.watch(foodRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

final createFoodWithExpenseProvider = Provider<CreateFoodWithExpense>(
  (ref) => CreateFoodWithExpense(
    ref.watch(createTransactionProvider),
    ref.watch(createFoodLogProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);

final logFoodForTransactionProvider = Provider<LogFoodForTransaction>(
  (ref) => LogFoodForTransaction(ref.watch(createFoodLogProvider)),
);

/// Ids of the categories counted as food: "Kategori makanan" from the
/// account, else by name (Makanan/Makan/Kuliner/Food + sub-categories).
final foodCategoryIdsProvider = Provider.autoDispose<Set<String>>(
  (ref) => resolveFoodCategoryIds(
    ref.watch(watchCategoriesProvider(null)).value ?? const [],
    ref.watch(currentUserProvider)?.foodCategoryIds,
  ),
);

/// The food logs linked to a transaction, oldest first.
final watchFoodForTransactionProvider = StreamProvider.autoDispose
    .family<List<FoodLog>, String>(
      (ref, id) => ref.watch(foodRepositoryProvider).watchByTransaction(id),
    );

/// Expenses from [from] on (inclusive), newest first.
final _expensesSinceProvider = StreamProvider.autoDispose
    .family<List<Transaction>, DateTime>(
      (ref, from) => ref
          .watch(transactionRepositoryProvider)
          .watch(from: from, type: TxType.expense),
    );

/// "Ini makanan yang sama?" for the last 7 days, newest meal first.
final foodLinkSuggestionsProvider =
    Provider.autoDispose<AsyncValue<List<FoodLinkSuggestion>>>((ref) {
      final now = ref.watch(clockProvider).now();
      final from = addDays(startOfDay(now), -6);
      final foods = ref.watch(watchFoodLogsProvider);
      final txs = ref.watch(_expensesSinceProvider(from));
      final ids = ref.watch(foodCategoryIdsProvider);
      final dismissed = ref.watch(foodLinkDismissedProvider);
      if (foods.value == null || txs.value == null) {
        if (foods.hasError) {
          return AsyncError(foods.error!, foods.stackTrace!);
        }
        if (txs.hasError) return AsyncError(txs.error!, txs.stackTrace!);
        return const AsyncLoading();
      }
      return AsyncData(
        suggestFoodLinks(
          [
            for (final f in foods.value!)
              if (!f.date.isBefore(from)) f,
          ],
          txs.value!,
          foodCategoryIds: ids,
          dismissed: dismissed,
        ),
      );
    });

/// The suggestion for one transaction (its detail screen), if any.
final foodLinkSuggestionForTransactionProvider = Provider.autoDispose
    .family<FoodLinkSuggestion?, String>(
      (ref, id) => ref
          .watch(foodLinkSuggestionsProvider)
          .value
          ?.where((s) => s.transaction.id == id)
          .firstOrNull,
    );

/// The suggestion for one food log (its detail screen), if any.
final foodLinkSuggestionForFoodProvider = Provider.autoDispose
    .family<FoodLinkSuggestion?, String>(
      (ref, id) => ref
          .watch(foodLinkSuggestionsProvider)
          .value
          ?.where((s) => s.food.id == id)
          .firstOrNull,
    );

/// Expenses of the day of [at] a food log may be linked to by hand: food
/// expenses first, closest in time.
final foodLinkCandidatesProvider = Provider.autoDispose
    .family<AsyncValue<List<Transaction>>, DateTime>((ref, at) {
      final day = startOfDay(at);
      final txs = ref.watch(_expensesSinceProvider(day));
      final ids = ref.watch(foodCategoryIdsProvider);
      return txs.whenData((l) => linkCandidates(at, l, ids));
    });

/// Food analytics of the current month (Food page).
final foodMonthStatsProvider = Provider.autoDispose<AsyncValue<FoodSpendStats>>(
  (ref) {
    final now = ref.watch(clockProvider).now();
    final start = DateTime(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    // A week of margin: a meal's linked expense may sit just outside.
    final txs = ref.watch(_expensesSinceProvider(addDays(start, -7)));
    final foods = ref.watch(watchFoodLogsProvider);
    final ids = ref.watch(foodCategoryIdsProvider);
    if (foods.value == null || txs.value == null) {
      if (foods.hasError) return AsyncError(foods.error!, foods.stackTrace!);
      if (txs.hasError) return AsyncError(txs.error!, txs.stackTrace!);
      return const AsyncLoading();
    }
    bool inMonth(DateTime d) => !d.isBefore(start) && d.isBefore(next);
    final monthFoods = [
      for (final f in foods.value!)
        if (inMonth(f.date)) f,
    ];
    final linked = {for (final f in monthFoods) ?f.transactionId};
    return AsyncData(
      foodSpendStats(monthFoods, [
        for (final t in txs.value!)
          if (inMonth(t.date) || linked.contains(t.id)) t,
      ], ids),
    );
  },
);

/// Food logs per linked transaction id (transaction list markers).
final foodByTransactionProvider =
    Provider.autoDispose<Map<String, List<FoodLog>>>((ref) {
      final out = <String, List<FoodLog>>{};
      for (final f
          in ref.watch(watchFoodLogsProvider).value ?? const <FoodLog>[]) {
        if (f.transactionId case final id?) {
          (out[id] ??= []).add(f);
        }
      }
      for (final l in out.values) {
        l.sort((a, b) => a.date.compareTo(b.date));
      }
      return out;
    });

/// Unlinked food logs that could belong to [transaction] ("Tautkan food log
/// yang ada"): within two days of it, closest first.
final foodCandidatesForTransactionProvider = Provider.autoDispose
    .family<List<FoodLog>, Transaction>(
      (ref, t) => foodCandidatesForTransaction(
        t,
        ref.watch(watchFoodLogsProvider).value ?? const <FoodLog>[],
      ),
    );
