import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dates.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_format.dart';
import 'dream_list_logic.dart';
import 'dream_list_rows.dart';
import 'dream_review_logic.dart';
import 'dream_sheets.dart';
import 'dream_visuals.dart';

/// `/dreams/review` ("Segarkan"): walks through the dreams that are stale or
/// tagged `perlu-ditinjau`, one at a time. Every action saves at once.
///
/// The queue is captured once when the page opens, so a save that makes a
/// dream leave the live queue never shifts the position; "3 / 43" counts that
/// captured list.
class DreamReviewPage extends ConsumerStatefulWidget {
  const DreamReviewPage({super.key});

  @override
  ConsumerState<DreamReviewPage> createState() => _DreamReviewPageState();
}

class _DreamReviewPageState extends ConsumerState<DreamReviewPage> {
  List<String>? _ids;
  int _i = 0;
  bool _busy = false;

  void _next(int from) => setState(() => _i = from + 1);

  /// Runs a save; a failure shows a toast and returns false (dream stays).
  Future<bool> _save(Future<Result<Object?>> Function() run) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final r = await run();
    if (!mounted) return false;
    setState(() => _busy = false);
    if (r case Err(:final failure)) {
      showFailureToast(context, failure);
      return false;
    }
    return true;
  }

  Future<void> _keep(DreamRow row, int at) async {
    final d = row.dream;
    final ok = await _save(
      () => ref.read(updateDreamProvider)(
        d.id,
        dreamInputOf(d, tags: removeReviewTag(d.tags)),
      ),
    );
    if (ok) _next(at);
  }

  Future<void> _status(DreamRow row, int at) async {
    final d = row.dream;
    final s = await showDreamStatusSheet(context, current: d.status);
    if (s == null || !mounted) return;
    final ok = await _save(() => ref.read(setDreamStatusProvider)(d.id, s));
    // Done / dropped leave the queue, so move on; an open status stays.
    if (ok && !s.isOpen) _next(at);
  }

  Future<void> _target(DreamRow row) async {
    final d = row.dream;
    final choice = await showChunkyBottomSheet<String>(
      context,
      title: 'Atur target',
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyTile(
            key: const ValueKey('target-pick'),
            dense: true,
            leading: const Text('🎯', style: TextStyle(fontSize: 20)),
            title: 'Pilih tanggal',
            onTap: () => Navigator.of(c).pop('pick'),
          ),
          if (d.targetDate != null) ...[
            const SizedBox(height: 8),
            ChunkyTile(
              key: const ValueKey('target-clear'),
              dense: true,
              leading: const Icon(Icons.event_busy_rounded),
              title: 'Hapus target',
              onTap: () => Navigator.of(c).pop('clear'),
            ),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    String? date;
    if (choice == 'pick') {
      final now = ref.read(clockProvider).now();
      final cur = d.targetDate == null
          ? null
          : DateTime.tryParse(d.targetDate!);
      final picked = await showGhinaDatePicker(
        context,
        initial: cur ?? now,
        today: now,
        title: 'Target mimpi',
      );
      if (picked == null || !mounted) return;
      date = dateKey(picked);
    }
    await _save(
      () => ref.read(updateDreamProvider)(
        d.id,
        dreamInputOf(
          d,
          targetDate: date,
          targetPrecision: date == null ? null : TargetPrecision.day,
        ),
      ),
    );
  }

  Future<void> _progress(DreamRow row) async {
    final d = row.dream;
    final r = await showChunkyBottomSheet<({int? value})>(
      context,
      title: 'Atur progres',
      showClose: true,
      builder: (_) =>
          _ProgressSheet(initial: d.progressManual ?? row.progressPct),
    );
    if (r == null || !mounted) return;
    await _save(
      () => ref.read(updateDreamProvider)(
        d.id,
        dreamInputOf(d, progressManual: r.value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rowsAsync = ref.watch(dreamRowsProvider);
    final rows = rowsAsync.value;
    if (rows != null) _ids ??= reviewSessionIds(rows);

    Widget body;
    if (rowsAsync.hasError && rows == null) {
      body = ScrollableFill(
        child: ErrorRetry(onRetry: () => ref.invalidate(watchDreamsProvider)),
      );
    } else if (rows == null) {
      body = const LoadingListView(tiles: 3);
    } else {
      final byId = {for (final r in rows) r.id: r};
      final ids = _ids!;
      // A dream deleted meanwhile is skipped.
      var at = _i;
      while (at < ids.length && !byId.containsKey(ids[at])) {
        at++;
      }
      body = at >= ids.length
          ? ScrollableFill(
              child: EmptyState(
                key: const ValueKey('review-empty'),
                title: 'Semua sudah segar',
                message: 'Tidak ada mimpi yang perlu ditinjau. Mantap! 🌿',
                mood: MascotMood.waving,
                actionLabel: 'Kembali',
                onAction: () => popOr(context, '/dreams'),
              ),
            )
          : _card(context, byId[ids[at]]!, at, ids.length);
    }

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Segarkan')),
      body: body,
    );
  }

  Widget _card(BuildContext context, DreamRow row, int at, int total) {
    final g = context.ghina;
    final d = row.dream;
    final now = ref.watch(clockProvider).now().millisecondsSinceEpoch;
    final categories =
        ref.watch(watchDreamCategoriesProvider).value ??
        const <DreamCategory>[];
    final reasons = dreamReviewReasonTexts(
      stale: row.stale,
      overdue: row.overdue,
      tagged: row.tagged,
    );
    final target = dreamTargetText(d);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        Text(
          reviewPositionText(at, total),
          key: const ValueKey('review-position'),
          style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 8),
        ChunkyProgressBar(value: (at + 1) / total, height: 8),
        const SizedBox(height: 16),
        ChunkyCard(
          key: ValueKey('review-card-${d.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(d.emoji ?? '✨', style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.title,
                      key: const ValueKey('review-title'),
                      style: GhinaType.h2.copyWith(color: g.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  DreamStatusPill(status: d.status),
                  DreamCategoryPill(
                    label: dreamCategoryLabel(d.category, categories),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _fact(
                context,
                Icons.flag_rounded,
                target.isEmpty ? 'Belum ada target' : 'Target $target',
              ),
              const SizedBox(height: 8),
              DreamProgressLine(
                pct: row.progressPct,
                color: dreamStatusColor(d.status),
              ),
              const SizedBox(height: 8),
              _fact(
                context,
                Icons.history_rounded,
                dreamUpdatedText(row.lastActivityMs, now),
              ),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final t in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $t',
                      style: GhinaType.bodyS
                          .w(700)
                          .copyWith(color: GhinaColors.orange.base),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          key: const ValueKey('review-keep'),
          label: 'Masih berlaku',
          icon: Icons.check_rounded,
          onPressed: _busy ? null : () => _keep(row, at),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('review-status'),
                label: 'Status',
                variant: ChunkyButtonVariant.outline,
                size: ChunkyButtonSize.medium,
                onPressed: _busy ? null : () => _status(row, at),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('review-target'),
                label: 'Target',
                variant: ChunkyButtonVariant.outline,
                size: ChunkyButtonSize.medium,
                onPressed: _busy ? null : () => _target(row),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('review-progress'),
                label: 'Progres',
                variant: ChunkyButtonVariant.outline,
                size: ChunkyButtonSize.medium,
                onPressed: _busy ? null : () => _progress(row),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('review-edit'),
                label: 'Ubah',
                icon: Icons.edit_rounded,
                variant: ChunkyButtonVariant.outline,
                size: ChunkyButtonSize.medium,
                onPressed: () => context.push('/dreams/${d.id}/edit'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('review-skip'),
                label: 'Lewati',
                icon: Icons.skip_next_rounded,
                variant: ChunkyButtonVariant.outline,
                size: ChunkyButtonSize.medium,
                onPressed: _busy ? null : () => _next(at),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fact(BuildContext context, IconData icon, String text) {
    final g = context.ghina;
    return Row(
      children: [
        Icon(icon, size: 16, color: g.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Slider 0-100 for the manual progress; "Hapus progres manual" clears it.
class _ProgressSheet extends StatefulWidget {
  const _ProgressSheet({required this.initial});

  final int? initial;

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  late double _v = (widget.initial ?? 0).toDouble().clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            '${_v.round()}%',
            key: const ValueKey('progress-value'),
            style: GhinaType.h1.copyWith(color: g.textPrimary),
          ),
        ),
        Slider(
          key: const ValueKey('progress-slider'),
          value: _v,
          min: 0,
          max: 100,
          divisions: 100,
          label: '${_v.round()}%',
          onChanged: (v) => setState(() => _v = v),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('progress-save'),
          label: 'Simpan',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).pop((value: _v.round())),
        ),
        const SizedBox(height: 8),
        ChunkyButton(
          key: const ValueKey('progress-clear'),
          label: 'Hapus progres manual',
          variant: ChunkyButtonVariant.outline,
          size: ChunkyButtonSize.medium,
          onPressed: () => Navigator.of(context).pop((value: null)),
        ),
      ],
    );
  }
}
