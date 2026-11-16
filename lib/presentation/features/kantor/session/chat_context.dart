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
      final w = applyTranscriptDelta(null, data, keep: cache.maxItems).window;
      cache.put(
        key,
        KantorTranscriptSnap(
          items: w.items,
          cursor: w.cursor,
          size: data['size'],
          at: DateTime.now(),
          first: w.first,
          gen: w.gen,
          older: w.older,
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

/// What the chat holds of one transcript: the items plus where they sit in
/// the daemon's transcript ([first] = sequence number of `items.first`,
/// [gen] = transcript generation, [older] = the daemon has lines before
/// [first]). Same meaning as the fields of [KantorTranscriptSnap].
typedef KantorTranscriptWindow = ({
  List<Map<String, dynamic>> items,
  String? cursor,
  int? first,
  String? gen,
  bool older,
});

/// Result of [applyTranscriptDelta] / [prependTranscript]: the new window and
/// whether its items changed.
typedef KantorTranscriptMerge = ({KantorTranscriptWindow window, bool changed});

List<Map<String, dynamic>> _itemsOf(Object? raw) => [
  if (raw is List)
    for (final e in raw)
      if (e is Map) Map<String, dynamic>.from(e),
];

/// Applies one `GET /transcript?delta=1` (or the `transcript` part of
/// `GET /open`) answer to [held], keeping `first`/`gen`/`older` in step.
///
/// The same rules as [mergeTranscript] decide between "append the delta" and
/// "replace with the whole tail"; at most [keep] items are kept and dropping
/// older ones moves `first` forward and sets `older`.
KantorTranscriptMerge applyTranscriptDelta(
  KantorTranscriptWindow? held,
  Map<String, dynamic> data, {
  int keep = 200,
}) {
  final items = _itemsOf(data['items']);
  final cursor = data['cursor'] is String ? data['cursor'] as String : null;
  final first = data['first'] is int ? data['first'] as int : null;
  final gen = data['gen'] is String ? data['gen'] as String : null;
  KantorTranscriptWindow trimmed(
    List<Map<String, dynamic>> l,
    int? first,
    String? gen,
    bool older,
  ) {
    if (l.length <= keep) {
      return (items: l, cursor: cursor, first: first, gen: gen, older: older);
    }
    final drop = l.length - keep;
    return (
      items: l.sublist(drop),
      cursor: cursor,
      first: first == null ? null : first + drop,
      gen: gen,
      older: true,
    );
  }

  if (cursor == null || held == null || data['reset'] != false) {
    return (
      window: trimmed(items, first, gen, data['older'] == true),
      changed: true,
    );
  }
  // a delta continues the held window: its start stays where it was
  var start = held.first;
  var older = held.older;
  if (start == null && first != null && items.isNotEmpty) {
    // window from a daemon (or cache) without paging info: the delta's own
    // sequence number places it, since the delta follows on directly
    final s = first - held.items.length;
    if (s >= 0) {
      start = s;
      older = s > 0;
    }
  }
  if (items.isEmpty) {
    return (
      window: (
        items: held.items,
        cursor: cursor,
        first: start,
        gen: gen ?? held.gen,
        older: older,
      ),
      changed: false,
    );
  }
  return (
    window: trimmed([...held.items, ...items], start, gen ?? held.gen, older),
    changed: true,
  );
}

/// Applies one `GET /transcript?before=<first>&gen=<gen>` answer: the older
/// items go in front of [held]. A `reset` answer (the transcript was
/// rewritten) or an answer that does not line up with [held] leaves the items
/// alone and only stops further paging.
KantorTranscriptMerge prependTranscript(
  KantorTranscriptWindow held,
  Map<String, dynamic> data,
) {
  KantorTranscriptMerge stop() => (
    window: (
      items: held.items,
      cursor: held.cursor,
      first: held.first,
      gen: held.gen,
      older: false,
    ),
    changed: false,
  );
  final at = held.first;
  if (data['reset'] == true || at == null) return stop();
  final gen = data['gen'] is String ? data['gen'] as String : held.gen;
  if (held.gen != null && gen != held.gen) return stop();
  var items = _itemsOf(data['items']);
  var first = data['first'] is int ? data['first'] as int : at - items.length;
  // the page must end right where the held window starts
  if (first + items.length > at) {
    final n = at - first;
    if (n < 0) return stop();
    items = items.sublist(0, n); // overlap: drop what is already held
  } else if (first + items.length < at) {
    return stop(); // gap: never show a hole in the history
  }
  final older = data['older'] == true && first > 0;
  if (items.isEmpty) {
    return (
      window: (
        items: held.items,
        cursor: held.cursor,
        first: held.first,
        gen: gen,
        older: older,
      ),
      changed: false,
    );
  }
  return (
    window: (
      items: [...items, ...held.items],
      cursor: held.cursor,
      first: first,
      gen: gen,
      older: older,
    ),
    changed: true,
  );
}

/// Timings of one chat load, for the hidden meter on the chat header.
class KantorLoadTiming {
  KantorLoadTiming({
    required this.source,
    required this.items,
    this.network,
    this.build,
    this.shown,
  });

  /// cache, open, delta or before.
  final String source;

  /// Items held after this load.
  final int items;

  /// Request until the JSON was in hand.
  Duration? network;

  /// buildChat + merge.
  Duration? build;

  /// setState until the first frame after it.
  Duration? shown;
  final DateTime at = DateTime.now();

  String get label {
    String ms(Duration? d) => d == null ? '–' : '${d.inMilliseconds} ms';
    return '$source · $items item · jaringan ${ms(network)} · '
        'susun ${ms(build)} · tampil ${ms(shown)}';
  }
}

/// Last few loads per chat, in memory only.
final kantorChatTimings = <KantorChatKey, List<KantorLoadTiming>>{};

void kantorRecordTiming(KantorChatKey key, KantorLoadTiming t) {
  final list = kantorChatTimings.remove(key) ?? <KantorLoadTiming>[];
  list.insert(0, t);
  if (list.length > 5) list.removeRange(5, list.length);
  kantorChatTimings[key] = list; // most recently used last
  while (kantorChatTimings.length > 16) {
    kantorChatTimings.remove(kantorChatTimings.keys.first);
  }
}

/// Connections whose daemon has no `GET /open` (answered 404): they use the
/// separate transcript + attachments requests.
final kantorNoOpenRoute = <String>{};

/// The hidden load meter: long-press on the chat header.
void showKantorChatTimings(BuildContext context, KantorChatKey key) {
  final list = kantorChatTimings[key] ?? const <KantorLoadTiming>[];
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('chat-timings'),
        duration: const Duration(seconds: 8),
        content: Text(
          list.isEmpty
              ? 'Belum ada pemuatan tercatat untuk chat ini.'
              : [
                  'Pemuatan terakhir:',
                  for (final t in list) t.label,
                ].join('\n'),
        ),
      ),
    );
}
