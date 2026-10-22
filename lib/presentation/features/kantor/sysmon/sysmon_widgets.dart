import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'sysmon_charts.dart';
import 'sysmon_data.dart';

/// Shared building blocks for the "Performa PC" tabs.

class SysCard extends StatelessWidget {
  const SysCard({
    super.key,
    required this.title,
    this.icon,
    this.color,
    this.trailing,
    this.sub,
    required this.child,
  });
  final String title;
  final IconData? icon;
  final ChunkySwatch? color;
  final Widget? trailing;
  final String? sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = color ?? GhinaColors.blue;
    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.tint(g.brightness),
                    borderRadius: GhinaRadii.rSm,
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: g.isDark ? c.base : c.edge,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GhinaType.body
                          .w(900)
                          .copyWith(color: g.textPrimary),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        style: GhinaType.caption.copyWith(color: g.textMuted),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: GhinaSpace.sm),
          child,
        ],
      ),
    );
  }
}

/// Label above a big value with an optional caption — absolute numbers first.
class SysStat extends StatelessWidget {
  const SysStat(this.label, this.value, {super.key, this.sub, this.color});
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: GhinaType.overline.copyWith(color: g.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GhinaType.body
              .w(900)
              .copyWith(
                color: color ?? g.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        if (sub != null)
          Text(
            sub!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(
              color: g.textSecondary,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

/// Grid of stats: 2 columns on phones, more when wide.
class SysStatGrid extends StatelessWidget {
  const SysStatGrid({super.key, required this.children, this.minWidth = 140});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final cols = (c.maxWidth / minWidth).floor().clamp(2, 4);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 12,
        children: [for (final x in children) SizedBox(width: w, child: x)],
      );
    },
  );
}

/// Page body: one column on phones, two on tablets.
class SysColumns extends StatelessWidget {
  const SysColumns({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      const gap = GhinaSpace.md;
      if (c.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final x in children)
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: x,
              ),
          ],
        );
      }
      final left = <Widget>[], right = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        (i.isEven ? left : right).add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: children[i],
          ),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: left,
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: right,
            ),
          ),
        ],
      );
    },
  );
}

class SysRangePicker extends StatelessWidget {
  const SysRangePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SysRange value;
  final ValueChanged<SysRange> onChanged;

  @override
  Widget build(BuildContext context) => ChunkySegmented<SysRange>(
    height: 38,
    segments: [
      for (final r in SysRange.values) ChunkySegment(value: r, label: r.label),
    ],
    value: value,
    onChanged: onChanged,
  );
}

class SysPill extends StatelessWidget {
  const SysPill(this.label, this.color, {super.key});
  final String label;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) =>
      ChunkyPill(label: label, color: color, soft: true, uppercase: false);
}

/// "14,6 GB / 16 GB" headline + caption.
class SysBig extends StatelessWidget {
  const SysBig({
    super.key,
    required this.main,
    required this.of,
    this.caption,
    this.color,
  });
  final String main, of;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: main,
                style: GhinaType.h1
                    .w(900)
                    .copyWith(color: color ?? g.textPrimary, height: 1.1),
              ),
              TextSpan(
                text: ' / $of',
                style: GhinaType.h3.w(800).copyWith(color: g.textMuted),
              ),
            ],
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: GhinaType.bodyS.w(700).copyWith(color: g.textSecondary),
          ),
      ],
    );
  }
}

/// RAM "terpakai / total" card with breakdown bar, used on Ringkasan and Memori.
class SysRamCard extends StatelessWidget {
  const SysRamCard({super.key, required this.mem, this.data});
  final Map mem;
  final SysSeries? data;

  @override
  Widget build(BuildContext context) {
    final total = sysNum(mem['total']) ?? 0, used = sysNum(mem['used']) ?? 0;
    final pct = sysNum(mem['pct']) ?? 0;
    final c = sysmonColor(pct);
    final swap = sysMap(mem['swap']);
    final pr = mem['pressure'];
    return SysCard(
      title: 'RAM',
      icon: Icons.memory_rounded,
      color: c,
      trailing: pr == null
          ? null
          : SysPill('tekanan $pr', sysmonLevelColor(pr)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SysBig(
            main: sysmonBytes(used),
            of: sysmonBytes(total),
            color: c.base,
            caption:
                'terpakai ${sysmonPct(pct, d: 1)} · sisa ${sysmonBytes(total - used)}',
          ),
          const SizedBox(height: 10),
          SysStackedBar(
            total: total,
            segs: memSegs(mem),
            fmt: (v) => sysmonBytes(v),
          ),
          if (swap.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Swap ${sysmonBytes(swap['used'])} dari ${sysmonBytes(swap['total'])} (sisa ${sysmonBytes(swap['free'])})',
              style: GhinaType.caption
                  .w(700)
                  .copyWith(color: context.ghina.textSecondary),
            ),
          ],
          if (data != null && !data!.isEmpty) ...[
            const SizedBox(height: 8),
            SysSpark(values: data!['ram'], color: c.base, max: 100, height: 34),
          ],
        ],
      ),
    );
  }
}

List<SysSeg> memSegs(Map mem) {
  final total = sysNum(mem['total']) ?? 0;
  final app = sysNum(mem['app']),
      wired = sysNum(mem['wired']),
      comp = sysNum(mem['compressed']);
  final cached = sysNum(mem['cached']);
  if (app == null) {
    final used = sysNum(mem['used']) ?? 0;
    return [
      SysSeg('Terpakai', used, GhinaColors.blue.base),
      SysSeg('Bebas', total - used, GhinaColors.gray.base),
    ];
  }
  final used = app + (wired ?? 0) + (comp ?? 0);
  final cach = (cached ?? 0)
      .clamp(0, (total - used).clamp(0, total))
      .toDouble();
  return [
    SysSeg('Aplikasi', app, GhinaColors.blue.base),
    SysSeg('Wired', wired ?? 0, GhinaColors.purple.base),
    SysSeg('Terkompresi', comp ?? 0, GhinaColors.orange.base),
    SysSeg('Cache', cach, GhinaColors.teal.base),
    SysSeg(
      'Bebas',
      (total - used - cach).clamp(0, total).toDouble(),
      GhinaColors.gray.base,
    ),
  ];
}

/// Collapsible chart card with a range picker.
class SysChartCard extends StatelessWidget {
  const SysChartCard({
    super.key,
    required this.title,
    required this.data,
    required this.lines,
    required this.fmt,
    this.max,
    this.icon,
    this.color,
    this.headline,
    this.stacked = false,
    this.height = 160,
  });
  final String title;
  final SysSeries data;
  final List<SysLine> lines;
  final String Function(double) fmt;
  final double? max;
  final IconData? icon;
  final ChunkySwatch? color;
  final String? headline;
  final bool stacked;
  final double height;

  @override
  Widget build(BuildContext context) => SysCard(
    title: title,
    icon: icon,
    color: color,
    trailing: headline == null
        ? null
        : Text(
            headline!,
            style: GhinaType.body
                .w(900)
                .copyWith(color: (color ?? GhinaColors.blue).base),
          ),
    child: SysAreaChart(
      data: data,
      lines: lines,
      fmt: fmt,
      max: max,
      height: height,
      stacked: stacked,
    ),
  );
}

String fmtPct(double v) => '${v.round()}%';
String fmtRate(double v) => sysmonBytes(v, rate: true).replaceAll('/dtk', '/d');
String fmtMB(double v) => sysmonBytes(v * 1048576);
String fmtNum(double v) => v >= 10 ? v.round().toString() : sysmonFixed(v, 1);
