/// Reminder flows shared by the list and the form: complete with undo, delete
/// with undo, the notification permission prompt and due-date labels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/notifications/notification_providers.dart';
import '../tasks/widgets/reminder_settings.dart'
    show showBatteryTip, showEnableInSettings;

/// `Hari ini 07.00`, `Besok 20.30`, `12 Okt 09.00`.
String reminderDueLabel(DateTime dueAt, DateTime now) =>
    '${Fmt.relativeDay(dueAt, now: now)} ${Fmt.time(dueAt)}';

/// "Selesai": one-off → done, repeating → next occurrence; a snackbar offers
/// "BATAL" (restores the reminder as it was).
Future<void> completeReminderWithUndo(
  BuildContext context,
  WidgetRef ref,
  ReminderItem reminder,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final restore = ref.read(restoreReminderProvider);
  final r = await ref.read(completeReminderProvider)(reminder.id);
  if (!context.mounted) return;
  switch (r) {
    case Ok(:final value):
      final now = ref.read(clockProvider).now();
      final message = value.repeats
          ? 'Mantap! Berikutnya ${reminderDueLabel(value.dueAt, now)} 🔁'
          : 'Mantap, "${reminder.title}" selesai ✅';
      messenger?.hideCurrentSnackBar();
      final c = messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          persist: false,
          action: SnackBarAction(label: 'BATAL', onPressed: () {}),
        ),
      );
      final reason = await c?.closed;
      if (reason == SnackBarClosedReason.action) {
        await restore(reminder);
      }
    case Err(:final failure):
      showFailureToast(context, failure);
  }
}

/// Deletes at once; "BATAL" puts it back (same id, so sync sees an upsert).
Future<void> deleteReminderWithUndo(
  BuildContext context,
  WidgetRef ref,
  ReminderItem reminder,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final restore = ref.read(restoreReminderProvider);
  final r = await ref.read(deleteReminderProvider)(reminder.id);
  if (!context.mounted) return;
  if (r case Err(:final failure)) {
    showFailureToast(context, failure);
    return;
  }
  messenger?.hideCurrentSnackBar();
  final c = messenger?.showSnackBar(
    SnackBar(
      content: Text('"${reminder.title}" dihapus'),
      duration: const Duration(seconds: 4),
      persist: false,
      action: SnackBarAction(label: 'BATAL', onPressed: () {}),
    ),
  );
  final reason = await c?.closed;
  if (reason == SnackBarClosedReason.action) {
    await restore(reminder);
  }
}

class _Asked {
  bool value = false;
}

final _askedProvider = Provider<_Asked>((_) => _Asked());

/// The app's notification permission flow (same provider, battery tip and
/// "turn it on in settings" dialog as task reminders), asked once per
/// session. Returns whether reminders can fire.
Future<bool> ensureReminderPermission(
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
        'Biar pengingatmu muncul tepat waktu, Ghina perlu izin kirim '
        'notifikasi.',
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
