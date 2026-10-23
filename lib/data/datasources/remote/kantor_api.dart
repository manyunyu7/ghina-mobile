import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/kantor_pratinjau.dart';

/// Kantor Claude: the office daemon for Claude Code sessions, running on the
/// owner's own computer and reachable only over their private network
/// (Tailscale). Online-only, not in sync. The JSON contract is the daemon's
/// own (`docs/FRONTEND-CONTRACT.md` in the kantor-claude repo); screens read
/// the maps as they come.

/// Where the office is and how to get in.
final class KantorConfig {
  const KantorConfig({required this.baseUrl, required this.token});

  static const defaultUrl = 'https://office.tentrem.space';

  final String baseUrl;
  final String token;

  bool get ready => baseUrl.isNotEmpty && token.isNotEmpty;
}

/// A named connection. Credentials stay in Keychain / Keystore.
final class KantorComplexProfile {
  const KantorComplexProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.token,
  });
  final String id;
  final String name;
  final String baseUrl;
  final String token;
  KantorConfig get config => KantorConfig(baseUrl: baseUrl, token: token);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'token': token,
  };
  factory KantorComplexProfile.fromJson(Map<String, dynamic> json) =>
      KantorComplexProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        token: json['token'] as String,
      );
}

/// All connections and the active ID live in one secure record, so switching
/// cannot leave a URL paired with another connection's token.
final class KantorConfigStore {
  KantorConfigStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _urlKey = 'kantor.url';
  static const _tokenKey = 'kantor.token';
  static const _profilesKey = 'kantor.complexes.v1';
  static const _previousProfilesKey = 'kantor.profiles';
  final FlutterSecureStorage _storage;
  Future<void> _pending = Future.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<({List<KantorComplexProfile> profiles, String? activeId})>
  _read() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        profiles: (json['profiles'] as List)
            .map(
              (e) => KantorComplexProfile.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        activeId: json['activeId'] as String?,
      );
    }
    // The earlier multi-profile build removed the single URL/token keys.
    // Import its secure record before attempting the oldest single connection.
    final previous = await _storage.read(key: _previousProfilesKey);
    if (previous != null) {
      try {
        final decoded = jsonDecode(previous);
        if (decoded is Map && decoded['items'] is List) {
          final profiles = <KantorComplexProfile>[];
          for (final item in decoded['items'] as List) {
            if (item is! Map || item['id'] is! String) continue;
            final id = item['id'] as String;
            if (id.isEmpty || profiles.any((p) => p.id == id)) continue;
            String field(String key) =>
                item[key] is String ? item[key] as String : '';
            final name = field('name');
            profiles.add(
              KantorComplexProfile(
                id: id,
                name: name.isNotEmpty
                    ? name
                    : (id == 'default' ? 'Default' : id),
                baseUrl: field('baseUrl'),
                token: field('token'),
              ),
            );
          }
          if (profiles.isNotEmpty) {
            final requested = decoded['active'];
            final activeId =
                requested is String && profiles.any((p) => p.id == requested)
                ? requested
                : profiles.where((p) => p.id == 'default').firstOrNull?.id ??
                      profiles.first.id;
            // Keep the previous record untouched so a failed write is retryable.
            await _write(profiles, activeId);
            return (profiles: profiles, activeId: activeId);
          }
        }
      } on FormatException {
        // A malformed previous envelope may still have a valid single config.
      }
    }
    final url = await _storage.read(key: _urlKey) ?? KantorConfig.defaultUrl;
    final token = await _storage.read(key: _tokenKey) ?? '';
    if (token.isEmpty) {
      return (profiles: <KantorComplexProfile>[], activeId: null);
    }
    final profile = KantorComplexProfile(
      id: 'legacy',
      name: _nameFor(url),
      baseUrl: url,
      token: token,
    );
    await _write([profile], profile.id);
    return (profiles: [profile], activeId: profile.id);
  }

  static String _nameFor(String url) => Uri.tryParse(url)?.host ?? 'Kompleks';

  Future<void> _write(
    List<KantorComplexProfile> profiles,
    String? activeId,
  ) async {
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode({
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'activeId': activeId,
      }),
    );
  }

  Future<List<KantorComplexProfile>> loadProfiles() =>
      _locked(() async => (await _read()).profiles);
  Future<String?> loadActiveId() =>
      _locked(() async => (await _read()).activeId);
  Future<KantorConfig> load() => _locked(() async {
    final saved = await _read();
    for (final profile in saved.profiles) {
      if (profile.id == saved.activeId) return profile.config;
    }
    return const KantorConfig(baseUrl: KantorConfig.defaultUrl, token: '');
  });

  Future<void> upsert(KantorComplexProfile profile, {bool activate = false}) =>
      _locked(() => _upsert(profile, activate: activate));

  Future<void> _upsert(
    KantorComplexProfile profile, {
    bool activate = false,
  }) async {
    final saved = await _read();
    final profiles = [...saved.profiles];
    final index = profiles.indexWhere((e) => e.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _write(profiles, activate ? profile.id : saved.activeId);
  }

  Future<void> activate(String id) => _locked(() async {
    final saved = await _read();
    if (!saved.profiles.any((e) => e.id == id)) {
      throw const KantorException(
        KantorFailure.notFound,
        'Kompleks tidak ditemukan.',
      );
    }
    await _write(saved.profiles, id);
  });

  Future<void> remove(String id) => _locked(() async {
    final saved = await _read();
    if (saved.activeId == id) {
      throw const KantorException(
        KantorFailure.server,
        'Pindah ke kompleks lain sebelum menghapus koneksi aktif.',
      );
    }
    await _write(
      saved.profiles.where((e) => e.id != id).toList(),
      saved.activeId,
    );
  });

  Future<void> save(KantorConfig config, {String? name, String? profileId}) =>
      _locked(() async {
        final saved = await _read();
        KantorComplexProfile? previous;
        for (final p in saved.profiles) {
          if (p.id == (profileId ?? saved.activeId)) previous = p;
        }
        await _upsert(
          KantorComplexProfile(
            id:
                profileId ??
                previous?.id ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            name: name?.trim().isNotEmpty == true
                ? name!.trim()
                : previous?.name ?? _nameFor(config.baseUrl),
            baseUrl: config.baseUrl.trim(),
            token: config.token.trim(),
          ),
          activate: true,
        );
      });
}

enum KantorFailure {
  /// No route to the office: the private network is off or the computer sleeps.
  unreachable,

  /// Wrong or missing token.
  unauthorized,
  notFound,

  /// The daemon refused the request; [KantorException.message] says why.
  server,
}

final class KantorException implements Exception {
  const KantorException(this.kind, this.message);
  final KantorFailure kind;
  final String message;

  @override
  String toString() => message;
}

/// Raw JSON client. Paths are the daemon's own (`/api/state`,
/// `/api/offices/<id>/board`, …). Every call throws a [KantorException].
final class KantorApi {
  KantorApi(this.config)
    : _dio = Dio(
        BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Authorization': 'Bearer ${config.token}'},
        ),
      );

  final KantorConfig config;
  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _call(() => _dio.get<dynamic>(path, queryParameters: query));
  Future<dynamic> post(String path, [Object? body]) =>
      _call(() => _dio.post<dynamic>(path, data: body ?? const {}));
  Future<dynamic> patch(String path, [Object? body]) =>
      _call(() => _dio.patch<dynamic>(path, data: body ?? const {}));
  Future<dynamic> put(String path, [Object? body]) =>
      _call(() => _dio.put<dynamic>(path, data: body ?? const {}));
  Future<dynamic> delete(String path) =>
      _call(() => _dio.delete<dynamic>(path));

  /// Raw bytes (media, uploaded files, music).
  Future<List<int>> bytes(String path, {Map<String, dynamic>? query}) async {
    final r = await _call(
      () => _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return (r as List<int>?) ?? const [];
  }

  /// Headers for `Image.network` and friends.
  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer ${config.token}',
  };

  /// Absolute URL for a daemon path, for images and downloads.
  Uri url(String path, [Map<String, String>? query]) =>
      Uri.parse(config.baseUrl).replace(path: path, queryParameters: query);

  /// `ws(s)://…/<path>` with the token as a header (the daemon accepts it on
  /// upgrades). Terminals: `/ws/term?kind=session&sid=…&cols=…&rows=…`.
  Future<WebSocket> connectWs(String path, {Map<String, String>? query}) {
    final base = Uri.parse(config.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      queryParameters: query,
    );
    return WebSocket.connect(uri.toString(), headers: authHeaders);
  }

  /// Live office events from `/ws` (`{t: 'session' | 'changed' | 'inbox' | …}`),
  /// reconnecting with backoff for as long as someone listens.
  Stream<Map<String, dynamic>> events() {
    late final StreamController<Map<String, dynamic>> out;
    WebSocket? socket;
    var open = true;
    Future<void> loop() async {
      var wait = const Duration(seconds: 1);
      while (open) {
        try {
          socket = await connectWs('/ws');
          if (!open) {
            await socket!.close();
            break;
          }
          wait = const Duration(seconds: 1);
          await for (final raw in socket!) {
            if (raw is! String) continue;
            final msg = jsonDecode(raw);
            if (msg is Map<String, dynamic>) out.add(msg);
          }
        } catch (_) {
          // unreachable or dropped: try again below
        }
        if (!open) break;
        await Future<void>.delayed(wait);
        wait = wait * 2 > const Duration(seconds: 30)
            ? const Duration(seconds: 30)
            : wait * 2;
      }
    }

    out = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        open = true;
        loop();
      },
      onCancel: () {
        open = false;
        socket?.close();
      },
    );
    return out.stream;
  }

  Future<dynamic> _call(Future<Response<dynamic>> Function() run) async {
    try {
      return (await run()).data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : null;
      if (status == null) {
        throw const KantorException(
          KantorFailure.unreachable,
          'Kantor tidak terjangkau. Pastikan Tailscale menyala dan komputer kantor tidak tidur.',
        );
      }
      if (status == 401 || status == 403) {
        throw KantorException(
          KantorFailure.unauthorized,
          msg ?? 'Token Kantor salah atau belum diisi.',
        );
      }
      if (status == 404) {
        throw KantorException(
          KantorFailure.notFound,
          msg ?? 'Tidak ditemukan.',
        );
      }
      throw KantorException(
        KantorFailure.server,
        msg ?? 'Kantor menolak ($status).',
      );
    }
  }
}

/// Pratinjau (preview feed): `/api/offices/<id>/pratinjau…`.
extension KantorPratinjauApi on KantorApi {
  String _pv(String office, [String? id]) =>
      '/api/offices/${Uri.encodeComponent(office)}/pratinjau'
      '${id == null ? '' : '/${Uri.encodeComponent(id)}'}';

  static PratinjauItem _item(Object? j) =>
      PratinjauItem.fromJson((j as Map).cast<String, dynamic>());

  /// [status]: `baru` | `perlu` | `semua` | `disimpan` | `arsip`.
  /// [sid] / [role]: only what that session / role sent.
  Future<PratinjauFeed> pratinjauList(
    String office, {
    String status = 'semua',
    int limit = 60,
    String? sid,
    String? role,
  }) async => PratinjauFeed.fromJson(
    ((await get(
              _pv(office),
              query: {
                'status': status,
                'limit': limit,
                if (sid != null && sid.isNotEmpty) 'sid': sid,
                if (role != null && role.isNotEmpty) 'role': role,
              },
            ))
            as Map)
        .cast<String, dynamic>(),
  );

  Future<PratinjauItem> pratinjauGet(String office, String id) async =>
      _item(await get(_pv(office, id)));

  /// Approve everything.
  Future<PratinjauItem> pratinjauSetujui(
    String office,
    String id, {
    String? catatan,
  }) async => _item(
    await post('${_pv(office, id)}/setujui', {
      if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
    }),
  );

  /// Ask for a revision; [catatan] is required by the daemon.
  Future<PratinjauItem> pratinjauRevisi(
    String office,
    String id,
    String catatan,
  ) async =>
      _item(await post('${_pv(office, id)}/revisi', {'catatan': catatan}));

  /// Per-file verdict: [status] `oke` | `revisi`.
  Future<PratinjauItem> pratinjauFile(
    String office,
    String id,
    String fileId, {
    required String status,
    String? catatan,
  }) async => _item(
    await post('${_pv(office, id)}/files/${Uri.encodeComponent(fileId)}', {
      'status': status,
      if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
    }),
  );

  /// Mode `pilihan`: pick one file.
  Future<PratinjauItem> pratinjauPilih(
    String office,
    String id,
    String fileId, {
    String? catatan,
  }) async => _item(
    await post('${_pv(office, id)}/pilih', {
      'file': fileId,
      if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
    }),
  );

  /// Comment; [file] = file id, [t] = video position in seconds.
  Future<PratinjauItem> pratinjauKomentar(
    String office,
    String id,
    String teks, {
    String? file,
    double? t,
  }) async => _item(
    await post('${_pv(office, id)}/komentar', {
      'teks': teks,
      'file': ?file,
      if (t != null) 't': double.parse(t.toStringAsFixed(1)),
    }),
  );

  /// "Sudah lihat".
  Future<PratinjauItem> pratinjauLihat(String office, String id) async =>
      _item(await post('${_pv(office, id)}/lihat', const {}));

  /// Toggles one reaction emoji.
  Future<PratinjauItem> pratinjauReaksi(
    String office,
    String id,
    String emoji,
  ) async => _item(await post('${_pv(office, id)}/reaksi', {'emoji': emoji}));

  /// Pin / archive / snooze. [clearSnooze] sends `snoozedUntil: null`.
  Future<PratinjauItem> pratinjauTanda(
    String office,
    String id, {
    bool? pinned,
    bool? archived,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) async => _item(
    await post('${_pv(office, id)}/tanda', {
      'pinned': ?pinned,
      'archived': ?archived,
      if (snoozedUntil != null)
        'snoozedUntil': snoozedUntil.toUtc().toIso8601String()
      else if (clearSnooze)
        'snoozedUntil': null,
    }),
  );

  /// Disk used by previews.
  Future<PratinjauUsage> pratinjauUsage(String office) async {
    final j = await get('${_pv(office)}/usage');
    final m = j is Map ? j : const {};
    int n(Object? v) => v is num ? v.toInt() : 0;
    return (bytes: n(m['bytes']), items: n(m['items']), files: n(m['files']));
  }

  /// Makes a wiki page from the preview → `(slug, title)`.
  Future<({String slug, String title})> pratinjauWiki(
    String office,
    String id, {
    String? judul,
  }) async {
    final j = await post('${_pv(office, id)}/wiki', {
      if (judul != null && judul.isNotEmpty) 'judul': judul,
    });
    final m = j is Map ? j : const {};
    return (slug: '${m['slug'] ?? ''}', title: '${m['title'] ?? ''}');
  }
}
