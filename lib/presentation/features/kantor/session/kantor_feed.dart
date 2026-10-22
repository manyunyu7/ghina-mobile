import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

typedef Json = Map<String, dynamic>;

Json asJson(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> asJsonList(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) asJson(e),
      ]
    : <Json>[];

/// One office as the agents tab and the session page see it: the
/// `GET /api/offices/<id>` snapshot, the open permission inbox for that
/// office, and the live `/ws` events patched onto both.
class KantorOfficeFeed extends ChangeNotifier {
  KantorOfficeFeed(this.officeId, this._api);

  final String officeId;
  final KantorApi? _api;

  Json? office;
  List<Json> inbox = const [];
  Object? error;
  bool loading = true;
  bool _disposed = false;
  Timer? _debounce;

  List<Json> get sessions => asJsonList(office?['sessions']);
  List<Json> get roles => asJsonList(office?['roles']);
  List<Json> get rooms => asJsonList(asJson(office?['plan'])['rooms']);

  Json? session(String sid) {
    for (final s in sessions) {
      if (s['sid'] == sid) return s;
    }
    return null;
  }

  Json? role(String? id) {
    if (id == null) return null;
    for (final r in roles) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  String roomName(String? id) {
    for (final r in rooms) {
      if (r['id'] == id) return '${r['name'] ?? id}';
    }
    return id ?? '';
  }

  Future<void> load() async {
    final api = _api;
    if (api == null) return;
    try {
      final results = await Future.wait([
        api.get('/api/offices/$officeId'),
        api.get('/api/inbox'),
      ]);
      office = asJson(results[0]);
      inbox = [
        for (final i in asJsonList(results[1]))
          if (i['office'] == officeId) i,
      ];
      error = null;
    } catch (e) {
      error = e;
    }
    loading = false;
    _notify();
  }

  void apply(Json? msg) {
    if (msg == null || office == null) return;
    switch (msg['t']) {
      case 'session':
        if (msg['office'] != officeId) return;
        final s = asJson(msg['session']);
        final list = sessions;
        final i = list.indexWhere((x) => x['sid'] == s['sid']);
        if (i < 0) {
          list.add(s);
        } else {
          list[i] = s;
        }
        office!['sessions'] = list;
      case 'session-gone':
        if (msg['office'] != officeId) return;
        final list = sessions;
        final i = list.indexWhere((x) => x['sid'] == msg['sid']);
        if (i >= 0) list[i] = {...list[i], 'status': 'ended', 'waiting': null};
        office!['sessions'] = list;
      case 'inbox':
        final item = asJson(msg['item']);
        if (item['office'] != officeId) return;
        inbox = [item, ...inbox.where((x) => x['id'] != item['id'])];
      case 'inbox-update':
        if (msg['status'] == 'open') return;
        inbox = inbox.where((x) => x['id'] != msg['id']).toList();
      case 'changed':
        final o = msg['office'];
        if ((o == officeId || o == '*') &&
            (msg['what'] == 'roles' || msg['what'] == 'plan')) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), load);
        }
        return;
      default:
        return;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

/// Shared by the agents tab and the session page, so both stay live from the
/// same snapshot.
final kantorOfficeFeedProvider = Provider.autoDispose
    .family<KantorOfficeFeed, String>((ref, officeId) {
      final feed = KantorOfficeFeed(officeId, ref.watch(kantorApiProvider));
      ref.listen(kantorEventsProvider, (_, next) => feed.apply(next.value));
      ref.onDispose(feed.dispose);
      feed.load();
      return feed;
    });

// --- shared labels -------------------------------------------------------

const kantorStatusLabel = {
  'starting': 'Memulai',
  'working': 'Bekerja',
  'idle': 'Idle',
  'waiting': 'Menunggu izin',
  'ended': 'Selesai',
};

const kantorModeLabel = {
  'default': 'Selalu tanya',
  'acceptEdits': 'Edit otomatis',
  'auto': 'Auto',
  'plan': 'Plan',
  'dontAsk': 'Tanpa tanya',
  'bypassPermissions': 'Bypass',
};

/// The modes the web `modeSelect` offers.
const kantorModeChoices = [
  'default',
  'acceptEdits',
  'auto',
  'plan',
  'bypassPermissions',
];

const kantorModelName = {
  'opus': 'Opus',
  'sonnet': 'Sonnet',
  'haiku': 'Haiku',
  'fable': 'Fable',
};

String modelLabel(Object? m) {
  final s = '$m';
  if (m == null || s.isEmpty) return '';
  final low = s.toLowerCase();
  for (final e in kantorModelName.entries) {
    if (low.contains(e.key)) return e.value;
  }
  return s;
}

String toolText(Object? tool) {
  if (tool is Map) return '${tool['label'] ?? tool['name'] ?? ''}'.trim();
  return tool == null ? '' : '$tool';
}

String toolFull(Object? tool) {
  if (tool is! Map) return '';
  return '${tool['name'] ?? ''} ${tool['label'] ?? ''}'.trim();
}

String clip(String s, int n) => s.length > n ? '${s.substring(0, n - 1)}…' : s;

/// "3 mnt", "2 j", "baru saja" from an ISO string or epoch millis.
String agoText(Object? at) {
  DateTime? t;
  if (at is num) {
    t = DateTime.fromMillisecondsSinceEpoch(at.toInt());
  } else if (at is String) {
    t = DateTime.tryParse(at);
  }
  if (t == null) return '';
  final sec = DateTime.now().difference(t).inSeconds;
  if (sec < 45) return 'baru saja';
  if (sec < 3600) return '${(sec / 60).round()} mnt';
  if (sec < 86400) return '${(sec / 3600).round()} j';
  return '${(sec / 86400).round()} hr';
}

/// Display name for a session, the same rule as the web `sessName`.
String sessionName(KantorOfficeFeed feed, Json s) {
  final r = feed.role(s['role'] as String?);
  final slot = (s['slot'] as num?)?.toInt() ?? 0;
  if (r != null) return '${r['name']}${slot > 0 ? ' #${slot + 1}' : ''}';
  final t = '${s['title'] ?? ''}';
  return t.isEmpty || t == 'Sesi belum terhubung' ? 'Sesi manual' : t;
}
