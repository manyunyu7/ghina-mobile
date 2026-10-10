import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';

/// Colour of each status (chips, board headers, progress bars).
ChunkySwatch dreamStatusColor(DreamStatus s) => switch (s) {
  DreamStatus.idea => GhinaColors.purple,
  DreamStatus.planned => GhinaColors.blue,
  DreamStatus.active => GhinaColors.green,
  DreamStatus.waiting => GhinaColors.yellow,
  DreamStatus.done => GhinaColors.lime,
  DreamStatus.paused => GhinaColors.gray,
  DreamStatus.dropped => GhinaColors.red,
  DreamStatus.watching => GhinaColors.orange,
};

/// "💭 Ide" style label of a status.
String dreamStatusText(DreamStatus s) => '${s.emoji} ${s.label}';

/// Status chip. Uses the soft fill so several fit in a row.
class DreamStatusPill extends StatelessWidget {
  const DreamStatusPill({super.key, required this.status});

  final DreamStatus status;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: dreamStatusText(status),
    color: dreamStatusColor(status),
    soft: true,
    uppercase: false,
  );
}

/// Category chip with its emoji ("🌟 Perjalanan"); unknown keys show plain.
class DreamCategoryPill extends StatelessWidget {
  const DreamCategoryPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: label,
    color: GhinaColors.gray,
    soft: true,
    uppercase: false,
  );
}

/// Progress of a dream: a bar and the percentage, or a dash when unknown.
class DreamProgressLine extends StatelessWidget {
  const DreamProgressLine({super.key, required this.pct, this.color});

  final int? pct;
  final ChunkySwatch? color;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = pct;
    if (p == null) {
      return Text(
        'Progres belum diketahui',
        style: GhinaType.caption.copyWith(color: g.textMuted),
      );
    }
    return Row(
      children: [
        Expanded(
          child: ChunkyProgressBar(
            value: (p / 100).clamp(0.0, 1.0),
            height: 8,
            color: color ?? GhinaColors.green,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$p%',
          style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
        ),
      ],
    );
  }
}
