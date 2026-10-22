import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';
import '../session/kantor_actions.dart';
import '../session/kantor_feed.dart';

/// Mesin kedua Kantor: OpenAI Codex. Semua yang khusus Codex ada di sini.

/// True bila sesi atau role memakai Codex. Server lama tidak mengirim
/// `engine`, jadi hilang berarti Claude.
bool kantorIsCodex(Json? j) => j != null && j['engine'] == 'codex';

/// Sesi lebih dulu (mesin yang benar-benar jalan), lalu role-nya.
bool kantorEngineIsCodex(Json? session, Json? role) =>
    session != null && session['engine'] != null
    ? kantorIsCodex(session)
    : kantorIsCodex(role);

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
    final hint = cat.defaultModel.isEmpty ? 'mis. gpt-5-codex' : cat.defaultModel;
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
  });

  final String engine;
  final String model;
  final String effort;
  final String perm;

  /// Mesin efektif adalah Codex.
  final bool codex;

  factory KantorEngineSel.initial(Json role) {
    final c = kantorIsCodex(role);
    return KantorEngineSel(
      model: c ? '${role['model'] ?? ''}' : '',
      effort: c ? '${role['effort'] ?? ''}' : '',
      perm: c ? 'default' : '',
      codex: c,
    );
  }

  /// Tambahan badan `POST .../start` untuk pilihan ini.
  Map<String, dynamic> body(Json role) => {
    if (engine.isNotEmpty) 'engine': engine,
    if (codex) ...{
      if (model.isNotEmpty) 'model': model,
      if (effort.isNotEmpty) 'effort': effort,
      'permissionMode': perm.isEmpty ? 'default' : perm,
    } else if (engine == 'claude' && kantorIsCodex(role))
      'model': 'sonnet',
  };

  KantorEngineSel copy({
    String? engine,
    String? model,
    String? effort,
    String? perm,
    bool? codex,
  }) => KantorEngineSel(
    engine: engine ?? this.engine,
    model: model ?? this.model,
    effort: effort ?? this.effort,
    perm: perm ?? this.perm,
    codex: codex ?? this.codex,
  );
}

/// Mesin + (untuk Codex) model, effort, dan mode izin. Mode izin Claude
/// tetap diurus sheet pemanggil saat [KantorEngineSel.codex] false.
class KantorEngineFields extends StatefulWidget {
  const KantorEngineFields({
    super.key,
    required this.role,
    required this.onChanged,
  });

  final Json role;
  final ValueChanged<KantorEngineSel> onChanged;

  @override
  State<KantorEngineFields> createState() => _EngineFieldsState();
}

class _EngineFieldsState extends State<KantorEngineFields> {
  late KantorEngineSel _sel = KantorEngineSel.initial(widget.role);

  void _set(KantorEngineSel s) {
    setState(() => _sel = s);
    widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    final roleCodex = kantorIsCodex(widget.role);
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MESIN',
          style: GhinaType.overline.copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapSm,
        KantorChips(
          options: {
            '': 'Bawaan (${roleCodex ? 'Codex' : 'Claude'})',
            'claude': 'Claude Code',
            'codex': 'OpenAI Codex',
          },
          value: _sel.engine,
          onChanged: (v) {
            final codex = v.isEmpty ? roleCodex : v == 'codex';
            final fresh = KantorEngineSel.initial(widget.role);
            _set(
              codex == roleCodex
                  ? fresh.copy(engine: v)
                  : KantorEngineSel(
                      engine: v,
                      codex: codex,
                      perm: codex ? 'default' : '',
                    ),
            );
          },
        ),
        if (_sel.codex) ...[
          GhinaSpace.gapMd,
          KantorCodexFields(
            key: ValueKey('${_sel.engine}/${_sel.model}'),
            model: _sel.model,
            effort: _sel.effort,
            onChanged: (m, e) => _set(_sel.copy(model: m, effort: e)),
          ),
          GhinaSpace.gapMd,
          Text(
            'MODE IZIN',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          GhinaSpace.gapSm,
          KantorChips(
            options: {for (final m in kantorCodexModes) m.$1: m.$2},
            value: _sel.perm,
            onChanged: (v) => _set(_sel.copy(perm: v)),
          ),
          if (_sel.perm == 'bypassPermissions')
            Padding(
              padding: const EdgeInsets.only(top: GhinaSpace.sm),
              child: Text(
                'Codex berjalan tanpa sandbox dan tanpa bertanya.',
                style: GhinaType.bodyS.copyWith(color: GhinaColors.orange.base),
              ),
            ),
        ],
      ],
    );
  }
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
    final changed = (_model != _m0 && _model.isNotEmpty) ||
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
