import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'sysmon_charts.dart';
import 'sysmon_data.dart';
import 'sysmon_tabs.dart';

/// "Performa PC": live dashboard of the Mac that runs the Kantor daemon
/// (`/api/sysmon*`, see FRONTEND-CONTRACT "Performa PC (sysmon)").
/// Live numbers come from `{t:'sysmon'}` events on `/ws`; a 5 s timer only
/// falls back to polling when events stop, loads processes while the
/// Proses/Agen tabs are open, and pings the events endpoint every 30 s, which
/// also keeps the daemon's sampler awake. Nothing runs when the screen is
/// closed or the app is in the background; widgets repaint only on new data.
class KantorSysmonPage extends ConsumerStatefulWidget {
  const KantorSysmonPage({super.key});

  @override
  ConsumerState<KantorSysmonPage> createState() => _KantorSysmonPageState();
}

const _tabs = <(String, IconData)>[
  ('Ringkasan', Icons.dashboard_rounded),
  ('CPU', Icons.developer_board_rounded),
  ('Memori', Icons.memory_rounded),
  ('Disk', Icons.storage_rounded),
  ('Jaringan', Icons.wifi_rounded),
  ('Baterai & Daya', Icons.battery_charging_full_rounded),
  ('GPU', Icons.videogame_asset_rounded),
  ('Proses', Icons.apps_rounded),
  ('Agen Kantor', Icons.smart_toy_rounded),
  ('Riwayat', Icons.history_rounded),
];

class _KantorSysmonPageState extends ConsumerState<KantorSysmonPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _snap;
  Map? _procs;
  List<Map> _events = const [];
  Object? _error;
  final _live = SysSeries(800);
  SysSeries? _day;
  DateTime _dayAt = DateTime.fromMillisecondsSinceEpoch(0);
  SysRange _range = SysRange.m15;
  int _tab = 0;
  Timer? _timer;
  DateTime _lastLive = DateTime.fromMillisecondsSinceEpoch(0);
  int _ticks = 0;

  bool get _wantsProcs => _tab == 7 || _tab == 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(full: true);
    _loadEvents();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(full: true);
      _loadEvents();
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _ticks++;
      if (DateTime.now().difference(_lastLive).inSeconds > 8) _load();
      if (_wantsProcs && _ticks.isEven) _loadProcs();
      if (_ticks % 6 == 0) _loadEvents();
      if (_range == SysRange.h24 &&
          DateTime.now().difference(_dayAt).inSeconds >= 60) {
        _loadDay();
      }
    });
    if (_wantsProcs) _loadProcs();
  }

  Future<void> _load({bool full = false}) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final r = await api.get(
        '/api/sysmon',
        query: {
          'min': full ? 60 : 1,
          if (full) 'series': sysmonHistorySeries else 'series': 'cpu',
        },
      );
      if (!mounted || r is! Map) return;
      final m = Map<String, dynamic>.from(r);
      setState(() {
        _error = null;
        _snap = m;
        final h = m['history'];
        if (full && h is Map) {
          _live.fill(h);
        } else {
          _live.add(sysNum(m['at'])?.toInt() ?? 0, sysPointFromSnapshot(m));
        }
        final ev = m['events'];
        if (ev is List && _events.isEmpty) {
          _events = ev.whereType<Map>().toList();
        }
      });
    } catch (e) {
      if (mounted && _snap == null) setState(() => _error = e);
    }
  }

  Future<void> _loadProcs() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final r = await api.get('/api/sysmon/procs');
      if (mounted && r is Map) setState(() => _procs = r);
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    try {
      final r = await api.get('/api/sysmon/events', query: {'limit': 100});
      if (mounted && r is Map && r['events'] is List) {
        final ev = (r['events'] as List).whereType<Map>().toList();
        if (ev.length != _events.length ||
            (ev.isNotEmpty && ev.first['at'] != _events.first['at'])) {
          setState(() => _events = ev);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDay() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    _dayAt = DateTime.now();
    try {
      final r = await api.get(
        '/api/sysmon/history',
        query: {'min': 1440, 'points': 360, 'series': sysmonHistorySeries},
      );
      if (mounted && r is Map) setState(() => _day = SysSeries(2000)..fill(r));
    } catch (_) {}
  }

  void _onLive(Map e) {
    final s = _snap;
    if (s == null) return;
    _lastLive = DateTime.now();
    setState(() {
      _snap = sysMergeLive(s, e);
      _live.add(sysNum(e['at'])?.toInt() ?? 0, sysPointFromSnapshot(_snap!));
    });
  }

  void _setRange(SysRange r) {
    setState(() => _range = r);
    if (r == SysRange.h24 &&
        (_day == null || DateTime.now().difference(_dayAt).inSeconds >= 60)) {
      _loadDay();
    }
  }

  void _setTab(int i) {
    setState(() => _tab = i);
    if (_wantsProcs && _procs == null) _loadProcs();
    if (i == 9) _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    ref.listen(kantorEventsProvider, (_, next) {
      final e = next.value;
      if (e != null && e['t'] == 'sysmon') _onLive(e);
    });
    final s = _snap;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Performa PC')),
      body: s == null
          ? (_error != null
                ? KantorErrorView(
                    error: _error!,
                    onRetry: () => _load(full: true),
                  )
                : const KantorLoading())
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                _load(full: true),
                _loadEvents(),
                if (_wantsProcs) _loadProcs(),
                if (_range == SysRange.h24) _loadDay(),
              ]),
              child: _content(s),
            ),
    );
  }

  Widget _content(Map<String, dynamic> s) {
    final data = _range == SysRange.h24
        ? (_day ?? SysSeries())
        : _live.window(_range.min);
    final c = SysCtx(
      s: s,
      data: data,
      live: _live.window(15),
      procs: _procs,
      events: _events,
      range: _range,
      onRange: _setRange,
    );
    final body = switch (_tab) {
      1 => sysCpu(context, c),
      2 => sysMemory(context, c),
      3 => sysDisk(context, c),
      4 => sysNet(context, c),
      5 => sysPower(context, c),
      6 => sysGpu(context, c),
      7 => sysProcesses(context, c),
      8 => sysAgents(context, c),
      9 => sysHistory(context, c),
      _ => sysOverview(context, c),
    };
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _Hero(s: s)),
        ),
        SliverToBoxAdapter(
          child: _TabStrip(index: _tab, onTap: _setTab),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            0,
            GhinaSpace.page,
            GhinaSpace.xl,
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: body,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _Footer(s: s)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final h = sysMap(s['health']);
    final score = sysNum(h['score']);
    final c = sysmonScoreColor(score ?? 100);
    final mem = sysMap(s['mem']);
    final active = s['active'] != false;
    return ChunkyCard(
      tinted: c,
      padding: const EdgeInsets.all(GhinaSpace.md),
      semanticLabel: 'Kesehatan PC ${score ?? ''}',
      child: Row(
        children: [
          SysGauge(
            value: score,
            color: c.base,
            center: score == null ? '–' : '${score.round()}',
            label: '${h['status'] ?? 'skor'}',
            size: 96,
            full: true,
            stroke: 10,
          ),
          const SizedBox(width: GhinaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s['host'] ?? 'Mac'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.h3
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    SysPulse(
                      beat: sysNum(s['at'])?.toInt() ?? 0,
                      color: active
                          ? GhinaColors.green.base
                          : GhinaColors.gray.base,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      active ? 'LIVE' : 'jeda',
                      style: GhinaType.overline.copyWith(
                        color: active ? GhinaColors.green.base : g.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                Text(
                  [
                    s['chip'],
                    s['model'],
                    s['os'],
                  ].where((x) => x != null).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption
                      .w(700)
                      .copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(
                      context,
                      Icons.schedule_rounded,
                      'nyala ${sysmonUptime(s['uptimeSec'])}',
                    ),
                    _chip(
                      context,
                      Icons.memory_rounded,
                      '${sysmonBytes(mem['used'])} / ${sysmonBytes(mem['total'])}',
                    ),
                    if (sysList(s['users']).isNotEmpty)
                      _chip(
                        context,
                        Icons.person_rounded,
                        sysList(s['users']).join(', '),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData i, String t) {
    final g = context.ghina;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: g.surface,
        borderRadius: GhinaRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 12, color: g.textSecondary),
          const SizedBox(width: 4),
          Text(
            t,
            style: GhinaType.caption
                .w(800)
                .copyWith(color: g.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: GhinaSpace.page,
          vertical: 11,
        ),
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final on = i == index;
          final c = g.highlight;
          return Semantics(
            selected: on,
            button: true,
            child: InkWell(
              borderRadius: GhinaRadii.rPill,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: GhinaMotion.fast,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: on ? c.base : g.surface,
                  borderRadius: GhinaRadii.rPill,
                  border: Border.all(color: on ? c.edge : g.border, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tabs[i].$2,
                      size: 16,
                      color: on ? c.on : g.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _tabs[i].$1,
                      style: GhinaType.caption
                          .w(900)
                          .copyWith(color: on ? c.on : g.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.s});
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final cost = sysMap(s['cost']);
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xl),
      child: Text(
        'Sampel tiap ${s['intervalSec'] ?? 5} dtk · ${sysmonFixed(s['tickMs'])} ms per sampel'
        '${cost['daemonCpuPct'] != null ? ' · daemon ${sysmonFixed(cost['daemonCpuPct'], 2)}% CPU' : ''}',
        style: GhinaType.caption.copyWith(color: g.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}
