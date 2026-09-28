import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/prayer_reminders.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fake_notification_gateway.dart';

/// Round prayer times, every day.
class FakeCalculator implements PrayerTimesCalculator {
  @override
  PrayerDayTimes compute(
    DateTime day, {
    required double lat,
    required double lng,
    required PrayerCalcMethod method,
    Map<Prayer, int> offsets = const {},
  }) {
    DateTime at(int h, int m, Prayer? p) => DateTime(
      day.year,
      day.month,
      day.day,
      h,
      m,
    ).add(Duration(minutes: offsets[p] ?? 0));
    return PrayerDayTimes(
      day: startOfDay(day),
      sunrise: at(5, 20, null),
      times: {
        Prayer.subuh: at(4, 10, Prayer.subuh),
        Prayer.dzuhur: at(11, 30, Prayer.dzuhur),
        Prayer.ashar: at(14, 40, Prayer.ashar),
        Prayer.maghrib: at(17, 35, Prayer.maghrib),
        Prayer.isya: at(18, 45, Prayer.isya),
      },
    );
  }
}

PrayerEntry entry(DateTime day, Prayer p) => PrayerEntry(
  id: '${dateKey(day)}-${p.wire}',
  date: dateKey(day),
  prayer: p,
  status: PrayerStatus.jamaah,
  createdAt: day,
  updatedAt: day,
);

void main() {
  final now = DateTime(2026, 9, 29, 12);
  final today = startOfDay(now);
  const settings = PrayerReminderSettings(enabled: true);
  final build = BuildPrayerReminderPlan(ComputePrayerTimes(FakeCalculator()));

  late FakeNotificationGateway gw;
  late LocalPrayerReminderScheduler scheduler;

  setUp(() {
    gw = FakeNotificationGateway();
    scheduler = LocalPrayerReminderScheduler(gw);
  });

  List<int> followUpIdsOf(Prayer p) => [
    for (final r in gw.scheduled.values)
      if (PrayerReminderPayload.tryDecode(r.payload) case final pl?
          when pl.kind == PrayerNotificationKind.followUp &&
              pl.prayer == p &&
              pl.dateKey == dateKey(today))
        r.id,
  ];

  test(
    'schedules the plan: action on adzan + follow-ups, channel, exact',
    () async {
      final plan = build(settings, const [], now);
      await scheduler.replaceAll(plan);
      expect(gw.scheduled.length, plan.length);
      expect(gw.initCount, 1);
      final adzan =
          gw.scheduled[prayerNotificationId(
            today,
            Prayer.maghrib,
            PrayerNotificationKind.adzan,
          )]!;
      expect(adzan.exact, isTrue);
      expect(adzan.channel, NotificationChannelKind.prayer);
      expect(adzan.actions.single.id, prayerDoneActionId);
      expect(adzan.actions.single.label, '✓ Sudah sholat');
      expect(adzan.fireAt, DateTime(2026, 9, 29, 17, 35));
      final p = PrayerReminderPayload.tryDecode(adzan.payload)!;
      expect(p.prayer, Prayer.maghrib);
      expect(p.dateKey, '2026-09-29');
      expect(notificationRouteOf(adzan.payload), '/prayers');
      final refresh = gw.scheduled[kPrayerRefreshId]!;
      expect(refresh.actions, isEmpty);
    },
  );

  test('replanning the same plan touches nothing', () async {
    final plan = build(settings, const [], now);
    await scheduler.replaceAll(plan);
    gw.log.clear();
    await scheduler.replaceAll(build(settings, const [], now));
    expect(gw.log, isEmpty);
  });

  test('ticking a prayer in the app cancels exactly its follow-ups', () async {
    await scheduler.replaceAll(build(settings, const [], now));
    final maghribFu = followUpIdsOf(Prayer.maghrib);
    expect(maghribFu, hasLength(2));
    final isyaFu = followUpIdsOf(Prayer.isya);
    gw.log.clear();

    // The tracker row appears (tap in the app / notification action) → replan.
    await scheduler.replaceAll(
      build(settings, [entry(today, Prayer.maghrib)], now),
    );
    expect(gw.log, [for (final id in maghribFu) 'cancel $id']);
    expect(followUpIdsOf(Prayer.maghrib), isEmpty);
    expect(followUpIdsOf(Prayer.isya), isyaFu);

    // Un-ticking brings them back.
    await scheduler.replaceAll(build(settings, const [], now));
    expect(followUpIdsOf(Prayer.maghrib), maghribFu);
  });

  test('never touches task reminders; cancelAll only cancels ours', () async {
    final task = const ReminderPayload(
      key: 't1',
      route: '/tasks/t1',
      fireAt: 'x',
      exact: false,
    ).encode();
    gw.foreign[42] = PendingNotification(id: 42, payload: task);
    await scheduler.replaceAll(build(settings, const [], now));
    await scheduler.replaceAll(const []);
    expect(gw.foreign.keys, [42]);
    await scheduler.replaceAll(build(settings, const [], now));
    await scheduler.cancelAll();
    expect(gw.scheduled, isEmpty);
    expect(gw.foreign.keys, [42]);
    expect(gw.log, isNot(contains('cancelAll')));
  });

  test('sound change reschedules on the silent channel', () async {
    final plan = build(settings, const [], now);
    await scheduler.replaceAll(plan);
    gw.log.clear();
    await scheduler.replaceAll(plan, sound: PrayerReminderSound.silent);
    expect(
      gw.log.where((l) => l.startsWith('schedule')),
      hasLength(plan.length),
    );
    expect(
      gw.scheduled.values.every(
        (r) => r.channel == NotificationChannelKind.prayerSilent,
      ),
      isTrue,
    );
  });

  test('inexact without the permission; exact refusal falls back', () async {
    gw.exactAllowed = false;
    final plan = build(settings, const [], now);
    await scheduler.replaceAll(plan);
    expect(gw.scheduled.values.every((r) => !r.exact), isTrue);

    gw
      ..exactAllowed = true
      ..rejectExact = true;
    await scheduler.replaceAll(plan);
    expect(gw.scheduled.length, plan.length);
    expect(gw.scheduled.values.every((r) => !r.exact), isTrue);
  });

  group('"✓ Sudah sholat" action', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    String payloadOf(Prayer p) {
      final spec = build(settings, const [], now).firstWhere(
        (s) => s.kind == PrayerNotificationKind.adzan && s.prayer == p,
      );
      return prayerNotificationRequest(
        spec,
        exact: true,
        channel: NotificationChannelKind.prayer,
      ).payload;
    }

    test('records the prayer (quick = jamaah, synced via outbox), cancels '
        'follow-ups and confirms', () async {
      await scheduler.replaceAll(build(settings, const [], now));
      final fu = followUpIdsOf(Prayer.maghrib);
      expect(fu, isNotEmpty);

      final ok = await handlePrayerDoneAction(
        payloadOf(Prayer.maghrib),
        db: db,
        gateway: gw,
      );
      expect(ok, isTrue);
      final rows = await db.select(db.prayers).get();
      expect(rows, hasLength(1));
      expect(rows.single.date, '2026-09-29');
      expect(rows.single.prayer, 'maghrib');
      expect(rows.single.status, PrayerStatus.jamaah.wire);
      expect(await db.select(db.outbox).get(), hasLength(1));
      for (final id in fu) {
        expect(gw.scheduled.containsKey(id), isFalse, reason: 'follow-up $id');
      }
      // Isya's follow-ups and the adzans stay.
      expect(followUpIdsOf(Prayer.isya), isNotEmpty);
      expect(gw.shown.single.title, 'Alhamdulillah! Maghrib tercatat ✓');
      expect(gw.shown.single.body, contains('+8 XP'));
    });

    test(
      'already filled in → no second row, follow-ups still cancelled',
      () async {
        await handlePrayerDoneAction(
          payloadOf(Prayer.isya),
          db: db,
          gateway: gw,
        );
        await scheduler.replaceAll(build(settings, const [], now));
        final ok = await handlePrayerDoneAction(
          payloadOf(Prayer.isya),
          db: db,
          gateway: gw,
        );
        expect(ok, isFalse);
        expect(await db.select(db.prayers).get(), hasLength(1));
        expect(followUpIdsOf(Prayer.isya), isEmpty);
        expect(gw.shown.last.title, 'Isya sudah tercatat ✓');
      },
    );

    test('ignores foreign / broken payloads', () async {
      expect(await handlePrayerDoneAction(null, db: db, gateway: gw), isFalse);
      expect(
        await handlePrayerDoneAction(
          '{"kind":"task_reminder"}',
          db: db,
          gateway: gw,
        ),
        isFalse,
      );
      expect(await db.select(db.prayers).get(), isEmpty);
      expect(gw.shown, isEmpty);
    });
  });
}
