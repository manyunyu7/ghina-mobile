import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// The investments part of the home balance card: portfolio value and
/// today's change; tap opens the portfolio.
class HomeInvestmentsStrip extends StatelessWidget {
  const HomeInvestmentsStrip({
    super.key,
    required this.value,
    required this.summary,
    required this.currency,
    required this.edge,
  });

  /// Portfolio value counted in net worth.
  final double value;
  final PortfolioSummary? summary;
  final String currency;

  /// Bottom edge color of the host card.
  final Color edge;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final day = s?.dayChange ?? 0;
    final pct = s?.dayChangePct;
    final hasDay = day.abs() >= 0.005;
    return ChunkySurface(
      key: const ValueKey('home-investments'),
      color: Colors.white.withValues(alpha: 0.18),
      edgeColor: edge,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      onTap: () => context.push('/investments'),
      semanticLabel: 'Investasi, buka portofolio',
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: GhinaRadii.rMd,
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Investasi ',
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: Colors.white),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MoneyText(
                          amount: value,
                          currency: currency,
                          tone: MoneyTone.neutral,
                          color: Colors.white,
                          style: GhinaType.moneyS,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  key: const ValueKey('home-investments-day'),
                  children: [
                    Text(
                      'Hari ini ',
                      style: GhinaType.caption
                          .w(700)
                          .copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                    if (hasDay) ...[
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MoneyText(
                            amount: day,
                            currency: currency,
                            compact: true,
                            tone: MoneyTone.auto,
                            color: Colors.white,
                            style: GhinaType.caption.w(900),
                          ),
                        ),
                      ),
                      if (pct != null)
                        Text(
                          ' (${pct > 0 ? '+' : '−'}${Fmt.number(pct.abs(), decimals: 2)}%)',
                          style: GhinaType.caption
                              .w(900)
                              .copyWith(color: Colors.white),
                        ),
                    ] else
                      Text(
                        'belum bergerak',
                        style: GhinaType.caption
                            .w(700)
                            .copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                      ),
                    if (s?.stale ?? false) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                        semanticLabel: 'Harga lama',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }
}
