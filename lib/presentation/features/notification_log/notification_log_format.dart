import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';

/// Prefill of the rule form ("Jadikan rule" from a log entry), passed as the
/// route's `extra`.
@immutable
class NotificationRuleDraft {
  const NotificationRuleDraft({
    required this.packageName,
    this.appName,
    this.sampleTitle = '',
    this.sampleBody = '',
  });

  factory NotificationRuleDraft.fromNotification(CapturedNotification n) =>
      NotificationRuleDraft(
        packageName: n.packageName,
        appName: n.appName,
        sampleTitle: n.title,
        sampleBody: n.body,
      );

  final String packageName;
  final String? appName;
  final String sampleTitle;
  final String sampleBody;
}

/// `Hari ini, 14.05` / `Kemarin, 09.12` / `3 Sep 2026, 20.00`.
String notificationTimeLabel(DateTime d, {DateTime? now}) =>
    '${Fmt.relativeDay(d, now: now)}, ${Fmt.time(d)}';

ChunkySwatch txTypeSwatch(TxType t) =>
    t == TxType.income ? GhinaColors.income : GhinaColors.expense;

IconData txTypeIcon(TxType t) =>
    t == TxType.income ? Icons.south_west_rounded : Icons.north_east_rounded;

/// A stable color per app (avatar in the log).
ChunkySwatch appSwatch(String packageName) {
  const swatches = [
    GhinaColors.blue,
    GhinaColors.green,
    GhinaColors.orange,
    GhinaColors.purple,
    GhinaColors.pink,
    GhinaColors.red,
    GhinaColors.lime,
    GhinaColors.yellow,
  ];
  var h = 0;
  for (final c in packageName.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return swatches[h % swatches.length];
}

/// Round avatar with the app's initial.
class AppInitialAvatar extends StatelessWidget {
  const AppInitialAvatar({
    super.key,
    required this.packageName,
    required this.label,
    this.size = 40,
  });

  final String packageName;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = appSwatch(packageName);
    final t = label.trim();
    final initial = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.base, shape: BoxShape.circle),
      child: Text(
        initial,
        style: GhinaType.h3.w(900).copyWith(color: s.on, fontSize: size * 0.42),
      ),
    );
  }
}
