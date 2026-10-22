import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// What a chart shows instead of an empty plot: a quiet "Belum ada data".
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key, this.label = 'Belum ada data', this.height});

  final String label;

  /// Null = as tall as its parent allows (or 120 when unbounded).
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height ?? 120,
    child: Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
      ),
    ),
  );
}
