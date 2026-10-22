import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/design_system.dart';
import '../board/kantor_board_data.dart';
import '../board/kantor_board_lib.dart';
import '../board/kantor_board_widgets.dart';
import '../board/kantor_card_detail.dart';
import '../widgets/kantor_states.dart';
import 'kantor_timeline_lib.dart';

const _rowH = 38.0;
const _headH = 52.0;
const _barT = 7.0;
const _barH = 24.0;
const _nameW = 128.0;

const _groups = [
  ('epic', 'Epic'),
  ('who', 'Orang'),
  ('repo', 'Repo'),
  ('label', 'Label'),
  ('none', 'Tanpa'),
];

class _Row {
  _Row.group(this.title, this.key, this.items, {this.role, this.color})
    : card = null;
  _Row.card(KCard this.card, this.key)
    : title = card.title,
      items = const [],
      role = null,
      color = null;
  final String title;
  final String key;
  final KCard? card;
  final List<KCard> items;
  final KRole? role;
  final String? color;
  bool get isGroup => card == null;
}

/// Gantt of the board's cards: bars by date, zoomable, long-press to move,
/// drag the ends to resize, tap to open the card.
class KantorTimelineTab extends ConsumerStatefulWidget {
  const KantorTimelineTab({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KantorTimelineTab> createState() => _KantorTimelineTabState();
}

class _KantorTimelineTabState extends ConsumerState<KantorTimelineTab> {
  String _zoom = 'week';
  String _group = 'epic';
  String _color = 'col';
  String _who = '';
  String _label = '';
  bool _hideDone = false;
  bool _crit = false;
  final _collapsed = <String>{};
  final _ov = <String, GSpan>{};

  final _hBars = ScrollController();
  final _hHead = ScrollController();
  final _vert = ScrollController();
  bool _scrolledToday = false;
  double _viewW = 300;

  String get id => widget.officeId;
  double get _dw => kZooms[_zoom]!;
  String get _prefKey => 'kantor.gantt.$id';

  @override
  void initState() {
    super.initState();
    _hBars.addListener(() {
      if (_hHead.hasClients && _hHead.offset != _hBars.offset) {
        _hHead.jumpTo(_hBars.offset.clamp(0, _hHead.position.maxScrollExtent));
      }
    });
    _loadPrefs();
  }

  @override
  void dispose() {
    _hBars.dispose();
    _hHead.dispose();
    _vert.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        if (kZooms.containsKey(j['zoom'])) _zoom = j['zoom'] as String;
        if (_groups.any((g) => g.$1 == j['group']))
          _group = j['group'] as String;
        if (j['color'] == 'col' || j['color'] == 'who')
          _color = j['color'] as String;
        _hideDone = j['hideDone'] == true;
        _crit = j['crit'] == true;
        _collapsed.addAll([
          for (final x in (j['collapsed'] as List? ?? const [])) '$x',
        ]);
      });
    } catch (_) {
      // defaults
    }
  }

  void _savePrefs() {
    SharedPreferences.getInstance()
        .then(
          (p) => p.setString(
            _prefKey,
            jsonEncode({
              'zoom': _zoom,
              'group': _group,
              'color': _color,
              'hideDone': _hideDone,
              'crit': _crit,
              'collapsed': _collapsed.toList(),
            }),
          ),
        )
        .catchError((_) => false);
  }

  /* ----- model ----- */

  GSpan? _span(KCard c) => ganttSpan(c, override: _ov[c.id]);

  List<KCard> _real(KBoard b) => [
    for (final c in b.cards)
      if (!c.epic) c,
  ];

  bool _passes(KCard c) =>
      (_who.isEmpty || (_who == kantorNone ? c.who.isEmpty : c.who == _who)) &&
      (_label.isEmpty || c.labels.contains(_label)) &&
      !(_hideDone && c.done);

  int _byStart(KCard a, KCard b, Map<String, GSpan?> sp) {
    final x = sp[a.id]!, y = sp[b.id]!;
    return x.s != y.s
        ? x.s - y.s
        : x.e != y.e
        ? x.e - y.e
        : a.title.compareTo(b.title);
  }

  List<_Row> _rows(KBoard b, KOffice? o, Map<String, GSpan?> sp) {
    final items = [
      for (final c in _real(b))
        if (sp[c.id] != null && _passes(c)) c,
    ];
    final groups = <_Row>[];
    switch (_group) {
      case 'epic':
        final epics = b.epics;
        final ids = {for (final e in epics) e.id};
        for (final e in epics) {
          groups.add(
            _Row.group(e.title, 'e:${e.id}', [
              for (final c in items)
                if (c.epicId == e.id) c,
            ]),
          );
        }
        groups.add(
          _Row.group('Tanpa epic', 'e:_', [
            for (final c in items)
              if (c.epicId.isEmpty || !ids.contains(c.epicId)) c,
          ]),
        );
      case 'who':
        for (final r in o?.activeRoles ?? <KRole>[]) {
          groups.add(
            _Row.group(r.name, 'w:${r.id}', [
              for (final c in items)
                if (c.who == r.id) c,
            ], role: r),
          );
        }
        groups.add(
          _Row.group('Belum ditugaskan', 'w:_', [
            for (final c in items)
              if (c.who.isEmpty || o?.role(c.who) == null) c,
          ]),
        );
      case 'repo':
        final keys = {for (final c in items) c.repo}.toList()
          ..sort(
            (a, b) => (o?.repoName(a) ?? a).compareTo(o?.repoName(b) ?? b),
          );
        for (final k in keys) {
          groups.add(
            _Row.group(o?.repoName(k) ?? k, 'r:$k', [
              for (final c in items)
                if (c.repo == k) c,
            ]),
          );
        }
      case 'label':
        for (final l in b.labels) {
          groups.add(
            _Row.group(l.name, 'l:${l.id}', [
              for (final c in items)
                if (c.labels.firstOrNull == l.id) c,
            ], color: l.color),
          );
        }
        groups.add(
          _Row.group('Tanpa label', 'l:_', [
            for (final c in items)
              if (!c.labels.any((x) => b.label(x) != null)) c,
          ]),
        );
      default:
        groups.add(_Row.group('', 'n', items));
    }
    final list = groups.where((g) => g.items.isNotEmpty).toList();
    if (_group == 'epic' || _group == 'repo') {
      int start(_Row g) => g.items.map((c) => sp[c.id]!.s).reduce(math.min);
      list.sort((a, b) => start(a) - start(b));
    }
    final rows = <_Row>[];
    for (final g in list) {
      g.items.sort((a, b) => _byStart(a, b, sp));
      if (_group != 'none') rows.add(g);
      if (_group != 'none' && _collapsed.contains(g.key)) continue;
      for (final c in g.items) {
        rows.add(_Row.card(c, g.key));
      }
    }
    return rows;
  }

  /* ----- actions ----- */

  Future<void> _patch(String cardId, Map<String, dynamic> body) async {
    try {
      await ref.read(kantorBoardProvider(id).notifier).patchCard(cardId, body);
    } catch (e) {
      if (mounted) kToast(context, '$e', bad: true);
    } finally {
      if (mounted) setState(() => _ov.remove(cardId));
    }
  }

  void _commit(KCard c) {
    final o = _ov[c.id];
    if (o == null) return;
    _patch(c.id, {'start': ganttFormat(o.s), 'due': ganttFormat(o.e)});
  }

  Future<void> _autoShift(List<KCard> cards, Map<String, GSpan?> sp) async {
    final sh = ganttPlanShift(cards, sp);
    if (sh.isEmpty) return;
    final ok = await showChunkyConfirm(
      context,
      title: 'Geser otomatis?',
      message:
          '${sh.length} kartu digeser supaya tidak mulai sebelum kartu yang ditunggunya selesai.',
      confirmLabel: 'Geser',
    );
    if (ok != true) return;
    final byId = {for (final c in cards) c.id: c};
    for (final e in sh.entries) {
      final s = sp[e.key]!;
      if (byId[e.key] == null) continue;
      await _patch(e.key, {
        'start': ganttFormat(s.s + e.value),
        'due': ganttFormat(s.e + e.value),
      });
    }
  }

  Future<void> _schedule(KCard c) async {
    final t = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: t,
        end: t.add(const Duration(days: 2)),
      ),
    );
    if (r != null)
      await _patch(c.id, {'start': kDayStr(r.start), 'due': kDayStr(r.end)});
  }

  void _setZoom(String z, int lo) {
    // Keep the middle of the screen where it was.
    final centerDay =
        lo + (_hBars.hasClients ? _hBars.offset + _viewW / 2 : 0) / _dw;
    setState(() => _zoom = z);
    _savePrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hBars.hasClients) return;
      final off = (centerDay - lo) * _dw - _viewW / 2;
      _hBars.jumpTo(off.clamp(0, _hBars.position.maxScrollExtent));
    });
  }

  void _goToday(int lo) {
    if (!_hBars.hasClients) return;
    final off = (ganttToday() - lo) * _dw - _viewW / 3;
    _hBars.animateTo(
      off.clamp(0, _hBars.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /* ----- build ----- */

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kantorBoardProvider(id));
    final office = ref.watch(kantorOfficeProvider(id)).value;
    return async.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kantorBoardProvider(id)),
      ),
      data: (board) => board.boards.isEmpty
          ? _content(board, office)
          : Column(
              children: [
                _boardBar(board),
                Expanded(child: _content(board, office)),
              ],
            ),
    );
  }

  /// Board switcher (shared with the board tab's selection).
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
      ],
    );
  }

  Widget _content(KBoard board, KOffice? office) {
    final g = context.ghina;
    final real = _real(board);
    final sp = <String, GSpan?>{for (final c in board.cards) c.id: _span(c)};
    final scheduled = [
      for (final c in real)
        if (sp[c.id] != null) c,
    ];
    if (scheduled.isEmpty && real.isNotEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              title: 'Belum ada kartu terjadwal',
              message:
                  'Isi tanggal mulai atau tenggat di kartu, nanti muncul di sini.',
              compact: true,
            ),
          ),
          _unscheduled(real, sp, board, office),
        ],
      );
    }
    final rows = _rows(board, office, sp);
    final conflicts = ganttConflicts(board.cards, sp);
    final conflictTo = {for (final c in conflicts) c.to};
    final crit = _crit
        ? ganttCritical(board.cards, sp)
        : (ids: <String>{}, edges: <String>{});

    // Range: from a Monday a week before the first bar to four weeks past the last.
    final spans = [for (final c in scheduled) sp[c.id]!];
    final t = ganttToday();
    var lo =
        (spans.isEmpty
            ? t
            : math.min(t, spans.map((s) => s.s).reduce(math.min))) -
        7;
    final hi =
        (spans.isEmpty
            ? t
            : math.max(t, spans.map((s) => s.e).reduce(math.max))) +
        28;
    lo -= (ganttDow(lo) + 6) % 7;
    final width = MediaQuery.sizeOf(context).width;
    _viewW = math.max(200, width - _nameW);
    final days = math.max(hi - lo + 1, (_viewW / _dw).ceil() + 2);
    final totalW = days * _dw;
    final bodyH = rows.length * _rowH;

    if (!_scrolledToday) {
      _scrolledToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToday(lo));
    }

    final overdue = scheduled
        .where((c) => !c.done && sp[c.id]!.e < t)
        .length;
    final unsched = real.where((c) => sp[c.id] == null).length;

    return Column(
      children: [
        _toolbar(lo, board, office),
        KChipStrip(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          gap: 0,
          children: [
            _pill('${scheduled.length}', 'terjadwal', false),
            _pill('$overdue', 'terlambat', overdue > 0),
            _pill('${conflicts.length}', 'konflik', conflicts.isNotEmpty),
            _pill('$unsched', 'belum dijadwalkan', false),
            if (conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChunkyButton(
                  label: 'Geser otomatis',
                  size: ChunkyButtonSize.small,
                  expand: false,
                  onPressed: () => _autoShift(board.cards, sp),
                ),
              ),
          ],
        ),
        // Header: dates scroll with the bars.
        SizedBox(
          height: _headH,
          child: Row(
            children: [
              Container(
                width: _nameW,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'TUGAS',
                  style: GhinaType.overline.copyWith(color: g.textMuted),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hHead,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: CustomPaint(
                    size: Size(totalW, _headH),
                    painter: _HeadPainter(
                      lo: lo,
                      days: days,
                      dw: _dw,
                      zoom: _zoom,
                      g: g,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: g.border),
        Expanded(
          child: SingleChildScrollView(
            controller: _vert,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _nameW,
                      child: Column(
                        children: [
                          for (final r in rows) _nameCell(r, board, office),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _hBars,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalW,
                          height: math.max(bodyH, 1),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _GridPainter(
                                    rows: rows,
                                    spans: sp,
                                    cards: board.map,
                                    lo: lo,
                                    days: days,
                                    dw: _dw,
                                    zoom: _zoom,
                                    g: g,
                                    conflicts: {
                                      for (final c in conflicts)
                                        '${c.from}>${c.to}',
                                    },
                                    crit: crit,
                                    critOn: _crit,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < rows.length; i++)
                                if (!rows[i].isGroup)
                                  _bar(
                                    rows[i].card!,
                                    i,
                                    lo,
                                    sp[rows[i].card!.id]!,
                                    office,
                                    conflictTo,
                                    crit,
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _legend(office, board),
                _unscheduled(real, sp, board, office),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String n, String label, bool bad) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChunkyPill(
      label: '$n $label',
      color: bad ? GhinaColors.red : GhinaColors.gray,
      soft: true,
      uppercase: false,
    ),
  );

  Widget _toolbar(int lo, KBoard board, KOffice? office) {
    final active =
        (_who.isNotEmpty ? 1 : 0) +
        (_label.isNotEmpty ? 1 : 0) +
        (_hideDone ? 1 : 0) +
        (_crit ? 1 : 0);
    return Row(
      children: [
        Expanded(
          child: KChipStrip(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            children: [
              for (final (k, n) in kZoomNames)
                ChunkyChip(
                  label: n,
                  selected: _zoom == k,
                  onTap: () => _setZoom(k, lo),
                ),
              ChunkyChip(
                label: 'Hari ini',
                selected: false,
                icon: Icons.today_rounded,
                onTap: () => _goToday(lo),
              ),
            ],
          ),
        ),
        Badge(
          isLabelVisible: active > 0,
          label: Text('$active'),
          child: IconButton(
            tooltip: 'Kelompok dan filter',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _options(board, office),
          ),
        ),
      ],
    );
  }

  void _options(KBoard board, KOffice? office) {
    showChunkyBottomSheet<void>(
      context,
      title: 'Timeline',
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void upd(VoidCallback f) {
            setState(f);
            setSheet(() {});
            _savePrefs();
          }

          Widget head(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              t,
              style: GhinaType.overline.copyWith(color: ctx.ghina.textMuted),
            ),
          );
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  head('KELOMPOK'),
                  ChunkyChoiceChips<String>(
                    options: [
                      for (final (k, n) in _groups)
                        ChunkyChoice(value: k, label: n),
                    ],
                    selected: {_group},
                    onChanged: (s) => upd(() => _group = s.first),
                  ),
                  head('WARNA BAR'),
                  ChunkyChoiceChips<String>(
                    options: const [
                      ChunkyChoice(value: 'col', label: 'Status'),
                      ChunkyChoice(value: 'who', label: 'Orang'),
                    ],
                    selected: {_color},
                    onChanged: (s) => upd(() => _color = s.first),
                  ),
                  head('ORANG'),
                  ChunkyChoiceChips<String>(
                    options: [
                      const ChunkyChoice(value: '', label: 'Semua'),
                      const ChunkyChoice(
                        value: kantorNone,
                        label: 'Belum ditugaskan',
                      ),
                      for (final r in office?.activeRoles ?? <KRole>[])
                        ChunkyChoice(value: r.id, label: r.name),
                    ],
                    selected: {_who},
                    onChanged: (s) => upd(() => _who = s.first),
                  ),
                  if (board.labels.isNotEmpty) ...[
                    head('LABEL'),
                    ChunkyChoiceChips<String>(
                      options: [
                        const ChunkyChoice(value: '', label: 'Semua'),
                        for (final l in board.labels)
                          ChunkyChoice(value: l.id, label: l.name),
                      ],
                      selected: {_label},
                      onChanged: (s) => upd(() => _label = s.first),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sembunyikan Selesai'),
                    value: _hideDone,
                    onChanged: (v) => upd(() => _hideDone = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Jalur kritis'),
                    value: _crit,
                    onChanged: (v) => upd(() => _crit = v),
                  ),
                  const SizedBox(height: 8),
                  ChunkyButton(
                    label: 'Selesai',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _nameCell(_Row r, KBoard board, KOffice? office) {
    final g = context.ghina;
    if (r.isGroup) {
      final open = !_collapsed.contains(r.key);
      return InkWell(
        onTap: () {
          setState(
            () => open ? _collapsed.add(r.key) : _collapsed.remove(r.key),
          );
          _savePrefs();
        },
        child: Container(
          height: _rowH,
          padding: const EdgeInsets.only(left: 6, right: 6),
          color: g.surfaceAlt,
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                size: 18,
                color: g.textMuted,
              ),
              if (r.role != null) ...[
                KantorSpriteBox(role: r.role!, office: office),
                const SizedBox(width: 4),
              ] else if (r.color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: kHex(r.color!),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              Text(
                '${r.items.length}',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    final c = r.card!;
    return InkWell(
      onTap: () => openKantorCard(context, officeId: id, cardId: c.id),
      child: Container(
        height: _rowH,
        padding: EdgeInsets.only(left: _group == 'none' ? 10 : 22, right: 6),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption.copyWith(
                  color: g.textPrimary,
                  height: 1.15,
                ),
              ),
            ),
            if (c.who.isNotEmpty)
              KWhoAvatar(office: office, who: c.who, size: 20),
          ],
        ),
      ),
    );
  }

  Color _barColor(KCard c, KOffice? o) {
    if (_color == 'who') {
      final hex = o?.role(c.who)?.raw['color'];
      if (hex is String) return kHex(hex);
      return GhinaColors.gray.base;
    }
    return kKindSwatch(c.colKind).base;
  }

  Widget _bar(
    KCard c,
    int row,
    int lo,
    GSpan s,
    KOffice? office,
    Set<String> conflictTo,
    ({Set<String> ids, Set<String> edges}) crit,
  ) {
    final top = row * _rowH + _barT;
    final color = _barColor(c, office);
    final done = c.done;
    final late = !done && s.e < ganttToday();
    final dimmed = _crit && !crit.ids.contains(c.id);
    final conflict = conflictTo.contains(c.id);
    void open() => openKantorCard(context, officeId: id, cardId: c.id);
    if (s.milestone) {
      final cx = (s.s - lo) * _dw + _dw / 2;
      return Positioned(
        left: cx - 14,
        top: top - 2,
        width: 28,
        height: _barH + 4,
        child: GestureDetector(
          onTap: open,
          behavior: HitTestBehavior.opaque,
          child: Opacity(
            opacity: dimmed ? 0.35 : 1,
            child: Center(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: done ? color.withValues(alpha: 0.5) : color,
                    border: Border.all(
                      color: late ? GhinaColors.red.base : color,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final w = (s.e - s.s + 1) * _dw;
    final p = ganttProgress(c);
    final ink = color.computeLuminance() > 0.6
        ? const Color(0xFF1F1628)
        : Colors.white;
    final canResize = w >= 36;
    return Positioned(
      left: (s.s - lo) * _dw,
      top: top,
      width: w,
      height: _barH,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: open,
                onLongPressStart: (_) {
                  _dragBase[c.id] = s;
                  setState(() => _ov[c.id] = s);
                },
                onLongPressMoveUpdate: (d) {
                  final base = _ovBase(c, s);
                  final n = (d.offsetFromOrigin.dx / _dw).round();
                  setState(() => _ov[c.id] = GSpan(base.s + n, base.e + n));
                },
                onLongPressEnd: (_) {
                  _dragBase.remove(c.id);
                  _commit(c);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: done
                          ? 0.45
                          : s.derived
                          ? 0.55
                          : 0.9,
                    ),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: conflict
                          ? GhinaColors.red.base
                          : late
                          ? GhinaColors.red.base
                          : c.blocked.isNotEmpty
                          ? GhinaColors.orange.base
                          : _crit && crit.ids.contains(c.id)
                          ? GhinaColors.yellow.base
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: p / 100,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.22),
                        ),
                      ),
                      if (w >= 60)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption
                                  .w(700)
                                  .copyWith(color: ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (canResize) ...[
              _handle(c, s, left: true),
              _handle(c, s, left: false),
            ],
          ],
        ),
      ),
    );
  }

  /// Span the current gesture started from (the override may already differ).
  GSpan _ovBase(KCard c, GSpan fallback) => _dragBase[c.id] ?? fallback;
  final _dragBase = <String, GSpan>{};

  Widget _handle(KCard c, GSpan s, {required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _dragBase[c.id] = s;
          _dragDx[c.id] = 0;
        },
        onHorizontalDragUpdate: (d) {
          final base = _dragBase[c.id] ?? s;
          final dx = (_dragDx[c.id] ?? 0) + d.delta.dx;
          _dragDx[c.id] = dx;
          final n = (dx / _dw).round();
          // never cross the other end
          final ns = left ? math.min(base.s + n, base.e) : base.s;
          final ne = left ? base.e : math.max(base.e + n, base.s);
          setState(() => _ov[c.id] = GSpan(ns, ne));
        },
        onHorizontalDragEnd: (_) {
          _dragBase.remove(c.id);
          _dragDx.remove(c.id);
          _commit(c);
        },
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: 4,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  final _dragDx = <String, double>{};

  Widget _legend(KOffice? office, KBoard board) {
    final g = context.ghina;
    final items = _color == 'who'
        ? [
            for (final r in office?.activeRoles ?? <KRole>[])
              if (r.raw['color'] is String)
                (r.name, kHex(r.raw['color'] as String)),
          ]
        : [
            for (final col in board.all ? kantorDefaultColumns : board.columns)
              (col.name, kKindSwatch(col.kind).base),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (n, c) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  n,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          Text(
            'Merah = terlambat/konflik · oranye = terblokir',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          Text(
            'Tahan bar untuk menggeser, tarik ujungnya untuk durasi',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _unscheduled(
    List<KCard> real,
    Map<String, GSpan?> sp,
    KBoard board,
    KOffice? office,
  ) {
    final g = context.ghina;
    final un = [
      for (final c in real)
        if (sp[c.id] == null && _passes(c)) c,
    ];
    if (un.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BELUM DIJADWALKAN (${un.length})',
            style: GhinaType.overline.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 6),
          for (final c in un)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: KWhoAvatar(office: office, who: c.who, size: 26),
              title: Text(
                c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.w(700),
              ),
              subtitle: Text(board.colNameOf(c)),
              trailing: TextButton(
                onPressed: () => _schedule(c),
                child: const Text('Jadwalkan'),
              ),
              onTap: () => openKantorCard(context, officeId: id, cardId: c.id),
            ),
        ],
      ),
    );
  }
}

/// A role's sprite at group-row size.
class KantorSpriteBox extends StatelessWidget {
  const KantorSpriteBox({super.key, required this.role, required this.office});
  final KRole role;
  final KOffice? office;
  @override
  Widget build(BuildContext context) =>
      KWhoAvatar(office: office, who: role.id, size: 20);
}

/* ---------------- painters ---------------- */

class _HeadPainter extends CustomPainter {
  _HeadPainter({
    required this.lo,
    required this.days,
    required this.dw,
    required this.zoom,
    required this.g,
  });
  final int lo, days;
  final double dw;
  final String zoom;
  final GhinaTokens g;

  void _text(Canvas c, String s, Rect r, TextStyle st) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, r.width - 4));
    tp.paint(c, Offset(r.left + 4, r.top + (r.height - tp.height) / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = g.border
      ..strokeWidth = 1;
    final t = ganttToday();
    final topSegs = (zoom == 'day' || zoom == 'week')
        ? ganttSegs(lo, days, (d) {
            final (y, m, _) = ganttYmd(d);
            return y * 12 + m;
          })
        : ganttSegs(lo, days, (d) => ganttYmd(d).$1);
    final botSegs = switch (zoom) {
      'day' => ganttSegs(lo, days, (d) => d),
      'week' => ganttSegs(lo, days, (d) => ((d + 3) / 7).floor()),
      'month' => ganttSegs(lo, days, (d) {
        final (y, m, _) = ganttYmd(d);
        return y * 12 + m;
      }),
      _ => ganttSegs(lo, days, (d) {
        final (y, m, _) = ganttYmd(d);
        return y * 4 + m ~/ 3;
      }),
    };
    final topStyle = GhinaType.caption.w(800).copyWith(color: g.textSecondary);
    final botStyle = GhinaType.caption.copyWith(color: g.textMuted);
    const h2 = _headH / 2;
    for (final s in topSegs) {
      final r = Rect.fromLTWH(
        (s.from - lo) * dw,
        0,
        (s.to - s.from + 1) * dw,
        h2,
      );
      final (y, m, _) = ganttYmd(s.from);
      final w = r.width;
      final label = (zoom == 'day' || zoom == 'week')
          ? (w >= 120
                ? '${kMonLong[m]} $y'
                : w >= 56
                ? '${kMonShort[m]} $y'
                : w >= 26
                ? kMonShort[m]
                : '')
          : '$y';
      _text(canvas, label, r, topStyle);
      canvas.drawLine(Offset(r.left, 0), Offset(r.left, _headH), line);
    }
    for (final s in botSegs) {
      final r = Rect.fromLTWH(
        (s.from - lo) * dw,
        h2,
        (s.to - s.from + 1) * dw,
        h2,
      );
      final (_, m, d) = ganttYmd(s.from);
      final label = switch (zoom) {
        'day' => '${kDowShort[ganttDow(s.from)]} $d',
        'week' => '$d ${kMonShort[m]}',
        'month' => r.width >= 70 ? kMonLong[m] : kMonShort[m],
        _ => 'Q${m ~/ 3 + 1}',
      };
      if (zoom == 'day' && s.from == t) {
        canvas.drawRect(
          r,
          Paint()..color = GhinaColors.red.base.withValues(alpha: 0.15),
        );
      } else if (zoom == 'day' && ganttWeekend(s.from)) {
        canvas.drawRect(r, Paint()..color = g.surfaceAlt);
      }
      _text(canvas, label, r, botStyle);
      canvas.drawLine(Offset(r.left, h2), Offset(r.left, _headH), line);
    }
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2), line);
    if (t >= lo && t < lo + days) {
      final x = (t - lo) * dw + dw / 2;
      canvas.drawLine(
        Offset(x, h2),
        Offset(x, _headH),
        Paint()
          ..color = GhinaColors.red.base
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_HeadPainter o) =>
      o.lo != lo || o.days != days || o.dw != dw || o.zoom != zoom || o.g != g;
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.rows,
    required this.spans,
    required this.cards,
    required this.lo,
    required this.days,
    required this.dw,
    required this.zoom,
    required this.g,
    required this.conflicts,
    required this.crit,
    required this.critOn,
  });

  final List<_Row> rows;
  final Map<String, GSpan?> spans;
  final Map<String, KCard> cards;
  final int lo, days;
  final double dw;
  final String zoom;
  final GhinaTokens g;
  final Set<String> conflicts;
  final ({Set<String> ids, Set<String> edges}) crit;
  final bool critOn;

  double _x(int d) => (d - lo) * dw;

  @override
  void paint(Canvas canvas, Size size) {
    // group bands
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isGroup) {
        canvas.drawRect(
          Rect.fromLTWH(0, i * _rowH, size.width, _rowH),
          Paint()..color = g.surfaceAlt,
        );
      }
    }
    // weekends
    if (dw >= 4) {
      final p = Paint()..color = g.surfaceAlt.withValues(alpha: 0.7);
      for (var d = lo; d < lo + days; d++) {
        if (ganttDow(d) == 6)
          canvas.drawRect(Rect.fromLTWH(_x(d), 0, 2 * dw, size.height), p);
      }
    }
    // vertical month/week lines
    final vl = Paint()
      ..color = g.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var d = lo; d < lo + days; d++) {
      final keyStart = switch (zoom) {
        'day' => true,
        'week' => ganttDow(d) == 1,
        'month' => ganttYmd(d).$3 == 1,
        _ => ganttYmd(d).$3 == 1 && ganttYmd(d).$2 % 3 == 0,
      };
      if (keyStart)
        canvas.drawLine(Offset(_x(d), 0), Offset(_x(d), size.height), vl);
    }
    // today
    final t = ganttToday();
    if (t >= lo && t < lo + days) {
      final x = _x(t) + dw / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = GhinaColors.red.base
          ..strokeWidth = 2,
      );
    }
    // row separators
    final sep = Paint()
      ..color = g.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i <= rows.length; i++) {
      canvas.drawLine(Offset(0, i * _rowH), Offset(size.width, i * _rowH), sep);
    }
    // group summary bars
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (!r.isGroup) continue;
      final sps = [for (final c in r.items) ?spans[c.id]];
      if (sps.isEmpty) continue;
      final s = sps.map((x) => x.s).reduce(math.min),
          e = sps.map((x) => x.e).reduce(math.max);
      var w = 0, p = 0;
      for (final c in r.items) {
        final sp = spans[c.id];
        if (sp == null) continue;
        final dd = sp.e - sp.s + 1;
        w += dd;
        p += dd * ganttProgress(c);
      }
      final pct = w == 0 ? 0 : (p / w).round();
      final rect = Rect.fromLTWH(
        _x(s),
        i * _rowH + _rowH / 2 - 5,
        (e - s + 1) * dw,
        10,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(
        rr,
        Paint()..color = g.textMuted.withValues(alpha: 0.35),
      );
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width * pct / 100, rect.height),
        Paint()..color = g.textMuted,
      );
      canvas.restore();
    }
    _arrows(canvas);
  }

  double _anchorY(int row) => row * _rowH + _rowH / 2;

  ({double xl, double xr}) _anchor(KCard c) {
    final sp = spans[c.id]!;
    if (sp.milestone) {
      final cx = _x(sp.s) + dw / 2;
      return (xl: cx - 11, xr: cx + 11);
    }
    return (xl: _x(sp.s), xr: _x(sp.e + 1));
  }

  void _arrows(Canvas canvas) {
    final rowOf = <String, int>{
      for (var i = 0; i < rows.length; i++)
        if (!rows[i].isGroup) rows[i].card!.id: i,
    };
    for (final c in cards.values) {
      final rc = rowOf[c.id];
      if (rc == null || spans[c.id] == null) continue;
      for (final d in c.deps) {
        final p = cards[d];
        final rp = rowOf[d];
        if (p == null || rp == null || spans[d] == null) continue;
        final a = _anchor(p), b = _anchor(c);
        final ay = _anchorY(rp), by = _anchorY(rc);
        final pts = <Offset>[];
        if (b.xl >= a.xr + 20) {
          final xm = a.xr + 10;
          pts.addAll([
            Offset(a.xr, ay),
            Offset(xm, ay),
            Offset(xm, by),
            Offset(b.xl - 1, by),
          ]);
        } else {
          final ycc = ay + (by < ay ? -_rowH / 2 : _rowH / 2);
          pts.addAll([
            Offset(a.xr, ay),
            Offset(a.xr + 10, ay),
            Offset(a.xr + 10, ycc),
            Offset(b.xl - 11, ycc),
            Offset(b.xl - 11, by),
            Offset(b.xl - 1, by),
          ]);
        }
        final bad = conflicts.contains('$d>${c.id}');
        final isCrit = critOn && crit.edges.contains('$d>${c.id}');
        final color = bad
            ? GhinaColors.red.base
            : isCrit
            ? GhinaColors.yellow.base
            : g.textMuted;
        final paint = Paint()
          ..color = critOn && !isCrit && !bad
              ? color.withValues(alpha: 0.3)
              : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = bad || isCrit ? 2 : 1.4;
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final q in pts.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, paint);
        final end = pts.last;
        canvas.drawPath(
          Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - 6, end.dy - 3.5)
            ..lineTo(end.dx - 6, end.dy + 3.5)
            ..close(),
          Paint()..color = paint.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => true;
}
