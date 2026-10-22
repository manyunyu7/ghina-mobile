import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../di/di.dart';
import 'attachment_model.dart';

/// Downloads an attachment's raw bytes to the cache (streamed, with the
/// bearer header) and returns the file. A finished earlier download of the
/// same size is reused.
Future<File> downloadAttachment(
  KantorApi api,
  KantorAttachment a, {
  void Function(int got, int total)? onProgress,
  CancelToken? cancel,
}) async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'kantor_dl', _safe(a.id)),
  );
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, _safe(a.name)));
  if (await file.exists() && a.size > 0 && await file.length() == a.size) {
    return file;
  }
  final part = File('${file.path}.part');
  await Dio().download(
    api.url(a.rawPath).toString(),
    part.path,
    options: Options(headers: api.authHeaders),
    cancelToken: cancel,
    onReceiveProgress: onProgress,
  );
  return part.rename(file.path);
}

String _safe(String s) {
  final t = s.replaceAll(RegExp(r'[^\w.\- ]'), '_');
  return t.isEmpty ? 'file' : t;
}

Future<void> shareAttachmentFile(File f, KantorAttachment a) =>
    SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(f.path, name: a.name, mimeType: a.mime.isEmpty ? null : a.mime),
        ],
      ),
    );

/// Saves an image or video into the phone gallery. Returns false when the
/// gallery permission was refused.
Future<bool> saveToGallery(File f, KantorAttachment a) async {
  if (!await Gal.hasAccess()) {
    if (!await Gal.requestAccess()) return false;
  }
  if (a.kind == AttachmentKind.video) {
    await Gal.putVideo(f.path);
  } else {
    await Gal.putImage(f.path);
  }
  return true;
}
