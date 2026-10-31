import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';

Map<String, String> _choices(Object? raw, String idKey, String labelKey) => {
  for (final v in raw is List ? raw : const [])
    if (v is String)
      v: v
    else if (v is Map && v[idKey] is String)
      v[idKey] as String: '${v[labelKey] ?? v[idKey]}',
};

class KantorEngineSpec {
  KantorEngineSpec(this.json);
  final Map<String, dynamic> json;
  String get id => '${json['id']}';
  String get name => '${json['name'] ?? id}';
  bool get available => json['available'] == true;
  bool get supportsEffort => json['supportsEffort'] == true;
  bool get allowDefaultModel => json['allowDefaultModel'] != false;
  String get defaultModel => '${json['defaultModel'] ?? ''}';
  String get defaultEffort => '${json['defaultEffort'] ?? ''}';
  String get defaultPermissionMode => '${json['defaultPermissionMode'] ?? ''}';
  List<Map> get models => [
    for (final m in json['models'] as List? ?? [])
      if (m is Map) m,
  ];
  Map<String, String> get permissionModes =>
      _choices(json['permissionModes'], 'id', 'name');
  String warning(String mode) {
    for (final m in json['permissionModes'] as List? ?? []) {
      if (m is Map && m['id'] == mode) return '${m['warning'] ?? ''}';
    }
    return '';
  }

  Map<String, String> effortsFor(String model) {
    for (final m in models) {
      if (m['slug'] == (model.isEmpty ? defaultModel : model)) {
        final choices = _choices(m['efforts'], 'effort', 'effort');
        if (choices.isNotEmpty) return choices;
      }
    }
    return _choices(json['efforts'], 'effort', 'effort');
  }
}

class KantorEngineCatalog {
  KantorEngineCatalog.fromJson(Map json)
    : engines = [
        for (final e in json['engines'] as List? ?? [])
          if (e is Map && e['id'] is String && (e['id'] as String).isNotEmpty)
            KantorEngineSpec(e.cast<String, dynamic>()),
      ];
  final List<KantorEngineSpec> engines;
  KantorEngineSpec? engine(String id) {
    for (final e in engines) {
      if (e.id == id) return e;
    }
    return null;
  }
}

// Re-created when the selected Kantor profile changes. Refreshing the form also
// fetches the catalog again; adding a supported engine needs no client release.
final kantorEngineCatalogProvider =
    FutureProvider.autoDispose<KantorEngineCatalog>((ref) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null)
        throw StateError('Hubungkan ke server Kantor terlebih dahulu.');
      final j = await api.get('/api/engines');
      final catalog = KantorEngineCatalog.fromJson(j as Map);
      if (catalog.engines.isEmpty)
        throw const FormatException('Katalog mesin kosong');
      return catalog;
    });

/// Generic launch/editor fields described entirely by the office server.
class KantorCatalogFields extends ConsumerStatefulWidget {
  const KantorCatalogFields({
    super.key,
    required this.engine,
    required this.model,
    required this.effort,
    required this.onChanged,
    this.inherit = false,
  });
  final String engine, model, effort;
  final bool inherit;
  final void Function(
    String engine,
    String model,
    String effort,
    String permission,
    KantorEngineSpec spec,
  )
  onChanged;
  @override
  ConsumerState<KantorCatalogFields> createState() => _CatalogFieldsState();
}

class _CatalogFieldsState extends ConsumerState<KantorCatalogFields> {
  late String _engine = widget.inherit ? '' : widget.engine;
  late String _model = widget.model;
  late String _effort = widget.effort;
  String? _permission;

  void _emit(KantorEngineSpec spec) => widget.onChanged(
    _engine,
    _model,
    spec.supportsEffort ? _effort : '',
    _permission ?? spec.defaultPermissionMode,
    spec,
  );

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(kantorEngineCatalogProvider);
    return result.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Katalog mesin belum bisa dimuat. Periksa koneksi dan versi server Kantor.',
          ),
          TextButton(
            onPressed: () => ref.invalidate(kantorEngineCatalogProvider),
            child: const Text('Coba lagi'),
          ),
        ],
      ),
      data: (catalog) {
        final effective = _engine.isEmpty ? widget.engine : _engine;
        final spec = catalog.engine(effective);
        final permission = _permission ?? spec?.defaultPermissionMode ?? '';
        final efforts = spec?.effortsFor(_model) ?? <String, String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KantorFieldLabel('Mesin'),
            KantorChips(
              options: {
                if (widget.inherit)
                  '': 'Bawaan (${catalog.engine(widget.engine)?.name ?? widget.engine})',
                if (spec == null && effective.isNotEmpty) effective: effective,
                for (final e in catalog.engines)
                  if (e.available || e.id == effective) e.id: e.name,
              },
              value: _engine,
              onChanged: (v) {
                final next = catalog.engine(v.isEmpty ? widget.engine : v);
                if (next == null) return;
                setState(() {
                  _engine = v;
                  final original = next.id == widget.engine;
                  _model = original
                      ? widget.model
                      : (next.allowDefaultModel ? '' : next.defaultModel);
                  _effort = original ? widget.effort : '';
                  _permission = next.defaultPermissionMode;
                });
                _emit(next);
              },
            ),
            if (spec == null || !spec.available)
              const Text('Mesin ini belum tersedia di server Kantor.'),
            if (spec != null) ...[
              GhinaSpace.gapMd,
              KantorPickField<String>(
                label: 'Model ${spec.name}',
                value: _model,
                emptyLabel: 'Bawaan ${spec.name}',
                options: [
                  if (spec.allowDefaultModel)
                    KantorChoice('', 'Bawaan ${spec.name}'),
                  if (_model.isNotEmpty &&
                      !spec.models.any((m) => m['slug'] == _model))
                    KantorChoice(_model, _model),
                  for (final m in spec.models)
                    KantorChoice(
                      '${m['slug']}',
                      '${m['name'] ?? m['slug']}',
                      m['desc'] as String?,
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _model = v;
                    if (!spec.effortsFor(v).containsKey(_effort)) _effort = '';
                  });
                  _emit(spec);
                },
              ),
              if (spec.supportsEffort && efforts.isNotEmpty) ...[
                GhinaSpace.gapMd,
                const KantorFieldLabel('Effort'),
                KantorChips(
                  options: {'': 'Bawaan', ...efforts},
                  value: _effort,
                  onChanged: (v) {
                    setState(() => _effort = v);
                    _emit(spec);
                  },
                ),
              ],
              if (widget.inherit && spec.permissionModes.isNotEmpty) ...[
                GhinaSpace.gapMd,
                const KantorFieldLabel('Mode izin'),
                KantorChips(
                  options: spec.permissionModes,
                  value: permission,
                  onChanged: (v) {
                    setState(() => _permission = v);
                    _emit(spec);
                  },
                ),
                if (spec.warning(permission).isNotEmpty)
                  Text(spec.warning(permission)),
              ],
              if (spec.json['error'] is String)
                Text(spec.json['error'] as String),
            ],
          ],
        );
      },
    );
  }
}
