import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'sysmon_charts.dart';
import 'sysmon_data.dart';
import 'sysmon_widgets.dart';

/// Inputs for every tab.
class SysCtx {
  const SysCtx({
    required this.s,
    required this.data,
    required this.live,
    required this.procs,
    required this.events,
    required this.range,
    required this.onRange,
  });
  final Map<String, dynamic> s;

  /// series for the chosen range
  final SysSeries data;

  /// last hour, for sparklines
  final SysSeries live;
  final Map? procs;
  final List<Map> events;
  final SysRange range;
  final ValueChanged<SysRange> onRange;

  Map get cpu => sysMap(s['cpu']);
  Map get mem => sysMap(s['mem']);
  Map get net => sysMap(s['net']);
  Map get dio => sysMap(s['diskio']);
  Map get gpu => sysMap(s['gpu']);
  Map get batt => sysMap(s['battery']);
  Map get agents => sysMap(s['agents']);
  Map get health => sysMap(s['health']);
  Map get top => {...sysMap(s['top']), ...sysMap(sysMap(procs)['top'])};
  List<Map> get disks => sysList(s['disks']).whereType<Map>().toList();
  List<double> get cores => [
    for (final c in sysList(cpu['cores'])) sysNum(c) ?? 0,
  ];
  int get coreCount => sysNum(cpu['count'])?.toInt() ?? cores.length;
  Widget get picker => SysRangePicker(value: range, onChanged: onRange);
}

Widget _alerts(BuildContext context, SysCtx c) {
  final alerts = sysList(c.s['alerts']).whereType<Map>().toList();
  if (alerts.isEmpty) return const SizedBox.shrink();
  return ChunkyCard(
    tinted: GhinaColors.red,
    padding: const EdgeInsets.all(GhinaSpace.md),
    semanticLabel: 'Peringatan performa',
    child: Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: GhinaColors.red.base),
        const SizedBox(width: GhinaSpace.sm),
        Expanded(
          child: Text(
            alerts
                .map(
                  (a) =>
                      '${a['label']} ${sysmonFixed(a['value'])} (batas ${a['limit']})${a['sustained'] == true ? '' : ' · baru mulai'}',
                )
                .join('\n'),
            style: GhinaType.bodyS.w(800).copyWith(color: GhinaColors.red.base),
          ),
        ),
      ],
    ),
  );
}

/* ---------------- Ringkasan ---------------- */

Widget sysOverview(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final cpuPct = sysNum(c.cpu['total']) ?? 0,
      ramPct = sysNum(c.mem['pct']) ?? 0;
  final main = c.disks.isEmpty ? const {} : c.disks.first;
  final diskPct = sysNum(main['pct']);
  final gpuPct = sysNum(c.gpu['util']);
  final reasons = sysList(c.health['reasons']).whereType<Map>().toList();
  return SysColumns(
    children: [
      if (sysList(c.s['alerts']).isNotEmpty) _alerts(context, c),
      SysRamCard(mem: c.mem, data: c.live),
      sysTopSummary(context, c),
      SysCard(
        title: 'Sekilas',
        icon: Icons.speed_rounded,
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 8,
          runSpacing: 10,
          children: [
            SysGauge(
              value: cpuPct,
              color: sysmonColor(cpuPct).base,
              center: sysmonPct(cpuPct),
              label: 'CPU',
              sub: '${c.coreCount} core',
              size: 100,
            ),
            SysGauge(
              value: ramPct,
              color: sysmonColor(ramPct).base,
              center: sysmonBytes(c.mem['used']).split(' ').first,
              label: 'RAM GB',
              sub: 'dari ${sysmonBytes(c.mem['total'])}',
              size: 100,
            ),
            if (gpuPct != null)
              SysGauge(
                value: gpuPct,
                color: sysmonColor(gpuPct).base,
                center: sysmonPct(gpuPct),
                label: 'GPU',
                sub: sysmonBytes(c.gpu['mem']),
                size: 100,
              ),
            if (diskPct != null)
              SysGauge(
                value: diskPct,
                color: sysmonColor(diskPct).base,
                center: sysmonPct(diskPct),
                label: 'Disk',
                sub: 'sisa ${sysmonBytes(main['free'])}',
                size: 100,
              ),
          ],
        ),
      ),
      SysCard(
        title: 'Lalu lintas',
        icon: Icons.swap_vert_rounded,
        color: GhinaColors.teal,
        child: SysStatGrid(
          children: [
            SysStat(
              'Unduh',
              sysmonBytes(c.net['rx'], rate: true),
              color: GhinaColors.blue.base,
            ),
            SysStat(
              'Unggah',
              sysmonBytes(c.net['tx'], rate: true),
              color: GhinaColors.purple.base,
            ),
            SysStat(
              'Disk baca',
              sysmonBytes(c.dio['read'], rate: true),
              sub: '${sysmonInt(c.dio['rIops'])} IOPS',
            ),
            SysStat(
              'Disk tulis',
              sysmonBytes(c.dio['write'], rate: true),
              sub: '${sysmonInt(c.dio['wIops'])} IOPS',
            ),
          ],
        ),
      ),
      SysCard(
        title: 'Agen Kantor',
        icon: Icons.smart_toy_rounded,
        color: GhinaColors.purple,
        sub: '${sysmonInt(c.agents['n'])} proses claude/codex/node/tmux',
        child: SysStatGrid(
          children: [
            SysStat(
              'CPU agen',
              sysmonPct(c.agents['cpu']),
              sub:
                  '≈ ${sysmonFixed((sysNum(c.agents['cpu']) ?? 0) / 100)} core',
            ),
            SysStat(
              'RAM agen',
              sysmonBytes(c.agents['rss']),
              sub: 'dari ${sysmonBytes(c.mem['total'])}',
            ),
          ],
        ),
      ),
      if (c.batt.isNotEmpty)
        SysCard(
          title: 'Baterai',
          icon: Icons.battery_charging_full_rounded,
          color: GhinaColors.green,
          child: Row(
            children: [
              SysBattery(
                pct: sysNum(c.batt['pct']) ?? 0,
                charging: c.batt['charging'] == true,
                ac: c.batt['ac'] == true,
                width: 110,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SysStat(
                  '${c.batt['state'] ?? ''}',
                  c.batt['remainingMin'] != null
                      ? 'sisa ${sysmonMinutes(c.batt['remainingMin'])}'
                      : (c.batt['ac'] == true ? 'Listrik AC' : '–'),
                  sub:
                      'kesehatan ${sysmonPct(c.batt['health'], d: 1)} · ${c.batt['cycles'] ?? '–'} siklus',
                ),
              ),
            ],
          ),
        ),
      if (reasons.isNotEmpty)
        SysCard(
          title: 'Kenapa skornya ${c.health['score'] ?? '–'}',
          icon: Icons.health_and_safety_rounded,
          color: sysmonScoreColor(sysNum(c.health['score']) ?? 100),
          child: Column(
            children: [
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: sysmonLevelColor(r['level']).base,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r['text']}',
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                      Text(
                        '−${r['pts']}',
                        style: GhinaType.caption
                            .w(900)
                            .copyWith(color: sysmonLevelColor(r['level']).base),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'CPU & RAM',
            icon: Icons.show_chart_rounded,
            data: c.data,
            max: 100,
            fmt: fmtPct,
            lines: [
              SysLine('cpu', 'CPU', GhinaColors.blue.base),
              SysLine('ram', 'RAM', GhinaColors.orange.base),
            ],
          ),
        ],
      ),
    ],
  );
}

/* ---------------- CPU ---------------- */

Widget sysCpu(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final cpuPct = sysNum(c.cpu['total']) ?? 0;
  final levels = sysList(c.cpu['levels']).whereType<Map>().toList();
  final load = sysList(c.s['load']);
  final counts = sysMap(c.s['counts']);
  return SysColumns(
    children: [
      sysTopCard(context, c, 'cpu'),
      SysCard(
        title: '${c.s['chip'] ?? 'CPU'}',
        icon: Icons.developer_board_rounded,
        sub: [
          '${c.coreCount} core',
          if (levels.isNotEmpty)
            levels.map((l) => '${l['cores']} ${l['name']}').join(' + '),
          if (c.cpu['freqMHz'] != null)
            '${sysmonFixed((sysNum(c.cpu['freqMHz']) ?? 0) / 1000, 2)} GHz',
        ].join(' · '),
        child: Row(
          children: [
            SysGauge(
              value: cpuPct,
              color: sysmonColor(cpuPct).base,
              center: sysmonPct(cpuPct),
              label: 'total',
              size: 116,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _splitRow(
                    context,
                    'User',
                    sysNum(c.cpu['user']),
                    GhinaColors.blue,
                  ),
                  _splitRow(
                    context,
                    'Sistem',
                    sysNum(c.cpu['sys']),
                    GhinaColors.red,
                  ),
                  _splitRow(
                    context,
                    'Idle',
                    sysNum(c.cpu['idle']),
                    GhinaColors.gray,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SysCard(
        title: 'Beban & proses',
        icon: Icons.stacked_line_chart_rounded,
        child: SysStatGrid(
          children: [
            for (final (i, l) in ['1 mnt', '5 mnt', '15 mnt'].indexed)
              SysStat(
                'Beban $l',
                i < load.length ? sysmonFixed(load[i], 2) : '–',
                sub: i < load.length
                    ? '${sysmonFixed((sysNum(load[i]) ?? 0) / c.coreCount * 100, 0)}% kapasitas'
                    : null,
              ),
            SysStat(
              'Proses',
              sysmonInt(counts['procs'] ?? sysMap(c.procs)['count']),
              sub: counts['running'] != null
                  ? '${counts['running']} berjalan'
                  : null,
            ),
            if (counts['threads'] != null)
              SysStat('Thread', sysmonInt(counts['threads'])),
          ],
        ),
      ),
      SysCard(
        title: 'Per core',
        icon: Icons.grid_view_rounded,
        sub: 'Peta panas ${c.range.label} terakhir · kanan = sekarang',
        child: SysCoreHeatmap(data: c.data, cores: c.cores, levels: levels),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'User + Sistem',
            icon: Icons.area_chart_rounded,
            data: c.data,
            max: 100,
            stacked: true,
            fmt: fmtPct,
            lines: [
              SysLine('user', 'User', GhinaColors.blue.base),
              SysLine('sys', 'Sistem', GhinaColors.red.base),
            ],
          ),
          const SizedBox(height: GhinaSpace.md),
          SysChartCard(
            title: 'Beban (1 mnt)',
            icon: Icons.timeline_rounded,
            data: c.data,
            fmt: fmtNum,
            color: GhinaColors.purple,
            lines: [SysLine('load', 'Beban', GhinaColors.purple.base)],
          ),
        ],
      ),
      Text(
        'Suhu CPU & kipas tidak tersedia tanpa sudo.',
        style: GhinaType.caption.copyWith(color: g.textMuted),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

Widget _splitRow(
  BuildContext context,
  String label,
  double? v,
  ChunkySwatch color,
) {
  final g = context.ghina;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GhinaType.caption
                    .w(800)
                    .copyWith(color: g.textSecondary),
              ),
            ),
            Text(
              sysmonPct(v, d: 1),
              style: GhinaType.caption.w(900).copyWith(color: g.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SysMeter(value: (v ?? 0) / 100, color: color.base),
      ],
    ),
  );
}

/* ---------------- Memori ---------------- */

Widget sysMemory(BuildContext context, SysCtx c) {
  final m = c.mem;
  final swap = sysMap(m['swap']);
  final rates = sysMap(m['rates']);
  final total = sysNum(m['total']) ?? 0;
  return SysColumns(
    children: [
      sysTopCard(context, c, 'ram'),
      SysRamCard(mem: m),
      SysCard(
        title: 'Rincian',
        icon: Icons.pie_chart_rounded,
        child: SysStatGrid(
          children: [
            SysStat(
              'Aplikasi',
              sysmonBytes(m['app']),
              sub: _of(m['app'], total),
            ),
            SysStat(
              'Wired',
              sysmonBytes(m['wired']),
              sub: _of(m['wired'], total),
            ),
            SysStat(
              'Terkompresi',
              sysmonBytes(m['compressed']),
              sub: _of(m['compressed'], total),
            ),
            SysStat(
              'Cache file',
              sysmonBytes(m['cached']),
              sub: 'bisa dipakai ulang',
            ),
            SysStat(
              'Benar-benar bebas',
              sysmonBytes(m['unused']),
              sub: m['freePct'] != null ? 'level bebas ${m['freePct']}%' : null,
            ),
            SysStat(
              'Tekanan',
              '${m['pressure'] ?? '–'}',
              color: sysmonLevelColor(m['pressure']).base,
            ),
          ],
        ),
      ),
      SysCard(
        title: 'Swap',
        icon: Icons.sync_alt_rounded,
        color: GhinaColors.orange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (swap.isNotEmpty) ...[
              SysBig(
                main: sysmonBytes(swap['used']),
                of: sysmonBytes(swap['total']),
                caption: 'sisa ${sysmonBytes(swap['free'])}',
              ),
              const SizedBox(height: 8),
              SysMeter(
                value:
                    (sysNum(swap['used']) ?? 0) /
                    ((sysNum(swap['total']) ?? 0) == 0
                        ? 1
                        : sysNum(swap['total'])!),
                color: GhinaColors.orange.base,
                height: 10,
              ),
              const SizedBox(height: 12),
            ],
            SysStatGrid(
              children: [
                SysStat('Swap masuk', '${sysmonInt(rates['swapins'])} hal/dtk'),
                SysStat(
                  'Swap keluar',
                  '${sysmonInt(rates['swapouts'])} hal/dtk',
                ),
                SysStat('Page-in', '${sysmonInt(rates['pageins'])} hal/dtk'),
                SysStat('Page-out', '${sysmonInt(rates['pageouts'])} hal/dtk'),
              ],
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'RAM terpakai',
            icon: Icons.show_chart_rounded,
            color: GhinaColors.orange,
            data: c.data,
            max: 100,
            fmt: fmtPct,
            lines: [SysLine('ram', 'RAM', GhinaColors.orange.base)],
          ),
          const SizedBox(height: GhinaSpace.md),
          SysChartCard(
            title: 'Swap & terkompresi',
            icon: Icons.stacked_line_chart_rounded,
            color: GhinaColors.purple,
            data: c.data,
            fmt: fmtMB,
            lines: [
              SysLine('swap', 'Swap', GhinaColors.red.base),
              SysLine('comp', 'Terkompresi', GhinaColors.purple.base),
            ],
          ),
        ],
      ),
    ],
  );
}

String _of(Object? v, double total) {
  final n = sysNum(v);
  return n == null || total <= 0
      ? ''
      : '${sysmonPct(n / total * 100, d: 1)} dari total';
}

/* ---------------- Disk ---------------- */

Widget sysDisk(BuildContext context, SysCtx c) {
  final g = context.ghina;
  return SysColumns(
    children: [
      sysTopCard(context, c, 'disk'),
      for (final d in c.disks)
        SysCard(
          title: '${d['name']}',
          icon: Icons.storage_rounded,
          color: sysmonColor(sysNum(d['pct']) ?? 0),
          sub: '${d['mount']}${d['dev'] != null ? ' · ${d['dev']}' : ''}',
          child: Row(
            children: [
              SysDonut(
                segs: [
                  SysSeg(
                    'Terpakai',
                    sysNum(d['used']) ?? 0,
                    sysmonColor(sysNum(d['pct']) ?? 0).base,
                  ),
                  SysSeg('Sisa', sysNum(d['free']) ?? 0, g.border),
                ],
                center: sysmonPct(d['pct']),
                sub: 'terpakai',
                size: 112,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SysStat('Terpakai', sysmonBytes(d['used'])),
                    const SizedBox(height: 6),
                    SysStat(
                      'Sisa',
                      sysmonBytes(d['free']),
                      color: sysmonColor(sysNum(d['pct']) ?? 0).base,
                    ),
                    const SizedBox(height: 6),
                    SysStat('Total', sysmonBytes(d['total'])),
                  ],
                ),
              ),
            ],
          ),
        ),
      SysCard(
        title: 'I/O disk',
        icon: Icons.import_export_rounded,
        color: GhinaColors.teal,
        child: SysStatGrid(
          children: [
            SysStat(
              'Baca',
              sysmonBytes(c.dio['read'], rate: true),
              sub: '${sysmonInt(c.dio['rIops'])} IOPS',
              color: GhinaColors.teal.base,
            ),
            SysStat(
              'Tulis',
              sysmonBytes(c.dio['write'], rate: true),
              sub: '${sysmonInt(c.dio['wIops'])} IOPS',
              color: GhinaColors.pink.base,
            ),
            SysStat(
              'Total dibaca',
              sysmonBytes(c.dio['readTotal']),
              sub: 'sejak nyala',
            ),
            SysStat(
              'Total ditulis',
              sysmonBytes(c.dio['writeTotal']),
              sub: 'sejak nyala',
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'Throughput',
            icon: Icons.area_chart_rounded,
            color: GhinaColors.teal,
            data: c.data,
            fmt: fmtRate,
            lines: [
              SysLine('dr', 'Baca', GhinaColors.teal.base),
              SysLine('dw', 'Tulis', GhinaColors.pink.base),
            ],
          ),
        ],
      ),
    ],
  );
}

/* ---------------- Jaringan ---------------- */

Widget sysNet(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final n = c.net;
  final ifs = sysMap(n['ifaces']);
  final wifi = sysMap(n['wifi']);
  final conns = sysMap(n['conns']);
  final active = n['active'];
  return SysColumns(
    children: [
      sysTopCard(context, c, 'net'),
      SysCard(
        title: 'Sekarang',
        icon: Icons.wifi_rounded,
        color: GhinaColors.blue,
        sub: [
          if (active != null) 'antarmuka $active',
          if (active != null && sysMap(ifs[active])['ip'] != null)
            'IP ${sysMap(ifs[active])['ip']}',
        ].join(' · '),
        child: SysStatGrid(
          children: [
            SysStat(
              '↓ Unduh',
              sysmonBytes(n['rx'], rate: true),
              color: GhinaColors.blue.base,
            ),
            SysStat(
              '↑ Unggah',
              sysmonBytes(n['tx'], rate: true),
              color: GhinaColors.purple.base,
            ),
            SysStat(
              'Total diterima',
              sysmonBytes(n['rxTotal']),
              sub: 'sejak nyala',
            ),
            SysStat(
              'Total dikirim',
              sysmonBytes(n['txTotal']),
              sub: 'sejak nyala',
            ),
            SysStat(
              'Koneksi TCP',
              sysmonInt(conns['established']),
              sub: conns['listen'] != null
                  ? '${conns['listen']} mendengarkan'
                  : null,
            ),
            if (wifi.isNotEmpty)
              SysStat(
                'Wi-Fi',
                '${wifi['ssid'] ?? 'tersembunyi'}',
                sub: '${wifi['security'] ?? ''}',
              ),
          ],
        ),
      ),
      if (ifs.isNotEmpty)
        SysCard(
          title: 'Antarmuka',
          icon: Icons.lan_rounded,
          child: Column(
            children: [
              for (final e in ifs.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        e.key == active
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 16,
                        color: e.key == active
                            ? GhinaColors.green.base
                            : g.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e.key}${sysMap(e.value)['ip'] != null ? ' · ${sysMap(e.value)['ip']}' : ''}',
                              style: GhinaType.bodyS
                                  .w(800)
                                  .copyWith(color: g.textPrimary),
                            ),
                            Text(
                              'total ↓ ${sysmonBytes(sysMap(e.value)['rxTotal'])} ↑ ${sysmonBytes(sysMap(e.value)['txTotal'])}',
                              style: GhinaType.caption.copyWith(
                                color: g.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '↓ ${sysmonBytes(sysMap(e.value)['rx'], rate: true)}\n↑ ${sysmonBytes(sysMap(e.value)['tx'], rate: true)}',
                        textAlign: TextAlign.right,
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(color: g.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'Unduh & unggah',
            icon: Icons.area_chart_rounded,
            data: c.data,
            fmt: fmtRate,
            lines: [
              SysLine('rx', 'Unduh', GhinaColors.blue.base),
              SysLine('tx', 'Unggah', GhinaColors.purple.base),
            ],
          ),
        ],
      ),
    ],
  );
}

/* ---------------- Baterai & Daya ---------------- */

Widget sysPower(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final b = c.batt;
  final therm = sysMap(c.s['thermal']);
  final ad = sysMap(b['adapter']);
  final volt = sysNum(b['voltage']);
  double? wh(Object? mah) =>
      sysNum(mah) == null || volt == null ? null : sysNum(mah)! * volt / 1000;
  final watts = sysNum(b['watts']);
  return SysColumns(
    children: [
      sysTopCard(context, c, 'power'),
      if (b.isEmpty)
        SysCard(
          title: 'Baterai',
          icon: Icons.power_rounded,
          child: Text(
            'Mac ini tidak punya baterai.',
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          ),
        )
      else ...[
        SysCard(
          title: 'Baterai',
          icon: Icons.battery_charging_full_rounded,
          color: GhinaColors.green,
          trailing: SysPill(
            '${b['state'] ?? ''}',
            b['ac'] == true ? GhinaColors.green : GhinaColors.orange,
          ),
          child: Column(
            children: [
              Center(
                child: SysBattery(
                  pct: sysNum(b['pct']) ?? 0,
                  charging: b['charging'] == true,
                  ac: b['ac'] == true,
                  width: 190,
                ),
              ),
              const SizedBox(height: 12),
              SysStatGrid(
                children: [
                  SysStat(
                    'Sisa waktu',
                    b['remainingMin'] != null
                        ? sysmonMinutes(b['remainingMin'])
                        : (b['ac'] == true ? 'Listrik AC' : 'menghitung…'),
                  ),
                  SysStat(
                    'Daya',
                    watts == null ? '–' : '${sysmonFixed(watts.abs())} W',
                    sub: watts == null
                        ? null
                        : watts < 0
                        ? 'dipakai dari baterai'
                        : 'masuk ke baterai',
                  ),
                  SysStat(
                    'Charger',
                    ad.isEmpty
                        ? (b['ac'] == true ? 'terhubung' : 'tidak')
                        : '${ad['watts'] ?? '–'} W',
                    sub: ad['name'] != null ? '${ad['name']}' : null,
                  ),
                  SysStat(
                    'Suhu baterai',
                    b['tempC'] == null ? '–' : '${sysmonFixed(b['tempC'])} °C',
                  ),
                ],
              ),
            ],
          ),
        ),
        SysCard(
          title: 'Kesehatan baterai',
          icon: Icons.favorite_rounded,
          color: (sysNum(b['health']) ?? 100) >= 80
              ? GhinaColors.green
              : GhinaColors.orange,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SysBig(
                main: sysmonPct(b['health'], d: 1),
                of: '100%',
                caption: 'kondisi ${b['condition'] ?? '–'}',
              ),
              const SizedBox(height: 8),
              SysMeter(
                value: (sysNum(b['health']) ?? 0) / 100,
                color: GhinaColors.green.base,
                height: 10,
              ),
              const SizedBox(height: 12),
              SysStatGrid(
                children: [
                  SysStat(
                    'Kapasitas penuh',
                    '${sysmonInt(b['capacityMah'])} mAh',
                    sub: wh(b['capacityMah']) == null
                        ? null
                        : '${sysmonFixed(wh(b['capacityMah']))} Wh',
                  ),
                  SysStat(
                    'Kapasitas desain',
                    '${sysmonInt(b['designMah'])} mAh',
                    sub: wh(b['designMah']) == null
                        ? null
                        : '${sysmonFixed(wh(b['designMah']))} Wh',
                  ),
                  SysStat(
                    'Siklus',
                    '${sysmonInt(b['cycles'])} / ${sysmonInt(b['designCycles'])}',
                  ),
                  SysStat(
                    'Tegangan',
                    volt == null ? '–' : '${sysmonFixed(volt, 2)} V',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      SysCard(
        title: 'Termal',
        icon: Icons.thermostat_rounded,
        color: sysmonLevelColor(therm['state']),
        child: SysStatGrid(
          children: [
            SysStat(
              'Status',
              '${therm['state'] ?? '–'}',
              color: sysmonLevelColor(therm['state']).base,
            ),
            SysStat(
              'Batas kecepatan CPU',
              therm['speedLimit'] == null
                  ? 'tidak dibatasi'
                  : '${therm['speedLimit']}%',
            ),
            SysStat(
              'Kipas',
              c.s['fan'] == null ? 'tidak terbaca' : '${c.s['fan']}',
              sub: 'butuh sudo/SMC',
            ),
          ],
        ),
      ),
      if (b.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            c.picker,
            const SizedBox(height: 10),
            SysChartCard(
              title: 'Persen baterai',
              icon: Icons.show_chart_rounded,
              color: GhinaColors.green,
              data: c.data,
              max: 100,
              fmt: fmtPct,
              lines: [SysLine('batt', 'Baterai', GhinaColors.green.base)],
            ),
          ],
        ),
    ],
  );
}

/* ---------------- GPU ---------------- */

Widget sysGpu(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final gp = c.gpu;
  if (gp.isEmpty) {
    return SysCard(
      title: 'GPU',
      icon: Icons.videogame_asset_rounded,
      child: Text(
        'Data GPU belum ada (hanya tersedia di Apple Silicon saat layar ini dibuka).',
        style: GhinaType.bodyS.copyWith(color: g.textMuted),
      ),
    );
  }
  final u = sysNum(gp['util']) ?? 0;
  return SysColumns(
    children: [
      sysTopCard(context, c, 'gpu'),
      SysCard(
        title: '${gp['name'] ?? 'GPU'}',
        icon: Icons.videogame_asset_rounded,
        color: GhinaColors.pink,
        sub: gp['cores'] != null ? '${gp['cores']} core GPU' : null,
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 8,
          runSpacing: 8,
          children: [
            SysGauge(
              value: u,
              color: sysmonColor(u).base,
              center: sysmonPct(u),
              label: 'Perangkat',
              size: 112,
            ),
            SysGauge(
              value: sysNum(gp['renderer']),
              color: GhinaColors.pink.base,
              center: sysmonPct(gp['renderer']),
              label: 'Renderer',
              size: 92,
              stroke: 9,
            ),
            SysGauge(
              value: sysNum(gp['tiler']),
              color: GhinaColors.purple.base,
              center: sysmonPct(gp['tiler']),
              label: 'Tiler',
              size: 92,
              stroke: 9,
            ),
          ],
        ),
      ),
      SysCard(
        title: 'Memori GPU',
        icon: Icons.memory_rounded,
        color: GhinaColors.purple,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SysBig(
              main: sysmonBytes(gp['mem']),
              of: sysmonBytes(gp['alloc']),
              caption: 'dipakai dari yang dialokasikan (memori bersama)',
            ),
            const SizedBox(height: 8),
            SysMeter(
              value:
                  (sysNum(gp['mem']) ?? 0) /
                  ((sysNum(gp['alloc']) ?? 0) == 0 ? 1 : sysNum(gp['alloc'])!),
              color: GhinaColors.purple.base,
              height: 10,
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'Pemakaian GPU',
            icon: Icons.area_chart_rounded,
            color: GhinaColors.pink,
            data: c.data,
            max: 100,
            fmt: fmtPct,
            lines: [SysLine('gpu', 'GPU', GhinaColors.pink.base)],
          ),
        ],
      ),
    ],
  );
}

/* ---------------- Agen Kantor ---------------- */

const _agentColors = {
  'claude': GhinaColors.orange,
  'codex': GhinaColors.blue,
  'node': GhinaColors.green,
  'tmux': GhinaColors.purple,
};

Widget sysAgents(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final a = sysMap(sysMap(c.procs)['agents']).isNotEmpty
      ? sysMap(sysMap(c.procs)['agents'])
      : c.agents;
  final kinds = sysMap(a['kinds']);
  final total = sysNum(c.mem['total']) ?? 0;
  final groups = sysList(
    sysMap(c.procs)['groups'],
  ).whereType<Map>().where((x) => x['agent'] != null).toList();
  return SysColumns(
    children: [
      SysCard(
        title: 'Agen Kantor',
        icon: Icons.smart_toy_rounded,
        color: GhinaColors.purple,
        sub: 'Semua proses claude, codex, node dan tmux',
        child: Row(
          children: [
            SysDonut(
              size: 124,
              segs: [
                for (final e in kinds.entries)
                  SysSeg(
                    '${e.key}',
                    sysNum(sysMap(e.value)['rss']) ?? 0,
                    (_agentColors[e.key] ?? GhinaColors.gray).base,
                  ),
              ],
              center: sysmonBytes(a['rss']),
              sub: 'RAM agen',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SysStat(
                    'CPU',
                    sysmonPct(a['cpu']),
                    sub:
                        '≈ ${sysmonFixed((sysNum(a['cpu']) ?? 0) / 100)} dari ${c.coreCount} core',
                  ),
                  const SizedBox(height: 6),
                  SysStat(
                    'RAM',
                    sysmonBytes(a['rss']),
                    sub: _of(a['rss'], total),
                  ),
                  const SizedBox(height: 6),
                  SysStat('Proses', sysmonInt(a['n'])),
                ],
              ),
            ),
          ],
        ),
      ),
      SysCard(
        title: 'Per jenis',
        icon: Icons.category_rounded,
        child: Column(
          children: [
            for (final e in kinds.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: (_agentColors[e.key] ?? GhinaColors.gray).base,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${e.key} · ${sysMap(e.value)['n']} proses',
                            style: GhinaType.bodyS
                                .w(800)
                                .copyWith(color: g.textPrimary),
                          ),
                        ),
                        Text(
                          '${sysmonPct(sysMap(e.value)['cpu'], d: 1)} · ${sysmonBytes(sysMap(e.value)['rss'])}',
                          style: GhinaType.caption
                              .w(800)
                              .copyWith(color: g.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SysMeter(
                      value:
                          (sysNum(sysMap(e.value)['rss']) ?? 0) /
                          (total == 0 ? 1 : total) *
                          4,
                      color: (_agentColors[e.key] ?? GhinaColors.gray).base,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'CPU agen (100% = 1 core)',
            icon: Icons.area_chart_rounded,
            color: GhinaColors.purple,
            data: c.data,
            fmt: fmtPct,
            lines: [SysLine('agents', 'Agen', GhinaColors.purple.base)],
          ),
        ],
      ),
      if (groups.isNotEmpty)
        SysProcessList(
          procs: {'groups': groups},
          total: total,
          title: 'Proses agen',
        ),
    ],
  );
}

/* ---------------- Riwayat & Peristiwa ---------------- */

Widget sysHistory(BuildContext context, SysCtx c) {
  final g = context.ghina;
  return SysColumns(
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c.picker,
          const SizedBox(height: 10),
          SysChartCard(
            title: 'Skor kesehatan',
            icon: Icons.health_and_safety_rounded,
            color: GhinaColors.green,
            data: c.data,
            max: 100,
            fmt: fmtNum,
            lines: [SysLine('score', 'Skor', GhinaColors.green.base)],
          ),
          const SizedBox(height: GhinaSpace.md),
          SysChartCard(
            title: 'CPU · RAM · GPU',
            icon: Icons.show_chart_rounded,
            data: c.data,
            max: 100,
            fmt: fmtPct,
            lines: [
              SysLine('cpu', 'CPU', GhinaColors.blue.base, fill: false),
              SysLine('ram', 'RAM', GhinaColors.orange.base, fill: false),
              SysLine('gpu', 'GPU', GhinaColors.pink.base, fill: false),
            ],
          ),
        ],
      ),
      SysCard(
        title: 'Peristiwa',
        icon: Icons.history_rounded,
        color: GhinaColors.orange,
        sub: 'Lewat batas, tekanan memori, termal, charger',
        child: c.events.isEmpty
            ? Text(
                'Belum ada peristiwa.',
                style: GhinaType.bodyS.copyWith(color: g.textMuted),
              )
            : Column(
                children: [
                  for (final e in c.events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sysmonLevelColor(e['level']).base,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${e['text']}',
                              style: GhinaType.bodyS
                                  .w(700)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sysNum(e['at']) == null
                                ? ''
                                : '${sysmonClock(sysNum(e['at'])!.toInt())}\n${sysmonAgo(sysNum(e['at'])!.toInt())}',
                            textAlign: TextAlign.right,
                            style: GhinaType.caption.copyWith(
                              color: g.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

/* ---------------- Proses ---------------- */

enum _Sort { cpu, ram, name }

/// Grouped, searchable, sortable process list with expandable app groups.
class SysProcessList extends StatefulWidget {
  const SysProcessList({
    super.key,
    required this.procs,
    required this.total,
    this.title = 'Aplikasi & proses',
  });
  final Map? procs;
  final double total;
  final String title;

  @override
  State<SysProcessList> createState() => _SysProcessListState();
}

class _SysProcessListState extends State<SysProcessList> {
  var _q = '';
  var _sort = _Sort.cpu;
  final _open = <String>{};
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = widget.procs;
    var groups = sysList(p?['groups']).whereType<Map>().toList();
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = groups
          .where(
            (x) =>
                '${x['name']}'.toLowerCase().contains(q) ||
                sysList(x['procs']).any(
                  (y) =>
                      '${sysMap(y)['name']}'.toLowerCase().contains(q) ||
                      '${sysMap(y)['pid']}' == q,
                ),
          )
          .toList();
    }
    int cmp(Map a, Map b) => switch (_sort) {
      _Sort.cpu => (sysNum(b['cpu']) ?? 0).compareTo(sysNum(a['cpu']) ?? 0),
      _Sort.ram => (sysNum(b['rss']) ?? 0).compareTo(sysNum(a['rss']) ?? 0),
      _Sort.name => '${a['name']}'.toLowerCase().compareTo(
        '${b['name']}'.toLowerCase(),
      ),
    };
    groups.sort(cmp);
    final shown = _all || q.isNotEmpty ? groups : groups.take(25).toList();
    final maxCpu = groups.fold<double>(
      1,
      (m, x) => (sysNum(x['cpu']) ?? 0) > m ? sysNum(x['cpu'])! : m,
    );
    final maxRss = groups.fold<double>(
      1,
      (m, x) => (sysNum(x['rss']) ?? 0) > m ? sysNum(x['rss'])! : m,
    );
    return SysCard(
      title: widget.title,
      icon: Icons.apps_rounded,
      sub: p == null
          ? 'Memuat…'
          : '${groups.length} aplikasi${p['count'] != null ? ' · ${sysmonInt(p['count'])} proses' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sysList(p?['groups']).length > 6) ...[
            TextField(
              onChanged: (v) => setState(() => _q = v),
              style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari aplikasi, proses atau PID',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: g.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: GhinaRadii.rMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ChunkySegmented<_Sort>(
              height: 36,
              segments: const [
                ChunkySegment(value: _Sort.cpu, label: 'CPU'),
                ChunkySegment(value: _Sort.ram, label: 'RAM'),
                ChunkySegment(value: _Sort.name, label: 'Nama'),
              ],
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
            ),
            const SizedBox(height: 6),
          ],
          for (final x in shown) _group(context, x, maxCpu, maxRss),
          if (!_all && q.isEmpty && groups.length > shown.length)
            TextButton(
              onPressed: () => setState(() => _all = true),
              child: Text('Tampilkan semua (${groups.length})'),
            ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, Map x, double maxCpu, double maxRss) {
    final g = context.ghina;
    final name = '${x['name']}';
    final n = sysNum(x['n'])?.toInt() ?? 1;
    final open = _open.contains(name);
    final agent = x['agent'];
    final ac = agent == null ? null : _agentColors[agent];
    final procs = sysList(x['procs']).whereType<Map>().toList();
    final cpu = sysNum(x['cpu']) ?? 0, rss = sysNum(x['rss']) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: GhinaRadii.rMd,
          onTap: n > 1
              ? () =>
                    setState(() => open ? _open.remove(name) : _open.add(name))
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      n > 1
                          ? (open
                                ? Icons.expand_more_rounded
                                : Icons.chevron_right_rounded)
                          : Icons.circle,
                      size: n > 1 ? 18 : 7,
                      color: g.textMuted,
                    ),
                    SizedBox(width: n > 1 ? 4 : 9),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: name,
                              style: GhinaType.bodyS
                                  .w(800)
                                  .copyWith(color: g.textPrimary),
                            ),
                            if (n > 1)
                              TextSpan(
                                text: '  ×$n',
                                style: GhinaType.caption
                                    .w(700)
                                    .copyWith(color: g.textMuted),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ac != null) ...[
                      SysPill('$agent', ac),
                      const SizedBox(width: 6),
                    ],
                    SizedBox(
                      width: 58,
                      child: Text(
                        sysmonPct(cpu, d: 1),
                        textAlign: TextAlign.right,
                        style: GhinaType.caption
                            .w(_sort == _Sort.cpu ? 900 : 600)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(
                        sysmonBytes(rss),
                        textAlign: TextAlign.right,
                        style: GhinaType.caption
                            .w(_sort == _Sort.ram ? 900 : 600)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SizedBox(width: 22),
                    Expanded(
                      child: SysMeter(
                        value: cpu / maxCpu,
                        color: sysmonColor(cpu.clamp(0, 100).toDouble()).base,
                        height: 4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SysMeter(
                        value: rss / maxRss,
                        color: GhinaColors.blue.base,
                        height: 4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 6),
            child: Column(
              children: [
                for (final p in procs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          'PID ${p['pid']}',
                          style: GhinaType.caption.copyWith(
                            color: g.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            sysmonPct(p['cpu'], d: 1),
                            textAlign: TextAlign.right,
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 66,
                          child: Text(
                            sysmonBytes(p['rss']),
                            textAlign: TextAlign.right,
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (n > procs.length)
                  Text(
                    '+${n - procs.length} proses lain',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget sysProcesses(BuildContext context, SysCtx c) {
  final p = c.procs;
  final byCpu = sysList(p?['byCpu']).whereType<Map>().take(5).toList();
  final byRam = sysList(p?['byRam']).whereType<Map>().take(5).toList();
  final g = context.ghina;
  Widget top(String t, List<Map> rows, bool ram) => SysCard(
    title: t,
    icon: ram ? Icons.memory_rounded : Icons.bolt_rounded,
    color: ram ? GhinaColors.blue : GhinaColors.orange,
    child: Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${r['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                Text(
                  ram ? sysmonBytes(r['rss']) : sysmonPct(r['cpu'], d: 1),
                  style: GhinaType.caption
                      .w(900)
                      .copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  return SysColumns(
    children: [
      sysTopCard(context, c, 'net'),
      sysTopCard(context, c, 'gpu'),
      sysTopCard(context, c, 'power'),
      if (byCpu.isNotEmpty) top('Paling sibuk (CPU)', byCpu, false),
      if (byRam.isNotEmpty) top('Paling boros RAM', byRam, true),
      SysProcessList(procs: p, total: sysNum(c.mem['total']) ?? 0),
    ],
  );
}

/* ---------------- Pemakan terbesar ---------------- */

const _topMeta = <String, (String, IconData, ChunkySwatch)>{
  'cpu': ('CPU', Icons.bolt_rounded, GhinaColors.orange),
  'ram': ('RAM', Icons.memory_rounded, GhinaColors.blue),
  'net': ('Jaringan', Icons.wifi_rounded, GhinaColors.teal),
  'gpu': ('GPU', Icons.videogame_asset_rounded, GhinaColors.pink),
  'power': ('Energi', Icons.battery_alert_rounded, GhinaColors.green),
  'disk': ('Disk', Icons.storage_rounded, GhinaColors.purple),
};

String sysTopValue(String key, Map e) => switch (key) {
  'ram' => sysmonBytes(e['value']),
  'net' =>
    '↓${sysmonBytes(e['rx'], rate: true)} ↑${sysmonBytes(e['tx'], rate: true)}',
  'power' => '${sysmonFixed(e['value'])} energi',
  'gpu' => sysmonPct(e['value'], d: 1),
  _ => sysmonPct(e['value'], d: 1),
};

/// One line per resource: "RAM: claude 2,5 GB".
Widget sysTopSummary(BuildContext context, SysCtx c) {
  final g = context.ghina;
  final top = c.top;
  return SysCard(
    title: 'Pemakan terbesar',
    icon: Icons.local_fire_department_rounded,
    color: GhinaColors.red,
    sub: 'Per aplikasi, digabung semua prosesnya',
    child: Column(
      children: [
        for (final k in ['ram', 'cpu', 'net', 'gpu', 'power'])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(_topMeta[k]!.$2, size: 16, color: _topMeta[k]!.$3.base),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    _topMeta[k]!.$1,
                    style: GhinaType.caption
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
                Expanded(
                  child: sysList(top[k]).isEmpty
                      ? Text(
                          k == 'power' ? 'diukur tiap 5 mnt…' : 'mengukur…',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        )
                      : Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${sysMap(sysList(top[k]).first)['name']} ',
                                style: GhinaType.bodyS
                                    .w(900)
                                    .copyWith(color: g.textPrimary),
                              ),
                              TextSpan(
                                text: sysTopValue(
                                  k,
                                  sysMap(sysList(top[k]).first),
                                ),
                                style: GhinaType.bodyS
                                    .w(700)
                                    .copyWith(color: _topMeta[k]!.$3.base),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Top-5 apps for one resource, with relative bars.
Widget sysTopCard(BuildContext context, SysCtx c, String key) {
  final g = context.ghina;
  final m = _topMeta[key]!;
  if (key == 'disk') {
    return SysCard(
      title: 'Pemakan disk terbesar',
      icon: m.$2,
      color: m.$3,
      child: Text(
        'macOS tidak memberi I/O disk per proses tanpa sudo (fs_usage/iotop), jadi daftar ini tidak tersedia.',
        style: GhinaType.caption.copyWith(color: g.textMuted),
      ),
    );
  }
  final rows = sysList(c.top[key]).whereType<Map>().toList();
  final max = rows.fold<double>(
    0,
    (a, e) => (sysNum(e['value']) ?? 0) > a ? sysNum(e['value'])! : a,
  );
  return SysCard(
    title: 'Pemakan ${m.$1} terbesar',
    icon: m.$2,
    color: m.$3,
    sub: switch (key) {
      'cpu' => '100% = 1 core penuh',
      'net' => 'per aplikasi, dari nettop tiap 10 dtk',
      'gpu' => '% waktu GPU',
      'power' => 'energy impact macOS, tiap 5 mnt',
      _ => null,
    },
    child: rows.isEmpty
        ? Text(
            'Mengukur…',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          )
        : Column(
            children: [
              for (final (i, e) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text(
                              '${i + 1}',
                              style: GhinaType.caption
                                  .w(900)
                                  .copyWith(color: g.textMuted),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${e['name']}${(sysNum(e['n']) ?? 1) > 1 ? '  ×${e['n']}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.bodyS
                                  .w(800)
                                  .copyWith(color: g.textPrimary),
                            ),
                          ),
                          Text(
                            sysTopValue(key, e),
                            style: GhinaType.caption
                                .w(900)
                                .copyWith(color: g.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: SysMeter(
                          value: max <= 0 ? 0 : (sysNum(e['value']) ?? 0) / max,
                          color: m.$3.base,
                          height: 5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}
