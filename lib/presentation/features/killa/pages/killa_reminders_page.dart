import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_data_providers.dart';
import '../widgets/killa_common.dart';

/// "Pengingat Killa" (`/killa/reminders`): reminders the agent scheduled in
/// the chat (they fire on WhatsApp / the engine, not as local notifications).
class KillaRemindersPage extends ConsumerStatefulWidget {
  const KillaRemindersPage({super.key});

  @override
  ConsumerState<KillaRemindersPage> createState() => _KillaRemindersPageState();
}

class _KillaRemindersPageState extends ConsumerState<KillaRemindersPage> {
  final Set<String> _cancelling = {};

  Future<void> _cancel(KillaReminder r) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Batalkan pengingat?',
      message: '"${r.text}" nggak akan dikirim lagi.',
      confirmLabel: 'Batalkan',
      cancelLabel: 'Biarkan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cancelling.add(r.id));
    try {
      final done = await ref.read(cancelKillaReminderProvider)(r.id);
      if (!mounted) return;
      if (done) {
        showOkToast(context, 'Pengingat dibatalkan');
      } else {
        showToastBadge(
          context,
          message: 'Pengingat ini sudah nggak ada (mungkin sudah terkirim)',
          icon: Icons.info_rounded,
          color: GhinaColors.blue,
        );
      }
      ref.invalidate(killaRemindersProvider);
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _cancelling.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(killaRemindersProvider);
    final now = ref.watch(clockProvider).now();
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Pengingat Killa')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(killaRemindersProvider.future),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => const ScrollableFill(
            child: EmptyState(
              mood: MascotMood.sleeping,
              title: 'Nggak ada pengingat',
              message:
                  'Minta Killa di chat, mis. "ingetin aku minum obat tiap jam 8 '
                  'malam".',
            ),
          ),
          AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              32,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = value[i];
              final busy = _cancelling.contains(r.id);
              return ChunkyCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    CategoryAvatar(
                      icon: Icons.alarm_rounded,
                      color: killaSwatch.base,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.text,
                            style: GhinaType.body
                                .w(800)
                                .copyWith(color: g.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (r.nextAt != null)
                                'Berikutnya ${Fmt.relativeDay(r.nextAt!, now: now)} '
                                    '${Fmt.time(r.nextAt!)}',
                              ?r.spec,
                            ].join(' · '),
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChunkyButton(
                      label: 'Batalkan',
                      size: ChunkyButtonSize.small,
                      variant: ChunkyButtonVariant.outline,
                      expand: false,
                      loading: busy,
                      onPressed: busy ? null : () => _cancel(r),
                    ),
                  ],
                ),
              );
            },
          ),
          AsyncError(:final error) => KillaErrorView(
            error: error,
            onRetry: () => ref.invalidate(killaRemindersProvider),
          ),
          _ => const LoadingListView(hero: false, tiles: 4),
        },
      ),
    );
  }
}
