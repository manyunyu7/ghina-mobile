import '../entities/stockbit.dart';

/// Where the Stockbit tokens live: the secure storage of this phone only.
abstract interface class StockbitSessionStore {
  Future<StockbitTokens?> read();
  Future<void> write(StockbitTokens tokens);
  Future<void> clear();
}
