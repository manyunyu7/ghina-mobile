import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/remote/kantor_api.dart';
import 'remote_protocol.dart';

/// Where a hub's pairing request is authorized.
enum RemoteHubKind {
  /// kantor-claude: pairing asked with the app's Kantor token.
  kantor,

  /// Ravel relay (VPS): pairing asked with a relay owner token `kcowner_`.
  relay,
}

/// One signaling hub. Hubs do NOT share device tokens (interim until
/// protocol v2): each has its own pairing and `kcview_` token.
class RemoteHub {
  const RemoteHub({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
  });

  final String id;
  final String name;

  /// Origin, e.g. `https://relay.example.com`.
  final String url;
  final RemoteHubKind kind;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'kind': kind.name,
  };

  static RemoteHub? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final url = RemoteHubStore.parseUrl(raw['url']?.toString() ?? '');
    if (id is! String || id.isEmpty || url == null) return null;
    return RemoteHub(
      id: id,
      name: raw['name']?.toString() ?? url,
      url: url,
      kind: raw['kind'] == 'relay' ? RemoteHubKind.relay : RemoteHubKind.kantor,
    );
  }

  RemoteHub copyWith({String? name, String? url, RemoteHubKind? kind}) =>
      RemoteHub(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        kind: kind ?? this.kind,
      );
}

/// Secret storage seam (tests use a map).
abstract interface class RemoteSecrets {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureRemoteSecrets implements RemoteSecrets {
  const SecureRemoteSecrets([this._s = const FlutterSecureStorage()]);
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryRemoteSecrets implements RemoteSecrets {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Hub list (prefs) and per-hub tokens (secure storage):
/// - viewer token `kcview_…` per hub (from that hub's pairing);
/// - relay owner token `kcowner_…` per relay hub (to ask for pairing).
class RemoteHubStore {
  RemoteHubStore({Future<SharedPreferences>? prefs, RemoteSecrets? secrets})
    : _prefs = prefs ?? SharedPreferences.getInstance(),
      _secrets = secrets ?? const SecureRemoteSecrets();

  final Future<SharedPreferences> _prefs;
  final RemoteSecrets _secrets;

  static const _listKey = 'ravel.remote.hubs.v2';
  static const _seededKey = 'ravel.remote.hubs.seeded';

  /// Built-in relay (VPS), first in the list. Override at build time with
  /// `--dart-define=RAVEL_RELAY_URL=…` (empty = no built-in relay).
  static const defaultRelayUrl = String.fromEnvironment(
    'RAVEL_RELAY_URL',
    defaultValue: 'https://remote.tentrem.space',
  );
  static const defaultRelayId = 'relay-default';
  static const _lastKey = 'ravel.remote.hub.last';
  static String _viewerKey(String id) => 'ravel.remote.hub.$id.viewer';
  static String _ownerKey(String id) => 'ravel.remote.hub.$id.owner';

  /// Token key of the single-hub build (by Kantor origin), migrated once.
  static String legacyViewerKey(String url) => 'ravel.remote.viewer.$url';

  /// `http(s)://host[:port]` → origin; null otherwise.
  static String? parseUrl(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
    if (u.host.isEmpty) return null;
    return u.origin;
  }

  static String newId() {
    final r = math.Random.secure();
    return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Hubs in list order. The current Kantor ([kantorUrl]) is added as the
  /// first hub when the list has none of kind kantor at that address.
  Future<List<RemoteHub>> hubs({String? kantorUrl}) async {
    final p = await _prefs;
    final raw = p.getString(_listKey);
    var list = <RemoteHub>[];
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is List) {
          list = j.map(RemoteHub.fromJson).whereType<RemoteHub>().toList();
        }
      } catch (_) {}
    }
    // Seed the built-in relay once (in front); if the owner deletes it, it
    // stays deleted.
    if (!(p.getBool(_seededKey) ?? false)) {
      final relay = parseUrl(defaultRelayUrl);
      if (relay != null && !list.any((h) => h.url == relay)) {
        list = [
          RemoteHub(
            id: defaultRelayId,
            name: 'Relay VPS',
            url: relay,
            kind: RemoteHubKind.relay,
          ),
          ...list,
        ];
      }
      await p.setBool(_seededKey, true);
      await save(list);
    }
    final k = kantorUrl == null ? null : parseUrl(kantorUrl);
    if (k != null &&
        !list.any((h) => h.kind == RemoteHubKind.kantor && h.url == k)) {
      final hub = RemoteHub(
        id: newId(),
        name: 'Kantor',
        url: k,
        kind: RemoteHubKind.kantor,
      );
      // after the relays (VPS first, then Kantor/Tailscale)
      final at = list.lastIndexWhere((h) => h.kind == RemoteHubKind.relay) + 1;
      list = [...list.sublist(0, at), hub, ...list.sublist(at)];
      await save(list);
      // single-hub build stored the viewer token by Kantor origin
      final legacy = await _secrets.read(legacyViewerKey(k));
      if (legacy != null && legacy.startsWith('kcview_')) {
        await _secrets.write(_viewerKey(hub.id), legacy);
        await _secrets.delete(legacyViewerKey(k));
      }
    }
    return list;
  }

  Future<void> save(List<RemoteHub> hubs) async => (await _prefs).setString(
    _listKey,
    jsonEncode([for (final h in hubs) h.toJson()]),
  );

  Future<void> upsert(RemoteHub hub) async {
    final list = await hubs();
    final i = list.indexWhere((h) => h.id == hub.id);
    if (i < 0) {
      list.add(hub);
    } else {
      list[i] = hub;
    }
    await save(list);
  }

  Future<void> remove(String id) async {
    await save((await hubs()).where((h) => h.id != id).toList());
    await _secrets.delete(_viewerKey(id));
    await _secrets.delete(_ownerKey(id));
  }

  Future<String?> viewerToken(String id) async {
    final v = await _secrets.read(_viewerKey(id));
    return v != null && v.startsWith('kcview_') ? v : null;
  }

  Future<void> setViewerToken(String id, String? token) => token == null
      ? _secrets.delete(_viewerKey(id))
      : _secrets.write(_viewerKey(id), token);

  Future<String?> ownerToken(String id) => _secrets.read(_ownerKey(id));

  Future<void> setOwnerToken(String id, String? token) => token == null
      ? _secrets.delete(_ownerKey(id))
      : _secrets.write(_ownerKey(id), token.trim());

  Future<String?> lastWorking() async => (await _prefs).getString(_lastKey);

  Future<void> rememberWorking(String id) async =>
      (await _prefs).setString(_lastKey, id);

  /// Try order: last hub that worked, then list order.
  static List<RemoteHub> tryOrder(List<RemoteHub> hubs, String? lastId) {
    final out = [...hubs];
    final i = out.indexWhere((h) => h.id == lastId);
    if (i > 0) out.insert(0, out.removeAt(i));
    return out;
  }
}

/// A paired hub: the hub plus a client speaking with its viewer token.
class RemoteHubConn {
  RemoteHubConn(this.hub, String token)
    : api = KantorApi(KantorConfig(baseUrl: hub.url, token: token));
  final RemoteHub hub;
  final KantorApi api;
}

/// Thrown when no hub could be used.
class RemoteHubsFailed implements Exception {
  const RemoteHubsFailed(this.message, {this.needPairing = const []});
  final String message;

  /// Hubs that refused this device's token (401/403).
  final List<RemoteHub> needPairing;
  @override
  String toString() => message;
}

/// Failover over paired hubs. Tries the hubs in the given order (already
/// "last working first, then list order"); a hub that is unreachable is
/// skipped, a hub that refuses the token is reported through [onUnauthorized]
/// (→ "needs pairing") and skipped too.
class RemoteHubClient {
  RemoteHubClient(this.conns, {this.onWorking, this.onUnauthorized}) {
    if (conns.isEmpty) throw ArgumentError('no paired hub');
  }

  final List<RemoteHubConn> conns;
  final void Function(RemoteHub hub)? onWorking;
  final void Function(RemoteHub hub)? onUnauthorized;

  int _current = 0;
  RemoteHubConn get current => conns[_current];

  /// Narrowed to the hubs in [ids] (e.g. where a Mac was seen), keeping
  /// the order and callbacks. Falls back to all hubs if none match.
  RemoteHubClient only(Iterable<String> ids) {
    final keep = conns.where((c) => ids.contains(c.hub.id)).toList();
    return RemoteHubClient(
      keep.isEmpty ? conns : keep,
      onWorking: onWorking,
      onUnauthorized: onUnauthorized,
    );
  }

  Future<T> run<T>(Future<T> Function(KantorApi api) call) async {
    final refused = <RemoteHub>[];
    Object? last;
    for (var i = 0; i < conns.length; i++) {
      final idx = (_current + i) % conns.length;
      final c = conns[idx];
      try {
        final r = await call(c.api);
        _use(idx);
        return r;
      } on KantorException catch (e) {
        if (e.kind == KantorFailure.unauthorized) {
          refused.add(c.hub);
          onUnauthorized?.call(c.hub);
        } else if (e.kind != KantorFailure.unreachable) {
          rethrow;
        }
        last = e;
      }
    }
    if (refused.length == conns.length) {
      throw RemoteHubsFailed(
        'Perangkat ini perlu dipasangkan ulang di hub.',
        needPairing: refused,
      );
    }
    throw last is KantorException
        ? last
        : const KantorException(
            KantorFailure.unreachable,
            'Tidak ada hub yang terjangkau.',
          );
  }

  /// Opens a WebSocket on the first hub that accepts it.
  Future<WebSocket> connectWs(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final refused = <RemoteHub>[];
    Object? last;
    for (var i = 0; i < conns.length; i++) {
      final idx = (_current + i) % conns.length;
      final c = conns[idx];
      try {
        final ws = await c.api.connectWs(path, query: query).timeout(timeout);
        _use(idx);
        return ws;
      } catch (e) {
        if (isAuthRefusal(e)) {
          refused.add(c.hub);
          onUnauthorized?.call(c.hub);
        }
        last = e;
      }
    }
    if (refused.length == conns.length) {
      throw RemoteHubsFailed(
        'Token perangkat ditolak di semua hub. Pasangkan ulang.',
        needPairing: refused,
      );
    }
    throw last ?? StateError('no hub');
  }

  /// A refused WebSocket upgrade (dart:io reports the HTTP status).
  static bool isAuthRefusal(Object e) =>
      e is WebSocketException && RegExp(r'\b(401|403)\b').hasMatch(e.message);

  void _use(int idx) {
    _current = idx;
    onWorking?.call(conns[idx].hub);
  }
}

/// A Mac seen on one or more hubs. Machine ids are per hub; the same Mac on
/// two hubs is merged when the id matches.
class RemoteHostEntry {
  RemoteHostEntry(this.host, this.hubIds);
  final RemoteHost host;
  final List<String> hubIds;
}

/// Merges host lists of several hubs (hub order kept): online wins, the
/// first hub that has the Mac online gives the details.
List<RemoteHostEntry> mergeHosts(List<(RemoteHub, List<RemoteHost>)> perHub) {
  final byMachine = <String, RemoteHostEntry>{};
  for (final (hub, hosts) in perHub) {
    for (final h in hosts) {
      final e = byMachine[h.machine];
      if (e == null) {
        byMachine[h.machine] = RemoteHostEntry(h, [hub.id]);
        continue;
      }
      e.hubIds.add(hub.id);
      if (h.online && !e.host.online) {
        byMachine[h.machine] = RemoteHostEntry(h, e.hubIds);
      }
    }
  }
  final out = byMachine.values.toList()
    ..sort((a, b) {
      if (a.host.online != b.host.online) return a.host.online ? -1 : 1;
      return a.host.name.toLowerCase().compareTo(b.host.name.toLowerCase());
    });
  // online hubs for a Mac first, so a session tries them first
  for (final e in out) {
    final online = <String>[];
    for (final (hub, hosts) in perHub) {
      if (hosts.any((h) => h.machine == e.host.machine && h.online)) {
        online.add(hub.id);
      }
    }
    e.hubIds.sort((a, b) {
      final ao = online.contains(a) ? 0 : 1;
      final bo = online.contains(b) ? 0 : 1;
      return ao - bo;
    });
  }
  return out;
}
