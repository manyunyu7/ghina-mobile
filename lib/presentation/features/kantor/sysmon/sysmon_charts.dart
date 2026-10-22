import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'sysmon_data.dart';

/// CustomPainter visuals for "Performa PC". Everything repaints only when its
/// inputs change; animations are short tweens triggered by new values, so
/// nothing ticks while the data is still.

const _anim = Duration(milliseconds: 450);

TextPainter _tp(String s, TextStyle st, {double maxW = 200}) => TextPainter(
  text: TextSpan(text: s, style: st),
  textDirection: TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: maxW);

/* ---------------- radial gauge / ring ---------------- */

/// 270° gauge (or a full ring with [full]) that tweens to [value] (0–100).
class SysGauge extends StatelessWidget {
  const SysGauge({
    super.key,
    required this.value,
    required this.color,
    required this.center,
    this.label,
    this.sub,
    this.size = 108,
    this.full = false,
    this.stroke = 11,
  });

  final double? value;
  final Color color;
  final String center;
  final String? label;
  final String? sub;
  final double size;
  final bool full;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final v = (value ?? 0).clamp(0, 100).toDouble();
    return Semantics(
      label: '${label ?? ''} $center',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: v),
          duration: _anim,
          curve: GhinaMotion.standard,
          builder: (_, a, child) => CustomPaint(
            painter: _GaugePainter(a, color, g.surfaceAlt, full, stroke),
            child: child,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(stroke + 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text(
                      center,
                      style: GhinaType.h3
                          .w(900)
                          .copyWith(color: g.textPrimary, height: 1.05),
                    ),
                  ),
                  if (label != null)
                    Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption
                          .w(800)
                          .copyWith(color: g.textSecondary, fontSize: 11),
                    ),
                  if (sub != null)
                    Text(
                      sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(
                        color: g.textMuted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.v, this.color, this.track, this.full, this.stroke);
  final double v;
  final Color color, track;
  final bool full;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final start = full ? -math.pi / 2 : math.pi * 0.75;
    final sweep = full ? math.pi * 2 : math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(r, start, sweep, false, base);
    if (v <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [color.withValues(alpha: 0.55), color],
        transform: GradientRotation(start),
      ).createShader(r);
    canvas.drawArc(r, start, sweep * v / 100, false, fg);
    if (!full) {
      // ticks every 25%
      final c = r.center, rad = r.width / 2;
      final tick = Paint()
        ..color = track.withValues(alpha: 1)
        ..strokeWidth = 1.5;
      for (var i = 0; i <= 4; i++) {
        final a = start + sweep * i / 4;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * (rad + stroke / 2 + 1),
          c + Offset(math.cos(a), math.sin(a)) * (rad + stroke / 2 + 4),
          tick,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.v != v || o.color != color || o.track != track;
}

/* ---------------- area line chart with scrub ---------------- */

class SysLine {
  const SysLine(
    this.key,
    this.label,
    this.color, {
    this.fill = true,
    this.dashed = false,
  });
  final String key;
  final String label;
  final Color color;
  final bool fill;
  final bool dashed;
}

/// Multi-series area chart: gradient fill, grid, Y/X labels, legend and a
/// touch-scrub tooltip. [max] null = auto-scale to the data.
class SysAreaChart extends StatefulWidget {
  const SysAreaChart({
    super.key,
    required this.data,
    required this.lines,
    required this.fmt,
    this.max,
    this.height = 150,
    this.stacked = false,
  });

  final SysSeries data;
  final List<SysLine> lines;
  final String Function(double v) fmt;
  final double? max;
  final double height;
  final bool stacked;

  @override
  State<SysAreaChart> createState() => _SysAreaChartState();
}

class _SysAreaChartState extends State<SysAreaChart> {
  int? _scrub;

  void _at(Offset p, double w) {
    final n = widget.data.t.length;
    if (n < 2) return;
    const left = 40.0;
    final x = ((p.dx - left) / (w - left)).clamp(0.0, 1.0);
    final i = (x * (n - 1)).round();
    if (i != _scrub) setState(() => _scrub = i);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (_, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _at(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _at(d.localPosition, c.maxWidth),
            onHorizontalDragEnd: (_) => setState(() => _scrub = null),
            onTapDown: (d) => _at(d.localPosition, c.maxWidth),
            onTapUp: (_) => Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _scrub = null);
            }),
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _AreaPainter(
                    data: widget.data,
                    lines: widget.lines,
                    fmt: widget.fmt,
                    max: widget.max,
                    scrub: _scrub,
                    grid: g.border,
                    label: g.textMuted,
                    tipBg: g.isDark ? g.surfaceAlt : GhinaColors.ink,
                    tipFg: g.isDark ? g.textPrimary : Colors.white,
                    stacked: widget.stacked,
                    version: widget.data.t.isEmpty
                        ? 0
                        : widget.data.t.last ^ widget.data.t.length,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.lines.length > 1) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final l in widget.lines)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: l.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.label,
                      style: GhinaType.caption
                          .w(700)
                          .copyWith(color: g.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.data,
    required this.lines,
    required this.fmt,
    required this.max,
    required this.scrub,
    required this.grid,
    required this.label,
    required this.tipBg,
    required this.tipFg,
    required this.stacked,
    required this.version,
  });

  final SysSeries data;
  final List<SysLine> lines;
  final String Function(double) fmt;
  final double? max;
  final int? scrub;
  final Color grid, label, tipBg, tipFg;
  final bool stacked;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 16.0, top = 4.0;
    final w = size.width - left, h = size.height - bottom - top;
    final n = data.t.length;
    final ls = TextStyle(
      color: label,
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );
    // values (stacked = cumulative)
    final vals = <List<double?>>[];
    for (var j = 0; j < lines.length; j++) {
      final src = data[lines[j].key];
      vals.add([
        for (var i = 0; i < n; i++)
          (i < src.length ? src[i] : null) == null
              ? null
              : src[i]! + (stacked && j > 0 ? (vals[j - 1][i] ?? 0) : 0),
      ]);
    }
    var top0 = max ?? 0;
    if (max == null) {
      for (final l in vals) {
        for (final v in l) {
          if (v != null && v > top0) top0 = v;
        }
      }
      top0 = _nice(top0 <= 0 ? 1 : top0 * 1.1);
    }
    final gp = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final y = top + h - h * k / 4;
      _dash(canvas, Offset(left, y), Offset(size.width, y), gp);
      final t = _tp(fmt(top0 * k / 4), ls, maxW: left - 4);
      t.paint(canvas, Offset(left - 4 - t.width, y - t.height / 2));
    }
    if (n < 2) {
      final t = _tp('Mengumpulkan data…', ls);
      t.paint(canvas, Offset(left + (w - t.width) / 2, top + h / 2 - 6));
      return;
    }
    // x labels
    for (final f in [0.0, 0.5, 1.0]) {
      final i = ((n - 1) * f).round();
      final t = _tp(sysmonClock(data.t[i]), ls);
      final x = left + w * f;
      t.paint(
        canvas,
        Offset(
          (x - t.width / 2).clamp(left, size.width - t.width),
          size.height - t.height,
        ),
      );
    }
    double xi(int i) => left + w * i / (n - 1);
    double yv(double v) => top + h - (v / top0).clamp(0.0, 1.0) * h;
    for (var j = lines.length - 1; j >= 0; j--) {
      final l = lines[j], v = vals[j];
      final path = Path(), fill = Path();
      var open = false;
      double? fx;
      double lx = 0;
      for (var i = 0; i < n; i++) {
        if (v[i] == null) {
          if (open && l.fill) {
            fill
              ..lineTo(lx, top + h)
              ..lineTo(fx!, top + h)
              ..close();
          }
          open = false;
          continue;
        }
        final x = xi(i), y = yv(v[i]!);
        if (!open) {
          path.moveTo(x, y);
          fill.moveTo(x, top + h);
          fill.lineTo(x, y);
          fx = x;
          open = true;
        } else {
          path.lineTo(x, y);
          fill.lineTo(x, y);
        }
        lx = x;
      }
      if (open && l.fill) {
        fill
          ..lineTo(lx, top + h)
          ..lineTo(fx!, top + h)
          ..close();
      }
      if (l.fill) {
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                l.color.withValues(alpha: stacked ? 0.55 : 0.32),
                l.color.withValues(alpha: 0.02),
              ],
            ).createShader(Rect.fromLTWH(left, top, w, h)),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    // last value dots
    for (var j = 0; j < lines.length; j++) {
      final v = vals[j].last;
      if (v != null) {
        canvas.drawCircle(
          Offset(xi(n - 1), yv(v)),
          3,
          Paint()..color = lines[j].color,
        );
      }
    }
    final s = scrub;
    if (s != null && s < n) {
      final x = xi(s);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + h),
        Paint()
          ..color = label
          ..strokeWidth = 1,
      );
      final rows = <(Color, String)>[];
      for (var j = 0; j < lines.length; j++) {
        final raw = data[lines[j].key];
        final v = s < raw.length ? raw[s] : null;
        if (vals[j][s] != null) {
          canvas.drawCircle(
            Offset(x, yv(vals[j][s]!)),
            4.5,
            Paint()..color = lines[j].color,
          );
          canvas.drawCircle(
            Offset(x, yv(vals[j][s]!)),
            2,
            Paint()..color = tipFg,
          );
        }
        rows.add((
          lines[j].color,
          '${lines[j].label}: ${v == null ? '–' : fmt(v)}',
        ));
      }
      final ts = TextStyle(
        color: tipFg,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      );
      final head = _tp(
        sysmonClock(data.t[s], seconds: data.step < 60),
        ts.copyWith(fontWeight: FontWeight.w900),
      );
      final tps = [for (final r in rows) _tp(r.$2, ts, maxW: 180)];
      final bw =
          [head.width, ...tps.map((t) => t.width + 12)].reduce(math.max) + 16;
      final bh =
          head.height + tps.fold<double>(0, (a, t) => a + t.height + 2) + 12;
      var bx = x + 10;
      if (bx + bw > size.width) bx = x - 10 - bw;
      bx = bx.clamp(0, size.width - bw);
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, top + 2, bw, bh),
        const Radius.circular(10),
      );
      canvas.drawRRect(rr, Paint()..color = tipBg.withValues(alpha: 0.94));
      var y = top + 8;
      head.paint(canvas, Offset(bx + 8, y));
      y += head.height + 2;
      for (var k = 0; k < tps.length; k++) {
        canvas.drawCircle(
          Offset(bx + 12, y + tps[k].height / 2),
          3.5,
          Paint()..color = rows[k].$1,
        );
        tps[k].paint(canvas, Offset(bx + 20, y));
        y += tps[k].height + 2;
      }
    }
  }

  static double _nice(double v) {
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (m * e >= v) return m * e;
    }
    return 10 * e;
  }

  static void _dash(Canvas c, Offset a, Offset b, Paint p) {
    const d = 3.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      c.drawLine(Offset(x, a.dy), Offset(math.min(x + d, b.dx), a.dy), p);
      x += d + gap;
    }
  }

  @override
  bool shouldRepaint(_AreaPainter o) =>
      o.version != version ||
      o.scrub != scrub ||
      o.max != max ||
      o.grid != grid ||
      o.lines.length != lines.length ||
      o.data != data;
}

/* ---------------- stacked bar ---------------- */

class SysSeg {
  const SysSeg(this.label, this.value, this.color, {this.detail});
  final String label;
  final double value;
  final Color color;
  final String? detail;
}

/// Horizontal stacked bar (memory breakdown) with an animated fill and legend.
class SysStackedBar extends StatelessWidget {
  const SysStackedBar({
    super.key,
    required this.segs,
    required this.total,
    this.height = 26,
    this.fmt,
  });
  final List<SysSeg> segs;
  final double total;
  final double height;
  final String Function(double)? fmt;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: GhinaRadii.rSm,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: _anim,
              builder: (_, a, _) => CustomPaint(
                painter: _StackPainter(segs, total, g.surfaceAlt, a),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final s in segs)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${s.label} ',
                          style: GhinaType.caption
                              .w(700)
                              .copyWith(color: g.textSecondary),
                        ),
                        TextSpan(
                          text: s.detail ?? fmt?.call(s.value) ?? '',
                          style: GhinaType.caption
                              .w(900)
                              .copyWith(color: g.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.segs, this.total, this.track, this.a);
  final List<SysSeg> segs;
  final double total, a;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (total <= 0) return;
    var x = 0.0;
    for (final s in segs) {
      final w = size.width * (s.value / total).clamp(0.0, 1.0) * a;
      if (w <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, size.height),
        Paint()..color = s.color,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, size.height * 0.62, w, size.height * 0.38),
        Paint()..color = Colors.black.withValues(alpha: 0.08),
      );
      x += w;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = track
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_StackPainter o) => true;
}

/* ---------------- per-core heatmap ---------------- */

/// Rows = cores (P/E labelled), columns = time buckets, color = load.
class SysCoreHeatmap extends StatelessWidget {
  const SysCoreHeatmap({
    super.key,
    required this.data,
    required this.cores,
    this.levels = const [],
    this.cols = 48,
  });
  final SysSeries data;
  final List<double> cores;
  final List<Map> levels;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final n = cores.length;
    final kinds = <String>[];
    for (final l in levels) {
      for (var i = 0; i < (sysNum(l['cores']) ?? 0); i++) {
        kinds.add('${l['kind'] ?? ''}');
      }
    }
    return SizedBox(
      height: n * 15.0 + 4,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HeatPainter(
            data,
            cores,
            kinds,
            cols,
            g.surfaceAlt,
            g.textMuted,
            data.t.isEmpty ? 0 : data.t.last ^ data.t.length,
          ),
        ),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(
    this.data,
    this.cores,
    this.kinds,
    this.cols,
    this.track,
    this.label,
    this.version,
  );
  final SysSeries data;
  final List<double> cores;
  final List<String> kinds;
  final int cols;
  final Color track, label;
  final int version;

  static Color heat(double v) {
    final t = (v / 100).clamp(0.0, 1.0);
    if (t < 0.5) {
      return Color.lerp(
        GhinaColors.green.base,
        GhinaColors.yellow.base,
        t * 2,
      )!;
    }
    return Color.lerp(
      GhinaColors.yellow.base,
      GhinaColors.red.base,
      (t - 0.5) * 2,
    )!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const lw = 30.0, bw = 56.0, rowH = 15.0;
    final n = cores.length, t = data.t.length;
    final ls = TextStyle(
      color: label,
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
    );
    final hw = size.width - lw - bw - 6;
    final per = t == 0 ? 1 : (t / cols).ceil();
    final cw = hw / cols;
    for (var r = 0; r < n; r++) {
      final y = r * rowH + 2;
      final k = r < kinds.length ? kinds[r] : '';
      _tp('$k${r + 1}', ls).paint(canvas, Offset(0, y));
      final s = data['c$r'];
      final nb = (t / per).ceil();
      for (var c = 0; c < cols; c++) {
        final b = c - (cols - nb);
        final rect = Rect.fromLTWH(lw + c * cw, y, cw - 1, rowH - 3);
        if (b < 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            Paint()..color = track,
          );
          continue;
        }
        double sum = 0;
        var cnt = 0;
        for (var i = b * per; i < math.min(t, (b + 1) * per); i++) {
          final v = i < s.length ? s[i] : null;
          if (v != null) {
            sum += v;
            cnt++;
          }
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color = cnt == 0
                ? track
                : heat(sum / cnt).withValues(
                    alpha: 0.25 + 0.75 * (sum / cnt / 100).clamp(0.0, 1.0),
                  ),
        );
      }
      // current bar
      final bx = size.width - bw;
      final br = Rect.fromLTWH(bx, y, bw - 22, rowH - 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(br, const Radius.circular(3)),
        Paint()..color = track,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            bx,
            y,
            (bw - 22) * (cores[r] / 100).clamp(0.0, 1.0),
            rowH - 3,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = heat(cores[r]),
      );
      final tt = _tp('${cores[r].round()}', ls);
      tt.paint(canvas, Offset(size.width - tt.width, y));
    }
  }

  @override
  bool shouldRepaint(_HeatPainter o) =>
      o.version != version || o.track != track || o.cores != cores;
}

/* ---------------- donut ---------------- */

class SysDonut extends StatelessWidget {
  const SysDonut({
    super.key,
    required this.segs,
    required this.center,
    this.sub,
    this.size = 120,
  });
  final List<SysSeg> segs;
  final String center;
  final String? sub;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _anim,
        curve: GhinaMotion.standard,
        builder: (_, a, child) => CustomPaint(
          painter: _DonutPainter(segs, a, g.surfaceAlt),
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                center,
                style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: GhinaType.caption.copyWith(
                    color: g.textMuted,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segs, this.a, this.track);
  final List<SysSeg> segs;
  final double a;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const sw = 16.0;
    final r = Rect.fromLTWH(sw / 2, sw / 2, size.width - sw, size.height - sw);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = track,
    );
    final tot = segs.fold<double>(0, (s, e) => s + e.value);
    if (tot <= 0) return;
    var st = -math.pi / 2;
    for (final s in segs) {
      final sweep = math.pi * 2 * s.value / tot * a;
      if (sweep > 0.02) {
        canvas.drawArc(
          r,
          st + 0.02,
          sweep - 0.04,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..color = s.color,
        );
      }
      st += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => true;
}

/* ---------------- battery illustration ---------------- */

class SysBattery extends StatelessWidget {
  const SysBattery({
    super.key,
    required this.pct,
    required this.charging,
    required this.ac,
    this.width = 150,
  });
  final double pct;
  final bool charging, ac;
  final double width;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = pct <= 10
        ? GhinaColors.red
        : pct <= 20
        ? GhinaColors.orange
        : GhinaColors.green;
    return SizedBox(
      width: width,
      height: width * 0.5,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: pct),
        duration: _anim,
        builder: (_, v, _) => CustomPaint(
          painter: _BattPainter(
            v,
            c.base,
            g.border,
            g.surfaceAlt,
            charging || ac,
            g.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _BattPainter extends CustomPainter {
  _BattPainter(this.v, this.color, this.edge, this.track, this.bolt, this.text);
  final double v;
  final Color color, edge, track, text;
  final bool bolt;

  @override
  void paint(Canvas canvas, Size size) {
    final cap = size.width * 0.06;
    final body = Rect.fromLTWH(2, 2, size.width - cap - 6, size.height - 4);
    final rr = RRect.fromRectAndRadius(
      body,
      Radius.circular(size.height * 0.18),
    );
    canvas.drawRRect(rr, Paint()..color = track);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = edge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.right + 2,
          size.height * 0.33,
          cap,
          size.height * 0.34,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = edge,
    );
    final inner = body.deflate(7);
    final fw = inner.width * (v / 100).clamp(0.0, 1.0);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(inner.left, inner.top, fw, inner.height),
      Radius.circular(size.height * 0.1),
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.25)!, color],
        ).createShader(inner),
    );
    final t = _tp(
      '${v.round()}%',
      TextStyle(
        color: text,
        fontSize: size.height * 0.3,
        fontWeight: FontWeight.w900,
      ),
    );
    t.paint(
      canvas,
      body.center - Offset(t.width / 2 - (bolt ? 9 : 0), t.height / 2),
    );
    if (bolt) {
      final cx = body.center.dx - t.width / 2 - 6,
          cy = body.center.dy,
          s = size.height * 0.2;
      final p = Path()
        ..moveTo(cx + s * 0.2, cy - s)
        ..lineTo(cx - s * 0.5, cy + s * 0.1)
        ..lineTo(cx, cy + s * 0.1)
        ..lineTo(cx - s * 0.2, cy + s)
        ..lineTo(cx + s * 0.5, cy - s * 0.1)
        ..lineTo(cx, cy - s * 0.1)
        ..close();
      canvas.drawPath(p, Paint()..color = GhinaColors.yellow.base);
    }
  }

  @override
  bool shouldRepaint(_BattPainter o) =>
      o.v != v || o.color != color || o.bolt != bolt || o.edge != edge;
}

/* ---------------- tiny sparkline (process rows, tiles) ---------------- */

class SysSpark extends StatelessWidget {
  const SysSpark({
    super.key,
    required this.values,
    required this.color,
    this.max,
    this.height = 28,
  });
  final List<double?> values;
  final Color color;
  final double? max;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: RepaintBoundary(
      child: CustomPaint(painter: _SparkPainter(values, color, max)),
    ),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color, this.max);
  final List<double?> v;
  final Color color;
  final double? max;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final x in v) x ?? 0.0];
    if (pts.length < 2) return;
    final top = max ?? math.max(1.0, pts.reduce(math.max));
    final dx = size.width / (pts.length - 1);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final y = size.height - (pts[i] / top).clamp(0.0, 1.0) * size.height;
      i == 0 ? path.moveTo(0, y) : path.lineTo(i * dx, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.v.length != v.length ||
      (v.isNotEmpty && o.v.last != v.last) ||
      o.color != color;
}

/// Small meter bar (process rows, disks).
class SysMeter extends StatelessWidget {
  const SysMeter({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: g.surfaceAlt)),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0, 1).toDouble()),
              duration: _anim,
              curve: GhinaMotion.standard,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dot that pulses once whenever [beat] changes (no idle ticker).
class SysPulse extends StatelessWidget {
  const SysPulse({super.key, required this.beat, required this.color});
  final int beat;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(beat),
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 900),
    builder: (_, a, _) => SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8 + 10 * a,
            height: 8 + 10 * a,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.45 * (1 - a)),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    ),
  );
}
