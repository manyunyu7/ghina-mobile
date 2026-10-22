import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';
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
                  final id = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) =>
                          KantorMeetingFormScreen(officeId: officeId),
                    ),
                  );
                  ref.invalidate(kantorMeetingsProvider(officeId));
                  if (id != null && context.mounted) _open(context, ref, id);
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
                  onTap: () => _open(context, ref, m.id),
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

  void _open(BuildContext context, WidgetRef ref, String id) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) =>
                KantorMeetingDetailScreen(officeId: officeId, meetingId: id),
          ),
        )
        .then((_) => ref.invalidate(kantorMeetingsProvider(officeId)));
  }
}
