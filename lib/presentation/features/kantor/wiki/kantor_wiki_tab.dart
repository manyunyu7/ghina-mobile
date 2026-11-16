import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import '../widgets/kantor_wide.dart';
import 'wiki_editor_screen.dart';
import 'wiki_format.dart';
import 'wiki_page_screen.dart';
import 'wiki_tree.dart';

/// Wiki of one office (or `_kompleks` for the shared one): page tree, search,
/// and the entry to read / write pages.
///
/// Di layar lebar: pohon halaman + pencarian di kiri, halaman yang dibuka di
/// panel kanan ([KantorMasterDetail]). Di layar sempit tetap satu daftar dan
/// halaman dibuka penuh.
class KantorWikiTab extends ConsumerStatefulWidget {
  const KantorWikiTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorWikiTab> createState() => _KantorWikiTabState();
}

class _KantorWikiTabState extends ConsumerState<KantorWikiTab> {
  final _search = TextEditingController();
  final _open = <String>{};
  WikiTree? _tree;
  List<dynamic> _sources = const [];
  List<dynamic>? _results;
  Object? _error;
  bool _loading = true;
  bool _pbOnly = false;
  Timer? _debounce;
  int _searchSeq = 0;

  String get _base => '/api/offices/${Uri.encodeComponent(widget.officeId)}';
  bool get _isKompleks => widget.officeId == '_kompleks';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KantorWikiTab old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId) {
      _open.clear();
      _search.clear();
      _results = null;
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
      final list = await api.get('$_base/wiki');
      var sources = const <dynamic>[];
      if (!_isKompleks) {
        try {
          sources = (await api.get('$_base/wiki-sources') as List?) ?? const [];
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _tree = WikiTree((list as List?) ?? const []);
        _sources = sources;
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

  void _onQuery(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final api = ref.read(kantorApiProvider);
      if (api == null) return;
      final seq = ++_searchSeq;
      try {
        final r = await api.get('$_base/wiki-search', query: {'q': query});
        if (!mounted || seq != _searchSeq) return;
        setState(() => _results = (r as List?) ?? const []);
      } on KantorException catch (e) {
        if (mounted)
          showToastBadge(
            context,
            message: e.message,
            icon: Icons.error_outline,
          );
      }
    });
  }

  // Membuka halaman lewat [KantorMasterDetail]: sempit = halaman penuh lalu
  // daftar dimuat ulang diam-diam saat kembali (onClosed), lebar = panel kanan.
  Future<void> _newPage(void Function(String) open) async {
    // editor: sempit tetap halaman penuh, lebar jadi panel samping
    final slug = await kantorPushAdaptive<String>(
      context,
      (_) => WikiEditorScreen(officeId: widget.officeId),
    );
    if (!mounted) return;
    await _load(quiet: true);
    if (slug != null && mounted) open(slug);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'wiki') return;
      if (m['office'] != '*' && m['office'] != widget.officeId) return;
      _load(quiet: true);
    });
    return KantorMasterDetail<String>(
      // ganti kantor = pilihan halaman ikut kosong lagi
      key: ValueKey('wiki-${widget.officeId}'),
      keyOf: (slug) => slug,
      master: _master,
      detail: (c, slug) => WikiPageScreen(
        officeId: widget.officeId,
        pageRef: slug,
        // panel kanan tidak pernah "kembali", jadi pohon disegarkan langsung
        // setiap halaman diubah / dipindah / dihapus
        onChanged: kantorIsWide(c) ? () => _load(quiet: true) : null,
      ),
      empty: const KantorPaneEmpty(
        icon: Icons.menu_book_outlined,
        text: 'Pilih halaman wiki di kiri untuk membacanya.',
      ),
      onClosed: () {
        if (mounted) _load(quiet: true);
      },
    );
  }

  Widget _master(
    BuildContext context,
    String? sel,
    void Function(String) open,
  ) {
    if (_loading && _tree == null) return const KantorLoading();
    if (_error != null && _tree == null) {
      return KantorErrorView(error: _error!, onRetry: _load);
    }
    final tree = _tree!;
    final g = context.ghina;
    return RefreshIndicator(
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
            hint: 'Cari di wiki',
            prefixIcon: Icons.search,
            onChanged: _onQuery,
          ),
          const SizedBox(height: GhinaSpace.md),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Halaman baru',
                  icon: Icons.add,
                  size: ChunkyButtonSize.small,
                  onPressed: () => _newPage(open),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              ChunkyChip(
                label: 'Playbook',
                selected: _pbOnly,
                onTap: () => setState(() => _pbOnly = !_pbOnly),
              ),
            ],
          ),
          const SizedBox(height: GhinaSpace.lg),
          if (_results != null)
            ..._searchResults(g, sel, open)
          else if (_pbOnly)
            ..._playbooks(tree, g, sel, open)
          else
            ..._treeRows(tree, g, sel, open),
          if (_results == null && !_isKompleks && _sources.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.xl),
            const SectionHeader(title: 'Dari repo (hanya baca)'),
            for (final s in _sources.whereType<Map>())
              ChunkyTile(
                title: '${s['label']}',
                subtitle: '${s['file']}',
                leading: const Icon(Icons.description_outlined),
                showChevron: true,
                dense: true,
                onTap: () => kantorPushAdaptive<void>(
                  context,
                  (_) => WikiSourceScreen(
                    officeId: widget.officeId,
                    file: '${s['file']}',
                    label: '${s['label']}',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _searchResults(
    GhinaTokens g,
    String? sel,
    void Function(String) open,
  ) {
    final r = _results!;
    if (r.isEmpty) {
      return [
        Text(
          'Tidak ada halaman yang cocok.',
          style: GhinaType.body.copyWith(color: g.textSecondary),
        ),
      ];
    }
    return [
      const SectionHeader(title: 'Hasil pencarian'),
      for (final x in r.whereType<Map>())
        ChunkyTile(
          title: '${x['title']}',
          subtitle: '${x['snippet'] ?? ''}'.replaceAll('\n', ' '),
          showChevron: true,
          tinted: sel != null && sel == '${x['slug']}'
              ? GhinaColors.blue
              : null,
          onTap: () => open('${x['slug']}'),
        ),
    ];
  }

  List<Widget> _playbooks(
    WikiTree tree,
    GhinaTokens g,
    String? sel,
    void Function(String) open,
  ) {
    final pbs = tree.pages.where((p) => p['playbook'] == true).toList()
      ..sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
    if (pbs.isEmpty) {
      return [
        EmptyState(
          title: 'Belum ada playbook',
          message: 'Playbook dibuat dari halaman wiki di web Kantor.',
          mood: MascotMood.sleeping,
          compact: true,
        ),
      ];
    }
    return [
      const SectionHeader(title: 'Playbook'),
      for (final p in pbs)
        ChunkyTile(
          title: '${p['title']}',
          subtitle: (p['roles'] as List?)?.join(', '),
          leading: Text(
            '${p['icon'] ?? '📘'}',
            style: const TextStyle(fontSize: 20),
          ),
          showChevron: true,
          tinted: sel != null && sel == p['slug'] ? GhinaColors.blue : null,
          onTap: () => open('${p['slug']}'),
        ),
    ];
  }

  List<Widget> _treeRows(
    WikiTree tree,
    GhinaTokens g,
    String? sel,
    void Function(String) open,
  ) {
    if (tree.pages.isEmpty) {
      return [
        EmptyState(
          title: 'Belum ada halaman',
          message: 'Tulis halaman pertama wiki kantor ini, yuk.',
          mood: MascotMood.sleeping,
          actionLabel: 'Halaman baru',
          onAction: () => _newPage(open),
        ),
      ];
    }
    final rows = tree.flatten(_open);
    return [
      const SectionHeader(title: 'Halaman'),
      for (final (p, depth) in rows)
        _TreeRow(
          page: p,
          depth: depth,
          expandable: tree.hasKids(p['slug'] as String),
          open: _open.contains(p['slug']),
          selected: sel != null && sel == p['slug'],
          onToggle: () => setState(() {
            final s = p['slug'] as String;
            _open.contains(s) ? _open.remove(s) : _open.add(s);
          }),
          onTap: () => open(p['slug'] as String),
        ),
    ];
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.page,
    required this.depth,
    required this.expandable,
    required this.open,
    required this.onToggle,
    required this.onTap,
    this.selected = false,
  });

  final Map<String, dynamic> page;
  final int depth;
  final bool expandable;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// Halaman ini sedang terbuka di panel kanan (layar lebar).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final icon = page['icon'] as String?;
    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0),
      child: InkWell(
        borderRadius: GhinaRadii.rMd,
        onTap: onTap,
        child: Ink(
          decoration: selected
              ? BoxDecoration(
                  color: GhinaColors.blue.tint(Theme.of(context).brightness),
                  borderRadius: GhinaRadii.rMd,
                )
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: expandable
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: open ? 'Ciutkan' : 'Buka',
                          icon: Icon(
                            open ? Icons.expand_more : Icons.chevron_right,
                            color: g.textSecondary,
                          ),
                          onPressed: onToggle,
                        )
                      : null,
                ),
                Text(
                  icon != null && icon.isNotEmpty ? icon : '·',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  child: Text(
                    '${page['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.body.w(700).copyWith(color: g.textPrimary),
                  ),
                ),
                if (page['playbook'] == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('📘', style: TextStyle(fontSize: 14)),
                  ),
                const SizedBox(width: GhinaSpace.sm),
                Text(
                  agoId(page['updated_at']),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
