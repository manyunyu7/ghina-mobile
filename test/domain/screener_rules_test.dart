// Screener pure helpers: Stockbit session health, changeOver, formatting,
// sorting and the decline histogram. All data is invented.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/features/screener/pages/screener_page.dart';
import 'package:ghina/presentation/features/screener/screener_format.dart';
import 'package:ghina/presentation/features/screener/widgets/screener_charts.dart';

final _now = DateTime(2026, 10, 18, 12);

ShareholderPoint _p(int y, int m, int d, int c) =>
    ShareholderPoint(date: DateTime(y, m, d), count: c);

ScreenerRow _row(
  String t,
  double pct, {
  int streak = 1,
  double ratio = 0.5,
  double? price,
  double? cap,
}) => ScreenerRow(
  ticker: t,
  firstCount: 100,
  lastCount: 90,
  change: -10,
  changePercent: pct,
  declineStreak: streak,
  declineRatio: ratio,
  points: 4,
  price: price,
  marketCap: cap,
);

void main() {
  group('changeOver', () {
    final history = [
      _p(2025, 10, 1, 1000),
      _p(2026, 4, 10, 900),
      _p(2026, 7, 1, 880),
      _p(2026, 9, 20, 850),
      _p(2026, 10, 1, 800),
    ];
    test('uses the last report on or before N calendar months back', () {
      // 3 months before 1 Oct 2026 = 1 Jul 2026 → 880 (on the day).
      expect(changeOver(history, 3), closeTo((800 - 880) / 880 * 100, 1e-9));
      // 6 months → 1 Apr 2026: last on/before is 1 Oct 2025.
      expect(changeOver(history, 6), closeTo(-20, 1e-9));
      expect(changeOver(history, 12), closeTo(-20, 1e-9));
    });
    test('null without a base or enough history', () {
      expect(changeOver(history, 36), isNull);
      expect(changeOver([_p(2026, 10, 1, 5)], 3), isNull);
      expect(changeOver(const [], 3), isNull);
    });
    test('order does not matter; a zero base is ignored', () {
      expect(changeOver(history.reversed.toList(), 12), closeTo(-20, 1e-9));
      expect(changeOver([_p(2026, 1, 1, 0), _p(2026, 10, 1, 5)], 6), isNull);
    });
    test('month arithmetic clamps the day', () {
      expect(subtractMonths(DateTime(2026, 3, 31), 1), DateTime(2026, 2, 28));
      expect(subtractMonths(DateTime(2026, 1, 15), 2), DateTime(2025, 11, 15));
    });
  });

  group('formatting', () {
    test('numbers use dots, commas and a real minus', () {
      expect(screenerNum(1234567), '1.234.567');
      expect(screenerNum(-1234), '−1.234');
      expect(screenerNum(12.5, decimals: 1), '12,5');
    });
    test('percent is always signed', () {
      expect(screenerPercent(1.234), '+1,2%');
      expect(screenerPercent(-3.456), '−3,5%');
      expect(screenerPercent(0), '0,0%');
      expect(screenerPercent(-0.01), '0,0%');
    });
    test('compact market cap and axis counts', () {
      expect(screenerMarketCap(1.2e12), '1,2 T');
      expect(screenerMarketCap(850e9), '850 M');
      expect(screenerMarketCap(45e6), '45 Jt');
      expect(screenerMarketCap(5000), '5.000');
      expect(screenerCount(850000), '850 rb');
      expect(screenerCount(1200000), '1,2 Jt');
      expect(screenerCount(640), '640');
    });
    test('relative time', () {
      expect(screenerAgo(_now, _now), 'baru saja');
      expect(
        screenerAgo(_now.subtract(const Duration(minutes: 5)), _now),
        '5 menit lalu',
      );
      expect(
        screenerAgo(_now.subtract(const Duration(hours: 3)), _now),
        '3 jam lalu',
      );
      expect(
        screenerAgo(_now.subtract(const Duration(days: 2)), _now),
        '2 hari lalu',
      );
    });
  });

  group('arrangeRows', () {
    final rows = [
      _row('AAAA', -5, streak: 2, ratio: 0.6, price: 100, cap: 5e9),
      _row('BBBB', -30, streak: 4, ratio: 0.9, price: null, cap: 9e12),
      _row('CCCC', -12, streak: 1, ratio: 0.7, price: 500),
    ];
    List<String> order(ScreenerSort s, [String q = '']) => [
      for (final r in arrangeRows(rows, q, s)) r.ticker,
    ];
    test('sorts', () {
      expect(order(ScreenerSort.change), ['BBBB', 'CCCC', 'AAAA']);
      expect(order(ScreenerSort.streak), ['BBBB', 'AAAA', 'CCCC']);
      expect(order(ScreenerSort.ratio), ['BBBB', 'CCCC', 'AAAA']);
      expect(order(ScreenerSort.price), ['CCCC', 'AAAA', 'BBBB']);
      expect(order(ScreenerSort.marketCap), ['BBBB', 'AAAA', 'CCCC']);
    });
    test('search is a case-insensitive contains', () {
      expect(order(ScreenerSort.change, 'bb'), ['BBBB']);
      expect(order(ScreenerSort.change, 'zz'), isEmpty);
    });
  });

  test('declineHistogram buckets declines only', () {
    final h = declineHistogram([
      _row('A', -2),
      _row('B', -5),
      _row('C', -15),
      _row('D', -39.9),
      _row('E', -80),
      _row('F', 3),
    ]);
    expect(h, [1, 1, 1, 1, 1]);
  });

  test('chart ranges clamp history', () {
    final newest = DateTime(2026, 10, 1);
    expect(ChartRange.all.start(newest), isNull);
    expect(ChartRange.year.start(newest), DateTime(2025, 10, 1));
    final pts = [_p(2024, 1, 1, 1), _p(2025, 10, 1, 2), _p(2026, 10, 1, 3)];
    expect(clampHolders(pts, ChartRange.year.start(newest)).length, 2);
    expect(clampHolders(pts, null).length, 3);
    expect(axisDateLabel(DateTime(2025, 3, 5), withYear: true), 'Mar 2025');
  });
}
