import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../screener_format.dart';
import 'screener_charts.dart';
import 'screener_common.dart';

/// One result of the screen: ticker, price, count step, change, streak, a
/// ratio bar and a sparkline.
class ScreenerRowTile extends StatelessWidget {
  const ScreenerRowTile({super.key, required this.row, required this.onTap});

  final ScreenerRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final down = row.changePercent < 0;
    return ChunkyCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: GhinaRadii.rLg,
      semanticLabel:
          '${row.ticker}, pemegang ${screenerPercent(row.changePercent)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.ticker,
                      style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
                    ),
                    Text(
                      '${row.points} laporan',
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
              PriceWithChange(
                price: row.price,
                changePercent: row.priceChangePercent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${screenerNum(row.firstCount)} → ${screenerNum(row.lastCount)}',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          down
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 18,
                          color: primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          screenerPercent(row.changePercent),
                          style: GhinaType.h3.w(900).copyWith(color: primary),
                        ),
                        const SizedBox(width: 8),
                        ChunkyPill(
                          label: '${row.declineStreak}×',
                          soft: true,
                          color: GhinaColors.orange,
                          uppercase: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Sparkline(values: row.spark),
            ],
          ),
          const SizedBox(height: 8),
          _RatioBar(ratio: row.declineRatio),
        ],
      ),
    );
  }
}

class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final pct = (ratio * 100).round();
    return Semantics(
      label: 'Porsi laporan yang turun $pct persen',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 5,
                color: screenerPrimary(context),
                backgroundColor: g.surfaceAlt,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$pct% turun',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}
