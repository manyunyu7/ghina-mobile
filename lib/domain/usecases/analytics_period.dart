/// Spending analytics: periods, their previous periods and chart granularity.
/// Pure Dart (no Flutter), tested in `test/domain/analytics_test.dart`.
library;

import '../../core/dates.dart';

/// Quick period choices on the Analitik page.
enum AnalyticsPreset {
  thisWeek('Minggu ini'),
  thisMonth('Bulan ini'),
  lastMonth('Bulan lalu'),
  last3Months('3 bulan'),
  last6Months('6 bulan'),
  last12Months('12 bulan'),
  thisYear('Tahun ini'),
  custom('Pilih tanggal');

  const AnalyticsPreset(this.label);
  final String label;
}

/// Bucket size of the trend charts.
enum Granularity {
  day('Harian'),
  week('Mingguan'),
  month('Bulanan');

  const Granularity(this.label);
  final String label;
}

/// An inclusive range of local days: [start] is midnight, [end] is the last
/// millisecond of its day.
final class AnalyticsPeriod {
  AnalyticsPeriod({
    required DateTime start,
    required DateTime end,
    required this.preset,
    required this.label,
  }) : start = startOfDay(start),
       end = endOfDay(end);

  final DateTime start;
  final DateTime end;
  final AnalyticsPreset preset;
  final String label;

  /// Number of calendar days covered.
  int get days => daysBetween(end, start) + 1;

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  /// Days that already happened (up to and including [now]'s day), ≥ 1 when
  /// the period has started, 0 when it lies completely in the future.
  int elapsedDays(DateTime now) {
    if (now.isBefore(start)) return 0;
    if (now.isAfter(end)) return days;
    return daysBetween(now, start) + 1;
  }

  /// True when the period is exactly one calendar month.
  bool get isCalendarMonth =>
      start.day == 1 &&
      start.year == end.year &&
      start.month == end.month &&
      end.day == daysInMonth(end.year, end.month);

  /// Every local day in the period, oldest first.
  List<DateTime> get dayList => [
    for (var i = 0; i < days; i++)
      DateTime(start.year, start.month, start.day + i),
  ];

  /// The period right before this one, same shape: the previous week /
  /// month(s) / year for calendar presets, else the same number of days.
  AnalyticsPeriod previous() {
    switch (preset) {
      case AnalyticsPreset.thisWeek:
        return AnalyticsPeriod(
          start: addDays(start, -7),
          end: addDays(end, -7),
          preset: preset,
          label: 'Minggu lalu',
        );
      case AnalyticsPreset.thisYear:
        return AnalyticsPeriod(
          start: DateTime(start.year - 1, 1, 1),
          end: DateTime(start.year - 1, 12, 31),
          preset: preset,
          label: 'Tahun ${start.year - 1}',
        );
      case AnalyticsPreset.thisMonth:
      case AnalyticsPreset.lastMonth:
      case AnalyticsPreset.last3Months:
      case AnalyticsPreset.last6Months:
      case AnalyticsPreset.last12Months:
        final first = YearMonth.of(start);
        final last = YearMonth.of(end);
        final n = (last.year - first.year) * 12 + last.month - first.month + 1;
        return AnalyticsPeriod(
          start: first.plus(-n).start,
          end: last.plus(-n).end,
          preset: preset,
          label: switch (preset) {
            AnalyticsPreset.thisMonth => 'Bulan lalu',
            AnalyticsPreset.lastMonth => '2 bulan lalu',
            _ => '$n bulan sebelumnya',
          },
        );
      case AnalyticsPreset.custom:
        if (isCalendarMonth) {
          final m = YearMonth.of(start).previous;
          return AnalyticsPeriod(
            start: m.start,
            end: m.end,
            preset: preset,
            label: 'Periode sebelumnya',
          );
        }
        return AnalyticsPeriod(
          start: addDays(start, -days),
          end: addDays(start, -1),
          preset: preset,
          label: 'Periode sebelumnya',
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPeriod &&
      other.start == start &&
      other.end == end &&
      other.preset == preset;

  @override
  int get hashCode => Object.hash(start, end, preset);

  @override
  String toString() =>
      'AnalyticsPeriod($label ${dateKey(start)}…${dateKey(end)})';
}

/// Monday of [d]'s ISO week (local midnight).
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

/// Resolves [preset] around [now]. `custom` needs [from] and [to] (swapped
/// when reversed; defaults to this month).
AnalyticsPeriod resolveAnalyticsPeriod(
  AnalyticsPreset preset,
  DateTime now, {
  DateTime? from,
  DateTime? to,
}) {
  final cur = YearMonth.of(now);
  AnalyticsPeriod months(int n, String label) => AnalyticsPeriod(
    start: cur.plus(-(n - 1)).start,
    end: cur.end,
    preset: preset,
    label: label,
  );
  switch (preset) {
    case AnalyticsPreset.thisWeek:
      final s = weekStart(now);
      return AnalyticsPeriod(
        start: s,
        end: addDays(s, 6),
        preset: preset,
        label: 'Minggu ini',
      );
    case AnalyticsPreset.thisMonth:
      return AnalyticsPeriod(
        start: cur.start,
        end: cur.end,
        preset: preset,
        label: 'Bulan ini',
      );
    case AnalyticsPreset.lastMonth:
      final m = cur.previous;
      return AnalyticsPeriod(
        start: m.start,
        end: m.end,
        preset: preset,
        label: 'Bulan lalu',
      );
    case AnalyticsPreset.last3Months:
      return months(3, '3 bulan terakhir');
    case AnalyticsPreset.last6Months:
      return months(6, '6 bulan terakhir');
    case AnalyticsPreset.last12Months:
      return months(12, '12 bulan terakhir');
    case AnalyticsPreset.thisYear:
      return AnalyticsPeriod(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31),
        preset: preset,
        label: 'Tahun ${now.year}',
      );
    case AnalyticsPreset.custom:
      var a = from ?? cur.start;
      var b = to ?? cur.end;
      if (b.isBefore(a)) (a, b) = (b, a);
      return AnalyticsPeriod(
        start: a,
        end: b,
        preset: preset,
        label: 'Rentang pilihan',
      );
  }
}

/// Day buckets up to a month, weeks up to ~4 months, months beyond.
Granularity granularityFor(AnalyticsPeriod p) {
  if (p.days <= 31) return Granularity.day;
  if (p.days <= 124) return Granularity.week;
  return Granularity.month;
}

/// Bucket start dates covering [p] for [g] (the first bucket starts at
/// `p.start` even mid-week / mid-month, so previous periods align by index).
List<DateTime> bucketStarts(AnalyticsPeriod p, Granularity g) {
  final out = <DateTime>[];
  var d = p.start;
  while (!d.isAfter(p.end)) {
    out.add(d);
    d = switch (g) {
      Granularity.day => DateTime(d.year, d.month, d.day + 1),
      Granularity.week => _plusDays(weekStart(d), 7),
      Granularity.month => DateTime(d.year, d.month + 1, 1),
    };
  }
  return out;
}

/// Index of the bucket containing [d] among sorted [starts] (−1 if before).
int bucketIndex(List<DateTime> starts, DateTime d) {
  var lo = 0, hi = starts.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (!starts[mid].isAfter(d)) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
