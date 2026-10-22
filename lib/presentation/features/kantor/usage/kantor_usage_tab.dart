import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/num_safe.dart';
import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/chart_empty.dart';
import '../payroll/kantor_payroll_tab.dart' show tok, usd, num_;
import '../widgets/kantor_states.dart';
import 'kantor_limits_card.dart';
import 'kantor_usage_data.dart';

/// Usage and statistics, for one office or (`_kompleks`) everything.
final kantorUsageSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (String, String)>((ref, key) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      final d = await api.get(
        '/api/usage/summary',
        query: {'range': key.$2, if (key.$1 != '_kompleks') 'office': key.$1},
      );
      if (d is! Map) {
        throw const KantorException(
          KantorFailure.server,
          'Jawaban statistik pemakaian tidak dikenali.',
        );
      }
      return Map<String, dynamic>.from(d);
    });

const _ranges = [('today', 'Hari ini'), ('7d', '7 hari'), ('30d', '30 hari')];

double _n(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;
List<Map> _list(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) x,
];

/// "1j 20m" / "45m" for a number of seconds.
String durText(num s) {
  final m = (s.isFinite ? s : 0) ~/ 60;
  if (m >= 60) return '${m ~/ 60}j ${m % 60}m';
  return '${m}m';
}

class KantorUsageTab extends ConsumerStatefulWidget {
  const KantorUsageTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorUsageTab> createState() => _KantorUsageTabState();
}

class _KantorUsageTabState extends ConsumerState<KantorUsageTab> {
  String _range = '7d';
  bool _cost = false;

  bool get _global => widget.officeId == '_kompleks';

  Future<void> _refresh() async {
    ref.invalidate(kantorUsageLimitsProvider);
    ref.invalidate(kantorUsageSummaryProvider);
    await ref.read(
      kantorUsageSummaryProvider((widget.officeId, _range)).future,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(
      kantorUsageSummaryProvider((widget.officeId, _range)),
    );
    final d = async.value;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          GhinaSpace.md,
          GhinaSpace.page,
          48,
        ),
        children: [
          if (_global)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: Text(
                'Pemakaian kompleks',
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
          const KantorLimitsCard(),
          const SizedBox(height: GhinaSpace.md),
          Wrap(
            spacing: GhinaSpace.sm,
            children: [
              for (final r in _ranges)
                ChoiceChip(
                  label: Text(r.$2),
                  selected: _range == r.$1,
                  onSelected: (_) => setState(() => _range = r.$1),
                ),
            ],
          ),
          const SizedBox(height: GhinaSpace.md),
          if (d == null && async.isLoading && !async.hasError)
            const KantorLoading()
          else if (d == null)
            KantorErrorView(
              error: async.error ?? 'Gagal memuat.',
              onRetry: _refresh,
            )
          else
            ..._body(d),
        ],
      ),
    );
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final g = context.ghina;
    final t = (d['totals'] as Map?) ?? const {};
    final avg = (d['avgPerSession'] as Map?) ?? const {};
    final work = (d['work'] as Map?) ?? const {};
    final eng = (d['engines'] as Map?) ?? const {};
    final days = _list(d['daily']);
    final tokens = _n(t['tokens']);
    final hasData = tokens > 0 || _n(t['sessions']) > 0;
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: GhinaSpace.md,
        crossAxisSpacing: GhinaSpace.md,
        childAspectRatio: 1.9,
        children: [
          _Kpi(tok(tokens), 'Total token'),
          _Kpi(usd(_n(t['cost'])), 'Biaya setara API (Claude)'),
          _Kpi(num_(_n(t['sessions'])), 'Sesi'),
          _Kpi(tok(_n(avg['tokens'])), 'Rata-rata token per sesi'),
          _Kpi(durText(_n(work['seconds'])), 'Durasi sesi'),
          _Kpi(durText(_n(work['avgSeconds'])), 'Rata-rata durasi sesi'),
        ],
      ),
      const SizedBox(height: GhinaSpace.md),
      ChunkyCard(
        padding: const EdgeInsets.all(GhinaSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rincian token',
              style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Masuk ${tok(_n(t['input']))} · Keluar ${tok(_n(t['output']))} · Cache tulis ${tok(_n(t['cacheW']))} · Cache baca ${tok(_n(t['cacheR']))}',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Claude ${tok(_n((eng['claude'] as Map?)?['tokens']))} · Codex ${tok(_n((eng['codex'] as Map?)?['tokens']))} (Codex hanya token, tanpa biaya)',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      ),
      const SizedBox(height: GhinaSpace.xl),
      SectionHeader(
        title: 'Harian',
        trailing: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Token')),
            ButtonSegment(value: true, label: Text('Biaya')),
          ],
          selected: {_cost},
          onSelectionChanged: (s) => setState(() => _cost = s.first),
        ),
      ),
      _DayChart(days: days, cost: _cost),
      if (!hasData)
        const Padding(
          padding: EdgeInsets.only(top: GhinaSpace.md),
          child: ChartEmpty(label: 'Belum ada pemakaian di rentang ini.'),
        )
      else ...[
        if (_global && _list(d['byOffice']).isNotEmpty) ...[
          const SizedBox(height: GhinaSpace.xl),
          const SectionHeader(title: 'Per kantor'),
          ..._rows(_list(d['byOffice']), tokens),
        ],
        const SizedBox(height: GhinaSpace.xl),
        const SectionHeader(title: 'Per peran'),
        ..._rows(_list(d['byRole']), tokens, withOffice: _global),
        const SizedBox(height: GhinaSpace.xl),
        const SectionHeader(title: 'Per model'),
        ..._rows(_list(d['byModel']), tokens, nameKey: 'label'),
        const SizedBox(height: GhinaSpace.xl),
        const SectionHeader(title: 'Per mesin'),
        ..._rows(_list(d['byMachine']), tokens),
        const SizedBox(height: GhinaSpace.xl),
        const SectionHeader(title: 'Sesi terboros'),
        ..._sessions(_list(d['topSessions'])),
      ],
      const SizedBox(height: GhinaSpace.xl),
      Text(
        '${d['costNote'] ?? ''} Jumlah tool call dan baris yang diedit belum dicatat.',
        style: GhinaType.caption.copyWith(color: g.textMuted),
      ),
    ];
  }

  List<Widget> _rows(
    List<Map> rows,
    double total, {
    String nameKey = 'name',
    bool withOffice = false,
  }) {
    if (rows.isEmpty) return [const ChartEmpty(height: 48)];
    return [
      for (final r in rows)
        ChunkyTile(
          title: '${r[nameKey] ?? r['name'] ?? '-'}',
          subtitle:
              '${total > 0 ? (_n(r['tokens']) / total * 100).toStringAsFixed(0) : 0}% · ${num_(_n(r['sessions']))} sesi · keluar ${tok(_n(r['output']))}${withOffice && r['officeName'] != null ? ' · ${r['officeName']}' : ''}',
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tok(_n(r['tokens'])),
                style: GhinaType.moneyS.copyWith(
                  color: context.ghina.textPrimary,
                ),
              ),
              if (_n(r['cost']) > 0)
                Text(
                  usd(_n(r['cost'])),
                  style: GhinaType.caption.copyWith(
                    color: context.ghina.textMuted,
                  ),
                ),
            ],
          ),
          dense: true,
        ),
    ];
  }

  List<Widget> _sessions(List<Map> rows) {
    if (rows.isEmpty) return [const ChartEmpty(height: 48)];
    return [
      for (final s in rows)
        ChunkyTile(
          title: '${s['title'] ?? s['roleName'] ?? 'Sesi tanpa judul'}',
          subtitle:
              '${s['roleName'] ?? ''}${s['officeName'] != null ? ' · ${s['officeName']}' : ''} · ${s['engine'] == 'codex' ? 'Codex' : 'Claude'} · ${num_(_n(s['days']))} hari',
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tok(_n(s['tokens'])),
                style: GhinaType.moneyS.copyWith(
                  color: context.ghina.textPrimary,
                ),
              ),
              if (_n(s['cost']) > 0)
                Text(
                  usd(_n(s['cost'])),
                  style: GhinaType.caption.copyWith(
                    color: context.ghina.textMuted,
                  ),
                ),
            ],
          ),
          dense: true,
        ),
    ];
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GhinaType.moneyL.copyWith(color: g.textPrimary),
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Daily bars of tokens or API-equivalent cost; empty and NaN safe.
class _DayChart extends StatelessWidget {
  const _DayChart({required this.days, required this.cost});

  final List<Map> days;
  final bool cost;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final vals = [
      for (final d in days) nonNegative(_n(cost ? d['cost'] : d['tokens'])),
    ];
    final max = vals.fold<double>(0, (a, v) => v > a ? v : a);
    if (vals.isEmpty || max <= 0) {
      return const ChartEmpty(label: 'Belum ada pemakaian.', height: 160);
    }
    final top = safeInterval(max * 1.15);
    String axis(double v) => cost ? usd(v, v < 10 ? 2 : 0) : tok(v);
    final step = vals.length <= 7 ? 1 : 5;
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: safeInterval(top / 2),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: g.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: safeInterval(top / 2),
                getTitlesWidget: (v, meta) => Text(
                  axis(v),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 ||
                      i >= days.length ||
                      !(i % step == 0 || i == days.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  final day = '${days[i]['day']}';
                  if (day.length < 10) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${day.substring(8)}/${day.substring(5, 7)}',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${days[group.x]['day']}\n${axis(rod.toY)}',
                GhinaType.caption.copyWith(color: Colors.white),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < vals.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: vals[i],
                    width: vals.length <= 7 ? 18 : 6,
                    color: GhinaColors.green.base,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
