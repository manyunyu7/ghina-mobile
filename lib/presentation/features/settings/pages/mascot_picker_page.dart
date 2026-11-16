import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../state/mascot_kind_provider.dart';

/// Indonesian labels for the mood preview chips.
extension MascotMoodLabel on MascotMood {
  String get label => switch (this) {
    MascotMood.happy => 'Senang',
    MascotMood.excited => 'Girang',
    MascotMood.thinking => 'Mikir',
    MascotMood.sad => 'Sedih',
    MascotMood.sleeping => 'Tidur',
    MascotMood.waving => 'Lambai',
  };
}

/// "Pilih maskot": a grid of all mascots (live-animated); tap one to preview
/// it bigger with every mood, then "Pakai maskot ini".
class MascotPickerPage extends ConsumerWidget {
  const MascotPickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(mascotKindProvider);
    // Ravel keeps its own launcher icon (no mascot aliases), so the icon
    // note is Ghina-only.
    final ravel = ref.watch(kantorOnlyProvider);
    final iconNote =
        !ravel && Theme.of(context).platform == TargetPlatform.android
        ? ' Ikon & layar pembuka Ghina ikut ganti begitu kamu keluar dari aplikasi.'
        : '';
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih maskot')),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.md,
                GhinaSpace.page,
                GhinaSpace.lg,
              ),
              sliver: SliverToBoxAdapter(
                child: MascotSpeech(
                  key: const ValueKey('mascot-current'),
                  mood: MascotMood.waving,
                  mascotSize: 92,
                  title: 'Halo, aku ${current.label}!',
                  message:
                      'Pilih teman yang paling cocok buat nemenin kamu '
                      '${ravel ? 'di kantor' : 'nabung'}. Ketuk salah satu '
                      'buat lihat ekspresinya.$iconNote',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                0,
                GhinaSpace.page,
                GhinaSpace.xxl,
              ),
              // Lazy grid: tiles scrolled far off-screen are disposed, so
              // their animations stop.
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 132,
                  mainAxisExtent: 150,
                  mainAxisSpacing: GhinaSpace.md,
                  crossAxisSpacing: GhinaSpace.md,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final kind = MascotKind.values[i];
                  return _MascotTile(
                    kind: kind,
                    selected: kind == current,
                    onTap: () => showMascotPreview(context, kind),
                  );
                }, childCount: MascotKind.values.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MascotTile extends StatelessWidget {
  const _MascotTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final MascotKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: ValueKey('mascot-tile-${kind.id}'),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      tinted: selected ? context.ghina.accent : null,
      semanticLabel: selected ? '${kind.label}, dipakai' : kind.label,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: MascotView(
                    kind: kind,
                    size: 84,
                    showShadow: false,
                    semanticLabel: kind.label,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kind.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
              ),
            ],
          ),
          if (selected)
            Positioned(
              top: -2,
              right: -2,
              child: Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: context.ghina.accent.base,
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the big preview sheet for [kind].
Future<void> showMascotPreview(BuildContext context, MascotKind kind) =>
    showChunkyBottomSheet<void>(
      context,
      title: kind.label,
      showClose: true,
      builder: (_) => MascotPreview(kind: kind),
    );

/// Big live preview + pitch + the 6 moods + "Pakai maskot ini".
class MascotPreview extends ConsumerStatefulWidget {
  const MascotPreview({super.key, required this.kind});

  final MascotKind kind;

  @override
  ConsumerState<MascotPreview> createState() => _MascotPreviewState();
}

class _MascotPreviewState extends ConsumerState<MascotPreview> {
  MascotMood _mood = MascotMood.waving;

  Future<void> _use() async {
    final kind = widget.kind;
    await ref.read(mascotKindProvider.notifier).select(kind);
    if (!mounted) return;
    showToastBadge(
      context,
      message: '${kind.label} jadi maskotmu sekarang!',
      icon: Icons.favorite_rounded,
      color: GhinaColors.green,
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final inUse = ref.watch(mascotKindProvider) == widget.kind;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: MascotView(
            key: const ValueKey('mascot-preview'),
            kind: widget.kind,
            mood: _mood,
            size: 180,
            semanticLabel: widget.kind.label,
          ),
        ),
        GhinaSpace.gapMd,
        Text(
          widget.kind.pitch,
          style: GhinaType.body.w(700).copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapLg,
        Text(
          'Coba ekspresinya',
          style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
        ),
        GhinaSpace.gapSm,
        ChunkyChoiceChips<MascotMood>(
          options: [
            for (final m in MascotMood.values)
              ChunkyChoice(value: m, label: m.label),
          ],
          selected: {_mood},
          onChanged: (s) => setState(() => _mood = s.first),
        ),
        GhinaSpace.gapXl,
        ChunkyButton(
          key: const ValueKey('mascot-use'),
          label: inUse ? 'Lagi dipakai' : 'Pakai maskot ini',
          icon: inUse ? Icons.check_rounded : Icons.favorite_rounded,
          expand: true,
          onPressed: inUse ? null : _use,
        ),
      ],
    );
  }
}

/// First-run "Pilih maskotmu" as a layer above the app's navigator, so
/// startup redirects (go/push) can neither sweep it away nor cover it.
/// A tap on the dimmed backdrop counts as "Nanti saja".
class MascotWelcomeLayer extends StatelessWidget {
  const MascotWelcomeLayer({super.key, required this.onDone});

  /// Called after a pick or "Nanti saja".
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final height = MediaQuery.sizeOf(context).height;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('mascot-welcome-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: onDone,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 640, maxHeight: height * 0.9),
            child: Material(
              color: g.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(GhinaRadii.xl),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: ChunkyBottomSheet(
                  title: 'Pilih maskotmu',
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: MascotWelcome(onDone: onDone),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The grid, "Pakai `maskot`" and "Nanti saja" of [MascotWelcomeLayer].
class MascotWelcome extends ConsumerStatefulWidget {
  const MascotWelcome({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<MascotWelcome> createState() => _MascotWelcomeState();
}

class _MascotWelcomeState extends ConsumerState<MascotWelcome> {
  late MascotKind _picked = ref.read(mascotKindProvider);
  bool _saving = false;

  Future<void> _use() async {
    setState(() => _saving = true);
    await ref.read(mascotKindProvider.notifier).select(_picked);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Siapa yang mau nemenin kamu? Bisa diganti kapan saja di '
          'Pengaturan.',
          style: GhinaType.body.w(700).copyWith(color: g.textSecondary),
        ),
        GhinaSpace.gapMd,
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            mainAxisExtent: 150,
            mainAxisSpacing: GhinaSpace.sm,
            crossAxisSpacing: GhinaSpace.sm,
          ),
          itemCount: MascotKind.values.length,
          itemBuilder: (context, i) {
            final kind = MascotKind.values[i];
            return _MascotTile(
              kind: kind,
              selected: kind == _picked,
              onTap: () => setState(() => _picked = kind),
            );
          },
        ),
        GhinaSpace.gapLg,
        ChunkyButton(
          key: const ValueKey('mascot-welcome-use'),
          label: 'Pakai ${_picked.label}',
          icon: Icons.favorite_rounded,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _use,
        ),
        GhinaSpace.gapSm,
        ChunkyButton(
          key: const ValueKey('mascot-welcome-later'),
          label: 'Nanti saja',
          variant: ChunkyButtonVariant.ghost,
          expand: true,
          onPressed: _saving ? null : widget.onDone,
        ),
      ],
    );
  }
}
