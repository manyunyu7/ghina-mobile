/// Pure Screener helpers: calendar-month arithmetic and the shareholder-count
/// change over a period.
library;

import '../entities/screener.dart';

/// [date] minus [months] calendar months, the day clamped to the target
/// month's length (31 Mar − 1 month = 28/29 Feb).
DateTime subtractMonths(DateTime date, int months) {
  final total = date.year * 12 + (date.month - 1) - months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, date.day > last ? last : date.day);
}

/// Percent change of the shareholder count from the last report on or before
/// [months] calendar months before the newest report, to the newest. Null
/// when there is no such base report (history too short) or the base is 0.
/// [history] may come in any order.
double? changeOver(List<ShareholderPoint> history, int months) {
  if (history.length < 2) return null;
  final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
  final newest = sorted.last;
  final cutoff = subtractMonths(newest.date, months);
  ShareholderPoint? base;
  for (final p in sorted) {
    if (p.date.isAfter(cutoff)) break;
    base = p;
  }
  if (base == null || base.count <= 0) return null;
  return (newest.count - base.count) / base.count * 100;
}
