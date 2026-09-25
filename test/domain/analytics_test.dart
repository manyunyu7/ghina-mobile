import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/analytics_spending.dart';

final _t0 = DateTime(2026, 1, 1);
var _n = 0;

Transaction tx(
  TxType type,
  double amount,
  DateTime date, {
  String? cat,
  String wallet = 'w1',
  String? to,
  String? note,
}) => Transaction(
  id: 't${_n++}',
  walletId: wallet,
  toWalletId: to,
  categoryId: cat,
  type: type,
  amount: amount,
  note: note,
  date: date,
  createdAt: _t0,
  updatedAt: _t0,
);

TxCategory cat(String id, String name) => TxCategory(
  id: id,
  name: name,
  type: CategoryType.expense,
  color: '#f97316',
  icon: 'utensils',
  createdAt: _t0,
  updatedAt: _t0,
);

Wallet wallet(String id, String name) => Wallet(
  id: id,
  name: name,
  type: WalletType.bank,
  balance: 0,
  syncedBalance: 0,
  currency: 'IDR',
  color: '#3b82f6',
  icon: 'wallet',
  archived: false,
  createdAt: _t0,
  updatedAt: _t0,
);

final now = DateTime(2026, 9, 23, 12); // Wednesday
final cats = [cat('food', 'Makan'), cat('fun', 'Hiburan')];
final wallets = [wallet('w1', 'BCA'), wallet('w2', 'GoPay')];

void main() {
  group('periods', () {
    test('presets resolve around now', () {
      final w = resolveAnalyticsPeriod(AnalyticsPreset.thisWeek, now);
      expect(w.start, DateTime(2026, 9, 21));
      expect(w.end, endOfDay(DateTime(2026, 9, 27)));
      expect(w.days, 7);
      expect(w.elapsedDays(now), 3);

      final m = resolveAnalyticsPeriod(AnalyticsPreset.thisMonth, now);
      expect(m.start, DateTime(2026, 9, 1));
      expect(m.days, 30);
      expect(m.isCalendarMonth, isTrue);

      final lm = resolveAnalyticsPeriod(AnalyticsPreset.lastMonth, now);
      expect(lm.start, DateTime(2026, 8, 1));
      expect(lm.end, YearMonth(2026, 8).end);
      expect(lm.elapsedDays(now), 31);

      final q = resolveAnalyticsPeriod(AnalyticsPreset.last3Months, now);
      expect(q.start, DateTime(2026, 7, 1));
      expect(q.end, YearMonth(2026, 9).end);

      final y = resolveAnalyticsPeriod(AnalyticsPreset.thisYear, now);
      expect(y.start, DateTime(2026, 1, 1));
      expect(y.days, 365);

      final c = resolveAnalyticsPeriod(
        AnalyticsPreset.custom,
        now,
        from: DateTime(2026, 9, 10, 15),
        to: DateTime(2026, 9, 1),
      );
      expect(c.start, DateTime(2026, 9, 1)); // swapped + midnight
      expect(c.end, endOfDay(DateTime(2026, 9, 10)));
    });

    test('previous periods keep the same shape', () {
      final w = resolveAnalyticsPeriod(
        AnalyticsPreset.thisWeek,
        now,
      ).previous();
      expect(w.start, DateTime(2026, 9, 14));
      expect(w.end, endOfDay(DateTime(2026, 9, 20)));

      final m = resolveAnalyticsPeriod(
        AnalyticsPreset.thisMonth,
        now,
      ).previous();
      expect(m.start, DateTime(2026, 8, 1));
      expect(m.end, YearMonth(2026, 8).end);

      final six = resolveAnalyticsPeriod(
        AnalyticsPreset.last6Months,
        now,
      ).previous();
      expect(six.start, DateTime(2025, 10, 1));
      expect(six.end, YearMonth(2026, 3).end);

      final y = resolveAnalyticsPeriod(
        AnalyticsPreset.thisYear,
        now,
      ).previous();
      expect(y.start, DateTime(2025, 1, 1));
      expect(y.end, endOfDay(DateTime(2025, 12, 31)));

      final c = resolveAnalyticsPeriod(
        AnalyticsPreset.custom,
        now,
        from: DateTime(2026, 9, 11),
        to: DateTime(2026, 9, 20),
      ).previous();
      expect(c.start, DateTime(2026, 9, 1));
      expect(c.end, endOfDay(DateTime(2026, 9, 10)));
    });

    test('granularity and buckets', () {
      final m = resolveAnalyticsPeriod(AnalyticsPreset.thisMonth, now);
      expect(granularityFor(m), Granularity.day);
      expect(bucketStarts(m, Granularity.day), hasLength(30));

      final q = resolveAnalyticsPeriod(AnalyticsPreset.last3Months, now);
      expect(granularityFor(q), Granularity.week);
      final weeks = bucketStarts(q, Granularity.week);
      expect(weeks.first, DateTime(2026, 7, 1)); // mid-week first bucket
      expect(weeks[1], DateTime(2026, 7, 6)); // then Mondays
      expect(weeks.every((d) => d == weeks.first || d.weekday == 1), isTrue);

      final y = resolveAnalyticsPeriod(AnalyticsPreset.last12Months, now);
      expect(granularityFor(y), Granularity.month);
      expect(bucketStarts(y, Granularity.month), hasLength(12));
      expect(bucketIndex(weeks, DateTime(2026, 7, 8, 10)), 1);
      expect(bucketIndex(weeks, DateTime(2026, 6, 30)), -1);
    });
  });

  group('aggregation', () {
    final txs = [
      tx(TxType.expense, 100000, DateTime(2026, 9, 1, 8), cat: 'food'),
      tx(TxType.expense, 50000, DateTime(2026, 9, 1, 19), cat: 'fun'),
      tx(
        TxType.expense,
        300000,
        DateTime(2026, 9, 21),
        cat: 'food',
        wallet: 'w2',
        note: 'Kopi',
      ),
      tx(TxType.expense, 20000, DateTime(2026, 9, 22, 9), note: ' kopi '),
      tx(TxType.expense, 30000, DateTime(2026, 9, 22, 9), cat: 'gone'),
      tx(TxType.income, 1000000, DateTime(2026, 9, 1, 9)),
      tx(TxType.adjustment, -500000, DateTime(2026, 9, 2)),
      tx(TxType.adjustment, 900000, DateTime(2026, 9, 3)),
      tx(TxType.transfer, 200000, DateTime(2026, 9, 4), to: 'w2'),
      // Previous month.
      tx(TxType.expense, 80000, DateTime(2026, 8, 1), cat: 'food'),
      tx(TxType.expense, 400000, DateTime(2026, 8, 30), cat: 'fun'),
    ];
    final period = resolveAnalyticsPeriod(AnalyticsPreset.thisMonth, now);

    test('spending = expense only; adjustments and transfers excluded', () {
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
      );
      expect(a.kpis.total, 500000);
      expect(a.kpis.count, 5);
      expect(a.kpis.avgPerTx, 100000);
      expect(a.kpis.avgPerDay, closeTo(500000 / 23, 0.01));
      expect(a.kpis.biggestDay, DateTime(2026, 9, 21));
      expect(a.kpis.biggestDayAmount, 300000);
      expect(a.kpis.projectedMonthEnd, closeTo(500000 / 23 * 30, 0.01));
      expect(a.kpis.previousTotal, isNull);
      expect(a.kpis.deltaPct, isNull);
      expect(a.incomeExpense.income, 1000000);
      expect(a.incomeExpense.expense, 500000);
      expect(a.incomeExpense.savingsRate, 50);
      // Deleted category → Tanpa kategori, merged with the uncategorized row.
      expect(a.categories.map((c) => c.key), [
        'food',
        'fun',
        kUncategorizedKey,
      ]);
      expect(a.categories.first.total, 400000);
      expect(a.categories.first.pct, 80);
      expect(a.categories.last.total, 50000);
      expect(a.largest.first.amount, 300000);
      expect(a.largest, hasLength(5));
    });

    test('investment and adjustment rows never count', () {
      final a = buildSpendingAnalytics(
        transactions: [
          tx(TxType.adjustment, 999, DateTime(2026, 9, 5)),
          tx(TxType.investment, -500000, DateTime(2026, 9, 5, 10)),
          tx(TxType.investment, 250000, DateTime(2026, 9, 6, 10)),
          tx(TxType.expense, 10, DateTime(2026, 9, 5)),
        ],
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
      );
      expect(a.kpis.total, 10);
      expect(a.incomeExpense.expense, 10);
      expect(a.incomeExpense.income, 0);
      expect(a.flow.fold<double>(0, (s, b) => s + b.expense), 10);
      expect(a.hours.untimed, 1);
    });

    test('transfers toggle and wallet filter', () {
      final withT = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
        filter: const AnalyticsFilter(includeTransfers: true),
      );
      expect(withT.kpis.total, 700000);
      expect(withT.categories.any((c) => c.key == kTransferKey), isTrue);
      // Income/expense ignores transfers either way.
      expect(withT.incomeExpense.expense, 500000);

      final w1 = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
        filter: const AnalyticsFilter(walletIds: {'w1'}),
      );
      expect(w1.kpis.total, 200000);
      expect(w1.wallets.single.name, 'BCA');

      // A transfer between two selected wallets is internal.
      final both = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
        filter: const AnalyticsFilter(
          walletIds: {'w1', 'w2'},
          includeTransfers: true,
        ),
      );
      expect(both.kpis.total, 500000);
    });

    test('compare with the previous period (same elapsed days)', () {
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
        compare: true,
      );
      expect(a.kpis.previousTotal, 480000);
      // Aug 1–23 only: the 30th is outside the first 23 days.
      expect(a.kpis.previousToDate, 80000);
      expect(a.kpis.delta, 420000);
      expect(a.kpis.deltaPct, closeTo(525, 0.001));
      expect(a.trend.first.previous, 80000);
      expect(a.trend[29].previous, 400000);
      // Per category too (the "naik X%" insight): Aug 1–23 only.
      expect(a.categories.firstWhere((c) => c.key == 'fun').previous, 0);
      expect(a.categories.firstWhere((c) => c.key == 'food').previous, 80000);
      // Once the period is over, whole periods are compared.
      final end = DateTime(2026, 10, 2, 9);
      final full = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: end,
        compare: true,
      );
      expect(
        full.categories.firstWhere((c) => c.key == 'fun').previous,
        400000,
      );
      expect(
        buildCategoryAnalytics(
          a: full,
          key: 'fun',
          transactions: txs,
          categories: cats,
          now: end,
        ).previousTotal,
        400000,
      );
      expect(
        buildCategoryAnalytics(
          a: a,
          key: 'fun',
          transactions: txs,
          categories: cats,
          now: now,
        ).previousTotal,
        0,
        reason: 'Sep 1–23 vs Aug 1–23, not vs all of August',
      );
    });

    test('finished period compares whole periods; no projection', () {
      final lm = resolveAnalyticsPeriod(AnalyticsPreset.lastMonth, now);
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: lm,
        now: now,
        compare: true,
      );
      expect(a.kpis.total, 480000);
      expect(a.kpis.previousToDate, 0);
      expect(a.kpis.deltaPct, isNull);
      expect(a.kpis.projectedMonthEnd, isNull);
      expect(a.kpis.avgPerDay, closeTo(480000 / 31, 0.01));
    });

    test('trend buckets, stacked keys and weekly granularity', () {
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
      );
      expect(a.granularity, Granularity.day);
      expect(a.trend, hasLength(30));
      expect(a.trend.first.total, 150000);
      expect(a.trend.first.byKey, {'food': 100000, 'fun': 50000});
      expect(a.trend.first.previous, isNull);

      final q = resolveAnalyticsPeriod(AnalyticsPreset.last3Months, now);
      final b = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: q,
        now: now,
      );
      expect(b.granularity, Granularity.week);
      expect(b.trend.fold<double>(0, (s, x) => s + x.total), 980000);
      expect(b.trend.last.end, DateTime(2026, 9, 30));
    });

    test('heatmap, weekday and hour patterns', () {
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
      );
      expect(a.daily['2026-09-01'], 150000);
      expect(a.daily['2026-09-22'], 50000);
      expect(a.daily.containsKey('2026-09-02'), isFalse);

      // Sep 1 2026 = Tuesday, 21 = Monday, 22 = Tuesday.
      final tue = a.weekdays[1];
      expect(tue.short, 'Sel');
      expect(tue.total, 200000);
      expect(tue.count, 4);
      expect(tue.days, 4); // Sep 1, 8, 15, 22 (up to the 23rd)
      expect(tue.average, 50000);
      expect(a.weekdays[0].total, 300000);
      expect(a.weekdays[6].days, 3);

      expect(a.hours.untimed, 1); // the 21st has no time
      expect(a.hours.totals[8], 100000);
      expect(a.hours.totals[9], 50000);
      expect(a.hours.counts[9], 2);
      expect(a.hours.peakHour, 8);
    });

    test('cash flow per bucket', () {
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: resolveAnalyticsPeriod(AnalyticsPreset.last6Months, now),
        now: now,
      );
      expect(a.granularity, Granularity.month);
      expect(a.flow, hasLength(6));
      expect(a.flow.last.income, 1000000);
      expect(a.flow.last.expense, 500000);
      expect(a.flow.last.net, 500000);
      expect(a.flow[4].expense, 480000);
    });

    test('top with Lainnya', () {
      final many = [
        for (var i = 0; i < 12; i++)
          CategorySpend(
            info: CategoryInfo(
              key: 'c$i',
              name: 'C$i',
              color: '#000000',
              icon: 'x',
            ),
            total: 100.0 - i,
            pct: 0,
            count: 1,
          ),
      ];
      final t = topWithOther(many);
      expect(t, hasLength(9));
      expect(t.last.key, kOtherKey);
      expect(t.last.total, 92 + 91 + 90 + 89);
      expect(t.last.count, 4);
      expect(topWithOther(many.take(9).toList()), hasLength(9));
    });

    test('empty data', () {
      final a = buildSpendingAnalytics(
        transactions: const [],
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
        compare: true,
      );
      expect(a.hasData, isFalse);
      expect(a.kpis.total, 0);
      expect(a.kpis.avgPerTx, 0);
      expect(a.kpis.biggestDay, isNull);
      expect(a.kpis.deltaPct, isNull);
      expect(a.hours.peakHour, isNull);
      expect(a.incomeExpense.savingsRate, isNull);
    });

    test('future period has no elapsed days', () {
      final p = resolveAnalyticsPeriod(
        AnalyticsPreset.custom,
        now,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: p,
        now: now,
      );
      expect(a.kpis.elapsedDays, 0);
      expect(a.kpis.avgPerDay, 0);
      expect(a.kpis.projectedMonthEnd, isNull);
    });
  });

  group('category drill-down', () {
    test('trend, notes, average ticket, previous', () {
      final txs = [
        tx(
          TxType.expense,
          25000,
          DateTime(2026, 9, 2, 8),
          cat: 'food',
          note: 'Kopi Kenangan',
        ),
        tx(
          TxType.expense,
          27000,
          DateTime(2026, 9, 9, 8),
          cat: 'food',
          note: 'kopi  kenangan',
        ),
        tx(
          TxType.expense,
          150000,
          DateTime(2026, 9, 12, 13),
          cat: 'food',
          note: 'Sushi',
        ),
        tx(TxType.expense, 10000, DateTime(2026, 9, 13), cat: 'food'),
        tx(TxType.expense, 99000, DateTime(2026, 9, 13), cat: 'fun'),
        tx(TxType.expense, 50000, DateTime(2026, 8, 3), cat: 'food'),
      ];
      final period = resolveAnalyticsPeriod(AnalyticsPreset.thisMonth, now);
      final a = buildSpendingAnalytics(
        transactions: txs,
        categories: cats,
        wallets: wallets,
        period: period,
        now: now,
      );
      final c = buildCategoryAnalytics(
        a: a,
        key: 'food',
        transactions: txs,
        categories: cats,
        now: now,
      );
      expect(c.info.name, 'Makan');
      expect(c.count, 4);
      expect(c.total, 212000);
      expect(c.avgTicket, 53000);
      expect(c.share, closeTo(212000 / 311000 * 100, 0.001));
      expect(c.previousTotal, 50000);
      expect(c.deltaPct, closeTo(324, 0.001));
      expect(c.notes.first.note, 'kopi  kenangan'); // latest spelling
      expect(c.notes.first.count, 2);
      expect(c.notes.first.total, 52000);
      expect(c.notes, hasLength(2));
      expect(c.largest!.amount, 150000);
      expect(c.trend[1].total, 25000);
      expect(c.trend[1].previous, isNull); // compare off
      expect(c.weekdays[2].count, 2); // Wednesdays: 2nd and 9th
    });
  });

  group('budgets', () {
    test('budget month and pace', () {
      final p = resolveAnalyticsPeriod(AnalyticsPreset.last3Months, now);
      expect(budgetMonthFor(p, now), YearMonth(2026, 9));
      final lm = resolveAnalyticsPeriod(AnalyticsPreset.lastMonth, now);
      expect(budgetMonthFor(lm, now), YearMonth(2026, 8));
      expect(monthPace(YearMonth(2026, 9), now), closeTo(23 / 30, 1e-9));
      expect(monthPace(YearMonth(2026, 8), now), 1);
      expect(monthPace(YearMonth(2026, 10), now), 0);
      expect(
        analyticsFetchStart(
          resolveAnalyticsPeriod(AnalyticsPreset.thisMonth, now),
        ),
        DateTime(2026, 8, 1),
      );
    });
  });
}
