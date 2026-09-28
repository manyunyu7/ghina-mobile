/// Ports of "Reminder Sholat". Implementations: `lib/data/notifications/`
/// (calculator, scheduler, settings store) and `lib/data/platform/` (GPS).
library;

import '../entities/enums.dart';
import '../entities/prayer_reminder.dart';

/// Offline prayer-time calculation (adhan).
abstract interface class PrayerTimesCalculator {
  /// Times of local [day] at ([lat], [lng]) with [method], each shifted by
  /// its [offsets] minutes. Returned as local wall-clock times.
  PrayerDayTimes compute(
    DateTime day, {
    required double lat,
    required double lng,
    required PrayerCalcMethod method,
    Map<Prayer, int> offsets = const {},
  });
}

/// Replaces the scheduled prayer notifications with a plan.
abstract interface class PrayerReminderScheduler {
  /// Schedules exactly [plan] (diffed against what's pending); only prayer
  /// notifications are touched.
  Future<void> replaceAll(
    List<PrayerNotificationSpec> plan, {
    PrayerReminderSound sound = PrayerReminderSound.system,
  });

  /// Cancels every scheduled prayer notification (master switch off, sign-out).
  Future<void> cancelAll();

  /// Android: exact alarms allowed (always true elsewhere).
  Future<bool> canScheduleExact();

  /// Android 14+: "Alarms & reminders" settings. Returns the new state.
  Future<bool> requestExactAlarms();
}

/// Device-local persistence of [PrayerReminderSettings].
abstract interface class PrayerReminderSettingsStore {
  Future<PrayerReminderSettings> load();
  Future<void> save(PrayerReminderSettings settings);
}

/// Outcome of a GPS fix.
sealed class LocationFix {
  const LocationFix();
}

final class LocationFound extends LocationFix {
  const LocationFound(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum LocationFailure {
  /// Location services (GPS) turned off.
  serviceOff,

  /// Permission denied (can ask again).
  denied,

  /// Permission denied forever: only system settings can fix it.
  deniedForever,

  /// Timeout / platform error.
  unavailable,

  /// Platform without location (tests, desktop).
  unsupported,
}

final class LocationFailed extends LocationFix {
  const LocationFailed(this.reason);
  final LocationFailure reason;
}

/// One-shot device location (no continuous tracking).
abstract interface class DeviceLocationService {
  /// Current coarse position. With [askPermission] false it never prompts
  /// (used on every app open); it fails with [LocationFailure.denied] instead.
  Future<LocationFix> current({bool askPermission = false});

  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

/// Android battery-optimisation exemption ("Tanpa batasan").
abstract interface class BatteryOptimization {
  /// True when Ghina is exempt (or the platform has no such thing). Null = unknown.
  Future<bool?> isIgnoring();

  /// Opens the system screen to exempt Ghina. Returns false if it couldn't.
  Future<bool> request();
}
