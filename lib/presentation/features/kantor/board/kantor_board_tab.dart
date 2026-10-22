import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'kantor_board_data.dart';
import 'kantor_board_filter.dart';
import 'kantor_board_lib.dart';
import 'kantor_board_sheets.dart';
import 'kantor_board_widgets.dart';
import 'kantor_calendar.dart';
import 'kantor_card_detail.dart';

const _quick = [
  ('mine', 'Kartu saya'),
  ('unassigned', 'Belum ditugaskan'),
  ('blocked', 'Terblokir'),
  ('waiting', 'Menunggu kartu lain'),
  ('hideOld', 'Sembunyikan Selesai lama'),
];

/// One swimlane of a grouped board: [key] goes into the PATCH on drop.
typedef _Lane = ({String key, String label});

/// One kanban column: [key] is the column index (one board) or the column
/// kind ("Semua papan"); it goes into the PATCH as `col`.
typedef _Col = ({Object key, String name, String kind});

const _kindNames = ['Antre', 'Siap', 'Dikerjakan', 'Review', 'Selesai'];

List<_Col> _colsOf(KBoard b) => b.all
    ? [
        for (var i = 0; i < kantorKinds.length; i++)
          (key: kantorKinds[i], name: _kindNames[i], kind: kantorKinds[i]),
      ]
    : [
        for (var i = 0; i < b.columns.length; i++)
          (key: i, name: b.columns[i].name, kind: b.columns[i].kind),
      ];

bool _isIn(KCard c, _Col col) =>
    col.key is int ? c.col == col.key : c.colKind == col.key;

/// Kanban + list of the office board. 1:1 with the web board tab.
class KantorBoardTab extends ConsumerStatefulWidget {
  const KantorBoardTab({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KantorBoardTab> createState() => _KantorBoardTabState();
}

class _KantorBoardTabState extends ConsumerState<KantorBoardTab> {
  final _search = TextEditingController();
  PageController? _pages;
  double _fraction = 0;
  final _scrolls = <int, ScrollController>{};
  Timer? _dragTimer;
  Offset _dragPos = Offset.zero;
  DateTime _lastPage = DateTime.fromMillisecondsSinceEpoch(0);
  bool _searchSynced = false;
  int _colCount = 5;

  String get id => widget.officeId;

  @override
  void dispose() {
    _dragTimer?.cancel();
    _search.dispose();
    _pages?.dispose();
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  ScrollController _scrollOf(int col) =>
      _scrolls.putIfAbsent(col, ScrollController.new);

  PageController _pagesFor(double fraction) {
    if (_pages == null || (_fraction - fraction).abs() > 0.001) {
      final old = _pages;
      final page = old != null && old.hasClients ? old.page?.round() ?? 0 : 0;
      _fraction = fraction;
      _pages = PageController(viewportFraction: fraction, initialPage: page);
      if (old != null)
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return _pages!;
  }

  /* ----- drag auto-scroll ----- */

  void _dragStart() {
    _dragTimer?.cancel();
    _dragTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _dragTick(),
    );
  }

  void _dragStop() {
    _dragTimer?.cancel();
    _dragTimer = null;
  }

  void _dragTick() {
    final size = MediaQuery.sizeOf(context);
    final p = _dragPos;
    final pc = _pages;
    if (pc != null && pc.hasClients) {
      final now = DateTime.now();
      if (now.difference(_lastPage).inMilliseconds > 550) {
        final page = pc.page?.round() ?? 0;
        if (p.dx < 48 && page > 0) {
          _lastPage = now;
          pc.animateToPage(
            page - 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else if (p.dx > size.width - 48 && page < _colCount - 1) {
          _lastPage = now;
          pc.animateToPage(
            page + 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
      final sc = _scrolls[pc.page?.round() ?? 0];
      if (sc != null && sc.hasClients) {
        final pos = sc.position;
        final box = context.findRenderObject() as RenderBox?;
        final top = box?.localToGlobal(Offset.zero).dy ?? 0;
        final h = box?.size.height ?? size.height;
        double d = 0;
        if (p.dy < top + 150 && p.dy > top - 40) {
          d = -14;
        } else if (p.dy > top + h - 90) {
          d = 14;
        }
        if (d != 0)
          pos.jumpTo(
            (pos.pixels + d).clamp(pos.minScrollExtent, pos.maxScrollExtent),
          );
      }
    }
  }

  /* ----- grouping ----- */

  List<String> _laneKeys(KCard c, String g, KBoard b) => switch (g) {
    'who' => [c.who.isEmpty ? kantorNone : c.who],
    'epic' => [
      c.epicId.isNotEmpty && b.map.containsKey(c.epicId)
          ? c.epicId
          : kantorNone,
    ],
    'prio' => [c.prio],
    'label' => () {
      final ls = c.labels.where((l) => b.label(l) != null).toList();
      return ls.isEmpty ? [kantorNone] : ls;
    }(),
    'repo' => [c.repo.isEmpty ? kantorNone : c.repo],
    _ => const [''],
  };

  List<_Lane> _lanes(List<KCard> cards, String g, KBoard b, KOffice? o) {
    if (g == 'none') return const [(key: '', label: '')];
    final used = <String>{for (final c in cards) ..._laneKeys(c, g, b)};
    final order = switch (g) {
      'who' => [...?o?.activeRoles.map((r) => r.id), ...used, kantorNone],
      'epic' => [...b.epics.map((e) => e.id), ...used, kantorNone],
      'prio' => [...kantorPrios],
      'label' => [...b.labels.map((l) => l.id), kantorNone],
      _ => [
        ...?o?.rooms.where((r) => r.isRepo).map((r) => r.id),
        ...used,
        kantorNone,
      ],
    };
    String name(String k) {
      if (k == kantorNone) {
        return switch (g) {
          'who' => 'Belum ditugaskan',
          'epic' => 'Tanpa epic',
          'label' => 'Tanpa label',
          _ => 'Tanpa repo',
        };
      }
      return switch (g) {
        'who' => o?.whoName(k) ?? k,
        'epic' => b.map[k]?.title ?? k,
        'label' => b.labelName(k),
        'repo' => o?.repoName(k) ?? k,
        _ => k,
      };
    }

    final seen = <String>{};
    return [
      for (final k in order)
        if (used.contains(k) && seen.add(k)) (key: k, label: name(k)),
    ];
  }

  Map<String, dynamic> _laneBody(String g, String key) => switch (g) {
    'who' => {'who': key == kantorNone ? null : key},
    'epic' => {'epicId': key == kantorNone ? '' : key},
    'prio' => {'prio': key},
    'repo' => {'repo': key == kantorNone ? '' : key},
    _ => const {},
  };

  /* ----- actions ----- */

  Future<void> _drop(
    KCard moved,
    Object col,
    KCard? before,
    KFilter f,
    String? lane,
    List<KCard> colCards,
  ) async {
    final notifier = ref.read(kantorBoardProvider(id).notifier);
    final siblings = colCards.where((c) => c.id != moved.id).toList();
    String? prev, next;
    if (before == null) {
      prev = siblings.lastOrNull?.id;
    } else {
      final i = siblings.indexWhere((c) => c.id == before.id);
      next = before.id;
      if (i > 0) prev = siblings[i - 1].id;
    }
    final extra = <String, dynamic>{};
    if (lane != null && f.group != 'none' && f.group != 'label') {
      extra.addAll(_laneBody(f.group, lane));
    }
    try {
      await notifier.place(
        [moved.id],
        col,
        prevId: prev,
        nextId: next,
        extra: extra,
      );
    } catch (e) {
      if (mounted) kToast(context, '$e', bad: true);
    }
  }

  /// Quick add into [col] of the shown board ("Semua papan": the default
  /// board's first column of that kind).
  void _quickAdd(KBoard b, _Col? col) {
    if (!b.all) {
      showKantorQuickAdd(
        context,
        officeId: id,
        col: (col?.key as int?) ?? 0,
        colName: col?.name ?? b.columns.firstOrNull?.name,
        boardId: b.board?.id,
      );
      return;
    }
    final def =
        b.boards.where((x) => x.isDefault).firstOrNull ??
        b.activeBoards.firstOrNull;
    final cols = def?.columns ?? kantorDefaultColumns;
    final i = col == null ? 0 : cols.indexWhere((c) => c.kind == col.kind);
    showKantorQuickAdd(
      context,
      officeId: id,
      col: i < 0 ? 0 : i,
      colName: cols.isEmpty ? null : cols[i < 0 ? 0 : i].name,
      boardId: def?.id,
    );
  }

  Future<void> _newBoard() async {
    final name = TextEditingController();
    var tpl = 'dev';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Papan baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Nama papan'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (k, l) in const [
                    ('dev', 'Dev'),
                    ('kreatif', 'Kreatif'),
                  ])
                    ChunkyChip(
                      label: l,
                      selected: tpl == k,
                      onTap: () => set(() => tpl = k),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok != true || n.isEmpty || !mounted) return;
    try {
      final bid = await ref
          .read(kantorBoardProvider(id).notifier)
          .createBoard(n, tpl);
      if (bid.isNotEmpty && bid != 'null') {
        ref.read(kantorBoardSelProvider(id).notifier).select(bid);
      }
    } catch (e) {
      if (mounted) kToast(context, '$e', bad: true);
    }
  }

  Widget _boardBar(KBoard b) {
    final sel = ref.watch(kantorBoardSelProvider(id));
    final n = ref.read(kantorBoardSelProvider(id).notifier);
    return KChipStrip(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      children: [
        for (final d in b.activeBoards)
          ChunkyChip(
            label: d.icon.isEmpty ? d.name : '${d.icon} ${d.name}',
            selected: sel == d.id,
            onTap: () => n.select(d.id),
          ),
        ChunkyChip(
          label: 'Semua papan',
          icon: Icons.dashboard_rounded,
          selected: sel == kantorAllBoards,
          onTap: () => n.select(kantorAllBoards),
        ),
        ChunkyChip(
          label: 'Papan',
          icon: Icons.add_rounded,
          selected: false,
          onTap: _newBoard,
        ),
      ],
    );
  }

  Future<void> _setMine(KFilter f, KOffice? office, bool on) async {
    final n = ref.read(kantorFilterProvider(id).notifier);
    if (!on) {
      n.update((x) => x.copyWith(mine: false));
      return;
    }
    var me = f.me;
    if (me.isEmpty && office != null) {
      me = await kPickMe(context, office, '') ?? '';
      if (me.isEmpty) return;
    }
    n.update((x) => x.copyWith(mine: true, me: me));
  }

  bool _quickOn(KFilter f, String k) => switch (k) {
    'mine' => f.mine,
    'unassigned' => f.unassigned,
    'blocked' => f.blocked,
    'waiting' => f.waiting,
    _ => f.hideOld,
  };

  void _toggleQuick(KFilter f, String k, KOffice? office) {
    final n = ref.read(kantorFilterProvider(id).notifier);
    final on = !_quickOn(f, k);
    switch (k) {
      case 'mine':
        _setMine(f, office, on);
      case 'unassigned':
        n.update((x) => x.copyWith(unassigned: on));
      case 'blocked':
        n.update((x) => x.copyWith(blocked: on));
      case 'waiting':
        n.update((x) => x.copyWith(waiting: on));
      default:
        n.update((x) => x.copyWith(hideOld: on));
    }
  }

  /* ----- build ----- */

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(kantorBoardProvider(id));
    final office = ref.watch(kantorOfficeProvider(id)).value;
    final f = ref.watch(kantorFilterProvider(id));
    if (!_searchSynced && f.q.isNotEmpty) {
      _search.text = f.q;
      _searchSynced = true;
    }
    return boardAsync.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kantorBoardProvider(id)),
      ),
      data: (board) {
        final cards = board.cards
            .where(
              (c) =>
                  !c.epic &&
                  kMatchCard(c, f, map: board.map, labelName: board.labelName),
            )
            .toList();
        return Column(
          children: [
            if (board.boards.isNotEmpty) _boardBar(board),
            _toolbar(f, board, office),
            _quickBar(f, office),
            Expanded(
              child: cards.isEmpty && board.cards.isEmpty
                  ? EmptyState(
                      title: 'Board masih kosong',
                      message: 'Buat kartu pertama, yuk!',
                      actionLabel: 'Buat kartu',
                      onAction: () => _quickAdd(board, null),
                    )
                  : f.list
                  ? _listView(cards, board, office, f)
                  : _kanban(cards, board, office, f),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(KFilter f, KBoard board, KOffice? office) {
    final g = context.ghina;
    final n = ref.read(kantorFilterProvider(id).notifier);
    final other =
        f.activeCount -
        [
          f.mine,
          f.unassigned,
          f.blocked,
          f.waiting,
          f.hideOld,
        ].where((b) => b).length -
        (f.q.trim().isEmpty ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => n.update((x) => x.copyWith(q: v)),
              decoration: InputDecoration(
                hintText: 'Cari kartu',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: f.q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          n.update((x) => x.copyWith(q: ''));
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Badge(
            isLabelVisible: other > 0 || f.group != 'none',
            label: Text(other > 0 ? '$other' : '•'),
            child: IconButton(
              tooltip: 'Filter dan kelompok',
              icon: Icon(Icons.tune_rounded, color: g.textSecondary),
              onPressed: () => showKantorFilterSheet(context, officeId: id),
            ),
          ),
          IconButton(
            tooltip: f.list ? 'Tampilan papan' : 'Tampilan daftar',
            icon: Icon(
              f.list ? Icons.view_kanban_rounded : Icons.view_list_rounded,
              color: g.textSecondary,
            ),
            onPressed: () => n.update((x) => x.copyWith(list: !x.list)),
          ),
          IconButton(
            tooltip: 'Kalender tayang',
            icon: Icon(Icons.calendar_month_rounded, color: g.textSecondary),
            onPressed: () => openKantorCalendar(context, officeId: id),
          ),
          IconButton(
            tooltip: 'Kartu baru',
            icon: Icon(Icons.add_circle_rounded, color: GhinaColors.green.base),
            onPressed: () => _quickAdd(board, null),
          ),
        ],
      ),
    );
  }

  Widget _quickBar(KFilter f, KOffice? office) {
    return KChipStrip(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      children: [
        for (final (k, label) in _quick)
          ChunkyChip(
            label: label,
            selected: _quickOn(f, k),
            onTap: () => _toggleQuick(f, k, office),
          ),
        if (f.activeCount > 0)
          ChunkyChip(
            label: 'Reset',
            selected: false,
            icon: Icons.close_rounded,
            onTap: () {
              _search.clear();
              ref.read(kantorFilterProvider(id).notifier).clear();
            },
          ),
      ],
    );
  }

  /* ----- kanban ----- */

  Widget _kanban(List<KCard> cards, KBoard board, KOffice? office, KFilter f) {
    final width = MediaQuery.sizeOf(context).width;
    final fraction = width > 600 ? (330 / width).clamp(0.2, 0.9) : 0.88;
    final pc = _pagesFor(fraction);
    final cols = _colsOf(board);
    _colCount = cols.length;
    return PageView.builder(
      controller: pc,
      padEnds: false,
      itemCount: cols.length,
      itemBuilder: (_, i) => _column(i, cols[i], cards, board, office, f),
    );
  }

  Widget _column(
    int page,
    _Col colDef,
    List<KCard> all,
    KBoard board,
    KOffice? office,
    KFilter f,
  ) {
    final g = context.ghina;
    final col = colDef.key;
    final here = all.where((c) => _isIn(c, colDef)).toList()
      ..sort((a, b) => a.ord.compareTo(b.ord));
    final wip = board.all ? 0 : (kantorKindWip[colDef.kind] ?? 0);
    final over = wip > 0 && here.length > wip;
    final lanes = _lanes(here, f.group, board, office);
    final laneIndex = {for (var i = 0; i < lanes.length; i++) lanes[i].key: i};
    // Each entry is a card with its lane (a label-grouped card may repeat).
    final entries =
        <({KCard card, String lane})>[
          for (final c in here)
            for (final k in _laneKeys(c, f.group, board)) (card: c, lane: k),
        ]..sort((a, b) {
          final d = (laneIndex[a.lane] ?? 0) - (laneIndex[b.lane] ?? 0);
          return d != 0 ? d : a.card.ord.compareTo(b.card.ord);
        });
    final sw = kKindSwatch(colDef.kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rLg,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: sw.base,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      colDef.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChunkyPill(
                    label: wip > 0 ? '${here.length}/$wip' : '${here.length}',
                    color: over ? GhinaColors.red : GhinaColors.gray,
                    soft: !over,
                    uppercase: false,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Tambah kartu di ${colDef.name}',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => _quickAdd(board, colDef),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollOf(page),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  if (entries.isEmpty)
                    _emptyDrop(col, f, here)
                  else
                    ..._columnItems(
                      col,
                      entries,
                      lanes,
                      f,
                      board,
                      office,
                      here,
                    ),
                  _endDrop(col, f, here),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _columnItems(
    Object col,
    List<({KCard card, String lane})> entries,
    List<_Lane> lanes,
    KFilter f,
    KBoard board,
    KOffice? office,
    List<KCard> colCards,
  ) {
    final out = <Widget>[];
    String? lastLane;
    for (final e in entries) {
      if (f.group != 'none' && e.lane != lastLane) {
        final l = lanes.firstWhere(
          (x) => x.key == e.lane,
          orElse: () => (key: e.lane, label: e.lane),
        );
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              l.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.overline.copyWith(
                color: context.ghina.textMuted,
              ),
            ),
          ),
        );
        lastLane = e.lane;
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _draggable(e.card, col, e.lane, f, board, office, colCards),
        ),
      );
    }
    return out;
  }

  Widget _tile(
    KCard c,
    KBoard board,
    KOffice? office, {
    bool compact = false,
  }) => KCardTile(
    card: c,
    board: board,
    office: office,
    compact: compact,
    onTap: () => openKantorCard(context, officeId: id, cardId: c.id),
    onMore: () => showKantorCardActions(
      context,
      ref,
      officeId: id,
      card: c,
      office: office,
    ),
  );

  Widget _draggable(
    KCard c,
    Object col,
    String lane,
    KFilter f,
    KBoard board,
    KOffice? office,
    List<KCard> colCards,
  ) {
    final width = MediaQuery.sizeOf(context).width * _fraction;
    return DragTarget<KCard>(
      onWillAcceptWithDetails: (d) => d.data.id != c.id,
      onAcceptWithDetails: (d) => _drop(d.data, col, c, f, lane, colCards),
      builder: (ctx, cand, _) => Column(
        children: [
          if (cand.isNotEmpty)
            Container(
              height: 4,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: GhinaColors.blue.base,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          LongPressDraggable<KCard>(
            data: c,
            delay: const Duration(milliseconds: 280),
            hapticFeedbackOnStart: true,
            onDragStarted: _dragStart,
            onDragUpdate: (d) => _dragPos = d.globalPosition,
            onDragEnd: (_) => _dragStop(),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.92,
                child: SizedBox(
                  width: (width - 28).clamp(220, 360),
                  child: _tile(c, board, office, compact: true),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: _tile(c, board, office),
            ),
            child: _tile(c, board, office),
          ),
        ],
      ),
    );
  }

  Widget _endDrop(Object col, KFilter f, List<KCard> here) => DragTarget<KCard>(
    onWillAcceptWithDetails: (_) => true,
    onAcceptWithDetails: (d) => _drop(d.data, col, null, f, null, here),
    builder: (ctx, cand, _) => AnimatedContainer(
      duration: GhinaMotion.fast,
      height: cand.isNotEmpty ? 90 : 56,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        borderRadius: GhinaRadii.rMd,
        border: cand.isNotEmpty
            ? Border.all(color: GhinaColors.blue.base, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: cand.isNotEmpty
          ? Text(
              'Taruh di sini',
              style: GhinaType.bodyS.copyWith(color: GhinaColors.blue.base),
            )
          : null,
    ),
  );

  Widget _emptyDrop(Object col, KFilter f, List<KCard> here) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        'Belum ada kartu',
        style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
      ),
    ),
  );

  /* ----- list ----- */

  Widget _listView(
    List<KCard> cards,
    KBoard board,
    KOffice? office,
    KFilter f,
  ) {
    final g = context.ghina;
    if (cards.isEmpty) {
      return const EmptyState(
        title: 'Tidak ada kartu yang cocok',
        message: 'Coba longgarkan filter.',
        compact: true,
      );
    }
    final lanes = _lanes(cards, f.group, board, office);
    final children = <Widget>[];
    for (final l in lanes) {
      if (f.group != 'none') {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(
              l.label.toUpperCase(),
              style: GhinaType.overline.copyWith(color: g.textMuted),
            ),
          ),
        );
      }
      final inLane =
          cards
              .where((c) => _laneKeys(c, f.group, board).contains(l.key))
              .toList()
            ..sort((a, b) {
              if (board.all && a.board != b.board) {
                final x = board.boards.indexWhere((d) => d.id == a.board);
                final y = board.boards.indexWhere((d) => d.id == b.board);
                return x != y ? x - y : a.board.compareTo(b.board);
              }
              return a.col != b.col ? a.col - b.col : a.ord.compareTo(b.ord);
            });
      String? lastCol;
      for (final c in inLane) {
        final head = board.all
            ? '${board.boardDef(c.board)?.name ?? c.board} · ${board.colNameOf(c)}'
            : board.colNameOf(c);
        if ('${c.board}/${c.col}' != lastCol) {
          lastCol = '${c.board}/${c.col}';
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: kKindSwatch(c.colKind).base,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    head,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _tile(c, board, office, compact: true),
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: children,
    );
  }
}
