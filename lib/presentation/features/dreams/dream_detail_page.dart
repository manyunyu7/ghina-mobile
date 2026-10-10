import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_cards.dart';
import 'dream_detail_metrics.dart';
import 'dream_detail_sections.dart';
import 'dream_format.dart';
import 'dream_sheets.dart';
import 'dream_visuals.dart';

/// `/dreams/:id`: header, why / condition / summary, metrics (computed values
/// only when online), the step checklist, costs, the linked note, tags, custom
/// columns and the dream's family. Local data first: it works offline, and the
/// online call only adds the computed values.
class DreamDetailPage extends ConsumerWidget {
  const DreamDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(watchDreamLocalDetailProvider(id));
    final detail = async.value;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(detail?.dream.title ?? 'Mimpi'),
        actions: [
          if (detail != null) ...[
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.push('/dreams/$id/edit'),
            ),
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(context, ref, detail.dream),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dreamOnlineDetailProvider(id));
          await pullToSync(context, ref);
        },
        child: switch (async) {
          AsyncData(:final value?) => _Body(detail: value),
          AsyncData() => ScrollableFill(
            child: EmptyState(
              title: 'Mimpi ini nggak ketemu',
              message: 'Mungkin sudah dihapus di perangkat lain.',
              mood: MascotMood.thinking,
              actionLabel: 'Kembali',
              onAction: () => popOr(context, '/dreams'),
            ),
          ),
          AsyncError() => ScrollableFill(
            child: ErrorRetry(
              onRetry: () => ref.invalidate(watchDreamLocalDetailProvider(id)),
            ),
          ),
          _ => const LoadingListView(tiles: 3),
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Dream d) async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus mimpi ini?',
      message:
          '"${d.title}" beserta langkah dan metriknya akan ikut terhapus dari '
          'semua perangkat.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final r = await ref.read(deleteDreamProvider)(d.id);
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Mimpi dihapus', icon: Icons.delete_rounded);
        popOr(context, '/dreams');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }
}

String _reasonText(String r) => switch (r) {
  'stale' => 'Perlu disegarkan',
  'overdue' => 'Target sudah lewat',
  'off_track' => 'Lewat jalur',
  _ => r,
};

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final DreamLocalDetail detail;

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    Dream d,
  ) async {
    final s = await showDreamStatusSheet(context, current: d.status);
    if (s == null || s == d.status || !context.mounted) return;
    final r = await ref.read(setDreamStatusProvider)(d.id, s);
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        showOkToast(context, 'Status jadi ${s.label}');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final d = detail.dream;
    final onlineAsync = ref.watch(dreamOnlineDetailProvider(d.id));
    final online = onlineAsync.value;
    // A failing call is retried by Riverpod and reads as loading meanwhile:
    // an error already seen counts as offline.
    final loading =
        onlineAsync.isLoading && online == null && !onlineAsync.hasError;
    final cats = ref.watch(watchDreamCategoriesProvider).value ?? const [];
    final defs = ref.watch(watchDreamFieldsProvider).value ?? const [];
    final all = ref.watch(watchDreamsProvider).value ?? const <Dream>[];
    var categoryLabel = d.category;
    for (final c in cats) {
      if (c.key == d.category) categoryLabel = '${c.emoji} ${c.label}';
    }
    final pct =
        online?.progress.pct ?? dreamProgress(d, detail.steps, const []).pct;
    final target = dreamTargetText(d);
    final cost = costTotals(d.costEstimate, detail.steps);
    final reasons = online?.reviewReasons ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        40,
      ),
      children: [
        ChunkyCard(
          key: const ValueKey('dream-header'),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  dreamEmojiText(d.emoji, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.title,
                      key: const ValueKey('dream-title'),
                      style: GhinaType.h2.copyWith(color: g.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    key: const ValueKey('dream-status-chip'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _changeStatus(context, ref, d),
                    child: DreamStatusPill(status: d.status),
                  ),
                  DreamCategoryPill(label: categoryLabel),
                  ChunkyPill(
                    label: dreamPriorityText(d.priority),
                    color: GhinaColors.orange,
                    soft: true,
                    uppercase: false,
                  ),
                  for (final r in reasons)
                    ChunkyPill(
                      key: ValueKey('dream-reason-$r'),
                      label: _reasonText(r),
                      color: GhinaColors.red,
                      soft: true,
                      uppercase: false,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                target.isEmpty ? 'Belum ada target' : '🎯 $target',
                key: const ValueKey('dream-target'),
                style: GhinaType.body.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 10),
              DreamProgressLine(
                key: const ValueKey('dream-progress'),
                pct: pct,
                color: dreamStatusColor(d.status),
              ),
            ],
          ),
        ),
        if (d.why != null) DreamTextCard(title: 'Kenapa', text: d.why!),
        if (d.condition != null)
          DreamTextCard(title: 'Syarat', text: d.condition!),
        if (d.summary != null)
          DreamTextCard(title: 'Ringkasan', text: d.summary!),
        const SizedBox(height: 16),
        DreamMetricsSection(
          dreamId: d.id,
          metrics: detail.metrics,
          online: online,
          loading: loading,
        ),
        DreamStepsSection(steps: detail.steps),
        DreamCostPanel(cost: cost, hasSteps: detail.steps.isNotEmpty),
        if (d.noteId != null) DreamNoteSection(noteId: d.noteId!),
        if (d.tags.isNotEmpty)
          DreamSection(
            title: 'Tag',
            child: Wrap(
              key: const ValueKey('dream-tags'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in d.tags)
                  ChunkyPill(
                    label: '#$t',
                    color: GhinaColors.blue,
                    soft: true,
                    uppercase: false,
                  ),
              ],
            ),
          ),
        DreamFieldsSection(dream: d, defs: defs),
        DreamRelationsSection(dream: d, all: all),
        DreamTimestamps(dream: d),
      ],
    );
  }
}
