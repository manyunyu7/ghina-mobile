import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/remote/prices_api.dart';
import 'package:ghina/data/models/habits_investments_wire.dart';
import 'package:ghina/domain/entities/entities.dart';

/// `GET /api/mobile/prices` in memory: [quotes] by `kind:SYMBOL` in the
/// server's wire shape; unknown keys answer `error: not_found`.
class FakePricesApi implements PricesApi {
  FakePricesApi(this.now);

  /// Device clock (receivedAt).
  DateTime Function() now;
  final quotes = <String, Map<String, dynamic>>{};
  bool online = true;
  final calls = <List<String>>[];

  void quote(
    String key, {
    required double price,
    double? prevClose,
    String? name,
    DateTime? fetchedAt,
    bool stale = false,
  }) {
    final p = key.split(':');
    quotes[key] = {
      'kind': p[0],
      'symbol': p[1],
      'name': name,
      'price': price,
      'prevClose': prevClose,
      'change': prevClose == null ? null : price - prevClose,
      'changePct': prevClose == null
          ? null
          : (price - prevClose) / prevClose * 100,
      'currency': 'IDR',
      'asOf': (fetchedAt ?? now()).toUtc().toIso8601String(),
      'fetchedAt': (fetchedAt ?? now()).toUtc().toIso8601String(),
      'source': 'yahoo',
      'stale': stale,
      'error': null,
    };
  }

  @override
  Future<({Map<String, SecurityPrice> prices, List<String> notFound})> fetch(
    List<String> keys,
  ) async {
    calls.add(keys);
    if (!online) throw const NetworkFailure();
    final body = {
      'serverTime': now().millisecondsSinceEpoch,
      'prices': [
        for (final k in keys)
          quotes[k] ??
              {
                'kind': k.split(':')[0],
                'symbol': k.split(':')[1],
                'price': null,
                'error': 'not_found',
                'stale': false,
              },
      ],
    };
    return pricesResponseFromWire(body, receivedAt: now());
  }
}
