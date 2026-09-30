import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_data_providers.dart';
import '../widgets/killa_common.dart';

/// The workspace's latest 100 commits (`/killa/commits`).
class KillaCommitsPage extends ConsumerWidget {
  const KillaCommitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(killaCommitsProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Commit')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(killaCommitsProvider.future),
        child: switch (async) {
          AsyncData(:final value) when value.isEmpty => const ScrollableFill(
            child: EmptyState(
              title: 'Belum ada commit',
              message: 'Riwayat perubahan workspace Killa muncul di sini.',
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
              final c = value[i];
              return ChunkyCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: c.hash));
                  showOkToast(context, 'Hash ${c.shortHash} disalin');
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: g.tint(killaSwatch),
                        borderRadius: GhinaRadii.rPill,
                      ),
                      child: Text(
                        c.shortHash,
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(
                              fontFamily: 'monospace',
                              color: killaSwatch.base,
                            ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.subject.isEmpty ? '(tanpa pesan)' : c.subject,
                            style: GhinaType.body
                                .w(800)
                                .copyWith(color: g.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              ?c.author,
                              if (c.date != null)
                                '${Fmt.relativeDay(c.date!)} ${Fmt.time(c.date!)}',
                            ].join(' · '),
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          AsyncError(:final error) => KillaErrorView(
            error: error,
            onRetry: () => ref.invalidate(killaCommitsProvider),
          ),
          _ => const LoadingListView(hero: false, tiles: 8),
        },
      ),
    );
  }
}
