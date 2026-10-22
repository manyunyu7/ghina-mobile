import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'wiki_editor_screen.dart';
import 'wiki_format.dart';
import 'wiki_page_screen.dart';
import 'wiki_tree.dart';

/// Wiki of one office (or `_kompleks` for the shared one): page tree, search,
/// and the entry to read / write pages.
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

  Future<void> _openPage(String ref_) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WikiPageScreen(officeId: widget.officeId, pageRef: ref_),
      ),
    );
    if (mounted) _load(quiet: true);
  }

  Future<void> _newPage({bool playbook = false}) async {
    final slug = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WikiEditorScreen(officeId: widget.officeId),
      ),
    );
    if (!mounted) return;
    await _load(quiet: true);
    if (slug != null && mounted) _openPage(slug);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'wiki') return;
      if (m['office'] != '*' && m['office'] != widget.officeId) return;
      _load(quiet: true);
    });
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
                  onPressed: _newPage,
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
            ..._searchResults(g)
          else if (_pbOnly)
            ..._playbooks(tree, g)
          else
            ..._treeRows(tree, g),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WikiSourceScreen(
                      officeId: widget.officeId,
                      file: '${s['file']}',
                      label: '${s['label']}',
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _searchResults(GhinaTokens g) {
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
          onTap: () => _openPage('${x['slug']}'),
        ),
    ];
  }

  List<Widget> _playbooks(WikiTree tree, GhinaTokens g) {
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
          onTap: () => _openPage('${p['slug']}'),
        ),
    ];
  }

  List<Widget> _treeRows(WikiTree tree, GhinaTokens g) {
    if (tree.pages.isEmpty) {
      return [
        EmptyState(
          title: 'Belum ada halaman',
          message: 'Tulis halaman pertama wiki kantor ini, yuk.',
          mood: MascotMood.sleeping,
          actionLabel: 'Halaman baru',
          onAction: _newPage,
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
          onToggle: () => setState(() {
            final s = p['slug'] as String;
            _open.contains(s) ? _open.remove(s) : _open.add(s);
          }),
          onTap: () => _openPage(p['slug'] as String),
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
  });

  final Map<String, dynamic> page;
  final int depth;
  final bool expandable;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final icon = page['icon'] as String?;
    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0),
      child: InkWell(
        borderRadius: GhinaRadii.rMd,
        onTap: onTap,
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
    );
  }
}
