/// Read-only Mimpi markers for the calendar: an open dream with a target date
/// shows on that day. Computed from the dreams, never stored as events.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';

/// One dream target on a calendar day.
final class DreamTargetMarker {
  const DreamTargetMarker({
    required this.dreamId,
    required this.title,
    required this.emoji,
    required this.dateKey,
    required this.precision,
    required this.period,
  });

  final String dreamId;
  final String title;
  final String emoji;

  /// The stored target date (`YYYY-MM-DD`, the last day of the period).
  final String dateKey;
  final TargetPrecision precision;

  /// The period as the user reads it: "31 Mar 2027", "Q1 2027", "2027".
  final String period;

  /// "Tanggal", "Bulan", "Kuartal" or "Tahun".
  String get precisionLabel => precision.label;
}

/// Open dreams whose target date lies in [from]..[to] (inclusive date keys),
/// by target date key, in the order of [dreams]. Done, dropped and undated
/// dreams never appear.
Map<String, List<DreamTargetMarker>> dreamTargetMarkers(
  Iterable<Dream> dreams, {
  required String from,
  required String to,
}) {
  final out = <String, List<DreamTargetMarker>>{};
  for (final d in dreams) {
    final date = d.targetDate;
    if (date == null || !d.status.isOpen || !isDreamDateKey(date)) continue;
    if (date.compareTo(from) < 0 || date.compareTo(to) > 0) continue;
    (out[date] ??= []).add(
      DreamTargetMarker(
        dreamId: d.id,
        title: d.title,
        emoji: d.emoji ?? '🎯',
        dateKey: date,
        precision: d.targetPrecision,
        period: formatTarget(date, d.targetPrecision),
      ),
    );
  }
  return out;
}

/// Markers of a `(from, to)` range from the live dreams. Empty while loading
/// or when the dreams cannot be read: the calendar never waits on them.
final dreamTargetMarkersProvider = Provider.autoDispose
    .family<Map<String, List<DreamTargetMarker>>, ({String from, String to})>((
      ref,
      range,
    ) {
      final dreams = ref.watch(watchDreamsProvider).value;
      if (dreams == null) return const {};
      return dreamTargetMarkers(dreams, from: range.from, to: range.to);
    });

/// A dream target on the day list: 🎯, title, then "Target" and the period. Read-only; the
/// tap opens the dream.
class DreamTargetTile extends StatelessWidget {
  const DreamTargetTile({super.key, required this.marker, this.onTap});

  final DreamTargetMarker marker;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = marker;
    return ChunkySurface(
      key: ValueKey('cal-dream-tile-${m.dreamId}'),
      color: g.surface,
      edgeColor: g.borderEdge,
      borderColor: g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      semanticLabel: 'Target mimpi ${m.title}',
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 40,
            decoration: BoxDecoration(
              color: GhinaColors.purple.base,
              borderRadius: GhinaRadii.rPill,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎯 ${m.emoji == '🎯' ? '' : '${m.emoji} '}${m.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                Text(
                  'Target ${m.period}',
                  style: GhinaType.bodyS
                      .w(700)
                      .copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}
