import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';
import '../engines/kantor_engines.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_feed.dart';

/// Pemilihan mesin, model, dan izin Kantor.

/// True bila sesi atau role memakai Codex. Server lama tidak mengirim
/// `engine`, jadi hilang berarti Claude.
bool kantorIsCodex(Json? j) => j != null && j['engine'] == 'codex';

/// Sesi lebih dulu (mesin yang benar-benar jalan), lalu role-nya.
bool kantorEngineIsCodex(Json? session, Json? role) =>
    session != null && session['engine'] != null
    ? kantorIsCodex(session)
    : kantorIsCodex(role);

bool kantorIsGemini(Json? j) => j?['engine'] == 'antigravity';

bool kantorEngineIsGemini(Json? session, Json? role) =>
    session?['engine'] != null ? kantorIsGemini(session) : kantorIsGemini(role);

String kantorEngineName(String engine) => switch (engine) {
  'codex' => 'OpenAI Codex',
  'antigravity' => 'Gemini (Antigravity)',
  _ => engine.isEmpty || engine == 'claude' ? 'Claude Code' : engine,
};

const kantorCodexModes = <(String, String, String)>[
  ('default', 'Tanya dulu', 'Minta izin sebelum menjalankan perintah.'),
  ('auto', 'Auto (Approve for me)', 'Codex menyetujui sendiri yang aman.'),
  ('readOnly', 'Hanya baca', 'Tidak boleh mengubah file.'),
  (
    'bypassPermissions',
    'Akses penuh (tanpa sandbox)',
    'Menjalankan apa pun tanpa bertanya dan tanpa sandbox.',
  ),
];

String kantorCodexModeLabel(String mode) {
  for (final m in kantorCodexModes) {
    if (m.$1 == mode) return m.$2;
  }
  return mode;
}

const kantorCodexEfforts = ['low', 'medium', 'high', 'xhigh'];

/// Model + effort aktif untuk tampilan. Codex: dari sesi; Claude: seperti biasa.
String kantorSessionModelText(Json? role, Json sess) {
  if (kantorEngineIsGemini(sess, role)) {
    final model =
        sess['model'] ?? (kantorIsGemini(role) ? (role?['model']) : null);
    return '$model' == 'null' || '$model'.isEmpty ? 'Bawaan Gemini' : '$model';
  }
  if (!kantorEngineIsCodex(sess, role)) {
    return modelLabel(role?['model'] ?? sess['model']);
  }
  final m = '${sess['model'] ?? ''}'.isNotEmpty
      ? '${sess['model']}'
      : '${role?['model'] ?? ''}';
  final e = '${sess['effort'] ?? ''}';
  return [m.isEmpty ? 'Bawaan Codex' : m, if (e.isNotEmpty) e].join(' · ');
}

/// Chip kecil "Codex" (gaya sama dengan chip lain). Claude tidak diberi badge.
class KantorCodexBadge extends StatelessWidget {
  const KantorCodexBadge({super.key});

  @override
  Widget build(BuildContext context) => const ChunkyPill(
    label: 'Codex',
    color: GhinaColors.green,
    soft: true,
    uppercase: false,
  );
}

class KantorCodexModel {
  const KantorCodexModel({
    required this.slug,
    required this.name,
    required this.desc,
    required this.defaultEffort,
    required this.efforts,
  });

  factory KantorCodexModel.fromJson(Map<dynamic, dynamic> j) =>
      KantorCodexModel(
        slug: '${j['slug'] ?? ''}',
        name: '${j['name'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
        defaultEffort: '${j['defaultEffort'] ?? ''}',
        efforts: [
          for (final e in (j['efforts'] as List?) ?? const [])
            if (e is Map)
              ('${e['effort'] ?? ''}', '${e['desc'] ?? ''}')
            else if (e is String)
              (e, ''),
        ],
      );

  final String slug;
  final String name;
  final String desc;
  final String defaultEffort;
  final List<(String, String)> efforts;
}

/// `GET /api/codex/models`.
class KantorCodexCatalog {
  const KantorCodexCatalog({
    this.available = false,
    this.defaultModel = '',
    this.defaultEffort = '',
    this.models = const [],
  });

  factory KantorCodexCatalog.fromJson(Map<dynamic, dynamic> j) {
    final d = j['default'] is Map ? j['default'] as Map : const {};
    return KantorCodexCatalog(
      available: j['available'] == true,
      defaultModel: '${d['model'] ?? ''}',
      defaultEffort: '${d['effort'] ?? ''}',
      models: [
        for (final m in (j['models'] as List?) ?? const [])
          if (m is Map) KantorCodexModel.fromJson(m),
      ],
    );
  }

  final bool available;
  final String defaultModel;
  final String defaultEffort;
  final List<KantorCodexModel> models;

  KantorCodexModel? model(String slug) {
    for (final m in models) {
      if (m.slug == slug) return m;
    }
    return null;
  }

  /// Effort yang boleh dipilih untuk [slug] (kosong = model bawaan).
  List<String> effortsFor(String slug) {
    final m = model(slug.isEmpty ? defaultModel : slug);
    final list = [
      if (m != null)
        for (final e in m.efforts) e.$1,
    ];
    return list.isEmpty ? kantorCodexEfforts : list;
  }
}

final kantorCodexCatalogProvider =
    FutureProvider.autoDispose<KantorCodexCatalog>((ref) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) return const KantorCodexCatalog();
      try {
        return KantorCodexCatalog.fromJson(
          await KantorActions(api).codexModels(),
        );
      } catch (_) {
        return const KantorCodexCatalog();
      }
    });

/// Pilihan model + effort Codex. [model] kosong = bawaan Codex (bila
/// [allowDefault]). Daftar model kosong -> isian bebas.
class KantorCodexFields extends ConsumerStatefulWidget {
  const KantorCodexFields({
    super.key,
    required this.model,
    required this.effort,
    required this.onChanged,
    this.allowDefault = true,
  });

  final String model;
  final String effort;
  final bool allowDefault;
  final void Function(String model, String effort) onChanged;

  @override
  ConsumerState<KantorCodexFields> createState() => _CodexFieldsState();
}

class _CodexFieldsState extends ConsumerState<KantorCodexFields> {
  late String _model = widget.model;
  late String _effort = widget.effort;

  void _set(String model, String effort) {
    setState(() {
      _model = model;
      _effort = effort;
    });
    widget.onChanged(model, effort);
  }

  @override
  Widget build(BuildContext context) {
    final cat =
        ref.watch(kantorCodexCatalogProvider).value ??
        const KantorCodexCatalog();
    final efforts = cat.effortsFor(_model);
    final hint = cat.defaultModel.isEmpty
        ? 'mis. gpt-5-codex'
        : cat.defaultModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cat.models.isEmpty)
          ChunkyTextField(
            label: 'Model Codex',
            hint: widget.allowDefault ? 'Bawaan Codex ($hint)' : hint,
            initialValue: _model,
            onChanged: (v) => _set(v.trim(), _effort),
          )
        else
          KantorPickField<String>(
            label: 'Model Codex',
            emptyLabel: 'Bawaan Codex',
            value: _model,
            options: [
              if (widget.allowDefault)
                KantorChoice(
                  '',
                  'Bawaan Codex',
                  cat.defaultModel.isEmpty ? null : cat.defaultModel,
                ),
              if (_model.isNotEmpty && cat.model(_model) == null)
                KantorChoice(_model, _model),
              for (final m in cat.models)
                KantorChoice(
                  m.slug,
                  m.name.isEmpty ? m.slug : m.name,
                  m.desc.isEmpty ? null : m.desc,
                ),
            ],
            onChanged: (v) {
              final ok = cat.effortsFor(v).contains(_effort);
              _set(v, ok ? _effort : '');
            },
          ),
        const SizedBox(height: GhinaSpace.md),
        const KantorFieldLabel('Effort'),
        KantorChips(
          options: {
            if (widget.allowDefault) '': 'Bawaan',
            for (final e in efforts) e: e,
          },
          value: _effort,
          onChanged: (v) => _set(_model, v),
        ),
      ],
    );
  }
}

/// Pilihan mesin saat mulai shift. [engine] kosong = ikut mesin role.
class KantorEngineSel {
  const KantorEngineSel({
    this.engine = '',
    this.model = '',
    this.effort = '',
    this.perm = '',
    this.codex = false,
    this.gemini = false,
    this.catalog = false,
    this.supportsEffort = false,
  });

  final String engine;
  final String model;
  final String effort;
  final String perm;

  /// Mesin efektif adalah Codex.
  final bool codex;
  final bool gemini;
  final bool catalog, supportsEffort;
  bool get managed => catalog || codex || gemini;

  factory KantorEngineSel.initial(Json role) {
    final c = kantorIsCodex(role);
    final a = kantorIsGemini(role);
    return KantorEngineSel(
      model: c || a ? '${role['model'] ?? ''}' : '',
      effort: c ? '${role['effort'] ?? ''}' : '',
      perm: c || a ? 'default' : '',
      codex: c,
      gemini: a,
    );
  }

  /// Tambahan badan `POST .../start` untuk pilihan ini.
  Map<String, dynamic> body(Json role) => {
    if (engine.isNotEmpty) 'engine': engine,
    if (managed) ...{
      if (model.isNotEmpty) 'model': model,
      if ((catalog ? supportsEffort : codex) && effort.isNotEmpty)
        'effort': effort,
      if (!catalog || perm.isNotEmpty)
        'permissionMode': perm.isEmpty ? 'default' : perm,
    } else if (engine == 'claude' &&
        (kantorIsCodex(role) || kantorIsGemini(role)))
      'model': 'sonnet',
  };

  KantorEngineSel copy({
    String? engine,
    String? model,
    String? effort,
    String? perm,
    bool? codex,
    bool? gemini,
    bool? catalog,
    bool? supportsEffort,
  }) => KantorEngineSel(
    engine: engine ?? this.engine,
    model: model ?? this.model,
    effort: effort ?? this.effort,
    perm: perm ?? this.perm,
    codex: codex ?? this.codex,
    gemini: gemini ?? this.gemini,
    catalog: catalog ?? this.catalog,
    supportsEffort: supportsEffort ?? this.supportsEffort,
  );
}

/// Form shift mengikuti katalog server, termasuk mesin yang baru ditambahkan.
class KantorEngineFields extends StatelessWidget {
  const KantorEngineFields({
    super.key,
    required this.role,
    required this.onChanged,
  });
  final Json role;
  final ValueChanged<KantorEngineSel> onChanged;

  @override
  Widget build(BuildContext context) => KantorCatalogFields(
    engine: '${role['engine'] ?? 'claude'}',
    model: '${role['model'] ?? ''}',
    effort: '${role['effort'] ?? ''}',
    inherit: true,
    onChanged: (engine, model, effort, permission, spec) => onChanged(
      KantorEngineSel(
        engine: engine,
        model: model,
        effort: effort,
        perm: permission,
        codex: spec.id == 'codex',
        gemini: spec.id == 'antigravity',
        catalog: true,
        supportsEffort: spec.supportsEffort,
      ),
    ),
  );
}

/// Sheet ganti model + effort untuk sesi Codex yang sedang jalan (harus idle).
/// Galat server (mis. 409 sibuk) tampil sebagai toast.
Future<void> showKantorCodexSettingsSheet(
  BuildContext context, {
  required KantorActions actions,
  required Json sess,
  Json? role,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Model & effort Codex',
  builder: (_) => _SettingsForm(actions: actions, sess: sess, role: role),
);

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({
    required this.actions,
    required this.sess,
    required this.role,
  });

  final KantorActions actions;
  final Json sess;
  final Json? role;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final String _m0 = '${widget.sess['model'] ?? ''}';
  late final String _e0 = '${widget.sess['effort'] ?? ''}';
  late String _model = _m0;
  late String _effort = _e0;
  bool _busy = false;

  Future<void> _apply() async {
    setState(() => _busy = true);
    final ok = await kantorGuard(context, () async {
      await widget.actions.codexSettings(
        '${widget.sess['sid']}',
        model: _model != _m0 && _model.isNotEmpty ? _model : null,
        effort: _effort != _e0 && _effort.isNotEmpty ? _effort : null,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    kantorToast(context, 'Pengaturan Codex diterapkan');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final changed =
        (_model != _m0 && _model.isNotEmpty) ||
        (_effort != _e0 && _effort.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aktif: ${kantorSessionModelText(widget.role, widget.sess)}. Berlaku untuk sesi ini saja; agen harus sedang idle.',
          style: GhinaType.bodyS.copyWith(color: context.ghina.textSecondary),
        ),
        GhinaSpace.gapMd,
        KantorCodexFields(
          model: _model,
          effort: _effort,
          allowDefault: false,
          onChanged: (m, e) => setState(() {
            _model = m;
            _effort = e;
          }),
        ),
        GhinaSpace.gapLg,
        ChunkyButton(
          label: 'Terapkan',
          loading: _busy,
          onPressed: _busy || !changed ? null : _apply,
        ),
      ],
    );
  }
}

/// Katalog resmi instalasi Antigravity di PC yang menjalankan kantor.
final kantorGeminiCatalogProvider =
    FutureProvider.autoDispose<KantorCodexCatalog>((ref) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) return const KantorCodexCatalog();
      final j = await api.get('/api/antigravity/models');
      return KantorCodexCatalog.fromJson((j as Map).cast<String, dynamic>());
    });

class KantorGeminiFields extends ConsumerWidget {
  const KantorGeminiFields({
    super.key,
    required this.model,
    required this.onChanged,
  });
  final String model;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(kantorGeminiCatalogProvider);
    final cat = result.value;
    final models =
        cat?.models.where((m) => m.slug.startsWith('gemini')).toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KantorPickField<String>(
          label: 'Model Gemini',
          value: model,
          emptyLabel: 'Bawaan Antigravity',
          options: [
            const KantorChoice('', 'Bawaan Antigravity'),
            if (model.isNotEmpty && !models.any((m) => m.slug == model))
              KantorChoice(model, model),
            for (final m in models) KantorChoice(m.slug, m.name, m.desc),
          ],
          onChanged: onChanged,
        ),
        if (result.isLoading) const LinearProgressIndicator(),
        if (result.hasError || (cat != null && !cat.available))
          const Text(
            'Katalog Gemini belum tersedia. Periksa Antigravity di PC kantor.',
          ),
      ],
    );
  }
}
