/// Screener use cases. Online-only: they throw [ScreenerException] (the
/// presentation layer shows its message; a `forbidden` hides the feature).
library;

import '../entities/screener.dart';
import '../repositories/screener_repository.dart';

final class LoadScreener {
  const LoadScreener(this._repo);
  final ScreenerRepository _repo;

  Future<ScreenerResult> call(ScreenerQuery query) => _repo.screen(query);
}

final class LoadScreenerStatus {
  const LoadScreenerStatus(this._repo);
  final ScreenerRepository _repo;

  Future<ScreenerStatus> call() => _repo.status();
}

final class LoadScreenerBreadth {
  const LoadScreenerBreadth(this._repo);
  final ScreenerRepository _repo;

  Future<List<BreadthMonth>> call({int months = 24}) =>
      _repo.breadth(months: months.clamp(3, 60));
}

final class LoadScreenerTicker {
  const LoadScreenerTicker(this._repo);
  final ScreenerRepository _repo;

  Future<ScreenerTicker> call(String ticker) =>
      _repo.ticker(ticker.trim().toUpperCase());
}
