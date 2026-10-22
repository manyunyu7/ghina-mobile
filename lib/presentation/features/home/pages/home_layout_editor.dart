import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../layout/home_layout.dart';
import '../layout/home_layout_store.dart';
import '../layout/home_presets.dart';

/// "Atur beranda": show / hide, reorder, resize and add cards, or start from a
/// preset. Every change is saved straight away and Beranda follows live.
class HomeLayoutEditorPage extends ConsumerWidget {
  const HomeLayoutEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final layout = ref.watch(homeLayoutProvider);
    final notifier = ref.read(homeLayoutProvider.notifier);
    final preset = homePresetById(layout.presetId);
    final changed = preset != null && preset.toLayout() != layout;

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: const Text('Atur beranda'),
        actions: [
          TextButton(
            key: const ValueKey('layout-reset'),
            onPressed: () {
              notifier.reset();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Beranda dikembalikan ke Seimbang.'),
                ),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          GhinaSpace.sm,
          GhinaSpace.page,
          GhinaSpace.xxl,
        ),
        children: [
          ChunkyCard(
            key: const ValueKey('layout-preset-card'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HomePresetGalleryPage(),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  preset?.icon ?? Icons.dashboard_customize_rounded,
                  color: GhinaColors.purple.base,
                ),
                const SizedBox(width: GhinaSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preset: ${preset?.name ?? 'Susunan sendiri'}'
                        '${changed ? ' (diubah)' : ''}',
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                      Text(
                        'Lihat ${homePresets.length} preset dan pratinjaunya.',
                        style: GhinaType.caption.copyWith(
                          color: g.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: g.textMuted),
              ],
            ),
          ),
          SectionHeader(
            title: 'Kartu di beranda',
            subtitle: 'Seret gagang untuk mengurutkan.',
          ),
          if (layout.entries.isEmpty)
            Text(
              'Belum ada kartu. Tambahkan dari daftar di bawah.',
              style: GhinaType.bodyS.copyWith(color: g.textSecondary),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => notifier.set(layout.move(from, to)),
              children: [
                for (final (i, e) in layout.entries.indexed)
                  _EntryRow(
                    key: ValueKey('layout-row-${e.card.wire}'),
                    index: i,
                    entry: e,
                    onSize: (s) => notifier.set(layout.resize(e.card, s)),
                    onHide: () => notifier.set(layout.remove(e.card)),
                  ),
              ],
            ),
          if (layout.hidden.isNotEmpty) ...[
            const SectionHeader(title: 'Tambah kartu'),
            for (final c in layout.hidden)
              Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                child: ChunkyCard(
                  key: ValueKey('layout-add-${c.wire}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: GhinaSpace.md,
                    vertical: GhinaSpace.sm,
                  ),
                  onTap: () => notifier.set(layout.add(c)),
                  child: Row(
                    children: [
                      Icon(c.icon, color: g.textSecondary),
                      const SizedBox(width: GhinaSpace.md),
                      Expanded(
                        child: Text(
                          c.title,
                          style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                        ),
                      ),
                      Icon(
                        Icons.add_circle_rounded,
                        color: GhinaColors.green.base,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: GhinaSpace.md),
          Text(
            'Susunan disimpan di perangkat ini saja.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.onSize,
    required this.onHide,
  });

  final int index;
  final HomeEntry entry;
  final ValueChanged<HomeCardSize> onSize;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = entry.card;
    final sizes = HomeCardSize.values.where(c.sizes.contains).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.xs,
          GhinaSpace.xs,
          GhinaSpace.xs,
          GhinaSpace.xs,
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              key: ValueKey('layout-handle-${c.wire}'),
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(GhinaSpace.sm),
                child: Icon(Icons.drag_indicator_rounded, color: g.textMuted),
              ),
            ),
            Icon(c.icon, color: g.textSecondary, size: 20),
            const SizedBox(width: GhinaSpace.sm),
            Expanded(
              child: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
              ),
            ),
            if (sizes.length > 1)
              PopupMenuButton<HomeCardSize>(
                key: ValueKey('layout-size-${c.wire}'),
                tooltip: 'Ukuran kartu',
                initialValue: entry.size,
                onSelected: onSize,
                itemBuilder: (_) => [
                  for (final s in sizes)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GhinaSpace.sm,
                  ),
                  child: ChunkyPill(label: entry.size.label, soft: true),
                ),
              ),
            IconButton(
              key: ValueKey('layout-hide-${c.wire}'),
              tooltip: 'Sembunyikan',
              icon: Icon(Icons.visibility_off_rounded, color: g.textMuted),
              onPressed: onHide,
            ),
          ],
        ),
      ),
    );
  }
}

/// All presets with a wireframe of each; tapping one installs it.
class HomePresetGalleryPage extends ConsumerWidget {
  const HomePresetGalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final layout = ref.watch(homeLayoutProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Preset beranda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          GhinaSpace.sm,
          GhinaSpace.page,
          GhinaSpace.xxl,
        ),
        children: [
          Text(
            'Pilih satu sebagai titik awal. Sesudahnya kamu tetap bisa menambah, menyembunyikan, dan mengurutkan kartu.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.md),
          for (final p in homePresets)
            Padding(
              padding: const EdgeInsets.only(bottom: GhinaSpace.md),
              child: _PresetCard(
                preset: p,
                current: layout.presetId == p.id,
                modified: layout.presetId == p.id && p.toLayout() != layout,
                onPick: () {
                  ref.read(homeLayoutProvider.notifier).applyPreset(p);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Preset ${p.name} dipasang. Kamu masih bisa mengubahnya.',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.current,
    required this.modified,
    required this.onPick,
  });

  final HomePreset preset;
  final bool current;
  final bool modified;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: ValueKey('preset-${preset.id}'),
      tinted: current ? GhinaColors.purple : null,
      onTap: onPick,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomePresetPreview(entries: preset.entries),
          const SizedBox(width: GhinaSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(preset.icon, size: 18, color: GhinaColors.purple.base),
                    const SizedBox(width: GhinaSpace.xs),
                    Expanded(
                      child: Text(
                        preset.name,
                        style: GhinaType.h3.copyWith(color: g.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GhinaSpace.xs),
                Text(
                  preset.description,
                  style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: GhinaSpace.sm),
                Text(
                  '${preset.entries.length} kartu: '
                  '${preset.entries.take(4).map((e) => e.card.title).join(', ')}'
                  '${preset.entries.length > 4 ? '…' : ''}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
                if (current) ...[
                  const SizedBox(height: GhinaSpace.sm),
                  ChunkyPill(
                    label: modified ? 'Dipakai (diubah)' : 'Dipakai',
                    color: GhinaColors.purple,
                    soft: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A miniature wireframe of a layout: full-width cards are bars, small cards
/// pair up side by side.
class HomePresetPreview extends StatelessWidget {
  const HomePresetPreview({super.key, required this.entries});

  final List<HomeEntry> entries;

  static const _colors = [
    GhinaColors.blue,
    GhinaColors.green,
    GhinaColors.orange,
    GhinaColors.purple,
    GhinaColors.pink,
    GhinaColors.yellow,
  ];

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget bar(HomeEntry e, {double? height}) => Container(
      height: height ?? (e.size == HomeCardSize.small ? 22 : 16),
      decoration: BoxDecoration(
        color: _colors[e.card.index % _colors.length].base.withValues(
          alpha: 0.32,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 3),
      child: Icon(
        e.card.icon,
        size: 9,
        color: _colors[e.card.index % _colors.length].base,
      ),
    );
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.size == HomeCardSize.small) {
        final next =
            i + 1 < entries.length && entries[i + 1].size == HomeCardSize.small
            ? entries[i + 1]
            : null;
        rows.add(
          Row(
            children: [
              Expanded(child: bar(e)),
              const SizedBox(width: 3),
              Expanded(child: next == null ? const SizedBox() : bar(next)),
            ],
          ),
        );
        if (next != null) i++;
      } else {
        rows.add(bar(e, height: e.size == HomeCardSize.wide ? 22 : 16));
      }
    }
    return Container(
      width: 84,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: g.surface,
        border: Border.all(color: g.border, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 3),
            r,
          ],
        ],
      ),
    );
  }
}
