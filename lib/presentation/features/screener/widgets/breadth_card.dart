import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../controllers/screener_providers.dart';
import '../screener_format.dart';
import 'screener_charts.dart';
import 'screener_common.dart';

/// "Napas pasar": market-wide breadth per month, collapsible. Loads on its
/// own, so a failure here never blocks the list.
class BreadthCard extends ConsumerStatefulWidget {
  const BreadthCard({super.key});

  @override
  ConsumerState<BreadthCard> createState() => _BreadthCardState();
}

class _BreadthCardState extends ConsumerState<BreadthCard> {
  bool _open = true;
  int _months = 24;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(screenerBreadthProvider(_months));
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('breadth-toggle'),
            borderRadius: GhinaRadii.rMd,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Napas pasar',
                      style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: g.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            switch (async) {
              AsyncData(:final value) => _content(context, value),
              AsyncError(:final error) => ScreenerErrorView(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(screenerBreadthProvider(_months)),
              ),
              _ => const Skeleton(height: 160, radius: GhinaRadii.lg),
            },
          ],
        ],
      ),
    );
  }

  Widget _content(BuildContext context, List<BreadthMonth> months) {
    final g = context.ghina;
    if (months.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Belum ada data pasar.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      );
    }
    final pct = months.last.decliningPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                pct == null
                    ? 'Bulan terakhir belum ada data'
                    : '${screenerNum(pct.round())}% emiten pemegangnya turun',
                key: const ValueKey('breadth-latest'),
                style: GhinaType.body
                    .w(800)
                    .copyWith(color: screenerPrimary(context)),
              ),
            ),
            SizedBox(
              width: 120,
              child: ChunkySegmented<int>(
                height: 34,
                segments: const [
                  ChunkySegment(value: 12, label: '12'),
                  ChunkySegment(value: 24, label: '24'),
                ],
                value: _months,
                onChanged: (m) => setState(() => _months = m),
              ),
            ),
          ],
        ),
        Text(
          'pada ${Fmt.monthYear(months.last.month)}',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 12),
        BreadthChart(months: months),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _dot(context, screenerPrimary(context), 'Turun'),
            _dot(context, g.textMuted.withValues(alpha: 0.55), 'Naik'),
          ],
        ),
      ],
    );
  }

  Widget _dot(BuildContext context, Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
      ),
    ],
  );
}
