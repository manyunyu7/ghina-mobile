/// The Stockbit connection that lives on this device, and what the phone
/// reads from Stockbit. Nothing here is sent to Ghina except the data rows.
library;

import '../usecases/stockbit_parser.dart' show jwtExpiry;
import 'screener.dart' show ScreenerQuoteRow;

/// The pair of tokens kept in the secure storage of the phone.
final class StockbitTokens {
  const StockbitTokens({this.access, this.refresh});

  final String? access;
  final String? refresh;

  /// `exp` of the JWTs (no signature check); null when unreadable.
  DateTime? get accessExpiresAt => access == null ? null : jwtExpiry(access!);
  DateTime? get refreshExpiresAt =>
      refresh == null ? null : jwtExpiry(refresh!);

  bool get isEmpty => access == null && refresh == null;
}

/// Health of the connection on this device.
enum StockbitHealth {
  /// A usable refresh token: the app renews the session by itself.
  auto,
  none,
  expired,
  expiring,
  active;

  /// Whether "Perbarui data" can work.
  bool get usable =>
      this == StockbitHealth.auto ||
      this == StockbitHealth.active ||
      this == StockbitHealth.expiring;
}

/// A line of the Stockbit company list (the screener's universe).
final class StockbitCompany {
  const StockbitCompany({
    required this.symbol,
    this.lastPrice,
    this.changeValue,
    this.changePercent,
    this.volume,
    this.marketCap,
  });

  final String symbol;

  /// Null when the stock is suspended (price "0").
  final double? lastPrice;
  final double? changeValue;
  final double? changePercent;
  final double? volume;
  final double? marketCap;

  ScreenerQuoteRow toQuote() => ScreenerQuoteRow(
    ticker: symbol,
    lastPrice: lastPrice,
    changeValue: changeValue,
    changePercent: changePercent,
    volume: volume,
    marketCap: marketCap,
  );
}

enum StockbitErrorKind {
  /// Nothing saved on this device.
  notConnected,

  /// 401, or 403 with a JSON body: Stockbit refused the token.
  tokenRejected,

  /// 403 with a non-JSON (HTML) body: the network is blocked.
  blocked,

  /// 429 / 5xx that outlived the retries.
  transient,
  network,
  notFound,

  /// The pasted text is waiting for an OTP / device approval.
  pendingVerification,

  /// The pasted text holds no token pair.
  unrecognized,
  unknown,
}

final class StockbitException implements Exception {
  const StockbitException(this.kind, this.message, {this.status});

  final StockbitErrorKind kind;

  /// Indonesian, user-facing.
  final String message;
  final int? status;

  @override
  String toString() => 'StockbitException($kind, $status): $message';
}

/// Phases of an on-device update.
enum ScreenerPhase {
  starting('Menyiapkan…'),
  quotes('Mengambil daftar emiten…'),
  probing('Mengecek laporan terbaru…'),
  profiles('Mengambil laporan pemegang'),
  uploading('Mengirim ke Ghina…'),
  prices('Melengkapi riwayat harga'),
  done('Selesai');

  const ScreenerPhase(this.label);
  final String label;
}

/// Live progress of a sync: [done] of [total] in the current [phase]
/// (total 0 = unknown).
final class ScreenerProgress {
  const ScreenerProgress(this.phase, {this.done = 0, this.total = 0});

  final ScreenerPhase phase;
  final int done;
  final int total;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  String get text =>
      total > 0 &&
          (phase == ScreenerPhase.profiles || phase == ScreenerPhase.prices)
      ? '${phase.label} $done/$total'
      : phase.label;
}

/// A cancel flag shared with a running sync.
final class ScreenerCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

final class ScreenerSyncSummary {
  const ScreenerSyncSummary({
    this.newestReport,
    this.universe = 0,
    this.discovered = const [],
    this.skippedCurrent = 0,
    this.fetched = 0,
    this.missingProfiles = 0,
    this.reportsWritten = 0,
    this.rowsFutureDated = 0,
    this.quotesWritten = 0,
    this.pricesTickers = 0,
    this.pricesWritten = 0,
    this.duration = Duration.zero,
    this.cancelled = false,
  });

  final DateTime? newestReport;
  final int universe;
  final List<String> discovered;
  final int skippedCurrent;
  final int fetched;
  final int missingProfiles;
  final int reportsWritten;
  final int rowsFutureDated;
  final int quotesWritten;

  /// Tickers whose daily closes were backfilled, and rows written for them.
  final int pricesTickers;
  final int pricesWritten;
  final Duration duration;
  final bool cancelled;
}
