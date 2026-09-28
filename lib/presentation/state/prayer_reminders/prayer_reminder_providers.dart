/// Reminder Sholat state: settings (device-local), today's times, GPS refresh
/// and the controller that keeps the OS schedule in sync.
///
/// * Settings UI: `ref.watch(prayerReminderSettingsProvider)` +
///   `ref.read(prayerReminderSettingsProvider.notifier).setX(...)`.
/// * Times: `ref.watch(prayerTimesProvider(day))` (null while settings load).
/// * Activate [prayerReminderSyncControllerProvider] once from the app shell
///   and call `syncNow()` on resume.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/services/prayer_reminders.dart';
import '../../../domain/usecases/usecases.dart';
import '../notifications/notification_providers.dart'
    show reminderSessionActiveProvider, reminderSyncDebounceProvider;

// ---------------------------------------------------------------- settings

class PrayerReminderSettingsController
    extends AsyncNotifier<PrayerReminderSettings> {
  @override
  Future<PrayerReminderSettings> build() =>
      ref.watch(prayerReminderSettingsStoreProvider).load();

  Future<void> _update(
    PrayerReminderSettings Function(PrayerReminderSettings) change,
  ) async {
    final current = state.value ?? await future;
    final next = change(current);
    if (next == current) return;
    state = AsyncData(next);
    await ref.read(prayerReminderSettingsStoreProvider).save(next);
  }

  Future<void> setEnabled(bool v) => _update((s) => s.copyWith(enabled: v));

  Future<void> setMethod(PrayerCalcMethod m) =>
      _update((s) => s.copyWith(method: m));

  Future<void> setSound(PrayerReminderSound v) =>
      _update((s) => s.copyWith(sound: v));

  Future<void> setSlot(Prayer p, PrayerSlotSettings slot) =>
      _update((s) => s.withSlot(p, slot));

  Future<void> updateSlot(
    Prayer p,
    PrayerSlotSettings Function(PrayerSlotSettings) change,
  ) => _update((s) => s.withSlot(p, change(s.slot(p))));

  Future<void> useCity(PrayerCity c) =>
      _update((s) => s.copyWith(location: PrayerLocation.city(c)));

  /// Asks for a GPS fix and, when found, saves it as the location (only when
  /// it moved more than [kGpsRescheduleKm], unless [force] — e.g. the user
  /// just picked "Pakai lokasi GPS"). With [askPermission] false it never
  /// prompts (app open). Returns the fix; the saved location is untouched on
  /// failure (last coordinates stay as the fallback).
  Future<LocationFix> refreshGps({
    bool askPermission = false,
    bool force = false,
  }) async {
    final fix = await ref
        .read(deviceLocationProvider)
        .current(askPermission: askPermission);
    if (fix is! LocationFound || !ref.mounted) return fix;
    final current = state.value ?? await future;
    final old = current.location;
    final moved = distanceKm(old.lat, old.lng, fix.lat, fix.lng);
    if (!force && old.isGps && moved <= kGpsRescheduleKm) return fix;
    if (!force && !old.isGps) return fix; // user switched to a city meanwhile
    final near = nearestCity(indonesianPrayerCities, fix.lat, fix.lng);
    await _update(
      (s) => s.copyWith(
        location: PrayerLocation(
          source: PrayerLocationSource.gps,
          name: near == null ? 'Lokasi GPS' : 'Dekat ${near.name}',
          lat: fix.lat,
          lng: fix.lng,
          updatedAt: ref.read(clockProvider).now(),
        ),
      ),
    );
    return fix;
  }
}

final prayerReminderSettingsProvider =
    AsyncNotifierProvider<
      PrayerReminderSettingsController,
      PrayerReminderSettings
    >(PrayerReminderSettingsController.new);

/// Prayer times of a local day for the saved location/method/offsets (null
/// while the settings load or if they fail to load).
final prayerTimesProvider = Provider.family<PrayerDayTimes?, DateTime>((
  ref,
  day,
) {
  final s = ref.watch(prayerReminderSettingsProvider).value;
  if (s == null) return null;
  return ref.watch(computePrayerTimesProvider)(day, s);
});

// ---------------------------------------------------------------- sync

enum PrayerReminderSyncStatus { idle, off, pending, scheduled, error }

/// Keeps the OS schedule equal to the plan:
///
/// * on (signed in + master switch): every change of the settings or of the
///   prayer rows (ticking a prayer in the app, or from the notification) →
///   debounced replan → `replaceAll` (the diff cancels that prayer's
///   follow-ups);
/// * off: `cancelAll` (prayer notifications only);
/// * a new day (midnight timer / resume) re-plans the rolling window;
/// * GPS location: one fix per app open (at start, and on resume after
///   [gpsRefreshEvery]); moving > 20 km saves it → replan.
class PrayerReminderSyncController extends Notifier<PrayerReminderSyncStatus> {
  static const gpsRefreshEvery = Duration(minutes: 30);

  Timer? _debounce;
  Timer? _midnight;
  ProviderSubscription<AsyncValue<List<PrayerEntry>>>? _entriesSub;
  DateTime? _windowDay;
  List<PrayerEntry>? _entries;
  bool? _on;
  DateTime? _gpsCheckedAt;

  PrayerReminderScheduler get _scheduler =>
      ref.read(prayerReminderSchedulerProvider);

  @override
  PrayerReminderSyncStatus build() {
    ref.watch(prayerReminderSchedulerProvider);
    _on = null;
    ref.listen(reminderSessionActiveProvider, (_, _) => _evaluate());
    ref.listen(prayerReminderSettingsProvider, (_, _) => _evaluate());
    ref.onDispose(() {
      _debounce?.cancel();
      _midnight?.cancel();
      _entriesSub?.close();
      _entriesSub = null;
    });
    Future.microtask(_evaluate);
    return PrayerReminderSyncStatus.idle;
  }

  void _evaluate() {
    if (!ref.mounted) return;
    final settings = ref.read(prayerReminderSettingsProvider).value;
    if (settings == null) return;
    final session = ref.read(reminderSessionActiveProvider);
    if (session) _maybeRefreshGps(settings);
    final on = settings.enabled && session;

    if (!on) {
      _debounce?.cancel();
      _midnight?.cancel();
      _entriesSub?.close();
      _entriesSub = null;
      _windowDay = null;
      _entries = null;
      if (_on != false) {
        _on = false;
        state = PrayerReminderSyncStatus.off;
        unawaited(_run(_scheduler.cancelAll, PrayerReminderSyncStatus.off));
      }
      return;
    }
    if (_on != true) {
      _on = true;
      state = PrayerReminderSyncStatus.pending;
    }
    _ensureWindow();
    _schedule();
  }

  void _maybeRefreshGps(PrayerReminderSettings s) {
    if (!s.location.isGps) return;
    final now = ref.read(clockProvider).now();
    // Checked this session, or the user just fixed it ("Pakai lokasi GPS").
    for (final last in [_gpsCheckedAt, s.location.updatedAt]) {
      if (last != null && now.difference(last).abs() < gpsRefreshEvery) return;
    }
    _gpsCheckedAt = now;
    unawaited(
      ref
          .read(prayerReminderSettingsProvider.notifier)
          .refreshGps()
          .then<void>((_) {}, onError: (Object e) => debugPrint('GPS: $e')),
    );
  }

  /// Prayer rows of the last 60 days (streak) … the planned window.
  void _ensureWindow() {
    final today = startOfDay(ref.read(clockProvider).now());
    if (_windowDay == today && _entriesSub != null) return;
    _entriesSub?.close();
    _windowDay = today;
    _entries = null;
    _entriesSub = ref.listen<AsyncValue<List<PrayerEntry>>>(
      watchPrayersProvider((
        from: addDays(today, -60),
        to: addDays(today, kPrayerHorizonDays),
      )),
      (_, next) {
        if (next case AsyncData(:final value)) {
          _entries = value;
          _schedule();
        } else if (next case AsyncError(:final error)) {
          debugPrint('Prayer rows failed: $error');
        }
      },
      fireImmediately: true,
    );
    _midnight?.cancel();
    final now = ref.read(clockProvider).now();
    final wait = addDays(today, 1).difference(now) + const Duration(minutes: 1);
    _midnight = Timer(wait.isNegative ? Duration.zero : wait, _evaluate);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(ref.read(reminderSyncDebounceProvider), _flush);
  }

  void _flush() {
    if (!ref.mounted || _on != true) return;
    final entries = _entries;
    final settings = ref.read(prayerReminderSettingsProvider).value;
    if (entries == null || settings == null) return;
    final plan = ref.read(buildPrayerReminderPlanProvider)(
      settings,
      entries,
      ref.read(clockProvider).now(),
    );
    unawaited(
      _run(
        () => _scheduler.replaceAll(plan, sound: settings.sound),
        PrayerReminderSyncStatus.scheduled,
      ),
    );
  }

  Future<void> _run(
    Future<void> Function() op,
    PrayerReminderSyncStatus ok,
  ) async {
    try {
      await op();
      final current = ok == PrayerReminderSyncStatus.off
          ? _on == false
          : _on == true;
      if (ref.mounted && current) state = ok;
    } catch (e) {
      debugPrint('Prayer reminder sync failed: $e');
      if (ref.mounted) state = PrayerReminderSyncStatus.error;
    }
  }

  /// App resumed: new day → new window, GPS if stale, and re-plan now.
  void syncNow() {
    _evaluate();
    _debounce?.cancel();
    _flush();
  }
}

final prayerReminderSyncControllerProvider =
    NotifierProvider<PrayerReminderSyncController, PrayerReminderSyncStatus>(
      PrayerReminderSyncController.new,
    );
