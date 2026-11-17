import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/services/services.dart';
import '../../../design_system/design_system.dart';
import '../../../state/platform/platform_state.dart';

/// Rough size of Google's offline Indonesian speech pack.
const kSpeechPackSizeHint = 'sekitar 50–80 MB';

/// "Paket suara Indonesia" sheet: what's missing, "Unduh sekarang" with a
/// progress bar (in-app, Android 13+), "Pakai online dulu", the scheduled
/// (waiting for Wi-Fi) state, and the system-settings fallback with steps.
/// Re-checks by itself when the user comes back from the settings.
///
/// Returns true when dictation may start right away (pack ready → "Mulai
/// dikte", or "Pakai online dulu").
Future<bool> showSpeechModelSheet(
  BuildContext context, {
  String? fallback,
}) async {
  final r = await showChunkyBottomSheet<bool>(
    context,
    showClose: true,
    builder: (_) => SpeechModelPanel(fallback: fallback),
  );
  return r ?? false;
}

class SpeechModelPanel extends ConsumerStatefulWidget {
  const SpeechModelPanel({super.key, this.fallback});

  /// What still works without dictation ("Kamu tetap bisa mengetik…").
  final String? fallback;

  @override
  ConsumerState<SpeechModelPanel> createState() => _SpeechModelPanelState();
}

class _SpeechModelPanelState extends ConsumerState<SpeechModelPanel> {
  late final AppLifecycleListener _life;

  SpeechModelController get _c =>
      ref.read(speechModelControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Back from the Google / Android settings: maybe installed now.
    _life = AppLifecycleListener(onResume: () => _c.refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.refresh();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  void _useOnline() {
    ref.read(dictationOnlineOptInProvider.notifier).allow();
    Navigator.of(context).pop(true);
  }

  Future<void> _openSettings() async {
    final s = await _c.openSettings();
    if (!mounted || s != null) return;
    showToastBadge(
      context,
      message: 'Pengaturan tidak bisa dibuka. Buka manual lewat Setelan HP',
      icon: Icons.settings_rounded,
      color: GhinaColors.orange,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = ref.watch(speechModelControllerProvider);
    final online = m.canUseOnline && !ref.watch(dictationAllowsNetworkProvider);

    Widget text(String s, {Key? key, bool strong = false}) => Text(
      s,
      key: key,
      textAlign: TextAlign.center,
      style: strong
          ? GhinaType.h2.w(900).copyWith(color: g.textPrimary)
          : GhinaType.body.copyWith(color: g.textSecondary),
    );

    final onlineButton = online
        ? ChunkyButton(
            key: const ValueKey('speech-model-online'),
            label: 'Pakai online dulu',
            icon: Icons.wifi_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: _useOnline,
          )
        : null;

    final List<Widget> children = switch (m.status) {
      SpeechModelStatus.checking => [
        const SizedBox(height: 12),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        text('Mengecek paket suara…'),
      ],
      SpeechModelStatus.ready => [
        Icon(
          Icons.check_circle_rounded,
          size: 56,
          color: GhinaColors.green.base,
        ),
        GhinaSpace.gapSm,
        text(
          'Siap dipakai offline ✓',
          key: const ValueKey('speech-model-ready'),
          strong: true,
        ),
        GhinaSpace.gapXs,
        text('Dikte Bahasa Indonesia jalan tanpa internet.'),
        GhinaSpace.gapLg,
        ChunkyButton(
          key: const ValueKey('speech-model-start'),
          label: 'Mulai dikte',
          icon: Icons.mic_rounded,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      SpeechModelStatus.noRecognizer => [
        text('Dikte belum bisa dipakai', strong: true),
        GhinaSpace.gapXs,
        text(
          m.availability?.hint ??
              'Perangkat ini tidak punya layanan pengenalan suara.',
        ),
        if (widget.fallback != null) ...[
          GhinaSpace.gapSm,
          text(widget.fallback!),
        ],
      ],
      SpeechModelStatus.downloading => [
        text('Mengunduh paket suara…', strong: true),
        GhinaSpace.gapMd,
        ClipRRect(
          borderRadius: GhinaRadii.rMd,
          child: LinearProgressIndicator(
            key: const ValueKey('speech-model-progress'),
            value: m.progress,
            minHeight: 10,
          ),
        ),
        GhinaSpace.gapSm,
        text(
          m.progress == null
              ? 'Meminta Android mengunduh Bahasa Indonesia…'
              : '${(m.progress! * 100).round()}% · $kSpeechPackSizeHint',
          key: const ValueKey('speech-model-progress-text'),
        ),
        GhinaSpace.gapXs,
        text('Boleh ditutup — unduhan jalan terus.'),
        if (onlineButton != null) ...[GhinaSpace.gapLg, onlineButton],
      ],
      SpeechModelStatus.scheduled => [
        Icon(Icons.schedule_rounded, size: 48, color: GhinaColors.blue.base),
        GhinaSpace.gapSm,
        text(
          'Unduhan dijadwalkan',
          key: const ValueKey('speech-model-scheduled'),
          strong: true,
        ),
        GhinaSpace.gapXs,
        text(
          'Android akan mengunduhnya sendiri, biasanya saat tersambung Wi-Fi '
          '(kadang menunggu HP dicas). Kamu boleh menutup ini — begitu '
          'selesai, dikte otomatis bisa offline.',
        ),
        GhinaSpace.gapLg,
        if (onlineButton != null) ...[onlineButton, GhinaSpace.gapSm],
        ChunkyButton(
          label: 'Buka pengaturan',
          icon: Icons.settings_rounded,
          variant: ChunkyButtonVariant.ghost,
          onPressed: _openSettings,
        ),
      ],
      SpeechModelStatus.failed => [
        text(
          'Unduh dari app belum bisa',
          key: const ValueKey('speech-model-failed'),
          strong: true,
        ),
        GhinaSpace.gapXs,
        text(_failReason(m.errorCode)),
        GhinaSpace.gapMd,
        _Steps(steps: _settingsSteps(m.openedScreen)),
        GhinaSpace.gapLg,
        ChunkyButton(
          key: const ValueKey('speech-model-settings'),
          label: 'Buka pengaturan',
          icon: Icons.settings_rounded,
          onPressed: _openSettings,
        ),
        if (onlineButton != null) ...[GhinaSpace.gapSm, onlineButton],
        GhinaSpace.gapSm,
        ChunkyButton(
          label: 'Coba unduh lagi',
          variant: ChunkyButtonVariant.ghost,
          onPressed: _c.download,
        ),
      ],
      SpeechModelStatus.missing || SpeechModelStatus.unknown => [
        Icon(
          Icons.record_voice_over_rounded,
          size: 48,
          color: GhinaColors.blue.base,
        ),
        GhinaSpace.gapSm,
        text(
          m.status == SpeechModelStatus.unknown
              ? 'Paket suara Indonesia belum bisa dicek'
              : 'Paket suara Indonesia belum ada di HP ini',
          key: const ValueKey('speech-model-missing'),
          strong: true,
        ),
        GhinaSpace.gapXs,
        text(
          'Unduh sekali ($kSpeechPackSizeHint, sebaiknya lewat Wi-Fi), lalu '
          'dikte jalan tanpa internet dan suaramu tidak keluar dari HP.',
        ),
        if (widget.fallback != null) ...[
          GhinaSpace.gapXs,
          text(widget.fallback!),
        ],
        GhinaSpace.gapLg,
        ChunkyButton(
          key: const ValueKey('dictation-download'),
          label: 'Unduh sekarang',
          icon: Icons.download_rounded,
          onPressed: _c.download,
        ),
        if (onlineButton != null) ...[GhinaSpace.gapSm, onlineButton],
      ],
    };

    return Column(
      key: const ValueKey('speech-model-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

String _failReason(int? code) => switch (code) {
  2 || 4 =>
    'Tidak ada koneksi. Sambungkan ke internet atau Wi-Fi, lalu coba '
        'lagi — atau unduh lewat pengaturan HP.',
  12 || 13 =>
    'Pengenal suara offline di HP ini belum menyediakan Bahasa Indonesia '
        'lewat app. Coba unduh lewat pengaturan HP.',
  _ =>
    'Android belum mau mengunduh dari dalam app. Unduh lewat pengaturan '
        'HP, caranya singkat:',
};

List<String> _settingsSteps(SpeechSettingsScreen? opened) => switch (opened) {
  SpeechSettingsScreen.googleOffline => const [
    'Buka tab "Semua" (All).',
    'Pilih "Indonesia" lalu ketuk Unduh.',
    'Kembali ke sini — dicek otomatis.',
  ],
  SpeechSettingsScreen.voiceInput => const [
    'Pilih "Pengenalan di perangkat" (On-device recognition).',
    'Tambah bahasa › Indonesia › Unduh.',
    'Kembali ke sini — dicek otomatis.',
  ],
  _ => const [
    'Ketuk "Buka pengaturan".',
    'Cari "Pengenalan ucapan offline" atau "Pengenalan di perangkat".',
    'Unduh "Indonesia", lalu kembali ke sini — dicek otomatis.',
  ],
};

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: const ValueKey('speech-model-steps'),
      padding: const EdgeInsets.all(GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Text(
                '${i + 1}. ${steps[i]}',
                style: GhinaType.bodyS.copyWith(color: g.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pengaturan: "Dikte offline: Siap ✓ / Belum diunduh — Unduh".
class DictationOfflineTile extends ConsumerStatefulWidget {
  const DictationOfflineTile({super.key, this.framed = true});

  final bool framed;

  @override
  ConsumerState<DictationOfflineTile> createState() =>
      _DictationOfflineTileState();
}

class _DictationOfflineTileState extends ConsumerState<DictationOfflineTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(speechModelControllerProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(speechModelControllerProvider);
    final subtitle = switch (m.status) {
      SpeechModelStatus.checking => 'Mengecek…',
      SpeechModelStatus.ready => 'Siap ✓ · dikte jalan tanpa internet',
      SpeechModelStatus.missing => 'Belum diunduh · $kSpeechPackSizeHint',
      SpeechModelStatus.unknown => 'Belum bisa dicek di HP ini',
      SpeechModelStatus.downloading =>
        m.progress == null
            ? 'Mengunduh…'
            : 'Mengunduh… ${(m.progress! * 100).round()}%',
      SpeechModelStatus.scheduled => 'Dijadwalkan Android (menunggu Wi-Fi)',
      SpeechModelStatus.failed => 'Belum berhasil · unduh lewat pengaturan',
      SpeechModelStatus.noRecognizer => 'Tidak tersedia di perangkat ini',
    };
    final canDownload =
        m.status == SpeechModelStatus.missing ||
        m.status == SpeechModelStatus.unknown ||
        m.status == SpeechModelStatus.failed;
    return ChunkyTile(
      key: const ValueKey('dictation-offline-tile'),
      framed: widget.framed,
      title: 'Dikte offline',
      subtitle: subtitle,
      leading: CategoryAvatar(
        icon: m.isReady
            ? Icons.offline_pin_rounded
            : Icons.record_voice_over_rounded,
        color: m.isReady ? GhinaColors.green.base : GhinaColors.blue.base,
        size: 40,
      ),
      trailing: canDownload
          ? TextButton(
              key: const ValueKey('dictation-offline-download'),
              onPressed: () => showSpeechModelSheet(context),
              child: const Text('Unduh'),
            )
          : null,
      showChevron: !canDownload,
      onTap: m.status == SpeechModelStatus.noRecognizer
          ? null
          : () => showSpeechModelSheet(context),
    );
  }
}
