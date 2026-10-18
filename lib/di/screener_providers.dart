/// Composition root, part 7: Screener — online-only, not in sync. Tests
/// override [screenerRepositoryProvider], [stockbitGatewayProvider] and
/// [stockbitSessionStoreProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/remote/screener_api.dart';
import '../data/datasources/remote/stockbit_api.dart';
import '../data/platform/secure_stockbit_session_store.dart';
import '../data/repositories/screener_repository_impl.dart';
import '../domain/repositories/screener_repository.dart';
import '../domain/repositories/stockbit_gateway.dart';
import '../domain/services/stockbit_session_store.dart';
import '../domain/usecases/screener_sync.dart';
import '../domain/usecases/screener_usecases.dart';
import '../domain/usecases/stockbit_session.dart';
import 'core_providers.dart';

final screenerApiProvider = Provider<ScreenerApi>(
  (ref) => DioScreenerApi(ref.watch(apiClientProvider)),
);

final screenerRepositoryProvider = Provider<ScreenerRepository>(
  (ref) => RemoteScreenerRepository(ref.watch(screenerApiProvider)),
);

final loadScreenerProvider = Provider(
  (ref) => LoadScreener(ref.watch(screenerRepositoryProvider)),
);
final loadScreenerStatusProvider = Provider(
  (ref) => LoadScreenerStatus(ref.watch(screenerRepositoryProvider)),
);
final loadScreenerBreadthProvider = Provider(
  (ref) => LoadScreenerBreadth(ref.watch(screenerRepositoryProvider)),
);
final loadScreenerTickerProvider = Provider(
  (ref) => LoadScreenerTicker(ref.watch(screenerRepositoryProvider)),
);

// ---- On-device Stockbit session and sync ----

final stockbitGatewayProvider = Provider<StockbitGateway>(
  (ref) => DioStockbitGateway(),
);

final stockbitSessionStoreProvider = Provider<StockbitSessionStore>(
  (ref) => SecureStockbitSessionStore(),
);

final stockbitSessionServiceProvider = Provider<StockbitSessionService>(
  (ref) => StockbitSessionService(
    store: ref.watch(stockbitSessionStoreProvider),
    gateway: ref.watch(stockbitGatewayProvider),
    clock: ref.watch(clockProvider),
  ),
);

final screenerSyncProvider = Provider<ScreenerSync>(
  (ref) => ScreenerSync(
    source: ref.watch(stockbitSessionServiceProvider),
    repository: ref.watch(screenerRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
