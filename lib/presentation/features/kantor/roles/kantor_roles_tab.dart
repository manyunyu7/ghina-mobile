import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import '../codex/kantor_codex.dart';
import 'kantor_playbooks.dart';
import 'kantor_role.dart';
import 'kantor_role_detail.dart';
import 'kantor_role_editor.dart';
import 'kantor_shift_sheet.dart';

/// Tab "Role": the office's employees, their status, and shifts.
class KantorRolesTab extends ConsumerStatefulWidget {
  const KantorRolesTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorRolesTab> createState() => _KantorRolesTabState();
}

class _KantorRolesTabState extends ConsumerState<KantorRolesTab> {
  bool _showArchived = false;

  void _refresh() {
    ref.invalidate(kantorRolesProvider(widget.officeId));
    ref.invalidate(kantorOfficeProvider(widget.officeId));
    ref.invalidate(kantorPlaybooksProvider(widget.officeId));
    ref.invalidate(kantorProposalsProvider(widget.officeId));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.officeId;
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null) return;
      final t = m['t'];
      if (t == 'session' || t == 'session-gone') {
        ref.invalidate(kantorOfficeProvider(id));
      } else if (t == 'changed' && (m['office'] == id || m['office'] == '*')) {
        switch (m['what']) {
          case 'roles' || 'plan':
            _refresh();
          case 'wiki':
            ref.invalidate(kantorPlaybooksProvider(id));
            ref.invalidate(kantorProposalsProvider(id));
        }
      }
    });

    final roles = ref.watch(kantorRolesProvider(id));
    final office = ref.watch(kantorOfficeProvider(id));
    final pbs =
        ref.watch(kantorPlaybooksProvider(id)).value ??
        const <KantorPlaybook>[];

    return roles.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(error: e, onRetry: _refresh),
      data: (all) {
        final active = [
          for (final r in all)
            if (!r.archived) r,
        ];
        final archived = [
          for (final r in all)
            if (r.archived) r,
        ];
        final off = office.value;
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await ref.read(kantorRolesProvider(id).future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  GhinaSpace.md,
                  GhinaSpace.page,
                  96,
                ),
                children: [
                  KantorProposalsSection(officeId: id),
                  SectionHeader(
                    title: 'Role',
                    subtitle:
                        'Karyawan tetap kantor ini. Satu role bisa punya beberapa sesi paralel.',
                    trailing: ChunkyButton(
                      label: 'Tambah',
                      icon: Icons.add_rounded,
                      size: ChunkyButtonSize.small,
                      onPressed: _add,
                    ),
                  ),
                  if (active.isEmpty)
                    EmptyState(
                      title: 'Belum ada role',
                      message: 'Tambahkan role pertama untuk mengisi kantor.',
                      actionLabel: 'Tambah role',
                      onAction: _add,
                      compact: true,
                    ),
                  for (final r in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                      child: _RoleCard(
                        role: r,
                        office: off,
                        playbooks: pbs
                            .where((p) => p.roles.contains(r.id))
                            .length,
                        onOpen: () => _open(r),
                        onShift: () => showKantorShiftSheet(
                          context,
                          officeId: id,
                          role: r,
                          liveSessions: off?.liveSessionsOf(r.id).length ?? 0,
                        ),
                      ),
                    ),
                  if (archived.isNotEmpty) ...[
                    TextButton(
                      onPressed: () =>
                          setState(() => _showArchived = !_showArchived),
                      child: Text(
                        '${_showArchived ? 'Sembunyikan' : 'Tampilkan'} ${archived.length} role diarsipkan',
                      ),
                    ),
                    if (_showArchived)
                      for (final r in archived)
                        Padding(
                          padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                          child: _RoleCard(
                            role: r,
                            office: off,
                            playbooks: 0,
                            onOpen: () => _open(r),
                          ),
                        ),
                  ],
                ],
              ),
            ),
            Positioned(
              right: GhinaSpace.page,
              bottom: GhinaSpace.page,
              child: FloatingActionButton.extended(
                heroTag: 'kantor-role-add',
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Tambah role'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _open(KantorRole r) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            KantorRoleDetailScreen(officeId: widget.officeId, roleId: r.id),
      ),
    );
    _refresh();
  }

  Future<void> _add() async {
    if (await kantorAddRole(context, widget.officeId)) _refresh();
  }
}

/// Status of a role from its live sessions.
({String label, ChunkySwatch color}) kantorRoleStatus(
  KantorOffice? office,
  KantorRole r,
) {
  if (r.archived) return (label: 'Diarsipkan', color: GhinaColors.gray);
  final ss = office?.liveSessionsOf(r.id) ?? const [];
  if (ss.isEmpty) return (label: 'Libur', color: GhinaColors.gray);
  final n = ss.length > 1 ? ' · ${ss.length} sesi' : '';
  if (ss.any((s) => s.status == 'waiting'))
    return (label: 'Menunggu izin$n', color: GhinaColors.orange);
  if (ss.any((s) => s.status == 'working' || s.status == 'starting'))
    return (label: 'Bekerja$n', color: GhinaColors.green);
  return (label: 'Idle$n', color: GhinaColors.blue);
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.office,
    required this.playbooks,
    required this.onOpen,
    this.onShift,
  });

  final KantorRole role;
  final KantorOffice? office;
  final int playbooks;
  final VoidCallback onOpen;
  final VoidCallback? onShift;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final st = kantorRoleStatus(office, role);
    return Opacity(
      opacity: role.archived ? 0.6 : 1,
      child: ChunkyCard(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KantorSprite(look: role.look, size: 64),
                const SizedBox(width: GhinaSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                      Text(
                        role.title,
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ChunkyPill(
                            label: st.label,
                            color: st.color,
                            soft: true,
                            uppercase: false,
                          ),
                          if (role.isCodex) const KantorCodexBadge(),
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
            if (role.persona.isNotEmpty) ...[
              const SizedBox(height: GhinaSpace.md),
              Text(
                role.persona,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            ],
            if (role.skills.isNotEmpty) ...[
              const SizedBox(height: GhinaSpace.sm),
              Wrap(
                spacing: 6,
                runSpacing: 4,
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
            const SizedBox(height: GhinaSpace.sm),
            Text(
              [
                role.modelText,
                office?.roomName(role.room) ?? role.room,
                if (playbooks > 0) '$playbooks playbook',
              ].where((s) => s.isNotEmpty).join(' · '),
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
            if (onShift != null && !role.archived) ...[
              const SizedBox(height: GhinaSpace.md),
              ChunkyButton(
                label: 'Mulai shift',
                icon: Icons.play_arrow_rounded,
                size: ChunkyButtonSize.small,
                onPressed: onShift,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
