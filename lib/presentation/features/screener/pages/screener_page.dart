import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/screener_providers.dart';
import '../screener_format.dart';
import '../widgets/breadth_card.dart';
import '../widgets/screener_charts.dart';
import '../widgets/screener_common.dart';
import '../widgets/screener_row_tile.dart';
import '../widgets/stockbit_connect_sheet.dart';
import '../widgets/stockbit_status_card.dart';

/// Sort orders of the result list.
enum ScreenerSort {
  change('Perubahan'),
  streak('Beruntun'),
  ratio('Porsi turun'),
  price('Harga'),
  marketCap('Kap. pasar');

  const ScreenerSort(this.label);
  final String label;
}

/// [rows] filtered by a ticker [search] (case-insensitive) and sorted.
List<ScreenerRow> arrangeRows(
  List<ScreenerRow> rows,
  String search,
  ScreenerSort sort,
) {
  final q = search.trim().toUpperCase();
  final out = [
    for (final r in rows)
      if (q.isEmpty || r.ticker.toUpperCase().contains(q)) r,
  ];
  int nullsLast(double? a, double? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  out.sort((a, b) {
    final c = switch (sort) {
      ScreenerSort.change => a.changePercent.compareTo(b.changePercent),
      ScreenerSort.streak => b.declineStreak.compareTo(a.declineStreak),
      ScreenerSort.ratio => b.declineRatio.compareTo(a.declineRatio),
      ScreenerSort.price => nullsLast(a.price, b.price),
      ScreenerSort.marketCap => nullsLast(a.marketCap, b.marketCap),
    };
    return c != 0 ? c : a.ticker.compareTo(b.ticker);
  });
  return out;
}

enum _Sync { idle, running, done, failed }

/// Screener: emiten whose shareholder count keeps falling, plus the state of
/// the Stockbit data behind it (online-only, allowlisted accounts).
class ScreenerPage extends ConsumerStatefulWidget {
  const ScreenerPage({super.key});

  @override
  ConsumerState<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends ConsumerState<ScreenerPage> {
  ScreenerQuery _query = const ScreenerQuery();
  ScreenerSort _sort = ScreenerSort.change;
  final _search = TextEditingController();
  _Sync _sync = _Sync.idle;
  String? _syncMessage;
  bool _syncNeedsConnect = false;
  ScreenerProgress _progress = const ScreenerProgress(ScreenerPhase.starting);
  ScreenerCancel? _cancel;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(ScreenerQuery q) => setState(() => _query = q);

  Future<void> _refresh() async {
    ref.invalidate(screenerStatusProvider);
    ref.invalidate(screenerBreadthProvider);
    await ref
        .refresh(screenerResultProvider(_query).future)
        .then<void>((_) {}, onError: (_) {});
  }

  Future<void> _connect() async {
    await showStockbitConnectSheet(context);
    if (!mounted) return;
    ref.invalidate(stockbitTokensProvider);
  }

  Future<void> _runSync({bool full = false}) async {
    final cancel = ScreenerCancel();
    setState(() {
      _sync = _Sync.running;
      _syncMessage = null;
      _syncNeedsConnect = false;
      _progress = const ScreenerProgress(ScreenerPhase.starting);
      _cancel = cancel;
    });
    try {
      final s = await ref
          .read(screenerSyncProvider)
          .run(
            full: full,
            cancel: cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _sync = _Sync.done;
        _syncMessage = syncSummaryText(s);
      });
    } on StockbitException catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.failed;
        _syncMessage = e.message;
        _syncNeedsConnect =
            e.kind == StockbitErrorKind.tokenRejected ||
            e.kind == StockbitErrorKind.notConnected;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.failed;
        _syncMessage = screenerErrorMessage(e);
      });
    } finally {
      _cancel = null;
      if (mounted) {
        // A renewal rewrites the tokens; the server data just changed.
        ref.invalidate(stockbitTokensProvider);
        ref.invalidate(screenerStatusProvider);
        ref.invalidate(screenerResultProvider);
        ref.invalidate(screenerBreadthProvider);
      }
    }
  }

  Future<void> _disconnect() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Putuskan Stockbit?',
      message:
          'Token Stockbit dihapus dari HP ini. Arsip laporan di Ghina tetap '
          'ada, tapi kamu perlu menghubungkan lagi untuk memperbarui data.',
      confirmLabel: 'Putuskan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(stockbitSessionServiceProvider).disconnect();
      ref.invalidate(stockbitTokensProvider);
      if (mounted) showOkToast(context, 'Stockbit diputuskan');
    } catch (e) {
      if (mounted) showErrorToast(context, screenerErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final status = ref.watch(screenerStatusProvider);
    final result = ref.watch(screenerResultProvider(_query));
    final now = ref.watch(clockProvider).now();
    final forbidden =
        isScreenerForbidden(status.error) || isScreenerForbidden(result.error);
    final tokens = ref.watch(stockbitTokensProvider).value;
    final connected = tokens != null && !tokens.isEmpty;

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Screener'),
        actions: [
          if (!forbidden && connected)
            PopupMenuButton<String>(
              key: const ValueKey('screener-menu'),
              tooltip: 'Menu',
              onSelected: (v) {
                if (v == 'full' && _sync != _Sync.running) {
                  _runSync(full: true);
                }
                if (v == 'disconnect') _disconnect();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'full',
                  child: Text('Periksa semua emiten'),
                ),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Putuskan Stockbit'),
                ),
              ],
            ),
        ],
      ),
      body: forbidden
          ? ScreenerErrorView(
              error: (isScreenerForbidden(status.error)
                  ? status.error
                  : result.error)!,
              onRetry: _refresh,
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _body(status, result, now),
            ),
    );
  }

  Widget _body(
    AsyncValue<ScreenerStatus> status,
    AsyncValue<ScreenerResult> result,
    DateTime now,
  ) {
    final rows = result.value == null
        ? const <ScreenerRow>[]
        : arrangeRows(result.value!.rows, _search.text, _sort);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            0,
          ),
          sliver: SliverList.list(
            children: [
              _statusArea(status, now),
              const SizedBox(height: 16),
              const BreadthCard(),
              const SizedBox(height: 16),
              _controls(),
              const SizedBox(height: 16),
              if (result.value != null) ..._summary(result.value!),
            ],
          ),
        ),
        ..._list(result, rows),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _statusArea(AsyncValue<ScreenerStatus> status, DateTime now) {
    final value = status.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value != null)
          StockbitStatusCard(
            status: value,
            tokens: ref.watch(stockbitTokensProvider).value,
            health: stockbitHealth(
              ref.watch(stockbitTokensProvider).value,
              now,
            ),
            now: now,
            running: _sync == _Sync.running,
            onSync: _runSync,
            onFullSync: () => _runSync(full: true),
            onConnect: _connect,
          )
        else if (status.hasError)
          ChunkyCard(
            child: ScreenerErrorView(
              error: status.error!,
              compact: true,
              onRetry: () => ref.invalidate(screenerStatusProvider),
            ),
          )
        else
          const Skeleton(height: 200, radius: GhinaRadii.xl),
        if (_sync != _Sync.idle) ...[const SizedBox(height: 12), _syncPanel()],
      ],
    );
  }

  Widget _syncPanel() {
    final g = context.ghina;
    final running = _sync == _Sync.running;
    final (swatch, icon) = switch (_sync) {
      _Sync.done => (GhinaColors.green, Icons.check_circle_rounded),
      _Sync.failed => (GhinaColors.orange, Icons.info_rounded),
      _ => (GhinaColors.blue, Icons.sync_rounded),
    };
    return ChunkyCard(
      key: const ValueKey('screener-sync-panel'),
      tinted: swatch,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: swatch.base),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  running ? _progress.text : (_syncMessage ?? ''),
                  key: const ValueKey('screener-sync-text'),
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
              ),
              if (!running)
                InkWell(
                  onTap: () => setState(() => _sync = _Sync.idle),
                  child: Icon(Icons.close_rounded, color: g.textSecondary),
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                key: const ValueKey('screener-sync-bar'),
                value: _progress.fraction,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            ChunkyButton(
              label: 'Batal',
              size: ChunkyButtonSize.small,
              expand: false,
              variant: ChunkyButtonVariant.outline,
              uppercase: false,
              onPressed: () => _cancel?.cancel(),
            ),
          ],
          if (_syncNeedsConnect) ...[
            const SizedBox(height: 10),
            ChunkyButton(
              label: 'Hubungkan',
              size: ChunkyButtonSize.small,
              expand: false,
              uppercase: false,
              onPressed: _connect,
            ),
          ],
        ],
      ),
    );
  }

  Widget _controls() {
    final g = context.ghina;
    final caption = GhinaType.caption.copyWith(color: g.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChunkySegmented<ScreenerMode>(
          height: 44,
          segments: [
            for (final m in ScreenerMode.values)
              ChunkySegment(value: m, label: m.label),
          ],
          value: _query.mode,
          onChanged: (m) => _setQuery(_query.copyWith(mode: m)),
        ),
        const SizedBox(height: 12),
        Text('Jendela', style: caption),
        const SizedBox(height: 6),
        ChunkyChoiceChips<int>(
          scrollable: true,
          options: [
            for (final m in const [3, 6, 12, 24])
              ChunkyChoice(value: m, label: '$m bulan'),
          ],
          selected: {_query.months},
          onChanged: (s) => _setQuery(_query.copyWith(months: s.first)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_query.mode == ScreenerMode.majority) ...[
              Expanded(
                child: _dropdown<double>(
                  label: 'Ambang turun',
                  value: _query.threshold,
                  items: const [0.5, 0.6, 0.7, 0.8, 0.9],
                  text: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => _setQuery(_query.copyWith(threshold: v)),
                  keyName: 'screener-threshold',
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _dropdown<int>(
                label: 'Min. laporan',
                value: _query.minPoints,
                items: const [2, 3, 4, 6],
                text: (v) => '$v laporan',
                onChanged: (v) => _setQuery(_query.copyWith(minPoints: v)),
                keyName: 'screener-minpoints',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) text,
    required ValueChanged<T> onChanged,
    required String keyName,
  }) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GhinaType.caption.copyWith(color: g.textSecondary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: g.surface,
            borderRadius: GhinaRadii.rMd,
            border: Border.all(color: g.border, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: ValueKey(keyName),
              isExpanded: true,
              value: value,
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              items: [
                for (final i in items)
                  DropdownMenuItem(value: i, child: Text(text(i))),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _summary(ScreenerResult r) {
    final g = context.ghina;
    final win = r.from != null && r.to != null
        ? '${Fmt.date(r.from!)} – ${Fmt.date(r.to!)}'
        : '${r.query.months} bulan';
    return [
      Row(
        children: [
          Expanded(
            child: StatTile(
              icon: Icons.check_circle_rounded,
              value: screenerNum(r.rows.length),
              label: 'Lolos',
              color: GhinaColors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.search_rounded,
              value: screenerNum(r.scanned),
              label: 'Dipindai',
              color: GhinaColors.blue,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      StatTile(
        icon: Icons.date_range_rounded,
        value: win,
        label: 'Jendela',
        color: GhinaColors.purple,
      ),
      if (r.rows.length >= 3) ...[
        const SizedBox(height: 16),
        ChunkyCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sebaran penurunan pemegang',
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
              Text(
                'Jumlah emiten per besar penurunan',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 12),
              DeclineHistogram(rows: r.rows),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: ChunkyTextField(
              controller: _search,
              hint: 'Cari kode emiten',
              prefixIcon: Icons.search_rounded,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<ScreenerSort>(
            key: const ValueKey('screener-sort'),
            tooltip: 'Urutkan',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in ScreenerSort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Urut: ${_sort.label}',
        style: GhinaType.caption.copyWith(color: g.textSecondary),
      ),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _list(
    AsyncValue<ScreenerResult> result,
    List<ScreenerRow> rows,
  ) {
    const pad = EdgeInsets.symmetric(horizontal: GhinaSpace.page);
    if (result.value == null) {
      if (result.hasError) {
        return [
          SliverToBoxAdapter(
            child: ScreenerErrorView(
              error: result.error!,
              onRetry: () => ref.invalidate(screenerResultProvider(_query)),
            ),
          ),
        ];
      }
      return const [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)),
        ),
      ];
    }
    if (rows.isEmpty) {
      final searching = _search.text.trim().isNotEmpty;
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            mood: MascotMood.sleeping,
            title: searching ? 'Kode nggak ketemu' : 'Belum ada yang lolos',
            message: searching
                ? 'Nggak ada emiten "${_search.text.trim().toUpperCase()}" di hasil ini.'
                : 'Coba longgarkan ambang, perpanjang jendela, atau kurangi '
                      'minimum laporan.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: pad,
        sliver: SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => ScreenerRowTile(
            row: rows[i],
            onTap: () => context.push(
              '/investments/screener/${Uri.encodeComponent(rows[i].ticker)}',
            ),
          ),
        ),
      ),
    ];
  }
}

/// One sentence about what an update did.
String syncSummaryText(ScreenerSyncSummary s) {
  final secs = s.duration.inSeconds;
  final parts = <String>[
    if (s.discovered.isNotEmpty) '${s.discovered.length} emiten baru',
    if (s.fetched == 0 && s.reportsWritten == 0)
      'laporan sudah paling baru'
    else
      '${screenerNum(s.reportsWritten)} laporan dikirim dari '
          '${screenerNum(s.fetched)} emiten',
    if (s.quotesWritten > 0) '${screenerNum(s.quotesWritten)} harga diperbarui',
    if (s.pricesTickers > 0)
      'riwayat harga ${screenerNum(s.pricesTickers)} emiten dilengkapi',
  ];
  final head = s.cancelled ? 'Dibatalkan' : 'Selesai';
  var text = '$head dalam $secs dtk: ${parts.join(', ')}.';
  if (s.rowsFutureDated > 0) {
    text +=
        ' (${screenerNum(s.rowsFutureDated)} baris bertanggal depan dilewati.)';
  }
  return text;
}
