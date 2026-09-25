import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import 'investments_strip.dart';

/// Home hero: **Kekayaan bersih** (wallets + investments, `DashboardSummary
/// .netWorth`) with the Kas · Investasi breakdown and today's portfolio
/// change. Without investments it stays the plain "Total saldo" card.
/// Amounts respect balance privacy; long-press peeks.
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key, required this.dash, required this.currency});

  final DashboardSummary dash;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final white70 = Colors.white.withValues(alpha: 0.82);
    final n = dash.wallets.length;
    // Watching the portfolio also keeps its prices fresh while home is open.
    final portfolio = ref.watch(watchPortfolioProvider).value;
    final invested =
        dash.investmentsValue != 0 || (portfolio != null && !portfolio.isEmpty);
    final walletsLine = n == 0
        ? 'Belum ada dompet · tambah yuk'
        : 'di $n dompet';
    // Long-press peeks while balances are hidden; the eye flips the setting.
    return MoneyPeek(
      child: ChunkyCard(
        color: GhinaColors.blue,
        onTap: () => context.push('/wallets'),
        semanticLabel: invested
            ? 'Kekayaan bersih, buka dompet'
            : 'Total saldo, buka dompet',
        padding: EdgeInsets.fromLTRB(20, 18, 16, invested ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            Text(
                              invested ? 'KEKAYAAN BERSIH' : 'TOTAL SALDO',
                              style: GhinaType.overline.copyWith(
                                color: white70,
                              ),
                            ),
                            const SizedBox(width: 2),
                            MoneyVisibilityToggle(color: white70, size: 18),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: GhinaMotion.fast,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, ?current],
                        ),
                        child: FittedBox(
                          key: ValueKey(context.moneyHidden),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MoneyText(
                            key: const ValueKey('home-networth'),
                            amount: invested
                                ? dash.netWorth
                                : dash.totalBalance,
                            currency: currency,
                            tone: MoneyTone.neutral,
                            color: Colors.white,
                            countUp: true,
                            style: GhinaType.moneyL.copyWith(fontSize: 34),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (invested)
                        Row(
                          key: const ValueKey('home-cash-line'),
                          children: [
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              color: white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Kas ',
                              style: GhinaType.bodyS
                                  .w(700)
                                  .copyWith(color: white70),
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: MoneyText(
                                  amount: dash.totalBalance,
                                  currency: currency,
                                  tone: MoneyTone.neutral,
                                  color: Colors.white,
                                  style: GhinaType.moneyS,
                                ),
                              ),
                            ),
                            Text(
                              ' · $walletsLine',
                              maxLines: 1,
                              style: GhinaType.bodyS
                                  .w(700)
                                  .copyWith(color: white70),
                            ),
                          ],
                        )
                      else
                        Text(
                          walletsLine,
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: white70),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ],
            ),
            if (invested) ...[
              const SizedBox(height: 12),
              HomeInvestmentsStrip(
                value: dash.investmentsValue,
                summary: portfolio,
                currency: currency,
                edge: GhinaColors.blue.edge,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
