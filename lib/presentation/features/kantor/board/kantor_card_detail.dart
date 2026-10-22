import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';
import 'kantor_board_data.dart';
import 'kantor_board_lib.dart';
import 'kantor_board_widgets.dart';
import 'kantor_label_manager.dart';

/// Opens the full-screen detail of an existing card.
Future<void> openKantorCard(
  BuildContext context, {
  required String officeId,
  required String cardId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => KantorCardScreen(officeId: officeId, cardId: cardId),
  ),
);

/// Opens the detail in "new card" mode; nothing is saved until "Buat kartu".
Future<void> openKantorNewCard(
  BuildContext context, {
  required String officeId,
  int col = 0,
  String? board,
  String title = '',
  String who = '',
  String repo = '',
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => KantorCardScreen(
      officeId: officeId,
      newCol: col,
      newBoard: board,
      newTitle: title,
      newWho: who,
      newRepo: repo,
    ),
  ),
);

typedef _J = Map<String, dynamic>;

class KantorCardScreen extends ConsumerStatefulWidget {
  const KantorCardScreen({
    super.key,
    required this.officeId,
    this.cardId,
    this.newCol = 0,
    this.newBoard,
    this.newTitle = '',
    this.newWho = '',
    this.newRepo = '',
  });

  final String officeId;
  final String? cardId;
  final int newCol;
  final String? newBoard;
  final String newTitle;
  final String newWho;
  final String newRepo;

  @override
  ConsumerState<KantorCardScreen> createState() => _KantorCardScreenState();
}

class _KantorCardScreenState extends ConsumerState<KantorCardScreen> {
  _J? _card;
  Object? _error;
  bool _preview = true;
  bool _notify = false;
  bool _blockedOpen = false;
  bool _busy = false;
  Timer? _descTimer;
  Timer? _liveTimer;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _why = TextEditingController();
  final _checkIn = TextEditingController();
  final _commentIn = TextEditingController();
  final _depQ = TextEditingController();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  final _whyFocus = FocusNode();

  late final KantorApi? _api = ref.read(kantorApiProvider);
  bool _descDirty = false;

  bool get _isNew => widget.cardId == null;
  String get _path => '${kBase(widget.officeId)}/cards/${widget.cardId}';
  _J get c => _card!;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _preview = false;
      _card = {
        'id': null,
        'title': widget.newTitle,
        'desc': '',
        'col': widget.newCol,
        'board': ?widget.newBoard,
        'publishAt': '',
        'who': widget.newWho,
        'repo': widget.newRepo,
        'prio': 'P2',
        'due': '',
        'start': '',
        'estDays': null,
        'progress': null,
        'labels': <String>[],
        'milestone': false,
        'blocked': '',
        'epicId': '',
        'checklist': [],
        'comments': [],
        'history': [],
        'links': [],
        'children': [],
        'deps': [],
        'blocks': [],
        'attachments': [],
      };
      _title.text = widget.newTitle;
    } else {
      _load();
      _titleFocus.addListener(_flushTitle);
      _descFocus.addListener(() {
        if (!_descFocus.hasFocus) _flushDesc();
      });
      _whyFocus.addListener(() {
        if (!_whyFocus.hasFocus) _saveWhy();
      });
    }
  }

  @override
  void dispose() {
    _descTimer?.cancel();
    _liveTimer?.cancel();
    if (_descDirty && !_isNew) {
      // The user left before the debounce fired: do not lose the text.
      _api?.patch(_path, {'desc': _desc.text}).catchError((_) => null);
    }
    for (final x in [_title, _desc, _why, _checkIn, _commentIn, _depQ]) {
      x.dispose();
    }
    for (final f in [_titleFocus, _descFocus, _whyFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  /* ----- data ----- */

  Future<void> _load({bool quiet = false}) async {
    final api = _api;
    if (api == null) return;
    try {
      final j = await api.get(_path);
      if (!mounted) return;
      final m = Map<String, dynamic>.from(j as Map);
      setState(() {
        _card = m;
        _error = null;
        if (!_titleFocus.hasFocus) _title.text = '${m['title'] ?? ''}';
        if (!_descFocus.hasFocus && !_descDirty)
          _desc.text = '${m['desc'] ?? ''}';
        if (!_whyFocus.hasFocus) _why.text = '${m['blocked'] ?? ''}';
      });
    } catch (e) {
      if (!mounted) return;
      if (quiet && _card != null) return;
      setState(() => _error = e);
    }
  }

  void _boardChanged() =>
      ref.read(kantorBoardProvider(widget.officeId).notifier).refresh();

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        kToast(context, '$e', bad: true);
        if (!_isNew) _load(quiet: true);
      }
    }
  }

  /// Change one or more fields. Existing cards PATCH at once; new cards just
  /// edit the draft.
  Future<void> _set(_J body) async {
    setState(() => c.addAll(body));
    if (_isNew) return;
    await _run(() async {
      final r = await _api!.patch(_path, body);
      if (!mounted) return;
      if (r is Map && r['id'] != null) {
        setState(() {
          for (final k in body.keys) {
            if (r.containsKey(k) && k != 'deps') c[k] = r[k];
          }
        });
      }
      _boardChanged();
    });
  }

  /// A mutating call on the card followed by a reload.
  Future<void> _act(Future<dynamic> Function(KantorApi api) f) =>
      _run(() async {
        await f(_api!);
        await _load(quiet: true);
        _boardChanged();
      });

  void _flushTitle() {
    if (_titleFocus.hasFocus || _isNew) return;
    final v = _title.text.trim();
    if (v.isEmpty) {
      _title.text = '${c['title']}';
    } else if (v != c['title']) {
      _set({'title': v});
    }
  }

  void _flushDesc() {
    _descTimer?.cancel();
    if (_isNew) return;
    if (_descDirty) {
      _descDirty = false;
      _set({'desc': _desc.text});
    }
  }

  void _saveWhy() {
    if (_isNew) return;
    final v = _why.text.trim();
    if (v != '${c['blocked'] ?? ''}') _set({'blocked': v});
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      kToast(context, 'Judul kartu wajib diisi');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final body = <String, dynamic>{
        'title': title,
        'desc': _desc.text,
        'col': c['col'],
        if ('${c['board'] ?? ''}'.isNotEmpty) 'board': c['board'],
        if (isKDate(c['publishAt'])) 'publishAt': c['publishAt'],
        'who': (c['who'] as String? ?? '').isEmpty ? null : c['who'],
        'repo': c['repo'],
        'prio': c['prio'],
        'due': c['due'],
        'start': c['start'],
        if (c['estDays'] != null) 'estDays': c['estDays'],
        if ('${c['epicId'] ?? ''}'.isNotEmpty) 'epicId': c['epicId'],
        'labels': c['labels'],
        if (_why.text.trim().isNotEmpty) 'blocked': _why.text.trim(),
      };
      await ref
          .read(kantorBoardProvider(widget.officeId).notifier)
          .create(body);
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        kToast(context, '$e', bad: true);
      }
    }
  }

  /* ----- helpers ----- */

  List<_J> _list(String k) => [
    for (final x in (c[k] as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];

  int get _col => (c['col'] as num?)?.toInt() ?? 0;
  String get _boardId => '${c['board'] ?? ''}'.isEmpty
      ? 'utama'
      : '${c['board']}';

  /// Columns of this card's board.
  List<KCol> _colsFor(KBoard? b) {
    final def = b?.boardDef(_boardId);
    if (def != null) return def.columns;
    if (b != null && !b.all && (b.board?.id ?? 'utama') == _boardId) {
      return b.columns;
    }
    return kantorDefaultColumns;
  }

  Future<void> _moveBoard(KBoard? b) async {
    final boards = b?.activeBoards ?? const <KBoardDef>[];
    if (boards.isEmpty) return;
    final v = await kPickOne<String>(
      context,
      title: 'Pindah papan',
      current: _boardId,
      options: [
        for (final d in boards)
          (
            value: d.id,
            label: d.icon.isEmpty ? d.name : '${d.icon} ${d.name}',
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: kBoardColor(d),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
    if (v == null || v == _boardId) return;
    final cols = b?.boardDef(v)?.columns ?? kantorDefaultColumns;
    // keep the stage: first column of the same kind on the target board
    final kind = _colsFor(b).elementAtOrNull(_col)?.kind ?? 'antre';
    final i = cols.indexWhere((x) => x.kind == kind);
    final to = i < 0 ? 0 : i;
    setState(() {
      if (to < cols.length) c['colName'] = cols[to].name;
    });
    await _set({'board': v, 'col': to});
  }
  String get _who => '${c['who'] ?? ''}';

  Future<void> _pickDate(String key) async {
    final cur = kParseDay('${c[key] ?? ''}') ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) await _set({key: kDayStr(d)});
  }

  Future<void> _pickEst() async {
    final ctl = TextEditingController(text: c['estDays']?.toString() ?? '');
    final r = await showChunkyDialog<String>(
      context,
      builder: (ctx) => ChunkyDialog(
        title: 'Estimasi (hari)',
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'mis. 3'),
        ),
        actions: [
          ChunkyButton(
            label: 'Simpan',
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (r == null) return;
    final v = r.isEmpty ? null : double.tryParse(r.replaceAll(',', '.'));
    await _set({'estDays': v == null ? null : (v < 0 ? 0 : v)});
  }

  /* ----- build ----- */

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    // Live refresh: any board change re-reads this card.
    if (!_isNew) {
      ref.listen(kantorEventsProvider, (_, next) {
        final e = next.value;
        if (e == null || e['t'] != 'changed') return;
        if (e['office'] != '*' && e['office'] != widget.officeId) return;
        if (e['what'] != 'board') return;
        if (e['card'] != null && e['card'] != widget.cardId) return;
        _liveTimer?.cancel();
        _liveTimer = Timer(
          const Duration(milliseconds: 350),
          () => _load(quiet: true),
        );
      });
    }
    final office = ref.watch(kantorOfficeProvider(widget.officeId)).value;
    final board = ref.watch(kantorBoardProvider(widget.officeId)).value;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _flushDesc(),
      child: Scaffold(
        backgroundColor: g.background,
        appBar: AppBar(
          title: Text(_isNew ? 'Kartu baru' : 'Kartu ${widget.cardId}'),
          actions: [
            if (!_isNew && _card != null)
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('Arsipkan kartu'),
                  ),
                ],
              ),
          ],
        ),
        body: _card == null
            ? (_error != null
                  ? KantorErrorView(error: _error!, onRetry: () => _load())
                  : const KantorLoading())
            : _body(office, board),
      ),
    );
  }

  Future<void> _menu(String v) async {
    if (v != 'archive') return;
    final isEpic = c['epic'] == true;
    final ok = await showChunkyConfirm(
      context,
      title: 'Arsipkan kartu?',
      message:
          'Kartu "${c['title']}"${isEpic ? ' beserta sub-kartunya' : ''} diarsipkan dari board.',
      confirmLabel: 'Arsipkan',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await _run(() async {
      await ref
          .read(kantorBoardProvider(widget.officeId).notifier)
          .archive(widget.cardId!);
      if (mounted) kToast(context, 'Kartu diarsipkan');
      nav.pop();
    });
  }

  Widget _sec(String title, Widget child, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: GhinaType.overline.copyWith(
                  color: context.ghina.textMuted,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _body(KOffice? office, KBoard? board) {
    final g = context.ghina;
    final isEpic = c['epic'] == true;
    final working =
        !_isNew &&
        _who.isNotEmpty &&
        (office?.workingRoles.contains(_who) ?? false);
    final blocked = '${c['blocked'] ?? ''}'.isNotEmpty || _blockedOpen;
    final labelIds = [for (final x in (c['labels'] as List? ?? const [])) '$x'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KPrioPill('${c['prio']}'),
            Text(
              office?.repoName('${c['repo'] ?? ''}') ?? '${c['repo']}',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
            if (isEpic)
              const ChunkyPill(
                label: 'Epic',
                color: GhinaColors.purple,
                soft: true,
              ),
            if (c['milestone'] == true)
              Text(
                '◆ Milestone',
                style: GhinaType.caption.copyWith(color: g.warning),
              ),
            Text(
              _isNew ? 'kartu baru' : '${c['id']}',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          maxLines: null,
          textInputAction: TextInputAction.done,
          style: GhinaType.h2.copyWith(color: g.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Judul kartu',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _titleFocus.unfocus(),
        ),
        if (working)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GhinaColors.green.tint(g.brightness),
              borderRadius: GhinaRadii.rMd,
            ),
            child: Text(
              '${office!.whoName(_who)} sedang bekerja',
              style: GhinaType.bodyS
                  .w(700)
                  .copyWith(color: GhinaColors.green.base),
            ),
          ),
        ..._fields(office, board),
        _progress(isEpic),
        _blockBox(blocked),
        _labels(board, labelIds),
        _description(board),
        if (isEpic && !_isNew) _children(office),
        if (!_isNew) ...[
          _deps(board),
          _attachments(),
          _checklist(),
          _comments(office),
          _links(),
          _history(),
        ],
        const SizedBox(height: 24),
        if (_isNew)
          ChunkyButton(label: 'Buat kartu', loading: _busy, onPressed: _create)
        else
          ChunkyButton(
            label: 'Arsipkan kartu',
            variant: ChunkyButtonVariant.danger,
            onPressed: () => _menu('archive'),
          ),
      ],
    );
  }

  /* ----- fields ----- */

  List<Widget> _fields(KOffice? office, KBoard? board) {
    final epicOpts = [
      for (final e in board?.epics ?? <KCard>[])
        if (e.id != widget.cardId) e,
    ];
    final epicId = '${c['epicId'] ?? ''}';
    final repoId = '${c['repo'] ?? ''}';
    final cols = _colsFor(board);
    final cur = _col >= 0 && _col < cols.length ? cols[_col] : null;
    final boardDef = board?.boardDef(_boardId);
    final publishAt = '${c['publishAt'] ?? ''}';
    return [
      if ((board != null && board.activeBoards.length > 1) || boardDef != null)
        KFieldRow(
          label: 'Papan',
          value: boardDef?.name ?? _boardId,
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: kBoardColor(boardDef),
              shape: BoxShape.circle,
            ),
          ),
          onTap: (board?.activeBoards.length ?? 0) > 1
              ? () => _moveBoard(board)
              : null,
        ),
      KFieldRow(
        label: 'Status',
        value: '${c['colName'] ?? ''}'.isNotEmpty
            ? '${c['colName']}'
            : cur?.name ?? '-',
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: kKindSwatch(cur?.kind ?? 'antre').base,
            shape: BoxShape.circle,
          ),
        ),
        onTap: () async {
          final v = await kPickOne<int>(
            context,
            title: 'Status',
            current: _col,
            options: [
              for (var i = 0; i < cols.length; i++)
                (value: i, label: cols[i].name, leading: null),
            ],
          );
          if (v != null && v < cols.length) {
            setState(() {
              c['colName'] = cols[v].name;
              c['colKind'] = cols[v].kind;
            });
            await _set({'col': v});
          }
        },
      ),
      KFieldRow(
        label: 'Tanggal tayang',
        value: isKDate(publishAt) ? kFmtDay(publishAt) : 'Belum diatur',
        onTap: () => _pickDate('publishAt'),
        onClear: isKDate(publishAt) ? () => _set({'publishAt': ''}) : null,
      ),
      KFieldRow(
        label: 'Ditugaskan ke',
        value:
            office?.whoName(_who) ?? (_who.isEmpty ? 'Belum ditugaskan' : _who),
        leading: KWhoAvatar(office: office, who: _who, size: 28),
        onTap: () async {
          final v = await kPickOne<String>(
            context,
            title: 'Ditugaskan ke',
            current: _who.isEmpty ? kantorNone : _who,
            options: [
              (value: kantorNone, label: 'Belum ditugaskan', leading: null),
              for (final r in office?.activeRoles ?? <KRole>[])
                (
                  value: r.id,
                  label: '${r.name} · ${r.title}',
                  leading: KWhoAvatar(office: office, who: r.id, size: 30),
                ),
            ],
          );
          if (v != null) await _set({'who': v == kantorNone ? null : v});
        },
      ),
      KFieldRow(
        label: 'Prioritas',
        value: '${c['prio']}',
        onTap: () async {
          final v = await kPickOne<String>(
            context,
            title: 'Prioritas',
            current: '${c['prio']}',
            options: [
              for (final p in kantorPrios) (value: p, label: p, leading: null),
            ],
          );
          if (v != null) await _set({'prio': v});
        },
      ),
      KFieldRow(
        label: 'Repo',
        value: repoId.isEmpty
            ? 'Tanpa repo'
            : (office?.repoName(repoId) ?? repoId),
        onTap: () async {
          final rooms = [
            ...?office?.rooms.where((r) => r.isRepo || r.id == repoId),
          ];
          final v = await kPickOne<String>(
            context,
            title: 'Repo',
            current: repoId.isEmpty ? kantorNone : repoId,
            options: [
              (value: kantorNone, label: 'Tanpa repo', leading: null),
              for (final r in rooms)
                (value: r.id, label: r.name, leading: null),
              if (!rooms.any((r) => r.id == 'lintas'))
                (value: 'lintas', label: 'lintas repo', leading: null),
            ],
          );
          if (v != null) await _set({'repo': v == kantorNone ? '' : v});
        },
      ),
      KFieldRow(
        label: 'Mulai',
        value: '${c['start'] ?? ''}'.isEmpty
            ? 'Belum diatur'
            : kFmtDay('${c['start']}'),
        onTap: () => _pickDate('start'),
        onClear: '${c['start'] ?? ''}'.isEmpty
            ? null
            : () => _set({'start': ''}),
      ),
      KFieldRow(
        label: 'Tenggat',
        value: '${c['due'] ?? ''}'.isEmpty
            ? 'Belum diatur'
            : kFmtDay('${c['due']}'),
        onTap: () => _pickDate('due'),
        onClear: '${c['due'] ?? ''}'.isEmpty ? null : () => _set({'due': ''}),
      ),
      KFieldRow(
        label: 'Estimasi',
        value: c['estDays'] == null ? 'Belum diatur' : '${c['estDays']} hari',
        onTap: _pickEst,
      ),
      KFieldRow(
        label: 'Epic induk',
        value: epicId.isEmpty
            ? 'Tanpa epic'
            : (board?.map[epicId]?.title ?? epicId),
        onTap: () async {
          final v = await kPickOne<String>(
            context,
            title: 'Epic induk',
            current: epicId.isEmpty ? kantorNone : epicId,
            options: [
              (value: kantorNone, label: 'Tanpa epic', leading: null),
              for (final e in epicOpts)
                (value: e.id, label: e.title, leading: null),
            ],
          );
          if (v != null) await _set({'epicId': v == kantorNone ? '' : v});
        },
      ),
    ];
  }

  Widget _progress(bool isEpic) {
    final g = context.ghina;
    final ck = _list('checklist');
    final auto = c['progress'] == null;
    final autoV = ck.isEmpty
        ? 0
        : (ck.where((x) => x['done'] == true).length / ck.length * 100).round();
    final v = auto ? autoV : (c['progress'] as num).toInt();
    return _sec(
      'Progres',
      Column(
        children: [
          Row(
            children: [
              Text('$v%', style: GhinaType.h3.copyWith(color: g.textPrimary)),
              Expanded(
                child: Slider(
                  value: v.toDouble().clamp(0, 100),
                  max: 100,
                  divisions: 20,
                  onChanged: auto
                      ? null
                      : (x) => setState(() => c['progress'] = x.round()),
                  onChangeEnd: auto
                      ? null
                      : (x) => _set({'progress': x.round()}),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Otomatis dari checklist'),
            value: auto,
            onChanged: (on) => _set({'progress': on ? null : autoV}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Milestone (penanda tonggak, tampil sebagai ◆)'),
            value: c['milestone'] == true,
            onChanged: (on) => _set({'milestone': on}),
          ),
        ],
      ),
    );
  }

  Widget _blockBox(bool blocked) => _sec(
    'Blokir',
    Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Terblokir'),
          value: blocked,
          onChanged: (on) {
            if (on) {
              setState(() => _blockedOpen = true);
              _whyFocus.requestFocus();
            } else {
              setState(() => _blockedOpen = false);
              _why.clear();
              _set({'blocked': ''});
            }
          },
        ),
        if (blocked)
          TextField(
            controller: _why,
            focusNode: _whyFocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _whyFocus.unfocus(),
            decoration: const InputDecoration(
              hintText: 'Alasan, mis. menunggu API dari tim lain',
            ),
          ),
      ],
    ),
  );

  Widget _labels(KBoard? board, List<String> ids) => _sec(
    'Label',
    board == null || board.labels.isEmpty
        ? Text(
            'Belum ada label. Buat lewat Kelola label.',
            style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
          )
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in board.labels)
                KLabelChip(
                  label: l,
                  selected: ids.contains(l.id),
                  onTap: () {
                    final next = ids.contains(l.id)
                        ? ids.where((x) => x != l.id).toList()
                        : [...ids, l.id];
                    _set({'labels': next});
                  },
                ),
            ],
          ),
    trailing: TextButton(
      onPressed: () =>
          showKantorLabelManager(context, officeId: widget.officeId),
      child: const Text('Kelola'),
    ),
  );

  Widget _description(KBoard? board) {
    final g = context.ghina;
    return _sec(
      'Deskripsi',
      _preview
          ? (_desc.text.isEmpty
                ? Text(
                    'Belum ada deskripsi.',
                    style: GhinaType.bodyS.copyWith(color: g.textMuted),
                  )
                : KantorMarkdown(_desc.text))
          : TextField(
              controller: _desc,
              focusNode: _descFocus,
              minLines: 5,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText:
                    'Apa yang harus dikerjakan, batasan, catatan. Markdown boleh.',
              ),
              onChanged: (_) {
                _descDirty = true;
                _descTimer?.cancel();
                _descTimer = Timer(
                  const Duration(milliseconds: 800),
                  _flushDesc,
                );
              },
            ),
      trailing: _isNew
          ? null
          : TextButton(
              onPressed: () {
                if (!_preview) _flushDesc();
                setState(() => _preview = !_preview);
              },
              child: Text(_preview ? 'Edit' : 'Pratinjau'),
            ),
    );
  }

  Widget _children(KOffice? office) {
    final kids = _list('children');
    bool isDone(_J k) =>
        k['done'] is bool ? k['done'] == true : k['col'] == kantorDoneCol;
    final done = kids.where(isDone).length;
    return _sec(
      'Sub-kartu ($done/${kids.length} selesai)',
      Column(
        children: [
          if (kids.isEmpty)
            Text(
              'Belum ada sub-kartu.',
              style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
            ),
          for (final k in kids)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${k['title']}', style: GhinaType.body.w(600)),
              subtitle: Text(
                '${office?.repoName('${k['repo'] ?? ''}') ?? ''} · ${k['colName'] ?? kantorCols[((k['col'] as num?)?.toInt() ?? 0).clamp(0, 4)]}${'${k['who'] ?? ''}'.isEmpty ? '' : ' · ${office?.whoName('${k['who']}') ?? k['who']}'}',
              ),
              trailing: isDone(k)
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : null,
              onTap: () => openKantorCard(
                context,
                officeId: widget.officeId,
                cardId: '${k['id']}',
              ),
            ),
        ],
      ),
    );
  }

  /* ----- dependencies ----- */

  Widget _deps(KBoard? board) {
    final g = context.ghina;
    final deps = _list('deps');
    final blocks = _list('blocks');
    final q = _depQ.text.trim().toLowerCase();
    final have = {for (final d in deps) '${d['id']}'};
    final hits = q.isEmpty || board == null
        ? <KCard>[]
        : board.cards
              .where(
                (x) =>
                    x.id != widget.cardId &&
                    !have.contains(x.id) &&
                    (x.title.toLowerCase().contains(q) ||
                        x.id.toLowerCase().contains(q)),
              )
              .take(6)
              .toList();
    Future<void> setDeps(List<String> ids) => _act((api) async {
      await api.patch(_path, {'deps': ids});
      _depQ.clear();
    });
    return _sec(
      'Dependensi',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menunggu kartu (${deps.length})',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          if (deps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Tidak menunggu kartu lain.',
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ),
          for (final d in deps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${d['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${d['colName'] ?? kantorCols[((d['col'] as num?)?.toInt() ?? 0).clamp(0, 4)]}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setDeps([
                  for (final x in deps)
                    if (x['id'] != d['id']) '${x['id']}',
                ]),
              ),
              onTap: () => openKantorCard(
                context,
                officeId: widget.officeId,
                cardId: '${d['id']}',
              ),
            ),
          TextField(
            controller: _depQ,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Cari kartu untuk ditunggu',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          for (final h in hits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                h.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(board?.colNameOf(h) ?? ''),
              trailing: const Icon(Icons.add_rounded),
              onTap: () => setDeps([...have, h.id]),
            ),
          if (q.isNotEmpty && hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Tidak ada kartu yang cocok.',
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Memblokir (${blocks.length}), kartu ini menahan:',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
            for (final d in blocks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${d['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => openKantorCard(
                  context,
                  officeId: widget.officeId,
                  cardId: '${d['id']}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  /* ----- attachments ----- */

  Widget _attachments() {
    final g = context.ghina;
    final at = _list('attachments');
    final api = _api;
    return _sec(
      'Lampiran (${at.length})',
      Column(
        children: [
          if (at.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Belum ada lampiran.',
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              ),
            ),
          for (final a in at)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: a['image'] == true && api != null
                        ? () => _viewImage(a)
                        : null,
                    child: Container(
                      width: 56,
                      height: 56,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: g.surfaceAlt,
                        borderRadius: GhinaRadii.rMd,
                      ),
                      child: a['image'] == true && api != null
                          ? Image.network(
                              _attUrl(api, a).toString(),
                              headers: api.authHeaders,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_rounded),
                            )
                          : const Icon(Icons.insert_drive_file_rounded),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.body.w(700),
                        ),
                        Text(
                          '${kFmtSize((a['size'] as num?) ?? 0)}${c['cover'] == a['id'] ? ' · sampul' : ''}',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'cover') {
                        _set({'cover': c['cover'] == a['id'] ? null : a['id']});
                      } else {
                        _act((api) => api.delete('$_path/attach/${a['id']}'));
                      }
                    },
                    itemBuilder: (_) => [
                      if (a['image'] == true)
                        PopupMenuItem(
                          value: 'cover',
                          child: Text(
                            c['cover'] == a['id']
                                ? 'Lepas sampul'
                                : 'Jadikan sampul',
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'del',
                        child: Text('Lepas lampiran'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Uri _attUrl(KantorApi api, _J a) {
    final u = '${a['url']}';
    if (u.startsWith('http')) return Uri.parse(u);
    final i = u.indexOf('?');
    return api.url(i < 0 ? u : u.substring(0, i));
  }

  void _viewImage(_J a) {
    final api = _api!;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.network(
                  _attUrl(api, a).toString(),
                  headers: api.authHeaders,
                ),
              ),
            ),
            SafeArea(
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ----- checklist ----- */

  Widget _checklist() {
    final g = context.ghina;
    final ck = _list('checklist');
    final unchecked = ck.where((x) => x['done'] != true).length;
    Future<void> reorder(int i, int d) {
      final ids = [for (final x in ck) x['id']];
      final j = i + d;
      if (j < 0 || j >= ids.length) return Future.value();
      final t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
      return _act((api) => api.post('$_path/checks-order', {'order': ids}));
    }

    return _sec(
      'Checklist (${ck.length - unchecked}/${ck.length})',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < ck.length; i++)
            Row(
              children: [
                Checkbox(
                  value: ck[i]['done'] == true,
                  onChanged: (v) => _act(
                    (api) => api.post('$_path/check', {
                      'itemId': ck[i]['id'],
                      'done': v == true,
                    }),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${ck[i]['text']}',
                    style: GhinaType.body.copyWith(
                      color: ck[i]['done'] == true
                          ? g.textMuted
                          : g.textPrimary,
                      decoration: ck[i]['done'] == true
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  onPressed: i == 0 ? null : () => reorder(i, -1),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  onPressed: i == ck.length - 1 ? null : () => reorder(i, 1),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _act(
                    (api) => api.post('$_path/check', {
                      'itemId': ck[i]['id'],
                      'remove': true,
                    }),
                  ),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _checkIn,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Tambah item checklist',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addCheck(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded),
                onPressed: _addCheck,
              ),
            ],
          ),
          if (unchecked > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await showChunkyConfirm(
                        context,
                        title: 'Pecah jadi sub-kartu?',
                        message:
                            'Item checklist yang belum dicentang jadi kartu sendiri, dan kartu ini menjadi epic.',
                        confirmLabel: 'Pecah',
                      );
                      if (ok == true) {
                        await _act((api) => api.post('$_path/split', {}));
                        if (mounted) kToast(context, 'Dipecah jadi sub-kartu');
                      }
                    },
                    child: const Text('Pecah jadi sub-kartu'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$unchecked item',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addCheck() async {
    final v = _checkIn.text.trim();
    if (v.isEmpty) return;
    _checkIn.clear();
    await _act((api) => api.post('$_path/check', {'text': v}));
  }

  /* ----- comments, links, history ----- */

  Widget _comments(KOffice? office) {
    final g = context.ghina;
    final list = _list('comments');
    return _sec(
      'Komentar (${list.length})',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (list.isEmpty)
            Text(
              'Belum ada komentar.',
              style: GhinaType.bodyS.copyWith(color: g.textMuted),
            ),
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _commentAvatar(office, '${m['who']}'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_commentName(office, '${m['who']}')} · ${kAgo('${m['at']}')}',
                          style: GhinaType.caption
                              .w(700)
                              .copyWith(color: g.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        KantorMarkdown('${m['text']}', selectable: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _commentIn,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Tulis komentar',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded),
                onPressed: _sendComment,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Teruskan ke sesi role yang ditugaskan'),
            value: _notify && _who.isNotEmpty,
            onChanged: _who.isEmpty ? null : (v) => setState(() => _notify = v),
          ),
        ],
      ),
    );
  }

  KRole? _roleByAny(KOffice? o, String k) {
    final x = k.toLowerCase();
    return o?.roles
        .where((r) => r.id.toLowerCase() == x || r.name.toLowerCase() == x)
        .firstOrNull;
  }

  String _commentName(KOffice? o, String who) =>
      RegExp(r'^(kamu|you)$', caseSensitive: false).hasMatch(who)
      ? 'Kamu'
      : _roleByAny(o, who)?.name ?? who;

  Widget _commentAvatar(KOffice? o, String who) {
    final r = _roleByAny(o, who);
    return r == null
        ? const SizedBox(width: 24)
        : KWhoAvatar(office: o, who: r.id, size: 28);
  }

  Future<void> _sendComment() async {
    final v = _commentIn.text.trim();
    if (v.isEmpty) return;
    _commentIn.clear();
    await _act(
      (api) => api.post('$_path/comment', {
        'text': v,
        'notify': _notify && _who.isNotEmpty,
      }),
    );
  }

  Widget _links() {
    final ls = _list('links');
    if (ls.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    return _sec(
      'Terkait',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in ls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${l['kind']}: ${l['value']}',
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _history() {
    final g = context.ghina;
    final h = _list('history').take(15).toList();
    return _sec(
      'Riwayat',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h.isEmpty)
            Text(
              'Belum ada.',
              style: GhinaType.bodyS.copyWith(color: g.textMuted),
            ),
          for (final x in h)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${kAgo('${x['at']}')}  ',
                      style: TextStyle(color: g.textMuted),
                    ),
                    TextSpan(
                      text: '${x['who']} ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '${x['text']}'),
                  ],
                ),
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
