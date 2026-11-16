import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import 'kantor_snapshot_store.dart';

/// Stable routing identity without exposing an authentication token in keys or
/// the persisted outbox. A different account on the same URL is a different chat.
String kantorConnectionKey(KantorConfig config) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
          config.token,
        ]),
      ),
    )
    .toString();

typedef KantorChatKey = ({String connection, String office, String sid});

class KantorChatMemory {
  TextEditingValue draft = TextEditingValue.empty;
  double scrollOffset = 0;
}

/// Kept for the lifetime of the app's ProviderScope, including route changes.
/// Drafts intentionally stay in memory rather than being written to disk.
final kantorChatMemoryProvider = Provider(
  (ref) => <KantorChatKey, KantorChatMemory>{},
);

String kantorOpenChatKey(String connection, String office, String sid) =>
    jsonEncode([connection, office, sid]);

/// One chat's recent transcript as the app last saw it.
class KantorTranscriptSnap {
  const KantorTranscriptSnap({
    required this.items,
    required this.cursor,
    required this.size,
    required this.at,
    this.first,
    this.gen,
    this.older = false,
  });

  final List<Map<String, dynamic>> items;

  /// Delta cursor from the daemon (null on daemons without delta support).
  final String? cursor;
  final Object? size;

  /// When the daemon last confirmed this snapshot.
  final DateTime at;

  /// Daemon sequence number of `items.first` and the transcript generation it
  /// belongs to, for paging back (`?before=<first>&gen=<gen>`). Null on
  /// daemons without paging.
  final int? first;
  final String? gen;

  /// The daemon holds lines older than `items.first`.
  final bool older;

  Map<String, dynamic> toJson() => {
    'items': items,
    'cursor': cursor,
    'size': size,
    'at': at.millisecondsSinceEpoch,
    'first': first,
    'gen': gen,
    'older': older,
  };

  static KantorTranscriptSnap? fromJson(Object? j) {
    if (j is! Map) return null;
    final items = j['items'];
    final at = j['at'];
    if (items is! List || at is! int) return null;
    return KantorTranscriptSnap(
      items: [
        for (final e in items)
          if (e is Map) Map<String, dynamic>.from(e),
      ],
      cursor: j['cursor'] is String ? j['cursor'] as String : null,
      size: j['size'],
      at: DateTime.fromMillisecondsSinceEpoch(at),
      first: j['first'] is int ? j['first'] as int : null,
      gen: j['gen'] is String ? j['gen'] as String : null,
      older: j['older'] == true,
    );
  }
}

/// Recently opened chats, held in memory so that reopening a chat or coming back from another office shows its history at
/// once while only the new lines are fetched. Bounded: [maxChats] chats of at
/// most [maxItems] items each, least recently used dropped first, and all of it
/// dropped when the system reports memory pressure. A small tail of each chat
/// is also kept on disk by [KantorSnapshotStore] (through [onPut] and [seed]).
class KantorTranscriptCache {
  KantorTranscriptCache({this.maxChats = 8, this.maxItems = 200});

  final int maxChats;
  final int maxItems;
  final _chats = <KantorChatKey, KantorTranscriptSnap>{};

  int get length => _chats.length;

  /// Called after every [put] with what was stored (the disk snapshot).
  void Function(KantorChatKey key, KantorTranscriptSnap snap)? onPut;

  /// Adds chats read from disk, given least recently used first, as older
  /// than anything already held (which was opened in this run, so newer);
  /// chats already held are kept as they are. Does not call [onPut].
  void seed(Iterable<(KantorChatKey, KantorTranscriptSnap)> chats) {
    final held = Map.of(_chats);
    _chats.clear();
    for (final (key, snap) in chats) {
      if (!held.containsKey(key)) _store(key, snap);
    }
    for (final e in held.entries) {
      _chats.remove(e.key);
      _chats[e.key] = e.value;
    }
    while (_chats.length > maxChats) {
      _chats.remove(_chats.keys.first);
    }
  }

  KantorTranscriptSnap? get(KantorChatKey key) {
    final snap = _chats.remove(key);
    if (snap != null) _chats[key] = snap; // most recently used goes last
    return snap;
  }

  /// [persist] false: already on disk (read back by [KantorSnapshotStore]).
  void put(
    KantorChatKey key,
    KantorTranscriptSnap snap, {
    bool persist = true,
  }) {
    _store(key, snap);
    while (_chats.length > maxChats) {
      _chats.remove(_chats.keys.first);
    }
    if (persist) onPut?.call(key, _chats[key]!);
  }

  void _store(KantorChatKey key, KantorTranscriptSnap snap) {
    _chats.remove(key);
    final items = snap.items.length > maxItems
        ? snap.items.sublist(snap.items.length - maxItems)
        : snap.items;
    _chats[key] = identical(items, snap.items)
        ? snap
        : KantorTranscriptSnap(
            items: items,
            cursor: snap.cursor,
            size: snap.size,
            at: snap.at,
            first: snap.first == null
                ? null
                : snap.first! + (snap.items.length - items.length),
            gen: snap.gen,
            older: snap.older || items.length < snap.items.length,
          );
  }

  void clear() => _chats.clear();

  /// Like [get] but without marking the chat as recently used.
  KantorTranscriptSnap? peek(KantorChatKey key) => _chats[key];

  bool get hasRoom => _chats.length < maxChats;
}

final _prefetching = <KantorChatKey>{};

/// Fetches the recent transcript of [sids] ahead of time (the agents shown
/// first in a list), so opening one of those chats for the first time shows
/// its history at once. Only fills free room in [cache]: it never pushes out a
/// chat the owner actually opened. Status, permissions and actions are not
/// part of this and still come fresh from the office feed.
Future<void> kantorPrefetchChats(
  KantorApi api,
  KantorTranscriptCache cache,
  String office,
  Iterable<String> sids,
) async {
  final connection = kantorConnectionKey(api.config);
  for (final sid in sids) {
    final key = (connection: connection, office: office, sid: sid);
    if (!cache.hasRoom) return;
    if (cache.peek(key) != null || !_prefetching.add(key)) continue;
    try {
      final raw = await api.get(
        '/api/sessions/${Uri.encodeComponent(sid)}/transcript',
        query: {'n': cache.maxItems, 'delta': 1},
      );
      if (raw is! Map || cache.peek(key) != null || !cache.hasRoom) continue;
      final data = Map<String, dynamic>.from(raw);
      final merged = mergeTranscript(null, data, keep: cache.maxItems);
      cache.put(
        key,
        KantorTranscriptSnap(
          items: merged.items,
          cursor: merged.cursor,
          size: data['size'],
          at: DateTime.now(),
        ),
      );
    } catch (_) {
      // best effort: the chat simply loads normally when opened
    } finally {
      _prefetching.remove(key);
    }
  }
}

class _MemoryPressure with WidgetsBindingObserver {
  _MemoryPressure(this.onPressure);

  final VoidCallback onPressure;

  @override
  void didHaveMemoryPressure() => onPressure();
}

final kantorTranscriptCacheProvider = Provider<KantorTranscriptCache>((ref) {
  // ~20 chats come back from disk at start ([kantorSnapshotWarmChats]); the
  // rest leaves room for prefetching the chats of the office being opened
  final cache = KantorTranscriptCache(maxChats: kantorSnapshotWarmChats + 4);
  WidgetsBinding? binding;
  try {
    binding = WidgetsBinding.instance;
  } catch (_) {
    binding = null; // plain unit tests without a binding
  }
  if (binding != null) {
    final watcher = _MemoryPressure(cache.clear);
    binding.addObserver(watcher);
    ref.onDispose(() => binding!.removeObserver(watcher));
  }
  ref.onDispose(cache.clear);
  // chats kept on disk from an earlier run; later puts are written there too
  ref.read(kantorSnapshotStoreProvider).attachCache(cache);
  ref.onDispose(() => cache.onPut = null);
  return cache;
});

/// Applies one `GET /transcript` answer to the items the app already holds.
///
/// A daemon with delta support answers with a `cursor`; `reset: false` means
/// [data] carries only the lines after the cursor that was sent. Anything else
/// (an old daemon, `reset: true`, nothing held yet) is the whole tail, which
/// replaces what was held so a rewritten or cleared transcript never mixes
/// with the old one.
({List<Map<String, dynamic>> items, String? cursor, bool changed})
mergeTranscript(
  List<Map<String, dynamic>>? held,
  Map<String, dynamic> data, {
  int keep = 200,
}) {
  List<Map<String, dynamic>> tail(List<Map<String, dynamic>> l) =>
      l.length > keep ? l.sublist(l.length - keep) : l;
  final raw = data['items'];
  final items = <Map<String, dynamic>>[
    if (raw is List)
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
  ];
  final cursor = data['cursor'] is String ? data['cursor'] as String : null;
  if (cursor == null || held == null || data['reset'] != false) {
    return (items: tail(items), cursor: cursor, changed: true);
  }
  if (items.isEmpty) return (items: held, cursor: cursor, changed: false);
  return (items: tail([...held, ...items]), cursor: cursor, changed: true);
}
