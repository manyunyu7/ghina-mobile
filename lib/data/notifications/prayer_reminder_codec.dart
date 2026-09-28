import 'dart:convert';

import '../../domain/entities/entities.dart';

/// Payload of every Reminder Sholat notification. Pending notifications only
/// give back id/title/body/payload, so it carries what's needed to recognise
/// ours, diff against the plan, route a tap and handle "✓ Sudah sholat".
class PrayerReminderPayload {
  const PrayerReminderPayload({
    required this.kind,
    required this.dateKey,
    required this.fireAt,
    required this.exact,
    this.prayer,
    this.index = 0,
    this.channel = '',
    this.timeZone = '',
  });

  static const kindTag = 'prayer_reminder';

  /// Tapping any prayer notification opens the Sholat page.
  static const route = '/prayers';

  final PrayerNotificationKind kind;
  final String dateKey;
  final Prayer? prayer;
  final int index;

  /// Local wall-clock ISO string.
  final String fireAt;
  final bool exact;

  /// Channel (sound option): a change makes the notification look changed.
  final String channel;
  final String timeZone;

  String encode() => jsonEncode({
    'kind': kindTag,
    'r': route,
    't': kind.name,
    'd': dateKey,
    if (prayer != null) 'p': prayer!.wire,
    'n': index,
    'at': fireAt,
    'x': exact,
    'ch': channel,
    'tz': timeZone,
  });

  static PrayerReminderPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['kind'] != kindTag) return null;
      final t = m['t'], d = m['d'], at = m['at'];
      if (t is! String || d is! String || at is! String) return null;
      final kind = PrayerNotificationKind.values
          .where((k) => k.name == t)
          .firstOrNull;
      if (kind == null) return null;
      final p = m['p'];
      final prayer = p is String
          ? Prayer.fardhu.where((x) => x.wire == p).firstOrNull
          : null;
      if (kind != PrayerNotificationKind.refresh && prayer == null) return null;
      return PrayerReminderPayload(
        kind: kind,
        dateKey: d,
        prayer: prayer,
        index: m['n'] is int ? m['n'] as int : 0,
        fireAt: at,
        exact: m['x'] == true,
        channel: m['ch'] is String ? m['ch'] as String : '',
        timeZone: m['tz'] is String ? m['tz'] as String : '',
      );
    } on FormatException {
      return null;
    }
  }
}
