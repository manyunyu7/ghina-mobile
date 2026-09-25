import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../state/notifications/notification_providers.dart';
import '../../tasks/widgets/reminder_settings.dart'
    show showBatteryTip, showEnableInSettings;

/// Session flag: the explainer is shown once per app session.
class _Asked {
  bool value = false;
}

final _askedProvider = Provider<_Asked>((_) => _Asked());

/// The app's notification permission flow (the same provider, battery tip and
/// "turn it on in settings" dialog as task reminders) with habit wording.
/// Returns whether reminders can fire.
Future<bool> ensureHabitReminderPermission(
  BuildContext context,
  WidgetRef ref,
) async {
  final NotificationPermissionState perm;
  try {
    perm = await ref.read(notificationPermissionProvider.future);
  } catch (_) {
    return true;
  }
  if (perm.granted || perm.status.name == 'unsupported') return true;
  final asked = ref.read(_askedProvider);
  if (asked.value) return false;
  asked.value = true;
  if (!context.mounted) return false;
  final go = await showChunkyConfirm(
    context,
    title: 'Boleh Ghina ngingetin? 🔔',
    message:
        'Biar kebiasaanmu nggak kelewat, Ghina perlu izin kirim notifikasi. '
        'Kebiasaan pribadi tetap disamarkan, kok.',
    confirmLabel: 'Izinkan',
    cancelLabel: 'Nanti saja',
    mood: MascotMood.waving,
  );
  if (!go || !context.mounted) return false;
  final granted = await ref
      .read(notificationPermissionProvider.notifier)
      .request();
  if (!context.mounted) return granted;
  if (granted) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await showBatteryTip(context);
    }
    return true;
  }
  await showEnableInSettings(context, ref);
  return false;
}
