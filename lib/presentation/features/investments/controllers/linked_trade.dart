import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';

/// The trade whose cash effect is transaction [txId] (a wallet row of type
/// `investment`, or a dividend income), with its asset — or null when no
/// trade links to it (the trade isn't synced yet / was unlinked).
///
/// Looks through every asset's trades; portfolios are small and this only
/// lives while the "open the linked trade" screen is up.
final linkedTradeProvider = Provider.autoDispose
    .family<AsyncValue<({Asset asset, AssetTrade trade})?>, String>((
      ref,
      txId,
    ) {
      final assets = ref.watch(watchAllAssetsProvider);
      final list = assets.value;
      if (list == null) {
        return assets.hasError
            ? AsyncError(assets.error!, assets.stackTrace!)
            : const AsyncLoading();
      }
      var pending = false;
      for (final a in list) {
        final d = ref.watch(watchAssetDetailProvider(a.id));
        final detail = d.value;
        if (detail == null) {
          if (d.isLoading) pending = true;
          continue;
        }
        for (final t in detail.trades) {
          if (t.trade.cashTransactionId == txId) {
            return AsyncData((asset: a, trade: t.trade));
          }
        }
      }
      return pending ? const AsyncLoading() : const AsyncData(null);
    });
