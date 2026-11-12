/// Tab Konten: bentuk data dari `/api/offices/<id>/konten`. Parsing dibuat
/// longgar: field kosong, hilang, atau bertipe lain tidak boleh bikin crash.
library;

String _s(Object? v, [String d = '']) =>
    v is String ? v : (v == null ? d : '$v');
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
bool _b(Object? v) => v == true || v == 1;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};
List<dynamic> _l(Object? v) => v is List ? v : const [];

/// Tanggal `yyyy-MM-dd` dari string tanggal/ISO apa pun, atau null.
DateTime? kontenDate(String? raw) {
  if (raw == null || raw.length < 10) return null;
  final d = DateTime.tryParse(raw.substring(0, 10));
  return d;
}

String kontenDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const kontenPlatformNames = <String, String>{
  'instagram': 'Instagram',
  'threads': 'Threads',
  'tiktok': 'TikTok',
  'youtube': 'YouTube',
};

String kontenPlatformName(String key) => kontenPlatformNames[key] ?? key;

class KontenFile {
  const KontenFile({
    required this.rel,
    required this.name,
    required this.url,
    this.thumb,
    this.size = 0,
  });

  factory KontenFile.fromJson(Object? raw) {
    final j = _m(raw);
    final rel = _s(j['rel']);
    return KontenFile(
      rel: rel,
      name: _sn(j['name']) ?? rel.split('/').last,
      url: _s(j['url']),
      thumb: _sn(j['thumb']),
      size: _i(j['size']),
    );
  }

  final String rel;
  final String name;
  final String url;
  final String? thumb;
  final int size;
}

class KontenMediaSet {
  const KontenMediaSet({this.slides = const [], this.video, this.cover});

  factory KontenMediaSet.fromJson(Object? raw) {
    final j = _m(raw);
    return KontenMediaSet(
      slides: [
        for (final s in _l(j['slides']))
          if (s is Map) KontenFile.fromJson(s),
      ],
      video: j['video'] is Map ? KontenFile.fromJson(j['video']) : null,
      cover: j['cover'] is Map ? KontenFile.fromJson(j['cover']) : null,
    );
  }

  final List<KontenFile> slides;
  final KontenFile? video;
  final KontenFile? cover;

  bool get isEmpty => slides.isEmpty && video == null;
}

class KontenPosted {
  const KontenPosted({this.link, this.at});
  final String? link;
  final String? at;
}

class KontenItem {
  const KontenItem({
    required this.id,
    required this.title,
    required this.tahap,
    this.tahapNama = '',
    this.jenis = 'lain',
    this.seri,
    this.publishAt,
    this.jam,
    this.jadwalStatus = '',
    this.lagu,
    this.sensitif = false,
    this.acuan = false,
    this.catatan,
    this.whoName,
    this.updatedAt,
    this.coverUrl,
    this.platforms = const {},
    this.perf = const {},
    this.media = const KontenMediaSet(),
    this.captions = const {},
    this.platformTarget = const [],
    this.desc,
  });

  factory KontenItem.fromJson(Object? raw) {
    final j = _m(raw);
    final caps = _m(j['captions']);
    return KontenItem(
      id: _s(j['id']),
      title: _sn(j['title']) ?? 'Tanpa judul',
      tahap: _s(j['tahap']),
      tahapNama: _s(j['tahapNama']),
      jenis: _sn(j['jenis']) ?? 'lain',
      seri: _sn(j['seri']),
      publishAt: _sn(j['publishAt']),
      jam: _sn(j['jam']),
      jadwalStatus: _s(j['jadwalStatus']),
      lagu: _sn(j['lagu']),
      sensitif: _b(j['sensitif']),
      acuan: _b(j['acuan']),
      catatan: _sn(j['catatan']),
      whoName: _sn(j['whoName']),
      updatedAt: _sn(j['updatedAt']),
      coverUrl: _sn(j['coverUrl']),
      platforms: {
        for (final e in _m(j['platforms']).entries)
          e.key: KontenPosted(
            link: _sn(_m(e.value)['link']),
            at: _sn(_m(e.value)['at']),
          ),
      },
      perf: {
        for (final e in _m(j['perf']).entries)
          e.key: {
            for (final f in _m(e.value).entries)
              if (f.value is num) f.key: (f.value as num).toInt(),
          },
      },
      media: KontenMediaSet.fromJson(j['media']),
      captions: {
        for (final p in kontenPlatformNames.keys)
          if (_sn(caps[p]) != null) p: caps[p] as String,
      },
      platformTarget: [
        for (final p in _l(j['platformTarget']))
          if (p is String) p,
      ],
      desc: _sn(j['desc']),
    );
  }

  final String id;
  final String title;
  final String tahap;
  final String tahapNama;
  final String jenis;
  final String? seri;
  final String? publishAt;
  final String? jam;
  final String jadwalStatus;
  final String? lagu;
  final bool sensitif;
  final bool acuan;
  final String? catatan;
  final String? whoName;
  final String? updatedAt;
  final String? coverUrl;
  final Map<String, KontenPosted> platforms;
  final Map<String, Map<String, int>> perf;
  final KontenMediaSet media;
  final Map<String, String> captions;
  final List<String> platformTarget;
  final String? desc;

  bool get usulan => jadwalStatus == 'usulan';
  DateTime? get tanggal => kontenDate(publishAt);

  /// Platform yang ditawarkan: target dari server, kalau kosong semua kecuali
  /// YouTube untuk carousel.
  List<String> get targets {
    if (platformTarget.isNotEmpty) return platformTarget;
    return [
      for (final p in kontenPlatformNames.keys)
        if (!(jenis == 'carousel' && p == 'youtube')) p,
    ];
  }
}

class KontenStage {
  const KontenStage({required this.id, required this.name, this.n = 0});
  final String id;
  final String name;
  final int n;
}

class KontenList {
  const KontenList({
    this.items = const [],
    this.stages = const [],
    this.unsupported = false,
  });

  factory KontenList.fromJson(Object? raw) {
    final j = _m(raw);
    return KontenList(
      items: [
        for (final i in _l(j['items']))
          if (i is Map) KontenItem.fromJson(i),
      ],
      stages: [
        for (final s in _l(j['stages']))
          if (s is Map)
            KontenStage(id: _s(s['id']), name: _s(s['name']), n: _i(s['n'])),
      ],
    );
  }

  final List<KontenItem> items;
  final List<KontenStage> stages;

  /// Server lama tanpa API Konten (404).
  final bool unsupported;
}

class KontenWarning {
  const KontenWarning({
    required this.kode,
    required this.pesan,
    this.ids = const [],
  });
  final String kode;
  final String pesan;
  final List<String> ids;
}

class KontenWeek {
  const KontenWeek({
    required this.mulai,
    required this.n,
    required this.target,
  });
  final String mulai;
  final int n;
  final int target;
}

class KontenJadwal {
  const KontenJadwal({
    this.items = const [],
    this.peringatan = const [],
    this.minggu = const [],
    this.unsupported = false,
  });

  factory KontenJadwal.fromJson(Object? raw) {
    final j = _m(raw);
    return KontenJadwal(
      items: [
        for (final i in _l(j['items']))
          if (i is Map) KontenItem.fromJson(i),
      ],
      peringatan: [
        for (final w in _l(j['peringatan']))
          if (w is Map)
            KontenWarning(
              kode: _s(w['kode']),
              pesan: _s(w['pesan']),
              ids: [for (final x in _l(w['ids'])) '$x'],
            ),
      ],
      minggu: [
        for (final w in _l(j['minggu']))
          if (w is Map)
            KontenWeek(
              mulai: _s(w['mulai']),
              n: _i(w['n']),
              target: _i(w['target']),
            ),
      ],
    );
  }

  final List<KontenItem> items;
  final List<KontenWarning> peringatan;
  final List<KontenWeek> minggu;
  final bool unsupported;
}
