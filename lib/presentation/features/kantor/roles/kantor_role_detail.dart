import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import '../codex/kantor_codex.dart';
import '../dm/kantor_dm_screen.dart';
import 'kantor_playbooks.dart';
import 'kantor_role.dart';
import 'kantor_role_editor.dart';
import 'kantor_roles_tab.dart' show kantorRoleStatus;
import 'kantor_shift_sheet.dart';
import 'kantor_ui.dart';

/// One role: persona, live sessions, playbooks and its notebook.
class KantorRoleDetailScreen extends ConsumerStatefulWidget {
  const KantorRoleDetailScreen({
    super.key,
    required this.officeId,
    required this.roleId,
  });

  final String officeId;
  final String roleId;

  @override
  ConsumerState<KantorRoleDetailScreen> createState() => _RoleDetailState();
}

class _RoleDetailState extends ConsumerState<KantorRoleDetailScreen> {
  final _notes = TextEditingController();
  bool _notesLoaded = false;
  String _notesHint = 'Tersimpan otomatis.';
  Timer? _debounce;

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _saveNotes(_notes.text); // flush the pending edit before leaving
    }
    _notes.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(kantorRolesProvider(widget.officeId));
    ref.invalidate(kantorOfficeProvider(widget.officeId));
  }

  void _notesChanged(String text) {
    _debounce?.cancel();
    setState(() => _notesHint = 'Menyimpan…');
    _debounce = Timer(
      const Duration(milliseconds: 700),
      () => _saveNotes(text),
    );
  }

  Future<void> _saveNotes(String text) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      await api.patch(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/roles/${Uri.encodeComponent(widget.roleId)}',
        {'notes': text},
      );
      if (mounted) {
        setState(() => _notesHint = 'Tersimpan');
        ref.invalidate(kantorRolesProvider(widget.officeId));
      }
    } catch (e) {
      if (mounted)
        setState(() => _notesHint = 'Gagal menyimpan: ${kantorErrorText(e)}');
    }
  }

  Future<void> _archive(
    KantorRole r,
    KantorOffice? office,
    bool archive,
  ) async {
    if (archive) {
      if ((office?.liveSessionsOf(r.id).length ?? 0) > 0) {
        kantorToast(
          context,
          '${r.name} masih punya sesi aktif. Selesaikan dulu.',
          warn: true,
        );
        return;
      }
      final ok = await showChunkyConfirm(
        context,
        title: 'Arsipkan role?',
        message:
            '${r.name} tidak lagi muncul di denah, tapi riwayat dan catatannya tetap ada. Bisa dipulihkan kapan saja.',
        confirmLabel: 'Arsipkan',
      );
      if (!ok || !mounted) return;
    }
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final done = await kantorGuard(context, () async {
      await api.patch(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/roles/${Uri.encodeComponent(r.id)}',
        {'archived': archive},
      );
    });
    if (!done || !mounted) return;
    _refresh();
    kantorToast(context, archive ? 'Role diarsipkan' : 'Role dipulihkan');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final id = widget.officeId;
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null) return;
      if (m['t'] == 'session' || m['t'] == 'session-gone')
        ref.invalidate(kantorOfficeProvider(id));
      if (m['t'] == 'changed' && m['what'] == 'wiki')
        ref.invalidate(kantorPlaybooksProvider(id));
    });
    final rolesAsync = ref.watch(kantorRolesProvider(id));
    final office = ref.watch(kantorOfficeProvider(id)).value;
    KantorRole? role;
    for (final r in rolesAsync.value ?? const <KantorRole>[]) {
      if (r.id == widget.roleId) role = r;
    }
    if (role != null && !_notesLoaded) {
      _notes.text = role.notes;
      _notesLoaded = true;
    }

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(role?.name ?? 'Role'),
        actions: [
          if (role != null)
            IconButton(
              tooltip: 'Ubah role',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        KantorRoleEditorScreen(officeId: id, role: role),
                  ),
                );
                if (saved == true) _refresh();
              },
            ),
        ],
      ),
      body: rolesAsync.hasError && role == null
          ? KantorErrorView(error: rolesAsync.error!, onRetry: _refresh)
          : role == null
          ? const KantorLoading(count: 4)
          : _body(context, role, office),
    );
  }

  Widget _body(BuildContext context, KantorRole role, KantorOffice? office) {
    final g = context.ghina;
    final id = widget.officeId;
    final st = kantorRoleStatus(office, role);
    final sessions =
        office?.liveSessionsOf(role.id) ?? const <KantorSessionInfo>[];
    return ListView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      children: [
        Row(
          children: [
            KantorSprite(look: role.look, size: 96),
            const SizedBox(width: GhinaSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.name,
                    style: GhinaType.h2.copyWith(color: g.textPrimary),
                  ),
                  Text(
                    role.title,
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                  const SizedBox(height: GhinaSpace.sm),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (role.isCodex) const KantorCodexBadge(),
                      ChunkyPill(
                        label: st.label,
                        color: st.color,
                        soft: true,
                        uppercase: false,
                      ),
                      if (role.isManager)
                        const ChunkyPill(
                          label: 'Manager',
                          color: GhinaColors.purple,
                          soft: true,
                          uppercase: false,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: GhinaSpace.lg),
        if (!role.archived)
          ChunkyButton(
            label: 'Mulai shift',
            icon: Icons.play_arrow_rounded,
            onPressed: () => showKantorShiftSheet(
              context,
              officeId: id,
              role: role,
              liveSessions: sessions.length,
            ),
          ),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyButton(
          label: 'Pesan agen',
          icon: Icons.forum_outlined,
          variant: ChunkyButtonVariant.outline,
          onPressed: () => openKantorDm(
            context,
            officeId: id,
            role: role.id,
            roleName: role.name,
          ),
        ),
        SectionHeader(title: 'Kepribadian'),
        Text(
          role.persona.isEmpty ? '-' : role.persona,
          style: GhinaType.body.copyWith(color: g.textPrimary, height: 1.4),
        ),
        if (role.skills.isNotEmpty) ...[
          const SectionHeader(title: 'Skills'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in role.skills)
                ChunkyPill(
                  label: s,
                  color: GhinaColors.gray,
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
        ],
        const SectionHeader(title: 'Fakta'),
        ChunkyCard(
          child: Column(
            children: [
              _fact(
                context,
                'Mesin',
                role.isCodex ? 'OpenAI Codex' : 'Claude Code',
              ),
              _fact(context, 'Model', role.modelText),
              _fact(
                context,
                'Ruangan',
                office?.roomName(role.room) ?? role.room,
              ),
              _fact(
                context,
                'Budget bulanan',
                role.budget != null && role.budget! > 0
                    ? kantorUsd(role.budget, 0)
                    : 'Tanpa batas',
              ),
              _fact(context, 'Peran', role.isManager ? 'Manager' : 'Anggota'),
            ],
          ),
        ),
        const SectionHeader(title: 'Sesi aktif'),
        if (sessions.isEmpty)
          Text(
            'Sedang libur. Belum ada sesi aktif.',
            style: GhinaType.body.copyWith(color: g.textMuted),
          )
        else
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
              child: ChunkyTile(
                title: s.title.isEmpty
                    ? 'Sesi ${s.sid.substring(0, 6)}'
                    : s.title,
                trailing: KantorStatusPill(s.status),
                showChevron: true,
                onTap: () => context.push('/kantor/o/$id/s/${s.sid}'),
              ),
            ),
        const SectionHeader(title: 'Playbook'),
        KantorRolePlaybooks(officeId: id, role: role),
        const SectionHeader(title: 'Buku catatan'),
        ChunkyTextField(
          controller: _notes,
          hint:
              'Catatan yang dibawa role ini dari shift ke shift. Role juga bisa menulisnya sendiri.',
          helperText: _notesHint,
          minLines: 5,
          maxLines: 14,
          onChanged: _notesChanged,
        ),
        const SizedBox(height: GhinaSpace.xl),
        ChunkyButton(
          label: role.archived ? 'Pulihkan role' : 'Arsipkan role',
          variant: role.archived
              ? ChunkyButtonVariant.secondary
              : ChunkyButtonVariant.outline,
          onPressed: () => _archive(role, office, !role.archived),
        ),
        const SizedBox(height: GhinaSpace.xxl),
      ],
    );
  }

  Widget _fact(BuildContext context, String k, String v) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
          Text(v, style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary)),
        ],
      ),
    );
  }
}
