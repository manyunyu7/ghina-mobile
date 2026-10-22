import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'wiki_format.dart';

/// Revisions of one page, with a diff against the current text and restore.
/// Pops `true` when a revision was restored.
class WikiHistoryScreen extends ConsumerStatefulWidget {
  const WikiHistoryScreen({
    super.key,
    required this.officeId,
    required this.page,
  });

  final String officeId;
  final Map<String, dynamic> page;

  @override
  ConsumerState<WikiHistoryScreen> createState() => _WikiHistoryScreenState();
}

class _WikiHistoryScreenState extends ConsumerState<WikiHistoryScreen> {
  List<dynamic>? _revs;
  Object? _error;
  Map<String, dynamic>? _sel;
  bool _busy = false;

  String get _base => '/api/offices/${Uri.encodeComponent(widget.officeId)}';

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
        '$_base/wiki-revs/${Uri.encodeComponent(widget.page['slug'] as String)}',
      );
      if (mounted) setState(() => _revs = (r as List?) ?? const []);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(Object id) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final r = await api.get('$_base/wiki-rev/${Uri.encodeComponent('$id')}');
      if (mounted && r is Map)
        setState(() => _sel = Map<String, dynamic>.from(r));
    } on KantorException catch (e) {
      if (mounted)
        showToastBadge(context, message: e.message, icon: Icons.error_outline);
    }
  }

  Future<void> _restore() async {
    final r = _sel, api = ref.read(kantorApiProvider);
    if (r == null || api == null) return;
    setState(() => _busy = true);
    try {
      await api.post('$_base/wiki', {
        'title': r['title'],
        'body': r['body'],
        'msg': 'Pulihkan revisi #${r['id']}',
        'prevSlug': widget.page['slug'],
      });
      if (!mounted) return;
      showToastBadge(
        context,
        message: 'Versi dipulihkan.',
        icon: Icons.check_circle_outline,
      );
      Navigator.of(context).pop(true);
    } on KantorException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToastBadge(context, message: e.message, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(
          'Riwayat: ${widget.page['title']}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : _revs == null
          ? const KantorLoading()
          : _revs!.isEmpty
          ? const Center(child: Text('Belum ada riwayat.'))
          : ListView(
              padding: const EdgeInsets.all(GhinaSpace.page),
              children: [
                Text(
                  'Pilih satu revisi untuk melihat perbedaannya dengan versi sekarang.',
                  style: GhinaType.bodyS.copyWith(color: g.textMuted),
                ),
                const SizedBox(height: GhinaSpace.md),
                for (final r in _revs!.whereType<Map>())
                  ChunkyTile(
                    title: '#${r['id']} · ${r['author'] ?? ''}',
                    subtitle: [
                      agoId(r['at']),
                      if ('${r['msg'] ?? ''}'.isNotEmpty) '${r['msg']}',
                      if (r['size'] != null) '${r['size']} B',
                    ].join(' · '),
                    tinted: _sel?['id'].toString() == '${r['id']}'
                        ? GhinaColors.blue
                        : null,
                    dense: true,
                    onTap: () => _pick(r['id'] as Object),
                  ),
                if (_sel != null) ...[
                  const SizedBox(height: GhinaSpace.lg),
                  SectionHeader(
                    title: 'Versi sekarang menjadi revisi #${_sel!['id']}',
                  ),
                  _Diff(
                    a: '${widget.page['body'] ?? ''}',
                    b: '${_sel!['body'] ?? ''}',
                  ),
                  const SizedBox(height: GhinaSpace.lg),
                  ChunkyButton(
                    label: 'Pulihkan versi ini',
                    loading: _busy,
                    onPressed: _busy ? null : _restore,
                  ),
                ],
              ],
            ),
    );
  }
}

class _Diff extends StatelessWidget {
  const _Diff({required this.a, required this.b});
  final String a;
  final String b;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final ops = lineOps(a, b);
    if (!ops.any((o) => o.k != ' ')) {
      return Text(
        'Tidak ada perbedaan dengan versi sekarang.',
        style: GhinaType.body.copyWith(color: g.textSecondary),
      );
    }
    final keep = List<bool>.filled(ops.length, false);
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].k == ' ') continue;
      for (var d = -2; d <= 2; d++) {
        if (i + d >= 0 && i + d < ops.length) keep[i + d] = true;
      }
    }
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: g.textPrimary,
      height: 1.35,
    );
    final rows = <Widget>[];
    var skip = 0;
    void flush() {
      if (skip > 0) {
        rows.add(
          Text('… $skip baris sama', style: mono.copyWith(color: g.textMuted)),
        );
        skip = 0;
      }
    }

    for (var i = 0; i < ops.length; i++) {
      if (!keep[i]) {
        skip++;
        continue;
      }
      flush();
      final o = ops[i];
      final bg = o.k == '+'
          ? GhinaColors.green.base.withValues(alpha: 0.18)
          : o.k == '-'
          ? GhinaColors.red.base.withValues(alpha: 0.18)
          : null;
      rows.add(
        Container(
          width: double.infinity,
          color: bg,
          child: Text('${o.k} ${o.t}', style: mono),
        ),
      );
    }
    flush();
    return Container(
      padding: const EdgeInsets.all(GhinaSpace.sm),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width - 72,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ),
    );
  }
}
