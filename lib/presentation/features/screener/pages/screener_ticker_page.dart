import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/screener_providers.dart';
import '../screener_format.dart';
import '../widgets/screener_charts.dart';
import '../widgets/screener_common.dart';
import '../widgets/stockbit_connect_sheet.dart';

/// One ticker: price, shareholder change over 3 / 6 / 12 / 36 months, the
/// charts and the list of reports.
class ScreenerTickerPage extends ConsumerStatefulWidget {
  const ScreenerTickerPage({super.key, required this.ticker});

  final String ticker;

  @override
  ConsumerState<ScreenerTickerPage> createState() => _ScreenerTickerPageState();
}

class _ScreenerTickerPageState extends ConsumerState<ScreenerTickerPage> {
  ChartRange _range = ChartRange.year;

  String get _code => widget.ticker.toUpperCase();

  Future<void> _connect() async {
    await showStockbitConnectSheet(context);
    if (!mounted) return;
    ref.invalidate(stockbitTokensProvider);
    ref.invalidate(screenerDevicePricesProvider(_code));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(screenerTickerProvider(_code));
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: Text(_code)),
      body: RefreshIndicator(
        onRefresh: () => ref
            .refresh(screenerTickerProvider(_code).future)
            .then<void>((_) {}, onError: (_) {}),
        child: switch (async) {
          AsyncData(:final value) => _content(value),
          AsyncError(:final error) => ScrollableFill(
            child: ScreenerErrorView(
              error: error,
              onRetry: () => ref.invalidate(screenerTickerProvider(_code)),
            ),
          ),
          _ => const LoadingListView(tiles: 3),
        },
      ),
    );
  }

  Widget _content(ScreenerTicker t) {
    final g = context.ghina;
    final history = t.history;
    final newest = history.isEmpty ? null : history.last.date;
    final start = newest == null ? null : _range.start(newest);
    // The server has no prices (not connected / error): read them from
    // Stockbit on this phone when a session is saved.
    final deviceAsync = t.prices.hasData
        ? null
        : ref.watch(screenerDevicePricesProvider(_code));
    final allPrices = t.prices.hasData
        ? t.prices.points
        : (deviceAsync?.value ?? const <PricePoint>[]);
    final holders = clampHolders(history, start);
    final prices = clampPrices(allPrices, start);
    final withPrices = prices.length >= 2;
    final hasLocalSession =
        ref.watch(stockbitTokensProvider).value?.isEmpty == false;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        32,
      ),
      children: [
        _header(t),
        const SizedBox(height: 16),
        _tiles(history),
        const SizedBox(height: 20),
        SectionHeader(
          title: withPrices ? 'Harga vs jumlah pemegang' : 'Jumlah pemegang',
          padding: const EdgeInsets.only(bottom: 8),
        ),
        ChunkySegmented<ChartRange>(
          height: 38,
          segments: [
            for (final r in ChartRange.values)
              ChunkySegment(value: r, label: r.label),
          ],
          value: _range,
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 12),
        ChunkyCard(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
          child: holders.length < 2
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Belum cukup laporan untuk digambar',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ),
                )
              : HoldersPriceChart(
                  holders: holders,
                  prices: withPrices ? prices : const [],
                ),
        ),
        if (!withPrices) ...[
          const SizedBox(height: 10),
          if (deviceAsync?.isLoading ?? false)
            const Skeleton(height: 48, radius: GhinaRadii.md)
          else
            _pricesNote(t.prices, hasLocalSession),
        ],
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Perubahan per laporan',
          padding: EdgeInsets.only(bottom: 8),
        ),
        ChunkyCard(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: ChangeBarsChart(history: holders),
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Riwayat laporan',
          padding: EdgeInsets.only(bottom: 8),
        ),
        ..._history(history),
        const SizedBox(height: 20),
        ChunkyButton(
          label: 'Buka di Stockbit',
          icon: Icons.open_in_new_rounded,
          variant: ChunkyButtonVariant.outline,
          uppercase: false,
          onPressed: () => openScreenerLink(context, stockbitSymbolUrl(_code)),
        ),
      ],
    );
  }

  Widget _header(ScreenerTicker t) {
    final g = context.ghina;
    final q = t.quote;
    final meta = <String>[
      if (q?.marketCap != null)
        'Kap. pasar ${screenerMarketCap(q!.marketCap!)}',
      if (q?.volume != null) 'Volume ${screenerMarketCap(q!.volume!)}',
    ];
    return ChunkyCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.ticker,
                  style: GhinaType.h1.copyWith(color: g.textPrimary),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta.join(' · '),
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                if (q?.fetchedAt != null)
                  Text(
                    'Harga ${screenerDateTime(q!.fetchedAt!)}',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
          PriceWithChange(
            price: q?.lastPrice,
            changePercent: q?.changePercent,
            large: true,
          ),
        ],
      ),
    );
  }

  Widget _tiles(List<ShareholderPoint> history) {
    const periods = [
      (3, '3 bulan'),
      (6, '6 bulan'),
      (12, '1 tahun'),
      (36, '3 tahun'),
    ];
    Widget tile((int, String) p) => Expanded(
      child: _ChangeTile(
        label: 'Pemegang · ${p.$2}',
        value: changeOver(history, p.$1),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            tile(periods[0]),
            const SizedBox(width: 10),
            tile(periods[1]),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile(periods[2]),
            const SizedBox(width: 10),
            tile(periods[3]),
          ],
        ),
      ],
    );
  }

  Widget _pricesNote(ScreenerPrices p, bool hasLocalSession) {
    final g = context.ghina;
    final needsConnect = !hasLocalSession;
    return Container(
      key: const ValueKey('prices-note'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: g.border),
      ),
      child: Row(
        children: [
          Icon(Icons.show_chart_rounded, color: g.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              needsConnect
                  ? (p.message ??
                        'Grafik harga muncul setelah Stockbit terhubung.')
                  : 'Grafik harga belum bisa dimuat dari Stockbit. Coba '
                        'lagi nanti.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            ),
          ),
          if (needsConnect)
            ChunkyButton(
              label: 'Hubungkan',
              size: ChunkyButtonSize.small,
              expand: false,
              variant: ChunkyButtonVariant.ghost,
              uppercase: false,
              onPressed: _connect,
            ),
        ],
      ),
    );
  }

  List<Widget> _history(List<ShareholderPoint> history) {
    final g = context.ghina;
    final primary = screenerPrimary(context);
    final desc = history.reversed.toList();
    return [
      for (var i = 0; i < desc.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            borderRadius: GhinaRadii.rLg,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Fmt.date(desc[i].date),
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                ),
                if (i + 1 < desc.length)
                  ..._step(desc[i], desc[i + 1], primary),
                const SizedBox(width: 12),
                Text(
                  screenerNum(desc[i].count),
                  style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _step(
    ShareholderPoint cur,
    ShareholderPoint prev,
    Color primary,
  ) {
    final g = context.ghina;
    final d = cur.count - prev.count;
    final pct = prev.count == 0 ? null : d / prev.count * 100;
    final down = d < 0;
    return [
      if (d != 0)
        Icon(
          down ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          size: 16,
          color: down ? primary : g.textMuted,
        ),
      Text(
        pct == null
            ? screenerSigned(d)
            : '${screenerSigned(d)} (${screenerPercent(pct)})',
        style: GhinaType.bodyS
            .w(800)
            .copyWith(color: down ? primary : g.textSecondary),
      ),
    ];
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = value;
    final down = v != null && v < 0;
    final color = v == null
        ? g.textMuted
        : (down ? screenerPrimary(context) : g.textPrimary);
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: GhinaRadii.rLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (v != null && v != 0)
                Icon(
                  down
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 18,
                  color: color,
                ),
              Flexible(
                child: Text(
                  v == null ? '–' : screenerPercent(v),
                  style: GhinaType.h3.w(900).copyWith(color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
