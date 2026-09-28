/// Pure scheduling logic of "Reminder Sholat": notification ids, follow-up
/// times, copy and the full plan. No plugin, no clock — everything is an input.
library;

import 'dart:math' as math;

import '../../core/dates.dart';
import '../entities/enums.dart';
import '../entities/prayer_reminder.dart';

// ---------------------------------------------------------------- ids

/// Prayer notifications live in their own id block, so they can be cancelled
/// deterministically (the background action needs no pending list) and task
/// reminder ids skip it (`assignReminderIds`).
///
/// id = base + (epochDay % 1000) × 100 + fardhuIndex × 20 + slot, where slot
/// 0 = adzan, 1 = pre-reminder, 2.. = follow-ups.
const int kPrayerIdBase = 2000000000;

/// One id per plan: the "open Ghina" nudge at the end of the window.
const int kPrayerRefreshId = kPrayerIdBase - 1;

/// First id of the block (inclusive) … last (exclusive).
const int kPrayerIdStart = kPrayerIdBase - 100;
const int kPrayerIdEnd = kPrayerIdBase + 100000;

bool isPrayerNotificationId(int id) =>
    id >= kPrayerIdStart && id < kPrayerIdEnd;

const int _slotsPerPrayer = 20;
const int _followUpSlot0 = 2;

/// Follow-ups that fit in a prayer's slot block.
const int kMaxFollowUpSlots = _slotsPerPrayer - _followUpSlot0;

int _epochDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Stable id of one prayer notification ([index] = follow-up number, 1-based).
int prayerNotificationId(
  DateTime day,
  Prayer prayer,
  PrayerNotificationKind kind, {
  int index = 0,
}) {
  final p = Prayer.fardhu.indexOf(prayer);
  if (p < 0) throw ArgumentError.value(prayer, 'prayer', 'fardhu only');
  final slot = switch (kind) {
    PrayerNotificationKind.adzan => 0,
    PrayerNotificationKind.pre => 1,
    PrayerNotificationKind.followUp => _followUpSlot0 + index - 1,
    PrayerNotificationKind.refresh => throw ArgumentError(
      'use kPrayerRefreshId',
    ),
  };
  if (slot >= _slotsPerPrayer) throw RangeError.value(index, 'index');
  return kPrayerIdBase +
      (_epochDay(day) % 1000) * 100 +
      p * _slotsPerPrayer +
      slot;
}

/// Every follow-up id (and the pre-reminder) of [prayer] on [day] — what the
/// "✓ Sudah sholat" action cancels.
List<int> prayerFollowUpIds(DateTime day, Prayer prayer) => [
  for (var i = 1; i <= kMaxFollowUpSlots; i++)
    prayerNotificationId(
      day,
      prayer,
      PrayerNotificationKind.followUp,
      index: i,
    ),
];

// ---------------------------------------------------------------- times

/// The fardhu after [prayer] on the same day, or null after Isya.
Prayer? nextFardhu(Prayer prayer) {
  final i = Prayer.fardhu.indexOf(prayer);
  return i >= 0 && i < Prayer.fardhu.length - 1 ? Prayer.fardhu[i + 1] : null;
}

/// When [prayer]'s time ends (the next prayer's time comes in): the next
/// fardhu of the same day, next day's Subuh after Isya (null if unknown).
DateTime? prayerWindowEnd(
  PrayerDayTimes day,
  Prayer prayer,
  PrayerDayTimes? nextDay,
) {
  final n = nextFardhu(prayer);
  if (n != null) return day[n];
  return nextDay?[Prayer.subuh];
}

/// Follow-up times: first at adzan + delay, then every interval, at most
/// `followUpMax`, and strictly before [until] (the next prayer's time).
List<DateTime> followUpTimes(
  DateTime adzan,
  PrayerSlotSettings s, {
  DateTime? until,
}) {
  if (!s.enabled || !s.followUpEnabled) return const [];
  final max = math.min(s.followUpMax, kMaxFollowUpSlots);
  final out = <DateTime>[];
  var t = adzan.add(Duration(minutes: math.max(1, s.followUpDelay)));
  for (var i = 0; i < max; i++) {
    if (until != null && !t.isBefore(until)) break;
    out.add(t);
    t = t.add(Duration(minutes: math.max(1, s.followUpInterval)));
  }
  return out;
}

/// The next fardhu time strictly after [now] across [days] (sorted), or null.
({Prayer prayer, DateTime at})? nextPrayerTime(
  List<PrayerDayTimes> days,
  DateTime now,
) {
  for (final d in days) {
    for (final p in Prayer.fardhu) {
      if (d[p].isAfter(now)) return (prayer: p, at: d[p]);
    }
  }
  return null;
}

/// The fardhu whose time is running at [now] on [day] (null before Subuh and
/// between sunrise and Dzuhur).
Prayer? currentPrayer(PrayerDayTimes day, DateTime now) {
  Prayer? cur;
  for (final p in Prayer.fardhu) {
    if (!day[p].isAfter(now)) cur = p;
  }
  if (cur == Prayer.subuh && !now.isBefore(day.sunrise)) return null;
  return cur;
}

/// Great-circle distance in km (haversine).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// GPS fixes closer than this to the saved location don't reschedule.
const double kGpsRescheduleKm = 20;

/// Nearest preset city within [maxKm], for a friendly GPS label.
PrayerCity? nearestCity(
  List<PrayerCity> cities,
  double lat,
  double lng, {
  double maxKm = 40,
}) {
  PrayerCity? best;
  var bestKm = double.infinity;
  for (final c in cities) {
    final d = distanceKm(lat, lng, c.lat, c.lng);
    if (d < bestKm) {
      bestKm = d;
      best = c;
    }
  }
  return bestKm <= maxKm ? best : null;
}

// ---------------------------------------------------------------- copy

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

/// Deterministic (stable across replans, so the diff leaves them alone) but
/// varied pick.
int _pick(String seed, int n) {
  var h = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h % n;
}

typedef PrayerCopy = ({String title, String body});

PrayerCopy adzanCopy(Prayer p, DateTime at, String place) => (
  title: '🕌 Waktunya sholat ${p.label} · ${hm(at)}',
  body:
      'Sudah masuk waktu ${p.label} untuk $place. Yuk tunaikan, lalu centang '
      'biar tercatat ✨',
);

PrayerCopy preCopy(Prayer p, DateTime at, int minutes) => (
  title: '⏰ $minutes menit lagi ${p.label}',
  body: 'Siap-siap wudhu, ya. ${p.label} masuk jam ${hm(at)}.',
);

/// Follow-up copy. [n] 1-based, [max] = how many are planned, [streak] = full
/// 5/5 days in a row (0 = none), [until] = when the prayer's time ends.
PrayerCopy followUpCopy(
  Prayer p, {
  required String dateKey,
  required int n,
  required int max,
  required int minutesSinceAdzan,
  int streak = 0,
  DateTime? until,
}) {
  final name = p.label;
  if (n == max && max > 1) {
    return (
      title: 'Pengingat terakhir buat $name 🤲',
      body: streak > 0
          ? 'Habis ini Ghina nggak ganggu lagi. Jaga streak $streak hari-mu, ya — '
                'kamu pasti bisa! 💪'
          : 'Habis ini Ghina nggak ganggu lagi. Semoga dimudahkan, semangat! 💪',
    );
  }
  final endsAt = until == null
      ? ''
      : ' Waktunya masih ada sampai ${hm(until)}.';
  final general = <PrayerCopy>[
    (
      title: '$name belum dicentang nih 👀',
      body:
          'Udah $minutesSinceAdzan menit sejak adzan. Kalau sudah sholat, tinggal '
          'tekan "Sudah sholat" di bawah.',
    ),
    (
      title: 'Yuk, $name dulu 🙏',
      body: 'Sebentar aja, urusan lain bisa nunggu.$endsAt',
    ),
    (
      title: 'Masih sempat kok! ⏳',
      body: 'Ambil wudhu, gelar sajadah, $name dulu yuk.$endsAt',
    ),
    (
      title: 'Ghina nungguin centangmu 🌱',
      body: '$name hari ini belum tercatat. Sholat dulu, baru lanjut lagi, ya.',
    ),
  ];
  final withStreak = <PrayerCopy>[
    (
      title: 'Jangan putus di sini! 🔥',
      body:
          'Streak sholat lengkapmu udah $streak hari. $name hari ini jangan sampai '
          'kelewat, ya.',
    ),
    (
      title: '$streak hari berturut-turut 🔥',
      body: 'Keren banget! Tinggal $name biar streak-mu lanjut.$endsAt',
    ),
  ];
  final pool = streak > 0 ? [...withStreak, ...general] : general;
  return pool[_pick('$dateKey|${p.wire}|$n', pool.length)];
}

const PrayerCopy refreshCopy = (
  title: 'Pengingat sholat perlu diperbarui 📅',
  body:
      'Buka Ghina sebentar, ya, biar jadwal pengingat sholat beberapa hari ke '
      'depan disiapkan lagi.',
);

// ---------------------------------------------------------------- plan

/// `YYYY-MM-DD|wire` of a prayer that is filled in (any status) — no
/// follow-ups for it.
String prayerFilledKey(String dateKey, Prayer p) => '$dateKey|${p.wire}';

/// Days with adzan + pre + follow-ups; after that only adzan (fewer alarms).
const int kPrayerFullDays = 2;

/// Days scheduled ahead (from today) with at least the adzan.
const int kPrayerHorizonDays = 7;

/// Cap on pending prayer notifications (Android caps alarms per app; task
/// reminders use up to 60 more).
const int kMaxPrayerNotifications = 80;

/// Everything the app wants scheduled, soonest first.
///
/// [days]: consecutive days from today (the last one may be a look-ahead
/// used only for Isya's window end). [filled]: [prayerFilledKey]s of prayers
/// already recorded — they get no follow-ups (that's how ticking a prayer, in
/// the app or from the notification, cancels them).
List<PrayerNotificationSpec> planPrayerReminders({
  required PrayerReminderSettings settings,
  required List<PrayerDayTimes> days,
  required Set<String> filled,
  required DateTime now,
  int streak = 0,
  int fullDays = kPrayerFullDays,
  int horizonDays = kPrayerHorizonDays,
  int maxTotal = kMaxPrayerNotifications,
  Duration minLead = const Duration(seconds: 5),
}) {
  if (!settings.enabled || days.isEmpty) return const [];
  final cutoff = now.add(minLead);
  final out = <PrayerNotificationSpec>[];
  final planned = math.min(horizonDays, days.length);

  for (var i = 0; i < planned; i++) {
    final d = days[i];
    final next = i + 1 < days.length ? days[i + 1] : null;
    final key = dateKey(d.day);
    final full = i < fullDays;
    for (final p in Prayer.fardhu) {
      final s = settings.slot(p);
      if (!s.enabled) continue;
      final at = d[p];

      if (full && s.preEnabled) {
        final t = at.subtract(Duration(minutes: s.preMinutes));
        if (t.isAfter(cutoff)) {
          final c = preCopy(p, at, s.preMinutes);
          out.add(
            PrayerNotificationSpec(
              id: prayerNotificationId(d.day, p, PrayerNotificationKind.pre),
              kind: PrayerNotificationKind.pre,
              dateKey: key,
              prayer: p,
              fireAt: t,
              title: c.title,
              body: c.body,
            ),
          );
        }
      }

      if (at.isAfter(cutoff)) {
        final c = adzanCopy(p, at, settings.location.name);
        out.add(
          PrayerNotificationSpec(
            id: prayerNotificationId(d.day, p, PrayerNotificationKind.adzan),
            kind: PrayerNotificationKind.adzan,
            dateKey: key,
            prayer: p,
            fireAt: at,
            title: c.title,
            body: c.body,
          ),
        );
      }

      if (full && !filled.contains(prayerFilledKey(key, p))) {
        final until = prayerWindowEnd(d, p, next);
        final times = followUpTimes(at, s, until: until);
        for (final (j, t) in times.indexed) {
          if (!t.isAfter(cutoff)) continue;
          final c = followUpCopy(
            p,
            dateKey: key,
            n: j + 1,
            max: times.length,
            minutesSinceAdzan: t.difference(at).inMinutes,
            streak: streak,
            until: until,
          );
          out.add(
            PrayerNotificationSpec(
              id: prayerNotificationId(
                d.day,
                p,
                PrayerNotificationKind.followUp,
                index: j + 1,
              ),
              kind: PrayerNotificationKind.followUp,
              dateKey: key,
              prayer: p,
              index: j + 1,
              fireAt: t,
              title: c.title,
              body: c.body,
            ),
          );
        }
      }
    }
  }

  out.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  if (out.length >= maxTotal) {
    out.length = maxTotal - 1;
  }
  // Nudge to open the app once the scheduled window runs out (reminders
  // would silently stop otherwise).
  if (out.isNotEmpty) {
    final nudgeAt = out.last.fireAt.add(const Duration(minutes: 45));
    out.add(
      PrayerNotificationSpec(
        id: kPrayerRefreshId,
        kind: PrayerNotificationKind.refresh,
        dateKey: dateKey(nudgeAt),
        fireAt: nudgeAt,
        title: refreshCopy.title,
        body: refreshCopy.body,
      ),
    );
  }
  return out;
}
