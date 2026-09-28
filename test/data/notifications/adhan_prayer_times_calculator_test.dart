import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/notifications/adhan_prayer_times_calculator.dart';
import 'package:ghina/domain/entities/entities.dart';

/// "HH:MM" in WIB (UTC+7) of a UTC instant — independent of the test machine's zone.
String wib(DateTime utc) {
  final l = utc.toUtc().add(const Duration(hours: 7));
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

void main() {
  const yogya = (lat: -7.7956, lng: 110.3695);

  test(
    'Kemenag, Yogyakarta 29 Sep 2026 matches the published schedule (±2 mnt)',
    () {
      final t = AdhanPrayerTimesCalculator.utcTimes(
        DateTime(2026, 9, 29),
        lat: yogya.lat,
        lng: yogya.lng,
        method: PrayerCalcMethod.kemenag,
      );
      // Kemenag RI schedule for Yogyakarta, end of September:
      // Subuh 04.08 · Terbit 05.22 · Dzuhur 11.31 · Ashar 14.40 · Maghrib 17.36 · Isya 18.45
      int minutes(String hm) {
        final p = hm.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      void near(DateTime got, String want) => expect(
        (minutes(wib(got)) - minutes(want)).abs(),
        lessThanOrEqualTo(2),
        reason: 'got ${wib(got)}, want $want',
      );
      near(t.fajr, '04:08');
      near(t.sunrise, '05:22');
      near(t.dhuhr, '11:31');
      near(t.asr, '14:40');
      near(t.maghrib, '17:36');
      near(t.isha, '18:45');
    },
  );

  test('methods differ where they should', () {
    DateTime isha(PrayerCalcMethod m) => AdhanPrayerTimesCalculator.utcTimes(
      DateTime(2026, 9, 29),
      lat: yogya.lat,
      lng: yogya.lng,
      method: m,
    ).isha;
    DateTime fajr(PrayerCalcMethod m) => AdhanPrayerTimesCalculator.utcTimes(
      DateTime(2026, 9, 29),
      lat: yogya.lat,
      lng: yogya.lng,
      method: m,
    ).fajr;
    // Subuh 20° (Kemenag) is earlier than 18° (MWL) and 15° (ISNA).
    expect(
      fajr(PrayerCalcMethod.kemenag).isBefore(fajr(PrayerCalcMethod.mwl)),
      isTrue,
    );
    expect(
      fajr(PrayerCalcMethod.mwl).isBefore(fajr(PrayerCalcMethod.isna)),
      isTrue,
    );
    // Umm al-Qura: Isya = Maghrib + 90 minutes.
    final uq = AdhanPrayerTimesCalculator.utcTimes(
      DateTime(2026, 9, 29),
      lat: yogya.lat,
      lng: yogya.lng,
      method: PrayerCalcMethod.ummAlQura,
    );
    expect(uq.isha.difference(uq.maghrib).inMinutes, 90);
    expect(
      isha(PrayerCalcMethod.kemenag).isAfter(isha(PrayerCalcMethod.mwl)),
      isTrue,
    );
  });

  test(
    'compute: local wall-clock times in order, offsets applied, no seconds',
    () {
      const calc = AdhanPrayerTimesCalculator();
      final day = DateTime(2026, 9, 29);
      final base = calc.compute(
        day,
        lat: yogya.lat,
        lng: yogya.lng,
        method: PrayerCalcMethod.kemenag,
      );
      final shifted = calc.compute(
        day,
        lat: yogya.lat,
        lng: yogya.lng,
        method: PrayerCalcMethod.kemenag,
        offsets: {Prayer.maghrib: 3, Prayer.subuh: -2},
      );
      expect(base.day, day);
      final order = [
        base[Prayer.subuh],
        base.sunrise,
        base[Prayer.dzuhur],
        base[Prayer.ashar],
        base[Prayer.maghrib],
        base[Prayer.isya],
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i].isAfter(order[i - 1]), isTrue);
      }
      for (final t in base.times.values) {
        expect(t.second, 0);
        expect(t.isUtc, isFalse);
      }
      expect(
        shifted[Prayer.maghrib].difference(base[Prayer.maghrib]).inMinutes,
        3,
      );
      expect(
        shifted[Prayer.subuh].difference(base[Prayer.subuh]).inMinutes,
        -2,
      );
      expect(shifted[Prayer.isya], base[Prayer.isya]);
    },
  );
}
