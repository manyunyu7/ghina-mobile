/// Kantor board: pure logic (cards, dates, filters, quick-add shorthand).
/// A port of the web `board-lib.js`; no Flutter here so it tests easily.
library;

const kantorCols = ['Backlog', 'Siap', 'Dikerjakan', 'Review', 'Selesai'];
const kantorDefaultWip = [0, 0, 5, 3, 0];
const kantorPrios = ['P0', 'P1', 'P2', 'P3'];
const kantorDoneCol = 4;

/// Column kinds (multi-board servers); index = legacy `stage`.
const kantorKinds = ['antre', 'siap', 'dikerjakan', 'review', 'selesai'];
const kantorKindWip = {'dikerjakan': 5, 'review': 3};

/// A column of a board: its name and its kind (one of [kantorKinds]).
class KCol {
  const KCol(this.id, this.name, this.kind);
  factory KCol.fromJson(Map<String, dynamic> j) => KCol(
    '${j['id'] ?? j['name'] ?? ''}',
    '${j['name'] ?? j['id'] ?? ''}',
    kantorKinds.contains(j['kind']) ? '${j['kind']}' : 'antre',
  );
  final String id;
  final String name;
  final String kind;
  int get stage => kantorKinds.indexOf(kind).clamp(0, 4);
}

/// The old fixed 5 columns (also used against an old server).
final kantorDefaultColumns = [
  for (var i = 0; i < kantorCols.length; i++)
    KCol(kantorKinds[i], kantorCols[i], kantorKinds[i]),
];

/// One board of an office (`GET /boards`). The default one has id `utama`.
class KBoardDef {
  const KBoardDef({
    required this.id,
    required this.name,
    this.icon = '',
    this.color = '',
    this.template = '',
    this.columns = const [],
    this.ord = 0,
    this.archived = false,
    this.isDefault = false,
  });
  factory KBoardDef.fromJson(Map<String, dynamic> j) {
    final cols = [
      for (final c in (j['columns'] as List? ?? const []))
        if (c is Map) KCol.fromJson(Map<String, dynamic>.from(c)),
    ];
    return KBoardDef(
      id: '${j['id']}',
      name: '${j['name'] ?? j['id']}',
      icon: '${j['icon'] ?? ''}',
      color: '${j['color'] ?? ''}',
      template: '${j['template'] ?? ''}',
      columns: cols.isEmpty ? kantorDefaultColumns : cols,
      ord: (j['ord'] as num?)?.toDouble() ?? 0,
      archived: j['archived'] == true,
      isDefault: j['isDefault'] == true || j['id'] == 'utama',
    );
  }
  final String id;
  final String name;
  final String icon;
  final String color;
  final String template;
  final List<KCol> columns;
  final double ord;
  final bool archived;
  final bool isDefault;
}
const kantorOldDoneDays = 7;
const kantorNone = '_none';

const kantorGroups = [
  ('none', 'Tanpa kelompok'),
  ('who', 'Role'),
  ('epic', 'Epic'),
  ('prio', 'Prioritas'),
  ('label', 'Label'),
  ('repo', 'Repo'),
];

/* ---------------- dates ---------------- */

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool isKDate(Object? v) => v is String && _dateRe.hasMatch(v);

String _pad(int n) => n.toString().padLeft(2, '0');
String kDayStr(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
String kTodayStr() => kDayStr(DateTime.now());

DateTime? kParseDay(String? s) {
  if (!isKDate(s)) return null;
  final p = s!.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String kAddDays(String s, int n) {
  final d = kParseDay(s)!;
  return kDayStr(DateTime(d.year, d.month, d.day + n));
}

const kMonShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des', //
];

String kFmtDay(String? s) {
  final d = kParseDay(s);
  if (d == null) return s ?? '';
  return '${d.day} ${kMonShort[d.month - 1]}';
}

/// "5m lalu" style relative time for an ISO timestamp.
String kAgo(String? iso, {DateTime? now}) {
  final t = DateTime.tryParse(iso ?? '');
  if (t == null) return '';
  final s = (now ?? DateTime.now()).difference(t).inSeconds;
  if (s < 45) return 'baru saja';
  if (s < 3600) return '${(s / 60).round()} mnt lalu';
  if (s < 86400) return '${(s / 3600).round()} jam lalu';
  if (s < 86400 * 30) return '${(s / 86400).round()} hari lalu';
  return kFmtDay(kDayStr(t.toLocal()));
}

enum KDue { none, over, soon, ok, done }

/* ---------------- cards ---------------- */

class KLabel {
  const KLabel({required this.id, required this.name, required this.color});
  factory KLabel.fromJson(Map<String, dynamic> j) => KLabel(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    color: '${j['color'] ?? '#888888'}',
  );
  final String id;
  final String name;
  final String color;
}

class KCard {
  const KCard({
    required this.id,
    required this.title,
    this.desc = '',
    this.col = 0,
    this.who = '',
    this.repo = '',
    this.prio = 'P2',
    this.due = '',
    this.start = '',
    this.estDays,
    this.progress,
    this.blocked = '',
    this.epic = false,
    this.epicId = '',
    this.milestone = false,
    this.cover,
    this.labels = const [],
    this.deps = const [],
    this.checksTotal = 0,
    this.checksDone = 0,
    this.comments = 0,
    this.attachments = 0,
    this.ord = 0,
    this.createdAt = '',
    this.updatedAt = '',
    this.movedAt = '',
    this.board = 'utama',
    this.colName = '',
    String? colKind,
    bool? done,
    this.publishAt = '',
    this.coverUrl,
  }) : _kind = colKind,
       // ignore: prefer_initializing_formals
       _done = done;

  factory KCard.fromJson(Map<String, dynamic> j) {
    final checks = j['checks'];
    List<String> ids(Object? v) => v is List
        ? [
            for (final x in v)
              if (x is Map) '${x['id']}' else '$x',
          ]
        : const [];
    final col = (j['col'] as num?)?.toInt() ?? 0;
    final kind = kantorKinds.contains(j['colKind'])
        ? '${j['colKind']}'
        : kantorKinds[col.clamp(0, 4)];
    return KCard(
      board: '${j['board'] ?? 'utama'}',
      colName: '${j['colName'] ?? ''}',
      colKind: kind,
      done: j['done'] is bool ? j['done'] as bool : kind == 'selesai',
      publishAt: isKDate(j['publishAt']) ? '${j['publishAt']}' : '',
      coverUrl: j['coverUrl'] is String && '${j['coverUrl']}'.isNotEmpty
          ? '${j['coverUrl']}'
          : null,
      id: '${j['id']}',
      title: '${j['title'] ?? ''}',
      desc: '${j['desc'] ?? ''}',
      col: col,
      who: '${j['who'] ?? ''}',
      repo: '${j['repo'] ?? ''}',
      prio: '${j['prio'] ?? 'P2'}',
      due: '${j['due'] ?? ''}',
      start: '${j['start'] ?? ''}',
      estDays: (j['estDays'] as num?)?.toDouble(),
      progress: (j['progress'] as num?)?.toInt(),
      blocked: '${j['blocked'] ?? ''}',
      epic: j['epic'] == true,
      epicId: '${j['epicId'] ?? ''}',
      milestone: j['milestone'] == true,
      cover: j['cover'] == null ? null : '${j['cover']}',
      labels: ids(j['labels']),
      deps: ids(j['deps']),
      checksTotal: checks is Map ? (checks['total'] as num?)?.toInt() ?? 0 : 0,
      checksDone: checks is Map ? (checks['done'] as num?)?.toInt() ?? 0 : 0,
      comments: j['comments'] is num ? (j['comments'] as num).toInt() : 0,
      attachments: j['attachments'] is num
          ? (j['attachments'] as num).toInt()
          : 0,
      ord: (j['ord'] as num?)?.toDouble() ?? 0,
      createdAt: '${j['createdAt'] ?? ''}',
      updatedAt: '${j['updatedAt'] ?? ''}',
      movedAt: '${j['movedAt'] ?? ''}',
    );
  }

  final String id;
  final String title;
  final String desc;
  final int col;
  final String who;
  final String repo;
  final String prio;
  final String due;
  final String start;
  final double? estDays;
  final int? progress;
  final String blocked;
  final bool epic;
  final String epicId;
  final bool milestone;
  final String? cover;
  final List<String> labels;
  final List<String> deps;
  final int checksTotal;
  final int checksDone;
  final int comments;
  final int attachments;
  final double ord;
  final String createdAt;
  final String updatedAt;
  final String movedAt;

  /// Board id (`utama` against an old server).
  final String board;
  final String colName;

  final String? _kind;
  final bool? _done;

  /// One of [kantorKinds] (from `col` against an old server).
  String get colKind => _kind ?? kantorKinds[col.clamp(0, 4)];

  /// Column kind is `selesai`.
  bool get done => _done ?? colKind == 'selesai';

  /// Legacy 0..4 index by kind.
  int get stage => kantorKinds.indexOf(colKind).clamp(0, 4);

  /// "YYYY-MM-DD" or "".
  final String publishAt;

  /// Relative `/api/…/media/<id>` URL of the cover, or null.
  final String? coverUrl;

  /// publishAt, else due ("" if neither): the calendar date.
  String get calDay => isKDate(publishAt) ? publishAt : (isKDate(due) ? due : '');

  /// Percent done: manual `progress`, else from the checklist; null if neither.
  int? get percent {
    if (progress != null) return progress;
    return checksTotal == 0 ? null : (checksDone / checksTotal * 100).round();
  }

  KCard copyWith({
    int? col,
    double? ord,
    String? who,
    String? repo,
    String? epicId,
    List<String>? labels,
    String? start,
    String? due,
    String? colName,
    String? colKind,
    String? board,
    String? publishAt,
  }) => KCard(
    id: id,
    title: title,
    desc: desc,
    col: col ?? this.col,
    who: who ?? this.who,
    repo: repo ?? this.repo,
    prio: prio,
    due: due ?? this.due,
    start: start ?? this.start,
    estDays: estDays,
    progress: progress,
    blocked: blocked,
    epic: epic,
    epicId: epicId ?? this.epicId,
    milestone: milestone,
    cover: cover,
    labels: labels ?? this.labels,
    deps: deps,
    checksTotal: checksTotal,
    checksDone: checksDone,
    comments: comments,
    attachments: attachments,
    ord: ord ?? this.ord,
    createdAt: createdAt,
    updatedAt: updatedAt,
    movedAt: movedAt,
    board: board ?? this.board,
    colName: colName ?? this.colName,
    colKind: colKind ?? _kind,
    done: colKind != null ? colKind == 'selesai' : _done,
    publishAt: publishAt ?? this.publishAt,
    coverUrl: coverUrl,
  );
}

KDue kDueState(KCard c, {String? today}) {
  if (!isKDate(c.due)) return KDue.none;
  if (c.done) return KDue.done;
  final t = today ?? kTodayStr();
  if (c.due.compareTo(t) < 0) return KDue.over;
  return c.due.compareTo(kAddDays(t, 2)) <= 0 ? KDue.soon : KDue.ok;
}

bool kIsOldDone(KCard c, {String? today}) {
  if (!c.done) return false;
  final t = DateTime.tryParse(c.movedAt.isEmpty ? c.updatedAt : c.movedAt);
  if (t == null) return false;
  final limit = kParseDay(kAddDays(today ?? kTodayStr(), -kantorOldDoneDays))!;
  return t.isBefore(limit);
}

/// Deps that are not Done yet (an archived dep counts as done).
List<String> kPendingDeps(KCard c, Map<String, KCard> map) => [
  for (final id in c.deps)
    if (map[id] != null && !map[id]!.done) id,
];

/// New `ord` that puts a card between [prev] and [next].
double kMidOrd(double? prev, double? next) {
  if (prev != null && next != null) {
    final m = (prev + next) / 2;
    return m > prev && m < next ? m : prev + (next - prev) / 2;
  }
  if (next != null) return next - 1000;
  if (prev != null) return prev + 1000;
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

/// `n` ords spread between [prev] and [next], for moving several cards at once.
List<double> kOrdsBetween(double? prev, double? next, int n) {
  if (prev != null && next != null) {
    return [
      for (var k = 0; k < n; k++) prev + (next - prev) * (k + 1) / (n + 1),
    ];
  }
  if (next != null)
    return [for (var k = 0; k < n; k++) next - 1000.0 * (n - k)];
  if (prev != null)
    return [for (var k = 0; k < n; k++) prev + 1000.0 * (k + 1)];
  final t = DateTime.now().millisecondsSinceEpoch.toDouble();
  return [for (var k = 0; k < n; k++) t + k];
}

/* ---------------- filter ---------------- */

class KFilter {
  const KFilter({
    this.q = '',
    this.who = const {},
    this.labels = const {},
    this.prios = const {},
    this.repos = const {},
    this.due = '',
    this.blocked = false,
    this.waiting = false,
    this.unassigned = false,
    this.mine = false,
    this.me = '',
    this.hideOld = false,
    this.group = 'none',
    this.list = false,
  });

  final String q;
  final Set<String> who;
  final Set<String> labels;
  final Set<String> prios;
  final Set<String> repos;

  /// '' | 'overdue' | 'week' | 'none'
  final String due;
  final bool blocked;
  final bool waiting;
  final bool unassigned;
  final bool mine;

  /// The role id the user stands for in "Kartu saya".
  final String me;
  final bool hideOld;
  final String group;
  final bool list;

  KFilter copyWith({
    String? q,
    Set<String>? who,
    Set<String>? labels,
    Set<String>? prios,
    Set<String>? repos,
    String? due,
    bool? blocked,
    bool? waiting,
    bool? unassigned,
    bool? mine,
    String? me,
    bool? hideOld,
    String? group,
    bool? list,
  }) => KFilter(
    q: q ?? this.q,
    who: who ?? this.who,
    labels: labels ?? this.labels,
    prios: prios ?? this.prios,
    repos: repos ?? this.repos,
    due: due ?? this.due,
    blocked: blocked ?? this.blocked,
    waiting: waiting ?? this.waiting,
    unassigned: unassigned ?? this.unassigned,
    mine: mine ?? this.mine,
    me: me ?? this.me,
    hideOld: hideOld ?? this.hideOld,
    group: group ?? this.group,
    list: list ?? this.list,
  );

  int get activeCount =>
      (q.trim().isEmpty ? 0 : 1) +
      who.length +
      labels.length +
      prios.length +
      repos.length +
      (due.isEmpty ? 0 : 1) +
      [blocked, waiting, unassigned, mine, hideOld].where((b) => b).length;

  Map<String, dynamic> toJson() => {
    'q': q,
    'who': who.toList(),
    'labels': labels.toList(),
    'prios': prios.toList(),
    'repos': repos.toList(),
    'due': due,
    'blocked': blocked,
    'waiting': waiting,
    'unassigned': unassigned,
    'mine': mine,
    'me': me,
    'hideOld': hideOld,
    'group': group,
    'list': list,
  };

  factory KFilter.fromJson(Map<String, dynamic> j) {
    Set<String> set(Object? v) => v is List
        ? {
            for (final x in v)
              if (x is String) x,
          }
        : <String>{};
    final due = '${j['due'] ?? ''}';
    final group = '${j['group'] ?? 'none'}';
    return KFilter(
      q: '${j['q'] ?? ''}',
      who: set(j['who']),
      labels: set(j['labels']),
      prios: set(j['prios']),
      repos: set(j['repos']),
      due: const ['overdue', 'week', 'none'].contains(due) ? due : '',
      blocked: j['blocked'] == true,
      waiting: j['waiting'] == true,
      unassigned: j['unassigned'] == true,
      mine: j['mine'] == true,
      me: '${j['me'] ?? ''}',
      hideOld: j['hideOld'] == true,
      group: kantorGroups.any((g) => g.$1 == group) ? group : 'none',
      list: j['list'] == true,
    );
  }
}

bool kMatchCard(
  KCard c,
  KFilter f, {
  required Map<String, KCard> map,
  String Function(String id)? labelName,
  String? today,
}) {
  final t = today ?? kTodayStr();
  final q = f.q.trim().toLowerCase();
  if (q.isNotEmpty) {
    final hay =
        '${c.title} ${c.desc} ${c.id} ${c.labels.map((l) => labelName?.call(l) ?? '').join(' ')}'
            .toLowerCase();
    if (!q.split(RegExp(r'\s+')).every(hay.contains)) return false;
  }
  if (f.who.isNotEmpty && !f.who.contains(c.who.isEmpty ? kantorNone : c.who)) {
    return false;
  }
  if (f.labels.isNotEmpty && !c.labels.any(f.labels.contains)) return false;
  if (f.prios.isNotEmpty && !f.prios.contains(c.prio)) return false;
  if (f.repos.isNotEmpty &&
      !f.repos.contains(c.repo.isEmpty ? kantorNone : c.repo)) {
    return false;
  }
  if (f.due == 'overdue' && kDueState(c, today: t) != KDue.over) return false;
  if (f.due == 'none' && c.due.isNotEmpty) return false;
  if (f.due == 'week' &&
      !(isKDate(c.due) &&
          c.due.compareTo(t) >= 0 &&
          c.due.compareTo(kAddDays(t, 7)) <= 0)) {
    return false;
  }
  if (f.blocked && c.blocked.isEmpty) return false;
  if (f.waiting && kPendingDeps(c, map).isEmpty) return false;
  if (f.unassigned && c.who.isNotEmpty) return false;
  if (f.mine && (f.me.isEmpty || c.who != f.me)) return false;
  if (f.hideOld && kIsOldDone(c, today: t)) return false;
  return true;
}

/* ---------------- quick add: "judul #label @role !P1" ---------------- */

class KQuick {
  KQuick({required this.title, required this.labels, this.who, this.prio});
  final String title;
  final List<String> labels;
  final String? who;
  final String? prio;
}

KQuick kParseQuick(
  String text, {
  List<KLabel> labels = const [],
  List<({String id, String name})> roles = const [],
}) {
  final keep = <String>[];
  final outLabels = <String>{};
  String? who, prio;
  for (final tok in text.trim().split(RegExp(r'\s+'))) {
    final lm = RegExp(r'^#([^\s#@!]+)$').firstMatch(tok);
    final wm = RegExp(r'^@([^\s#@!]+)$').firstMatch(tok);
    final pm = RegExp(r'^!([pP][0-3])$').firstMatch(tok);
    if (lm != null) {
      final name = lm.group(1)!.replaceAll('_', ' ');
      final hit = labels
          .where((l) => l.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      outLabels.add(hit?.name ?? name);
    } else if (wm != null) {
      final k = wm.group(1)!.toLowerCase();
      final r =
          roles
              .where(
                (x) => x.id.toLowerCase() == k || x.name.toLowerCase() == k,
              )
              .firstOrNull ??
          roles
              .where(
                (x) =>
                    x.name.toLowerCase().startsWith(k) ||
                    x.id.toLowerCase().startsWith(k),
              )
              .firstOrNull;
      if (r != null) {
        who = r.id;
      } else {
        keep.add(tok);
      }
    } else if (pm != null) {
      prio = pm.group(1)!.toUpperCase();
    } else {
      keep.add(tok);
    }
  }
  return KQuick(
    title: keep.join(' ').trim(),
    labels: outLabels.toList(),
    who: who,
    prio: prio,
  );
}

String kFmtSize(num n) => n >= 1048576
    ? '${(n / 1048576).toStringAsFixed(1)} MB'
    : n >= 1024
    ? '${(n / 1024).round()} KB'
    : '${n.round()} B';

/// Black or white ink that reads on a `#rrggbb` color.
bool kInkIsDark(String hex) {
  final n = int.tryParse(
    hex.replaceFirst('#', '').padRight(6, '0').substring(0, 6),
    radix: 16,
  );
  if (n == null) return false;
  final l =
      (0.299 * ((n >> 16) & 255) +
          0.587 * ((n >> 8) & 255) +
          0.114 * (n & 255)) /
      255;
  return l > 0.62;
}
