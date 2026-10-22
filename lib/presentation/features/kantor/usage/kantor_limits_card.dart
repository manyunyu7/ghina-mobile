import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import 'kantor_usage_data.dart';

/// Subscription quota: Claude (5 hours, weekly) and Codex. Bars turn orange
/// from 80% and red from 90%. [onTap] opens the full usage screen.
class KantorLimitsCard extends ConsumerWidget {
  const KantorLimitsCard({super.key, this.onTap, this.now});

  final VoidCallback? onTap;

  /// Test hook for the clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(kantorUsageLimitsProvider);
    final clock = now ?? DateTime.now();
    final d = async.value;
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      onTap: onTap,
      semanticLabel: 'Batas pemakaian langganan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Batas pemakaian',
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: g.textMuted),
            ],
          ),
          const SizedBox(height: GhinaSpace.sm),
          if (d == null && async.isLoading && !async.hasError)
            Text(
              'Memuat…',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            )
          else if (d == null)
            Text(
              'Batas pemakaian belum bisa dibaca dari daemon.',
              style: GhinaType.caption.copyWith(color: g.textMuted),
            )
          else ...[
            _Engine(
              name: 'Claude',
              engine: d['claude'],
              now: clock,
              empty:
                  'Belum ada laporan. Batas Claude datang dari statusline sesi Claude Code yang berjalan lewat Kantor.',
            ),
            const SizedBox(height: GhinaSpace.md),
            _Engine(
              name: 'Codex',
              engine: d['codex'],
              now: clock,
              empty: 'Belum ada sesi Codex dengan data kuota.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Engine extends StatelessWidget {
  const _Engine({
    required this.name,
    required this.engine,
    required this.now,
    required this.empty,
  });

  final String name;
  final Object? engine;
  final DateTime now;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final ws = usageWindows(engine);
    final updated = engine is Map
        ? agoText((engine as Map)['updatedAt'], now)
        : '';
    final plan = engine is Map ? (engine as Map)['plan'] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              name,
              style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
            ),
            if (plan is String && plan.isNotEmpty) ...[
              const SizedBox(width: GhinaSpace.xs),
              Text(plan, style: GhinaType.caption.copyWith(color: g.textMuted)),
            ],
            const Spacer(),
            if (updated.isNotEmpty)
              Text(
                updated,
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (ws.isEmpty)
          Text(empty, style: GhinaType.caption.copyWith(color: g.textMuted))
        else
          for (final w in ws) ...[
            _WindowBar(w: w, now: now),
            const SizedBox(height: GhinaSpace.sm),
          ],
      ],
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.w, required this.now});

  final UsageWindow w;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = w.shown;
    final reset = untilReset(w.resetsAt, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                w.label,
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ),
            Text(
              w.expired ? 'sudah reset' : '${p.round()}% terpakai',
              style: GhinaType.caption
                  .w(800)
                  .copyWith(
                    color: p >= 80 ? usageColor(p).base : g.textPrimary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ChunkyProgressBar(
          value: p / 100,
          color: usageColor(p),
          height: 12,
          animate: false,
        ),
        if (reset.isNotEmpty && !w.expired)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              reset,
              style: GhinaType.caption.copyWith(color: g.textMuted),
            ),
          ),
      ],
    );
  }
}
