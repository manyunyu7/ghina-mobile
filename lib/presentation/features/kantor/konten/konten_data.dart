import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import 'konten_model.dart';

/// Pintu ke API Konten. Dipisah dari [KantorApi] supaya tes bisa memakai data
/// palsu. Server lama (404) dibalas sebagai keadaan kosong, bukan galat.
abstract class KontenRepo {
  /// Alamat mutlak untuk `url`/`thumb` dari server (jalur relatif atau mutlak).
  Uri uri(String url);
  Map<String, String> get headers;

  /// Tautan web untuk sub-tampilan yang tidak ada di HP (kit, grid).
  Uri webUrl(String office, String sub);

  Future<KontenList> list(String office);
  Future<KontenItem> get(String office, String id);
  Future<KontenJadwal> jadwal(String office);
  Future<void> review(
    String office,
    String id, {
    required bool setuju,
    String? catatan,
  });
  Future<void> setujuiJadwal(String office, List<String> ids);

  /// [publishAt] null = kosongkan tanggal.
  Future<void> setTanggal(
    String office,
    String id, {
    String? publishAt,
    String? jam,
  });

  /// Mengembalikan daftar berkas yang masih menyebut path lama.
  Future<List<String>> tayang(
    String office,
    String id,
    String platform, {
    String? link,
  });
  Future<void> performa(
    String office,
    String id,
    String platform,
    Map<String, int> angka,
  );
}

class ApiKontenRepo implements KontenRepo {
  ApiKontenRepo(this.api);
  final KantorApi api;

  String _b(String office) =>
      '/api/offices/${Uri.encodeComponent(office)}/konten';
  String _i(String office, String id) =>
      '${_b(office)}/${Uri.encodeComponent(id)}';

  @override
  Uri uri(String url) => Uri.parse(api.config.baseUrl).resolve(url);

  @override
  Map<String, String> get headers => api.authHeaders;

  @override
  Uri webUrl(String office, String sub) =>
      Uri.parse(api.config.baseUrl).replace(
        path: '/',
        fragment: '/o/${Uri.encodeComponent(office)}/konten/$sub',
      );

  @override
  Future<KontenList> list(String office) async {
    try {
      return KontenList.fromJson(await api.get(_b(office)));
    } on KantorException catch (e) {
      if (e.kind == KantorFailure.notFound) {
        return const KontenList(unsupported: true);
      }
      rethrow;
    }
  }

  @override
  Future<KontenItem> get(String office, String id) async =>
      KontenItem.fromJson(await api.get(_i(office, id)));

  @override
  Future<KontenJadwal> jadwal(String office) async {
    try {
      return KontenJadwal.fromJson(await api.get('${_b(office)}/jadwal'));
    } on KantorException catch (e) {
      if (e.kind == KantorFailure.notFound) {
        return const KontenJadwal(unsupported: true);
      }
      rethrow;
    }
  }

  @override
  Future<void> review(
    String office,
    String id, {
    required bool setuju,
    String? catatan,
  }) async {
    await api.post('${_i(office, id)}/review', {
      'keputusan': setuju ? 'setuju' : 'revisi',
      if (catatan != null && catatan.trim().isNotEmpty)
        'catatan': catatan.trim(),
    });
  }

  @override
  Future<void> setujuiJadwal(String office, List<String> ids) async {
    await api.post('${_b(office)}/jadwal/setujui', {'ids': ids});
  }

  @override
  Future<void> setTanggal(
    String office,
    String id, {
    String? publishAt,
    String? jam,
  }) async {
    await api.patch(_i(office, id), {
      'publishAt': publishAt ?? '',
      'jam': ?jam,
    });
  }

  @override
  Future<List<String>> tayang(
    String office,
    String id,
    String platform, {
    String? link,
  }) async {
    final r = await api.post('${_i(office, id)}/tayang', {
      'platform': platform,
      if (link != null && link.trim().isNotEmpty) 'link': link.trim(),
    });
    final cek = r is Map ? r['pathPerluCek'] : null;
    return [
      if (cek is List)
        for (final c in cek) '$c',
    ];
  }

  @override
  Future<void> performa(
    String office,
    String id,
    String platform,
    Map<String, int> angka,
  ) async {
    await api.post('${_i(office, id)}/performa', {
      'platform': platform,
      ...angka,
    });
  }
}

final kontenRepoProvider = Provider<KontenRepo?>((ref) {
  final api = ref.watch(kantorApiProvider);
  return api == null ? null : ApiKontenRepo(api);
});

KontenRepo _need(Ref ref) {
  final repo = ref.watch(kontenRepoProvider);
  if (repo == null) {
    throw const KantorException(
      KantorFailure.unauthorized,
      'Token Kantor belum diisi.',
    );
  }
  return repo;
}

/// Segarkan saat daemon memancarkan `{t:'changed', what:'konten'}`.
void _refetchOnKonten(Ref ref, String office) {
  Timer? debounce;
  ref.onDispose(() => debounce?.cancel());
  ref.listen(kantorEventsProvider, (_, next) {
    final e = next.value;
    if (e == null || e['t'] != 'changed' || e['what'] != 'konten') return;
    if (e['office'] != office && e['office'] != '*') return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), ref.invalidateSelf);
  });
}

final kontenListProvider = FutureProvider.autoDispose
    .family<KontenList, String>((ref, office) async {
      final repo = _need(ref);
      _refetchOnKonten(ref, office);
      return repo.list(office);
    });

final kontenJadwalProvider = FutureProvider.autoDispose
    .family<KontenJadwal, String>((ref, office) async {
      final repo = _need(ref);
      _refetchOnKonten(ref, office);
      return repo.jadwal(office);
    });

final kontenItemProvider = FutureProvider.autoDispose
    .family<KontenItem, (String, String)>((ref, key) async {
      final repo = _need(ref);
      _refetchOnKonten(ref, key.$1);
      return repo.get(key.$1, key.$2);
    });
