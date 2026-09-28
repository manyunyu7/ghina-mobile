/// Composition root, part 6: "Reminder Sholat" (offline prayer times, prayer
/// notifications, GPS / battery helpers) and the app version.
///
/// Tests override [prayerReminderSettingsStoreProvider],
/// [prayerReminderSchedulerProvider], [deviceLocationProvider] and
/// [batteryOptimizationProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notifications/notifications.dart'
    show
        AdhanPrayerTimesCalculator,
        SharedPrefsPrayerReminderSettingsStore,
        createPrayerReminderScheduler;
import '../data/platform/platform.dart'
    show createBatteryOptimization, createDeviceLocation, readAppVersion;
import '../domain/services/prayer_reminders.dart';
import '../domain/usecases/usecases.dart'
    show BuildPrayerReminderPlan, ComputePrayerTimes;

final prayerTimesCalculatorProvider = Provider<PrayerTimesCalculator>(
  (ref) => const AdhanPrayerTimesCalculator(),
);

final prayerReminderSettingsStoreProvider =
    Provider<PrayerReminderSettingsStore>(
      (ref) => SharedPrefsPrayerReminderSettingsStore(),
    );

/// No-op off Android/iOS and under `flutter test`.
final prayerReminderSchedulerProvider = Provider<PrayerReminderScheduler>(
  (ref) => createPrayerReminderScheduler(),
);

final deviceLocationProvider = Provider<DeviceLocationService>(
  (ref) => createDeviceLocation(),
);

final batteryOptimizationProvider = Provider<BatteryOptimization>(
  (ref) => createBatteryOptimization(),
);

/// `(day, settings)` → the five fardhu times of that day.
final computePrayerTimesProvider = Provider<ComputePrayerTimes>(
  (ref) => ComputePrayerTimes(ref.watch(prayerTimesCalculatorProvider)),
);

/// `(settings, entries, now)` → every prayer notification to schedule.
final buildPrayerReminderPlanProvider = Provider<BuildPrayerReminderPlan>(
  (ref) => BuildPrayerReminderPlan(ref.watch(computePrayerTimesProvider)),
);

/// Installed version name (`1.0.8`), from the platform (package_info_plus).
final appVersionProvider = FutureProvider<String>((ref) => readAppVersion());
