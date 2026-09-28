import 'package:adhan/adhan.dart' as adhan;

import '../../domain/entities/entities.dart';
import '../../domain/services/prayer_reminders.dart';

/// [PrayerTimesCalculator] on the offline `adhan` package.
///
/// Kemenag RI: Subuh 20°, Isya 18° (Syafi'i Ashar) plus the usual ihtiyat of
/// 2 minutes (Subuh/Dzuhur/Ashar/Maghrib/Isya +2, terbit −2) that Kemenag's
/// published schedules include. The user can fine-tune per prayer (offsets).
class AdhanPrayerTimesCalculator implements PrayerTimesCalculator {
  const AdhanPrayerTimesCalculator();

  static adhan.CalculationParameters parameters(PrayerCalcMethod m) {
    final params = switch (m) {
      PrayerCalcMethod.kemenag =>
        adhan.CalculationParameters(
          fajrAngle: 20,
          ishaAngle: 18,
        ).withMethodAdjustments(
          adhan.PrayerAdjustments(
            fajr: 2,
            sunrise: -2,
            dhuhr: 2,
            asr: 2,
            maghrib: 2,
            isha: 2,
          ),
        ),
      PrayerCalcMethod.mwl =>
        adhan.CalculationMethod.muslim_world_league.getParameters(),
      PrayerCalcMethod.egyptian =>
        adhan.CalculationMethod.egyptian.getParameters(),
      PrayerCalcMethod.karachi =>
        adhan.CalculationMethod.karachi.getParameters(),
      PrayerCalcMethod.ummAlQura =>
        adhan.CalculationMethod.umm_al_qura.getParameters(),
      PrayerCalcMethod.singapore =>
        adhan.CalculationMethod.singapore.getParameters(),
      PrayerCalcMethod.isna =>
        adhan.CalculationMethod.north_america.getParameters(),
    };
    return params..madhab = adhan.Madhab.shafi;
  }

  /// The instants (UTC) of [day] at the location, before offsets.
  static adhan.PrayerTimes utcTimes(
    DateTime day, {
    required double lat,
    required double lng,
    required PrayerCalcMethod method,
  }) => adhan.PrayerTimes.utc(
    adhan.Coordinates(lat, lng),
    adhan.DateComponents(day.year, day.month, day.day),
    parameters(method),
  );

  @override
  PrayerDayTimes compute(
    DateTime day, {
    required double lat,
    required double lng,
    required PrayerCalcMethod method,
    Map<Prayer, int> offsets = const {},
  }) {
    final t = utcTimes(day, lat: lat, lng: lng, method: method);
    DateTime local(DateTime utc, Prayer? p) {
      // Drop seconds so notification times read cleanly ("17.45").
      final l = utc.toLocal().add(Duration(minutes: offsets[p] ?? 0));
      return DateTime(l.year, l.month, l.day, l.hour, l.minute);
    }

    return PrayerDayTimes(
      day: DateTime(day.year, day.month, day.day),
      sunrise: local(t.sunrise, null),
      times: {
        Prayer.subuh: local(t.fajr, Prayer.subuh),
        Prayer.dzuhur: local(t.dhuhr, Prayer.dzuhur),
        Prayer.ashar: local(t.asr, Prayer.ashar),
        Prayer.maghrib: local(t.maghrib, Prayer.maghrib),
        Prayer.isya: local(t.isha, Prayer.isya),
      },
    );
  }
}
