/// Indonesian number / date formatting of the Screener screens: dot
/// thousands, comma decimals, a real minus sign (U+2212).
library;

import '../../../core/formatters.dart';

const _minus = '−';

/// `1.234`, `−1.234`, `12,5` (with [decimals]).
String screenerNum(num n, {int decimals = 0}) =>
    Fmt.number(n, decimals: decimals).replaceAll('-', _minus);

/// Always signed: `+1,2%`, `−3,4%`, `0,0%`. A value that rounds to zero
/// carries no sign.
String screenerPercent(num v, {int decimals = 1}) {
  final rounded = double.parse(v.toStringAsFixed(decimals));
  final body = '${screenerNum(rounded.abs(), decimals: decimals)}%';
  if (rounded > 0) return '+$body';
  if (rounded < 0) return '$_minus$body';
  return body;
}

/// `+1.200` / `−350` (a count step).
String screenerSigned(int v) =>
    v > 0 ? '+${screenerNum(v)}' : (v < 0 ? screenerNum(v) : '0');

String _scaled(double v) {
  final s = screenerNum(v, decimals: v < 10 ? 1 : 0);
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// Market cap: `1,2 T`, `850 M`, `45 Jt`; below a million it is plain.
String screenerMarketCap(num v) {
  final a = v.abs();
  if (a >= 1e12) return '${_scaled(v / 1e12)} T';
  if (a >= 1e9) return '${_scaled(v / 1e9)} M';
  if (a >= 1e6) return '${_scaled(v / 1e6)} Jt';
  return screenerNum(v);
}

/// Axis label of a shareholder count: `850 rb`, `1,2 Jt`, `640`.
String screenerCount(num v) {
  final a = v.abs();
  if (a >= 1e6) return '${_scaled(v / 1e6)} Jt';
  if (a >= 1e3) return '${_scaled(v / 1e3)} rb';
  return screenerNum(v);
}

/// `5 menit lalu`, `3 jam lalu`, `2 hari lalu`, else the date.
String screenerAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  if (d.inDays < 30) return '${d.inDays} hari lalu';
  return Fmt.date(t);
}

/// `18 Okt 2026 14.05`
String screenerDateTime(DateTime t) => '${Fmt.date(t)} ${Fmt.time(t)}';
