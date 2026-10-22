import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/num_safe.dart';
import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/chart_empty.dart';
import '../payroll/kantor_payroll_tab.dart' show tok, usd, num_;
import '../widgets/kantor_states.dart';
import 'kantor_metrics_data.dart';

const _ranges = [
  ('today', 'Hari ini'),
  ('night', 'Semalam'),
  ('24h', '24 jam'),
  ('7d', '7 hari'),
];

/// Cycle metrics of one office (or all offices when [officeId] is `_kompleks`):
/// cards, DMs, sessions, cost, git and friction for a chosen range.
class KantorMetricsTab extends ConsumerStatefulWidget {
  const KantorMetricsTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorMetricsTab> createState() => _KantorMetricsTabState();
}

class _KantorMetricsTabState extends ConsumerState<KantorMetricsTab> {
  String _range = 'today';
  int _stuck = 3;
  bool _reporting = false;

  KantorMetricsQuery get _q =>
      KantorMetricsQuery(widget.officeId, range: _range, stuckHours: _stuck);

  Future<void> _report() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _reporting) return;
    setState(() => _reporting = true);
    try {
      final md = await fetchKantorShiftReport(api, _q);
      await Clipboard.setData(ClipboardData(text: md));
      if (!mounted) return;
      showToastBadge(
        context,
        message: 'Laporan shift disalin (markdown).',
        icon: Icons.check_circle_outline,
      );
    } on KantorException catch (e) {
      if (mounted) {
        showToastBadge(context, message: e.message, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(kantorMetricsProvider(_q));
    final global = widget.officeId == '_kompleks';
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(kantorMetricsProvider(_q).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          GhinaSpace.md,
          GhinaSpace.page,
          48,
        ),
        children: [
          if (global)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: Text(
                'Metrik kompleks',
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
          ChunkySegmented<String>(
            segments: [
              for (final r in _ranges) ChunkySegment(value: r.$1, label: r.$2),
            ],
            value: _range,
            onChanged: (v) => setState(() => _range = v),
          ),
          if (!global) ...[
            const SizedBox(height: GhinaSpace.sm),
            Row(
              children: [
                DropdownButton<int>(
                  value: _stuck,
                  items: [
                    for (final h in const [1, 2, 3, 6, 12])
                      DropdownMenuItem(
                        value: h,
                        child: Text('Macet setelah $h jam'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _stuck = v ?? 3),
                ),
                const Spacer(),
                ChunkyButton(
                  label: 'Laporan shift',
                  size: ChunkyButtonSize.small,
                  expand: false,
                  onPressed: _reporting ? null : _report,
                ),
              ],
            ),
          ],
          const SizedBox(height: GhinaSpace.md),
          ...async.when(
            loading: () => const [KantorLoading(count: 3)],
            error: (e, _) => [
              SizedBox(
                height: 240,
                child: KantorErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(kantorMetricsProvider(_q)),
                ),
              ),
            ],
            data: (d) => global ? _complex(d) : _office(d),
          ),
        ],
      ),
    );
  }

  /* ---------------- complex ---------------- */

  List<Widget> _complex(Map<String, dynamic> d) {
    final t = metricMap(d['total']);
    final g = context.ghina;
    String n(String k) => num_(metricNum(t[k]) ?? 0);
    return [
      _Kpis([
        _K(n('cardsDone'), 'Kartu selesai', '${n('cardsCreated')} dibuat'),
        _K(metricHours(t['cycleAvgH']), 'Siklus rata-rata'),
        _K(n('stuck'), 'Kartu macet', '', (metricNum(t['stuck']) ?? 0) > 0),
        _K(n('commits'), 'Commit', '${n('reverts')} revert'),
        _K(n('dm'), 'DM', '${n('dmWaiting')} menunggu'),
        _K(usd(metricNum(t['cost']) ?? 0), 'Biaya'),
        _K(
          metricDur(t['workSec']),
          'Waktu kerja',
          'idle ${metricDur(t['idleSec'])}',
        ),
        _K(n('toolErrors'), 'Tool gagal'),
      ]),
      const SizedBox(height: GhinaSpace.lg),
      const SectionHeader(title: 'Per kantor'),
      for (final o in metricRows(d['offices']))
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: ChunkyCard(
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o['name']}',
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                Text(
                  '${num_(metricNum(o['cardsDone']) ?? 0)} selesai · siklus ${metricHours(o['cycleAvgH'])} · ${num_(metricNum(o['stuck']) ?? 0)} macet · '
                  '${num_(metricNum(o['commits']) ?? 0)} commit · ${usd(metricNum(o['cost']) ?? 0)}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ),
      if (metricRows(d['offices']).isEmpty)
        const ChartEmpty(label: 'Tidak ada aktivitas di rentang ini'),
    ];
  }

  /* ---------------- one office ---------------- */

  List<Widget> _office(Map<String, dynamic> d) {
    final g = context.ghina;
    final cards = metricMap(d['cards']);
    final cycle = metricMap(cards['cycle']);
    final stuck = metricMap(cards['stuck']);
    final review = metricMap(cards['review']);
    final dm = metricMap(d['dm']);
    final sess = metricMap(d['sessions']);
    final totals = metricMap(sess['totals']);
    final perms = metricMap(sess['permissions']);
    final cost = metricMap(d['cost']);
    final git = metricMap(d['git']);
    final fr = metricMap(d['friction']);
    final series = metricMap(d['series']);
    final range = metricMap(d['range']);
    final bucket = '${range['bucket']}';
    final starts = [
      for (final s in (series['starts'] as List? ?? const [])) '$s',
    ];
    List<double> vals(String k) => [
      for (final v in (series[k] as List? ?? const [])) metricNum(v) ?? 0,
    ];
    String n(Object? v) => num_(metricNum(v) ?? 0);
    final unit = bucket == 'hour' ? 'jam' : 'hari';

    return [
      SectionHeader(title: 'Kartu', subtitle: '${range['label'] ?? ''}'),
      _Kpis([
        _K(n(cards['done']), 'Kartu selesai', '${n(cards['created'])} dibuat'),
        _K(
          metricHours(cycle['avgH']),
          'Siklus rata-rata',
          'median ${metricHours(cycle['medianH'])} · p90 ${metricHours(cycle['p90H'])}',
        ),
        _K(
          n(stuck['count']),
          'Macet > ${n(stuck['hours'])} jam',
          '',
          (metricNum(stuck['count']) ?? 0) > 0,
        ),
        _K(
          n(review['bounces']),
          'Bolak-balik Review',
          '${n(review['bouncedCards'])} kartu',
        ),
      ]),
      const SizedBox(height: GhinaSpace.md),
      _ChartCard(
        title: 'Kartu selesai per $unit',
        child: MetricBars(
          starts: starts,
          values: vals('done'),
          hourly: bucket == 'hour',
          color: GhinaColors.green.base,
        ),
      ),
      for (final c in metricRows(stuck['cards']))
        Padding(
          padding: const EdgeInsets.only(top: GhinaSpace.sm),
          child: ChunkyCard(
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
                Text(
                  '${c['col']} · ${c['who'] ?? '-'} · diam ${metricHours(c['hours'])}${(c['blocked'] ?? '') != '' ? ' · terblokir' : ''}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: GhinaSpace.xl),
      const SectionHeader(
        title: 'Pesan langsung',
        subtitle: 'DM dibuat sampai diketik ke sesi',
      ),
      _Kpis([
        _K(
          n(dm['total']),
          'DM',
          '${n(dm['pesan'])} pesan · ${n(dm['balasan'])} balasan',
        ),
        _K(
          metricDur(metricMap(dm['deliver'])['avgSec']),
          'Kirim sampai terlihat',
          'p90 ${metricDur(metricMap(dm['deliver'])['p90Sec'])} · maks ${metricDur(metricMap(dm['deliver'])['maxSec'])}',
        ),
        _K(
          metricDur(metricMap(dm['reply'])['avgSec']),
          'Sampai dibalas',
          'p90 ${metricDur(metricMap(dm['reply'])['p90Sec'])}',
        ),
        _K(
          n(dm['slow5']),
          'DM antre > 5 mnt',
          '${n(dm['slow1'])} lewat 1 mnt',
          (metricNum(dm['slow5']) ?? 0) > 0,
        ),
        _K(n(dm['askTimeout']), 'Tanya timeout'),
        _K(
          n(metricMap(dm['waitingNow'])['count']),
          'Menunggu sekarang',
          '',
          (metricNum(metricMap(dm['waitingNow'])['count']) ?? 0) > 0,
        ),
      ]),
      const SizedBox(height: GhinaSpace.md),
      _BarList(
        rows: [
          for (final p in metricRows(dm['perRole']))
            _BarRow(
              '${p['name']}',
              metricNum(metricMap(p['deliver'])['avgSec']) ?? 0,
              '${metricDur(metricMap(p['deliver'])['avgSec'])} · maks ${metricDur(metricMap(p['deliver'])['maxSec'])} · ${n(p['n'])} DM',
              GhinaColors.blue,
            ),
        ],
        empty: 'Belum ada DM di rentang ini.',
      ),
      const SizedBox(height: GhinaSpace.xl),
      const SectionHeader(
        title: 'Sesi',
        subtitle: 'perkiraan dari jejak aktivitas',
      ),
      _Kpis([
        _K(metricDur(totals['workSec']), 'Bekerja'),
        _K(metricDur(totals['idleSec']), 'Idle'),
        _K(metricDur(totals['waitSec']), 'Menunggu izin'),
        _K(
          n(sess['compactions']),
          'Kompaksi',
          '${n(sess['interrupts'])} interrupt',
        ),
        _K(
          n(perms['toTerminal']),
          'Izin jatuh ke terminal',
          'dari ${n(perms['total'])} izin',
          (metricNum(perms['toTerminal']) ?? 0) > 0,
        ),
      ]),
      const SizedBox(height: GhinaSpace.md),
      for (final p in metricRows(sess['perRole']))
        Padding(
          padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
          child: _WorkBar(row: p),
        ),
      const SizedBox(height: GhinaSpace.xl),
      SectionHeader(
        title: 'Biaya',
        subtitle: 'per hari penuh, estimasi setara API',
      ),
      _Kpis([
        _K(usd(metricNum(cost['total']) ?? 0), 'Biaya'),
        _K(
          metricNum(cost['perDoneCard']) == null
              ? '-'
              : usd(metricNum(cost['perDoneCard'])!),
          'Per kartu selesai',
        ),
        _K(
          metricNum(cost['perCommit']) == null
              ? '-'
              : usd(metricNum(cost['perCommit'])!),
          'Per commit',
        ),
        if ((metricNum(cost['tokenOnlyTokens']) ?? 0) > 0)
          _K(
            tok(metricNum(cost['tokenOnlyTokens'])!),
            'Token Codex',
            'tanpa harga',
          ),
      ]),
      const SizedBox(height: GhinaSpace.md),
      _BarList(
        rows: [
          for (final p in metricRows(cost['perRole']))
            _BarRow(
              '${p['name']}',
              metricNum(p['cost']) ?? 0,
              (metricNum(p['tokenOnlyTokens']) ?? 0) > 0 &&
                      (metricNum(p['cost']) ?? 0) == 0
                  ? '${tok(metricNum(p['tokenOnlyTokens'])!)} token'
                  : usd(metricNum(p['cost']) ?? 0),
              GhinaColors.green,
            ),
        ],
        empty: 'Belum ada pemakaian.',
      ),
      const SizedBox(height: GhinaSpace.xl),
      const SectionHeader(title: 'Git'),
      _Kpis([
        _K(n(git['total']), 'Commit'),
        _K(
          n(git['reverts']),
          'Revert',
          '',
          (metricNum(git['reverts']) ?? 0) > 0,
        ),
      ]),
      const SizedBox(height: GhinaSpace.md),
      _ChartCard(
        title: 'Commit per $unit',
        child: MetricBars(
          starts: starts,
          values: vals('commits'),
          hourly: bucket == 'hour',
          color: GhinaColors.blue.base,
        ),
      ),
      const SizedBox(height: GhinaSpace.xl),
      const SectionHeader(title: 'Gesekan'),
      _Kpis([
        _K(n(metricMap(fr['toolErrors'])['total']), 'Tool gagal'),
        _K(n(fr['announcements']), 'Pengumuman'),
      ]),
      const SizedBox(height: GhinaSpace.md),
      _BarList(
        rows: [
          for (final e in metricRows(metricMap(fr['toolErrors'])['byTool']))
            _BarRow('${e['tool']}', metricNum(e['n']) ?? 0, () {
              final r = metricRows(e['reasons']);
              return r.isEmpty
                  ? '${n(e['n'])}x · alasan tidak tercatat'
                  : '${n(e['n'])}x · ${r.first['text']}';
            }(), GhinaColors.orange),
        ],
        empty: 'Tidak ada tool yang gagal.',
      ),
    ];
  }
}

class _K {
  const _K(this.value, this.label, [this.hint = '', this.warn = false]);
  final String value;
  final String label;
  final String hint;
  final bool warn;
}

class _Kpis extends StatelessWidget {
  const _Kpis(this.items);
  final List<_K> items;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: GhinaSpace.md,
      crossAxisSpacing: GhinaSpace.md,
      childAspectRatio: 1.7,
      children: [
        for (final k in items)
          ChunkyCard(
            tinted: k.warn ? GhinaColors.orange : null,
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    k.value,
                    style: GhinaType.moneyL.copyWith(color: g.textPrimary),
                  ),
                ),
                Text(
                  k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.w(800).copyWith(color: g.textMuted),
                ),
                if (k.hint.isNotEmpty)
                  Text(
                    k.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ChunkyCard(
    padding: const EdgeInsets.all(GhinaSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GhinaType.bodyS
              .w(800)
              .copyWith(color: context.ghina.textPrimary),
        ),
        const SizedBox(height: GhinaSpace.sm),
        child,
      ],
    ),
  );
}

class _BarRow {
  const _BarRow(this.label, this.value, this.text, this.color);
  final String label;
  final double value;
  final String text;
  final ChunkySwatch color;
}

/// Name, a proportional bar and a caption per row.
class _BarList extends StatelessWidget {
  const _BarList({required this.rows, required this.empty});
  final List<_BarRow> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return ChartEmpty(label: empty);
    final g = context.ghina;
    final max = rows.fold<double>(
      0,
      (a, r) => math.max(a, nonNegative(r.value)),
    );
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.label,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  ChunkyProgressBar(
                    value: max > 0
                        ? (nonNegative(r.value) / max).clamp(0, 1).toDouble()
                        : 0,
                    color: r.color,
                    height: 10,
                    animate: false,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.text,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Work / permission wait / idle share of one role's session time.
class _WorkBar extends StatelessWidget {
  const _WorkBar({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final w = nonNegative(metricNum(row['workSec']) ?? 0);
    final p = nonNegative(metricNum(row['waitSec']) ?? 0);
    final i = nonNegative(metricNum(row['idleSec']) ?? 0);
    final total = w + p + i;
    int fl(double v) => total > 0 ? math.max(0, (v / total * 1000).round()) : 0;
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row['name']}',
            style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: total <= 0
                  ? ColoredBox(color: g.border)
                  : Row(
                      children: [
                        if (fl(w) > 0)
                          Expanded(
                            flex: fl(w),
                            child: ColoredBox(color: GhinaColors.green.base),
                          ),
                        if (fl(p) > 0)
                          Expanded(
                            flex: fl(p),
                            child: ColoredBox(color: GhinaColors.orange.base),
                          ),
                        if (fl(i) > 0)
                          Expanded(
                            flex: fl(i),
                            child: ColoredBox(color: g.border),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'kerja ${metricDur(row['workSec'])} · izin ${metricDur(row['waitSec'])} · idle ${metricDur(row['idleSec'])} · '
            'kompaksi ${row['compactions'] ?? 0} · interrupt ${row['interrupts'] ?? 0}',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Bars per hour or day; every value is guarded so a bad series cannot break paint.
class MetricBars extends StatelessWidget {
  const MetricBars({
    super.key,
    required this.starts,
    required this.values,
    required this.hourly,
    required this.color,
  });

  final List<String> starts;
  final List<double> values;
  final bool hourly;
  final Color color;

  static double _niceMax(double v) {
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = v / p;
    return (n <= 1
            ? 1
            : n <= 2
            ? 2
            : n <= 5
            ? 5
            : 10) *
        p;
  }

  String _label(int i) {
    final d = DateTime.tryParse(starts[i])?.toLocal();
    if (d == null) return '';
    return hourly
        ? '${d.hour.toString().padLeft(2, '0')}.00'
        : '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final n = math.min(starts.length, values.length);
    if (n == 0 || !values.take(n).any((v) => v.isFinite && v > 0)) {
      return const ChartEmpty(label: 'Belum ada data di rentang ini');
    }
    final top = safeInterval(
      _niceMax(
        values.take(n).fold<double>(1, (a, v) => math.max(a, nonNegative(v))),
      ),
    );
    final step = math.max(1, (n / 6).ceil());
    return SizedBox(
      height: 160,
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
                reservedSize: 30,
                interval: safeInterval(top / 2),
                getTitlesWidget: (v, meta) => Text(
                  num_(v.round()),
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
                  if (i < 0 || i >= n || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _label(i),
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${_label(group.x)}\n${num_(values[group.x].round())}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: nonNegative(values[i]),
                    width: math.max(3, math.min(14, 280 / n)),
                    color: color,
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
