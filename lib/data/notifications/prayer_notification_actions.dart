/// "✓ Sudah sholat" on a Reminder Sholat notification: records the prayer in
/// the tracker and cancels its follow-ups **without opening the app**.
///
/// Android delivers action buttons with `showsUserInterface: false` to a
/// headless background engine (flutter_local_notifications'
/// `ActionBroadcastReceiver`), which runs [ghinaNotificationBackgroundHandler].
/// That isolate opens the shared drift database (`AppDatabase.open()` connects
/// to the same drift server isolate as the UI), writes the row + outbox entry
/// exactly like a tap in the app (so it syncs and earns the same XP — XP is
/// derived from prayer rows), and the UI's stream queries pick it up.
library;

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/result.dart';
import '../../domain/entities/entities.dart';
import '../../domain/game/xp_rules.dart';
import '../../domain/usecases/prayer_reminder_rules.dart';
import '../../domain/usecases/prayer_reminder_usecases.dart';
import '../datasources/local/app_database.dart';
import '../repositories/life_repositories.dart';
import '../repositories/local_store.dart';
import '../sync/outbox.dart';
import 'flutter_notification_gateway.dart';
import 'notification_gateway.dart';
import 'prayer_reminder_codec.dart';

const prayerDoneActionId = 'prayer_done';
const prayerDoneActionLabel = '✓ Sudah sholat';

/// iOS notification category carrying the action.
const prayerCategoryId = 'prayer_reminder';

/// Database the action writes to. The UI isolate registers its connection
/// (`appDatabaseProvider`); the background isolate opens its own once.
AppDatabase? prayerActionDatabase;
LocalStore? _store;

/// Registered with the plugin; must stay a top-level entry point.
@pragma('vm:entry-point')
void ghinaNotificationBackgroundHandler(NotificationResponse response) {
  final action = response.actionId;
  if (action == null || action.isEmpty) return;
  // Dart-side plugin implementations (path_provider, shared_preferences) in
  // this headless isolate.
  DartPluginRegistrant.ensureInitialized();
  handleNotificationAction(action, response.payload);
}

/// Dispatches an action button (background isolate or UI isolate).
void handleNotificationAction(String actionId, String? payload) {
  if (actionId != prayerDoneActionId) return;
  unawaited(handlePrayerDoneAction(payload));
}

/// Records the prayer of [payload] (unless already filled in), cancels its
/// follow-ups and shows a short confirmation. Returns whether a row was
/// written. Never throws.
Future<bool> handlePrayerDoneAction(
  String? payload, {
  AppDatabase? db,
  NotificationGateway? gateway,
  Clock clock = const SystemClock(),
}) async {
  final p = PrayerReminderPayload.tryDecode(payload);
  final prayer = p?.prayer;
  if (p == null || prayer == null || !isDateKey(p.dateKey)) return false;
  final day = parseDateKey(p.dateKey);
  final gw = gateway ?? FlutterNotificationGateway();

  var recorded = false;
  var failed = false;
  try {
    final LocalStore store;
    if (db != null) {
      store = LocalStore(db, Outbox(db), clock);
    } else {
      final d = prayerActionDatabase ??= AppDatabase.open();
      store = _store != null && identical(_store!.db, d)
          ? _store!
          : (_store = LocalStore(d, Outbox(d), clock));
    }
    final r = await RecordPrayerFromReminder(
      DriftPrayerRepository(store),
      clock,
    )(day, prayer);
    switch (r) {
      case Ok(:final value):
        recorded = value != null;
      case Err(:final failure):
        failed = true;
        debugPrint('Prayer action failed: ${failure.message}');
    }
  } catch (e) {
    failed = true;
    debugPrint('Prayer action failed: $e');
  }

  // Ticked (now or before): no more nagging for this prayer.
  if (!failed) {
    for (final id in prayerFollowUpIds(day, prayer)) {
      try {
        await gw.cancel(id);
      } catch (_) {}
    }
  }

  try {
    final xp = XpRules.prayerXp(PrayerStatus.quick.wire);
    await gw.show(
      NotificationRequest(
        // Reuses the adzan id: replaces it if it's still showing.
        id: prayerNotificationId(day, prayer, PrayerNotificationKind.adzan),
        title: failed
            ? 'Belum bisa mencatat ${prayer.label} 😕'
            : recorded
            ? 'Alhamdulillah! ${prayer.label} tercatat ✓'
            : '${prayer.label} sudah tercatat ✓',
        body: failed
            ? 'Buka Ghina buat mencatatnya, ya.'
            : recorded
            ? '+$xp XP masuk. Buka Ghina kapan-kapan buat lihat progresmu 🌱'
            : 'Pengingat susulannya sudah Ghina matikan.',
        fireAt: clock.now(),
        exact: false,
        channel: NotificationChannelKind.prayerSilent,
        payload: PrayerReminderPayload(
          kind: PrayerNotificationKind.adzan,
          dateKey: p.dateKey,
          prayer: prayer,
          fireAt: clock.now().toIso8601String(),
          exact: false,
          channel: 'confirmation',
        ).encode(),
      ),
    );
  } catch (e) {
    debugPrint('Prayer action confirmation failed: $e');
  }
  return recorded;
}
