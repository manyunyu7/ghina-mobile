import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../di/kantor_providers.dart';
import 'chat_context.dart';
import 'kantor_feed.dart';

/// Hard limit of the disk snapshot per connection (gzip files + index).
const kantorSnapshotMaxBytes = 50 * 1024 * 1024;

/// Chats kept on disk, and items kept per chat (the newest).
const kantorSnapshotMaxChats = 40;
const kantorSnapshotMaxItems = 200;

/// Most recently used chats read into the memory cache when the app starts;
/// the others are read when opened ([KantorSnapshotStore.warm]).
const kantorSnapshotWarmChats = 20;

/// A chat of an ended session not opened for this long goes first.
const kantorSnapshotEndedAge = Duration(hours: 24);

/// Small on-device snapshot of Kantor so opening an office or chat after
/// Android killed the app (or switching offices) shows something at once, then
/// refreshes. What is kept:
/// - up to [maxChats] chats with their last [maxItems] transcript items,
/// - the lite snapshot of every office opened, WITHOUT inbox or permissions
///   (live statuses are neutralised, see [kantorNeutralOffice]),
/// - the last office list from `/api/state` (no inbox, sessions, settings).
///
/// Manageable, as agreed with the owner: a hard limit of [maxBytes] per
/// connection, checked before anything is written; the size is shown and the
/// cache can be cleared in Pengaturan Kompleks. Past the limit, entries are
/// removed in this order:
/// 1. chats of ended sessions (ended in a fresh feed, or no longer listed by
///    their office) not opened for [kantorSnapshotEndedAge], oldest first,
/// 2. chats least recently opened,
/// 3. offices least recently opened (then the office list).
/// An ended chat is only a candidate: it stays and can be opened while it fits.
///
/// Layout: one gzip JSON file per item plus a small `index.json` (kind, ids,
/// last use, size) so start-up reads only what it shows. Writes are debounced
/// ([debounce]), also done when the app is paused, and atomic (`.tmp` then
/// rename).
///
/// Security: files live in the app-private support directory
/// (`getApplicationSupportDirectory()/kantor_snapshot/<connectionKey>/`), which
/// other apps cannot read, and Android's file-based encryption covers it. No
/// extra encryption layer and no new package. The folder name is
/// [kantorConnectionKey] (a SHA-256 of URL + token) and file names are hashes
/// of office/session ids, so no raw token is ever in a path or in the content.
/// Only one connection is kept: switching URL/token deletes the others.
///
/// Every disk error is swallowed (logged with debugPrint): the cache is best
/// effort and must never crash the app.
class KantorSnapshotStore {
  KantorSnapshotStore({
    required Future<Directory?> Function() root,
    this.maxBytes = kantorSnapshotMaxBytes,
    this.maxChats = kantorSnapshotMaxChats,
    this.maxItems = kantorSnapshotMaxItems,
    this.warmChats = kantorSnapshotWarmChats,
    this.debounce = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _rootFn = root,
       _clock = clock ?? DateTime.now;

  final Future<Directory?> Function() _rootFn;
  final int maxBytes;
  final int maxChats;
  final int maxItems;
  final int warmChats;
  final Duration debounce;
  final DateTime Function() _clock;

  /// Bytes on disk for the active connection.
  final usedBytes = ValueNotifier<int>(0);

  static const indexName = 'index.json';
  static const stateName = 'state.json.gz';

  Future<Directory?>? _rootFuture;
  String? _connection;
  Directory? _dir;
  int _generation = 0;
  Completer<void> _ready = Completer<void>()..complete();

  /// Everything on disk (or about to be), by file name.
  final _meta = <String, _Meta>{};

  /// Data waiting to be written, by file name.
  final _pending = <String, Object>{};
  bool _indexDirty = false;
  int _indexBytes = 0;

  /// Offices are small: all of them are held in memory for [office].
  final _offices = <String, Json>{};
  Json? _state;

  Timer? _timer;
  Future<void> _writing = Future.value();
  KantorTranscriptCache? _cache;
  bool _disposed = false;

  /// Completes when the active connection's files have been read.
  Future<void> get ready => _ready.future;

  String? get connection => _connection;

  int get _now => _clock().millisecondsSinceEpoch;

  Future<Directory?> _root() => _rootFuture ??= () async {
    try {
      return await _rootFn();
    } catch (e) {
      debugPrint('kantor snapshot: no storage ($e)');
      return null;
    }
  }();

  static String _h(Object v) =>
      sha256.convert(utf8.encode(jsonEncode(v))).toString().substring(0, 32);
  static String chatName(String office, String sid) =>
      'c_${_h([office, sid])}.json.gz';
  static String officeName(String office) => 'o_${_h(office)}.json.gz';

  // --- connection --------------------------------------------------------

  /// Makes [connection] (a [kantorConnectionKey], or null when no token is
  /// saved) the active one: reads its files and deletes other connections'.
  Future<void> activate(String? connection) {
    if (_disposed || connection == _connection) return ready;
    _reset();
    _connection = connection;
    final gen = ++_generation;
    final done = Completer<void>();
    _ready = done;
    () async {
      try {
        await _writing;
        final root = await _root();
        if (root == null || connection == null || gen != _generation) return;
        final dir = Directory(p.join(root.path, connection));
        try {
          if (await root.exists()) {
            await for (final e in root.list(followLinks: false)) {
              if (p.basename(e.path) != connection) {
                await e.delete(recursive: true);
              }
            }
          }
          await dir.create(recursive: true);
        } catch (e) {
          debugPrint('kantor snapshot: prepare failed ($e)');
        }
        if (gen != _generation) return;
        await _readAll(dir, gen);
      } catch (e) {
        debugPrint('kantor snapshot: activate failed ($e)');
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }();
    return done.future;
  }

  void _reset() {
    _timer?.cancel();
    _meta.clear();
    _pending.clear();
    _offices.clear();
    _state = null;
    _indexDirty = false;
    _indexBytes = 0;
    _dir = null;
    if (!_disposed) usedBytes.value = 0;
  }

  Future<void> _readAll(Directory dir, int gen) async {
    final files = <String, File>{};
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (name.endsWith('.json.gz') || name == indexName) {
          files[name] = e;
        } else {
          await _tryDelete(e); // a .tmp left by an interrupted write
        }
      }
    } catch (e) {
      debugPrint('kantor snapshot: list failed ($e)');
    }

    final meta = <String, _Meta>{};
    var indexOk = false;
    final indexFile = files.remove(indexName);
    if (indexFile != null) {
      try {
        final bytes = await indexFile.readAsBytes();
        final j = jsonDecode(utf8.decode(bytes));
        if (j is Map && j['v'] == 1 && j['files'] is Map) {
          for (final e in (j['files'] as Map).entries) {
            final m = _Meta.fromJson(e.value);
            if (m != null) meta['${e.key}'] = m;
          }
          indexOk = true;
          _indexBytes = bytes.length;
        }
      } catch (e) {
        debugPrint('kantor snapshot: index unreadable, rebuilding ($e)');
      }
    }
    if (!indexOk) _indexDirty = true;
    meta.removeWhere((name, _) => !files.containsKey(name));

    final offices = <String, Json>{};
    Json? state;
    for (final MapEntry(key: name, value: file) in files.entries) {
      final known = meta[name];
      if (known != null && known.kind == 'chat') {
        try {
          known.bytes = await file.length();
        } catch (_) {}
        continue; // chats are read when shown
      }
      // offices and the office list are small and read now; a file the
      // index does not know is read to learn what it is
      final w = await _decode(file);
      if (w == null) {
        meta.remove(name);
        continue;
      }
      final m = known != null && known.kind == w.meta.kind ? known : w.meta;
      if (!identical(m, known)) _indexDirty = true;
      m.bytes = w.bytes;
      meta[name] = m;
      if (m.kind == 'office' && w.data is Map) {
        offices[m.office!] = asJson(w.data);
      } else if (m.kind == 'state' && w.data is Map) {
        state = asJson(w.data);
      }
    }
    if (gen != _generation) return;
    _dir = dir;
    for (final e in meta.entries) {
      _meta.putIfAbsent(e.key, () => e.value); // puts meanwhile are newer
    }
    offices.forEach((k, v) => _offices.putIfAbsent(k, () => v));
    _state ??= state;
    _updateUsed();
    if (_cache != null) await _seedRecent(dir, gen);
    if (_pending.isNotEmpty || _indexDirty) _schedule();
  }

  /// The most recently used chats go into the memory cache.
  Future<void> _seedRecent(Directory dir, int gen) async {
    final recent =
        _meta.entries
            .where(
              (e) => e.value.kind == 'chat' && !_pending.containsKey(e.key),
            )
            .toList()
          ..sort((a, b) => b.value.used.compareTo(a.value.used));
    final warm = <(KantorChatKey, KantorTranscriptSnap)>[];
    for (final e in recent.take(warmChats)) {
      final snap = await _readChat(dir, e.key);
      if (gen != _generation) return;
      if (snap != null) warm.add((_chatKey(e.value), snap));
    }
    _cache?.seed(warm.reversed);
  }

  KantorChatKey _chatKey(_Meta m) =>
      (connection: _connection ?? '', office: m.office!, sid: m.sid!);

  Future<({_Meta meta, Object? data, int bytes})?> _decode(File f) async {
    try {
      final bytes = await f.readAsBytes();
      final j = jsonDecode(utf8.decode(gzip.decode(bytes)));
      final m = j is Map ? _Meta.fromJson(j) : null;
      if (m == null) throw const FormatException('bad snapshot');
      final data = j['data'];
      if (m.kind == 'chat' && KantorTranscriptSnap.fromJson(data) == null) {
        throw const FormatException('bad chat');
      }
      if (m.kind != 'chat' && data is! Map) {
        throw const FormatException('bad data');
      }
      return (meta: m, data: data, bytes: bytes.length);
    } catch (e) {
      debugPrint(
        'kantor snapshot: ignoring unreadable ${p.basename(f.path)} ($e)',
      );
      await _tryDelete(f);
      return null;
    }
  }

  Future<KantorTranscriptSnap?> _readChat(Directory dir, String name) async {
    final w = await _decode(File(p.join(dir.path, name)));
    final snap = w == null ? null : KantorTranscriptSnap.fromJson(w.data);
    if (snap == null) {
      _meta.remove(name);
      _indexDirty = true;
    }
    return snap;
  }

  // --- reads -------------------------------------------------------------

  /// The office snapshot held for [officeId], neutralised (no live status,
  /// no permission), as a fresh copy the feed may mutate.
  Json? office(String officeId) {
    final o = _offices[officeId];
    return o == null ? null : kantorNeutralOffice(_copy(o));
  }

  /// The last office list (`offices` of `/api/state`, without sessions).
  Json? get state => _state == null ? null : _copy(_state);

  /// Chats on disk (ids only), least recently used first.
  List<KantorChatKey> get chatKeys {
    if (_connection == null) return const [];
    final list = _meta.values.where((m) => m.kind == 'chat').toList()
      ..sort((a, b) => a.used.compareTo(b.used));
    return [for (final m in list) _chatKey(m)];
  }

  bool isEnded(KantorChatKey key) {
    final m = _meta[chatName(key.office, key.sid)];
    return m != null && _ended(m);
  }

  /// Puts [key]'s chat from disk into the memory cache (most recently used)
  /// if the cache does not hold it, and counts it as opened. Call before a
  /// chat opens (e.g. a tap in the agent list): [KantorTranscriptCache.get]
  /// then shows it at once. True when the cache holds the chat afterwards.
  Future<bool> warm(KantorChatKey key) async {
    final cache = _cache;
    if (cache == null || key.connection != _connection) return false;
    final name = chatName(key.office, key.sid);
    final m = _meta[name];
    if (m != null) {
      m.used = _now;
      _indexDirty = true;
      _schedule();
    }
    if (cache.peek(key) != null) return true;
    if (m == null) return false;
    final gen = _generation;
    final pending = _pending[name];
    KantorTranscriptSnap? snap = pending is KantorTranscriptSnap
        ? pending
        : null;
    final dir = _dir;
    if (snap == null && dir != null) snap = await _readChat(dir, name);
    if (snap == null || gen != _generation || cache.peek(key) != null) {
      return cache.peek(key) != null;
    }
    cache.put(key, snap, persist: false);
    return true;
  }

  /// Connects [cache]: recent chats from disk go into it (under what it
  /// already holds) and every [KantorTranscriptCache.put] is written here.
  void attachCache(KantorTranscriptCache cache) {
    _cache = cache;
    cache.onPut = putChat;
    final dir = _dir;
    if (dir != null) unawaited(_seedRecent(dir, _generation));
  }

  // --- writes ------------------------------------------------------------

  void putChat(KantorChatKey key, KantorTranscriptSnap snap) {
    if (_disposed || _connection == null || key.connection != _connection) {
      return;
    }
    final cut = snap.items.length > maxItems ? snap.items.length - maxItems : 0;
    final trimmed = cut == 0
        ? snap
        : KantorTranscriptSnap(
            items: snap.items.sublist(cut),
            cursor: snap.cursor,
            size: snap.size,
            at: snap.at,
            first: snap.first == null ? null : snap.first! + cut,
            gen: snap.gen,
            older: true,
          );
    final name = chatName(key.office, key.sid);
    final old = _meta[name];
    _meta[name] = _Meta(
      kind: 'chat',
      office: key.office,
      sid: key.sid,
      used: _now,
      ended: old?.ended ?? false,
      bytes: old?.bytes ?? 0,
    );
    _pending[name] = trimmed;
    _indexDirty = true;
    _schedule();
  }

  /// A fresh `GET /api/offices/<id>?lite=1` answer (after [KantorOfficeFeed.load]).
  /// Chats of sessions it lists as ended, or no longer lists, become
  /// candidates for removal.
  void putOffice(String officeId, Json office) {
    if (_disposed || _connection == null) return;
    final name = officeName(officeId);
    final old = _meta[name];
    _meta[name] = _Meta(
      kind: 'office',
      office: officeId,
      used: _now,
      bytes: old?.bytes ?? 0,
    );
    _offices[officeId] = office;
    _pending[name] = office;
    final live = {
      for (final s in asJsonList(office['sessions']))
        if (s['status'] != 'ended') '${s['sid']}',
    };
    for (final m in _meta.values) {
      if (m.kind == 'chat' && m.office == officeId) {
        m.ended = !live.contains(m.sid);
      }
    }
    _indexDirty = true;
    _schedule();
  }

  /// A fresh feed says [sid] ended (`session-gone`, or status `ended`).
  void markEnded(String officeId, String sid) {
    final m = _meta[chatName(officeId, sid)];
    if (_disposed || m == null || m.ended) return;
    m.ended = true;
    _indexDirty = true;
    _schedule();
  }

  /// A fresh `GET /api/state`: only the office list is kept.
  void putState(Map<String, dynamic> state) {
    if (_disposed || _connection == null) return;
    final offices = [
      for (final o in asJsonList(state['offices']))
        {
          for (final e in o.entries)
            if (e.key != 'sessions' && e.key != 'inbox') e.key: e.value,
        },
    ];
    _state = {'offices': offices};
    final old = _meta[stateName];
    _meta[stateName] = _Meta(kind: 'state', used: _now, bytes: old?.bytes ?? 0);
    _pending[stateName] = _state!;
    _indexDirty = true;
    _schedule();
  }

  void _schedule() {
    // before the files are read (or without storage) nothing is scheduled;
    // reading schedules the write of what became dirty meanwhile
    if (_disposed || _dir == null) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  bool _ended(_Meta m) {
    if (m.kind != 'chat') return false;
    if (m.ended) return true;
    final o = _offices[m.office];
    if (o == null) return false;
    for (final s in asJsonList(o['sessions'])) {
      if (s['sid'] == m.sid) return s['status'] == 'ended';
    }
    return true; // its office no longer lists it
  }

  /// Names in the order they are removed when space is needed.
  List<String> _evictionOrder() {
    final old = _now - kantorSnapshotEndedAge.inMilliseconds;
    int rank(_Meta m) => switch (m.kind) {
      'chat' => _ended(m) && m.used < old ? 0 : 1,
      'office' => 2,
      _ => 3,
    };
    return _meta.keys.toList()..sort((a, b) {
      final ma = _meta[a]!, mb = _meta[b]!;
      final r = rank(ma) - rank(mb);
      return r != 0 ? r : ma.used.compareTo(mb.used);
    });
  }

  /// Writes what changed now (debounced writes and app pause call this).
  Future<void> flush() {
    _timer?.cancel();
    final run = _writing.then((_) => _flush());
    _writing = run.catchError((Object e) {
      debugPrint('kantor snapshot: flush failed ($e)');
    });
    return _writing;
  }

  Future<void> _flush() async {
    final gen = _generation;
    final dir = _dir;
    if (dir == null || (_pending.isEmpty && !_indexDirty)) return;

    final drop = <String>{};
    void remove(String n) {
      final m = _meta.remove(n);
      _pending.remove(n);
      if (m?.kind == 'office') _offices.remove(m!.office);
      if (m?.kind == 'state') _state = null;
      drop.add(n);
      _indexDirty = true;
    }

    // count bound on chats, in the same order as the size bound
    final order = _evictionOrder();
    var chats = _meta.values.where((m) => m.kind == 'chat').length;
    for (final n in order) {
      if (chats <= maxChats) break;
      if (_meta[n]!.kind != 'chat') continue;
      remove(n);
      chats--;
    }

    // encode first, so the hard size limit holds before anything is written
    final encoded = <String, List<int>>{};
    for (final MapEntry(key: n, value: data) in _pending.entries.toList()) {
      final m = _meta[n];
      if (m == null) continue;
      try {
        final payload = switch (data) {
          final KantorTranscriptSnap s => s.toJson(),
          final Json o when m.kind == 'office' => kantorNeutralOffice(o),
          final other => other,
        };
        final bytes = gzip.encode(
          utf8.encode(jsonEncode({...m.toJson(), 'data': payload})),
        );
        encoded[n] = bytes;
        m.bytes = bytes.length;
      } catch (err) {
        debugPrint('kantor snapshot: cannot encode $n ($err)');
        remove(n);
      }
    }
    _pending.clear();
    var total =
        _meta.values.fold<int>(0, (s, m) => s + m.bytes) + _indexEstimate();
    for (final n in _evictionOrder()) {
      if (total <= maxBytes) break;
      total -= _meta[n]!.bytes;
      encoded.remove(n);
      remove(n);
    }

    for (final n in drop) {
      await _tryDelete(File(p.join(dir.path, n)));
    }
    for (final MapEntry(key: n, value: bytes) in encoded.entries) {
      if (gen != _generation) return;
      if (!await _atomicWrite(File(p.join(dir.path, n)), bytes)) {
        _meta.remove(n);
        _indexDirty = true;
      }
    }
    if (gen != _generation) return;
    if (_indexDirty) {
      _indexDirty = false;
      final bytes = utf8.encode(
        jsonEncode({
          'v': 1,
          'files': {for (final e in _meta.entries) e.key: e.value.toJson()},
        }),
      );
      if (await _atomicWrite(File(p.join(dir.path, indexName)), bytes)) {
        _indexBytes = bytes.length;
      }
    }
    _updateUsed();
  }

  int _indexEstimate() => 64 + _meta.length * 160;

  static Future<bool> _atomicWrite(File file, List<int> bytes) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return true;
    } catch (e) {
      debugPrint('kantor snapshot: write ${p.basename(file.path)} failed ($e)');
      await _tryDelete(tmp);
      return false;
    }
  }

  /// Deletes every connection's snapshot and empties the memory chat cache.
  Future<void> clearAll() async {
    if (_disposed) return;
    _reset();
    _cache?.clear();
    final gen = ++_generation; // a write in progress stops
    try {
      await _writing;
    } catch (_) {}
    final root = await _root();
    try {
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
      final c = _connection;
      if (root != null && c != null && gen == _generation) {
        final dir = Directory(p.join(root.path, c));
        await dir.create(recursive: true);
        _dir = dir;
      }
    } catch (e) {
      debugPrint('kantor snapshot: clear failed ($e)');
    }
  }

  void _updateUsed() {
    if (_disposed) return;
    usedBytes.value =
        _meta.values.fold<int>(0, (s, m) => s + m.bytes) +
        (_meta.isEmpty ? 0 : _indexBytes);
  }

  static Future<void> _tryDelete(FileSystemEntity f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('kantor snapshot: delete failed ($e)');
    }
  }

  static Json _copy(Object? v) => asJson(jsonDecode(jsonEncode(v)));

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_cache?.onPut == putChat) _cache?.onPut = null;
    usedBytes.dispose();
  }
}

class _Meta {
  _Meta({
    required this.kind,
    required this.used,
    this.office,
    this.sid,
    this.ended = false,
    this.bytes = 0,
  });

  final String kind; // chat | office | state
  final String? office;
  final String? sid;

  /// Last opened (chats: last shown or refreshed; offices: last loaded).
  int used;

  /// A fresh feed said the session ended (chats only).
  bool ended;
  int bytes;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'kind': kind,
    'office': office,
    'sid': sid,
    'used': used,
    'ended': ended,
  };

  static _Meta? fromJson(Object? j) {
    if (j is! Map || j['v'] != 1 || j['used'] is! int) return null;
    final kind = j['kind'];
    final office = j['office'] is String ? j['office'] as String : null;
    final sid = j['sid'] is String ? j['sid'] as String : null;
    switch (kind) {
      case 'chat':
        if (office == null || sid == null) return null;
      case 'office':
        if (office == null) return null;
      case 'state':
        break;
      default:
        return null;
    }
    return _Meta(
      kind: kind as String,
      office: office,
      sid: sid,
      used: j['used'] as int,
      ended: j['ended'] == true,
    );
  }
}

/// [office] as it may be shown before the daemon answered: live sessions get
/// an unknown status (`''`, shown as "Menyinkronkan…"), and no permission
/// wait, tool, subagents, work step, error or draft. Ended sessions stay ended.
Json kantorNeutralOffice(Json office) {
  Json neutral(Json s) {
    final out = Map<String, dynamic>.from(s)
      ..remove('waiting')
      ..remove('tool')
      ..remove('subs')
      ..remove('compacting');
    if (out['status'] != 'ended') out['status'] = '';
    final k = out['konteks'];
    if (k is Map) {
      out['konteks'] = Map<String, dynamic>.from(k)
        ..remove('kerjaan')
        ..remove('err')
        ..remove('draft')
        ..['state'] = {'k': 'sinkron', 'label': 'Menyinkronkan'};
    }
    return out;
  }

  return {
    ...office,
    'sessions': [for (final s in asJsonList(office['sessions'])) neutral(s)],
  }..remove('inbox');
}

/// Reads [key]'s chat from disk into the memory cache before it opens, at
/// most [wait] so a slow disk never holds the tap up.
Future<void> kantorWarmChat(
  ProviderContainer c,
  KantorChatKey key, {
  Duration wait = const Duration(milliseconds: 300),
}) async {
  try {
    await c
        .read(kantorSnapshotStoreProvider)
        .warm(key)
        .timeout(wait, onTimeout: () => false);
  } catch (e) {
    debugPrint('kantor snapshot: warm failed ($e)');
  }
}

/// `<app support>/kantor_snapshot`; tests override with a temp directory.
final kantorSnapshotRootProvider = Provider<Future<Directory?> Function()>(
  (ref) =>
      () async => Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          'kantor_snapshot',
        ),
      ),
);

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.onPause);
  final VoidCallback onPause;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      onPause();
    }
  }
}

final kantorSnapshotStoreProvider = Provider<KantorSnapshotStore>((ref) {
  final store = KantorSnapshotStore(
    root: ref.watch(kantorSnapshotRootProvider),
  );
  WidgetsBinding? binding;
  try {
    binding = WidgetsBinding.instance;
  } catch (_) {
    binding = null; // plain unit tests without a binding
  }
  if (binding != null) {
    final watcher = _Lifecycle(() => unawaited(store.flush()));
    binding.addObserver(watcher);
    ref.onDispose(() => binding!.removeObserver(watcher));
  }
  void onConfig(KantorConfig? c) => unawaited(
    store.activate(c != null && c.ready ? kantorConnectionKey(c) : null),
  );
  ref.listen(kantorConfigProvider, (_, next) {
    if (next.hasValue) onConfig(next.value);
  }, fireImmediately: true);
  ref.onDispose(store.dispose);
  return store;
});
