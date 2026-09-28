import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

/// Fixed, round prayer times so the expectations read easily.
PrayerDayTimes dayTimes(DateTime day) {
  DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
  return PrayerDayTimes(
    day: startOfDay(day),
    sunrise: at(5, 20),
    times: {
      Prayer.subuh: at(4, 10),
      Prayer.dzuhur: at(11, 30),
      Prayer.ashar: at(14, 40),
      Prayer.maghrib: at(17, 35),
      Prayer.isya: at(18, 45),
    },
  );
}

List<PrayerDayTimes> window(DateTime today, [int n = 8]) => [
  for (var i = 0; i < n; i++) dayTimes(addDays(today, i)),
];

const on = PrayerReminderSettings(enabled: true);

void main() {
  final today = DateTime(2026, 9, 29);
  final key = dateKey(today);

  group('ids', () {
    test('unique per day × prayer × kind × index, inside the prayer block', () {
      final ids = <int>{};
      for (var d = 0; d < 1000; d++) {
        final day = addDays(today, d);
        for (final p in Prayer.fardhu) {
          ids.add(prayerNotificationId(day, p, PrayerNotificationKind.adzan));
          ids.add(prayerNotificationId(day, p, PrayerNotificationKind.pre));
          for (var i = 1; i <= kMaxFollowUpSlots; i++) {
            ids.add(
              prayerNotificationId(
                day,
                p,
                PrayerNotificationKind.followUp,
                index: i,
              ),
            );
          }
        }
      }
      expect(ids.length, 1000 * 5 * (2 + kMaxFollowUpSlots));
      expect(ids.every(isPrayerNotificationId), isTrue);
      expect(isPrayerNotificationId(kPrayerRefreshId), isTrue);
      expect(ids.contains(kPrayerRefreshId), isFalse);
      expect(ids.every((id) => id <= 0x7fffffff), isTrue);
    });

    test('follow-up ids of a prayer cover every follow-up the plan uses', () {
      final plan = planPrayerReminders(
        settings: on,
        days: window(today),
        filled: const {},
        now: DateTime(2026, 9, 29, 0, 1),
      );
      final maghribFu = plan
          .where(
            (s) =>
                s.kind == PrayerNotificationKind.followUp &&
                s.prayer == Prayer.isya &&
                s.dateKey == key,
          )
          .map((s) => s.id);
      expect(maghribFu, hasLength(3));
      expect(prayerFollowUpIds(today, Prayer.isya), containsAll(maghribFu));
      expect(
        prayerFollowUpIds(today, Prayer.isya),
        isNot(
          contains(
            prayerNotificationId(
              today,
              Prayer.isya,
              PrayerNotificationKind.adzan,
            ),
          ),
        ),
      );
    });
  });

  group('followUpTimes', () {
    final adzan = DateTime(2026, 9, 29, 17, 35);

    test('first after the delay, then every interval, at most max', () {
      expect(followUpTimes(adzan, const PrayerSlotSettings()), [
        DateTime(2026, 9, 29, 18, 5),
        DateTime(2026, 9, 29, 18, 35),
        DateTime(2026, 9, 29, 19, 5),
      ]);
      expect(
        followUpTimes(
          adzan,
          const PrayerSlotSettings(
            followUpDelay: 10,
            followUpInterval: 15,
            followUpMax: 2,
          ),
        ),
        [DateTime(2026, 9, 29, 17, 45), DateTime(2026, 9, 29, 18, 0)],
      );
    });

    test('stops before the next prayer comes in', () {
      // Maghrib 17.35 → Isya 18.45: 18.05 and 18.35 fit, 19.05 doesn't.
      expect(
        followUpTimes(
          adzan,
          const PrayerSlotSettings(),
          until: DateTime(2026, 9, 29, 18, 45),
        ),
        [DateTime(2026, 9, 29, 18, 5), DateTime(2026, 9, 29, 18, 35)],
      );
      // Exactly at the next time is too late.
      expect(
        followUpTimes(
          adzan,
          const PrayerSlotSettings(followUpMax: 1),
          until: DateTime(2026, 9, 29, 18, 5),
        ),
        isEmpty,
      );
    });

    test('none when follow-ups or the prayer are off', () {
      expect(
        followUpTimes(adzan, const PrayerSlotSettings(followUpEnabled: false)),
        isEmpty,
      );
      expect(
        followUpTimes(adzan, const PrayerSlotSettings(enabled: false)),
        isEmpty,
      );
    });

    test('window end: next fardhu, or next day\'s Subuh after Isya', () {
      final d = dayTimes(today), n = dayTimes(addDays(today, 1));
      expect(prayerWindowEnd(d, Prayer.ashar, n), d[Prayer.maghrib]);
      expect(prayerWindowEnd(d, Prayer.isya, n), n[Prayer.subuh]);
      expect(prayerWindowEnd(d, Prayer.isya, null), isNull);
    });
  });

  group('planPrayerReminders', () {
    List<PrayerNotificationSpec> plan({
      PrayerReminderSettings settings = on,
      Set<String> filled = const {},
      DateTime? now,
      int streak = 0,
      int maxTotal = kMaxPrayerNotifications,
    }) => planPrayerReminders(
      settings: settings,
      days: window(today),
      filled: filled,
      now: now ?? DateTime(2026, 9, 29, 12),
      streak: streak,
      maxTotal: maxTotal,
    );

    Iterable<PrayerNotificationSpec> of(
      List<PrayerNotificationSpec> p,
      PrayerNotificationKind k, {
      Prayer? prayer,
      String? day,
    }) => p.where(
      (s) =>
          s.kind == k &&
          (prayer == null || s.prayer == prayer) &&
          (day == null || s.dateKey == day),
    );

    test('master switch off → nothing', () {
      expect(plan(settings: const PrayerReminderSettings()), isEmpty);
    });

    test(
      'adzan for 7 days, follow-ups only in the first 2, sorted, nudge last',
      () {
        final p = plan();
        // Today from noon: Ashar, Maghrib, Isya left (+ 6 full days of 5).
        expect(of(p, PrayerNotificationKind.adzan), hasLength(3 + 6 * 5));
        final fuDays = of(
          p,
          PrayerNotificationKind.followUp,
        ).map((s) => s.dateKey).toSet();
        expect(fuDays, {key, dateKey(addDays(today, 1))});
        for (var i = 1; i < p.length; i++) {
          expect(p[i].fireAt.isBefore(p[i - 1].fireAt), isFalse);
        }
        expect(p.last.kind, PrayerNotificationKind.refresh);
        expect(p.last.id, kPrayerRefreshId);
        expect(
          p.every((s) => s.fireAt.isAfter(DateTime(2026, 9, 29, 12))),
          isTrue,
        );
        // Adzan + follow-ups carry the action, pre/refresh don't.
        expect(p.where((s) => s.hasDoneAction).map((s) => s.kind).toSet(), {
          PrayerNotificationKind.adzan,
          PrayerNotificationKind.followUp,
        });
      },
    );

    test('Dzuhur already passed at noon keeps its pending follow-ups', () {
      // Dzuhur 11.30 → follow-ups 12.00 (past cut-off at 12.00), 12.30, 13.00.
      final p = plan(now: DateTime(2026, 9, 29, 12, 10));
      expect(
        of(
          p,
          PrayerNotificationKind.followUp,
          prayer: Prayer.dzuhur,
          day: key,
        ).map((s) => s.fireAt),
        [DateTime(2026, 9, 29, 12, 30), DateTime(2026, 9, 29, 13, 0)],
      );
    });

    test(
      'ticked prayer → its follow-ups disappear (so the diff cancels them)',
      () {
        final before = plan();
        final after = plan(filled: {prayerFilledKey(key, Prayer.maghrib)});
        final gone = before.toSet().difference(after.toSet());
        expect(gone, isNotEmpty);
        expect(
          gone.every(
            (s) =>
                s.kind == PrayerNotificationKind.followUp &&
                s.prayer == Prayer.maghrib &&
                s.dateKey == key,
          ),
          isTrue,
        );
        // The adzan of that prayer and everything else stays.
        expect(
          of(
            after,
            PrayerNotificationKind.adzan,
            prayer: Prayer.maghrib,
            day: key,
          ),
          hasLength(1),
        );
        expect(
          of(
            after,
            PrayerNotificationKind.followUp,
            prayer: Prayer.isya,
            day: key,
          ),
          isNotEmpty,
        );
      },
    );

    test('pre-reminder N minutes before, only when on', () {
      expect(of(plan(), PrayerNotificationKind.pre), isEmpty);
      final s = on.withSlot(
        Prayer.maghrib,
        const PrayerSlotSettings(preEnabled: true, preMinutes: 10),
      );
      final pre = of(plan(settings: s), PrayerNotificationKind.pre).toList();
      expect(pre.map((x) => x.fireAt), [
        DateTime(2026, 9, 29, 17, 25),
        DateTime(2026, 9, 30, 17, 25),
      ]);
      expect(pre.first.title, contains('10 menit lagi Maghrib'));
    });

    test(
      'a disabled prayer gets nothing; per-prayer follow-up settings apply',
      () {
        final s = on
            .withSlot(Prayer.ashar, const PrayerSlotSettings(enabled: false))
            .withSlot(
              Prayer.isya,
              const PrayerSlotSettings(
                followUpDelay: 15,
                followUpInterval: 60,
                followUpMax: 5,
              ),
            );
        final p = plan(settings: s);
        expect(p.where((x) => x.prayer == Prayer.ashar), isEmpty);
        expect(
          of(
            p,
            PrayerNotificationKind.followUp,
            prayer: Prayer.isya,
            day: key,
          ).map((x) => x.fireAt),
          [
            DateTime(2026, 9, 29, 19, 0),
            DateTime(2026, 9, 29, 20, 0),
            DateTime(2026, 9, 29, 21, 0),
            DateTime(2026, 9, 29, 22, 0),
            DateTime(2026, 9, 29, 23, 0),
          ],
        );
      },
    );

    test('Maghrib follow-ups stop when Isya comes in', () {
      final fu = of(
        plan(),
        PrayerNotificationKind.followUp,
        prayer: Prayer.maghrib,
        day: key,
      );
      // 17.35 + 30 / 60 → 18.05, 18.35 (19.05 is after Isya 18.45).
      expect(fu.map((x) => x.fireAt), [
        DateTime(2026, 9, 29, 18, 5),
        DateTime(2026, 9, 29, 18, 35),
      ]);
    });

    test('capped, keeping the soonest', () {
      final p = plan(maxTotal: 10);
      expect(p, hasLength(10));
      expect(p.last.kind, PrayerNotificationKind.refresh);
      // 12.00 itself is inside the 5 s lead time → skipped.
      expect(p.first.fireAt, DateTime(2026, 9, 29, 12, 30));
    });

    test('stable copy (same inputs → same plan), streak in the copy', () {
      expect(plan(streak: 5), plan(streak: 5));
      final fu = of(
        plan(streak: 5),
        PrayerNotificationKind.followUp,
        prayer: Prayer.isya,
        day: key,
      ).toList();
      expect(fu.last.title, contains('terakhir'));
      expect(fu.last.body, contains('streak 5 hari'));
      final noStreak = of(
        plan(),
        PrayerNotificationKind.followUp,
      ).map((s) => '${s.title} ${s.body}');
      expect(noStreak.any((t) => t.contains('streak')), isFalse);
    });

    test('adzan copy names the prayer, time and place', () {
      final a = of(plan(), PrayerNotificationKind.adzan).first;
      expect(a.title, '🕌 Waktunya sholat Ashar · 14.40');
      expect(a.body, contains('Yogyakarta'));
    });
  });

  group('helpers', () {
    test('next and current prayer', () {
      final d = dayTimes(today), n = dayTimes(addDays(today, 1));
      expect(
        nextPrayerTime([d, n], DateTime(2026, 9, 29, 12))?.prayer,
        Prayer.ashar,
      );
      expect(
        nextPrayerTime([d, n], DateTime(2026, 9, 29, 20))?.at,
        n[Prayer.subuh],
      );
      expect(currentPrayer(d, DateTime(2026, 9, 29, 12)), Prayer.dzuhur);
      expect(currentPrayer(d, DateTime(2026, 9, 29, 4, 30)), Prayer.subuh);
      expect(currentPrayer(d, DateTime(2026, 9, 29, 6)), isNull);
      expect(currentPrayer(d, DateTime(2026, 9, 29, 3)), isNull);
    });

    test('distance and nearest city', () {
      final jkt = indonesianPrayerCities.firstWhere((c) => c.name == 'Jakarta');
      final bdg = indonesianPrayerCities.firstWhere((c) => c.name == 'Bandung');
      expect(distanceKm(jkt.lat, jkt.lng, bdg.lat, bdg.lng), closeTo(118, 6));
      expect(
        nearestCity(indonesianPrayerCities, -7.78, 110.40)?.name,
        'Yogyakarta',
      );
      expect(nearestCity(indonesianPrayerCities, 21.42, 39.82), isNull);
      expect(indonesianPrayerCities.length, greaterThanOrEqualTo(30));
    });
  });

  group('settings JSON', () {
    test('round-trips', () {
      final s =
          const PrayerReminderSettings(
            enabled: true,
            method: PrayerCalcMethod.mwl,
            sound: PrayerReminderSound.silent,
            location: PrayerLocation(
              source: PrayerLocationSource.gps,
              name: 'Dekat Bandung',
              lat: -6.9,
              lng: 107.6,
            ),
          ).withSlot(
            Prayer.subuh,
            const PrayerSlotSettings(
              preEnabled: true,
              preMinutes: 15,
              followUpMax: 5,
              offsetMinutes: -3,
            ),
          );
      final back = PrayerReminderSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.offsets[Prayer.subuh], -3);
    });

    test(
      'defaults: off, Yogyakarta, Kemenag, follow-ups on (30/30/3), pre off (10)',
      () {
        final d = PrayerReminderSettings.fromJson(null);
        expect(d.enabled, isFalse);
        expect(d.location.name, 'Yogyakarta');
        expect(d.method, PrayerCalcMethod.kemenag);
        final slot = d.slot(Prayer.isya);
        expect(slot.followUpEnabled, isTrue);
        expect(slot.followUpDelay, 30);
        expect(slot.followUpInterval, 30);
        expect(slot.followUpMax, 3);
        expect(slot.preEnabled, isFalse);
        expect(slot.preMinutes, 10);
      },
    );

    test('lenient: bad values clamp or fall back', () {
      final s = PrayerReminderSettings.fromJson({
        'on': true,
        'method': 'nope',
        'loc': {'lat': 200, 'lng': 0, 'name': 'x'},
        'slots': {
          'maghrib': {'offset': 99, 'fuMax': 0, 'fu': 'yes'},
        },
      });
      expect(s.method, PrayerCalcMethod.kemenag);
      expect(s.location, defaultPrayerLocation);
      expect(s.slot(Prayer.maghrib).offsetMinutes, 10);
      expect(s.slot(Prayer.maghrib).followUpMax, 1);
      expect(s.slot(Prayer.maghrib).followUpEnabled, isTrue);
    });
  });
}
