import 'package:flutter/material.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../notification_log_format.dart';

/// Totals of the current filter + a 14-day activity strip. Tapping a bar
/// narrows the log to that day.
class LogOverviewCard extends StatelessWidget {
  const LogOverviewCard({
    super.key,
    required this.total,
    required this.apps,
    required this.days,
    required this.from,
    required this.to,
    required this.onPickDay,
    this.today,
  });

  /// Entries under the filter.
  final int total;

  /// Apps under the filter.
  final int apps;

  /// Entries per day under the filter *without* its date range, so the
  /// strip keeps context while a day is picked.
  final List<NotificationDayCount> days;

  /// The filter's range (highlighted bars); null = open-ended.
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime> onPickDay;
  final DateTime? today;

  static const span = 14;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final t = startOfDay(today ?? DateTime.now());
    final end = to == null ? t : startOfDay(to!);
    final counts = {for (final d in days) startOfDay(d.day): d.count};
    final strip = [
      for (var i = span - 1; i >= 0; i--) end.subtract(Duration(days: i)),
    ];
    final peak = strip.fold<int>(
      1,
      (m, d) => (counts[d] ?? 0) > m ? counts[d]! : m,
    );
    bool inRange(DateTime d) =>
        (from == null || !d.isBefore(startOfDay(from!))) &&
        (to == null || !d.isAfter(startOfDay(to!)));
    return ChunkyCard(
      key: const ValueKey('notif-overview'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.number(total),
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'notifikasi · $apps aplikasi',
                    maxLines: 2,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in strip)
                  Expanded(
                    child: _Bar(
                      day: d,
                      count: counts[d] ?? 0,
                      fraction: (counts[d] ?? 0) / peak,
                      active: inRange(d),
                      isToday: d == t,
                      onTap: () => onPickDay(d),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                Fmt.relativeDay(strip.first, now: t),
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
              Expanded(
                child: Text(
                  'Ketuk batang untuk lihat harinya',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
              Text(
                Fmt.relativeDay(strip.last, now: t),
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.count,
    required this.fraction,
    required this.active,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final int count;
  final double fraction;
  final bool active;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final color = active ? GhinaColors.blue.base : g.border;
    return Semantics(
      button: true,
      label: '${Fmt.relativeDay(day)}: $count notifikasi',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: GhinaMotion.medium,
              curve: GhinaMotion.pop,
              height: count == 0 ? 4 : 6 + 50 * fraction,
              decoration: BoxDecoration(
                color: count == 0 ? g.border.withValues(alpha: 0.5) : color,
                borderRadius: BorderRadius.circular(4),
                border: isToday
                    ? Border.all(color: GhinaColors.blue.edge, width: 2)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky-looking day separator in the timeline: `Hari ini · 42`.
class LogDayHeader extends StatelessWidget {
  const LogDayHeader({super.key, required this.day, this.count, this.today});

  final DateTime day;

  /// Entries that day under the filter (may exceed the loaded rows).
  final int? count;

  /// "Today" for the Hari ini / Kemarin label (tests pin it); null = now.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rel = Fmt.relativeDay(day, now: today);
    final label = rel == 'Hari ini' || rel == 'Kemarin'
        ? '$rel · ${Fmt.dateShortWeekday(day)}'
        : Fmt.dateFull(day);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: GhinaType.caption.w(900).copyWith(color: g.textSecondary),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            ChunkyPill(
              label: Fmt.number(count!),
              color: GhinaColors.blue,
              soft: true,
              uppercase: false,
            ),
          ],
          const SizedBox(width: 8),
          Expanded(child: Divider(color: g.border, thickness: 2)),
        ],
      ),
    );
  }
}

/// One app in the "Per aplikasi" view: count, share of the filter, newest
/// entry.
class LogAppCard extends StatelessWidget {
  const LogAppCard({
    super.key,
    required this.source,
    required this.total,
    required this.onTap,
    required this.onLongPress,
  });

  final NotificationSource source;
  final int total;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = source;
    final share = total == 0 ? 0.0 : s.count / total;
    final sw = appSwatch(s.packageName);
    return ChunkyCard(
      key: ValueKey('notif-app-${s.packageName}'),
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      borderRadius: GhinaRadii.rLg,
      child: Row(
        children: [
          AppInitialAvatar(
            packageName: s.packageName,
            label: s.displayAppName,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.displayAppName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Fmt.number(s.count),
                      style: GhinaType.body.w(900).copyWith(color: sw.base),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0),
                    minHeight: 6,
                    color: sw.base,
                    backgroundColor: g.surfaceAlt,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%',
                    if (s.lastPostedAt != null)
                      'terakhir ${notificationTimeLabel(s.lastPostedAt!)}',
                  ].join(' · '),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}
