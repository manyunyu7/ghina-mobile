/// Composition root, part 4: habits (`docs/habits.md`) and investments
/// (`docs/investments.md`). See `lib/di/README.md` → "Habits & investments
/// API".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import '../presentation/state/session_controller.dart' show currentUserProvider;
import 'core_providers.dart';
import 'usecase_providers.dart'
    show
        createTransactionProvider,
        deleteTransactionProvider,
        updateTransactionProvider;

// ================================================================ habits

// ---------------------------------------------------------------- writes

/// `(HabitInput(...))` → [Habit] (added at the end of the order).
final createHabitProvider = Provider<CreateHabit>(
  (ref) =>
      CreateHabit(ref.watch(habitRepositoryProvider), ref.watch(clockProvider)),
);

/// `(id, HabitInput)` → [Habit] (keeps archived/order; startDate null =
/// unchanged).
final updateHabitProvider = Provider<UpdateHabit>(
  (ref) =>
      UpdateHabit(ref.watch(habitRepositoryProvider), ref.watch(clockProvider)),
);

/// `([ids in new order])`.
final reorderHabitsProvider = Provider<ReorderHabits>(
  (ref) => ReorderHabits(
    ref.watch(habitRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, bool)`.
final setHabitArchivedProvider = Provider<SetHabitArchived>(
  (ref) => SetHabitArchived(
    ref.watch(habitRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id)` — also deletes every log of the habit (confirm first).
final deleteHabitProvider = Provider<DeleteHabit>(
  (ref) => DeleteHabit(ref.watch(habitRepositoryProvider)),
);

/// Build: `(habitId, day:, value:, add: true, note:)` → today's `done` row.
final checkInHabitProvider = Provider<CheckInHabit>(
  (ref) => CheckInHabit(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Build: `(habitId, day)` removes the day's `done` row.
final undoHabitCheckInProvider = Provider<UndoHabitCheckIn>(
  (ref) => UndoHabitCheckIn(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
  ),
);

/// Build: `(habitId, day:, note:)` — ≤ 2 per rolling 7 days.
final skipHabitDayProvider = Provider<SkipHabitDay>(
  (ref) => SkipHabitDay(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final unskipHabitDayProvider = Provider<UnskipHabitDay>(
  (ref) => UnskipHabitDay(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
  ),
);

/// Quit: `(habitId, day:, note:)` — "Hari ini bersih ✅".
final confirmCleanDayProvider = Provider<ConfirmCleanDay>(
  (ref) => ConfirmCleanDay(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final undoCleanDayProvider = Provider<UndoCleanDay>(
  (ref) => UndoCleanDay(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
  ),
);

/// Quit: `(habitId, at:, triggers:, note:)` — urge resisted +1.
final logUrgeProvider = Provider<LogUrge>(
  (ref) => LogUrge(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Quit: `(habitId, RelapseInput(...))` → `(log, previousStreak)`.
final logRelapseProvider = Provider<LogRelapse>(
  (ref) => LogRelapse(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Quit, emergency screen "Aku kalah kali ini": urge −1 + relapse.
final convertUrgeToRelapseProvider = Provider<ConvertUrgeToRelapse>(
  (ref) => ConvertUrgeToRelapse(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(habitId, day, note, type:)` — journal note on the day's row.
final setHabitJournalProvider = Provider<SetHabitJournal>(
  (ref) => SetHabitJournal(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(logId)`.
final deleteHabitLogProvider = Provider<DeleteHabitLog>(
  (ref) => DeleteHabitLog(ref.watch(habitLogRepositoryProvider)),
);

// ---------------------------------------------------------------- reads

/// Non-archived habits in order.
final watchHabitsProvider = StreamProvider.autoDispose<List<Habit>>(
  (ref) => WatchHabits(ref.watch(habitRepositoryProvider))(),
);

/// Every habit incl. archived.
final watchAllHabitsProvider = StreamProvider.autoDispose<List<Habit>>(
  (ref) =>
      WatchHabits(ref.watch(habitRepositoryProvider))(includeArchived: true),
);

/// The today board (home card "Kebiasaan hari ini", habit list).
final watchHabitBoardProvider = StreamProvider.autoDispose<HabitBoard>(
  (ref) => WatchHabitBoard(
    ref.watch(habitRepositoryProvider),
    ref.watch(habitLogRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(),
);

/// One habit's today state (null when deleted).
final watchHabitTodayProvider = StreamProvider.autoDispose
    .family<HabitToday?, String>(
      (ref, id) => WatchHabitToday(
        ref.watch(habitRepositoryProvider),
        ref.watch(habitLogRepositoryProvider),
        ref.watch(tickSourceProvider),
      )(id),
    );

/// Habit detail for `(id:, range:)` — use `habitRangeLastDays(now, 30)` /
/// `habitRangeOfMonth(YearMonth(y, m))`.
final watchHabitDetailProvider = StreamProvider.autoDispose
    .family<HabitDetail?, ({String id, HabitRange range})>(
      (ref, a) => WatchHabitDetail(
        ref.watch(habitRepositoryProvider),
        ref.watch(habitLogRepositoryProvider),
        ref.watch(tickSourceProvider),
      )(a.id, a.range),
    );

// ================================================================ investments

// ---------------------------------------------------------------- writes

/// `(AssetInput(...))` → [Asset]; duplicate kind+symbol →
/// `ValidationFailure(field: 'symbol')`.
final createAssetProvider = Provider<CreateAsset>(
  (ref) => CreateAsset(
    ref.watch(assetRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateAssetProvider = Provider<UpdateAsset>(
  (ref) => UpdateAsset(
    ref.watch(assetRepositoryProvider),
    ref.watch(walletRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, price, at:)` — manual assets.
final updateManualPriceProvider = Provider<UpdateManualPrice>(
  (ref) => UpdateManualPrice(
    ref.watch(assetRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setAssetArchivedProvider = Provider<SetAssetArchived>(
  (ref) => SetAssetArchived(
    ref.watch(assetRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final reorderAssetsProvider = Provider<ReorderAssets>(
  (ref) => ReorderAssets(
    ref.watch(assetRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, deleteCashTransactions: true)` — asset + trades (+ their cash
/// transactions).
final deleteAssetProvider = Provider<DeleteAsset>(
  (ref) => DeleteAsset(
    ref.watch(assetRepositoryProvider),
    ref.watch(assetTradeRepositoryProvider),
    ref.watch(deleteTransactionProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(unitOfWorkProvider),
  ),
);

/// `(kind, symbol)` → [SymbolInfo]? (online; null = unknown ticker).
final lookupSymbolProvider = Provider<LookupSymbol>(
  (ref) => LookupSymbol(ref.watch(priceRepositoryProvider)),
);

final _tradeUseCasesProvider = Provider(
  (ref) => tradeUseCases(
    assets: ref.watch(assetRepositoryProvider),
    trades: ref.watch(assetTradeRepositoryProvider),
    transactions: ref.watch(transactionRepositoryProvider),
    createTx: ref.watch(createTransactionProvider),
    updateTx: ref.watch(updateTransactionProvider),
    deleteTx: ref.watch(deleteTransactionProvider),
    dividendCategory: EnsureDividendCategory(
      ref.watch(categoryRepositoryProvider),
      ref.watch(clockProvider),
      userId: ref.watch(currentUserProvider)?.id,
    ),
    uow: ref.watch(unitOfWorkProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// `(TradeInput(...))` → [TradeView] (trade + linked transaction).
final createTradeProvider = Provider<CreateTrade>(
  (ref) => ref.watch(_tradeUseCasesProvider).create,
);

/// `(id, TradeInput)` → [TradeView].
final updateTradeProvider = Provider<UpdateTrade>(
  (ref) => ref.watch(_tradeUseCasesProvider).update,
);

/// `(id)` — trade + its linked transaction.
final deleteTradeProvider = Provider<DeleteTrade>(
  (ref) => ref.watch(_tradeUseCasesProvider).delete,
);

final recordPortfolioSnapshotProvider = Provider<RecordPortfolioSnapshot>(
  (ref) => RecordPortfolioSnapshot(
    ref.watch(assetRepositoryProvider),
    ref.watch(assetTradeRepositoryProvider),
    ref.watch(priceRepositoryProvider),
    ref.watch(portfolioSnapshotRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `()` → [PriceRefreshResult] (pull-to-refresh; `NetworkFailure` offline).
final refreshPricesProvider = Provider<RefreshPrices>(
  (ref) => RefreshPrices(
    ref.watch(assetRepositoryProvider),
    ref.watch(priceRepositoryProvider),
    ref.watch(recordPortfolioSnapshotProvider),
  ),
);

/// Keeps prices fresh while watched: refresh now, then every 15 min during
/// IDX hours. [watchPortfolioProvider] watches it, so any screen/card
/// showing the portfolio refreshes on open.
final priceAutoRefreshProvider = Provider.autoDispose<PriceAutoRefresher>((
  ref,
) {
  final r = PriceAutoRefresher(
    ref.watch(refreshPricesProvider),
    ref.watch(assetRepositoryProvider),
    ref.watch(tickSourceProvider),
    ref.watch(clockProvider),
  )..start();
  ref.onDispose(r.stop);
  return r;
});

// ---------------------------------------------------------------- reads

final watchPortfolioUseCaseProvider = Provider(
  (ref) => WatchPortfolio(
    ref.watch(assetRepositoryProvider),
    ref.watch(assetTradeRepositoryProvider),
    ref.watch(priceRepositoryProvider),
    ref.watch(tickSourceProvider),
    ref.watch(clockProvider),
  ),
);

/// Non-archived assets in order.
final watchAssetsProvider = StreamProvider.autoDispose<List<Asset>>(
  (ref) => WatchAssets(ref.watch(assetRepositoryProvider))(),
);
final watchAllAssetsProvider = StreamProvider.autoDispose<List<Asset>>(
  (ref) =>
      WatchAssets(ref.watch(assetRepositoryProvider))(includeArchived: true),
);

/// The portfolio summary (also starts [priceAutoRefreshProvider]).
final watchPortfolioProvider = StreamProvider.autoDispose<PortfolioSummary>((
  ref,
) {
  ref.watch(priceAutoRefreshProvider);
  return ref.watch(watchPortfolioUseCaseProvider)();
});

/// Asset detail (null when deleted).
final watchAssetDetailProvider = StreamProvider.autoDispose
    .family<AssetDetail?, String>((ref, id) {
      ref.watch(priceAutoRefreshProvider);
      return WatchAssetDetail(
        ref.watch(assetRepositoryProvider),
        ref.watch(assetTradeRepositoryProvider),
        ref.watch(priceRepositoryProvider),
        ref.watch(transactionRepositoryProvider),
        ref.watch(tickSourceProvider),
        ref.watch(clockProvider),
      )(id);
    });

/// Value history `(from:, to:)` (`YYYY-MM-DD`), today live.
final watchPortfolioHistoryProvider = StreamProvider.autoDispose
    .family<List<PortfolioPoint>, ({String from, String to})>(
      (ref, r) => WatchPortfolioHistory(
        ref.watch(portfolioSnapshotRepositoryProvider),
        ref.watch(watchPortfolioUseCaseProvider),
        ref.watch(clockProvider),
      )(r.from, r.to),
    );

/// Net worth = wallets + portfolio market value.
final watchNetWorthProvider = StreamProvider.autoDispose<NetWorth>(
  (ref) => WatchNetWorth(
    ref.watch(walletRepositoryProvider),
    ref.watch(watchPortfolioUseCaseProvider),
  )(),
);
