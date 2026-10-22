import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../plan/plan_thumb.dart';
import '../widgets/kantor_states.dart';

/// `GET /api/templates`: the "suasana kantor" gallery with SVG thumbnails.
final kantorTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) return const [];
      final r = await api.get('/api/templates') as Map;
      return [
        for (final t in r['templates'] as List? ?? const [])
          Map<String, dynamic>.from(t as Map),
      ];
    });

/// `GET /api/offices/<id>/template`: the template applied now and whether a
/// backup of the old layout can be restored.
final kantorTemplateStateProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) return const {};
      return Map<String, dynamic>.from(
        await api.get('/api/offices/${Uri.encodeComponent(id)}/template')
            as Map,
      );
    });

/// Cards for every template; [none] adds a "keep the default plan" card.
class KantorTemplateGallery extends StatelessWidget {
  const KantorTemplateGallery({
    super.key,
    required this.templates,
    required this.selected,
    required this.onSelect,
    this.none,
  });

  final List<Map<String, dynamic>> templates;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final String? none;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget card({
      required String id,
      required String name,
      String? mood,
      required String desc,
      String? thumb,
      required Color accent,
    }) {
      final on = (selected ?? '') == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
        child: ChunkyCard(
          key: ValueKey('tpl-$id'),
          padding: const EdgeInsets.all(GhinaSpace.sm),
          tinted: on ? GhinaColors.green : null,
          onTap: () => onSelect(id.isEmpty ? null : id),
          semanticLabel: name,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumb != null)
                SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: KantorPlanThumb.svg(thumb),
                  ),
                ),
              if (thumb != null) const SizedBox(width: GhinaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            style: GhinaType.h3.copyWith(color: g.textPrimary),
                          ),
                        ),
                        if (on)
                          const Icon(Icons.check_circle_rounded, size: 20),
                      ],
                    ),
                    if (mood != null && mood.isNotEmpty)
                      Text(
                        mood,
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final t in templates)
          card(
            id: '${t['id']}',
            name: '${t['name']}',
            mood: t['mood'] as String?,
            desc: '${t['desc'] ?? ''}',
            thumb: t['thumb'] as String?,
            accent: _accent(t['accent']),
          ),
        if (none != null)
          card(
            id: '',
            name: none!,
            desc:
                'Denah disusun otomatis dari isi folder, tanpa perabot '
                'tambahan.',
            accent: g.textMuted,
          ),
      ],
    );
  }
}

Color _accent(Object? hex) {
  final s = '$hex';
  final v = s.startsWith('#') && s.length >= 7
      ? int.tryParse(s.substring(1, 7), radix: 16)
      : null;
  return v == null ? const Color(0xFF7FA88A) : Color(0xFF000000 | v);
}

/// Apply a template to an existing office: gallery, preview of the layout,
/// then Terapkan / Acak lagi / Pulihkan susunan lama.
class KantorTemplatePage extends ConsumerStatefulWidget {
  const KantorTemplatePage({super.key, required this.officeId, this.random});

  final String officeId;

  /// Seeds for "Acak lagi"; tests pass a fixed one.
  final Random? random;

  @override
  ConsumerState<KantorTemplatePage> createState() => _KantorTemplatePageState();
}

class _KantorTemplatePageState extends ConsumerState<KantorTemplatePage> {
  String? _tpl;
  int _seed = 1;
  Map<String, dynamic>? _preview;
  String? _error;
  bool _busy = false;
  int _gen = 0;

  String get _base => '/api/offices/${Uri.encodeComponent(widget.officeId)}';

  Future<void> _load() async {
    final tpl = _tpl;
    final api = ref.read(kantorApiProvider);
    if (tpl == null || api == null) return;
    final gen = ++_gen;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = Map<String, dynamic>.from(
        await api.post('$_base/template/preview', {
              'template': tpl,
              'seed': _seed,
            })
            as Map,
      );
      if (mounted && gen == _gen) setState(() => _preview = r);
    } on KantorException catch (e) {
      if (mounted && gen == _gen) {
        setState(() {
          _preview = null;
          _error = e.message;
        });
      }
    } finally {
      if (mounted && gen == _gen) setState(() => _busy = false);
    }
  }

  void _pick(String? id) {
    if (id == null) return;
    _tpl = id;
    _seed = 1;
    _load();
  }

  void _reroll() {
    _seed = (widget.random ?? Random()).nextInt(1000000);
    _load();
  }

  Future<void> _do(String path, Object? body, String done) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.post('$_base/$path', body);
      ref.invalidate(kantorOfficeProvider(widget.officeId));
      ref.invalidate(kantorTemplateStateProvider(widget.officeId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      Navigator.of(context).pop(true);
    } on KantorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Pulihkan susunan lama?',
      message:
          'Denah, perabot, dan ruangan tambahan kembali seperti sebelum '
          'template pertama diterapkan.',
      confirmLabel: 'Pulihkan',
    );
    if (ok) await _do('template/restore', null, 'Susunan dipulihkan');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final list = ref.watch(kantorTemplatesProvider);
    final state = ref.watch(kantorTemplateStateProvider(widget.officeId));
    final current = state.value?['current'] as Map?;
    final canRestore = state.value?['backup'] != null;
    final pv = _preview;
    final problems = [
      for (final p in pv?['problems'] as List? ?? const []) '$p',
    ];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Suasana kantor')),
      body: switch (list) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(GhinaSpace.page),
          children: [
            Text(
              current == null
                  ? 'Template menyusun ulang denah dan mengisi perabot '
                        'bertema. Susunan lama disimpan dan bisa dipulihkan.'
                  : 'Sekarang: ${_nameOf(value, current['id'])}. '
                        'Susunan sebelum template bisa dipulihkan.',
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: GhinaSpace.md),
            KantorTemplateGallery(
              templates: value,
              selected: _tpl,
              onSelect: _pick,
            ),
            if (_busy && pv == null) const KantorLoading(),
            if (pv != null) ...[
              SectionHeader(
                title: 'Pratinjau',
                subtitle:
                    '${_nameOf(value, pv['template'])} · seed ${pv['seed']}',
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: KantorPlanThumb.plan(
                  Map<String, dynamic>.from(pv['plan'] as Map),
                ),
              ),
              const SizedBox(height: GhinaSpace.sm),
              _summary(pv, g),
            ],
            if (problems.isNotEmpty)
              ChunkyCard(
                tinted: GhinaColors.orange,
                padding: const EdgeInsets.all(GhinaSpace.md),
                child: Text(
                  'Belum bisa diterapkan:\n${problems.take(4).join('\n')}',
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: GhinaSpace.sm),
                child: Text(
                  _error!,
                  style: GhinaType.body.copyWith(color: GhinaColors.red.base),
                ),
              ),
            const SizedBox(height: GhinaSpace.lg),
            if (pv != null) ...[
              ChunkyButton(
                label: 'Terapkan',
                loading: _busy,
                onPressed: _busy || problems.isNotEmpty
                    ? null
                    : () => _do('template/apply', {
                        'template': _tpl,
                        'seed': _seed,
                      }, 'Template diterapkan'),
              ),
              const SizedBox(height: GhinaSpace.sm),
              ChunkyButton(
                label: 'Acak lagi',
                variant: ChunkyButtonVariant.secondary,
                onPressed: _busy ? null : _reroll,
              ),
              const SizedBox(height: GhinaSpace.sm),
            ],
            if (canRestore)
              ChunkyButton(
                label: 'Pulihkan susunan lama',
                variant: ChunkyButtonVariant.outline,
                onPressed: _busy ? null : _restore,
              ),
          ],
        ),
        AsyncError(:final error) => KantorErrorView(
          error: error,
          onRetry: () => ref.invalidate(kantorTemplatesProvider),
        ),
        _ => const KantorLoading(),
      },
    );
  }

  Widget _summary(Map<String, dynamic> pv, GhinaTokens g) {
    final added = [
      for (final r in pv['newRooms'] as List? ?? const [])
        '${(r as Map)['name']}',
    ];
    final dropped = [for (final d in pv['dropped'] as List? ?? const []) '$d'];
    return Text(
      [
        '${(pv['plan'] as Map)['rooms'].length} ruangan',
        if (added.isNotEmpty) 'Ruangan baru: ${added.join(', ')}',
        if (dropped.isNotEmpty) 'Dilepas: ${dropped.join(', ')}',
      ].join('\n'),
      style: GhinaType.caption.copyWith(color: g.textSecondary),
    );
  }
}

String _nameOf(List<Map<String, dynamic>> list, Object? id) {
  for (final t in list) {
    if (t['id'] == id) return '${t['name']}';
  }
  return '$id';
}
