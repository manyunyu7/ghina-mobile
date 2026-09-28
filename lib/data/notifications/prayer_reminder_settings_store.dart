import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/entities.dart';
import '../../domain/services/prayer_reminders.dart';

/// Device-local (not synced) like the task reminder settings: one JSON value
/// in shared_preferences (per-prayer options are nested).
class SharedPrefsPrayerReminderSettingsStore
    implements PrayerReminderSettingsStore {
  SharedPrefsPrayerReminderSettingsStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const key = 'prayerReminder.settings';

  @override
  Future<PrayerReminderSettings> load() async {
    final raw = (await _prefs).getString(key);
    if (raw == null || raw.isEmpty) return const PrayerReminderSettings();
    try {
      return PrayerReminderSettings.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      debugPrint('Prayer reminder settings unreadable, using defaults: $e');
      return const PrayerReminderSettings();
    }
  }

  @override
  Future<void> save(PrayerReminderSettings settings) async =>
      (await _prefs).setString(key, jsonEncode(settings.toJson()));
}

class InMemoryPrayerReminderSettingsStore
    implements PrayerReminderSettingsStore {
  InMemoryPrayerReminderSettingsStore([
    this.value = const PrayerReminderSettings(),
  ]);

  PrayerReminderSettings value;
  int saves = 0;

  @override
  Future<PrayerReminderSettings> load() async => value;

  @override
  Future<void> save(PrayerReminderSettings settings) async {
    saves++;
    value = settings;
  }
}
