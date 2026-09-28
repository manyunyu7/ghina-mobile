import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../state/prayer_reminders/prayer_reminder_providers.dart';
import 'prayer_visuals.dart';

/// "Jadwal sholat" card (top of the Sholat page and the reminder settings
/// preview): today's five times (or tomorrow / the day after), the next
/// prayer with a live countdown, the location and the reminder state.
class PrayerScheduleCard extends ConsumerStatefulWidget {
  const PrayerScheduleCard({super.key, this.showSettingsLink = true});

  /// Bell + "Aktifkan pengingat" (hidden on the settings page itself).
  final bool showSettingsLink;

  @override
  ConsumerState<PrayerScheduleCard> createState() => _PrayerScheduleCardState();
}

class _PrayerScheduleCardState extends ConsumerState<PrayerScheduleCard> {
  int _offset = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Countdown granularity is a minute; refresh a bit more often so it
    // flips right at the boundary.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final now = ref.watch(clockProvider).now();
    final today = startOfDay(now);
    final day = addDays(today, _offset);
    final settingsAsync = ref.watch(prayerReminderSettingsProvider);
    final settings = settingsAsync.value;
    final times = ref.watch(prayerTimesProvider(day));

    if (settings == null || times == null) {
      if (settingsAsync.hasError) return const SizedBox.shrink();
      return const ChunkyCard(
        key: ValueKey('prayer-schedule-loading'),
        child: SizedBox(height: 120),
      );
    }

    // Next prayer (today view only; after Isya it's tomorrow's Subuh).
    ({Prayer prayer, DateTime at})? next;
    if (_offset == 0) {
      final tomorrow = ref.watch(prayerTimesProvider(addDays(today, 1)));
      next = nextPrayerTime([times, ?tomorrow], now);
    }
    final highlight = next != null && isSameDay(next.at, day)
        ? next.prayer
        : null;
    final current = _offset == 0 ? currentPrayer(times, now) : null;

    const dayLabels = ['Hari ini', 'Besok', 'Lusa'];
    return ChunkyCard(
      key: const ValueKey('prayer-schedule'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.mosque_rounded, color: GhinaColors.green.base),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jadwal sholat',
                      style: GhinaType.body
                          .w(900)
                          .copyWith(color: g.textPrimary),
                    ),
                    Text(
                      '${settings.location.name} · terbit ${Fmt.time(times.sunrise)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                key: const ValueKey('prayer-schedule-day'),
                tooltip: 'Pilih hari',
                initialValue: _offset,
                onSelected: (v) => setState(() => _offset = v),
                itemBuilder: (_) => [
                  for (final (i, l) in dayLabels.indexed)
                    PopupMenuItem(
                      key: ValueKey('prayer-schedule-day-$i'),
                      value: i,
                      child: Text(
                        i == 0
                            ? l
                            : '$l · ${Fmt.dateShortWeekday(addDays(today, i))}',
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChunkyPill(
                    label: dayLabels[_offset],
                    icon: Icons.expand_more_rounded,
                    color: GhinaColors.blue,
                    soft: true,
                    uppercase: false,
                  ),
                ),
              ),
              if (widget.showSettingsLink)
                IconButton(
                  key: const ValueKey('prayer-reminder-bell'),
                  tooltip: settings.enabled
                      ? 'Reminder sholat aktif'
                      : 'Reminder sholat mati',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    settings.enabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                  ),
                  color: settings.enabled
                      ? GhinaColors.green.base
                      : g.textMuted,
                  onPressed: () => context.push('/prayers/reminders'),
                )
              else
                const SizedBox(width: 6),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Countdown(next: next, now: now),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                for (final p in Prayer.fardhu)
                  Expanded(
                    child: _TimeCell(
                      prayer: p,
                      time: times[p],
                      highlighted: p == highlight,
                      current: p == current,
                      muted: _offset == 0 && !times[p].isAfter(now),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.showSettingsLink && !settings.enabled)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: InkWell(
                key: const ValueKey('prayer-reminder-enable'),
                borderRadius: GhinaRadii.rMd,
                onTap: () => context.push('/prayers/reminders'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Pengingat sholat masih mati · Aktifkan',
                    textAlign: TextAlign.center,
                    style: GhinaType.caption.copyWith(
                      color: GhinaColors.blue.base,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Maghrib 17.45 · 1 j 23 m lagi".
class _Countdown extends StatelessWidget {
  const _Countdown({required this.next, required this.now});

  final ({Prayer prayer, DateTime at}) next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final style = prayerStyles[next.prayer]!;
    final left = next.at.difference(now);
    return Container(
      key: const ValueKey('prayer-countdown'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.color.tint(g.brightness),
        borderRadius: GhinaRadii.rLg,
      ),
      child: Row(
        children: [
          Icon(style.icon, size: 18, color: style.color.base),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${next.prayer.label} ${Fmt.time(next.at)}'
              '${isSameDay(next.at, now) ? '' : ' (besok)'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
            ),
          ),
          Text(
            countdownLabel(left),
            style: GhinaType.body.w(900).copyWith(color: style.color.base),
          ),
        ],
      ),
    );
  }
}

/// `1 j 23 m lagi` / `23 m lagi` / `sebentar lagi`.
String countdownLabel(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  if (mins <= 1) return 'sebentar lagi';
  final h = mins ~/ 60, m = mins % 60;
  if (h == 0) return '$m m lagi';
  return m == 0 ? '$h j lagi' : '$h j $m m lagi';
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({
    required this.prayer,
    required this.time,
    required this.highlighted,
    required this.current,
    required this.muted,
  });

  final Prayer prayer;
  final DateTime time;
  final bool highlighted;
  final bool current;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final style = prayerStyles[prayer]!;
    final color = highlighted ? style.color.base : null;
    return Container(
      key: ValueKey('prayer-time-${prayer.wire}'),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? style.color.tint(g.brightness) : null,
        borderRadius: GhinaRadii.rMd,
        border: current
            ? Border.all(color: style.color.base, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              prayerShort(prayer),
              style: GhinaType.caption.copyWith(
                color: muted ? g.textMuted : g.textSecondary,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Fmt.time(time),
              style: GhinaType.body
                  .w(900)
                  .copyWith(
                    color: color ?? (muted ? g.textMuted : g.textPrimary),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
