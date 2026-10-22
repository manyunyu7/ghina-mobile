import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';

/// `GET /api/usage/limits`: Claude 5-hour / weekly and Codex quota windows.
/// Refetches when the daemon pushes `usage-limits`.
final kantorUsageLimitsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      ref.listen(kantorEventsProvider, (_, next) {
        if (next.value?['t'] == 'usage-limits') ref.invalidateSelf();
      });
      final d = await api.get('/api/usage/limits');
      if (d is! Map) {
        throw const KantorException(
          KantorFailure.server,
          'Jawaban batas pemakaian tidak dikenali.',
        );
      }
      return Map<String, dynamic>.from(d);
    });

/// One quota window as the daemon reports it.
class UsageWindow {
  const UsageWindow({
    required this.label,
    required this.usedPercent,
    this.resetsAt,
    this.expired = false,
  });

  final String label;

  /// 0..100, always finite.
  final double usedPercent;
  final DateTime? resetsAt;

  /// The window ended after the last report, so the real figure is unknown (about 0).
  final bool expired;

  static UsageWindow? parse(Object? raw) {
    if (raw is! Map) return null;
    final p = raw['usedPercent'];
    if (p is! num || !p.isFinite) return null;
    final at = raw['resetsAt'];
    return UsageWindow(
      label: '${raw['label'] ?? 'Kuota'}',
      usedPercent: p.toDouble().clamp(0, 100),
      resetsAt: at is num && at.isFinite
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : null,
      expired: raw['expired'] == true,
    );
  }

  /// Percent that counts for warnings and the bar.
  double get shown => expired ? 0 : usedPercent;
}

List<UsageWindow> usageWindows(Object? engine) {
  if (engine is! Map) return const [];
  return [
    for (final w in (engine['windows'] as List? ?? const []))
      ?UsageWindow.parse(w),
  ];
}

/// Warning colour: green, orange from 80%, red from 90%.
ChunkySwatch usageColor(double percent) => percent >= 90
    ? GhinaColors.red
    : percent >= 80
    ? GhinaColors.orange
    : GhinaColors.green;

/// "2j 10m" / "3h 4j" / "5m" / "sebentar lagi".
String untilReset(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = at.difference(now);
  if (d.inSeconds <= 0) return 'sudah reset';
  if (d.inDays >= 1) return 'reset ${d.inDays}h ${d.inHours % 24}j lagi';
  if (d.inHours >= 1) return 'reset ${d.inHours}j ${d.inMinutes % 60}m lagi';
  if (d.inMinutes >= 1) return 'reset ${d.inMinutes}m lagi';
  return 'reset sebentar lagi';
}

/// "5 menit lalu" for a millisecond timestamp.
String agoText(Object? ms, DateTime now) {
  if (ms is! num || !ms.isFinite) return '';
  final d = now.difference(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inHours < 1) return '${d.inMinutes} menit lalu';
  if (d.inDays < 1) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}
