import '../entities/screener.dart';

/// Screener (shareholder-count screen). Online-only; every method throws a
/// [ScreenerException] on failure.
abstract interface class ScreenerRepository {
  Future<ScreenerResult> screen(ScreenerQuery query);
  Future<ScreenerStatus> status();

  /// Market-wide breadth per month, oldest first ([months] 3–60).
  Future<List<BreadthMonth>> breadth({int months = 24});

  /// History + quote of one ticker; `notFound` when the archive lacks it.
  Future<ScreenerTicker> ticker(String ticker);

  // ---- Push: the phone reads Stockbit and sends the rows to Ghina. ----

  /// Tickers that already have reports on the server.
  Future<List<String>> known();

  /// Tickers whose newest report is on or after [date].
  Future<List<String>> currentAt(DateTime date);

  /// Each call carries at most `screenerPushChunk` rows. Returns rows written.
  Future<int> pushReports(List<ScreenerReportRow> rows);
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes);
  Future<int> pushPrices(List<ScreenerPriceRow> rows);

  /// Daily-close coverage per ticker.
  Future<Map<String, PriceCoverage>> priceCoverage();

  /// Tickers that currently pass the screener.
  Future<List<String>> priority();
}

/// Rows per request (nginx caps a body at 1 MB).
const screenerPushChunk = 1500;
