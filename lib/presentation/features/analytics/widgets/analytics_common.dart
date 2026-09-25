import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/usecases/analytics_spending.dart';
import '../../../design_system/design_system.dart';

/// Every money string on the analytics pages that is not a [MoneyText]
/// (chart axes, tooltips, compact labels) goes through here, so amount
/// masking can hook in at one place.
/// Money for chart axes/tooltips/labels; masked when balances are hidden.
String aMoney(
  BuildContext context,
  num v,
  String currency, {
  bool compact = false,
}) => context.money(v, currency: currency, compact: compact);

/// `+12%` / `-8%` (no decimals above 10%).
String pctLabel(double pct, {bool signed = true}) {
  final a = pct.abs();
  final body = a >= 10 || a == 0
      ? a.toStringAsFixed(0)
      : a.toStringAsFixed(1).replaceAll('.', ',');
  if (!signed || pct == 0) return '$body%';
  return '${pct > 0 ? '+' : '-'}$body%';
}

/// Short date range: `1–30 Sep 2026`, `1 Jul – 30 Sep 2026`.
String rangeLabel(AnalyticsPeriod p) {
  final s = p.start, e = p.end;
  if (s.year == e.year && s.month == e.month) {
    if (s.day == e.day) return Fmt.date(s);
    return '${s.day}–${Fmt.date(e)}';
  }
  if (s.year == e.year) {
    return '${s.day} ${Fmt.monthShort(s.month)} – ${Fmt.date(e)}';
  }
  return '${Fmt.date(s)} – ${Fmt.date(e)}';
}

/// "Nice" axis step (1, 2, 2.5, 5 × 10^n).
double niceStep(double raw) {
  if (raw <= 0 || raw.isNaN || raw.isInfinite) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final n = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return n * exp;
}

/// A titled chart card.
class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.header,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  /// Small widget at the right of the title (e.g. a pill).
  final Widget? trailing;

  /// Controls under the title (segmented, legend…).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, color: g.textMuted, size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GhinaType.h3
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            if (header != null) ...[const SizedBox(height: 12), header!],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// A KPI tile: label, a money (or text) value and an optional note.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.currency,
    this.amount,
    this.text,
    this.tone = MoneyTone.neutral,
    this.note,
    this.noteColor,
    this.amountColor,
  });

  final String label;
  final IconData icon;
  final Color? amountColor;
  final ChunkySwatch color;
  final String currency;
  final num? amount;
  final String? text;
  final MoneyTone tone;
  final String? note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final style = GhinaType.moneyM.copyWith(fontSize: 18);
    return ChunkyCard(
      padding: const EdgeInsets.all(12),
      borderRadius: GhinaRadii.rLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: g.tint(color),
                  borderRadius: GhinaRadii.rSm,
                ),
                child: Icon(icon, size: 18, color: color.base),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(
                    color: g.textSecondary,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount != null
                ? MoneyText(
                    amount: amount,
                    currency: currency,
                    tone: tone,
                    style: style,
                    color: amountColor,
                  )
                : Text(
                    text ?? '–',
                    maxLines: 1,
                    style: style.copyWith(color: g.textPrimary),
                  ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(
                color: noteColor ?? g.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two tiles per row.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2)
        Padding(
          padding: EdgeInsets.only(
            bottom: i + 2 < children.length ? GhinaSpace.md : 0,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: GhinaSpace.md),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Muted one-liner for an empty chart.
class NoChartData extends StatelessWidget {
  const NoChartData(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
    ),
  );
}

/// A colored square + label.
class LegendDot extends StatelessWidget {
  const LegendDot({
    super.key,
    required this.label,
    required this.color,
    this.dashed = false,
  });
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dashed
            ? SizedBox(
                width: 16,
                height: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(width: 4, height: 2.5, color: color),
                  ],
                ),
              )
            : Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Change vs the previous period as a pill: red when spending went up,
/// green when it went down.
class DeltaPill extends StatelessWidget {
  const DeltaPill({super.key, required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final up = pct > 0.05;
    final down = pct < -0.05;
    return ChunkyPill(
      label: pctLabel(pct),
      soft: true,
      uppercase: false,
      icon: up
          ? Icons.trending_up_rounded
          : down
          ? Icons.trending_down_rounded
          : Icons.trending_flat_rounded,
      color: up
          ? GhinaColors.red
          : down
          ? GhinaColors.green
          : GhinaColors.gray,
    );
  }
}
