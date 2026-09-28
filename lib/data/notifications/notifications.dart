/// Local notifications: task reminders and Reminder Sholat (see README.md).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../domain/services/prayer_reminders.dart';
import 'device_reminder_scheduler.dart';
import 'flutter_notification_gateway.dart';
import 'prayer_reminder_scheduler.dart';

export 'device_reminder_scheduler.dart';
export 'flutter_notification_gateway.dart' show FlutterNotificationGateway;
export 'notification_gateway.dart';
export 'adhan_prayer_times_calculator.dart';
export 'notification_settings_store.dart';
export 'prayer_notification_actions.dart'
    show
        prayerActionDatabase,
        prayerDoneActionId,
        prayerDoneActionLabel,
        handlePrayerDoneAction;
export 'prayer_reminder_codec.dart';
export 'prayer_reminder_scheduler.dart';
export 'prayer_reminder_settings_store.dart';
export 'reminder_codec.dart';

/// The real scheduler on Android/iOS, a no-op everywhere else (including
/// `flutter test`, where `defaultTargetPlatform` pretends to be Android).
DeviceReminderScheduler createDeviceReminderScheduler() => _supported
    ? LocalReminderScheduler(FlutterNotificationGateway())
    : const NoopReminderScheduler();

/// Reminder Sholat's scheduler (same plugin, its own channels / id block).
PrayerReminderScheduler createPrayerReminderScheduler() => _supported
    ? LocalPrayerReminderScheduler(FlutterNotificationGateway())
    : const NoopPrayerReminderScheduler();

bool get _supported =>
    !kIsWeb &&
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
