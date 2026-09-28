import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/entities.dart';
import '../../domain/services/prayer_reminders.dart';
import 'notification_gateway.dart';
import 'prayer_notification_actions.dart';
import 'prayer_reminder_codec.dart';

/// Schedules Reminder Sholat notifications through a [NotificationGateway].
///
/// Like `LocalReminderScheduler` (task reminders): lazy one-time init,
/// serialised calls, and [replaceAll] diffs the plan against the OS's pending
/// notifications — only ones carrying a [PrayerReminderPayload] are touched,
/// unchanged ones are left alone. Exact alarms are used whenever the OS
/// allows them (a prayer time is time-critical); otherwise inexact.
class LocalPrayerReminderScheduler implements PrayerReminderScheduler {
  LocalPrayerReminderScheduler(this._gateway);

  final NotificationGateway _gateway;

  Future<void>? _init;
  Future<void> _queue = Future.value();

  Future<void> _ensureInit() => _init ??= _gateway.initialize((_) {});

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) async {
      await _ensureInit();
      return op();
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<bool> canScheduleExact() => _serial(_gateway.canScheduleExact);

  @override
  Future<bool> requestExactAlarms() => _serial(_gateway.requestExactAlarms);

  @override
  Future<void> cancelAll() => _serial(() async {
    final pending = await _pendingOurs();
    if (pending == null) return;
    for (final id in pending.keys) {
      await _gateway.cancel(id);
    }
  });

  /// Our pending notifications by id; null when the OS can't list them.
  Future<Map<int, PendingNotification>?> _pendingOurs() async {
    try {
      return {
        for (final p in await _gateway.pending())
          if (PrayerReminderPayload.tryDecode(p.payload) != null) p.id: p,
      };
    } catch (e) {
      debugPrint('Reading pending prayer reminders failed: $e');
      return null;
    }
  }

  @override
  Future<void> replaceAll(
    List<PrayerNotificationSpec> plan, {
    PrayerReminderSound sound = PrayerReminderSound.system,
  }) => _serial(() async {
    final exact = await _gateway.canScheduleExact();
    final channel = sound == PrayerReminderSound.silent
        ? NotificationChannelKind.prayerSilent
        : NotificationChannelKind.prayer;
    final seen = <int>{};
    final requests = [
      for (final s in plan)
        if (seen.add(s.id))
          prayerNotificationRequest(
            s,
            exact: exact,
            channel: channel,
            timeZone: _gateway.timeZone,
          ),
    ];

    final ours = await _pendingOurs();
    if (ours != null) {
      final wanted = {for (final r in requests) r.id};
      for (final id in ours.keys) {
        if (!wanted.contains(id)) await _gateway.cancel(id);
      }
      requests.removeWhere((r) {
        final p = ours[r.id];
        return p != null &&
            p.title == r.title &&
            p.body == r.body &&
            p.payload == r.payload;
      });
    }
    for (final r in requests) {
      await _schedule(r);
    }
  });

  Future<void> _schedule(NotificationRequest r) async {
    try {
      await _gateway.schedule(r);
    } catch (e) {
      if (!r.exact) {
        debugPrint('Scheduling prayer reminder ${r.id} failed: $e');
        return;
      }
      // Exact alarms revoked between the check and now: go inexact.
      try {
        await _gateway.schedule(
          NotificationRequest(
            id: r.id,
            title: r.title,
            body: r.body,
            fireAt: r.fireAt,
            payload: r.payload,
            exact: false,
            channel: r.channel,
            actions: r.actions,
          ),
        );
      } catch (e) {
        debugPrint('Scheduling prayer reminder ${r.id} failed: $e');
      }
    }
  }
}

/// The gateway request of one planned notification.
NotificationRequest prayerNotificationRequest(
  PrayerNotificationSpec s, {
  required bool exact,
  required NotificationChannelKind channel,
  String timeZone = '',
}) => NotificationRequest(
  id: s.id,
  title: s.title,
  body: s.body,
  fireAt: s.fireAt,
  exact: exact,
  channel: channel,
  actions: s.hasDoneAction
      ? const [
          NotificationActionSpec(prayerDoneActionId, prayerDoneActionLabel),
        ]
      : const [],
  payload: PrayerReminderPayload(
    kind: s.kind,
    dateKey: s.dateKey,
    prayer: s.prayer,
    index: s.index,
    fireAt: s.fireAt.toIso8601String(),
    exact: exact,
    channel: channel.name,
    timeZone: timeZone,
  ).encode(),
);

/// Platforms without local notifications, and tests.
class NoopPrayerReminderScheduler implements PrayerReminderScheduler {
  const NoopPrayerReminderScheduler();

  @override
  Future<void> replaceAll(
    List<PrayerNotificationSpec> plan, {
    PrayerReminderSound sound = PrayerReminderSound.system,
  }) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> canScheduleExact() async => false;

  @override
  Future<bool> requestExactAlarms() async => false;
}
