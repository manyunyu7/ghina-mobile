/// The Stockbit session of this device: connect from pasted text, renew, and
/// read Stockbit with a fresh token.
library;

import '../../core/clock.dart';
import '../entities/screener.dart';
import '../entities/stockbit.dart';
import '../repositories/stockbit_gateway.dart';
import '../services/stockbit_session_store.dart';
import 'stockbit_parser.dart';

/// What the sync reads from Stockbit (the session service implements it;
/// tests use fakes).
abstract interface class StockbitSource {
  Future<List<StockbitCompany>> companies();
  Future<List<ShareholderPoint>?> profile(String ticker);
  Future<List<PricePoint>> dailyPrices(String ticker);
}

/// Renew when the access token has less time left than this.
const stockbitRenewWindow = Duration(minutes: 30);

class StockbitSessionService implements StockbitSource {
  StockbitSessionService({
    required this.store,
    required this.gateway,
    required this.clock,
  });

  final StockbitSessionStore store;
  final StockbitGateway gateway;
  final Clock clock;
  Future<StockbitTokens>? _renewing;

  /// The saved tokens, if any.
  Future<StockbitTokens?> current() async {
    final t = await store.read();
    return t == null || t.isEmpty ? null : t;
  }

  Future<void> disconnect() => store.clear();

  /// Reads [text], checks it against Stockbit and saves it only when that
  /// worked. Throws a [StockbitException].
  Future<StockbitTokens> connect(String text) async {
    switch (parseStockbitInput(text)) {
      case StockbitPending():
        throw const StockbitException(
          StockbitErrorKind.pendingVerification,
          stockbitPendingMessage,
        );
      case StockbitUnrecognized():
        throw const StockbitException(
          StockbitErrorKind.unrecognized,
          'Teks ini nggak berisi token Stockbit yang bisa dikenali. '
          'Salin ulang dari browser, ya.',
        );
      case StockbitParsed(:final tokens):
        var t = tokens;
        if (t.access == null || _expiring(t)) {
          // Only a refresh token (or a stale access): spend it right away,
          // the old refresh token is gone after this.
          final r = t.refresh;
          if (r == null) {
            throw const StockbitException(
              StockbitErrorKind.tokenRejected,
              'Token ini sudah kedaluwarsa. Tempel token yang baru.',
            );
          }
          t = await gateway.refresh(r);
          await store.write(t);
        }
        // Verify with a real call; save only if it works.
        await gateway.companies(t.access!);
        await store.write(t);
        return t;
    }
  }

  bool _expiring(StockbitTokens t) {
    final exp = t.accessExpiresAt;
    return exp != null && exp.difference(clock.now()) < stockbitRenewWindow;
  }

  /// A usable access token, renewed first when it ends within 30 minutes.
  /// Concurrent callers share one renewal.
  Future<String> accessToken() async {
    final t = await current();
    if (t == null) {
      throw const StockbitException(
        StockbitErrorKind.notConnected,
        'Stockbit belum terhubung di HP ini.',
      );
    }
    if (t.access != null && !_expiring(t)) return t.access!;
    if (t.refresh == null) {
      if (t.access != null) return t.access!;
      throw const StockbitException(
        StockbitErrorKind.tokenRejected,
        'Sesi Stockbit habis — tempel token baru.',
      );
    }
    final fresh = await (_renewing ??= _renew(
      t.refresh!,
    ).whenComplete(() => _renewing = null));
    return fresh.access!;
  }

  Future<StockbitTokens> _renew(String refresh) async {
    final t = await gateway.refresh(refresh);
    await store.write(t);
    return t;
  }

  @override
  Future<List<StockbitCompany>> companies() async =>
      gateway.companies(await accessToken());

  @override
  Future<List<ShareholderPoint>?> profile(String ticker) async =>
      gateway.profile(await accessToken(), ticker);

  @override
  Future<List<PricePoint>> dailyPrices(String ticker) async =>
      gateway.dailyPrices(await accessToken(), ticker);
}
