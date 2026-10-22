/// Kantor "Pratinjau" (preview feed): work an agent sends to the owner for
/// review — a set of files, a pick-one choice, or an HTML bundle. Shapes follow
/// the daemon's `/api/offices/<id>/pratinjau` JSON. File URLs are signed paths
/// on the Kantor host (`/pv/…`, `/pvt/…`) and need no auth header.
library;

String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
List<Map<String, dynamic>> _maps(Object? v) => [
  for (final e in (v is List ? v : const []))
    if (e is Map) e.cast<String, dynamic>(),
];

/// One file in a preview.
final class PratinjauFile {
  const PratinjauFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    required this.rel,
    required this.url,
    required this.thumb,
    required this.status,
    required this.note,
    this.thumbState,
    this.putar,
    this.putarUrl,
  });

  factory PratinjauFile.fromJson(Map<String, dynamic> j) => PratinjauFile(
    id: _s(j['id']),
    name: _s(j['name']),
    mime: _s(j['mime']),
    size: _i(j['size']),
    kind: _sn(j['kind']) ?? 'other',
    rel: _s(j['rel']),
    url: _s(j['url']),
    thumb: _sn(j['thumb']),
    status: _sn(j['status']) ?? 'menunggu',
    note: _sn(j['note']),
    thumbState: _sn(j['thumbState']),
    putar: _sn(j['putar']),
    putarUrl: _sn(j['putarUrl']),
  );

  final String id;
  final String name;
  final String mime;
  final int size;

  /// `html` | `image` | `pdf` | `video` | `doc` | `other`.
  final String kind;
  final String rel;

  /// Path on the Kantor host (signed).
  final String url;
  final String? thumb;

  /// `menunggu` | `oke` | `revisi`.
  final String status;
  final String? note;

  /// `siap` | `menyiapkan` | `gagal` (null on old daemons).
  final String? thumbState;

  /// H.264 rendition of a video: null | `menyiapkan` | `siap` | `gagal`.
  final String? putar;
  final String? putarUrl;

  /// What to play: the H.264 rendition when ready, else the original.
  String get playUrl => putarUrl ?? url;
}

/// One owner comment (`t` = video seconds, `file` = file id).
final class PratinjauComment {
  const PratinjauComment({
    required this.id,
    required this.text,
    required this.file,
    required this.t,
    required this.at,
  });

  factory PratinjauComment.fromJson(Map<String, dynamic> j) => PratinjauComment(
    id: _s(j['id']),
    text: _s(j['text']),
    file: _sn(j['file']),
    t: j['t'] is num ? (j['t'] as num).toDouble() : null,
    at: _sn(j['at']),
  );

  final String id;
  final String text;
  final String? file;
  final double? t;
  final String? at;
}

/// One entry of the version chain.
final class PratinjauVersion {
  const PratinjauVersion({
    required this.id,
    required this.version,
    required this.status,
    required this.createdAt,
  });

  factory PratinjauVersion.fromJson(Map<String, dynamic> j) => PratinjauVersion(
    id: _s(j['id']),
    version: _i(j['version']),
    status: _s(j['status']),
    createdAt: _sn(j['createdAt']),
  );

  final String id;
  final int version;
  final String status;
  final String? createdAt;
}

final class PratinjauItem {
  const PratinjauItem({
    required this.id,
    required this.office,
    required this.fromRole,
    required this.fromName,
    required this.sid,
    required this.title,
    required this.note,
    required this.mode,
    required this.card,
    required this.version,
    required this.parentId,
    required this.rootId,
    required this.status,
    required this.picked,
    required this.ownerNote,
    required this.createdAt,
    required this.decidedAt,
    required this.base,
    required this.files,
    required this.versions,
    this.jenis = 'persetujuan',
    this.seenAt,
    this.pinned = false,
    this.archived = false,
    this.snoozedUntil,
    this.snoozed = false,
    this.reactions = const {},
    this.comments = const [],
    this.filesPurged = false,
    this.purgedAt,
  });

  factory PratinjauItem.fromJson(Map<String, dynamic> j) => PratinjauItem(
    id: _s(j['id']),
    office: _s(j['office']),
    fromRole: _sn(j['fromRole']),
    fromName: _sn(j['fromName']),
    sid: _sn(j['sid']),
    title: _s(j['title']),
    note: _sn(j['note']),
    mode: _sn(j['mode']) ?? 'set',
    card: j['card'] == null ? null : '${j['card']}',
    version: _i(j['version']) < 1 ? 1 : _i(j['version']),
    parentId: _sn(j['parentId']),
    rootId: _sn(j['rootId']),
    status: _sn(j['status']) ?? 'menunggu',
    picked: _sn(j['picked']),
    ownerNote: _sn(j['ownerNote']),
    createdAt: _sn(j['createdAt']),
    decidedAt: _sn(j['decidedAt']),
    base: _sn(j['base']),
    files: [for (final f in _maps(j['files'])) PratinjauFile.fromJson(f)],
    versions: [
      for (final v in _maps(j['versions'])) PratinjauVersion.fromJson(v),
    ],
    jenis:
        _sn(j['jenis']) ??
        (_sn(j['mode']) == 'pilihan' ? 'pilihan' : 'persetujuan'),
    seenAt: _sn(j['seenAt']),
    pinned: j['pinned'] == true,
    archived: j['archived'] == true,
    snoozedUntil: _sn(j['snoozedUntil']),
    snoozed: j['snoozed'] == true,
    reactions: {
      if (j['reactions'] is Map)
        for (final e in (j['reactions'] as Map).entries)
          if (e.value != null && e.value != false) '${e.key}': '${e.value}',
    },
    comments: [
      for (final c in _maps(j['comments'])) PratinjauComment.fromJson(c),
    ],
    filesPurged: j['filesPurged'] == true,
    purgedAt: _sn(j['purgedAt']),
  );

  final String id;
  final String office;
  final String? fromRole;
  final String? fromName;
  final String? sid;
  final String title;
  final String? note;

  /// `set` | `pilihan` | `bundle`.
  final String mode;
  final String? card;
  final int version;
  final String? parentId;
  final String? rootId;

  /// `baru` | `dilihat` | `dikomentari` | `sebagian` | `disetujui` |
  /// `revisi` | `dipilih` (old caches: `menunggu` = baru).
  final String status;
  final String? picked;
  final String? ownerNote;
  final String? createdAt;
  final String? decidedAt;

  /// Bundle only: URL of the bundle root (ends with `/`).
  final String? base;
  final List<PratinjauFile> files;
  final List<PratinjauVersion> versions;

  /// `persetujuan` | `info` | `pilihan`.
  final String jenis;
  final String? seenAt;
  final bool pinned;
  final bool archived;
  final String? snoozedUntil;
  final bool snoozed;

  /// emoji → ISO time it was set.
  final Map<String, String> reactions;
  final List<PratinjauComment> comments;

  /// Files removed by storage cleanup; only `thumb` still loads.
  final bool filesPurged;
  final String? purgedAt;

  bool get isPilihan => jenis == 'pilihan' || mode == 'pilihan';
  bool get isInfo => jenis == 'info';
  bool get isBundle => mode == 'bundle';
  bool get decided =>
      status == 'disetujui' || status == 'revisi' || status == 'dipilih';
  bool get needsAction => !isInfo && !decided;

  /// Who sent it, for display.
  String get from => fromName ?? fromRole ?? 'Agen';
}

/// `GET /api/offices/<id>/pratinjau` response.
final class PratinjauFeed {
  const PratinjauFeed({required this.items, required this.counts});

  factory PratinjauFeed.fromJson(Map<String, dynamic> j) => PratinjauFeed(
    items: [for (final m in _maps(j['items'])) PratinjauItem.fromJson(m)],
    counts: {
      if (j['counts'] is Map)
        for (final e in (j['counts'] as Map).entries) '${e.key}': _i(e.value),
    },
  );

  final List<PratinjauItem> items;

  /// `baru` | `perlu` | `semua` | `disimpan` | `arsip` (+ old `menunggu`).
  final Map<String, int> counts;
}

/// `GET /api/offices/<id>/pratinjau/usage`.
typedef PratinjauUsage = ({int bytes, int items, int files});
