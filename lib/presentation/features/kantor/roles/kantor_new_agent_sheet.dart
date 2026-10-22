import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'kantor_role.dart';
import 'kantor_role_editor.dart';
import 'kantor_shift_sheet.dart';
import 'kantor_ui.dart';

const _newRole = '\u0000new-role';

/// "Agen baru": pick a role (or create one) and start its shift with engine,
/// model, permission mode, first task and card. A role that already has a
/// session starts a parallel one (optionally in its own worktree). The daemon
/// has no role-less session, so every agent belongs to a role.
Future<void> showKantorNewAgentSheet(
  BuildContext context, {
  required String officeId,
}) async {
  final pick = await showChunkyBottomSheet<String>(
    context,
    title: 'Agen baru',
    builder: (_) =>
        SingleChildScrollView(child: _NewAgentBody(officeId: officeId)),
  );
  if (pick == _newRole && context.mounted) {
    await kantorAddRole(context, officeId);
  }
}

class _NewAgentBody extends ConsumerStatefulWidget {
  const _NewAgentBody({required this.officeId});

  final String officeId;

  @override
  ConsumerState<_NewAgentBody> createState() => _NewAgentBodyState();
}

class _NewAgentBodyState extends ConsumerState<_NewAgentBody> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final id = widget.officeId;
    final roles = ref.watch(kantorRolesProvider(id));
    final office = ref.watch(kantorOfficeProvider(id)).value;
    return roles.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(GhinaSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kantorRolesProvider(id)),
      ),
      data: (all) {
        final active = [
          for (final r in all)
            if (!r.archived) r,
        ];
        if (active.isEmpty) {
          return EmptyState(
            title: 'Belum ada role',
            message: 'Agen selalu punya role. Buat role pertama dulu.',
            actionLabel: 'Buat role baru',
            onAction: () => Navigator.of(context).pop(_newRole),
            compact: true,
          );
        }
        final role =
            active.where((r) => r.id == _role).firstOrNull ?? active.first;
        String hint(KantorRole r) {
          final n = office?.liveSessionsOf(r.id).length ?? 0;
          return n == 0 ? r.title : '${r.title} · $n sesi aktif';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KantorPickField<String>(
              label: 'Role',
              value: role.id,
              options: [
                for (final r in active) KantorChoice(r.id, r.name, hint(r)),
                const KantorChoice(
                  _newRole,
                  'Buat role baru...',
                  'Lalu langsung mulai shift',
                ),
              ],
              onChanged: (v) {
                if (v == _newRole) {
                  Navigator.of(context).pop(_newRole);
                } else {
                  setState(() => _role = v);
                }
              },
            ),
            const SizedBox(height: GhinaSpace.md),
            KantorShiftForm(
              key: ValueKey(role.id),
              officeId: id,
              role: role,
              liveSessions: office?.liveSessionsOf(role.id).length ?? 0,
            ),
          ],
        );
      },
    );
  }
}
