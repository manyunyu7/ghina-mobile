import 'package:flutter/material.dart';

import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../screener_format.dart';

/// Laporan older than this get the "Stockbit hanya menyimpan 6 bulan" warning.
const screenerStaleAfter = Duration(days: 14);

({String label, ChunkySwatch color, IconData icon}) healthLook(
  StockbitHealth h,
) => switch (h) {
  StockbitHealth.auto => (
    label: 'Terhubung · diperpanjang otomatis',
    color: GhinaColors.green,
    icon: Icons.check_circle_rounded,
  ),
  StockbitHealth.active => (
    label: 'Terhubung',
    color: GhinaColors.green,
    icon: Icons.check_circle_rounded,
  ),
  StockbitHealth.expiring => (
    label: 'Segera berakhir',
    color: GhinaColors.orange,
    icon: Icons.schedule_rounded,
  ),
  StockbitHealth.expired => (
    label: 'Sesi berakhir',
    color: GhinaColors.red,
    icon: Icons.error_rounded,
  ),
  StockbitHealth.none => (
    label: 'Belum terhubung',
    color: GhinaColors.gray,
    icon: Icons.link_off_rounded,
  ),
};

/// "Data Stockbit": how fresh the data on Ghina is, the Stockbit session of
/// this phone and the main action (update / connect).
class StockbitStatusCard extends StatelessWidget {
  const StockbitStatusCard({
    super.key,
    required this.status,
    required this.tokens,
    required this.health,
    required this.now,
    required this.running,
    required this.onSync,
    required this.onFullSync,
    required this.onConnect,
  });

  final ScreenerStatus status;

  /// The tokens saved on this phone, if any.
  final StockbitTokens? tokens;
  final StockbitHealth health;
  final DateTime now;

  /// An update is in progress.
  final bool running;
  final VoidCallback onSync;
  final VoidCallback onFullSync;
  final VoidCallback onConnect;

  /// `Stockbit di HP ini: ...`
  String deviceLine() {
    final t = tokens;
    String until(DateTime d) => 's/d ${Fmt.date(d)} ${Fmt.time(d)}';
    switch (health) {
      case StockbitHealth.none:
        return 'Stockbit di HP ini: belum terhubung';
      case StockbitHealth.auto:
        final e = t?.refreshExpiresAt;
        return 'Stockbit di HP ini: diperpanjang otomatis${e == null ? '' : ' ${until(e)}'}';
      case StockbitHealth.expired:
        return 'Stockbit di HP ini: sesi berakhir';
      case StockbitHealth.active:
      case StockbitHealth.expiring:
        final e = t?.accessExpiresAt;
        return 'Stockbit di HP ini: aktif${e == null ? '' : ' ${until(e)}'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final look = healthLook(health);
    final updated = status.reportsUpdatedAt;
    final quotes = status.quotesFetchedAt;
    final stale =
        updated != null && now.difference(updated) >= screenerStaleAfter;
    final lineStyle = GhinaType.bodyS.copyWith(color: g.textSecondary);
    return ChunkyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data Stockbit',
            style: GhinaType.h3.w(900).copyWith(color: g.textPrimary),
          ),
          const SizedBox(height: 6),
          _HealthPill(look: look),
          const SizedBox(height: 10),
          if (status.anchor != null)
            Text(
              'Laporan terbaru ${Fmt.date(status.anchor!)}',
              style: lineStyle,
            ),
          Text(
            updated == null
                ? 'Terakhir diambil: belum pernah'
                : 'Terakhir diambil ${screenerAgo(updated, now)}',
            style: lineStyle,
          ),
          if (quotes != null)
            Text('Harga ${screenerDateTime(quotes)}', style: lineStyle),
          Text(
            'Arsip ${screenerNum(status.stats.rows)} laporan · '
            '${screenerNum(status.stats.tickers)} emiten',
            style: lineStyle,
          ),
          const SizedBox(height: 4),
          Text(
            deviceLine(),
            key: const ValueKey('stockbit-device-line'),
            style: lineStyle.w(800),
          ),
          if (stale) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('screener-stale-warning'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GhinaColors.orange.tint(g.brightness),
                borderRadius: GhinaRadii.rMd,
                border: Border.all(
                  color: GhinaColors.orange.tintBorder(g.brightness),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: GhinaColors.orange.base,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stockbit hanya menyimpan 6 bulan terakhir. Laporan '
                      'terakhir masuk ${now.difference(updated).inDays} hari '
                      'lalu, perbarui supaya arsipnya nggak bolong.',
                      style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (health.usable)
            GestureDetector(
              onLongPress: running ? null : onFullSync,
              child: ChunkyButton(
                label: running ? 'Memperbarui…' : 'Perbarui data',
                icon: Icons.sync_rounded,
                loading: running,
                uppercase: false,
                onPressed: running ? null : onSync,
              ),
            )
          else
            ChunkyButton(
              label: 'Hubungkan Stockbit',
              icon: Icons.link_rounded,
              uppercase: false,
              onPressed: onConnect,
            ),
        ],
      ),
    );
  }
}

/// Like a [ChunkyPill], but the label may wrap (the longest one is
/// "Terhubung · diperpanjang otomatis").
class _HealthPill extends StatelessWidget {
  const _HealthPill({required this.look});

  final ({String label, ChunkySwatch color, IconData icon}) look;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = g.isDark ? look.color.base : look.color.edge;
    return Container(
      key: const ValueKey('stockbit-health'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: look.color.tint(g.brightness),
        borderRadius: GhinaRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(look.icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              look.label,
              style: GhinaType.caption.w(900).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
