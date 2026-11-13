import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-session marks for the messenger room list, kept on this device only:
/// when the owner last read a session, and whether it is pinned or muted.
class KantorRoomMarks {
  const KantorRoomMarks({
    this.readAt = const {},
    this.pinned = const {},
    this.muted = const {},
    this.unread = const {},
  });

  /// sid -> epoch ms the owner last had the session open.
  final Map<String, int> readAt;
  final Set<String> pinned;
  final Set<String> muted;

  /// Marked unread by hand ("Tandai belum dibaca").
  final Set<String> unread;

  Map<String, dynamic> toJson() => {
    'readAt': readAt,
    'pinned': pinned.toList(),
    'muted': muted.toList(),
    'unread': unread.toList(),
  };

  factory KantorRoomMarks.fromJson(Map<String, dynamic> j) {
    Set<String> set(Object? v) => {
      for (final e in (v is List ? v : const [])) '$e',
    };
    final r = j['readAt'];
    return KantorRoomMarks(
      readAt: {
        if (r is Map)
          for (final e in r.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      pinned: set(j['pinned']),
      muted: set(j['muted']),
      unread: set(j['unread']),
    );
  }
}

class KantorRoomMarksNotifier extends Notifier<KantorRoomMarks> {
  static const _key = 'kantor_room_marks_v1';
  bool _touched = false;

  @override
  KantorRoomMarks build() {
    _load();
    return const KantorRoomMarks();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || _touched) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) state = KantorRoomMarks.fromJson(j);
    } catch (_) {
      // no marks yet
    }
  }

  void _set(KantorRoomMarks next) {
    _touched = true;
    state = next;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode(next.toJson())))
        .catchError((_) => false);
  }

  void markRead(String sid) => _set(
    KantorRoomMarks(
      readAt: {...state.readAt, sid: DateTime.now().millisecondsSinceEpoch},
      pinned: state.pinned,
      muted: state.muted,
      unread: {...state.unread}..remove(sid),
    ),
  );

  void markUnread(String sid) => _set(
    KantorRoomMarks(
      readAt: state.readAt,
      pinned: state.pinned,
      muted: state.muted,
      unread: {...state.unread, sid},
    ),
  );

  void togglePin(String sid) => _set(
    KantorRoomMarks(
      readAt: state.readAt,
      pinned: state.pinned.contains(sid)
          ? ({...state.pinned}..remove(sid))
          : {...state.pinned, sid},
      muted: state.muted,
      unread: state.unread,
    ),
  );

  void toggleMute(String sid) => _set(
    KantorRoomMarks(
      readAt: state.readAt,
      pinned: state.pinned,
      muted: state.muted.contains(sid)
          ? ({...state.muted}..remove(sid))
          : {...state.muted, sid},
      unread: state.unread,
    ),
  );
}

final kantorRoomMarksProvider =
    NotifierProvider<KantorRoomMarksNotifier, KantorRoomMarks>(
      KantorRoomMarksNotifier.new,
    );

DateTime? kantorTime(Object? at) {
  if (at is num) return DateTime.fromMillisecondsSinceEpoch(at.toInt());
  if (at is String) return DateTime.tryParse(at)?.toLocal();
  return null;
}

const _hari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

/// Messenger-style stamp: "18.30" today, "Kemarin", a weekday this week,
/// else "13/11/26".
String messengerStamp(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  String two(int v) => v.toString().padLeft(2, '0');
  if (diff <= 0) return '${two(t.hour)}.${two(t.minute)}';
  if (diff == 1) return 'Kemarin';
  if (diff < 7) return _hari[t.weekday - 1];
  return '${two(t.day)}/${two(t.month)}/${two(t.year % 100)}';
}
