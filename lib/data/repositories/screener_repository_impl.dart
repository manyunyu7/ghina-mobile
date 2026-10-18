import '../../domain/entities/screener.dart';
import '../../domain/repositories/screener_repository.dart';
import '../datasources/remote/screener_api.dart';

/// [ScreenerRepository] straight over the API — online-only, no local table,
/// not part of sync.
class RemoteScreenerRepository implements ScreenerRepository {
  RemoteScreenerRepository(this._api);
  final ScreenerApi _api;

  @override
  Future<ScreenerResult> screen(ScreenerQuery query) => _api.screen(query);

  @override
  Future<ScreenerStatus> status() => _api.status();

  @override
  Future<List<BreadthMonth>> breadth({int months = 24}) =>
      _api.breadth(months: months);

  @override
  Future<ScreenerTicker> ticker(String ticker) => _api.ticker(ticker);

  @override
  Future<List<String>> known() => _api.known();

  @override
  Future<List<String>> currentAt(DateTime date) => _api.currentAt(date);

  @override
  Future<int> pushReports(List<ScreenerReportRow> rows) =>
      _api.pushReports(rows);

  @override
  Future<int> pushQuotes(List<ScreenerQuoteRow> quotes) =>
      _api.pushQuotes(quotes);

  @override
  Future<int> pushPrices(List<ScreenerPriceRow> rows) => _api.pushPrices(rows);

  @override
  Future<Map<String, PriceCoverage>> priceCoverage() => _api.priceCoverage();

  @override
  Future<List<String>> priority() => _api.priority();
}
