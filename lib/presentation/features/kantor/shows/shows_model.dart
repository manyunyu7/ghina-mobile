/// "Dibuka untukmu": something an agent put in front of the user.
final class KantorShow {
  const KantorShow({
    required this.id,
    required this.office,
    required this.who,
    required this.kind,
    required this.target,
    required this.at,
    this.sid,
    this.note = '',
    this.lines,
    this.seen = false,
    this.closed = false,
    this.view,
  });

  factory KantorShow.fromJson(Map<String, dynamic> j) => KantorShow(
    id: '${j['id']}',
    office: '${j['office'] ?? ''}',
    sid: j['sid'] as String?,
    who: '${j['who'] ?? 'Agen'}',
    kind: '${j['kind'] ?? 'file'}',
    target: '${j['target'] ?? ''}',
    note: '${j['note'] ?? ''}',
    lines: kantorParseLines(j['lines']),
    at: '${j['at'] ?? ''}',
    seen: j['seen'] == true || j['seen'] == 1,
    closed: j['closed'] == true || j['closed'] == 1,
    view: j['view'] is String ? j['view'] as String : null,
  );

  final String id;
  final String office;
  final String? sid;
  final String who;

  /// `file`, `folder` or `url` (the daemon also says `dir` in some docs).
  final String kind;

  /// Path relative to the office root, or an absolute http(s) address.
  final String target;
  final String note;

  /// Inclusive 1-based range to highlight, or null.
  final (int, int)? lines;
  final String at;
  final bool seen;
  final bool closed;

  /// For an HTML file: signed `/sv/<id>/<key>/…` path that renders it (sandboxed,
  /// relative assets included). Null for everything else.
  final String? view;

  bool get isHtml => kind == 'file' && view != null;

  bool get isUrl => kind == 'url';
  bool get isFolder => kind == 'folder' || kind == 'dir';

  /// Short name for titles and notifications.
  String get label {
    if (isUrl) return target;
    final t = target.replaceAll(RegExp(r'/+$'), '');
    return t.isEmpty ? office : t.split('/').last;
  }

  /// A Mac-only address: the phone cannot reach it.
  bool get isLocalUrl =>
      isUrl && kantorIsLocalHost(Uri.tryParse(target)?.host ?? '');

  KantorShow copyWith({bool? seen, bool? closed}) => KantorShow(
    id: id,
    office: office,
    sid: sid,
    who: who,
    kind: kind,
    target: target,
    note: note,
    lines: lines,
    at: at,
    seen: seen ?? this.seen,
    closed: closed ?? this.closed,
    view: view,
  );
}

/// `[from, to]`, `"12"` or `"12-30"` → an ordered inclusive range.
(int, int)? kantorParseLines(Object? v) {
  int? a, b;
  if (v is List && v.isNotEmpty) {
    a = (v[0] as num?)?.toInt();
    b = v.length > 1 ? (v[1] as num?)?.toInt() : a;
  } else if (v is String) {
    final m = RegExp(r'^\s*(\d+)\s*(?:[-–:]\s*(\d+))?\s*$').firstMatch(v);
    if (m != null) {
      a = int.parse(m.group(1)!);
      b = m.group(2) == null ? a : int.parse(m.group(2)!);
    }
  }
  if (a == null || b == null || a < 1 || b < 1) return null;
  return a <= b ? (a, b) : (b, a);
}

/// Loopback, private-network and `.local` hosts.
bool kantorIsLocalHost(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty ||
      h == 'localhost' ||
      h.endsWith('.local') ||
      h == '::1' ||
      h == '[::1]')
    return true;
  final m = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(h);
  if (m == null) return false;
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  return a == 127 ||
      a == 10 ||
      a == 0 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}
