import 'package:flutter/services.dart';

/// Android owns the queue and notifications, so downloads do not depend on
/// Dart timers, the current complex, or a living Flutter engine.
class KantorDownloads {
  const KantorDownloads();
  static const channel = MethodChannel('kantor/downloads');
  static const instance = KantorDownloads();

  Future<int> enqueue({
    required Uri url,
    required String name,
    required String mime,
    required String description,
  }) async {
    if (!['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !url.path.startsWith('/pv/')) {
      throw const FormatException('Alamat berkas pratinjau tidak valid.');
    }
    return (await channel.invokeMethod<int>('enqueue', {
      'url': url.toString(),
      'name': name,
      'mime': mime,
      'description': description,
    }))!;
  }

  Future<List<KantorDownload>> list() async => [
    for (final row in await channel.invokeListMethod<Object?>('list') ?? [])
      KantorDownload.fromMap((row as Map).cast<String, dynamic>()),
  ];

  Future<void> action(String action, int id) async {
    if (!['cancel', 'retry', 'open', 'share'].contains(action)) {
      throw ArgumentError.value(action);
    }
    await channel.invokeMethod<Object?>(action, {'id': id});
  }
}

class KantorDownload {
  const KantorDownload({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.status,
    required this.received,
    required this.total,
    required this.reason,
  });
  factory KantorDownload.fromMap(Map<String, dynamic> m) => KantorDownload(
    id: (m['id'] as num).toInt(),
    name: m['name'] as String,
    description: m['description'] as String? ?? '',
    location: m['location'] as String? ?? '',
    status: m['status'] as String,
    received: (m['received'] as num? ?? 0).toInt(),
    total: (m['total'] as num? ?? -1).toInt(),
    reason: (m['reason'] as num? ?? 0).toInt(),
  );
  final int id, received, total, reason;
  final String name, description, location, status;
  bool get active => ['queued', 'running', 'waiting'].contains(status);
  bool get complete => status == 'complete';
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
  String get label => switch (status) {
    'queued' => 'Dalam antrean',
    'running' => 'Mengunduh',
    'waiting' => switch (reason) {
      3 => 'Menunggu Wi-Fi',
      2 => 'Menunggu koneksi',
      _ => 'Menunggu untuk melanjutkan',
    },
    'complete' => 'Selesai',
    'cancelled' => 'Dibatalkan',
    'missing' => 'Berkas tidak tersedia',
    _ => switch (reason) {
      401 || 403 => 'Akses berakhir. Buka ulang pratinjau.',
      404 || 410 => 'Berkas tidak lagi tersedia di server.',
      1006 => 'Ruang penyimpanan tidak cukup.',
      1007 => 'Penyimpanan tidak tersedia.',
      _ => 'Unduhan gagal. Periksa koneksi lalu coba lagi.',
    },
  };
}

String downloadBytes(int bytes) {
  if (bytes < 0) return 'Ukuran belum diketahui';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
