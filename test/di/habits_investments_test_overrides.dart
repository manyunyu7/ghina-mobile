import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ghina/di/core_providers.dart';

import '../domain/fakes.dart';

/// In-memory habits/investments repositories for tests that run the app's
/// providers on fakes (no drift): the dashboard/report net worth, the
/// reminders and the game's activity stream read them. Add to any harness
/// that overrides the other repositories with fakes.
List<Override> habitsInvestmentsFakeOverrides({
  FakeHabitRepository? habits,
  FakeHabitLogRepository? habitLogs,
  FakeHabitFieldRepository? habitFields,
  FakeHabitEventRepository? habitEvents,
  FakeHabitOnline? habitOnline,
  FakeAssetRepository? assets,
  FakeAssetTradeRepository? trades,
  FakePriceRepository? prices,
  FakePortfolioSnapshotRepository? snapshots,
}) => [
  habitRepositoryProvider.overrideWithValue(habits ?? FakeHabitRepository()),
  habitLogRepositoryProvider.overrideWithValue(
    habitLogs ?? FakeHabitLogRepository(),
  ),
  habitFieldRepositoryProvider.overrideWithValue(
    habitFields ?? FakeHabitFieldRepository(),
  ),
  habitEventRepositoryProvider.overrideWithValue(
    habitEvents ?? FakeHabitEventRepository(),
  ),
  habitOnlineRepositoryProvider.overrideWithValue(
    habitOnline ?? FakeHabitOnline(),
  ),
  assetRepositoryProvider.overrideWithValue(assets ?? FakeAssetRepository()),
  assetTradeRepositoryProvider.overrideWithValue(
    trades ?? FakeAssetTradeRepository(),
  ),
  priceRepositoryProvider.overrideWithValue(prices ?? FakePriceRepository()),
  portfolioSnapshotRepositoryProvider.overrideWithValue(
    snapshots ?? FakePortfolioSnapshotRepository(),
  ),
];
