import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/linked_trade.dart';

/// `/investments/cash/:txId` — opened from a wallet transaction of type
/// `investment` (transactions list, home): finds the trade that created it and
/// replaces itself with that trade's edit form (or the asset when the trade
/// can't be edited here). Such transactions are managed from the portfolio,
/// never from the transaction form.
class InvestmentCashPage extends ConsumerStatefulWidget {
  const InvestmentCashPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<InvestmentCashPage> createState() => _InvestmentCashPageState();
}

class _InvestmentCashPageState extends ConsumerState<InvestmentCashPage> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final linked = ref.watch(linkedTradeProvider(widget.transactionId));
    final found = linked.value;
    if (found != null && !_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(
          '/investments/${found.asset.id}/trade/${found.trade.id}',
        );
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi investasi')),
      body: switch (linked) {
        AsyncData(value: null) => ScrollableFill(
          child: EmptyState(
            key: const ValueKey('invest-cash-missing'),
            mood: MascotMood.thinking,
            title: 'Asetnya belum ketemu',
            message:
                'Transaksi ini dibuat dari portofolio, tapi datanya belum sampai di HP ini. '
                'Coba sinkron dulu, ya.',
            actionLabel: 'Buka portofolio',
            onAction: () => context.pushReplacement('/investments'),
          ),
        ),
        AsyncError() => ErrorRetry(
          onRetry: () =>
              ref.invalidate(linkedTradeProvider(widget.transactionId)),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(GhinaSpace.page),
          child: SkeletonList(count: 3),
        ),
      },
    );
  }
}
