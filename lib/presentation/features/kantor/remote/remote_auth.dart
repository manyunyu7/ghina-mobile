import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../data/datasources/remote/kantor_api.dart';

/// Ravel Remote needs a per-device viewer token (`kcview_…`): the owner token
/// alone is refused on `/api/remote/ws` and `/api/remote/hosts`. The app gets
/// one by pairing (kantor-claude `server/remote-api.js`):
///
/// 1. `POST /api/remote/pair {device}` with the owner token → `{id, claim,
///    expiresAt, hostsNotified}`; every online Mac shows a 6-digit code;
/// 2. `POST /api/remote/pair/<id>/approve {code, claim}` (owner) → `{token}`,
///    or another paired device approves and we fetch the token once with
///    `GET /api/remote/pair/<id>?claim=` (owner).
class RemotePairRequest {
  const RemotePairRequest({
    required this.id,
    required this.claim,
    required this.device,
    required this.expiresAt,
    required this.hostsNotified,
  });

  final String id;
  final String claim;
  final String device;
  final DateTime expiresAt;
  final int hostsNotified;

  static RemotePairRequest fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['claim'] is! String) {
      throw const KantorException(
        KantorFailure.server,
        'Jawaban pairing dari Kantor tidak dikenal.',
      );
    }
    final notified = raw['hostsNotified'];
    return RemotePairRequest(
      id: raw['id'] as String,
      claim: raw['claim'] as String,
      device: raw['device']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(raw['expiresAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 5)),
      hostsNotified: notified is num
          ? notified.toInt()
          : (notified is List ? notified.length : 0),
    );
  }
}

/// A device that may open remote sessions.
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.device,
    this.lastUsed,
    this.via,
    this.current = false,
  });

  final String id;
  final String device;
  final DateTime? lastUsed;
  final String? via;
  final bool current;

  static RemoteDevice? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return RemoteDevice(
      id: raw['id'] as String,
      device: raw['device']?.toString() ?? 'Perangkat',
      lastUsed: DateTime.tryParse(raw['lastUsed']?.toString() ?? '')?.toLocal(),
      via: raw['via']?.toString(),
      current: raw['current'] == true,
    );
  }
}

/// Another device waiting to be approved.
class RemotePendingPair {
  const RemotePendingPair({required this.id, required this.device, this.ip});

  final String id;
  final String device;
  final String? ip;

  static RemotePendingPair? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return RemotePendingPair(
      id: raw['id'] as String,
      device: raw['device']?.toString() ?? 'Perangkat',
      ip: raw['ip']?.toString(),
    );
  }
}

/// Viewer token storage, one per Kantor address.
class RemoteDeviceStore {
  RemoteDeviceStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String keyFor(String baseUrl) =>
      'ravel.remote.viewer.${Uri.tryParse(baseUrl.trim())?.origin ?? baseUrl.trim()}';

  Future<String?> read(String baseUrl) async {
    final v = await _storage.read(key: keyFor(baseUrl));
    return v != null && v.startsWith('kcview_') ? v : null;
  }

  Future<void> write(String baseUrl, String token) =>
      _storage.write(key: keyFor(baseUrl), value: token);

  Future<void> clear(String baseUrl) => _storage.delete(key: keyFor(baseUrl));
}

/// Calls for pairing and device management.
abstract final class RemoteAuth {
  /// Client that speaks as this device (viewer token) to the same Kantor.
  static KantorApi viewerApi(KantorApi owner, String token) =>
      KantorApi(KantorConfig(baseUrl: owner.config.baseUrl, token: token));

  static Future<RemotePairRequest> requestPair(
    KantorApi owner,
    String device,
  ) async => RemotePairRequest.fromJson(
    await owner.post('/api/remote/pair', {'device': device}),
  );

  /// Approves with the Mac's code; returns the viewer token.
  static Future<String> approveWithCode(
    KantorApi owner,
    RemotePairRequest req,
    String code,
  ) async {
    final r = await owner.post('/api/remote/pair/${req.id}/approve', {
      'code': code.trim(),
      'claim': req.claim,
    });
    final token = r is Map ? r['token'] : null;
    if (token is! String || token.isEmpty) {
      throw const KantorException(
        KantorFailure.server,
        'Kantor tidak mengembalikan token perangkat.',
      );
    }
    return token;
  }

  /// Polls a request approved from another device. Returns the token once
  /// approved, null while pending; throws when expired.
  static Future<String?> claim(KantorApi owner, RemotePairRequest req) async {
    final r = await owner.get(
      '/api/remote/pair/${req.id}',
      query: {'claim': req.claim},
    );
    if (r is! Map) return null;
    switch (r['status']) {
      case 'approved':
        final t = r['token'];
        return t is String && t.isNotEmpty ? t : null;
      case 'expired':
        throw const KantorException(
          KantorFailure.notFound,
          'Permintaan pairing kedaluwarsa. Minta ulang.',
        );
      default:
        return null;
    }
  }

  static Future<List<RemoteDevice>> devices(KantorApi viewer) async {
    final r = await viewer.get('/api/remote/devices');
    return r is List
        ? r.map(RemoteDevice.fromJson).whereType<RemoteDevice>().toList()
        : const [];
  }

  static Future<void> revoke(KantorApi viewer, String id) =>
      viewer.delete('/api/remote/devices/$id');

  static Future<List<RemotePendingPair>> pending(KantorApi viewer) async {
    final r = await viewer.get('/api/remote/pair');
    return r is List
        ? r
              .map(RemotePendingPair.fromJson)
              .whereType<RemotePendingPair>()
              .toList()
        : const [];
  }

  static Future<void> approveOther(KantorApi viewer, String id) =>
      viewer.post('/api/remote/pair/$id/approve');
}
