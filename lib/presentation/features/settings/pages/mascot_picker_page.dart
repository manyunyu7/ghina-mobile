import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                      'nabung. Ketuk salah satu buat lihat ekspresinya.'
                      '${Theme.of(context).platform == TargetPlatform.android ? ' Ikon & layar pembuka Ghina ikut ganti begitu kamu keluar dari aplikasi.' : ''}',
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
