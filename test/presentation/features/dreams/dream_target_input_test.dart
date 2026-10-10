import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dream_target_input.dart';

void main() {
  group('periodTargetDate', () {
    test('day keeps the picked day', () {
      expect(
        periodTargetDate(TargetPrecision.day, (year: 2027, index: 3)),
        '2027-03-01',
      );
    });

    test('month is the last day, leap February included', () {
      expect(
        periodTargetDate(TargetPrecision.month, (year: 2028, index: 2)),
        '2028-02-29',
      );
      expect(
        periodTargetDate(TargetPrecision.month, (year: 2027, index: 2)),
        '2027-02-28',
      );
      expect(
        periodTargetDate(TargetPrecision.month, (year: 2027, index: 4)),
        '2027-04-30',
      );
    });

    test('quarter ends on the last day of its third month', () {
      expect(
        periodTargetDate(TargetPrecision.quarter, (year: 2027, index: 1)),
        '2027-03-31',
      );
      expect(
        periodTargetDate(TargetPrecision.quarter, (year: 2027, index: 2)),
        '2027-06-30',
      );
      expect(
        periodTargetDate(TargetPrecision.quarter, (year: 2027, index: 4)),
        '2027-12-31',
      );
    });

    test('year ends on 31 December', () {
      expect(
        periodTargetDate(TargetPrecision.year, (year: 2030, index: 1)),
        '2030-12-31',
      );
    });
  });

  group('periodOfTarget', () {
    test('reverses the stored date', () {
      expect(periodOfTarget('2027-03-31', TargetPrecision.quarter), (
        year: 2027,
        index: 1,
      ));
      expect(periodOfTarget('2028-02-29', TargetPrecision.month), (
        year: 2028,
        index: 2,
      ));
      expect(periodOfTarget('2027-12-31', TargetPrecision.year), (
        year: 2027,
        index: 1,
      ));
      expect(periodOfTarget(null, TargetPrecision.day), isNull);
      expect(periodOfTarget('bukan tanggal', TargetPrecision.day), isNull);
    });

    test('round trips through periodTargetDate', () {
      for (final p in TargetPrecision.values) {
        final date = periodTargetDate(p, (year: 2029, index: 2));
        final back = periodOfTarget(date, p)!;
        expect(periodTargetDate(p, back), date);
      }
    });
  });

  test('periodLabel reads like the list', () {
    expect(
      periodLabel(TargetPrecision.quarter, (year: 2027, index: 2)),
      'Q2 2027',
    );
    expect(
      periodLabel(TargetPrecision.month, (year: 2027, index: 3)),
      'Maret 2027',
    );
    expect(periodLabel(TargetPrecision.year, (year: 2027, index: 1)), '2027');
  });

  test('resnapTarget keeps the period when the precision changes', () {
    expect(resnapTarget('2027-03-15', TargetPrecision.quarter), '2027-03-31');
    expect(resnapTarget('2027-03-31', TargetPrecision.year), '2027-12-31');
    expect(resnapTarget('2027-03-15', TargetPrecision.day), '2027-03-15');
    expect(resnapTarget(null, TargetPrecision.month), isNull);
  });

  group('parseTargetText', () {
    test('Q2 2027', () {
      final r = parseTargetText('Q2 2027');
      expect(r.error, isNull);
      expect(r.target, (
        date: '2027-06-30',
        precision: TargetPrecision.quarter,
      ));
    });

    test('Maret 2027', () {
      final r = parseTargetText('Maret 2027');
      expect(r.target, (date: '2027-03-31', precision: TargetPrecision.month));
    });

    test('2027', () {
      final r = parseTargetText('2027');
      expect(r.target, (date: '2027-12-31', precision: TargetPrecision.year));
    });

    test('a full date stays a day', () {
      final r = parseTargetText('2028-02-29');
      expect(r.target, (date: '2028-02-29', precision: TargetPrecision.day));
    });

    test('rejects what it cannot read', () {
      final r = parseTargetText('besok lusa');
      expect(r.target, isNull);
      expect(r.error, 'Tidak dimengerti');
    });

    test('blank means no target and no error', () {
      expect(parseTargetText('  '), (target: null, error: null));
    });
  });

  group('parseDreamAmount', () {
    test('plain, thousands and decimals', () {
      expect(parseDreamAmount('1500000'), 1500000);
      expect(parseDreamAmount('1.500.000'), 1500000);
      expect(parseDreamAmount('Rp 2.500'), 2500);
      expect(parseDreamAmount('1.500.000,50'), 1500000.5);
      expect(parseDreamAmount('2,5'), 2.5);
      expect(parseDreamAmount('1.5'), 1.5);
    });

    test('not a number', () {
      expect(parseDreamAmount('abc'), isNull);
      expect(parseDreamAmount('12a'), isNull);
      expect(parseDreamAmount(''), isNull);
    });
  });

  group('source ref', () {
    test('habit sources carry habitId', () {
      expect(buildSourceRef(MetricSource.habitCleanDays, refId: 'h1'), {
        'habitId': 'h1',
      });
      expect(
        readSourceRef(MetricSource.habitLongestStreak, {'habitId': 'h1'}).refId,
        'h1',
      );
    });

    test('wallet balance carries walletId', () {
      expect(buildSourceRef(MetricSource.walletBalance, refId: 'w1'), {
        'walletId': 'w1',
      });
    });

    test('spend category carries categoryId and period', () {
      final ref = buildSourceRef(
        MetricSource.spendCategory,
        refId: 'c1',
        period: SpendPeriod.week,
      );
      expect(ref, {'categoryId': 'c1', 'period': 'week'});
      final back = readSourceRef(MetricSource.spendCategory, ref);
      expect(back.refId, 'c1');
      expect(back.period, SpendPeriod.week);
    });

    test('sources without a reference, or a missing id, give null', () {
      expect(buildSourceRef(MetricSource.manual, refId: 'x'), isNull);
      expect(buildSourceRef(MetricSource.weight), isNull);
      expect(buildSourceRef(MetricSource.walletBalance), isNull);
      expect(readSourceRef(MetricSource.manual, null).refId, isNull);
    });
  });

  test('addDreamTag ignores blanks and duplicates, drops the hash', () {
    var tags = <String>[];
    tags = addDreamTag(tags, '#Liburan');
    tags = addDreamTag(tags, 'liburan');
    tags = addDreamTag(tags, '   ');
    tags = addDreamTag(tags, 'Hemat');
    expect(tags, ['Liburan', 'Hemat']);
  });

  test('dreamDateKey pads', () {
    expect(dreamDateKey(DateTime(2027, 3, 5)), '2027-03-05');
    expect(dreamKeyToDate('2027-03-05'), DateTime(2027, 3, 5));
    expect(dreamKeyToDate('2027-02-30'), isNull);
  });
}
