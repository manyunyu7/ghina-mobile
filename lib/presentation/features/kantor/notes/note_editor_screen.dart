import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../wiki/wiki_format.dart';
import '../wiki/wiki_markdown.dart';
import '../wiki/wiki_page_screen.dart';
import 'note_colors.dart';

/// One note: autosaves 600 ms after the last keystroke, like the web drawer.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.officeId,
    required this.note,
  });

  final String officeId;

  /// Note map; `_fresh: true` marks one just created, which is discarded
  /// again when closed while still empty.
  final Map<String, dynamic> note;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final _tagIn = TextEditingController();
  late Map<String, dynamic> _n;
  late List<String> _tags;
  late String _color;
  bool _preview = false;
  bool _dirty = false;
  bool _touched = false;
  bool _gone = false;
  String _state = 'Tersimpan';
  bool _stateBad = false;
  Timer? _timer;

  bool get _kompleks => widget.officeId == '_kompleks';
  String get _base =>
      '/api/offices/${Uri.encodeComponent(widget.officeId)}/notes';
  String get _id => _n['id'] as String;

  @override
  void initState() {
    super.initState();
    _n = Map<String, dynamic>.from(widget.note);
    _title = TextEditingController(text: '${_n['title'] ?? ''}');
    _body = TextEditingController(text: '${_n['body'] ?? ''}');
    _tags = [for (final t in (_n['tags'] as List? ?? const [])) '$t'];
    _color = noteColors.contains(_n['color'])
        ? _n['color'] as String
        : 'kuning';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _title.dispose();
    _body.dispose();
    _tagIn.dispose();
    super.dispose();
  }

  void _toast(String m, {bool bad = true}) => showToastBadge(
    context,
    message: m,
    icon: bad ? Icons.error_outline : Icons.check_circle_outline,
  );

  void _touch() {
    _dirty = true;
    _touched = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), _flush);
    if (_state != 'Menyimpan…') setState(() => _state = 'Menyimpan…');
  }

  /// Save now; [extra] carries flags (pinned, archived…). Null on failure.
  Future<Map<String, dynamic>?> _flush([
    Map<String, dynamic> extra = const {},
  ]) async {
    _timer?.cancel();
    final api = ref.read(kantorApiProvider);
    if (api == null) return null;
    _dirty = false;
    try {
      final r = await api.post(_base, {
        'id': _id,
        'title': _title.text,
        'body': _body.text,
        'color': _color,
        'tags': _tags,
        ...extra,
      });
      if (r is Map) {
        for (final k in [
          'updatedAt',
          'author',
          'pinned',
          'wall',
          'archived',
          'deleted',
          'room',
        ]) {
          if (r.containsKey(k)) _n[k] = r[k];
        }
      }
      if (mounted) {
        setState(() {
          _state = _dirty ? 'Menyimpan…' : 'Tersimpan';
          _stateBad = false;
        });
      }
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    } on KantorException catch (e) {
      _dirty = true;
      if (mounted) {
        setState(() {
          _state = 'Gagal menyimpan';
          _stateBad = true;
        });
        _toast(e.message);
      }
      return null;
    }
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!_gone) {
      if (_dirty) {
        await _flush();
      } else if (widget.note['_fresh'] == true &&
          !_touched &&
          _title.text.isEmpty &&
          _body.text.isEmpty) {
        try {
          await ref.read(kantorApiProvider)?.post(_base, {
            'id': _id,
            'deleted': true,
          });
        } catch (_) {}
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _setFlag(Map<String, dynamic> extra) async {
    final r = await _flush(extra);
    if (r != null && mounted) setState(() {});
  }

  Future<void> _finish(Map<String, dynamic> extra, String msg) async {
    final r = await _flush(extra);
    if (r == null || !mounted) return;
    _gone = true;
    _toast(msg, bad: false);
    Navigator.of(context).pop();
  }

  void _insert(String text, {bool wrap = false, int back = 0}) {
    if (_preview) setState(() => _preview = false);
    final v = _body.text;
    final sel = _body.selection;
    final a = sel.isValid ? sel.start : v.length;
    final b = sel.isValid ? sel.end : v.length;
    var ins = text;
    if (wrap) ins = '$text${v.substring(a, b)}$text';
    if (RegExp(r'^(- \[ \] |## )$').hasMatch(text) && a > 0 && v[a - 1] != '\n')
      ins = '\n$text';
    final pos = a + ins.length - back;
    _body.value = TextEditingValue(
      text: v.replaceRange(a, b, ins),
      selection: TextSelection.collapsed(offset: pos),
    );
    _touch();
  }

  void _addTags(String raw) {
    var changed = false;
    for (final p in raw.split(',')) {
      final t = p.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
      if (t.isNotEmpty && !_tags.contains(t)) {
        _tags.add(t);
        changed = true;
      }
    }
    _tagIn.clear();
    if (changed) {
      setState(() {});
      _touch();
    }
  }

  Future<List<Map<String, dynamic>>> _roles() async {
    final r = await ref
        .read(kantorApiProvider)
        ?.get('/api/offices/${Uri.encodeComponent(widget.officeId)}/roles');
    return [
      for (final x in (r as List? ?? const []))
        if (x is Map && x['archived'] != true) Map<String, dynamic>.from(x),
    ];
  }

  Future<void> _pickRole() async {
    try {
      final roles = await _roles();
      if (!mounted) return;
      final id = await showChunkyBottomSheet<String>(
        context,
        title: 'Sebut role',
        builder: (c) => roles.isEmpty
            ? const Text('Belum ada role di kantor ini.')
            : Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in roles)
                      ChunkyTile(
                        title: '${r['name']}',
                        subtitle: '${r['title'] ?? ''}',
                        dense: true,
                        onTap: () => Navigator.pop(c, '${r['id']}'),
                      ),
                  ],
                ),
              ),
      );
      if (id != null) _insert('@$id ');
    } on KantorException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _copy() async {
    final t = _title.text.isEmpty
        ? _body.text
        : '# ${_title.text}\n\n${_body.text}';
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) _toast('Markdown disalin.', bad: false);
  }

  Future<void> _purge() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus permanen?',
      message: 'Catatan ini tidak bisa dikembalikan lagi.',
      confirmLabel: 'Hapus permanen',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(kantorApiProvider)!
          .delete('$_base/${Uri.encodeComponent(_id)}');
      _gone = true;
      if (!mounted) return;
      _toast('Catatan dihapus permanen.', bad: false);
      Navigator.of(context).pop();
    } on KantorException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _toCard() async {
    var mode = 'one';
    String? who;
    final repo = TextEditingController(text: '${_n['room'] ?? ''}');
    List<Map<String, dynamic>> roles = const [];
    try {
      roles = await _roles();
    } catch (_) {}
    if (!mounted) return;
    final go = await showChunkyBottomSheet<bool>(
      context,
      title: 'Jadikan kartu',
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (v) => set(() => mode = v ?? 'one'),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'one',
                    title: Text(
                      'Satu kartu untuk seluruh catatan (item centang jadi checklist)',
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'each',
                    title: Text(
                      'Satu kartu per item centang yang belum selesai',
                    ),
                  ),
                ],
              ),
            ),
            DropdownButtonFormField<String?>(
              initialValue: who,
              decoration: const InputDecoration(labelText: 'Penanggung jawab'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Belum ditugaskan'),
                ),
                for (final r in roles)
                  DropdownMenuItem(
                    value: '${r['id']}',
                    child: Text('${r['name']}'),
                  ),
              ],
              onChanged: (v) => set(() => who = v),
            ),
            const SizedBox(height: GhinaSpace.md),
            ChunkyTextField(label: 'Repo / ruangan', controller: repo),
            const SizedBox(height: GhinaSpace.lg),
            ChunkyButton(
              label: 'Buat kartu',
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
        ),
      ),
    );
    final room = repo.text.trim();
    repo.dispose();
    if (go != true || !mounted) return;
    await _flush();
    try {
      final r = await ref.read(kantorApiProvider)!.post(
        '$_base/${Uri.encodeComponent(_id)}/to-card',
        {'mode': mode, 'who': ?who, if (room.isNotEmpty) 'repo': room},
      );
      final n = (r is Map ? (r['cards'] as List?)?.length : null) ?? 1;
      if (mounted)
        _toast(n > 1 ? '$n kartu dibuat.' : 'Kartu dibuat.', bad: false);
    } on KantorException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _sendRole() async {
    List<Map<String, dynamic>> roles;
    try {
      roles = await _roles();
    } on KantorException catch (e) {
      if (mounted) _toast(e.message);
      return;
    }
    if (!mounted) return;
    if (roles.isEmpty) {
      _toast('Belum ada role di kantor ini.');
      return;
    }
    var role = '${roles.first['id']}';
    var live = false;
    final go = await showChunkyBottomSheet<bool>(
      context,
      title: 'Kirim ke role',
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Catatan ditambahkan ke buku catatan role yang dipilih.',
              style: GhinaType.bodyS.copyWith(
                color: context.ghina.textSecondary,
              ),
            ),
            const SizedBox(height: GhinaSpace.md),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final r in roles)
                  DropdownMenuItem(
                    value: '${r['id']}',
                    child: Text(
                      '${r['name']}${(r['title'] ?? '') == '' ? '' : ' · ${r['title']}'}',
                    ),
                  ),
              ],
              onChanged: (v) => set(() => role = v ?? role),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: live,
              onChanged: (v) => set(() => live = v ?? false),
              title: const Text('Kirim juga ke sesi yang sedang jalan'),
            ),
            const SizedBox(height: GhinaSpace.md),
            ChunkyButton(
              label: 'Kirim',
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    await _flush();
    try {
      final r = await ref.read(kantorApiProvider)!.post(
        '$_base/${Uri.encodeComponent(_id)}/send-role',
        {'role': role, 'live': live},
      );
      final sentLive = r is Map && r['live'] == true;
      if (mounted)
        _toast(
          sentLive
              ? 'Terkirim ke buku catatan dan sesi yang jalan.'
              : 'Masuk ke buku catatan role.',
          bad: false,
        );
    } on KantorException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) async {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'notes' || _dirty)
        return;
      if (m['office'] != '*' && m['office'] != widget.officeId) return;
      if (m['note'] != null && m['note'] != _id) return;
      final api = ref.read(kantorApiProvider);
      if (api == null) return;
      for (final v in ['aktif', 'arsip', 'sampah']) {
        try {
          final r = await api.get(_base, query: {'view': v});
          final hit = (r is Map ? r['notes'] as List? : null)
              ?.whereType<Map>()
              .where((x) => x['id'] == _id)
              .firstOrNull;
          if (hit == null) continue;
          if (!mounted || _dirty || hit['updatedAt'] == _n['updatedAt']) return;
          setState(() {
            _n = Map<String, dynamic>.from(hit);
            _title.text = '${hit['title'] ?? ''}';
            _body.text = '${hit['body'] ?? ''}';
            _tags = [for (final t in (hit['tags'] as List? ?? const [])) '$t'];
            _color = noteColors.contains(hit['color'])
                ? hit['color'] as String
                : _color;
            _state = 'Diperbarui oleh ${hit['author'] ?? 'orang lain'}';
          });
          return;
        } catch (_) {
          return;
        }
      }
    });
    final g = context.ghina;
    final api = ref.watch(kantorApiProvider);
    final deleted = _n['deleted'] == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: g.background,
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Catatan'),
              Text(
                _state,
                style: GhinaType.caption.copyWith(
                  color: _stateBad ? GhinaColors.red.base : g.textMuted,
                ),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(GhinaSpace.page),
          children: [
            ChunkyTextField(
              hint: 'Judul catatan',
              controller: _title,
              onChanged: (_) => _touch(),
            ),
            const SizedBox(height: GhinaSpace.md),
            Row(
              children: [
                for (final c in noteColors)
                  Padding(
                    padding: const EdgeInsets.only(right: GhinaSpace.sm),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setState(() => _color = c);
                        _touch();
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: noteSwatch(c).base,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c
                                ? g.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GhinaSpace.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () {
                      setState(() => _tags.remove(t));
                      _touch();
                    },
                  ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _tagIn,
                    decoration: const InputDecoration(
                      hintText: 'Tambah tag',
                      isDense: true,
                    ),
                    onSubmitted: _addTags,
                    onChanged: (v) {
                      if (v.endsWith(',')) _addTags(v);
                    },
                    onTapOutside: (_) => _addTags(_tagIn.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GhinaSpace.lg),
            ChunkySegmented<bool>(
              segments: const [
                ChunkySegment(value: false, label: 'Tulis'),
                ChunkySegment(value: true, label: 'Pratinjau'),
              ],
              value: _preview,
              onChanged: (v) => setState(() => _preview = v),
            ),
            const SizedBox(height: GhinaSpace.sm),
            if (!_preview) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Tool('Centang', () => _insert('- [ ] ')),
                    _Tool('Judul', () => _insert('## ')),
                    _Tool('Tebal', () => _insert('**', wrap: true)),
                    _Tool('[[Wiki]]', () => _insert('[[]]', back: 2)),
                    if (!_kompleks) _Tool('@Role', _pickRole),
                  ],
                ),
              ),
              ChunkyTextField(
                hint: 'Tulis dengan markdown. Daftar tugas: - [ ] langkah',
                controller: _body,
                maxLines: null,
                minLines: 10,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _touch(),
              ),
            ] else if (_body.text.trim().isEmpty)
              Text(
                'Belum ada isi.',
                style: GhinaType.body.copyWith(color: g.textMuted),
              )
            else
              WikiMarkdown(
                text: _body.text,
                api: api,
                onWikiLink: (t) =>
                    openWikiPage(context, officeId: widget.officeId, ref: t),
                onToggleTask: (i) {
                  setState(() => _body.text = toggleTask(_body.text, i));
                  _touch();
                },
              ),
            const SizedBox(height: GhinaSpace.lg),
            if (deleted) ...[
              ChunkyCard(
                tinted: GhinaColors.blue,
                padding: const EdgeInsets.all(GhinaSpace.md),
                child: const Text('Catatan ini ada di Sampah.'),
              ),
              const SizedBox(height: GhinaSpace.md),
              Wrap(
                spacing: GhinaSpace.sm,
                children: [
                  ChunkyButton(
                    label: 'Pulihkan',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    expand: false,
                    onPressed: () =>
                        _finish({'deleted': false}, 'Catatan dipulihkan.'),
                  ),
                  ChunkyButton(
                    label: 'Hapus permanen',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.danger,
                    expand: false,
                    onPressed: _purge,
                  ),
                  ChunkyButton(
                    label: 'Salin markdown',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    expand: false,
                    onPressed: _copy,
                  ),
                ],
              ),
            ] else
              Wrap(
                spacing: GhinaSpace.sm,
                runSpacing: GhinaSpace.sm,
                children: [
                  _Act(
                    _n['pinned'] == true ? 'Lepas sematan' : 'Sematkan',
                    () => _setFlag({'pinned': _n['pinned'] != true}),
                  ),
                  if (!_kompleks)
                    _Act(
                      _n['wall'] == true
                          ? 'Lepas dari dinding'
                          : 'Tempel di dinding',
                      () => _setFlag({'wall': _n['wall'] != true}),
                    ),
                  _Act(
                    _n['archived'] == true
                        ? 'Keluarkan dari arsip'
                        : 'Arsipkan',
                    () => _finish(
                      {'archived': _n['archived'] != true},
                      _n['archived'] == true
                          ? 'Dikeluarkan dari arsip.'
                          : 'Dipindah ke arsip.',
                    ),
                  ),
                  if (!_kompleks) _Act('Jadikan kartu', _toCard),
                  if (!_kompleks) _Act('Kirim ke role', _sendRole),
                  _Act('Salin markdown', _copy),
                  _Act(
                    'Hapus',
                    () => _finish({'deleted': true}, 'Dipindah ke sampah.'),
                    danger: true,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ActionChip(label: Text(label), onPressed: onTap),
  );
}

class _Act extends StatelessWidget {
  const _Act(this.label, this.onTap, {this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ChunkyButton(
    label: label,
    size: ChunkyButtonSize.small,
    variant: danger ? ChunkyButtonVariant.danger : ChunkyButtonVariant.outline,
    expand: false,
    onPressed: onTap,
  );
}
