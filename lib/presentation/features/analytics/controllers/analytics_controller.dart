import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/analytics_spending.dart';

/// What the Analitik page shows: period, wallets, transfers, compare.
final class AnalyticsQuery {
  const AnalyticsQuery({
    this.preset = AnalyticsPreset.thisMonth,
    this.from,
    this.to,
    this.walletIds = const {},
    this.includeTransfers = false,
    this.compare = true,
  });

  final AnalyticsPreset preset;

  /// Custom range (only with [AnalyticsPreset.custom]).
  final DateTime? from;
  final DateTime? to;
  final Set<String> walletIds;
  final bool includeTransfers;
  final bool compare;

  AnalyticsFilter get filter =>
      AnalyticsFilter(walletIds: walletIds, includeTransfers: includeTransfers);

  AnalyticsQuery copyWith({
    AnalyticsPreset? preset,
    DateTime? from,
    DateTime? to,
    Set<String>? walletIds,
    bool? includeTransfers,
    bool? compare,
  }) => AnalyticsQuery(
    preset: preset ?? this.preset,
    from: from ?? this.from,
    to: to ?? this.to,
    walletIds: walletIds ?? this.walletIds,
    includeTransfers: includeTransfers ?? this.includeTransfers,
    compare: compare ?? this.compare,
  );
}

final analyticsQueryProvider =
    NotifierProvider<AnalyticsQueryState, AnalyticsQuery>(
      AnalyticsQueryState.new,
    );

class AnalyticsQueryState extends Notifier<AnalyticsQuery> {
  @override
  AnalyticsQuery build() => const AnalyticsQuery();

  void setPreset(AnalyticsPreset p) => state = state.copyWith(preset: p);

  void setCustom(DateTime from, DateTime to) => state = state.copyWith(
    preset: AnalyticsPreset.custom,
    from: from,
    to: to,
  );

  void setWallets(Set<String> ids) => state = state.copyWith(walletIds: ids);

  void toggleTransfers() =>
      state = state.copyWith(includeTransfers: !state.includeTransfers);

  void toggleCompare() => state = state.copyWith(compare: !state.compare);
}

/// The resolved period for the current query (stable within a day).
final analyticsPeriodProvider = Provider.autoDispose<AnalyticsPeriod>((ref) {
  final q = ref.watch(analyticsQueryProvider);
  final now = ref.watch(clockProvider).now();
  return resolveAnalyticsPeriod(q.preset, now, from: q.from, to: q.to);
});

AsyncValue<R> _combine<R>(List<AsyncValue<Object?>> xs, R Function() build) {
  for (final x in xs) {
    if (x.hasError && !x.hasValue) {
      return AsyncError<R>(x.error!, x.stackTrace ?? StackTrace.current);
    }
  }
  if (xs.every((x) => x.hasValue)) return AsyncData(build());
  return AsyncLoading<R>();
}

/// Source rows: transactions from the previous period's start to the end
/// of the period (compare and drill-downs never refetch).
final _analyticsTxProvider =
    Provider.autoDispose<AsyncValue<List<Transaction>>>((ref) {
      final p = ref.watch(analyticsPeriodProvider);
      final v = ref.watch(
        watchTransactionsProvider(
          TransactionFilter(from: analyticsFetchStart(p), to: p.end),
        ),
      );
      return v.whenData((rows) => [for (final r in rows) r.transaction]);
    });

/// Everything the Analitik page draws.
final spendingAnalyticsProvider =
    Provider.autoDispose<AsyncValue<SpendingAnalytics>>((ref) {
      final q = ref.watch(analyticsQueryProvider);
      final p = ref.watch(analyticsPeriodProvider);
      final now = ref.watch(clockProvider).now();
      final txs = ref.watch(_analyticsTxProvider);
      final cats = ref.watch(watchCategoriesProvider(null));
      final wallets = ref.watch(watchAllWalletsProvider);
      return _combine(
        [txs, cats, wallets],
        () => buildSpendingAnalytics(
          transactions: txs.requireValue,
          categories: cats.requireValue,
          wallets: wallets.requireValue,
          period: p,
          now: now,
          filter: q.filter,
          compare: q.compare,
        ),
      );
    });

/// One category (or `__none` / `__transfer`) drilled in.
final categoryAnalyticsProvider = Provider.autoDispose
    .family<AsyncValue<CategoryAnalytics>, String>((ref, key) {
      final a = ref.watch(spendingAnalyticsProvider);
      final txs = ref.watch(_analyticsTxProvider);
      final cats = ref.watch(watchCategoriesProvider(null));
      final now = ref.watch(clockProvider).now();
      return _combine(
        [a, txs, cats],
        () => buildCategoryAnalytics(
          a: a.requireValue,
          key: key,
          transactions: txs.requireValue,
          categories: cats.requireValue,
          now: now,
        ),
      );
    });

/// Budgets of the month the period points at.
final analyticsBudgetProvider = Provider.autoDispose<AsyncValue<BudgetMonth>>((
  ref,
) {
  final p = ref.watch(analyticsPeriodProvider);
  final now = ref.watch(clockProvider).now();
  return ref.watch(watchBudgetMonthProvider(budgetMonthFor(p, now)));
});
