import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../../state/notification_capture_controller.dart';

/// Android battery-optimisation exemption; re-read whenever the capture state
/// refreshes (app resume), so coming back from Settings updates it. Null where
/// there is nothing to exempt (iOS, tests).
final _batteryExemptProvider = FutureProvider.autoDispose<bool?>((ref) {
  ref.watch(notificationCaptureProvider);
  return ref.watch(batteryOptimizationProvider).isIgnoring();
});

/// On/off switch of the notification listener, the notification-access state
/// and a button to Settings › Notification access, with a short explanation.
/// While active, warns when battery optimisation still applies to Ghina: the
/// ROM then freezes the listener in the background and the log gets holes.
class ListenerStatusCard extends ConsumerWidget {
  const ListenerStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final s = ref.watch(notificationCaptureProvider);
    final c = ref.read(notificationCaptureProvider.notifier);
    final batteryExempt = ref.watch(_batteryExemptProvider).value;
    final (ChunkySwatch color, IconData icon, String status) = switch (s) {
      NotificationCaptureState(loading: true) => (
        GhinaColors.gray,
        Icons.hourglass_top_rounded,
        'Memeriksa…',
      ),
      NotificationCaptureState(active: true) => (
        GhinaColors.green,
        Icons.check_circle_rounded,
        'Aktif — notifikasi baru dicatat otomatis',
      ),
      NotificationCaptureState(waitingForAccess: true) => (
        GhinaColors.orange,
        Icons.lock_open_rounded,
        'Belum dapat izin akses notifikasi',
      ),
      _ => (GhinaColors.gray, Icons.pause_circle_rounded, 'Nonaktif'),
    };
    return ChunkyCard(
      key: const ValueKey('notif-listener-card'),
      tinted: s.active ? GhinaColors.green : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                CategoryAvatar(
                  icon: Icons.notifications_active_rounded,
                  color: GhinaColors.orange.base,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catat notifikasi',
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(icon, size: 16, color: color.base),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              status,
                              style: GhinaType.caption
                                  .w(800)
                                  .copyWith(
                                    color: g.isDark ? color.base : color.edge,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('notif-listener-switch'),
                  value: s.enabled,
                  onChanged: s.loading ? null : c.setEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ghina membaca notifikasi dari aplikasi lain (mis. m-banking & '
            'e-wallet) dan menyimpannya di HP ini saja — nggak dikirim ke '
            'server. Notifikasi yang cocok dengan rule bisa langsung jadi '
            'transaksi.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          if (!s.loading && !s.hasAccess) ...[
            const SizedBox(height: 10),
            Text(
              'Izin ini bukan izin biasa: buka Pengaturan › Akses notifikasi, '
              'lalu nyalakan "Ghina".',
              style: GhinaType.caption.w(700).copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 10),
            ChunkyButton(
              key: const ValueKey('notif-listener-access'),
              label: 'Buka akses notifikasi',
              icon: Icons.settings_rounded,
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.outline,
              color: GhinaColors.blue,
              onPressed: c.openAccessSettings,
            ),
          ],
          if (s.active && batteryExempt == false) ...[
            const SizedBox(height: 12),
            Row(
              key: const ValueKey('notif-listener-battery'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.battery_alert_rounded,
                  size: 18,
                  color: GhinaColors.orange.base,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ghina masih dibatasi hemat baterai — saat HP lama nggak '
                    'dipakai, pencatatan bisa berhenti berjam-jam. Pilih Ghina '
                    '→ "Tanpa batasan". Di Samsung, tambahkan juga ke Baterai › '
                    'Batas penggunaan latar belakang › "Aplikasi yang tidak '
                    'pernah tidur".',
                    style: GhinaType.caption
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ChunkyButton(
              key: const ValueKey('notif-listener-battery-open'),
              label: 'Buka pengaturan baterai',
              icon: Icons.battery_charging_full_rounded,
              size: ChunkyButtonSize.small,
              variant: ChunkyButtonVariant.outline,
              color: GhinaColors.orange,
              onPressed: () => ref.read(batteryOptimizationProvider).request(),
            ),
          ],
        ],
      ),
    );
  }
}
