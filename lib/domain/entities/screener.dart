/// Screener (saham: jumlah pemegang yang menurun) — read models of the
/// Screener mobile API. Online-only, never stored. Dates of reports are plain
/// calendar days (`yyyy-mm-dd`, parsed as a local midnight).
library;

/// How the screener decides that a ticker's shareholder count is "falling".
enum ScreenerMode {
  /// Most steps went down (`threshold` of the steps).
  majority('majority', 'Mayoritas turun'),

  /// Every step went down.
  strict('strict', 'Turun terus'),

  /// Only the first vs the last report.
  endpoint('endpoint', 'Awal vs akhir');

  const ScreenerMode(this.wire, this.label);

  /// Value of the `mode` query parameter.
  final String wire;
  final String label;

  static ScreenerMode fromWire(Object? v) => ScreenerMode.values.firstWhere(
    (m) => m.wire == v,
    orElse: () => ScreenerMode.majority,
  );
}

/// The screener's parameters (also the cache key of a result).
final class ScreenerQuery {
  const ScreenerQuery({
    this.months = 6,
    this.mode = ScreenerMode.majority,
    this.threshold = 0.6,
    this.minPoints = 2,
  });

  final int months;
  final ScreenerMode mode;

  /// 0..1; only used by [ScreenerMode.majority].
  final double threshold;

  /// Minimum number of reports a ticker needs inside the window.
  final int minPoints;

  ScreenerQuery copyWith({
    int? months,
    ScreenerMode? mode,
    double? threshold,
    int? minPoints,
  }) => ScreenerQuery(
    months: months ?? this.months,
    mode: mode ?? this.mode,
    threshold: threshold ?? this.threshold,
    minPoints: minPoints ?? this.minPoints,
  );

  @override
  bool operator ==(Object other) =>
      other is ScreenerQuery &&
      other.months == months &&
      other.mode == mode &&
      other.threshold == threshold &&
      other.minPoints == minPoints;

  @override
  int get hashCode => Object.hash(months, mode, threshold, minPoints);
}

/// One ticker that passed the screen.
final class ScreenerRow {
  const ScreenerRow({
    required this.ticker,
    this.firstDate,
    this.lastDate,
    required this.firstCount,
    required this.lastCount,
    required this.change,
    required this.changePercent,
    required this.declineStreak,
    required this.declineRatio,
    required this.points,
    this.price,
    this.priceChangePercent,
    this.volume,
    this.marketCap,
    this.spark = const [],
  });

  final String ticker;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final int firstCount;
  final int lastCount;
  final int change;

  /// Negative = fewer shareholders (the signal).
  final double changePercent;

  /// Consecutive falling reports, counted back from the newest.
  final int declineStreak;

  /// 0..1: share of the steps that fell.
  final double declineRatio;
  final int points;
  final double? price;
  final double? priceChangePercent;
  final double? volume;
  final double? marketCap;

  /// Shareholder counts inside the window, oldest first (sparkline).
  final List<double> spark;
}

final class ScreenerResult {
  const ScreenerResult({
    required this.query,
    required this.rows,
    this.from,
    this.to,
    required this.scanned,
  });

  /// The parameters the server actually applied.
  final ScreenerQuery query;
  final List<ScreenerRow> rows;
  final DateTime? from;
  final DateTime? to;

  /// Tickers looked at before filtering.
  final int scanned;
}

final class ScreenerArchiveStats {
  const ScreenerArchiveStats({
    required this.rows,
    required this.tickers,
    this.oldest,
  });

  final int rows;
  final int tickers;
  final DateTime? oldest;
}

final class ScreenerStatus {
  const ScreenerStatus({
    required this.stats,
    this.anchor,
    this.reportsUpdatedAt,
    this.quotesFetchedAt,
  });

  final ScreenerArchiveStats stats;

  /// Date of the newest report in the archive.
  final DateTime? anchor;
  final DateTime? reportsUpdatedAt;
  final DateTime? quotesFetchedAt;
}

/// One shareholder-count report of a ticker.
final class ShareholderPoint {
  const ShareholderPoint({required this.date, required this.count});

  final DateTime date;
  final int count;
}

final class ScreenerQuote {
  const ScreenerQuote({
    this.lastPrice,
    this.changeValue,
    this.changePercent,
    this.volume,
    this.marketCap,
    this.fetchedAt,
  });

  final double? lastPrice;
  final double? changeValue;
  final double? changePercent;
  final double? volume;
  final double? marketCap;
  final DateTime? fetchedAt;
}

/// Whether the daily closes of a ticker could be loaded.
enum ScreenerPricesStatus {
  ok,

  /// No Stockbit connection, so no prices.
  notConnected,
  error,
}

/// One daily close.
final class PricePoint {
  const PricePoint({required this.date, required this.close});

  final DateTime date;
  final double close;
}

final class ScreenerPrices {
  const ScreenerPrices({
    this.status = ScreenerPricesStatus.error,
    this.points = const [],
    this.message,
  });

  final ScreenerPricesStatus status;

  /// Oldest first; empty unless [status] is ok.
  final List<PricePoint> points;
  final String? message;

  bool get hasData => status == ScreenerPricesStatus.ok && points.length >= 2;
}

/// Market breadth of one month: tickers whose shareholder count fell / rose.
final class BreadthMonth {
  const BreadthMonth({
    required this.month,
    required this.declining,
    required this.rising,
    required this.flat,
  });

  /// First day of the month.
  final DateTime month;
  final int declining;
  final int rising;
  final int flat;

  int get total => declining + rising + flat;

  /// 0..100; null when the month has no tickers.
  double? get decliningPercent => total == 0 ? null : declining / total * 100;
}

final class ScreenerTicker {
  const ScreenerTicker({
    required this.ticker,
    required this.history,
    this.quote,
    this.prices = const ScreenerPrices(),
  });

  final String ticker;
  final ScreenerPrices prices;

  /// Oldest first.
  final List<ShareholderPoint> history;
  final ScreenerQuote? quote;
}

enum ScreenerErrorKind {
  /// 403: this account isn't allowlisted.
  forbidden,

  /// 401: the app session expired.
  unauthorized,
  network,
  timeout,
  notFound,

  /// 400 / 422: the server refused the input.
  invalid,
  unknown,
}

/// Every Screener call throws this; [message] is Indonesian and user-facing.
final class ScreenerException implements Exception {
  const ScreenerException(this.kind, this.message, {this.status, this.code});

  final ScreenerErrorKind kind;
  final String message;
  final int? status;

  /// The server's machine-readable `code`, when it sent one.
  final String? code;

  @override
  String toString() => 'ScreenerException($kind, $status, $code): $message';
}

/// One row pushed to Ghina: a shareholder-count report.
final class ScreenerReportRow {
  const ScreenerReportRow({
    required this.ticker,
    required this.date,
    required this.count,
  });

  final String ticker;
  final DateTime date;
  final int count;
}

/// One row pushed to Ghina: today's quote of a ticker (nullable numbers).
final class ScreenerQuoteRow {
  const ScreenerQuoteRow({
    required this.ticker,
    this.lastPrice,
    this.changeValue,
    this.changePercent,
    this.volume,
    this.marketCap,
  });

  final String ticker;
  final double? lastPrice;
  final double? changeValue;
  final double? changePercent;
  final double? volume;
  final double? marketCap;
}

/// One row pushed to Ghina: a daily close.
final class ScreenerPriceRow {
  const ScreenerPriceRow({
    required this.ticker,
    required this.date,
    required this.close,
  });

  final String ticker;
  final DateTime date;
  final double close;
}

/// What Ghina already holds of the daily closes of a ticker.
final class PriceCoverage {
  const PriceCoverage({this.first, this.last, required this.count});

  final DateTime? first;
  final DateTime? last;
  final int count;
}
