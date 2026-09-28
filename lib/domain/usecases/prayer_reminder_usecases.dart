/// "Reminder Sholat" use cases: prayer times, the notification plan and the
/// "✓ Sudah sholat" action. Rules live in `prayer_reminder_rules.dart`.
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import '../services/prayer_reminders.dart';
import 'prayer_quality.dart' show completeDayStreak;
import 'prayer_reminder_rules.dart';
import 'prayer_usecases.dart' show SetPrayerStatus;

/// Prayer times of one local day for the saved location / method / offsets.
final class ComputePrayerTimes {
  const ComputePrayerTimes(this._calc);
  final PrayerTimesCalculator _calc;

  PrayerDayTimes call(DateTime day, PrayerReminderSettings s) => _calc.compute(
    startOfDay(day),
    lat: s.location.lat,
    lng: s.location.lng,
    method: s.method,
    offsets: s.offsets,
  );

  /// [count] consecutive days from [from].
  List<PrayerDayTimes> range(
    DateTime from,
    int count,
    PrayerReminderSettings s,
  ) => [for (var i = 0; i < count; i++) call(addDays(startOfDay(from), i), s)];
}

/// The full set of prayer notifications for "now": today + the next days,
/// without follow-ups for prayers already filled in.
final class BuildPrayerReminderPlan {
  const BuildPrayerReminderPlan(this._times);
  final ComputePrayerTimes _times;

  /// [entries]: prayer rows covering at least today … horizon (and the past
  /// days used for the streak).
  List<PrayerNotificationSpec> call(
    PrayerReminderSettings settings,
    List<PrayerEntry> entries,
    DateTime now,
  ) {
    if (!settings.enabled) return const [];
    final today = startOfDay(now);
    // +1 look-ahead day: Isya's window ends at next day's Subuh.
    final days = _times.range(today, kPrayerHorizonDays + 1, settings);
    final filled = {
      for (final e in entries)
        if (e.prayer.isFardhu) prayerFilledKey(e.date, e.prayer),
    };
    return planPrayerReminders(
      settings: settings,
      days: days,
      filled: filled,
      now: now,
      streak: completeDayStreak(entries, today),
    );
  }
}

/// "✓ Sudah sholat" from a notification: records the fardhu the same way a
/// tap in the app does ([PrayerStatus.quick], so the same XP) unless it's
/// already filled in. Returns the row, or null when it already existed.
final class RecordPrayerFromReminder {
  const RecordPrayerFromReminder(this._repo, this._clock);
  final PrayerRepository _repo;
  final Clock _clock;

  Future<Result<PrayerEntry?>> call(DateTime day, Prayer prayer) =>
      guard(() async {
        final existing = await _repo.findByKey(dateKey(day), prayer);
        if (existing != null) return null;
        final r = await SetPrayerStatus(_repo, _clock)(
          day,
          prayer,
          PrayerStatus.quick,
        );
        return switch (r) {
          Ok(:final value) => value,
          Err(:final failure) => throw failure,
        };
      });
}
