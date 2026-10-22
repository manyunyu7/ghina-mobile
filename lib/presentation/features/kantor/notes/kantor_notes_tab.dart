import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import '../wiki/wiki_format.dart';
import 'note_colors.dart';
import 'note_editor_screen.dart';

/// Sticky notes of one office (or `_kompleks`): search, tags, colors, pinned,
/// archive and trash views.
class KantorNotesTab extends ConsumerStatefulWidget {
  const KantorNotesTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorNotesTab> createState() => _KantorNotesTabState();
}

class _KantorNotesTabState extends ConsumerState<KantorNotesTab> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _notes = const [];
  List<Map<String, dynamic>> _tags = const [];
  String _view = 'aktif';
  String _q = '';
  String _tag = '';
  String _color = '';
  Object? _error;
  bool _loading = true;
  Timer? _debounce;

  String get _base =>
      '/api/offices/${Uri.encodeComponent(widget.officeId)}/notes';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KantorNotesTab old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId) {
      _search.clear();
      _q = _tag = _color = '';
      _view = 'aktif';
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await api.get(
        _base,
        query: {
          'view': _view,
          if (_q.isNotEmpty) 'q': _q,
          if (_tag.isNotEmpty) 'tag': _tag,
        },
      );
      if (!mounted) return;
      final m = r is Map ? r : const {};
      setState(() {
        _notes = [
          for (final n in (m['notes'] as List? ?? const []))
            if (n is Map) Map<String, dynamic>.from(n),
        ];
        _tags = [
          for (final n in (m['tags'] as List? ?? const []))
            if (n is Map) Map<String, dynamic>.from(n),
        ];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(officeId: widget.officeId, note: n),
      ),
    );
    if (mounted) _load(quiet: true);
  }

  Future<void> _create() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final n = await api.post(_base, {
        'title': '',
        'body': '',
        'color': _color.isEmpty ? 'kuning' : _color,
        'tags': [if (_tag.isNotEmpty) _tag],
      });
      if (!mounted || n is! Map) return;
      if (_view != 'aktif') _view = 'aktif';
      await _open({...Map<String, dynamic>.from(n), '_fresh': true});
    } on KantorException catch (e) {
      if (mounted)
        showToastBadge(context, message: e.message, icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'notes') return;
      if (m['office'] != '*' && m['office'] != widget.officeId) return;
      _load(quiet: true);
    });
    final g = context.ghina;
    final list = _color.isEmpty
        ? _notes
        : _notes.where((n) => n['color'] == _color).toList();
    final pinned = list.where((n) => n['pinned'] == true).toList();
    final rest = list.where((n) => n['pinned'] != true).toList();
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _load(quiet: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.md,
              GhinaSpace.page,
              96,
            ),
            children: [
              ChunkyTextField(
                controller: _search,
                hint: 'Cari catatan',
                prefixIcon: Icons.search,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    _q = v.trim();
                    _load(quiet: true);
                  });
                },
              ),
              const SizedBox(height: GhinaSpace.md),
              ChunkySegmented<String>(
                segments: const [
                  ChunkySegment(value: 'aktif', label: 'Aktif'),
                  ChunkySegment(value: 'arsip', label: 'Arsip'),
                  ChunkySegment(value: 'sampah', label: 'Sampah'),
                ],
                value: _view,
                onChanged: (v) {
                  setState(() => _view = v);
                  _load();
                },
              ),
              const SizedBox(height: GhinaSpace.md),
              Row(
                children: [
                  for (final c in noteColors)
                    Padding(
                      padding: const EdgeInsets.only(right: GhinaSpace.sm),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            setState(() => _color = _color == c ? '' : c),
                        child: Container(
                          width: 30,
                          height: 30,
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
              if (_tags.isNotEmpty || _tag.isNotEmpty) ...[
                const SizedBox(height: GhinaSpace.md),
                Wrap(
                  spacing: GhinaSpace.sm,
                  runSpacing: GhinaSpace.sm,
                  children: [
                    for (final t
                        in (_tags.isEmpty
                            ? [
                                {'tag': _tag, 'n': 0},
                              ]
                            : _tags))
                      ChunkyChip(
                        label: '${t['tag']}${t['n'] == 0 ? '' : ' ${t['n']}'}',
                        selected: _tag == t['tag'],
                        onTap: () {
                          setState(
                            () => _tag = _tag == t['tag'] ? '' : '${t['tag']}',
                          );
                          _load(quiet: true);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: GhinaSpace.lg),
              if (_loading && _notes.isEmpty)
                const KantorLoading(count: 3)
              else if (_error != null && _notes.isEmpty)
                SizedBox(
                  height: 320,
                  child: KantorErrorView(error: _error!, onRetry: _load),
                )
              else if (list.isEmpty)
                _empty()
              else ...[
                if (pinned.isNotEmpty) ...[
                  const SectionHeader(title: 'Disematkan'),
                  _Masonry(notes: pinned, onTap: _open),
                ],
                if (pinned.isNotEmpty && rest.isNotEmpty)
                  const SectionHeader(title: 'Lainnya'),
                if (rest.isNotEmpty) _Masonry(notes: rest, onTap: _open),
              ],
            ],
          ),
        ),
        if (_view == 'aktif')
          Positioned(
            right: GhinaSpace.page,
            bottom: GhinaSpace.page,
            child: FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Catatan baru'),
            ),
          ),
      ],
    );
  }

  Widget _empty() {
    final filtered = _q.isNotEmpty || _tag.isNotEmpty || _color.isNotEmpty;
    final (title, msg) = filtered
        ? (
            'Tidak ada yang cocok',
            'Tidak ada catatan yang cocok dengan penyaring ini.',
          )
        : switch (_view) {
            'arsip' => (
              'Arsip kosong',
              'Catatan yang sudah tidak dipakai bisa dipindah ke sini.',
            ),
            'sampah' => (
              'Sampah kosong',
              'Catatan yang dihapus mampir di sini dulu sebelum hilang permanen.',
            ),
            _ => (
              'Belum ada catatan',
              'Tulis catatan umum untuk ${widget.officeId == '_kompleks' ? 'semua kantor' : 'kantor ini'}: daftar tugas, ide, tautan, apa saja.',
            ),
          };
    return EmptyState(
      title: title,
      message: msg,
      mood: MascotMood.sleeping,
      compact: true,
      actionLabel: !filtered && _view == 'aktif' ? 'Catatan baru' : null,
      onAction: !filtered && _view == 'aktif' ? _create : null,
    );
  }
}

/// Two columns, each note on the shorter one.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.notes, required this.onTap});

  final List<Map<String, dynamic>> notes;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    final cols = <List<Map<String, dynamic>>>[[], []];
    final h = [0, 0];
    for (final n in notes) {
      final i = h[0] <= h[1] ? 0 : 1;
      cols[i].add(n);
      h[i] +=
          60 +
          ('${n['body'] ?? ''}'.length.clamp(0, 220)) +
          ('${n['title'] ?? ''}'.length > 20 ? 20 : 0);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i == 1) const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Column(
              children: [
                for (final n in cols[i])
                  Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                    child: _NoteCard(note: n, onTap: () => onTap(n)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final Map<String, dynamic> note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final title = '${note['title'] ?? ''}';
    final body = '${note['body'] ?? ''}';
    final tags = (note['tags'] as List?)?.cast<dynamic>() ?? const [];
    return ChunkyCard(
      tinted: noteSwatch(note['color'] as String?),
      onTap: onTap,
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Tanpa judul' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              if (note['pinned'] == true)
                Icon(Icons.push_pin, size: 16, color: g.textSecondary),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            ),
          ],
          if (tags.isNotEmpty || note['wall'] == true) ...[
            const SizedBox(height: GhinaSpace.sm),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final t in tags)
                  ChunkyPill(label: '$t', color: GhinaColors.gray),
                if (note['wall'] == true)
                  ChunkyPill(label: 'di dinding', color: GhinaColors.blue),
              ],
            ),
          ],
          const SizedBox(height: GhinaSpace.sm),
          Text(
            '${note['author'] ?? ''} · ${agoId(note['updatedAt'])}',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }
}
