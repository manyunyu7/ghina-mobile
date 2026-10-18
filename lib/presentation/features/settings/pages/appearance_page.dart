import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../state/appearance_provider.dart';

/// Indonesian name of a theme mode.
String themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => 'Sistem',
  ThemeMode.light => 'Terang',
  ThemeMode.dark => 'Gelap',
};

/// Confirms a change. One tag: fast taps replace the toast instead of
/// stacking. The tap itself already gave haptic feedback.
void _confirm(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  ChunkySwatch color = GhinaColors.blue,
}) => showToastBadge(
  context,
  message: message,
  icon: icon,
  color: color,
  tag: 'appearance',
  haptics: false,
  duration: const Duration(milliseconds: 1600),
);

/// "Tampilan": theme mode, accent color, text size and style. Every change
/// applies app-wide and is saved right away (the preview card on top shows
/// it first; each change confirms with a short toast).
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final ctrl = ref.read(appearanceProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Tema & warna')),
      body: SafeArea(
        top: false,
        // A short page: build it whole (the preview stays live while the
        // options below are scrolled into view).
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.lg,
            GhinaSpace.page,
            GhinaSpace.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pratinjau · perubahan langsung tersimpan',
                key: const ValueKey('appearance-preview-caption'),
                style: GhinaType.bodyS
                    .w(700)
                    .copyWith(color: context.ghina.textSecondary),
              ),
              GhinaSpace.gapSm,
              const _Preview(),
              GhinaSpace.gapXl,
              const SectionHeader(
                title: 'Mode',
                subtitle: 'Ikut HP, atau pilih terang / gelap sendiri.',
              ),
              ChunkySegmented<ThemeMode>(
                key: const ValueKey('appearance-mode'),
                segments: const [
                  ChunkySegment(
                    value: ThemeMode.system,
                    label: 'Sistem',
                    icon: Icons.brightness_auto_rounded,
                  ),
                  ChunkySegment(
                    value: ThemeMode.light,
                    label: 'Terang',
                    icon: Icons.light_mode_rounded,
                  ),
                  ChunkySegment(
                    value: ThemeMode.dark,
                    label: 'Gelap',
                    icon: Icons.dark_mode_rounded,
                  ),
                ],
                value: look.mode,
                onChanged: (m) {
                  ctrl.setMode(m);
                  _confirm(
                    context,
                    'Mode: ${themeModeLabel(m)}',
                    icon: switch (m) {
                      ThemeMode.system => Icons.brightness_auto_rounded,
                      ThemeMode.light => Icons.light_mode_rounded,
                      ThemeMode.dark => Icons.dark_mode_rounded,
                    },
                  );
                },
              ),
              GhinaSpace.gapXl,
              const SectionHeader(
                title: 'Warna aksen',
                subtitle:
                    'Buat tombol, menu, dan progres. Hijau pemasukan & merah '
                    'pengeluaran tetap sama.',
              ),
              Wrap(
                spacing: GhinaSpace.md,
                runSpacing: GhinaSpace.md,
                children: [
                  for (final a in GhinaAccent.values)
                    _AccentSwatch(
                      accent: a,
                      selected: a == look.accent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ctrl.setAccent(a);
                        _confirm(
                          context,
                          'Warna aksen: ${a.label}',
                          icon: Icons.palette_rounded,
                          color: a.swatchFor(context.ghina.brightness),
                        );
                      },
                    ),
                ],
              ),
              GhinaSpace.gapXl,
              const SectionHeader(
                title: 'Ukuran teks',
                subtitle: 'Dikalikan dengan ukuran teks di pengaturan HP.',
              ),
              ChunkySegmented<GhinaTextSize>(
                key: const ValueKey('appearance-text-size'),
                segments: [
                  for (final s in GhinaTextSize.values)
                    ChunkySegment(value: s, label: s.label),
                ],
                value: look.textSize,
                onChanged: (s) {
                  ctrl.setTextSize(s);
                  _confirm(
                    context,
                    'Teks: ${s.label}',
                    icon: Icons.format_size_rounded,
                  );
                },
              ),
              GhinaSpace.gapXl,
              const SectionHeader(
                title: 'Gaya',
                subtitle:
                    'Chunky: tombol & kartu timbul. Datar: tanpa bayangan '
                    'bawah. Minimal: font sistem, abu-abu lembut, tombol '
                    'monokrom.',
              ),
              ChunkySegmented<GhinaStyle>(
                key: const ValueKey('appearance-style'),
                segments: const [
                  ChunkySegment(
                    value: GhinaStyle.chunky,
                    label: 'Chunky',
                    icon: Icons.layers_rounded,
                  ),
                  ChunkySegment(
                    value: GhinaStyle.datar,
                    label: 'Datar',
                    icon: Icons.crop_square_rounded,
                  ),
                  ChunkySegment(
                    value: GhinaStyle.minimal,
                    label: 'Minimal',
                    icon: Icons.blur_on_rounded,
                  ),
                ],
                value: look.style,
                onChanged: (s) {
                  ctrl.setStyle(s);
                  _confirm(
                    context,
                    'Gaya: ${s.label}',
                    icon: Icons.style_rounded,
                  );
                },
              ),
              GhinaSpace.gapXxl,
              ChunkyButton(
                key: const ValueKey('appearance-reset'),
                label: 'Reset ke default',
                icon: Icons.restart_alt_rounded,
                variant: ChunkyButtonVariant.outline,
                onPressed: look.isDefault
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        await ctrl.reset();
                        if (!context.mounted) return;
                        _confirm(
                          context,
                          'Kembali ke default',
                          icon: Icons.restart_alt_rounded,
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A mini mock of the app in the current look: mascot, money, chip,
/// progress bar and a primary button.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: const ValueKey('appearance-preview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const MascotView(
                key: ValueKey('appearance-preview-mascot'),
                mood: MascotMood.waving,
                size: 64,
                showShadow: false,
              ),
              GhinaSpace.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo kamu',
                      style: GhinaType.bodyS
                          .w(800)
                          .copyWith(color: g.textSecondary),
                    ),
                    const MoneyText(
                      key: ValueKey('appearance-preview-money'),
                      amount: 1250000,
                      tone: MoneyTone.neutral,
                    ),
                    const SizedBox(height: 2),
                    MoneyText(
                      key: const ValueKey('appearance-preview-income'),
                      amount: 350000,
                      tone: MoneyTone.income,
                      style: GhinaType.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          GhinaSpace.gapMd,
          Wrap(
            spacing: GhinaSpace.sm,
            runSpacing: GhinaSpace.sm,
            children: [
              ChunkyChip(label: 'Makan', selected: true, onTap: () {}),
              ChunkyChip(label: 'Jajan', selected: false, onTap: () {}),
            ],
          ),
          GhinaSpace.gapMd,
          const ChunkyProgressBar(
            key: ValueKey('appearance-preview-progress'),
            value: 0.65,
            animate: false,
          ),
          GhinaSpace.gapMd,
          ChunkyButton(
            key: const ValueKey('appearance-preview-button'),
            label: 'Simpan',
            icon: Icons.check_rounded,
            size: ChunkyButtonSize.medium,
            expand: true,
            // Only a sample: say so instead of doing nothing.
            onPressed: () {
              HapticFeedback.selectionClick();
              _confirm(
                context,
                'Ini cuma contoh tombol — pilihanmu sudah otomatis tersimpan',
                icon: Icons.info_rounded,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final GhinaAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = accent.swatchFor(g.brightness);
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          AnimatedContainer(
            duration: GhinaMotion.fast,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? sw.base : Colors.transparent,
                width: 3,
              ),
            ),
            child: ChunkySurface(
              key: ValueKey('accent-${accent.id}'),
              color: sw.base,
              edgeColor: sw.edge,
              depth: GhinaDepth.sm,
              borderRadius: GhinaRadii.rPill,
              haptics: false, // the page gives a selection click
              semanticLabel: selected
                  ? '${accent.label}, dipakai'
                  : accent.label,
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: selected
                    ? Icon(Icons.check_rounded, color: sw.on, size: 28)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            accent.label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: GhinaType.caption
                .w(800)
                .copyWith(color: selected ? g.textPrimary : g.textSecondary),
          ),
        ],
      ),
    );
  }
}
