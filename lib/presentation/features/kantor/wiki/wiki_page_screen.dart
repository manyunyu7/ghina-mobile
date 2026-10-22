import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';
import 'wiki_editor_screen.dart';
import 'wiki_format.dart';
import 'wiki_history_screen.dart';
import 'wiki_markdown.dart';
import 'wiki_tree.dart';

const _emoji =
    '📄 📘 📗 📙 📕 📓 📚 🗂️ 📁 🧭 🚀 🛠️ ⚙️ 🔧 🧪 🐛 🔒 🔑 🌐 📱 💻 🖥️ 🗄️ ☁️ 📦 🧩 🎯 💡 ⭐ 🔥 ✅ ⚠️ 📌 📝 📊 📈 💰 🧾 👥 🤝 📅 ⏱️ 🏗️ 🎨 🎵 🚆 🗺️ 🏠 ❓';

/// Opens a wiki page by slug or title (as written in a `[[link]]`); pages that
/// do not exist yet open the editor with that title.
Future<void> openWikiPage(
  BuildContext context, {
  required String officeId,
  required String ref,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => WikiPageScreen(officeId: officeId, pageRef: ref),
  ),
);

/// One wiki page: read, then edit / move / history / delete.
class WikiPageScreen extends ConsumerStatefulWidget {
  const WikiPageScreen({
    super.key,
    required this.officeId,
    required this.pageRef,
  });

  final String officeId;
  final String pageRef;

  @override
  ConsumerState<WikiPageScreen> createState() => _WikiPageScreenState();
}

class _WikiPageScreenState extends ConsumerState<WikiPageScreen> {
  Map<String, dynamic>? _page;
  WikiTree _tree = WikiTree(const []);
  Object? _error;
  bool _loading = true;
  String? _hint;

  String get _base => '/api/offices/${Uri.encodeComponent(widget.officeId)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool live = false}) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    if (!live) setState(() => _loading = true);
    try {
      final res = await Future.wait([
        api.get(
          '$_base/wiki/page',
          query: {'ref': _page?['slug'] ?? widget.pageRef},
        ),
        api.get('$_base/wiki'),
      ]);
      if (!mounted) return;
      final p = res[0] is Map ? Map<String, dynamic>.from(res[0] as Map) : null;
      setState(() {
        if (live &&
            p != null &&
            _page != null &&
            p['updatedAt'] != _page!['updatedAt']) {
          _hint =
              'Halaman diperbarui oleh ${p['author'] ?? 'seseorang'} ${agoId(p['updatedAt'])}.';
        }
        _page = p;
        _tree = WikiTree((res[1] as List?) ?? const []);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (live) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String m, {bool bad = false}) => showToastBadge(
    context,
    message: m,
    icon: bad ? Icons.error_outline : Icons.check_circle_outline,
  );

  Future<void> _edit({
    Map<String, dynamic>? page,
    String? title,
    String? parent,
  }) async {
    final slug = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WikiEditorScreen(
          officeId: widget.officeId,
          page: page,
          initialTitle: title,
          parent: parent,
        ),
      ),
    );
    if (!mounted) return;
    if (slug == null) return;
    if (page == null && parent == null && _page == null) {
      // created the page this screen was asking for
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              WikiPageScreen(officeId: widget.officeId, pageRef: slug),
        ),
      );
    } else if (page == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              WikiPageScreen(officeId: widget.officeId, pageRef: slug),
        ),
      );
      if (mounted) _load(live: true);
    } else {
      _hint = null;
      _load(live: true);
    }
  }

  void _followLink(String title) {
    final hit = _tree.find(title) ?? _tree.byId(slugify(title));
    if (hit != null) {
      openWikiPage(
        context,
        officeId: widget.officeId,
        ref: hit['slug'] as String,
      );
    } else {
      _edit(title: title);
    }
  }

  Future<void> _setIcon(String icon) async {
    final p = _page;
    final api = ref.read(kantorApiProvider);
    if (p == null || api == null) return;
    try {
      await api.post('$_base/wiki', {
        'title': p['title'],
        'body': p['body'],
        'prevSlug': p['slug'],
        'icon': icon,
        'msg': icon.isEmpty ? 'Ikon dihapus' : 'Ikon diubah',
      });
      await _load(live: true);
    } on KantorException catch (e) {
      _toast(e.message, bad: true);
    }
  }

  Future<void> _pickIcon() async {
    final ctl = TextEditingController();
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: 'Pilih ikon',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in _emoji.split(' '))
                    InkWell(
                      borderRadius: GhinaRadii.rMd,
                      onTap: () => Navigator.pop(c, e),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            controller: ctl,
            hint: 'Ketik emoji sendiri',
            maxLength: 4,
            onSubmitted: (v) => Navigator.pop(c, v.trim()),
          ),
          const SizedBox(height: GhinaSpace.sm),
          Row(
            children: [
              if ((_page?['icon'] as String?)?.isNotEmpty ?? false)
                Expanded(
                  child: ChunkyButton(
                    label: 'Hapus ikon',
                    variant: ChunkyButtonVariant.outline,
                    size: ChunkyButtonSize.small,
                    onPressed: () => Navigator.pop(c, ''),
                  ),
                ),
              if ((_page?['icon'] as String?)?.isNotEmpty ?? false)
                const SizedBox(width: GhinaSpace.sm),
              Expanded(
                child: ChunkyButton(
                  label: 'Pakai',
                  size: ChunkyButtonSize.small,
                  onPressed: () => Navigator.pop(c, ctl.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    ctl.dispose();
    if (picked != null) _setIcon(picked);
  }

  Future<void> _move() async {
    final p = _page;
    final api = ref.read(kantorApiProvider);
    if (p == null || api == null) return;
    final slug = p['slug'] as String;
    final choices = _tree.parentChoices(slug);
    final current = (p['parent'] as String?) ?? '';
    final picked = await showChunkyBottomSheet<String>(
      context,
      title: 'Pindahkan "${p['title']}"',
      builder: (c) => Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            _ParentTile(
              label: '(Halaman utama)',
              depth: 0,
              selected: current.isEmpty,
              onTap: () => Navigator.pop(c, ''),
            ),
            for (final (k, d) in choices)
              _ParentTile(
                label: '${k['icon'] ?? ''} ${k['title']}'.trim(),
                depth: d + 1,
                selected: k['slug'] == current,
                onTap: () => Navigator.pop(c, k['slug'] as String),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    final sibs = picked.isEmpty ? _tree.kids('') : _tree.kids(picked);
    final last = sibs.isEmpty
        ? 0
        : sibs
              .map((x) => ((x['ord'] as num?) ?? 0).toInt())
              .reduce((a, b) => a > b ? a : b);
    try {
      await api.post('$_base/wiki-move', {
        'slug': slug,
        'parent': picked,
        'ord': last + 10,
      });
      _toast('Halaman dipindahkan.');
      await _load(live: true);
    } on KantorException catch (e) {
      _toast(e.message, bad: true);
    }
  }

  Future<void> _delete() async {
    final p = _page;
    final api = ref.read(kantorApiProvider);
    if (p == null || api == null) return;
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus halaman?',
      message: 'Halaman "${p['title']}" dan riwayatnya akan dihapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await api.delete(
        '$_base/wiki/${Uri.encodeComponent(p['slug'] as String)}',
      );
      if (!mounted) return;
      _toast('Halaman dihapus.');
      Navigator.of(context).pop();
    } on KantorException catch (e) {
      _toast(e.message, bad: true);
    }
  }

  Future<void> _history() async {
    final p = _page;
    if (p == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WikiHistoryScreen(officeId: widget.officeId, page: p),
      ),
    );
    if (changed == true && mounted) _load(live: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'wiki') return;
      if (m['office'] != '*' && m['office'] != widget.officeId) return;
      final cur = _page?['slug'] ?? widget.pageRef;
      if (m['slug'] == null || m['slug'] == cur) _load(live: true);
    });
    final p = _page;
    final api = ref.watch(kantorApiProvider);
    return Scaffold(
      backgroundColor: context.ghina.background,
      appBar: AppBar(
        title: Text(
          p?['title'] as String? ?? 'Wiki',
          overflow: TextOverflow.ellipsis,
        ),
        actions: p == null
            ? null
            : [
                IconButton(
                  tooltip: 'Ubah',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(page: p),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'sub':
                        _edit(parent: p['slug'] as String);
                      case 'icon':
                        _pickIcon();
                      case 'move':
                        _move();
                      case 'hist':
                        _history();
                      case 'del':
                        _delete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'sub',
                      child: Text('Sub-halaman baru'),
                    ),
                    const PopupMenuItem(value: 'icon', child: Text('Ikon')),
                    if (p['slug'] != 'beranda')
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('Pindahkan'),
                      ),
                    const PopupMenuItem(value: 'hist', child: Text('Riwayat')),
                    if (p['slug'] != 'beranda')
                      const PopupMenuItem(value: 'del', child: Text('Hapus')),
                  ],
                ),
              ],
      ),
      body: _loading
          ? const KantorLoading()
          : _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : p == null
          ? _missing()
          : RefreshIndicator(
              onRefresh: () => _load(live: true),
              child: _body(p, api),
            ),
    );
  }

  Widget _missing() {
    final title = widget.pageRef == 'beranda'
        ? 'Beranda'
        : widget.pageRef.replaceAll('-', ' ');
    return Padding(
      padding: const EdgeInsets.all(GhinaSpace.page),
      child: EmptyState(
        title: widget.pageRef == 'beranda'
            ? 'Beranda belum ditulis'
            : 'Halaman belum ada',
        message: 'Belum ada halaman dengan nama ini. Mau dibuat sekarang?',
        mood: MascotMood.thinking,
        actionLabel: 'Buat halaman ini',
        onAction: () => _edit(
          title: title.isEmpty
              ? title
              : title[0].toUpperCase() + title.substring(1),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> p, KantorApi? api) {
    final g = context.ghina;
    final body = (p['body'] as String?) ?? '';
    final icon = (p['icon'] as String?) ?? '';
    final crumbs =
        (p['crumbs'] as List?)?.whereType<Map>().toList() ?? const [];
    final children =
        (p['children'] as List?)?.whereType<Map>().toList() ?? const [];
    final back =
        (p['backlinks'] as List?)?.whereType<Map>().toList() ?? const [];
    final pb = p['playbook'];
    final hasH1 = RegExp(r'^\s*#\s').hasMatch(body);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        48,
      ),
      children: [
        if (crumbs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                _Crumb(
                  'Wiki',
                  () => openWikiPage(
                    context,
                    officeId: widget.officeId,
                    ref: 'beranda',
                  ),
                ),
                for (final c in crumbs) ...[
                  Text('›', style: TextStyle(color: g.textMuted)),
                  _Crumb(
                    '${c['icon'] ?? ''} ${c['title']}'.trim(),
                    () => openWikiPage(
                      context,
                      officeId: widget.officeId,
                      ref: '${c['slug']}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.md),
            child: ChunkyCard(
              tinted: GhinaColors.blue,
              padding: const EdgeInsets.all(GhinaSpace.md),
              child: Text(
                _hint!,
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
          ),
        if (!hasH1)
          Padding(
            padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
            child: Text(
              '${icon.isEmpty ? '' : '$icon '}${p['title']}',
              style: GhinaType.h1.copyWith(color: g.textPrimary),
            ),
          ),
        Text(
          '${p['author'] ?? 'Tidak diketahui'} · ${agoId(p['updatedAt'])} · ${p['revs'] ?? 1} revisi',
          style: GhinaType.caption.copyWith(color: g.textMuted),
        ),
        const SizedBox(height: GhinaSpace.md),
        if (pb is Map) _PlaybookHead(pb: pb),
        WikiMarkdown(
          text: body,
          api: api,
          onWikiLink: _followLink,
          onMedia: (_) =>
              _toast('Lampiran dibuka lewat web Kantor.', bad: true),
        ),
        const SizedBox(height: GhinaSpace.xl),
        SectionHeader(
          title: 'Sub-halaman',
          actionLabel: '+ Sub-halaman',
          onAction: () => _edit(parent: p['slug'] as String),
        ),
        if (children.isEmpty)
          Text(
            'Belum ada sub-halaman.',
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          )
        else
          for (final c in children)
            ChunkyTile(
              title: '${c['title']}',
              subtitle: agoId(c['updated_at']),
              leading: Text(
                '${c['icon'] ?? '📄'}',
                style: const TextStyle(fontSize: 20),
              ),
              showChevron: true,
              dense: true,
              onTap: () => openWikiPage(
                context,
                officeId: widget.officeId,
                ref: '${c['slug']}',
              ),
            ),
        if (back.isNotEmpty) ...[
          const SizedBox(height: GhinaSpace.lg),
          const SectionHeader(title: 'Ditautkan dari'),
          Wrap(
            spacing: GhinaSpace.sm,
            runSpacing: GhinaSpace.sm,
            children: [
              for (final b in back)
                ActionChip(
                  label: Text('${b['title']}'),
                  onPressed: () => openWikiPage(
                    context,
                    officeId: widget.officeId,
                    ref: '${b['slug']}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: GhinaType.bodyS.copyWith(color: GhinaColors.blue.base),
      ),
    ),
  );
}

class _ParentTile extends StatelessWidget {
  const _ParentTile({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.fromLTRB(depth * 16.0, 12, 0, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GhinaType.body
                  .w(selected ? 800 : 600)
                  .copyWith(color: context.ghina.textPrimary),
            ),
          ),
          if (selected) Icon(Icons.check, color: GhinaColors.green.base),
        ],
      ),
    ),
  );
}

class _PlaybookHead extends StatelessWidget {
  const _PlaybookHead({required this.pb});
  final Map pb;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final roles = (pb['roles'] as List?)?.join(', ') ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: ChunkyCard(
        tinted: GhinaColors.blue,
        padding: const EdgeInsets.all(GhinaSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📘 Playbook',
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Dipegang oleh: ${roles.isEmpty ? 'belum ada role' : roles}',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
            if ('${pb['when'] ?? ''}'.isNotEmpty)
              Text(
                'Kapan dipakai: ${pb['when']}',
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            if (pb['always'] == true || pb['approval'] == true)
              Text(
                [
                  if (pb['always'] == true) 'Selalu dibacakan',
                  if (pb['approval'] == true) 'Minta persetujuan',
                ].join(' · '),
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Read-only repo source (CLAUDE.md, memory…).
class WikiSourceScreen extends ConsumerStatefulWidget {
  const WikiSourceScreen({
    super.key,
    required this.officeId,
    required this.file,
    required this.label,
  });

  final String officeId;
  final String file;
  final String label;

  @override
  ConsumerState<WikiSourceScreen> createState() => _WikiSourceScreenState();
}

class _WikiSourceScreenState extends ConsumerState<WikiSourceScreen> {
  String? _text;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _error = null);
    try {
      final r = await api.get(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/wiki-source',
        query: {'file': widget.file},
      );
      if (mounted) setState(() => _text = r is Map ? '${r['text'] ?? ''}' : '');
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ghina.background,
    appBar: AppBar(title: Text(widget.label)),
    body: _error != null
        ? KantorErrorView(error: _error!, onRetry: _load)
        : _text == null
        ? const KantorLoading()
        : ListView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            children: [
              Text(
                'Sumber dari disk, ubah lewat repo.',
                style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
              ),
              const SizedBox(height: GhinaSpace.md),
              if (_text!.trim().isEmpty)
                const Text('File kosong.')
              else
                KantorMarkdown(_text!, selectable: true),
            ],
          ),
  );
}
