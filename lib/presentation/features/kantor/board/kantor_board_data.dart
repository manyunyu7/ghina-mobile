import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../di/di.dart';
import 'kantor_board_lib.dart';

/// A role of the office, kept as the daemon's raw map so [KantorSprite] can
/// draw it.
class KRole {
  KRole(this.raw)
    : id = '${raw['id']}',
      name = '${raw['name'] ?? raw['id']}',
      title = '${raw['title'] ?? ''}',
      archived = raw['archived'] == true;
  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final String title;
  final bool archived;
}

class KRoom {
  const KRoom(this.id, this.name, {required this.isRepo});
  final String id;
  final String name;

  /// Rooms with a `path` are repositories.
  final bool isRepo;
}

/// What the board needs from `GET /api/offices/:id`.
class KOffice {
  KOffice({
    required this.roles,
    required this.rooms,
    required this.workingRoles,
  });

  factory KOffice.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'];
    final rooms = plan is Map && plan['rooms'] is List
        ? plan['rooms'] as List
        : const [];
    final sessions = j['sessions'] is List ? j['sessions'] as List : const [];
    return KOffice(
      roles: [
        for (final r in (j['roles'] as List? ?? const []))
          if (r is Map<String, dynamic>) KRole(r),
      ],
      rooms: [
        for (final r in rooms)
          if (r is Map)
            KRoom(
              '${r['id']}',
              '${r['name'] ?? r['id']}',
              isRepo: r['path'] != null,
            ),
      ],
      workingRoles: {
        for (final s in sessions)
          if (s is Map && s['status'] == 'working') '${s['role']}',
      },
    );
  }

  final List<KRole> roles;
  final List<KRoom> rooms;

  /// Roles with a session that is working right now.
  final Set<String> workingRoles;

  List<KRole> get activeRoles => roles.where((r) => !r.archived).toList();
  KRole? role(String id) =>
      id.isEmpty ? null : roles.where((r) => r.id == id).firstOrNull;
  String whoName(String id) =>
      id.isEmpty ? 'Belum ditugaskan' : role(id)?.name ?? id;
  String repoName(String id) {
    if (id.isEmpty) return 'tanpa repo';
    if (id == 'lintas') return 'lintas repo';
    return rooms.where((r) => r.id == id).firstOrNull?.name ?? id;
  }
}

class KBoard {
  KBoard(
    this.cards,
    this.labels, {
    this.boards = const [],
    this.board,
    List<KCol>? columns,
    this.all = false,
  }) : columns = columns ?? board?.columns ?? kantorDefaultColumns,
       map = {for (final c in cards) c.id: c};
  final List<KCard> cards;
  final List<KLabel> labels;
  final Map<String, KCard> map;

  /// Every board of the office (empty against an old server).
  final List<KBoardDef> boards;

  /// The shown board; null in "Semua papan" mode or against an old server.
  final KBoardDef? board;

  /// Columns of [board] (the old 5 when unknown).
  final List<KCol> columns;

  /// "Semua papan" mode: cards of every board.
  final bool all;

  List<KBoardDef> get activeBoards => boards.where((b) => !b.archived).toList()
    ..sort((a, b) => a.ord.compareTo(b.ord));
  KBoardDef? boardDef(String id) => boards.where((b) => b.id == id).firstOrNull;

  /// Columns of the card's own board.
  List<KCol> colsOf(KCard c) =>
      boardDef(c.board)?.columns ?? (all ? kantorDefaultColumns : columns);

  /// Column name of a card.
  String colNameOf(KCard c) {
    if (c.colName.isNotEmpty) return c.colName;
    final cols = colsOf(c);
    return c.col >= 0 && c.col < cols.length ? cols[c.col].name : c.colKind;
  }

  KLabel? label(String id) => labels.where((l) => l.id == id).firstOrNull;
  String labelName(String id) => label(id)?.name ?? '';
  List<KCard> get epics => cards.where((c) => c.epic).toList();
  List<KCard> kids(String epicId) =>
      cards.where((c) => c.epicId == epicId).toList();
  List<KCard> inCol(int col) =>
      cards.where((c) => !c.epic && c.col == col).toList()
        ..sort((a, b) => a.ord.compareTo(b.ord));

  KBoard withCards(List<KCard> next) => KBoard(
    next,
    labels,
    boards: boards,
    board: board,
    columns: columns,
    all: all,
  );
}

KantorApi _need(Ref ref) {
  final api = ref.read(kantorApiProvider);
  if (api == null) {
    throw const KantorException(KantorFailure.unauthorized, 'Belum ada token');
  }
  return api;
}

String kBase(String officeId) => '/api/offices/$officeId';

bool _eventFor(Map<String, dynamic> e, String officeId, Set<String> what) {
  if (e['t'] != 'changed') return false;
  final o = e['office'];
  if (o != '*' && o != officeId) return false;
  return what.contains(e['what']);
}

/// Roles, rooms and who is working.
final kantorOfficeProvider = FutureProvider.family<KOffice, String>((
  ref,
  officeId,
) async {
  final api = _need(ref);
  ref.listen(kantorEventsProvider, (_, next) {
    final e = next.value;
    if (e == null) return;
    if (e['t'] == 'session' ||
        _eventFor(e, officeId, const {'roles', 'plan'})) {
      ref.invalidateSelf();
    }
  });
  final j = await api.get(kBase(officeId));
  return KOffice.fromJson(Map<String, dynamic>.from(j as Map));
});

/// Board id value for "Semua papan".
const kantorAllBoards = 'all';

/// Selected board per office (`utama`, a board id, or [kantorAllBoards]),
/// remembered in SharedPreferences.
final kantorBoardSelProvider =
    NotifierProvider.family<KBoardSelNotifier, String, String>(
      KBoardSelNotifier.new,
    );

class KBoardSelNotifier extends Notifier<String> {
  KBoardSelNotifier(this.officeId);
  final String officeId;
  bool _touched = false;

  String get _key => 'kantor.board.$officeId';

  @override
  String build() {
    SharedPreferences.getInstance()
        .then((p) {
          final v = p.getString(_key);
          if (!_touched && v != null && v.isNotEmpty && v != state) state = v;
        })
        .catchError((_) {});
    return 'utama';
  }

  void select(String id) {
    _touched = true;
    if (id == state) return;
    state = id;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, id))
        .catchError((_) => false);
  }
}

/// `GET /boards`: boards, column kinds and templates.
typedef KBoardsInfo = ({
  List<KBoardDef> boards,
  List<({String id, String name})> templates,
});

final kantorBoardsProvider = FutureProvider.autoDispose
    .family<KBoardsInfo, String>((ref, officeId) async {
      final api = _need(ref);
      final j = Map<String, dynamic>.from(
        await api.get('${kBase(officeId)}/boards') as Map,
      );
      return (
        boards: [
          for (final b in (j['boards'] as List? ?? const []))
            if (b is Map) KBoardDef.fromJson(Map<String, dynamic>.from(b)),
        ],
        templates: [
          for (final t in (j['templates'] as List? ?? const []))
            if (t is Map) (id: '${t['id']}', name: '${t['name'] ?? t['id']}'),
        ],
      );
    });

/// Every card of every board (calendar). Live like the board.
final kantorAllCardsProvider = FutureProvider.autoDispose.family<KBoard, String>(
  (ref, officeId) async {
    final api = _need(ref);
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e != null && _eventFor(e, officeId, const {'board', 'boards'})) {
        ref.invalidateSelf();
      }
    });
    final j = await api.get(
      '${kBase(officeId)}/board',
      query: {'board': kantorAllBoards},
    );
    return kParseBoard(Map<String, dynamic>.from(j as Map), all: true);
  },
);

/// Parses `GET /board`; tolerant of an old server (no boards/columns).
KBoard kParseBoard(Map<String, dynamic> m, {bool all = false}) {
  final boards = [
    for (final b in (m['boards'] as List? ?? const []))
      if (b is Map) KBoardDef.fromJson(Map<String, dynamic>.from(b)),
  ];
  final bj = m['board'];
  final board = bj is Map
      ? KBoardDef.fromJson(Map<String, dynamic>.from(bj))
      : null;
  final cols = [
    for (final c in (m['columns'] as List? ?? const []))
      if (c is Map) KCol.fromJson(Map<String, dynamic>.from(c)),
  ];
  return KBoard(
    [
      for (final c in (m['cards'] as List? ?? const []))
        if (c is Map) KCard.fromJson(Map<String, dynamic>.from(c)),
    ],
    [
      for (final l in (m['labels'] as List? ?? const []))
        if (l is Map) KLabel.fromJson(Map<String, dynamic>.from(l)),
    ],
    boards: boards,
    board: board,
    columns: all || cols.isEmpty ? null : cols,
    all: all && boards.isNotEmpty,
  );
}

/// The board of one office, live. Writes are optimistic and refetch after.
final kantorBoardProvider =
    AsyncNotifierProvider.family<KBoardNotifier, KBoard, String>(
      KBoardNotifier.new,
    );

class KBoardNotifier extends AsyncNotifier<KBoard> {
  KBoardNotifier(this.officeId);
  final String officeId;

  Timer? _debounce;
  String _sel = 'utama';

  KantorApi get _api => _need(ref);

  @override
  Future<KBoard> build() async {
    _sel = ref.watch(kantorBoardSelProvider(officeId));
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e != null && _eventFor(e, officeId, const {'board', 'boards'})) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), refresh);
      }
    });
    ref.onDispose(() => _debounce?.cancel());
    return _fetch();
  }

  Future<KBoard> _fetch() async {
    var sel = _sel;
    dynamic j;
    try {
      j = await _api.get(
        '${kBase(officeId)}/board',
        query: sel == 'utama' ? null : {'board': sel},
      );
    } on KantorException {
      if (sel == 'utama') rethrow;
      // the remembered board is gone: back to the default one
      sel = 'utama';
      j = await _api.get('${kBase(officeId)}/board');
    }
    return kParseBoard(
      Map<String, dynamic>.from(j as Map),
      all: sel == kantorAllBoards,
    );
  }

  /// Quiet refetch: keeps the old board on screen if it fails.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {
      // keep what we have
    }
  }

  /// PATCH one card; the local copy is updated first via [local].
  Future<void> patchCard(
    String id,
    Map<String, dynamic> body, {
    KCard Function(KCard c)? local,
  }) async {
    final cur = state.value;
    if (cur != null && local != null) {
      state = AsyncData(
        cur.withCards([for (final c in cur.cards) c.id == id ? local(c) : c]),
      );
    }
    try {
      await _api.patch('${kBase(officeId)}/cards/$id', body);
    } finally {
      await refresh();
    }
  }

  /// Move cards to [col], between [prevId] and [nextId] (neighbours there).
  /// [col] is an index into the board's columns, or a column kind (all mode).
  Future<void> place(
    List<String> ids,
    Object col, {
    String? prevId,
    String? nextId,
    Map<String, dynamic> extra = const {},
  }) async {
    final cur = state.value;
    if (cur == null) return;
    final cards = [for (final i in ids) ?cur.map[i]];
    if (cards.isEmpty) return;
    final ords = kOrdsBetween(
      cur.map[prevId]?.ord,
      cur.map[nextId]?.ord,
      cards.length,
    );
    final jobs = <(String, Map<String, dynamic>)>[];
    final next = {for (final c in cur.cards) c.id: c};
    for (var k = 0; k < cards.length; k++) {
      final c = cards[k];
      final body = <String, dynamic>{'col': col, 'ord': ords[k], ...extra};
      final cols = cur.colsOf(c);
      final KCol? to = col is int
          ? (col >= 0 && col < cols.length ? cols[col] : null)
          : cols.where((x) => x.kind == col).firstOrNull;
      next[c.id] = c.copyWith(
        col: col is int ? col : (to == null ? null : cols.indexOf(to)),
        colName: to?.name,
        colKind: to?.kind ?? (col is String ? col : null),
        ord: ords[k],
        who: extra.containsKey('who') ? '${extra['who'] ?? ''}' : null,
        repo: extra.containsKey('repo') ? '${extra['repo'] ?? ''}' : null,
        epicId: extra.containsKey('epicId') ? '${extra['epicId'] ?? ''}' : null,
      );
      jobs.add((c.id, body));
    }
    state = AsyncData(cur.withCards(next.values.toList()));
    try {
      await Future.wait([
        for (final (id, body) in jobs)
          _api.patch('${kBase(officeId)}/cards/$id', body),
      ]);
    } finally {
      await refresh();
    }
  }

  Future<String> create(Map<String, dynamic> body) async {
    final r = await _api.post('${kBase(officeId)}/cards', body);
    await refresh();
    return '${(r as Map)['id']}';
  }

  Future<void> archive(String id) async {
    await _api.delete('${kBase(officeId)}/cards/$id');
    await refresh();
  }

  Future<void> reloadLabels() => refresh();

  /// `POST /boards`; returns the new board id.
  Future<String> createBoard(String name, String template) async {
    final r = await _api.post('${kBase(officeId)}/boards', {
      'name': name,
      'template': template,
    });
    ref.invalidate(kantorBoardsProvider(officeId));
    final m = r is Map ? r : const {};
    final b = m['board'];
    return '${b is Map ? b['id'] : m['id']}';
  }
}
