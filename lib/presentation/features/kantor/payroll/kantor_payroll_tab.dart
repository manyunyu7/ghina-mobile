import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_sprite.dart';
import '../widgets/kantor_states.dart';

final _usd2 = NumberFormat('#,##0.00', 'en_US');
final _usd0 = NumberFormat('#,##0', 'en_US');
final _int = NumberFormat('#,##0', 'id_ID');

String usd(num v, [int d = 2]) => '\$${(d == 0 ? _usd0 : _usd2).format(v)}';
String num_(num v) => _int.format(v);

/// 1.2K / 3.4M / 5.6B
String tok(num v) {
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return '${v.round()}';
}

/// Monthly cost (estimated at API prices) of one office, or of all offices
/// when [officeId] is `_kompleks`.
class KantorPayrollTab extends ConsumerStatefulWidget {
  const KantorPayrollTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorPayrollTab> createState() => _KantorPayrollTabState();
}

class _KantorPayrollTabState extends ConsumerState<KantorPayrollTab> {
  Map<String, dynamic>? _d;
  Map<String, Map<String, dynamic>> _roles = const {};
  Map<String, String> _officeNames = const {};
  String _month = '';
  Object? _error;
  bool _loading = true;
  Timer? _poll;
  Timer? _debounce;

  bool get _global => widget.officeId == '_kompleks';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KantorPayrollTab old) {
    super.didUpdateWidget(old);
    if (old.officeId != widget.officeId) {
      _month = '';
      _d = null;
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final d = await api.get(
        '/api/payroll',
        query: {
          if (!_global) 'office': widget.officeId,
          if (_month.isNotEmpty) 'month': _month,
        },
      );
      if (d is! Map)
        throw const KantorException(
          KantorFailure.server,
          'Jawaban payroll tidak dikenali.',
        );
      if (_roles.isEmpty && !_global) {
        try {
          final r = await api.get(
            '/api/offices/${Uri.encodeComponent(widget.officeId)}/roles',
          );
          _roles = {
            for (final x in (r as List? ?? const []))
              if (x is Map) '${x['id']}': Map<String, dynamic>.from(x),
          };
        } catch (_) {}
      }
      if (_global && _officeNames.isEmpty) {
        try {
          final s = await api.get('/api/state');
          _officeNames = {
            for (final o in ((s as Map)['offices'] as List? ?? const []))
              if (o is Map) '${o['id']}': '${o['name']}',
          };
        } catch (_) {}
      }
      if (!mounted) return;
      final m = Map<String, dynamic>.from(d);
      setState(() {
        _d = m;
        if (_month.isEmpty) _month = '${m['month']}';
        _error = null;
        _loading = false;
      });
      _poll?.cancel();
      if ((m['scan'] as Map?)?['running'] == true) {
        _poll = Timer(const Duration(seconds: 2), () => _load(quiet: true));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String m, {bool bad = true}) => showToastBadge(
    context,
    message: m,
    icon: bad ? Icons.error_outline : Icons.check_circle_outline,
  );

  Future<void> _rescan() async {
    try {
      await ref.read(kantorApiProvider)!.post('/api/payroll/rescan');
      _toast('Pemindaian dimulai.', bad: false);
      await _load(quiet: true);
    } on KantorException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _budget() async {
    final cur = (_d?['budget'] as num?) ?? 0;
    final ctl = TextEditingController(text: cur > 0 ? '$cur' : '');
    final v = await showChunkyBottomSheet<double>(
      context,
      title: 'Atur budget bulanan',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batas biaya per bulan untuk kantor ini, dalam dolar (estimasi setara API). Isi 0 untuk menghapus batas.',
            style: GhinaType.bodyS.copyWith(color: context.ghina.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.md),
          ChunkyTextField(
            label: 'Budget (USD)',
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: 'Simpan',
            onPressed: () {
              final raw = ctl.text.trim().replaceAll(',', '.');
              final n = double.tryParse(raw.isEmpty ? '0' : raw);
              if (n == null || n < 0) {
                _toast('Isi angka yang valid.');
                return;
              }
              Navigator.pop(c, n);
            },
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v == null) return;
    try {
      await ref.read(kantorApiProvider)!.post(
        '/api/offices/${Uri.encodeComponent(widget.officeId)}/budget',
        {'usd': v},
      );
      _toast('Budget disimpan.', bad: false);
      await _load(quiet: true);
    } on KantorException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m == null || m['t'] != 'changed' || m['what'] != 'payroll') return;
      if (m['office'] != '*' && m['office'] != widget.officeId && !_global)
        return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _load(quiet: true);
      });
    });
    if (_loading && _d == null) return const KantorLoading();
    if (_error != null && _d == null)
      return KantorErrorView(error: _error!, onRetry: _load);
    final d = _d!;
    final g = context.ghina;
    final t = Map<String, dynamic>.from(d['total'] as Map);
    final byDay = [
      for (final x in (d['byDay'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    final activeDays = byDay.where((x) => (x['cost'] as num) > 0).length;
    final dayTotal = byDay.fold<double>(0, (a, x) => a + (x['cost'] as num));
    final budget = (d['budget'] as num?)?.toDouble();
    final cost = (t['cost'] as num).toDouble();
    final pct = budget != null && budget > 0 ? cost / budget * 100 : 0.0;
    final months = [for (final m in (d['months'] as List? ?? const [])) '$m'];
    final scan = d['scan'] as Map?;
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      child: ListView(
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
                'Payroll kompleks',
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
          ChunkyCard(
            tinted: GhinaColors.blue,
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Text(
              'Biaya di sini adalah estimasi setara harga API, dihitung dari transcript Claude Code di Mac kantor. Ini bukan tagihan langganan.',
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
            ),
          ),
          const SizedBox(height: GhinaSpace.md),
          Row(
            children: [
              if (months.isNotEmpty)
                DropdownButton<String>(
                  value: months.contains(_month) ? _month : months.first,
                  items: [
                    for (final m in months)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _month = v);
                    _load(quiet: true);
                  },
                ),
              const SizedBox(width: GhinaSpace.sm),
              ChunkyButton(
                label: 'Pindai ulang',
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.outline,
                expand: false,
                onPressed: scan?['running'] == true ? null : _rescan,
              ),
            ],
          ),
          if (scan != null)
            Padding(
              padding: const EdgeInsets.only(top: GhinaSpace.xs),
              child: Text(
                _scanText(scan),
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
          const SizedBox(height: GhinaSpace.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: GhinaSpace.md,
            crossAxisSpacing: GhinaSpace.md,
            childAspectRatio: 1.9,
            children: [
              _Kpi(usd(cost), 'Biaya bulan ini'),
              _Kpi(num_(t['sessions'] as num), 'Sesi'),
              _Kpi(tok(t['output'] as num), 'Token keluaran'),
              _Kpi(
                usd(activeDays > 0 ? dayTotal / activeDays : 0),
                'Rata-rata per hari aktif (30 hari)',
              ),
            ],
          ),
          if (!_global) ...[
            const SizedBox(height: GhinaSpace.md),
            ChunkyCard(
              padding: const EdgeInsets.all(GhinaSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    budget != null && budget > 0
                        ? usd(budget, 0)
                        : 'Belum diatur',
                    style: GhinaType.moneyL.copyWith(color: g.textPrimary),
                  ),
                  Text(
                    'Budget bulan ini',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                  if (budget != null && budget > 0) ...[
                    const SizedBox(height: GhinaSpace.sm),
                    ChunkyProgressBar.budget(
                      used: (pct / 100).clamp(0, 1).toDouble(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pct.toStringAsFixed(0)}% terpakai',
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                  const SizedBox(height: GhinaSpace.sm),
                  ChunkyButton(
                    label: 'Atur budget',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    expand: false,
                    onPressed: _budget,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: GhinaSpace.xl),
          const SectionHeader(title: 'Biaya harian, 30 hari terakhir'),
          _DayChart(days: byDay),
          const SizedBox(height: GhinaSpace.xl),
          const SectionHeader(title: 'Slip gaji'),
          ..._slips(d, cost),
          const SizedBox(height: GhinaSpace.xl),
          const SectionHeader(title: 'Per model'),
          ..._models(d, cost),
          if (_global) ...[
            const SizedBox(height: GhinaSpace.xl),
            const SectionHeader(title: 'Per kantor'),
            ..._offices(d),
          ],
          const SizedBox(height: GhinaSpace.xl),
          const SectionHeader(title: 'Sesi termahal'),
          ..._sessions(d),
        ],
      ),
    );
  }

  String _scanText(Map s) {
    if (s['running'] == true)
      return 'Memindai ${num_((s['done'] as num?) ?? 0)} dari ${num_((s['files'] as num?) ?? 0)} berkas…';
    if (s['error'] != null) return 'Pemindaian gagal: ${s['error']}';
    final t = DateTime.tryParse('${s['lastRun'] ?? ''}')?.toLocal();
    if (t == null) return '';
    return 'Dipindai ${DateFormat('d MMM HH:mm', 'en_US').format(t)} · ${num_((s['files'] as num?) ?? 0)} berkas';
  }

  List<Widget> _slips(Map d, double total) {
    final rows = [
      for (final r in (d['byRole'] as List? ?? const []))
        if (r is Map) r,
    ];
    if (rows.isEmpty) return [const Text('Belum ada pemakaian bulan ini.')];
    final g = context.ghina;
    return [
      for (final r in rows)
        Builder(
          builder: (_) {
            final id = r['role'] as String?;
            final role = id == null ? null : _roles[id];
            final name = id == null
                ? 'Sesi manual'
                : (role?['name'] as String? ?? id);
            final p = total > 0 ? (r['cost'] as num) / total * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: ChunkyCard(
                padding: const EdgeInsets.all(GhinaSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        KantorSprite(
                          look: role ?? KantorSprite.guestLook(id ?? 'manual'),
                          size: 40,
                        ),
                        const SizedBox(width: GhinaSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GhinaType.body
                                    .w(800)
                                    .copyWith(color: g.textPrimary),
                              ),
                              Text(
                                role?['title'] as String? ??
                                    (id == null ? 'Tidak terikat role' : ''),
                                style: GhinaType.caption.copyWith(
                                  color: g.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          usd(r['cost'] as num),
                          style: GhinaType.moneyM.copyWith(
                            color: g.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: GhinaSpace.sm),
                    ChunkyProgressBar(value: (p / 100).clamp(0, 1).toDouble()),
                    const SizedBox(height: 4),
                    Text(
                      '${p.toStringAsFixed(0)}% dari total · ${num_(r['sessions'] as num)} sesi · ${tok(r['output'] as num)} token keluaran',
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _models(Map d, double total) {
    final rows = [
      for (final r in (d['byModel'] as List? ?? const []))
        if (r is Map) r,
    ];
    if (rows.isEmpty) return [const Text('Belum ada data.')];
    return [
      for (final m in rows)
        ChunkyTile(
          title: '${m['label'] ?? m['model']}',
          subtitle:
              '${tok(m['output'] as num)} token keluaran · ${total > 0 ? ((m['cost'] as num) / total * 100).toStringAsFixed(0) : 0}%',
          trailing: Text(
            usd(m['cost'] as num),
            style: GhinaType.moneyS.copyWith(color: context.ghina.textPrimary),
          ),
          dense: true,
        ),
    ];
  }

  List<Widget> _offices(Map d) {
    final rows = [
      for (final r in (d['byOffice'] as List? ?? const []))
        if (r is Map) r,
    ];
    if (rows.isEmpty) return [const Text('Belum ada data.')];
    return [
      for (final o in rows)
        ChunkyTile(
          title: _officeNames['${o['office']}'] ?? '${o['office']}',
          subtitle: '${num_(o['sessions'] as num)} sesi',
          trailing: Text(
            usd(o['cost'] as num),
            style: GhinaType.moneyS.copyWith(color: context.ghina.textPrimary),
          ),
          dense: true,
        ),
    ];
  }

  List<Widget> _sessions(Map d) {
    final rows = [
      for (final r in (d['bySession'] as List? ?? const []))
        if (r is Map) r,
    ];
    if (rows.isEmpty) return [const Text('Belum ada sesi.')];
    String roleName(String? id) =>
        id == null ? 'Manual' : (_roles[id]?['name'] as String? ?? id);
    return [
      for (final s in rows)
        ChunkyTile(
          title: _short(
            '${s['title'] ?? s['first_prompt'] ?? '${s['sid']}'.substring(0, 8)}',
            60,
          ),
          subtitle: [
            roleName(s['role'] as String?),
            if (s['room'] != null) '${s['room']}',
            s['first'] == s['last']
                ? '${s['first']}'
                : '${s['first']} – ${s['last']}',
          ].join(' · '),
          trailing: Text(
            usd(s['cost'] as num),
            style: GhinaType.moneyS.copyWith(color: context.ghina.textPrimary),
          ),
          dense: true,
        ),
    ];
  }

  static String _short(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n - 1)}…';
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

class _DayChart extends StatelessWidget {
  const _DayChart({required this.days});
  final List<Map<String, dynamic>> days;

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

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (days.isEmpty) return const Text('Belum ada data.');
    final max = days.fold<double>(
      0.01,
      (a, d) => math.max(a, (d['cost'] as num).toDouble()),
    );
    final top = _niceMax(max);
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 2,
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
                interval: top / 2,
                getTitlesWidget: (v, meta) => Text(
                  usd(v, top < 10 ? 2 : 0),
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
                      !(i % 5 == 0 || i == days.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  final day = '${days[i]['day']}';
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
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${days[group.x]['day']}\n${usd(days[group.x]['cost'] as num)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (days[i]['cost'] as num).toDouble(),
                    width: 6,
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
