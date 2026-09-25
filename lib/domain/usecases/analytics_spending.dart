/// Spending analytics aggregations (the Analitik page). Pure functions over
/// transactions, categories, wallets and budgets.
///
/// Rules: spending = `expense` rows only (plus outgoing transfers when
/// [AnalyticsFilter.includeTransfers] is on); income = `income` rows only.
/// `adjustment`, `investment` and any other/unknown type never count.
library;

import '../../core/dates.dart';
import '../entities/entities.dart';
import 'analytics_period.dart';

export 'analytics_period.dart';

/// Pseudo category keys.
const kUncategorizedKey = '__none';
const kTransferKey = '__transfer';
const kOtherKey = '__other';

/// Wallet + transfer filters.
final class AnalyticsFilter {
  const AnalyticsFilter({
    this.walletIds = const {},
    this.includeTransfers = false,
  });

  /// Empty = every wallet.
  final Set<String> walletIds;

  /// Count outgoing transfers as spending (off by default).
  final bool includeTransfers;

  bool matchesWallet(String walletId) =>
      walletIds.isEmpty || walletIds.contains(walletId);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsFilter &&
      other.includeTransfers == includeTransfers &&
      other.walletIds.length == walletIds.length &&
      other.walletIds.containsAll(walletIds);

  @override
  int get hashCode =>
      Object.hash(includeTransfers, Object.hashAllUnordered(walletIds));
}

/// One transaction counted as spending, with its resolved category key.
final class SpendItem {
  const SpendItem(this.tx, this.key);
  final Transaction tx;

  /// A category id, [kUncategorizedKey] or [kTransferKey].
  final String key;
  double get amount => tx.amount;
  DateTime get date => tx.date;
}

/// Display info of a category key.
final class CategoryInfo {
  const CategoryInfo({
    required this.key,
    required this.name,
    required this.color,
    required this.icon,
  });
  final String key;
  final String name;
  final String color;
  final String icon;

  static const uncategorized = CategoryInfo(
    key: kUncategorizedKey,
    name: 'Tanpa kategori',
    color: CategoryTotal.uncategorizedColor,
    icon: 'circle',
  );
  static const transfer = CategoryInfo(
    key: kTransferKey,
    name: 'Transfer',
    color: '#3b82f6',
    icon: 'arrow-left-right',
  );
  static const other = CategoryInfo(
    key: kOtherKey,
    name: 'Lainnya',
    color: '#94a3b8',
    icon: 'circle',
  );

  factory CategoryInfo.of(TxCategory c) =>
      CategoryInfo(key: c.id, name: c.name, color: c.color, icon: c.icon);
}

/// Resolves a key (category id or pseudo key) to display info.
CategoryInfo categoryInfo(String key, Map<String, TxCategory> cats) {
  if (key == kTransferKey) return CategoryInfo.transfer;
  if (key == kOtherKey) return CategoryInfo.other;
  final c = cats[key];
  return c == null ? CategoryInfo.uncategorized : CategoryInfo.of(c);
}

/// Spending rows of [txs] within [period] that pass [filter].
List<SpendItem> spendingItems(
  List<Transaction> txs,
  AnalyticsPeriod period,
  AnalyticsFilter filter,
  Map<String, TxCategory> cats,
) {
  final out = <SpendItem>[];
  for (final t in txs) {
    if (!period.contains(t.date)) continue;
    if (!filter.matchesWallet(t.walletId)) continue;
    if (t.type == TxType.expense) {
      if (t.amount <= 0) continue;
      final id = t.categoryId;
      out.add(
        SpendItem(
          t,
          id != null && cats.containsKey(id) ? id : kUncategorizedKey,
        ),
      );
    } else if (t.type == TxType.transfer && filter.includeTransfers) {
      if (t.amount <= 0) continue;
      // With a wallet filter, a transfer between two selected wallets is
      // internal: it moves money but nothing leaves the selection.
      final to = t.toWalletId;
      if (filter.walletIds.isNotEmpty &&
          to != null &&
          filter.walletIds.contains(to)) {
        continue;
      }
      out.add(SpendItem(t, kTransferKey));
    }
  }
  return out;
}

double _sum(Iterable<SpendItem> xs) => xs.fold(0.0, (s, x) => s + x.amount);

/// A category slice of the spending.
final class CategorySpend {
  const CategorySpend({
    required this.info,
    required this.total,
    required this.pct,
    required this.count,
    this.previous = 0,
  });
  final CategoryInfo info;
  final double total;

  /// 0–100 share of the period total.
  final double pct;
  final int count;

  /// Same category in the previous period (0 when compare is off).
  final double previous;

  String get key => info.key;
  String get name => info.name;
  String get color => info.color;
}

/// Totals per category key, largest first.
List<CategorySpend> spendByCategory(
  List<SpendItem> items,
  Map<String, TxCategory> cats, {
  List<SpendItem> previous = const [],
}) {
  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final i in items) {
    sums[i.key] = (sums[i.key] ?? 0) + i.amount;
    counts[i.key] = (counts[i.key] ?? 0) + 1;
  }
  final prev = <String, double>{};
  for (final i in previous) {
    prev[i.key] = (prev[i.key] ?? 0) + i.amount;
  }
  final total = sums.values.fold(0.0, (s, v) => s + v);
  return [
    for (final e in sums.entries)
      CategorySpend(
        info: categoryInfo(e.key, cats),
        total: e.value,
        pct: total > 0 ? e.value / total * 100 : 0,
        count: counts[e.key] ?? 0,
        previous: prev[e.key] ?? 0,
      ),
  ]..sort((a, b) {
    final c = b.total.compareTo(a.total);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
}

/// The first [top] slices plus one "Lainnya" slice for the rest.
List<CategorySpend> topWithOther(List<CategorySpend> rows, {int top = 8}) {
  if (rows.length <= top + 1) return rows;
  final rest = rows.skip(top);
  final total = rows.fold(0.0, (s, r) => s + r.total);
  final restTotal = rest.fold(0.0, (s, r) => s + r.total);
  return [
    ...rows.take(top),
    CategorySpend(
      info: CategoryInfo.other,
      total: restTotal,
      pct: total > 0 ? restTotal / total * 100 : 0,
      count: rest.fold(0, (s, r) => s + r.count),
      previous: rest.fold(0.0, (s, r) => s + r.previous),
    ),
  ];
}

/// One trend bucket.
final class TrendBucket {
  const TrendBucket({
    required this.start,
    required this.end,
    required this.total,
    required this.byKey,
    this.previous,
  });
  final DateTime start;

  /// Last day of the bucket (clamped to the period).
  final DateTime end;
  final double total;

  /// Totals per category key.
  final Map<String, double> byKey;

  /// The aligned bucket of the previous period (null = compare off / none).
  final double? previous;
}

/// Buckets [items] over [period] at [g]. [previousItems] (from
/// [previousPeriod]) are aligned bucket by bucket (index).
List<TrendBucket> spendTrend(
  List<SpendItem> items,
  AnalyticsPeriod period,
  Granularity g, {
  List<SpendItem>? previousItems,
  AnalyticsPeriod? previousPeriod,
}) {
  final starts = bucketStarts(period, g);
  final totals = List<double>.filled(starts.length, 0);
  final byKey = List.generate(starts.length, (_) => <String, double>{});
  for (final i in items) {
    final b = bucketIndex(starts, i.date);
    if (b < 0) continue;
    totals[b] += i.amount;
    byKey[b][i.key] = (byKey[b][i.key] ?? 0) + i.amount;
  }
  List<double>? prev;
  if (previousItems != null && previousPeriod != null) {
    final ps = bucketStarts(previousPeriod, g);
    prev = List<double>.filled(starts.length, 0);
    for (final i in previousItems) {
      final b = bucketIndex(ps, i.date);
      if (b < 0 || b >= prev.length) continue;
      prev[b] += i.amount;
    }
  }
  return [
    for (var k = 0; k < starts.length; k++)
      TrendBucket(
        start: starts[k],
        end: k + 1 < starts.length
            ? DateTime(
                starts[k + 1].year,
                starts[k + 1].month,
                starts[k + 1].day - 1,
              )
            : startOfDay(period.end),
        total: totals[k],
        byKey: byKey[k],
        previous: prev?[k],
      ),
  ];
}

/// Spending per local day (`dateKey` → total) for the heatmap; days without
/// spending are absent.
Map<String, double> dailySpend(List<SpendItem> items) {
  final out = <String, double>{};
  for (final i in items) {
    final k = dateKey(i.date);
    out[k] = (out[k] ?? 0) + i.amount;
  }
  return out;
}

/// Weekday pattern, Monday first.
final class WeekdayStat {
  const WeekdayStat({
    required this.weekday,
    required this.total,
    required this.count,
    required this.days,
  });

  /// 1 = Monday … 7 = Sunday.
  final int weekday;
  final double total;

  /// Transactions.
  final int count;

  /// How many of this weekday are in the (elapsed) period.
  final int days;

  /// Average spend on one such day.
  double get average => days > 0 ? total / days : 0;

  static const shortNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const names = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  String get short => shortNames[weekday - 1];
  String get name => names[weekday - 1];
}

/// Totals per weekday; `days` counts the weekdays of [period] up to [now].
List<WeekdayStat> weekdayPattern(
  List<SpendItem> items,
  AnalyticsPeriod period,
  DateTime now,
) {
  final totals = List<double>.filled(7, 0);
  final counts = List<int>.filled(7, 0);
  for (final i in items) {
    totals[i.date.weekday - 1] += i.amount;
    counts[i.date.weekday - 1]++;
  }
  final days = List<int>.filled(7, 0);
  final n = period.elapsedDays(now);
  for (var k = 0; k < n; k++) {
    final d = DateTime(
      period.start.year,
      period.start.month,
      period.start.day + k,
    );
    days[d.weekday - 1]++;
  }
  return [
    for (var w = 1; w <= 7; w++)
      WeekdayStat(
        weekday: w,
        total: totals[w - 1],
        count: counts[w - 1],
        days: days[w - 1],
      ),
  ];
}

/// Hour-of-day pattern.
final class HourPattern {
  const HourPattern({
    required this.totals,
    required this.counts,
    required this.untimed,
  });

  /// 24 totals, index = hour.
  final List<double> totals;
  final List<int> counts;

  /// Rows stored at exactly 00:00:00.000 (date-only entries): left out.
  final int untimed;

  bool get hasData => counts.any((c) => c > 0);

  /// The hour with the most spending (null without data).
  int? get peakHour {
    if (!hasData) return null;
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (totals[h] > totals[best]) best = h;
    }
    return best;
  }
}

bool _hasTime(DateTime d) =>
    d.hour != 0 || d.minute != 0 || d.second != 0 || d.millisecond != 0;

HourPattern hourPattern(List<SpendItem> items) {
  final totals = List<double>.filled(24, 0);
  final counts = List<int>.filled(24, 0);
  var untimed = 0;
  for (final i in items) {
    if (!_hasTime(i.date)) {
      untimed++;
      continue;
    }
    totals[i.date.hour] += i.amount;
    counts[i.date.hour]++;
  }
  return HourPattern(totals: totals, counts: counts, untimed: untimed);
}

/// Spending per wallet.
final class WalletSpend {
  const WalletSpend({
    required this.walletId,
    required this.wallet,
    required this.total,
    required this.pct,
    required this.count,
  });
  final String walletId;
  final Wallet? wallet;
  final double total;
  final double pct;
  final int count;
  String get name => wallet?.name ?? 'Dompet terhapus';
  String get color => wallet?.color ?? CategoryTotal.uncategorizedColor;
}

List<WalletSpend> spendByWallet(List<SpendItem> items, List<Wallet> wallets) {
  final wm = {for (final w in wallets) w.id: w};
  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final i in items) {
    sums[i.tx.walletId] = (sums[i.tx.walletId] ?? 0) + i.amount;
    counts[i.tx.walletId] = (counts[i.tx.walletId] ?? 0) + 1;
  }
  final total = sums.values.fold(0.0, (s, v) => s + v);
  return [
    for (final e in sums.entries)
      WalletSpend(
        walletId: e.key,
        wallet: wm[e.key],
        total: e.value,
        pct: total > 0 ? e.value / total * 100 : 0,
        count: counts[e.key] ?? 0,
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
}

/// Income vs expense per bucket.
final class FlowBucket {
  const FlowBucket({
    required this.start,
    required this.income,
    required this.expense,
  });
  final DateTime start;
  final double income;
  final double expense;
  double get net => income - expense;
}

/// Income (`income` rows) and expense (`expense` rows) per bucket, same
/// wallet filter; transfers, adjustments and investments never count here.
List<FlowBucket> cashFlow(
  List<Transaction> txs,
  AnalyticsPeriod period,
  Granularity g,
  AnalyticsFilter filter,
) {
  final starts = bucketStarts(period, g);
  final inc = List<double>.filled(starts.length, 0);
  final exp = List<double>.filled(starts.length, 0);
  for (final t in txs) {
    if (!period.contains(t.date) || !filter.matchesWallet(t.walletId)) {
      continue;
    }
    final isInc = t.type == TxType.income;
    final isExp = t.type == TxType.expense;
    if (!isInc && !isExp) continue;
    final b = bucketIndex(starts, t.date);
    if (b < 0) continue;
    if (isInc) inc[b] += t.amount;
    if (isExp) exp[b] += t.amount;
  }
  return [
    for (var k = 0; k < starts.length; k++)
      FlowBucket(start: starts[k], income: inc[k], expense: exp[k]),
  ];
}

/// Most frequent notes ("merchants") of a set of spending rows.
final class NoteStat {
  const NoteStat({
    required this.note,
    required this.count,
    required this.total,
  });
  final String note;
  final int count;
  final double total;
}

/// Groups notes case/space-insensitively (display = the latest spelling);
/// ordered by count, then total. Empty notes are skipped.
List<NoteStat> topNotes(List<SpendItem> items, {int limit = 5}) {
  final groups =
      <String, ({String note, int count, double total, DateTime at})>{};
  for (final i in items) {
    final raw = i.tx.note?.trim();
    if (raw == null || raw.isEmpty) continue;
    final k = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final g = groups[k];
    if (g == null) {
      groups[k] = (note: raw, count: 1, total: i.amount, at: i.date);
    } else {
      final newer = i.date.isAfter(g.at);
      groups[k] = (
        note: newer ? raw : g.note,
        count: g.count + 1,
        total: g.total + i.amount,
        at: newer ? i.date : g.at,
      );
    }
  }
  final rows =
      [
        for (final g in groups.values)
          NoteStat(note: g.note, count: g.count, total: g.total),
      ]..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : b.total.compareTo(a.total);
      });
  return rows.take(limit).toList();
}

/// The KPI block.
final class SpendingKpis {
  const SpendingKpis({
    required this.total,
    required this.count,
    required this.avgPerDay,
    required this.avgPerTx,
    required this.biggestDay,
    required this.biggestDayAmount,
    required this.previousTotal,
    required this.previousToDate,
    required this.projectedMonthEnd,
    required this.elapsedDays,
  });

  final double total;
  final int count;

  /// Over the elapsed days of the period.
  final double avgPerDay;
  final double avgPerTx;
  final DateTime? biggestDay;
  final double biggestDayAmount;

  /// Whole previous period (null = compare off).
  final double? previousTotal;

  /// The previous period cut at the same number of elapsed days (fair
  /// comparison while the current period is still running).
  final double? previousToDate;

  /// Only for the running calendar month.
  final double? projectedMonthEnd;
  final int elapsedDays;

  /// Rp change vs the previous period (same elapsed length).
  double? get delta => previousToDate == null ? null : total - previousToDate!;

  /// % change; null when there is nothing to compare against.
  double? get deltaPct {
    final p = previousToDate;
    if (p == null || p <= 0) return null;
    return (total - p) / p * 100;
  }
}

SpendingKpis spendingKpis({
  required List<SpendItem> items,
  required AnalyticsPeriod period,
  required DateTime now,
  List<SpendItem>? previousItems,
  AnalyticsPeriod? previousPeriod,
}) {
  final total = _sum(items);
  final elapsed = period.elapsedDays(now);
  final daily = dailySpend(items);
  String? bestKey;
  var best = 0.0;
  daily.forEach((k, v) {
    if (v > best ||
        (v == best && bestKey != null && k.compareTo(bestKey!) < 0)) {
      best = v;
      bestKey = k;
    }
  });
  double? prevTotal, prevToDate;
  if (previousItems != null && previousPeriod != null) {
    prevTotal = _sum(previousItems);
    prevToDate = _sum(
      _previousToDate(previousItems, period, previousPeriod, now),
    );
  }
  final running = period.isCalendarMonth && period.contains(now);
  final avgPerDay = elapsed > 0 ? total / elapsed : 0.0;
  return SpendingKpis(
    total: total,
    count: items.length,
    avgPerDay: avgPerDay,
    avgPerTx: items.isEmpty ? 0 : total / items.length,
    biggestDay: bestKey == null ? null : parseDateKey(bestKey!),
    biggestDayAmount: best,
    previousTotal: prevTotal,
    previousToDate: prevToDate,
    projectedMonthEnd: running ? avgPerDay * period.days : null,
    elapsedDays: elapsed,
  );
}

/// The rows of [previous] up to the same elapsed day as [period] at [now]
/// (all of them once [period] is over) — a fair "vs periode lalu" while the
/// current period is still running.
List<SpendItem> _previousToDate(
  List<SpendItem> previous,
  AnalyticsPeriod period,
  AnalyticsPeriod previousPeriod,
  DateTime now,
) {
  final elapsed = period.elapsedDays(now);
  if (elapsed >= period.days) return previous;
  final cut = endOfDay(
    DateTime(
      previousPeriod.start.year,
      previousPeriod.start.month,
      previousPeriod.start.day + (elapsed < 1 ? 1 : elapsed) - 1,
    ),
  );
  return previous.where((i) => !i.date.isAfter(cut)).toList();
}

/// Income vs expense summary for the period.
final class IncomeExpense {
  const IncomeExpense({required this.income, required this.expense});
  final double income;
  final double expense;
  double get net => income - expense;

  /// % of income kept; null without income.
  double? get savingsRate => income > 0 ? net / income * 100 : null;
}

/// Everything on the Analitik page.
final class SpendingAnalytics {
  const SpendingAnalytics({
    required this.period,
    required this.previousPeriod,
    required this.granularity,
    required this.filter,
    required this.compare,
    required this.items,
    required this.kpis,
    required this.categories,
    required this.trend,
    required this.daily,
    required this.weekdays,
    required this.hours,
    required this.wallets,
    required this.flow,
    required this.incomeExpense,
    required this.largest,
  });

  final AnalyticsPeriod period;
  final AnalyticsPeriod previousPeriod;
  final Granularity granularity;
  final AnalyticsFilter filter;
  final bool compare;

  /// Counted spending rows, newest first.
  final List<SpendItem> items;
  final SpendingKpis kpis;
  final List<CategorySpend> categories;
  final List<TrendBucket> trend;
  final Map<String, double> daily;
  final List<WeekdayStat> weekdays;
  final HourPattern hours;
  final List<WalletSpend> wallets;
  final List<FlowBucket> flow;
  final IncomeExpense incomeExpense;

  /// Top 10 largest spending rows.
  final List<SpendItem> largest;

  bool get hasSpending => items.isNotEmpty;
  bool get hasData => hasSpending || incomeExpense.income > 0;
}

/// Builds the whole page. [transactions] must cover [period] and, when
/// [compare] is on, its previous period.
SpendingAnalytics buildSpendingAnalytics({
  required List<Transaction> transactions,
  required List<TxCategory> categories,
  required List<Wallet> wallets,
  required AnalyticsPeriod period,
  required DateTime now,
  AnalyticsFilter filter = const AnalyticsFilter(),
  bool compare = false,
}) {
  final cats = {for (final c in categories) c.id: c};
  final prevPeriod = period.previous();
  final g = granularityFor(period);
  final items = spendingItems(transactions, period, filter, cats)
    ..sort((a, b) => b.date.compareTo(a.date));
  final prevItems = compare
      ? spendingItems(transactions, prevPeriod, filter, cats)
      : null;
  final inc = transactions
      .where(
        (t) =>
            t.type == TxType.income &&
            period.contains(t.date) &&
            filter.matchesWallet(t.walletId),
      )
      .fold(0.0, (s, t) => s + t.amount);
  final exp = transactions
      .where(
        (t) =>
            t.type == TxType.expense &&
            period.contains(t.date) &&
            filter.matchesWallet(t.walletId),
      )
      .fold(0.0, (s, t) => s + t.amount);
  final largest = [...items]
    ..sort((a, b) {
      final c = b.amount.compareTo(a.amount);
      return c != 0 ? c : b.date.compareTo(a.date);
    });
  return SpendingAnalytics(
    period: period,
    previousPeriod: prevPeriod,
    granularity: g,
    filter: filter,
    compare: compare,
    items: items,
    kpis: spendingKpis(
      items: items,
      period: period,
      now: now,
      previousItems: prevItems,
      previousPeriod: compare ? prevPeriod : null,
    ),
    categories: spendByCategory(
      items,
      cats,
      previous: prevItems == null
          ? const []
          : _previousToDate(prevItems, period, prevPeriod, now),
    ),
    trend: spendTrend(
      items,
      period,
      g,
      previousItems: prevItems,
      previousPeriod: compare ? prevPeriod : null,
    ),
    daily: dailySpend(items),
    weekdays: weekdayPattern(items, period, now),
    hours: hourPattern(items),
    wallets: spendByWallet(items, wallets),
    flow: cashFlow(transactions, period, g, filter),
    incomeExpense: IncomeExpense(income: inc, expense: exp),
    largest: largest.take(10).toList(),
  );
}

/// One category drilled in.
final class CategoryAnalytics {
  const CategoryAnalytics({
    required this.info,
    required this.period,
    required this.granularity,
    required this.items,
    required this.total,
    required this.share,
    required this.previousTotal,
    required this.trend,
    required this.weekdays,
    required this.notes,
    required this.largest,
  });

  final CategoryInfo info;
  final AnalyticsPeriod period;
  final Granularity granularity;

  /// Its spending rows, newest first.
  final List<SpendItem> items;
  final double total;

  /// 0–100 share of all spending in the period.
  final double share;
  final double? previousTotal;
  final List<TrendBucket> trend;
  final List<WeekdayStat> weekdays;
  final List<NoteStat> notes;
  final SpendItem? largest;

  int get count => items.length;
  double get avgTicket => items.isEmpty ? 0 : total / items.length;

  double? get deltaPct {
    final p = previousTotal;
    if (p == null || p <= 0) return null;
    return (total - p) / p * 100;
  }
}

/// Drill-down for [key] (a category id or a pseudo key) inside [a].
CategoryAnalytics buildCategoryAnalytics({
  required SpendingAnalytics a,
  required String key,
  required List<Transaction> transactions,
  required List<TxCategory> categories,
  required DateTime now,
}) {
  final cats = {for (final c in categories) c.id: c};
  final items = a.items.where((i) => i.key == key).toList();
  final total = _sum(items);
  // [transactions] always cover the previous period (see
  // [analyticsFetchStart]), so the drill-down compares even with compare off.
  final prevItems = spendingItems(
    transactions,
    a.previousPeriod,
    a.filter,
    cats,
  ).where((i) => i.key == key).toList();
  final largest = items.isEmpty
      ? null
      : items.reduce((x, y) => y.amount > x.amount ? y : x);
  return CategoryAnalytics(
    info: categoryInfo(key, cats),
    period: a.period,
    granularity: a.granularity,
    items: items,
    total: total,
    share: a.kpis.total > 0 ? total / a.kpis.total * 100 : 0,
    previousTotal: _sum(
      _previousToDate(prevItems, a.period, a.previousPeriod, now),
    ),
    trend: spendTrend(
      items,
      a.period,
      a.granularity,
      previousItems: a.compare ? prevItems : null,
      previousPeriod: a.compare ? a.previousPeriod : null,
    ),
    weekdays: weekdayPattern(items, a.period, now),
    notes: topNotes(items),
    largest: largest,
  );
}

/// The month whose budgets the page compares against: the running month when
/// the period includes today, else the period's last month.
YearMonth budgetMonthFor(AnalyticsPeriod p, DateTime now) =>
    p.contains(now) ? YearMonth.of(now) : YearMonth.of(p.end);

/// Share (0–1) of [m] that has passed at [now]: the "should have spent by
/// now" marker on budget bars.
double monthPace(YearMonth m, DateTime now) {
  if (now.isBefore(m.start)) return 0;
  if (now.isAfter(m.end)) return 1;
  return now.day / daysInMonth(m.year, m.month);
}

/// Earliest date the page needs transactions from (the previous period's
/// start, so toggling compare or drilling in needs no refetch).
DateTime analyticsFetchStart(AnalyticsPeriod p) => p.previous().start;
