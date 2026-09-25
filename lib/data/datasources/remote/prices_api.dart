import '../../../core/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../models/habits_investments_wire.dart';
import 'api_client.dart';

/// `GET /api/mobile/prices?symbols=stock:BBCA,crypto:BTC` (`docs/investments.md`).
/// Implementations throw `Failure`s (`NetworkFailure` offline).
abstract interface class PricesApi {
  Future<({Map<String, SecurityPrice> prices, List<String> notFound})> fetch(
    List<String> keys,
  );
}

final class DioPricesApi implements PricesApi {
  DioPricesApi(this._client, [this._clock = const SystemClock()]);
  final ApiClient _client;
  final Clock _clock;

  /// Keys per request (the server batches; keep URLs short).
  static const chunk = 50;

  @override
  Future<({Map<String, SecurityPrice> prices, List<String> notFound})> fetch(
    List<String> keys,
  ) => apiCall(() async {
    final prices = <String, SecurityPrice>{};
    final notFound = <String>[];
    for (var i = 0; i < keys.length; i += chunk) {
      final part = keys.sublist(
        i,
        i + chunk > keys.length ? keys.length : i + chunk,
      );
      final r = await _client.dio.get<Object?>(
        '/api/mobile/prices',
        queryParameters: {'symbols': part.join(',')},
      );
      final parsed = pricesResponseFromWire(r.data, receivedAt: _clock.now());
      prices.addAll(parsed.prices);
      notFound.addAll(parsed.notFound);
    }
    return (prices: prices, notFound: notFound);
  });
}
