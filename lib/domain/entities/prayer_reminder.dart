/// "Reminder Sholat": offline prayer times + scheduled notifications for the
/// five fardhu (docs in `lib/data/notifications/README.md` → Reminder Sholat).
///
/// Pure value types; the time calculation (adhan), the notification plugin and
/// the settings storage are behind the ports in `domain/services`.
library;

import 'enums.dart';

/// How the prayer times are calculated (angles of the sun for Subuh / Isya).
enum PrayerCalcMethod {
  kemenag('kemenag', 'Kemenag RI', 'Subuh 20°, Isya 18°, ihtiyat 2 menit'),
  mwl('mwl', 'Muslim World League', 'Subuh 18°, Isya 17°'),
  egyptian('egyptian', 'Mesir (Egyptian)', 'Subuh 19,5°, Isya 17,5°'),
  karachi('karachi', 'Karachi', 'Subuh 18°, Isya 18°'),
  ummAlQura(
    'umm_al_qura',
    'Umm al-Qura (Makkah)',
    'Subuh 18,5°, Isya +90 menit',
  ),
  singapore('singapore', 'MUIS Singapura', 'Subuh 20°, Isya 18°'),
  isna('isna', 'ISNA (Amerika Utara)', 'Subuh 15°, Isya 15°');

  const PrayerCalcMethod(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  static PrayerCalcMethod fromWire(Object? w) => values.firstWhere(
    (m) => m.wire == w,
    orElse: () => PrayerCalcMethod.kemenag,
  );
}

/// Sound of the prayer notifications. Android fixes the sound per channel, so
/// each option is its own notification channel.
enum PrayerReminderSound {
  system('system', 'Suara notifikasi bawaan'),
  silent('silent', 'Senyap (tanpa suara & getar)');

  const PrayerReminderSound(this.wire, this.label);

  final String wire;
  final String label;

  static PrayerReminderSound fromWire(Object? w) => values.firstWhere(
    (s) => s.wire == w,
    orElse: () => PrayerReminderSound.system,
  );
}

enum PrayerLocationSource { city, gps }

/// A preset city (manual location).
final class PrayerCity {
  const PrayerCity(this.name, this.province, this.lat, this.lng);

  final String name;
  final String province;
  final double lat;
  final double lng;
}

/// Where the prayer times are calculated for.
final class PrayerLocation {
  const PrayerLocation({
    required this.source,
    required this.name,
    required this.lat,
    required this.lng,
    this.updatedAt,
  });

  factory PrayerLocation.city(PrayerCity c) => PrayerLocation(
    source: PrayerLocationSource.city,
    name: c.name,
    lat: c.lat,
    lng: c.lng,
  );

  final PrayerLocationSource source;

  /// City name, or "Lokasi GPS" / "Dekat Yogyakarta" for GPS fixes.
  final String name;
  final double lat;
  final double lng;

  /// GPS: when the coordinates were last fixed.
  final DateTime? updatedAt;

  bool get isGps => source == PrayerLocationSource.gps;

  Map<String, Object?> toJson() => {
    'src': source.name,
    'name': name,
    'lat': lat,
    'lng': lng,
    if (updatedAt != null) 'at': updatedAt!.toIso8601String(),
  };

  static PrayerLocation? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'], name = j['name'];
    if (lat is! num || lng is! num || name is! String) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    final at = j['at'];
    return PrayerLocation(
      source: j['src'] == 'gps'
          ? PrayerLocationSource.gps
          : PrayerLocationSource.city,
      name: name,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      updatedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerLocation &&
      other.source == source &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(source, name, lat, lng, updatedAt);
}

/// Per-prayer reminder options.
final class PrayerSlotSettings {
  const PrayerSlotSettings({
    this.enabled = true,
    this.preEnabled = false,
    this.preMinutes = 10,
    this.followUpEnabled = true,
    this.followUpDelay = 30,
    this.followUpInterval = 30,
    this.followUpMax = 3,
    this.offsetMinutes = 0,
  });

  static const preMinuteOptions = [5, 10, 15, 20, 30];
  static const delayOptions = [10, 15, 20, 30, 45, 60];
  static const intervalOptions = [10, 15, 20, 30, 45, 60];
  static const maxFollowUps = 6;
  static const minOffset = -10;
  static const maxOffset = 10;

  /// Adzan notification for this prayer at all.
  final bool enabled;

  /// "10 menit lagi Maghrib" before the time comes in.
  final bool preEnabled;
  final int preMinutes;

  /// Follow-ups while the prayer isn't ticked in the tracker.
  final bool followUpEnabled;

  /// Minutes after adzan for the first follow-up.
  final int followUpDelay;

  /// Minutes between follow-ups.
  final int followUpInterval;

  /// At most this many follow-ups (1..[maxFollowUps]).
  final int followUpMax;

  /// Manual correction of the calculated time (-10..+10 minutes).
  final int offsetMinutes;

  PrayerSlotSettings copyWith({
    bool? enabled,
    bool? preEnabled,
    int? preMinutes,
    bool? followUpEnabled,
    int? followUpDelay,
    int? followUpInterval,
    int? followUpMax,
    int? offsetMinutes,
  }) => PrayerSlotSettings(
    enabled: enabled ?? this.enabled,
    preEnabled: preEnabled ?? this.preEnabled,
    preMinutes: preMinutes ?? this.preMinutes,
    followUpEnabled: followUpEnabled ?? this.followUpEnabled,
    followUpDelay: followUpDelay ?? this.followUpDelay,
    followUpInterval: followUpInterval ?? this.followUpInterval,
    followUpMax: followUpMax ?? this.followUpMax,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
  );

  Map<String, Object?> toJson() => {
    'on': enabled,
    'pre': preEnabled,
    'preMin': preMinutes,
    'fu': followUpEnabled,
    'fuDelay': followUpDelay,
    'fuEvery': followUpInterval,
    'fuMax': followUpMax,
    'offset': offsetMinutes,
  };

  /// Lenient: unknown/out-of-range values fall back to the defaults / clamp.
  static PrayerSlotSettings fromJson(Object? j) {
    const d = PrayerSlotSettings();
    if (j is! Map) return d;
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    int i(String k, int def, int min, int max) {
      final v = j[k];
      return v is num ? v.toInt().clamp(min, max) : def;
    }

    return PrayerSlotSettings(
      enabled: b('on', d.enabled),
      preEnabled: b('pre', d.preEnabled),
      preMinutes: i('preMin', d.preMinutes, 1, 60),
      followUpEnabled: b('fu', d.followUpEnabled),
      followUpDelay: i('fuDelay', d.followUpDelay, 5, 120),
      followUpInterval: i('fuEvery', d.followUpInterval, 5, 120),
      followUpMax: i('fuMax', d.followUpMax, 1, maxFollowUps),
      offsetMinutes: i('offset', d.offsetMinutes, minOffset, maxOffset),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerSlotSettings &&
      other.enabled == enabled &&
      other.preEnabled == preEnabled &&
      other.preMinutes == preMinutes &&
      other.followUpEnabled == followUpEnabled &&
      other.followUpDelay == followUpDelay &&
      other.followUpInterval == followUpInterval &&
      other.followUpMax == followUpMax &&
      other.offsetMinutes == offsetMinutes;

  @override
  int get hashCode => Object.hash(
    enabled,
    preEnabled,
    preMinutes,
    followUpEnabled,
    followUpDelay,
    followUpInterval,
    followUpMax,
    offsetMinutes,
  );
}

/// Yogyakarta (Henry's home, the default location).
const defaultPrayerLocation = PrayerLocation(
  source: PrayerLocationSource.city,
  name: 'Yogyakarta',
  lat: -7.7956,
  lng: 110.3695,
);

/// Everything on the "Reminder Sholat" settings page (device-local).
final class PrayerReminderSettings {
  const PrayerReminderSettings({
    this.enabled = false,
    this.location = defaultPrayerLocation,
    this.method = PrayerCalcMethod.kemenag,
    this.sound = PrayerReminderSound.system,
    this.slots = const {},
  });

  /// Master switch. Off by default: turning it on asks for notification
  /// permission in context.
  final bool enabled;
  final PrayerLocation location;
  final PrayerCalcMethod method;
  final PrayerReminderSound sound;

  /// Fardhu → options; missing = defaults.
  final Map<Prayer, PrayerSlotSettings> slots;

  PrayerSlotSettings slot(Prayer p) => slots[p] ?? const PrayerSlotSettings();

  /// Manual offsets per prayer (minutes).
  Map<Prayer, int> get offsets => {
    for (final p in Prayer.fardhu) p: slot(p).offsetMinutes,
  };

  PrayerReminderSettings copyWith({
    bool? enabled,
    PrayerLocation? location,
    PrayerCalcMethod? method,
    PrayerReminderSound? sound,
    Map<Prayer, PrayerSlotSettings>? slots,
  }) => PrayerReminderSettings(
    enabled: enabled ?? this.enabled,
    location: location ?? this.location,
    method: method ?? this.method,
    sound: sound ?? this.sound,
    slots: slots ?? this.slots,
  );

  PrayerReminderSettings withSlot(Prayer p, PrayerSlotSettings s) =>
      copyWith(slots: {...slots, p: s});

  Map<String, Object?> toJson() => {
    'v': 1,
    'on': enabled,
    'loc': location.toJson(),
    'method': method.wire,
    'sound': sound.wire,
    'slots': {for (final p in Prayer.fardhu) p.wire: slot(p).toJson()},
  };

  static PrayerReminderSettings fromJson(Object? j) {
    if (j is! Map) return const PrayerReminderSettings();
    final rawSlots = j['slots'];
    return PrayerReminderSettings(
      enabled: j['on'] == true,
      location: PrayerLocation.fromJson(j['loc']) ?? defaultPrayerLocation,
      method: PrayerCalcMethod.fromWire(j['method']),
      sound: PrayerReminderSound.fromWire(j['sound']),
      slots: {
        for (final p in Prayer.fardhu)
          if (rawSlots is Map && rawSlots[p.wire] != null)
            p: PrayerSlotSettings.fromJson(rawSlots[p.wire]),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerReminderSettings &&
      other.enabled == enabled &&
      other.location == location &&
      other.method == method &&
      other.sound == sound &&
      Prayer.fardhu.every((p) => other.slot(p) == slot(p));

  @override
  int get hashCode => Object.hash(
    enabled,
    location,
    method,
    sound,
    Object.hashAll(Prayer.fardhu.map(slot)),
  );
}

/// The five fardhu times (+ sunrise) of one local day, in local wall-clock time.
final class PrayerDayTimes {
  const PrayerDayTimes({
    required this.day,
    required this.times,
    required this.sunrise,
  });

  /// Local midnight of the day.
  final DateTime day;

  /// Fardhu → time (offsets already applied).
  final Map<Prayer, DateTime> times;
  final DateTime sunrise;

  DateTime operator [](Prayer p) => times[p]!;
}

enum PrayerNotificationKind {
  /// "10 menit lagi Maghrib".
  pre,

  /// At the time itself, with the "✓ Sudah sholat" action.
  adzan,

  /// While not ticked, every N minutes (with the action too).
  followUp,

  /// End of the scheduled window: "open Ghina so reminders keep going".
  refresh,
}

/// One notification the plan wants scheduled.
final class PrayerNotificationSpec {
  const PrayerNotificationSpec({
    required this.id,
    required this.kind,
    required this.dateKey,
    required this.fireAt,
    required this.title,
    required this.body,
    this.prayer,
    this.index = 0,
  });

  /// Stable id (see `prayerNotificationId`).
  final int id;
  final PrayerNotificationKind kind;

  /// Local day the prayer belongs to (`YYYY-MM-DD`), e.g. Isya follow-ups
  /// after midnight still belong to the previous day.
  final String dateKey;

  /// Null only for [PrayerNotificationKind.refresh].
  final Prayer? prayer;

  /// Follow-up number (1-based); 0 otherwise.
  final int index;
  final DateTime fireAt;
  final String title;
  final String body;

  /// Adzan + follow-ups carry the "✓ Sudah sholat" action.
  bool get hasDoneAction =>
      kind == PrayerNotificationKind.adzan ||
      kind == PrayerNotificationKind.followUp;

  @override
  bool operator ==(Object other) =>
      other is PrayerNotificationSpec &&
      other.id == id &&
      other.kind == kind &&
      other.dateKey == dateKey &&
      other.prayer == prayer &&
      other.index == index &&
      other.fireAt == fireAt &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode =>
      Object.hash(id, kind, dateKey, prayer, index, fireAt, title, body);

  @override
  String toString() =>
      'PrayerNotificationSpec(${kind.name} ${prayer?.wire} $dateKey#$index @ $fireAt)';
}
