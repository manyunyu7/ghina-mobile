import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../plan/plan_thumb.dart';
import '../templates/kantor_templates.dart';
import '../widgets/kantor_states.dart';
import 'kantor_wizard.dart';

const _steps = ['Project', 'Tim', 'Suasana', 'Mulai'];

/// "Kantor baru": pick or create a project folder, name the team, choose a
/// template and let the daemon open the office (`/api/wizard/*`). The preview
/// of the floor plan follows every change, like on the web.
class KantorWizardPage extends ConsumerStatefulWidget {
  const KantorWizardPage({super.key, this.onCreated, this.random});

  /// Called with the new office id; defaults to opening it.
  final void Function(String id)? onCreated;

  /// Picks the manager's name and the "Acak susunan" seed.
  final Random? random;

  @override
  ConsumerState<KantorWizardPage> createState() => _KantorWizardPageState();
}

class _KantorWizardPageState extends ConsumerState<KantorWizardPage> {
  int _step = 0;
  String _mode = 'new';
  String _layout = 'single';
  String _base = '';
  String _root = '';
  String _query = '';
  String _error = '';
  String _permission = '';
  String? _template = 'zen-garden';
  int _seed = 1;
  bool _gitInit = true;
  bool _claudeMd = true;
  bool _firstCard = true;
  bool _startManager = false;
  bool _folderEdited = false;
  bool _busy = false;
  bool _loadingFolders = true;
  Object? _loadError;

  List<String> _roots = [];
  List<Map<String, dynamic>> _folders = [];
  final List<String> _subs = [];
  late final List<Map<String, dynamic>> _team;
  Map<String, dynamic>? _preview;
  String? _previewError;
  Timer? _debounce;
  int _previewGen = 0;

  final _name = TextEditingController();
  final _folder = TextEditingController();
  final _desc = TextEditingController();
  final _sub = TextEditingController();
  final _brief = TextEditingController();
  final _managerName = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rnd = widget.random ?? Random();
    _managerName.text =
        kantorManagerNames[rnd.nextInt(kantorManagerNames.length)];
    _team = [kantorManagerMember(_managerName.text)];
    _loadFolders();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _folder, _desc, _sub, _brief, _managerName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) {
      setState(() => _loadingFolders = false);
      return;
    }
    try {
      final r = await api.get('/api/wizard/folders') as Map;
      if (!mounted) return;
      setState(() {
        _roots = [for (final x in r['roots'] as List) '$x'];
        _folders = [
          for (final f in r['folders'] as List)
            Map<String, dynamic>.from(f as Map),
        ];
        _base = _roots.isEmpty ? '' : _roots.first;
        _loadingFolders = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loadingFolders = false;
        });
      }
    }
  }

  /// What `wizard/preview` and `wizard/create` take.
  Map<String, dynamic> _spec() {
    _team.first['name'] = _managerName.text;
    return {
      'mode': _mode,
      if (_mode == 'new')
        'name': _name.text.trim().isEmpty ? _folder.text : _name.text.trim(),
      'base': _base,
      'folder': _folder.text,
      'layout': _layout,
      'subs': _subs,
      'gitInit': _gitInit,
      'root': _root,
      'description': _desc.text,
      'team': _team,
      'claudeMd': _claudeMd,
      'firstCard': _firstCard,
      'startManager': _startManager,
      'brief': _brief.text,
      'permissionMode': _permission,
      'template': _template,
      'seed': _seed,
    };
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || !mounted) return;
    if (_mode == 'new' ? _folder.text.isEmpty : _root.isEmpty) {
      setState(() {
        _preview = null;
        _previewError = null;
      });
      return;
    }
    final gen = ++_previewGen;
    try {
      final r = Map<String, dynamic>.from(
        await api.post('/api/wizard/preview', _spec()) as Map,
      );
      if (!mounted || gen != _previewGen) return;
      // rooms may have changed under the team: keep each room valid
      final ids = {for (final x in r['rooms'] as List) (x as Map)['id']};
      final fixed = r['team'] as List? ?? const [];
      for (var i = 1; i < _team.length && i < fixed.length; i++) {
        if (!ids.contains(_team[i]['room'])) {
          _team[i]['room'] = (fixed[i] as Map)['room'];
        }
      }
      setState(() {
        _preview = r;
        _previewError = null;
      });
    } on KantorException catch (e) {
      if (mounted && gen == _previewGen) {
        setState(() {
          _preview = null;
          _previewError = e.message;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _codeRooms => [
    for (final r in _preview?['rooms'] as List? ?? const [])
      Map<String, dynamic>.from(r as Map),
  ];

  void _update(VoidCallback f, {bool preview = true}) {
    setState(() {
      _error = '';
      f();
    });
    if (preview) _schedulePreview();
  }

  void _addSub(String raw) {
    final s = kantorSlugDir(raw);
    _sub.clear();
    if (s.isEmpty || _subs.contains(s)) return;
    _update(() => _subs.add(s));
  }

  String _check() {
    if (_step == 0) {
      if (_mode == 'new' && _folder.text.isEmpty) {
        return 'Isi nama project dulu.';
      }
      if (_mode == 'new' && _layout == 'multi' && _subs.isEmpty) {
        return 'Tambahkan minimal satu repo.';
      }
      if (_mode == 'existing' && _root.isEmpty) return 'Pilih foldernya dulu.';
      final w = _preview?['warnings'] as List?;
      if (w != null && w.isNotEmpty) return '${w.first}';
    }
    if (_step == 1 && _managerName.text.trim().isEmpty) {
      return 'Manager perlu nama.';
    }
    return '';
  }

  void _next() {
    final err = _check();
    setState(() {
      _error = err;
      if (err.isEmpty) _step++;
    });
  }

  Future<void> _create() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await api.post('/api/wizard/create', _spec()) as Map;
      ref.invalidate(kantorStateProvider);
      if (!mounted) return;
      final id = '${r['id']}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r['shift'] != null
                ? 'Kantor dibuka, manager mulai bekerja'
                : 'Kantor dibuka',
          ),
        ),
      );
      if (widget.onCreated != null) {
        widget.onCreated!(id);
      } else {
        context.go('/kantor/o/${Uri.encodeComponent(id)}');
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e is KantorException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final last = _step == _steps.length - 1;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Kantor baru')),
      body: _loadingFolders
          ? const KantorLoading()
          : _loadError != null
          ? KantorErrorView(error: _loadError!)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.sm,
                    GhinaSpace.page,
                    0,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: i <= _step ? 1 : 0,
                                  minHeight: 4,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${i + 1}. ${_steps[i]}',
                                  style: GhinaType.caption.copyWith(
                                    color: i == _step
                                        ? g.textPrimary
                                        : g.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(GhinaSpace.page),
                    children: [
                      [_project, _team_, _mood, _start][_step](),
                      if (_step > 0) _previewCard(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    0,
                    GhinaSpace.page,
                    GhinaSpace.md,
                  ),
                  child: Column(
                    children: [
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                          child: Text(
                            _error,
                            key: const ValueKey('wizard-error'),
                            style: GhinaType.body.copyWith(
                              color: GhinaColors.red.base,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: ChunkyButton(
                              label: _step == 0 ? 'Batal' : 'Kembali',
                              variant: ChunkyButtonVariant.secondary,
                              onPressed: _busy
                                  ? null
                                  : () => _step == 0
                                        ? context.pop()
                                        : setState(() {
                                            _error = '';
                                            _step--;
                                          }),
                            ),
                          ),
                          const SizedBox(width: GhinaSpace.md),
                          Expanded(
                            child: ChunkyButton(
                              label: last ? 'Buat kantor' : 'Lanjut',
                              loading: _busy,
                              onPressed: _busy
                                  ? null
                                  : last
                                  ? _create
                                  : _next,
                            ),
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

  /* ---------- step 1: project ---------- */

  Widget _project() {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Project apa?',
          style: GhinaType.h3.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: GhinaSpace.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'new', label: Text('Project baru')),
            ButtonSegment(value: 'existing', label: Text('Folder ada')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => _update(() {
            _mode = s.first;
            _preview = null;
          }),
        ),
        const SizedBox(height: GhinaSpace.md),
        if (_mode == 'new') ..._newFields() else ..._existingFields(),
        if (_previewError != null)
          Padding(
            padding: const EdgeInsets.only(top: GhinaSpace.sm),
            child: Text(
              _previewError!,
              style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
            ),
          ),
        if ((_preview?['warnings'] as List?)?.isNotEmpty ?? false)
          for (final w in _preview!['warnings'] as List)
            Padding(
              padding: const EdgeInsets.only(top: GhinaSpace.sm),
              child: Text(
                '$w',
                style: GhinaType.caption.copyWith(
                  color: GhinaColors.orange.base,
                ),
              ),
            ),
      ],
    );
  }

  List<Widget> _newFields() {
    final g = context.ghina;
    final multi = _layout == 'multi';
    return [
      ChunkyTextField(
        label: 'Nama project',
        hint: 'mis. Toko Kopi',
        controller: _name,
        onChanged: (v) => _update(() {
          if (!_folderEdited) _folder.text = kantorSlugDir(v);
        }),
      ),
      const SizedBox(height: GhinaSpace.md),
      if (_roots.length > 1) ...[
        DropdownButtonFormField<String>(
          initialValue: _base,
          decoration: const InputDecoration(labelText: 'Lokasi'),
          items: [
            for (final r in _roots)
              DropdownMenuItem(value: r, child: Text(kantorTilde(r))),
          ],
          onChanged: (v) => _update(() => _base = v ?? _base),
        ),
        const SizedBox(height: GhinaSpace.md),
      ],
      ChunkyTextField(
        label: 'Nama folder',
        hint: 'toko-kopi',
        controller: _folder,
        helperText: 'Folder: ${kantorTilde(_base)}/${_folder.text}',
        onChanged: (v) => _update(() {
          _folderEdited = v.isNotEmpty;
          final slug = kantorSlugDir(v);
          if (slug != v) {
            _folder.value = TextEditingValue(
              text: slug,
              selection: TextSelection.collapsed(offset: slug.length),
            );
          }
        }),
      ),
      const SizedBox(height: GhinaSpace.md),
      ChunkyTextField(
        label: 'Mau bikin apa?',
        hint: 'Satu-dua kalimat; ditulis ke CLAUDE.md dan wiki.',
        controller: _desc,
        maxLines: 3,
      ),
      const SizedBox(height: GhinaSpace.md),
      Text('Struktur', style: GhinaType.caption.copyWith(color: g.textMuted)),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'single', label: Text('Satu repo')),
          ButtonSegment(value: 'multi', label: Text('Beberapa repo')),
        ],
        selected: {_layout},
        onSelectionChanged: (s) => _update(() => _layout = s.first),
      ),
      const SizedBox(height: GhinaSpace.md),
      ChunkyTextField(
        label: multi ? 'Repo di dalamnya' : 'Subfolder (opsional)',
        hint: 'ketik lalu Enter',
        controller: _sub,
        textCapitalization: TextCapitalization.none,
        onSubmitted: _addSub,
        suffix: IconButton(
          tooltip: 'Tambah',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => _addSub(_sub.text),
        ),
      ),
      Wrap(
        spacing: GhinaSpace.xs,
        children: [
          for (final s in _subs)
            InputChip(
              label: Text(s),
              onDeleted: () => _update(() => _subs.remove(s)),
            ),
          for (final s in kantorSubSuggestions.where((s) => !_subs.contains(s)))
            ActionChip(label: Text('+ $s'), onPressed: () => _addSub(s)),
        ],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _gitInit,
        title: Text(
          multi ? 'git init di tiap repo' : 'git init di folder project',
        ),
        onChanged: (v) => _update(() => _gitInit = v ?? false),
      ),
    ];
  }

  List<Widget> _existingFields() {
    final q = _query.trim().toLowerCase();
    final list =
        _folders
            .where((f) => q.isEmpty || '${f['name']}'.toLowerCase().contains(q))
            .toList()
          ..sort(
            (a, b) => ((b['mtime'] as num?) ?? 0).compareTo(
              (a['mtime'] as num?) ?? 0,
            ),
          );
    String desc(Map<String, dynamic> f) => [
      if ((f['repos'] as num? ?? 0) > 1)
        '${f['repos']} repo'
      else if (f['git'] == true)
        'repo git'
      else
        'folder',
      if ('${f['stack'] ?? ''}'.isNotEmpty) '${f['stack']}',
      if (f['md'] == true) 'CLAUDE.md',
    ].join(' · ');
    return [
      ChunkyTextField(
        hint: 'Cari folder…',
        prefixIcon: Icons.search_rounded,
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: GhinaSpace.sm),
      if (list.isEmpty)
        const EmptyState(
          title: 'Tidak ada folder yang cocok',
          message: 'Folder di folder induk mungkin sudah jadi kantor.',
          compact: true,
        ),
      for (final f in list)
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: ChunkyTile(
            key: ValueKey('folder-${f['name']}'),
            leading: Icon(
              _root == f['root']
                  ? Icons.radio_button_checked_rounded
                  : Icons.folder_rounded,
            ),
            title: '${f['name']}',
            subtitle: desc(f),
            onTap: () => _update(() {
              _root = '${f['root']}';
              _claudeMd = f['md'] != true;
            }),
          ),
        ),
      const SizedBox(height: GhinaSpace.sm),
      ChunkyTextField(
        label: 'Catatan tentang project (opsional)',
        controller: _desc,
        maxLines: 2,
      ),
    ];
  }

  /* ---------- step 2: team ---------- */

  Widget _team_() {
    final g = context.ghina;
    final picked = {for (final t in _team) t['key']};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tim', style: GhinaType.h3.copyWith(color: g.textPrimary)),
        Text(
          'Manager memecah pekerjaan jadi kartu dan menunjuk role. Role lain '
          'bekerja di ruangannya. Semua bisa diubah nanti.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyTextField(
          label: 'Nama manager',
          controller: _managerName,
          onChanged: (_) => setState(() => _error = ''),
        ),
        const SizedBox(height: GhinaSpace.md),
        Wrap(
          spacing: GhinaSpace.xs,
          children: [
            for (final p in kantorPresets)
              FilterChip(
                key: ValueKey('preset-${p.key}'),
                label: Text(p.title),
                selected: picked.contains(p.key),
                onSelected: (_) => _update(() {
                  final i = _team.indexWhere((t) => t['key'] == p.key);
                  if (i >= 0) {
                    _team.removeAt(i);
                  } else {
                    _team.add(kantorTeamMember(p, _codeRooms));
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: GhinaSpace.md),
        for (var i = 1; i < _team.length; i++) _member(i),
      ],
    );
  }

  Widget _member(int i) {
    final t = _team[i];
    final rooms = _codeRooms;
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        padding: const EdgeInsets.all(GhinaSpace.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${t['name']}',
                    decoration: const InputDecoration(labelText: 'Nama'),
                    onChanged: (v) => t['name'] = v,
                  ),
                ),
                const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  child: TextFormField(
                    initialValue: '${t['title']}',
                    decoration: const InputDecoration(labelText: 'Jabatan'),
                    onChanged: (v) => t['title'] = v,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (rooms.isNotEmpty)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: rooms.any((r) => r['id'] == t['room'])
                          ? '${t['room']}'
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ruangan'),
                      items: [
                        for (final r in rooms)
                          DropdownMenuItem(
                            value: '${r['id']}',
                            child: Text(
                              '${r['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => _update(() => t['room'] = v),
                    ),
                  ),
                if (rooms.isNotEmpty) const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: '${t['model']}',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Model'),
                    items: [
                      for (final (v, l) in kantorModels)
                        DropdownMenuItem(value: v, child: Text(l)),
                    ],
                    onChanged: (v) => setState(() => t['model'] = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus ${t['name']}',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _update(() => _team.removeAt(i)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- step 3: mood ---------- */

  Widget _mood() {
    final g = context.ghina;
    final tpls = ref.watch(kantorTemplatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pilih suasana kantor',
          style: GhinaType.h3.copyWith(color: g.textPrimary),
        ),
        Text(
          'Template menyusun ulang denah, menambah ruangan fasilitas dan '
          'mengisi perabot bertema. Pratinjaunya terlihat di bawah.',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: GhinaSpace.md),
        switch (tpls) {
          AsyncData(:final value) => Column(
            children: [
              KantorTemplateGallery(
                templates: value,
                selected: _template,
                none: 'Tanpa template',
                onSelect: (id) => _update(() {
                  _template = id;
                  _seed = 1;
                }),
              ),
              if (_template != null)
                ChunkyButton(
                  label: 'Acak susunan',
                  variant: ChunkyButtonVariant.secondary,
                  size: ChunkyButtonSize.small,
                  onPressed: () => _update(
                    () => _seed = (widget.random ?? Random()).nextInt(1000000),
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => KantorErrorView(
            error: error,
            onRetry: () => ref.invalidate(kantorTemplatesProvider),
          ),
          _ => const KantorLoading(),
        },
      ],
    );
  }

  /* ---------- step 4: start ---------- */

  Widget _start() {
    final g = context.ghina;
    final mgr = _managerName.text.trim().isEmpty
        ? 'manager'
        : _managerName.text.trim();
    final where = _mode == 'new'
        ? '${kantorTilde(_base)}/${_folder.text}'
        : kantorTilde(_root);
    final tpl = ref.watch(kantorTemplatesProvider).value;
    final tplName = tpl
        ?.where((t) => t['id'] == _template)
        .map((t) => '${t['name']}')
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mulai', style: GhinaType.h3.copyWith(color: g.textPrimary)),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyCard(
          padding: const EdgeInsets.all(GhinaSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mode == 'new'
                    ? (_name.text.isEmpty ? _folder.text : _name.text)
                    : _root.split('/').last,
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              Text(
                where,
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Tim: ${_team.map((t) => t['name']).join(', ')}\n'
                '${(_preview?['plan'] as Map?)?['rooms']?.length ?? '?'} ruangan · '
                'suasana ${tplName ?? 'bawaan'}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              if (_mode == 'existing')
                Text(
                  'Isi folder tidak diubah, kecuali CLAUDE.md kalau dicentang '
                  'dan belum ada.',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
            ],
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _claudeMd,
          title: Text(
            'Tulis CLAUDE.md awal${_mode == 'existing' ? ' (kalau belum ada)' : ''}',
          ),
          onChanged: (v) => setState(() => _claudeMd = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _firstCard,
          title: Text('Kartu pertama untuk $mgr'),
          subtitle: Text(
            _mode == 'new'
                ? 'Rancang struktur awal project'
                : 'Kenali project dan rapikan board',
          ),
          onChanged: (v) => setState(() => _firstCard = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _startManager,
          title: Text('Langsung mulai shift $mgr'),
          subtitle: const Text('Memakai token.'),
          onChanged: (v) => setState(() => _startManager = v ?? false),
        ),
        if (_startManager) ...[
          ChunkyTextField(
            label: 'Brief untuk $mgr',
            hint: 'Kosongkan untuk memakai kartu pertama sebagai tugas.',
            controller: _brief,
            maxLines: 3,
          ),
          const SizedBox(height: GhinaSpace.md),
          DropdownButtonFormField<String>(
            initialValue: _permission,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Mode izin'),
            items: [
              for (final (v, l) in kantorPermModes)
                DropdownMenuItem(value: v, child: Text(l)),
            ],
            onChanged: (v) => setState(() => _permission = v ?? ''),
          ),
        ],
      ],
    );
  }

  Widget _previewCard() {
    final pv = _preview;
    if (pv == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: GhinaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Pratinjau denah'),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: KantorPlanThumb.plan(
              Map<String, dynamic>.from(pv['plan'] as Map),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(pv['plan'] as Map)['rooms'].length} ruangan · '
            '${(pv['rooms'] as List).length} ruangan kode · '
            '${(pv['team'] as List).length} orang',
            style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          ),
        ],
      ),
    );
  }
}
