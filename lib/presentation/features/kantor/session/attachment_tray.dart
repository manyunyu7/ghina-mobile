import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'attach_picker.dart';

/// Most files one message may carry (same as the web chat and the daemon).
const maxStagedFiles = 20;

/// A file chosen but not sent yet: it waits in the tray above the message
/// field until Kirim.
class StagedFile {
  const StagedFile(this.key, this.file);

  /// Unique within the tray (the same file can be picked twice).
  final String key;
  final PickedAttachment file;
}

/// The tray above the message field: one thumbnail per held file with a
/// remove button, and a line telling the owner what happens next. Empty
/// [items] draw nothing.
class AttachmentTray extends StatelessWidget {
  const AttachmentTray({
    super.key,
    required this.items,
    required this.onRemove,
  });

  final List<StagedFile> items;
  final void Function(StagedFile item) onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    return Padding(
      key: const ValueKey('attachment-tray'),
      padding: const EdgeInsets.fromLTRB(GhinaSpace.md, GhinaSpace.xs, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: GhinaSpace.md),
            child: Text(
              '${items.length} file · tulis konteksnya lalu Kirim',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 6, right: GhinaSpace.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  _TrayItem(item: items[i], onRemove: () => onRemove(items[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayItem extends StatelessWidget {
  const _TrayItem({required this.item, required this.onRemove});

  final StagedFile item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final f = item.file;
    final name = f.name.isEmpty ? 'gambar tempel' : f.name;
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : 'FILE';
    Widget face;
    if (f.mime.startsWith('image/')) {
      face = Image.file(
        f.file,
        fit: BoxFit.cover,
        cacheWidth: 192,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_rounded),
      );
    } else if (f.mime.startsWith('video/')) {
      face = Icon(Icons.play_circle_outline_rounded, color: g.textMuted);
    } else {
      face = Text(
        ext.length > 4 ? ext.substring(0, 4) : ext,
        style: GhinaType.bodyS.w(800).copyWith(color: g.textMuted),
      );
    }
    return SizedBox(
      width: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: g.surfaceAlt,
                  borderRadius: GhinaRadii.rMd,
                  border: Border.all(color: g.border, width: 2),
                ),
                child: face,
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ],
          ),
          Positioned(
            top: -6,
            right: 0,
            child: Semantics(
              button: true,
              label: 'Hapus $name',
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('tray-remove-${item.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: g.textPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: g.surface, width: 2),
                  ),
                  child: Icon(Icons.close_rounded, size: 14, color: g.surface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
