import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';

/// What the mic is for (changes the explanation copy).
enum MicPurpose { record, dictate }

/// Permissions UX before "Rekam suara" / "Dikte", the one place that asks
/// for the mic (the controllers only re-check, so one tap never shows two
/// prompts):
///
/// 1. not asked yet → short explanation → the system prompt;
/// 2. denied → a clear message with "Coba lagi" (asks again, one prompt per
///    tap) / "Nanti saja";
/// 3. blocked ("jangan tanya lagi") → sheet with "Buka pengaturan app"; back
///    in the app the status is checked again by itself.
///
/// Returns true only when the mic is usable now — the caller then starts
/// right away (no second tap on the mic). Checked on every start, so
/// Android's "Hanya kali ini" grant is honoured when it lapses.
Future<bool> ensureMicReady(
  BuildContext context,
  WidgetRef ref,
  MicPurpose purpose,
) async {
  final perm = ref.read(microphonePermissionProvider);
  var status = await perm.status();
  if (!context.mounted) return false;
  if (_usable(status)) return true;
  if (status == MicPermissionStatus.denied) {
    final go = await _explain(context, purpose);
    if (go != true || !context.mounted) return false;
    status = await perm.request();
    while (status == MicPermissionStatus.denied) {
      if (!context.mounted) return false;
      final again = await _deniedAgain(context, purpose);
      if (again != true || !context.mounted) return false;
      status = await perm.request();
    }
    if (!context.mounted) return false;
    if (_usable(status)) return true;
  }
  return showMicSettingsGuide(context, ref);
}

bool _usable(MicPermissionStatus s) =>
    s.isGranted || s == MicPermissionStatus.unsupported;

Future<bool?> _explain(BuildContext context, MicPurpose purpose) =>
    showChunkyDialog<bool>(
      context,
      builder: (c) => ChunkyDialog(
        title: purpose == MicPurpose.record
            ? 'Izinkan mikrofon, ya'
            : 'Izinkan mikrofon untuk dikte',
        message: purpose == MicPurpose.record
            ? 'Mikrofon dipakai buat merekam suaramu. Rekaman disimpan di HP '
                  'dulu, lalu ikut tersinkron.'
            : 'Mikrofon dipakai buat mengubah ucapanmu jadi teks. Pengenalan '
                  'suara jalan di perangkat. Setelah kamu izinkan, dikte '
                  'langsung mulai.',
        mood: MascotMood.waving,
        actions: [
          ChunkyButton(
            key: const ValueKey('mic-allow'),
            label: 'Izinkan',
            icon: Icons.mic_rounded,
            onPressed: () => Navigator.of(c).pop(true),
          ),
          ChunkyButton(
            label: 'Nanti saja',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(c).pop(false),
          ),
        ],
      ),
    );

Future<bool?> _deniedAgain(BuildContext context, MicPurpose purpose) =>
    showChunkyDialog<bool>(
      context,
      builder: (c) => ChunkyDialog(
        title: 'Mikrofon belum diizinkan',
        message: purpose == MicPurpose.record
            ? 'Tanpa mikrofon suaramu tidak bisa direkam. Ketuk "Coba lagi", '
                  'lalu pilih Izinkan.'
            : 'Tanpa mikrofon dikte tidak bisa jalan. Ketuk "Coba lagi", lalu '
                  'pilih Izinkan. Kamu tetap bisa mengetik.',
        mood: MascotMood.thinking,
        actions: [
          ChunkyButton(
            key: const ValueKey('mic-retry'),
            label: 'Coba lagi',
            icon: Icons.mic_rounded,
            onPressed: () => Navigator.of(c).pop(true),
          ),
          ChunkyButton(
            key: const ValueKey('mic-later'),
            label: 'Nanti saja',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(c).pop(false),
          ),
        ],
      ),
    );

/// "Buka pengaturan app" sheet after a permanent denial. When the user went
/// to the settings, waits until the app is back in front and checks again:
/// true = the mic is allowed now (the caller goes on by itself).
Future<bool> showMicSettingsGuide(BuildContext context, WidgetRef ref) async {
  final open = await showChunkyBottomSheet<bool>(
    context,
    title: 'Mikrofon masih diblokir',
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isIos
              ? 'Buka Pengaturan, pilih app ini, lalu nyalakan Mikrofon (dan '
                    'Pengenalan Ucapan untuk dikte). Setelah kembali ke sini, '
                    'langsung dicek lagi.'
              : 'Buka pengaturan app ini › Izin › Mikrofon, lalu pilih '
                    'Izinkan. Setelah kembali ke sini, langsung dicek lagi.',
          style: GhinaType.body.copyWith(color: c.ghina.textSecondary),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('mic-settings'),
          label: 'Buka pengaturan app',
          icon: Icons.settings_rounded,
          onPressed: () => Navigator.of(c).pop(true),
        ),
        const SizedBox(height: 10),
        ChunkyButton(
          label: 'Nanti saja',
          variant: ChunkyButtonVariant.ghost,
          onPressed: () => Navigator.of(c).pop(false),
        ),
      ],
    ),
  );
  if (open != true) return false;
  final perm = ref.read(microphonePermissionProvider);
  final back = waitForAppResume();
  final ok = await perm.openAppSettings();
  if (!ok) {
    back.cancel();
    if (context.mounted) {
      showToastBadge(
        context,
        message: 'Buka Pengaturan HP › Aplikasi › app ini › Mikrofon, ya',
        icon: Icons.settings_rounded,
        color: GhinaColors.blue,
      );
    }
    return false;
  }
  if (!await back.future || !context.mounted) return false;
  final status = await perm.status();
  if (!context.mounted) return false;
  if (_usable(status)) return true;
  showToastBadge(
    context,
    message: 'Mikrofon masih belum diizinkan',
    icon: Icons.mic_off_rounded,
    color: GhinaColors.blue,
  );
  return false;
}

/// Completes with true when the app comes back to the foreground (after the
/// system settings), false when cancelled. No timer: the settings visit may
/// take as long as it takes.
({Future<bool> future, void Function() cancel}) waitForAppResume() {
  final done = Completer<bool>();
  AppLifecycleListener? l;
  void finish(bool v) {
    l?.dispose();
    l = null;
    if (!done.isCompleted) done.complete(v);
  }

  var left = false;
  l = AppLifecycleListener(
    onStateChange: (s) {
      if (s == AppLifecycleState.resumed) {
        if (left) finish(true);
      } else {
        left = true;
      }
    },
  );
  return (future: done.future, cancel: () => finish(false));
}

bool get _isIos {
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}
