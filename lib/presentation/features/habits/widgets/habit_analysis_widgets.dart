import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../habit_format.dart';
import 'habit_insight_widgets.dart';

/// Wording of the analysis: a quit habit has relapses and clean days, a build
/// habit has missed and met days.
class AnalysisWords {
  const AnalysisWords(this.quit);
  final bool quit;

  String get lapse => quit ? 'kambuh' : 'terlewat';
  String get lapseCap => quit ? 'Kambuh' : 'Terlewat';
  String get ok => quit ? 'bersih' : 'terpenuhi';
  String get okCap => quit ? 'Bersih' : 'Terpenuhi';
}

const _weekdayOrder = [
  ('mon', 'Sen'),
  ('tue', 'Sel'),
  ('wed', 'Rab'),
  ('thu', 'Kam'),
  ('fri', 'Jum'),
  ('sat', 'Sab'),
  ('sun', 'Min'),
];

const _timeOrder = [
  ('night', 'Dini hari'),
  ('morning', 'Pagi'),
  ('afternoon', 'Siang'),
  ('evening', 'Malam'),
  ('unknown', 'Tanpa jam'),
];

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// `2026-08` -> `Agu`.
String analysisMonthLabel(String ym) {
  final m = int.tryParse(ym.length >= 7 ? ym.substring(5, 7) : '');
  return m == null || m < 1 || m > 12 ? ym : _monthShort[m - 1];
}

/// `21:00` -> `21.00`.
String analysisClock(String hm) => hm.replaceFirst(':', '.');

String _pct(double share) => '${(share * 100).round()}%';

String _num(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

/// Card with a small overline title.
class AnalysisSection extends StatelessWidget {
  const AnalysisSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(title: title, subtitle: subtitle),
      ChunkyCard(child: child),
      GhinaSpace.gapMd,
    ],
  );
}

class AnalysisSummary extends StatelessWidget {
  const AnalysisSummary({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final w = AnalysisWords(a.isQuit);
    final unit = a.unit == 'week' ? 'minggu' : 'hari';
    final g = context.ghina;
    return AnalysisSection(
      title: 'Ringkasan',
      subtitle: a.from.isEmpty ? null : '${a.from} – ${a.to}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  key: const ValueKey('analysis-current'),
                  icon: Icons.local_fire_department_rounded,
                  value: '${a.current} $unit',
                  label: 'Sekarang',
                  color: GhinaColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  key: const ValueKey('analysis-longest'),
                  icon: Icons.emoji_events_rounded,
                  value: '${a.longest} $unit',
                  label: 'Terpanjang',
                  color: GhinaColors.yellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            a.lastRelapse == null
                ? 'Belum ada hari ${w.lapse} di rentang ini.'
                : 'Terakhir ${w.lapse}: ${habitLongDate(a.lastRelapse!)}',
            key: const ValueKey('analysis-last'),
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ],
      ),
    );
  }
}

class AnalysisRuns extends StatelessWidget {
  const AnalysisRuns({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final g = context.ghina;
    final w = AnalysisWords(a.isQuit);
    if (a.runCount == 0 && a.recentRuns.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnalysisSection(
      title: 'Rentetan ${w.ok}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.runCount} rentetan'
            '${a.longestRun == null ? '' : ' · terpanjang ${a.longestRun!.days} hari'}',
            key: const ValueKey('analysis-runs'),
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
          for (final r in a.recentRuns)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.start} → ${r.end}',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ),
                  Text(
                    '${r.days} hari${r.ongoing ? ' · berlangsung' : ''}',
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(
                          color: r.ongoing
                              ? GhinaColors.green.base
                              : g.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AnalysisPerMonth extends StatelessWidget {
  const AnalysisPerMonth({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a.perMonth.isEmpty) return const SizedBox.shrink();
    final w = AnalysisWords(a.isQuit);
    final keys = a.perMonth.keys.toList();
    return AnalysisSection(
      title: '${w.lapseCap} per bulan',
      subtitle: '${a.relapseTotal}× di ${a.relapseDays} hari',
      child: MiniBars(
        key: const ValueKey('analysis-per-month'),
        values: [for (final k in keys) a.perMonth[k]!],
        labels: [for (final k in keys) analysisMonthLabel(k)],
        color: GhinaColors.red,
      ),
    );
  }
}

class AnalysisTriggers extends StatelessWidget {
  const AnalysisTriggers({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a.triggers.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    return AnalysisSection(
      title: 'Pemicu terbanyak',
      child: Column(
        children: [
          for (final t in a.triggers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.tag,
                          style: GhinaType.body
                              .w(800)
                              .copyWith(color: g.textPrimary),
                        ),
                      ),
                      Text(
                        '${t.count}× · ${_pct(t.share)}',
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ChunkyProgressBar(
                    value: t.share.clamp(0.0, 1.0),
                    color: GhinaColors.purple,
                    height: 8,
                    animate: false,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AnalysisDistributions extends StatelessWidget {
  const AnalysisDistributions({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final w = AnalysisWords(a.isQuit);
    final children = <Widget>[];
    if (a.timeOfDay.values.any((v) => v > 0)) {
      children.add(
        AnalysisSection(
          title: 'Jam ${w.lapse}',
          child: MiniBars(
            key: const ValueKey('analysis-time'),
            values: [for (final (k, _) in _timeOrder) a.timeOfDay[k] ?? 0],
            labels: [for (final (_, l) in _timeOrder) l],
            color: GhinaColors.blue,
          ),
        ),
      );
    }
    if (a.weekday.values.any((v) => v > 0)) {
      children.add(
        AnalysisSection(
          title: 'Hari ${w.lapse}',
          child: MiniBars(
            key: const ValueKey('analysis-weekday'),
            values: [for (final (k, _) in _weekdayOrder) a.weekday[k] ?? 0],
            labels: [for (final (_, l) in _weekdayOrder) l],
            color: GhinaColors.orange,
          ),
        ),
      );
    }
    return Column(children: children);
  }
}

class AnalysisRiskWindows extends StatelessWidget {
  const AnalysisRiskWindows({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a.riskWindows.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    return AnalysisSection(
      title: 'Jam rawan',
      subtitle: 'Waktu yang paling sering bikin goyah',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in a.riskWindows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${analysisClock(r.from)}–${analysisClock(r.to)} · ${r.count}× · ${_pct(r.share)}',
                style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

String _side(HabitDimensionStat d, HabitDimensionAgg? s) {
  if (s == null || s.n == 0) return '—';
  if (s.avg != null) return 'rata-rata ${_num(s.avg!)}';
  if (s.trueShare != null) return 'ya ${_pct(s.trueShare!)}';
  final o = s.options;
  if (o != null && o.isNotEmpty) {
    final top = o.entries.reduce((x, y) => y.value > x.value ? y : x);
    return '${top.key} (${top.value}×)';
  }
  return '${s.n}×';
}

class AnalysisDimensions extends StatelessWidget {
  const AnalysisDimensions({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a.dimensions.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    final w = AnalysisWords(a.isQuit);
    return AnalysisSection(
      title: 'Perbandingan dimensi',
      subtitle: 'Hari ${w.lapse} vs hari ${w.ok}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final d in a.dimensions)
            Padding(
              key: ValueKey('analysis-dim-${d.key}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.label,
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                  if (!d.comparable)
                    Text(
                      'belum bisa dibandingkan',
                      style: GhinaType.bodyS.copyWith(color: g.textMuted),
                    )
                  else ...[
                    Text(
                      'Hari ${w.lapse}: ${_side(d, d.lapse)}',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                    Text(
                      'Hari ${w.ok}: ${_side(d, d.ok)}',
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AnalysisEvents extends StatelessWidget {
  const AnalysisEvents({super.key, required this.analysis});

  final HabitAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a.lastEvents.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    return AnalysisSection(
      title: 'Kejadian terakhir',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in a.lastEvents)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.date} · ${e.label}',
                    style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                  ),
                  if (e.note != null)
                    Text(
                      e.note!,
                      style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
