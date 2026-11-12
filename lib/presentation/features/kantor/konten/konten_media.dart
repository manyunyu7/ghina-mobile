import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'konten_data.dart';
import 'konten_model.dart';

/// Unduh, simpan ke galeri, dan bagikan berkas paket posting. Dipisah supaya
/// tes tidak menyentuh jaringan atau galeri.
abstract class KontenMedia {
  /// Unduh [files] ke folder sementara (dengan auth), kembalikan path lokal
  /// berurutan. Berkas yang sudah ada dengan ukuran sama dipakai ulang.
  Future<List<String>> fetchAll(
    KontenRepo repo,
    String cid,
    List<KontenFile> files, {
    void Function(int done, int total)? onProgress,
  });

  /// Simpan ke galeri. False bila izin galeri ditolak.
  Future<bool> saveToGallery(List<String> paths);

  Future<void> share(List<String> paths, {String? text});
}

class DeviceKontenMedia implements KontenMedia {
  const DeviceKontenMedia();

  static const _videoExt = {'.mp4', '.mov', '.m4v', '.webm', '.mkv'};
  static bool _isVideo(String path) =>
      _videoExt.contains(p.extension(path).toLowerCase());

  static String _safe(String s) {
    final t = s.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    return t.isEmpty ? 'file' : t;
  }

  @override
  Future<List<String>> fetchAll(
    KontenRepo repo,
    String cid,
    List<KontenFile> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'konten_dl', _safe(cid)),
    );
    await dir.create(recursive: true);
    final out = <String>[];
    final dio = Dio();
    for (var i = 0; i < files.length; i++) {
      onProgress?.call(i, files.length);
      final f = files[i];
      // Awalan nomor menjaga urutan slide walau namanya kembar.
      final name = '${(i + 1).toString().padLeft(2, '0')}_${_safe(f.name)}';
      final file = File(p.join(dir.path, name));
      if (!(await file.exists() &&
          f.size > 0 &&
          await file.length() == f.size)) {
        final part = File('${file.path}.part');
        await dio.download(
          repo.uri(f.url).toString(),
          part.path,
          options: Options(headers: repo.headers),
        );
        await part.rename(file.path);
      }
      out.add(file.path);
    }
    onProgress?.call(files.length, files.length);
    return out;
  }

  @override
  Future<bool> saveToGallery(List<String> paths) async {
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) return false;
    }
    for (final path in paths) {
      if (_isVideo(path)) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
    }
    return true;
  }

  @override
  Future<void> share(List<String> paths, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(files: [for (final x in paths) XFile(x)], text: text),
    );
  }
}

final kontenMediaProvider = Provider<KontenMedia>(
  (ref) => const DeviceKontenMedia(),
);
