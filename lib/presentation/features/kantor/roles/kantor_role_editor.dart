import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../codex/kantor_codex.dart';
import '../widgets/kantor_sprite.dart';
import 'kantor_look.dart';
import 'kantor_role.dart';
import 'kantor_shift_sheet.dart';
import 'kantor_ui.dart';

const _skillSuggestions = [
  'frontend',
  'backend',
  'review',
  'testing',
  'dokumentasi',
  'debugging',
  'refactor',
  'database',
  'devops',
  'delegasi',
];

/// Opens the editor for a new role; once saved, offers to start its first
/// shift. Returns whether a role was created.
Future<bool> kantorAddRole(BuildContext context, String officeId) async {
  final made = await Navigator.of(context).push<Object>(
    MaterialPageRoute<Object>(
      builder: (_) => KantorRoleEditorScreen(officeId: officeId),
    ),
  );
  if (made == null) return false;
  if (made is KantorRole && context.mounted) {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${made.name} sudah dibuat'),
        content: const Text('Mulai shift sekarang?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Nanti'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Mulai shift'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await showKantorShiftSheet(
        context,
        officeId: officeId,
        role: made,
        liveSessions: 0,
      );
    }
  }
  return true;
}

/// Create ([role] null) or edit a role. Pops `true` when an edit is saved and
/// the new [KantorRole] when one is created.
class KantorRoleEditorScreen extends ConsumerStatefulWidget {
  const KantorRoleEditorScreen({super.key, required this.officeId, this.role});

  final String officeId;
  final KantorRole? role;

  @override
  ConsumerState<KantorRoleEditorScreen> createState() => _RoleEditorState();
}

class _RoleEditorState extends ConsumerState<KantorRoleEditorScreen> {
  late final _name = TextEditingController(text: widget.role?.name);
  late final _title = TextEditingController(text: widget.role?.title);
  late final _persona = TextEditingController(text: widget.role?.persona);
  final _skillInput = TextEditingController();
  late final List<String> _skills = [...?widget.role?.skills];
  late final KantorLook _look = widget.role == null
      ? kantorRandomLook()
      : KantorLook.fromJson(widget.role!.look);
  late String _model = widget.role?.model ?? 'sonnet';
  late String _engine = widget.role?.engine ?? 'claude';
  late String _effort = widget.role?.effort ?? '';
  late String? _room = widget.role?.room;
  late String _boss = widget.role?.reportsTo ?? '';
  bool _manager = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _persona.dispose();
    _skillInput.dispose();
    super.dispose();
  }

  void _addSkill(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    if (s.isEmpty || _skills.contains(s)) return;
    setState(() => _skills.add(s));
  }

  Future<void> _save(KantorOffice office) async {
    final name = _name.text.trim();
    final title = _title.text.trim();
    if (name.isEmpty || title.isEmpty) {
      kantorToast(context, 'Nama dan jabatan wajib diisi', warn: true);
      return;
    }
    if (_skillInput.text.trim().isNotEmpty) {
      _addSkill(_skillInput.text);
      _skillInput.clear();
    }
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    _look.normalize();
    final editing = widget.role;
    final body = <String, dynamic>{
      'name': name,
      'title': title,
      'persona': _persona.text.trim(),
      'skills': _skills,
      'engine': _engine,
      'model': _model,
      'effort': _engine == 'codex' ? _effort : '',
      'room':
          _room ??
          office.rooms
              .firstWhere((r) => r.hasDesk, orElse: () => office.rooms.first)
              .id,
      ..._look.toJson(),
      if (editing?.isManager != true) 'reportsTo': _boss.isEmpty ? null : _boss,
    };
    final base = '/api/offices/${Uri.encodeComponent(widget.officeId)}/roles';
    setState(() => _busy = true);
    KantorRole? made;
    final ok = await kantorGuard(context, () async {
      if (editing != null) {
        await api.patch('$base/${Uri.encodeComponent(editing.id)}', body);
      } else {
        final r = await api.post(base, {...body, 'isMgr': _manager});
        if (r is Map && r['id'] is String) {
          made = KantorRole.fromJson(r.cast<String, dynamic>());
        }
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    kantorToast(context, editing != null ? 'Role disimpan' : 'Role dibuat');
    Navigator.of(context).pop(made ?? true);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final editing = widget.role;
    final officeAsync = ref.watch(kantorOfficeProvider(widget.officeId));
    final roles =
        ref.watch(kantorRolesProvider(widget.officeId)).value ??
        const <KantorRole>[];
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(editing != null ? 'Ubah ${editing.name}' : 'Tambah role'),
      ),
      body: officeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(kantorErrorText(e))),
        data: (office) {
          final rooms = [
            for (final r in office.rooms)
              if (r.hasDesk) r,
          ];
          _room ??=
              rooms.where((r) => r.kind == 'kode').firstOrNull?.id ??
              rooms.firstOrNull?.id;
          final bosses = [
            for (final r in roles)
              if (!r.archived && !r.isManager && r.id != editing?.id) r,
          ];
          return ListView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            children: [
              Center(
                child: Column(
                  children: [
                    KantorSprite(look: _look.toJson(), size: 120),
                    const SizedBox(height: GhinaSpace.sm),
                    Text(
                      _name.text.trim().isEmpty
                          ? 'Role baru'
                          : _name.text.trim(),
                      style: GhinaType.h3.copyWith(color: g.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GhinaSpace.lg),
              ChunkyTextField(
                controller: _name,
                label: 'Nama',
                hint: 'mis. Gilang',
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: GhinaSpace.md),
              ChunkyTextField(
                controller: _title,
                label: 'Jabatan',
                hint: 'mis. Desainer UI',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: GhinaSpace.md),
              ChunkyTextField(
                controller: _persona,
                label: 'Kepribadian',
                hint:
                    'Cara dia bicara, apa yang dia pedulikan, apa yang tidak pernah dia lakukan',
                helperText:
                    'Menjadi system prompt role: dibaca Claude setiap shift dimulai.',
                minLines: 3,
                maxLines: 8,
              ),
              const SizedBox(height: GhinaSpace.lg),
              const KantorFieldLabel('Skills'),
              Wrap(
                spacing: GhinaSpace.sm,
                runSpacing: GhinaSpace.sm,
                children: [
                  for (final s in _skills)
                    InputChip(
                      label: Text(s),
                      onDeleted: () => setState(() => _skills.remove(s)),
                    ),
                ],
              ),
              const SizedBox(height: GhinaSpace.sm),
              ChunkyTextField(
                controller: _skillInput,
                hint: 'Ketik lalu enter',
                textCapitalization: TextCapitalization.none,
                onSubmitted: (v) {
                  _addSkill(v);
                  _skillInput.clear();
                },
              ),
              const SizedBox(height: GhinaSpace.sm),
              Wrap(
                spacing: GhinaSpace.sm,
                children: [
                  for (final s in _skillSuggestions)
                    if (!_skills.contains(s))
                      ActionChip(
                        label: Text('+ $s'),
                        onPressed: () => _addSkill(s),
                      ),
                ],
              ),
              const SizedBox(height: GhinaSpace.lg),
              const KantorFieldLabel('Mesin'),
              KantorChips(
                options: const {
                  'claude': 'Claude Code',
                  'codex': 'OpenAI Codex',
                },
                value: _engine,
                onChanged: (v) => setState(() {
                  if (v == _engine) return;
                  _engine = v;
                  _model = v == 'codex' ? '' : 'sonnet';
                  _effort = '';
                }),
              ),
              const SizedBox(height: GhinaSpace.md),
              if (_engine == 'codex')
                KantorCodexFields(
                  key: ValueKey('codex/${widget.role?.id}'),
                  model: _model,
                  effort: _effort,
                  onChanged: (m, e) => setState(() {
                    _model = m;
                    _effort = e;
                  }),
                )
              else ...[
                const KantorFieldLabel('Model'),
                KantorChips(
                  options: {
                    for (final m in kantorModelOptions)
                      m.$1: kantorModelName(m.$1),
                  },
                  value: _model,
                  onChanged: (v) => setState(() => _model = v),
                ),
              ],
              const SizedBox(height: GhinaSpace.md),
              KantorPickField<String>(
                label: 'Ruangan',
                value: _room,
                options: [
                  for (final r in rooms) KantorChoice(r.id, r.name, r.path),
                ],
                onChanged: (v) => setState(() => _room = v),
              ),
              if (editing?.isManager != true) ...[
                const SizedBox(height: GhinaSpace.md),
                KantorPickField<String>(
                  label: 'Atasan',
                  value: _boss,
                  options: [
                    const KantorChoice('', 'Langsung di bawah manager'),
                    for (final r in bosses) KantorChoice(r.id, r.name, r.title),
                  ],
                  onChanged: (v) => setState(() => _boss = v),
                ),
              ],
              const SizedBox(height: GhinaSpace.xl),
              Text(
                'Tampilan karakter',
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Template'),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kantorLookTemplates.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: GhinaSpace.sm),
                  itemBuilder: (_, i) {
                    final t = kantorLookTemplates[i];
                    return GestureDetector(
                      onTap: () => setState(() => _look.apply(t.look())),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            KantorSprite(look: t.look().toJson(), size: 64),
                            const SizedBox(height: 4),
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption.copyWith(
                                color: g.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: ChunkyButton(
                  label: 'Acak',
                  icon: Icons.casino_rounded,
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.small,
                  onPressed: () =>
                      setState(() => _look.apply(kantorRandomLook())),
                ),
              ),
              const SizedBox(height: GhinaSpace.lg),
              const KantorFieldLabel('Warna seragam'),
              KantorSwatchRow(
                colors: kantorSwatches,
                selected: _look.color,
                onChanged: (c) => setState(() => _look.color = c),
              ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Warna kulit'),
              KantorSwatchRow(
                colors: kantorSkins,
                selected: _look.skin,
                onChanged: (c) => setState(() => _look.skin = c),
              ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Warna rambut'),
              KantorSwatchRow(
                colors: kantorHairColors,
                selected: _look.hair,
                onChanged: (c) => setState(() => _look.hair = c),
              ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Gaya rambut'),
              KantorChips(
                options: kantorHairStyles,
                value: _look.hairStyle,
                onChanged: (v) => setState(() {
                  _look.hairStyle = v;
                  _look.normalize();
                }),
              ),
              if (_look.hairStyle == 'hijab') ...[
                const SizedBox(height: GhinaSpace.md),
                const KantorFieldLabel('Warna hijab'),
                KantorSwatchRow(
                  colors: kantorHijabs,
                  selected: _look.hijab,
                  onChanged: (c) => setState(() => _look.hijab = c),
                ),
              ],
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Pakaian'),
              KantorChips(
                options: kantorOutfits,
                value: _look.outfit,
                onChanged: (v) => setState(() => _look.outfit = v),
              ),
              const SizedBox(height: GhinaSpace.md),
              const KantorFieldLabel('Aksesori'),
              KantorChips(
                options: {
                  for (final e in kantorAccessories.entries)
                    if (!(e.key == 'topi' && _look.hairStyle == 'hijab'))
                      e.key: e.value,
                },
                value: _look.acc,
                onChanged: (v) => setState(() => _look.acc = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Berdasi'),
                value: _look.tie,
                onChanged: (v) => setState(() => _look.tie = v),
              ),
              if (editing == null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Manager'),
                  subtitle: const Text(
                    'Memecah permintaan jadi kartu dan boleh memulai shift role lain. Ditetapkan saat dibuat.',
                  ),
                  value: _manager,
                  onChanged: (v) => setState(() => _manager = v),
                ),
              const SizedBox(height: GhinaSpace.xl),
              ChunkyButton(
                label: editing != null ? 'Simpan' : 'Buat role',
                loading: _busy,
                onPressed: _busy ? null : () => _save(office),
              ),
              const SizedBox(height: GhinaSpace.xxl),
            ],
          );
        },
      ),
    );
  }
}
