import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/di/di.dart';
import 'package:ghina/di/core_providers.dart' show prayerRepositoryProvider;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/prayer_reminders.dart';
import 'package:ghina/presentation/state/notifications/notification_providers.dart';
import 'package:ghina/presentation/state/prayer_reminders/prayer_reminder_providers.dart';

import '../../../data/notifications/prayer_reminder_scheduler_test.dart'
    show FakeCalculator, entry;
import '../../features/profile/_harness.dart' show FakePrayerRepository;

class RecordingPrayerScheduler implements PrayerReminderScheduler {
  final calls = <String>[];
  final plans = <List<PrayerNotificationSpec>>[];
  PrayerReminderSound? lastSound;

  @override
  Future<void> replaceAll(
    List<PrayerNotificationSpec> plan, {
    PrayerReminderSound sound = PrayerReminderSound.system,
  }) async {
    calls.add('replaceAll');
    plans.add(plan);
    lastSound = sound;
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<bool> requestExactAlarms() async => true;
}

class FakeLocation implements DeviceLocationService {
  LocationFix next = const LocationFailed(LocationFailure.unavailable);
  final asks = <bool>[];

  @override
  Future<LocationFix> current({bool askPermission = false}) async {
    asks.add(askPermission);
    return next;
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}

void main() {
  const debounce = Duration(milliseconds: 20);
  Future<void> settle() => Future<void>.delayed(debounce * 4);
  final now = DateTime(2026, 9, 29, 12);
  final today = startOfDay(now);

  late RecordingPrayerScheduler scheduler;
  late InMemoryPrayerReminderSettingsStore store;
  late FakePrayerRepository prayers;
  late FakeLocation location;
  late bool signedIn;
  late ProviderContainer c;

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [
        prayerReminderSchedulerProvider.overrideWithValue(scheduler),
        prayerReminderSettingsStoreProvider.overrideWithValue(store),
        prayerTimesCalculatorProvider.overrideWithValue(FakeCalculator()),
        deviceLocationProvider.overrideWithValue(location),
        prayerRepositoryProvider.overrideWithValue(prayers),
        clockProvider.overrideWithValue(FixedClock(now)),
        reminderSessionActiveProvider.overrideWith((ref) => signedIn),
        reminderSyncDebounceProvider.overrideWithValue(debounce),
      ],
    );
    c.listen(prayerReminderSyncControllerProvider, (_, _) {});
    return c;
  }

  setUp(() {
    scheduler = RecordingPrayerScheduler();
    store = InMemoryPrayerReminderSettingsStore(
      const PrayerReminderSettings(enabled: true),
    );
    prayers = FakePrayerRepository();
    location = FakeLocation();
    signedIn = true;
    c = make();
  });

  tearDown(() => c.dispose());

  Iterable<PrayerNotificationSpec> followUps(Prayer p) =>
      scheduler.plans.last.where(
        (s) =>
            s.kind == PrayerNotificationKind.followUp &&
            s.prayer == p &&
            s.dateKey == dateKey(today),
      );

  test('on: schedules the plan once (debounced)', () async {
    await settle();
    expect(scheduler.calls, ['replaceAll']);
    expect(scheduler.plans.last, isNotEmpty);
    expect(followUps(Prayer.maghrib), isNotEmpty);
    expect(
      c.read(prayerReminderSyncControllerProvider),
      PrayerReminderSyncStatus.scheduled,
    );
  });

  test(
    'ticking a prayer in the tracker re-plans without its follow-ups',
    () async {
      await settle();
      await prayers.save(entry(today, Prayer.maghrib));
      await settle();
      expect(scheduler.calls, ['replaceAll', 'replaceAll']);
      expect(followUps(Prayer.maghrib), isEmpty);
      expect(followUps(Prayer.isya), isNotEmpty);
    },
  );

  test('master switch off → cancelAll; on again → schedules', () async {
    await settle();
    await c.read(prayerReminderSettingsProvider.notifier).setEnabled(false);
    await settle();
    expect(scheduler.calls.last, 'cancelAll');
    expect(
      c.read(prayerReminderSyncControllerProvider),
      PrayerReminderSyncStatus.off,
    );
    expect(store.value.enabled, isFalse);
    await c.read(prayerReminderSettingsProvider.notifier).setEnabled(true);
    await settle();
    expect(scheduler.calls.last, 'replaceAll');
  });

  test('signed out → cancelAll, even at startup', () async {
    c.dispose();
    signedIn = false;
    scheduler = RecordingPrayerScheduler();
    c = make();
    await settle();
    expect(scheduler.calls, ['cancelAll']);
  });

  test('per-prayer setting and sound changes re-plan', () async {
    await settle();
    final ctl = c.read(prayerReminderSettingsProvider.notifier);
    await ctl.updateSlot(
      Prayer.maghrib,
      (s) => s.copyWith(followUpEnabled: false),
    );
    await settle();
    expect(followUps(Prayer.maghrib), isEmpty);
    await ctl.setSound(PrayerReminderSound.silent);
    await settle();
    expect(scheduler.lastSound, PrayerReminderSound.silent);
    expect(
      PrayerReminderSettings.fromJson(
        store.value.toJson(),
      ).slot(Prayer.maghrib).followUpEnabled,
      isFalse,
    );
  });

  group('GPS', () {
    const gps = PrayerLocation(
      source: PrayerLocationSource.gps,
      name: 'Dekat Yogyakarta',
      lat: -7.7956,
      lng: 110.3695,
    );

    test('one silent fix per app open; > 20 km moves the location', () async {
      c.dispose();
      store = InMemoryPrayerReminderSettingsStore(
        const PrayerReminderSettings(enabled: true, location: gps),
      );
      location.next = const LocationFound(-6.9175, 107.6191); // Bandung
      c = make();
      await settle();
      expect(location.asks, [false], reason: 'never prompts on app open');
      final loc = store.value.location;
      expect(loc.isGps, isTrue);
      expect(loc.name, 'Dekat Bandung');
      expect(loc.updatedAt, now);
      // Re-planned for the new place.
      expect(scheduler.plans.last.first.body, isNot(contains('Yogyakarta')));

      // Resume shortly after: no new fix (once per app open).
      c.read(prayerReminderSyncControllerProvider.notifier).syncNow();
      await settle();
      expect(location.asks, [false]);
    });

    test('small moves and failures keep the saved (cached) location', () async {
      c.dispose();
      store = InMemoryPrayerReminderSettingsStore(
        const PrayerReminderSettings(enabled: true, location: gps),
      );
      location.next = const LocationFound(-7.80, 110.45); // ~9 km
      c = make();
      await settle();
      expect(store.value.location, gps);

      location.next = const LocationFailed(LocationFailure.unavailable);
      final fix = await c
          .read(prayerReminderSettingsProvider.notifier)
          .refreshGps(force: true);
      expect(fix, isA<LocationFailed>());
      expect(store.value.location, gps);
    });

    test('"Pakai lokasi GPS" asks permission and always saves', () async {
      location.next = const LocationFound(-7.80, 110.37);
      await c
          .read(prayerReminderSettingsProvider.notifier)
          .refreshGps(askPermission: true, force: true);
      expect(location.asks.last, isTrue);
      expect(store.value.location.isGps, isTrue);
      expect(store.value.location.name, 'Dekat Yogyakarta');
    });

    test('city mode never asks for GPS', () async {
      await settle();
      expect(location.asks, isEmpty);
    });
  });

  test('prayerTimesProvider follows location/method/offsets', () async {
    await c.read(prayerReminderSettingsProvider.future);
    final t = c.read(prayerTimesProvider(today))!;
    expect(t[Prayer.maghrib], DateTime(2026, 9, 29, 17, 35));
    await c
        .read(prayerReminderSettingsProvider.notifier)
        .updateSlot(Prayer.maghrib, (s) => s.copyWith(offsetMinutes: 2));
    expect(
      c.read(prayerTimesProvider(today))![Prayer.maghrib],
      DateTime(2026, 9, 29, 17, 37),
    );
  });
}
