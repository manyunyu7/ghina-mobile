import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// File explorer data: the office folder tree, sandboxed by the daemon.

final class KantorFileEntry {
  const KantorFileEntry({
    required this.name,
    required this.path,
    required this.dir,
    this.size,
    this.mtime,
  });

  factory KantorFileEntry.fromJson(Map<String, dynamic> j) => KantorFileEntry(
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    dir: j['dir'] == true,
    size: (j['size'] as num?)?.toInt(),
    mtime: j['mtime'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['mtime'] as num).toInt())
        : null,
  );

  final String name;
  final String path;
  final bool dir;
  final int? size;
  final DateTime? mtime;

  bool get isImage => RegExp(
    r'\.(png|jpe?g|gif|webp|svg)$',
    caseSensitive: false,
  ).hasMatch(name);
}

final class KantorFolder {
  const KantorFolder({
    required this.path,
    required this.root,
    required this.entries,
    required this.hidden,
  });

  factory KantorFolder.fromJson(Map<String, dynamic> j) => KantorFolder(
    path: j['path'] as String? ?? '',
    root: j['root'] as String? ?? '',
    entries: [
      for (final e in (j['entries'] as List?) ?? const [])
        if (e is Map) KantorFileEntry.fromJson(e.cast<String, dynamic>()),
    ],
    hidden: (j['hidden'] as num?)?.toInt() ?? 0,
  );

  final String path;
  final String root;
  final List<KantorFileEntry> entries;
  final int hidden;
}

/// A file opened for viewing. [kind]: text, image, video, audio, pdf, binary.
final class KantorFileInfo {
  const KantorFileInfo({
    required this.path,
    required this.size,
    required this.kind,
    required this.ext,
    this.text = '',
    this.truncated = false,
    this.mtime,
  });

  factory KantorFileInfo.fromJson(Map<String, dynamic> j) => KantorFileInfo(
    path: j['path'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
    kind: j['kind'] as String? ?? 'binary',
    ext: j['ext'] as String? ?? '',
    text: j['text'] as String? ?? '',
    truncated: j['truncated'] == true,
    mtime: j['mtime'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['mtime'] as num).toInt())
        : null,
  );

  final String path;
  final int size;
  final String kind;
  final String ext;
  final String text;
  final bool truncated;
  final DateTime? mtime;

  String get name => path.split('/').last;
}

String kantorFileSize(int? n) {
  if (n == null) return '';
  if (n < 1024) return '$n B';
  if (n < 1048576) return '${(n / 1024).toStringAsFixed(n < 10240 ? 1 : 0)} KB';
  return '${(n / 1048576).toStringAsFixed(1)} MB';
}

/// `files` endpoint path for an office.
String kantorFilesBase(String officeId) =>
    '/api/offices/${Uri.encodeComponent(officeId)}/files';

/// Folder listing keyed by (office, folder, show hidden).
final kantorFolderProvider = FutureProvider.autoDispose
    .family<KantorFolder, ({String office, String path, bool all})>((
      ref,
      k,
    ) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw const KantorException(
          KantorFailure.unauthorized,
          'Belum ada token',
        );
      final j = await api.get(
        kantorFilesBase(k.office),
        query: {'path': k.path, 'all': k.all ? '1' : '0'},
      );
      return KantorFolder.fromJson((j as Map).cast<String, dynamic>());
    });
