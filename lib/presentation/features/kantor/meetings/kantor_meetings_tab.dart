import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
import '../widgets/kantor_wide.dart';
import 'kantor_meeting.dart';
import 'kantor_meeting_detail.dart';
import 'kantor_meeting_form.dart';

/// Tab "Rapat": past and running meetings, and a new-meeting form.
class KantorMeetingsTab extends ConsumerWidget {
  const KantorMeetingsTab({super.key, required this.officeId});

  final String officeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m != null &&
          m['t'] == 'changed' &&
          m['what'] == 'meetings' &&
          (m['office'] == officeId || m['office'] == '*')) {
        ref.invalidate(kantorMeetingsProvider(officeId));
      }
    });
    void reload() => ref.invalidate(kantorMeetingsProvider(officeId));

    // Layar lebar: daftar rapat di kiri, detail rapat di kanan. Layar sempit:
    // daftar saja, detail halaman penuh, daftar dimuat ulang saat kembali.
    return KantorMasterDetail<String>(
      key: ValueKey('meetings-$officeId'),
      keyOf: (id) => id,
      onClosed: reload,
      empty: const KantorPaneEmpty(
        icon: Icons.groups_outlined,
        text: 'Pilih rapat di kiri untuk membaca jalannya dan notulennya.',
      ),
      detail: (_, id) =>
          KantorMeetingDetailScreen(officeId: officeId, meetingId: id),
      master: (context, selected, open) => Consumer(
        builder: (context, ref, _) => _master(context, ref, selected, open),
      ),
    );
  }

  Widget _master(
    BuildContext context,
    WidgetRef ref,
    String? selected,
    void Function(String) open,
  ) {
    final meetings = ref.watch(kantorMeetingsProvider(officeId));
    final roles =
        ref.watch(kantorRolesProvider(officeId)).value ?? const <KantorRole>[];
    final g = context.ghina;

    return meetings.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kantorMeetingsProvider(officeId)),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(kantorMeetingsProvider(officeId));
          await ref.read(kantorMeetingsProvider(officeId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            96,
          ),
          children: [
            SectionHeader(
              title: 'Rapat',
              subtitle:
                  'Role AI berdiskusi bergiliran, lalu ketua menulis notulen.',
              trailing: ChunkyButton(
                label: 'Rapat baru',
                icon: Icons.add_rounded,
                size: ChunkyButtonSize.small,
                onPressed: () async {
                  // Form rapat baru: panel samping di layar lebar.
                  final id = await kantorPushAdaptive<String>(
                    context,
                    (_) => KantorMeetingFormScreen(officeId: officeId),
                  );
                  ref.invalidate(kantorMeetingsProvider(officeId));
                  if (id != null && context.mounted) open(id);
                },
              ),
            ),
            if (list.isEmpty)
              const EmptyState(
                title: 'Belum ada rapat',
                message:
                    'Mulai rapat untuk membahas satu topik bersama beberapa role.',
                compact: true,
              ),
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                child: ChunkyCard(
                  onTap: () => open(m.id),
                  // rapat yang sedang terbuka di panel kanan disorot
                  tinted: selected == m.id ? GhinaColors.blue : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.topic,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                      const SizedBox(height: GhinaSpace.sm),
                      Row(
                        children: [
                          KantorStatusPill(m.status),
                          const SizedBox(width: GhinaSpace.sm),
                          Expanded(
                            child: Text(
                              '${kantorWhen(m.createdAt)} · ${m.participants.length} peserta · ${kantorUsd(m.cost, 3)}',
                              style: GhinaType.caption.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GhinaSpace.sm),
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final pid in m.participants)
                            KantorSprite(
                              look:
                                  roles
                                      .where((r) => r.id == pid)
                                      .firstOrNull
                                      ?.look ??
                                  KantorSprite.guestLook(pid),
                              size: 32,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
