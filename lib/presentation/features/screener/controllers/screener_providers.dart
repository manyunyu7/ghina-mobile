import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/screener_sync.dart' show chunked;
import '../../../state/screener_access_provider.dart';

/// Runs a Screener read, remembering the account's access (403 → forbidden).
Future<T> _track<T>(Ref ref, Future<T> Function() body) async {
  try {
    final v = await body();
    ref.read(screenerAccessProvider.notifier).markAllowed();
    return v;
  } on ScreenerException catch (e) {
    if (e.kind == ScreenerErrorKind.forbidden) {
      ref.read(screenerAccessProvider.notifier).markForbidden();
    }
    rethrow;
  }
}

/// Screener errors are answers (403, 404…): never auto-retry.
Duration? _noRetry(int count, Object error) => null;

/// The screen for one set of parameters.
final screenerResultProvider = FutureProvider.autoDispose
    .family<ScreenerResult, ScreenerQuery>(
      (ref, q) => _track(ref, () => ref.watch(loadScreenerProvider)(q)),
      retry: _noRetry,
    );

/// Archive stats + Stockbit connection.
final screenerStatusProvider = FutureProvider.autoDispose<ScreenerStatus>(
  (ref) => _track(ref, () => ref.watch(loadScreenerStatusProvider)()),
  retry: _noRetry,
);

/// History + quote of one ticker.
final screenerTickerProvider = FutureProvider.autoDispose
    .family<ScreenerTicker, String>(
      (ref, t) => _track(ref, () => ref.watch(loadScreenerTickerProvider)(t)),
      retry: _noRetry,
    );

/// Market breadth for the last N months (loaded on its own: a failure here
/// must not block the list).
final screenerBreadthProvider = FutureProvider.autoDispose
    .family<List<BreadthMonth>, int>(
      (ref, months) => _track(
        ref,
        () => ref.watch(loadScreenerBreadthProvider)(months: months),
      ),
      retry: _noRetry,
    );

/// The Stockbit tokens saved on this phone (null = not connected). Invalidate
/// after connecting, disconnecting or a sync (a renewal rewrites them).
final stockbitTokensProvider = FutureProvider.autoDispose<StockbitTokens?>(
  (ref) => ref.watch(stockbitSessionServiceProvider).current(),
);

/// Daily closes of [ticker] read from Stockbit on this phone, pushed to Ghina
/// in the background. Null when there is no local session or it failed.
final screenerDevicePricesProvider = FutureProvider.autoDispose
    .family<List<PricePoint>?, String>((ref, ticker) async {
      final service = ref.watch(stockbitSessionServiceProvider);
      if (await service.current() == null) return null;
      try {
        final points = await service.dailyPrices(ticker);
        if (points.isNotEmpty) {
          final repo = ref.read(screenerRepositoryProvider);
          unawaited(() async {
            try {
              for (final part in chunked([
                for (final p in points)
                  ScreenerPriceRow(
                    ticker: ticker,
                    date: p.date,
                    close: p.close,
                  ),
              ])) {
                await repo.pushPrices(part);
              }
            } catch (_) {
              // Best effort: the chart is already on screen.
            }
          }());
        }
        return points;
      } on StockbitException {
        return null;
      }
    }, retry: _noRetry);
