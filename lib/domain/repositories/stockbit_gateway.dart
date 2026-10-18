import '../entities/screener.dart';
import '../entities/stockbit.dart';

/// What the phone reads straight from Stockbit (`exodus.stockbit.com`).
/// Every method throws a [StockbitException].
abstract interface class StockbitGateway {
  /// The company list of the screener's universe.
  Future<List<StockbitCompany>> companies(String access);

  /// Shareholder-count reports of [ticker], any order; null = no profile.
  Future<List<ShareholderPoint>?> profile(String access, String ticker);

  /// ~3 years of daily closes of [ticker], oldest first.
  Future<List<PricePoint>> dailyPrices(String access, String ticker);

  /// Spends [refreshToken] for a new pair.
  Future<StockbitTokens> refresh(String refreshToken);
}
