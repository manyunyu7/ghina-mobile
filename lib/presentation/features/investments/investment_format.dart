import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';

/// Display helpers of the portfolio screens (Indonesian formatting, same
/// rules as the web's `investments/format.ts`).
///
/// Privacy: market prices (last price, per-unit change) are public data and
/// stay visible while balances are hidden — like the web's `fmtPrice`.
/// Everything the user owns (values, cost, average price, P/L, fees, cash)
/// goes through `MoneyText` / `context.money` so it is masked.

/// Market price per unit: up to 2 decimals below 1.000, whole otherwise
/// (`Rp 9.500`, `Rp 152,35`). Not masked.
String fmtPrice(num n, {String currency = 'IDR'}) {
  final c = currency.toUpperCase();
  final frac = n.abs() < 1000 ? 2 : 0;
  final f = NumberFormat.currency(
    locale: c == 'IDR' ? 'id_ID' : 'en_US',
    symbol: c == 'IDR' ? 'Rp ' : GhinaMoney.symbolFor(c),
    decimalDigits: frac,
  );
  var s = f.format(n.abs());
  if (frac > 0) {
    // Drop trailing zero decimals: Rp 152,00 → Rp 152.
    final sep = c == 'IDR' ? ',' : '.';
    s = s.replaceFirst(RegExp('\\${sep}0+\$'), '');
  }
  return n < 0 ? '-$s' : s;
}

/// Grouped quantity with up to [maxFrac] decimals: `1.200`, `0,5`.
String fmtQty(num n, {int maxFrac = 4}) {
  final f = NumberFormat.decimalPattern('id_ID')
    ..maximumFractionDigits = maxFrac;
  return f.format(n);
}

/// `+1,25%` / `−0,80%` / `0,00%`; `–` when unknown.
String fmtPct(double? n, {bool sign = true}) {
  if (n == null || !n.isFinite) return '–';
  final s = Fmt.number(n.abs(), decimals: 2);
  final prefix = n > 0.00499
      ? (sign ? '+' : '')
      : n < -0.00499
      ? '−'
      : '';
  return '$prefix$s%';
}

/// Holding quantity: `12 lot` + `1.200 lembar` for stocks (odd lots show
/// lembar first), `3,5 gram` otherwise.
({String main, String? sub}) qtyLabel(Asset a, double shares) {
  if (a.kind.usesLots) {
    final lembar = '${fmtQty(shares)} lembar';
    return isWholeLots(shares)
        ? (main: '${fmtQty(sharesToLots(shares))} lot', sub: lembar)
        : (
            main: lembar,
            sub: '${fmtQty(sharesToLots(shares), maxFrac: 2)} lot',
          );
  }
  return (main: '${fmtQty(shares, maxFrac: 8)} ${a.unit}'.trim(), sub: null);
}

/// Green / red / muted for a P/L number.
Color plColor(BuildContext context, double? n) {
  if (n == null || n.abs() < 0.005) return context.ghina.textSecondary;
  return n > 0 ? GhinaColors.income.base : GhinaColors.expense.base;
}

/// `▲` / `▼` icon for a change.
IconData plIcon(double? n) => n == null || n.abs() < 0.005
    ? Icons.remove_rounded
    : n > 0
    ? Icons.arrow_drop_up_rounded
    : Icons.arrow_drop_down_rounded;

/// Stable swatch per asset kind (donut, avatars).
ChunkySwatch kindSwatch(AssetKind k) => switch (k) {
  AssetKind.stock => GhinaColors.blue,
  AssetKind.fund => GhinaColors.green,
  AssetKind.gold => GhinaColors.yellow,
  AssetKind.crypto => GhinaColors.orange,
  AssetKind.bond => GhinaColors.purple,
  AssetKind.other => GhinaColors.gray,
};

IconData kindIcon(AssetKind k) => switch (k) {
  AssetKind.stock => Icons.candlestick_chart_rounded,
  AssetKind.fund => Icons.donut_small_rounded,
  AssetKind.gold => Icons.workspace_premium_rounded,
  AssetKind.crypto => Icons.currency_bitcoin_rounded,
  AssetKind.bond => Icons.receipt_long_rounded,
  AssetKind.other => Icons.category_rounded,
};

/// Palette for the per-asset donut (cycled).
const assetSlicePalette = [
  GhinaColors.blue,
  GhinaColors.green,
  GhinaColors.orange,
  GhinaColors.purple,
  GhinaColors.pink,
  GhinaColors.yellow,
  GhinaColors.lime,
  GhinaColors.red,
];

/// `Hari ini 15.10` / `Kemarin 09.02` / `23 Sep 15.10`.
String fmtWhen(DateTime d, DateTime now) =>
    '${Fmt.relativeDay(d, now: now)} ${Fmt.time(d)}';

/// Line under the portfolio value: when prices are from.
String pricesAsOfLabel(DateTime? at, DateTime now) =>
    at == null ? 'Belum ada harga pasar' : 'Harga per ${fmtWhen(at, now)}';

/// Swatch of a trade type (segmented thumb, history icons).
ChunkySwatch tradeSwatch(TradeType t) => switch (t) {
  TradeType.buy => GhinaColors.blue,
  TradeType.sell => GhinaColors.orange,
  TradeType.dividend => GhinaColors.green,
  TradeType.split => GhinaColors.purple,
  TradeType.fee => GhinaColors.gray,
};

IconData tradeIcon(TradeType t) => switch (t) {
  TradeType.buy => Icons.add_shopping_cart_rounded,
  TradeType.sell => Icons.sell_rounded,
  TradeType.dividend => Icons.savings_rounded,
  TradeType.split => Icons.call_split_rounded,
  TradeType.fee => Icons.receipt_rounded,
};
