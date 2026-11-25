import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/remote/kantor_api.dart';

/// Ravel Remote can reach the same Kantor (signaling hub) through several
/// addresses (Tailscale, VPS, Cloudflare…). The primary one is the Kantor
/// address of the app; extra ones are kept per primary address. Calls try
/// the last address that worked first and fall over to the next one when a
/// hub is unreachable.
class RemoteHubList {
  RemoteHubList([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static String originOf(String url) {
    final u = Uri.tryParse(url.trim());
    return u == null || u.origin.isEmpty ? url.trim() : u.origin;
  }

  static String _extraKey(String primary) =>
      'ravel.remote.hubs.${originOf(primary)}';
  static String _lastKey(String primary) =>
      'ravel.remote.hub.last.${originOf(primary)}';

  /// Accepts `http(s)://host[:port]` only; returns the normalized origin.
  static String? parse(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
    if (u.host.isEmpty) return null;
    return u.origin;
  }

  /// Extra hub addresses (without the primary).
  Future<List<String>> extras(String primary) async =>
      (await _prefs).getStringList(_extraKey(primary)) ?? const [];

  Future<void> setExtras(String primary, Iterable<String> urls) async {
    final p = originOf(primary);
    final clean = <String>[];
    for (final u in urls) {
      final o = parse(u);
      if (o != null && o != p && !clean.contains(o)) clean.add(o);
    }
    await (await _prefs).setStringList(_extraKey(primary), clean);
  }

  /// All addresses, the last one that worked first.
  Future<List<String>> ordered(String primary) async {
    final all = <String>[originOf(primary)];
    for (final e in await extras(primary)) {
      if (!all.contains(e)) all.add(e);
    }
    final last = (await _prefs).getString(_lastKey(primary));
    if (last != null && all.remove(last)) all.insert(0, last);
    return all;
  }

  Future<void> remember(String primary, String working) async =>
      (await _prefs).setString(_lastKey(primary), originOf(working));
}

/// A viewer client over a list of hub addresses, all using the same device
/// token. [id] (the primary address) keys per-Kantor data such as pinned
/// fingerprints, so switching hubs does not lose them.
class RemoteHubClient {
  RemoteHubClient({
    required this.id,
    required List<String> urls,
    required this.token,
    this.onWorking,
  }) : apis = [
         for (final u in urls)
           KantorApi(KantorConfig(baseUrl: u, token: token)),
       ] {
    if (apis.isEmpty) throw ArgumentError('no hub address');
  }

  /// Single-address client (tests, or no extra hubs configured).
  factory RemoteHubClient.single(KantorApi api) => RemoteHubClient(
    id: RemoteHubList.originOf(api.config.baseUrl),
    urls: [api.config.baseUrl],
    token: api.config.token,
  );

  final String id;
  final String token;
  final List<KantorApi> apis;

  /// Called with the address that answered (to try it first next time).
  final void Function(String url)? onWorking;

  int _current = 0;

  KantorApi get current => apis[_current];

  /// Runs [call] on the current hub, then on the others while they are
  /// unreachable. Any other failure (401, 404, …) is returned as is.
  Future<T> run<T>(Future<T> Function(KantorApi api) call) async {
    KantorException? last;
    for (var i = 0; i < apis.length; i++) {
      final idx = (_current + i) % apis.length;
      try {
        final r = await call(apis[idx]);
        _use(idx);
        return r;
      } on KantorException catch (e) {
        if (e.kind != KantorFailure.unreachable) rethrow;
        last = e;
      }
    }
    throw last!;
  }

  /// Opens the remote WebSocket on the first hub that accepts it.
  Future<WebSocket> connectWs(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    Object? last;
    for (var i = 0; i < apis.length; i++) {
      final idx = (_current + i) % apis.length;
      try {
        final ws = await apis[idx]
            .connectWs(path, query: query)
            .timeout(timeout);
        _use(idx);
        return ws;
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('no hub address');
  }

  void _use(int idx) {
    if (idx == _current) return;
    _current = idx;
    onWorking?.call(apis[idx].config.baseUrl);
  }
}
