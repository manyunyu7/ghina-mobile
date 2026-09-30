import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config.dart';
import '../../../../core/formatters.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_chat_controller.dart';
import 'killa_common.dart';

/// Day separator chip: `Hari ini`, `Kemarin`, `Sen, 28 Sep`.
class KillaDaySeparator extends StatelessWidget {
  const KillaDaySeparator({super.key, required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final rel = Fmt.relativeDay(day, now: now);
    final label = const {'Hari ini', 'Kemarin'}.contains(rel)
        ? rel
        : Fmt.dateShortWeekday(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: g.surfaceAlt,
            borderRadius: GhinaRadii.rPill,
            border: Border.all(color: g.border),
          ),
          child: Text(
            label,
            style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// A `system` message ("Sesi baru") as a divider line.
class KillaSystemDivider extends StatelessWidget {
  const KillaSystemDivider({super.key, required this.message});

  final KillaMessage message;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final text = message.body.trim().isEmpty ? 'Sesi baru' : message.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: g.border, thickness: 2)),
          const SizedBox(width: 10),
          Icon(Icons.auto_awesome_rounded, size: 14, color: killaSwatch.base),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$text · ${Fmt.time(message.createdAt)}',
              style: GhinaType.caption.w(800).copyWith(color: g.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: g.border, thickness: 2)),
        ],
      ),
    );
  }
}

/// A user / assistant bubble with attachments, time, model and a WA badge.
class KillaBubble extends StatelessWidget {
  const KillaBubble({super.key, required this.message});

  final KillaMessage message;

  bool get _mine => message.role == KillaRole.user;

  void _menu(BuildContext context) {
    HapticFeedback.mediumImpact();
    if (message.body.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: message.body));
    showOkToast(context, 'Pesan disalin', icon: Icons.copy_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = message;
    final mine = _mine;
    final bg = mine
        ? (g.isDark ? killaSwatch.edge : killaSwatch.base)
        : g.surface;
    final fg = mine ? Colors.white : g.textPrimary;
    final meta = mine ? Colors.white.withValues(alpha: 0.8) : g.textMuted;
    final maxW = MediaQuery.sizeOf(context).width * 0.84;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: GestureDetector(
          onLongPress: () => _menu(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 6),
                bottomRight: Radius.circular(mine ? 6 : 20),
              ),
              border: mine ? null : Border.all(color: g.border, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.attachments.isNotEmpty) ...[
                  KillaAttachments(attachments: m.attachments, onDark: mine),
                  if (m.body.trim().isNotEmpty) const SizedBox(height: 8),
                ],
                if (m.body.trim().isNotEmpty)
                  mine
                      ? SelectableText(
                          m.body,
                          style: GhinaType.body.copyWith(
                            color: fg,
                            height: 1.4,
                          ),
                        )
                      : KillaMarkdown(text: m.body),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.channel == KillaChannel.wa) ...[
                      const _WaBadge(),
                      const SizedBox(width: 6),
                    ],
                    if (!mine && m.model != null) ...[
                      Text(
                        m.model!,
                        style: GhinaType.caption
                            .w(800)
                            .copyWith(color: killaSwatch.base),
                      ),
                      Text(
                        ' · ',
                        style: GhinaType.caption.copyWith(color: meta),
                      ),
                    ],
                    Text(
                      Fmt.time(m.createdAt),
                      style: GhinaType.caption.copyWith(color: meta),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaBadge extends StatelessWidget {
  const _WaBadge();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Dari WhatsApp',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366),
        borderRadius: GhinaRadii.rPill,
      ),
      child: Text(
        'WA',
        style: GhinaType.caption.w(900).copyWith(color: Colors.white),
      ),
    ),
  );
}

/// Attachments of a message: images as thumbnails (tap → viewer), other
/// files as chips (tap → open).
class KillaAttachments extends StatelessWidget {
  const KillaAttachments({
    super.key,
    required this.attachments,
    this.onDark = false,
  });

  final List<KillaAttachment> attachments;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final a in attachments)
        if (a.isImage) a,
    ];
    final files = [
      for (final a in attachments)
        if (!a.isImage) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in images)
                _ImageThumb(
                  attachment: a,
                  size: images.length == 1 ? 200 : 110,
                ),
            ],
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
        for (final a in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _FileChip(attachment: a, onDark: onDark),
          ),
      ],
    );
  }
}

class _ImageThumb extends ConsumerWidget {
  const _ImageThumb({required this.attachment, required this.size});

  final KillaAttachment attachment;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final a = attachment;
    Widget child;
    VoidCallback? onTap;
    if (!a.fromEngine) {
      final url = AppConfig.resolveUrl(a.path);
      child = url == null
          ? const _Broken()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _Broken(),
              loadingBuilder: (c, w, p) =>
                  p == null ? w : const Skeleton(width: 400, height: 400),
            );
      onTap = () => showPhotoViewer(context, [ViewerPhoto.network(a.path)]);
    } else {
      final media = ref.watch(killaMediaProvider(a.path));
      switch (media) {
        case AsyncData(:final value):
          child = Image.memory(
            value.bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _Broken(),
          );
          final local = value.localPath;
          onTap = local == null
              ? null
              : () => showPhotoViewer(context, [ViewerPhoto.file(local)]);
        case AsyncError():
          child = const _Broken();
          onTap = () => ref.invalidate(killaMediaProvider(a.path));
        default:
          child = const Skeleton(width: 400, height: 400);
      }
    }
    return Semantics(
      image: true,
      label: a.name,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: GhinaRadii.rMd,
          child: Container(
            width: size,
            height: size,
            color: g.surfaceAlt,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(Icons.broken_image_rounded, color: context.ghina.textMuted),
  );
}

class _FileChip extends ConsumerStatefulWidget {
  const _FileChip({required this.attachment, required this.onDark});

  final KillaAttachment attachment;
  final bool onDark;

  @override
  ConsumerState<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends ConsumerState<_FileChip> {
  bool _busy = false;

  Future<void> _open() async {
    final a = widget.attachment;
    if (!a.fromEngine) {
      final url = AppConfig.resolveUrl(a.path);
      if (url != null) await openKillaLink(context, url);
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await ref.read(killaMediaProvider(a.path).future);
      final local = file.localPath;
      var ok = false;
      if (local != null && File(local).existsSync()) {
        try {
          ok = await launchUrl(Uri.file(local));
        } catch (_) {
          ok = false;
        }
      }
      if (!ok && mounted) {
        showToastBadge(
          context,
          message: local == null
              ? 'Berkas diunduh, tapi belum bisa dibuka di HP ini'
              : 'Tersimpan sementara: ${local.split('/').last}',
          icon: Icons.download_done_rounded,
          color: GhinaColors.blue,
        );
      }
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } catch (_) {
      if (mounted) showErrorToast(context, 'Berkasnya belum bisa dibuka');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = widget.attachment;
    final fg = widget.onDark ? Colors.white : g.textPrimary;
    return Material(
      color: widget.onDark
          ? Colors.white.withValues(alpha: 0.16)
          : g.surfaceAlt,
      borderRadius: GhinaRadii.rMd,
      child: InkWell(
        borderRadius: GhinaRadii.rMd,
        onTap: _busy ? null : () => unawaited(_open()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(
                  a.isPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.insert_drive_file_rounded,
                  size: 18,
                  color: a.isPdf ? GhinaColors.red.base : fg,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(700).copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The message being sent: the user's bubble (with local previews) and
/// Killa "thinking" with the elapsed time.
class KillaPendingBubbles extends StatefulWidget {
  const KillaPendingBubbles({super.key, required this.pending});

  final KillaPending pending;

  @override
  State<KillaPendingBubbles> createState() => _KillaPendingBubblesState();
}

class _KillaPendingBubblesState extends State<KillaPendingBubbles> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = widget.pending;
    final secs = DateTime.now().difference(p.startedAt).inSeconds;
    final elapsed = secs < 60
        ? '$secs dtk'
        : '${secs ~/ 60} mnt ${(secs % 60).toString().padLeft(2, '0')} dtk';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Opacity(
            opacity: 0.75,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.84,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: g.isDark ? killaSwatch.edge : killaSwatch.base,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.media.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in p.media) KillaMediaPreview(media: m),
                      ],
                    ),
                  if (p.media.isNotEmpty && p.text.isNotEmpty)
                    const SizedBox(height: 8),
                  if (p.text.isNotEmpty)
                    Text(
                      p.text,
                      style: GhinaType.body.copyWith(
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Mengirim…',
                        style: GhinaType.caption.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: g.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: g.border, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _TypingDots(),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    secs < 20
                        ? 'Killa lagi mikir…'
                        : 'Killa lagi mikir… $elapsed '
                              '(bisa sampai ~5 menit)',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: killaSwatch.base.withValues(
                alpha:
                    0.35 +
                    0.65 *
                        (1 - ((_c.value * 3 - i) % 3 - 0.5).abs().clamp(0, 1)),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Thumbnail of a picked attachment (composer / pending bubble).
class KillaMediaPreview extends StatelessWidget {
  const KillaMediaPreview({
    super.key,
    required this.media,
    this.size = 64,
    this.onRemove,
  });

  final KillaOutgoingMedia media;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final body = media.isImage
        ? Image.memory(media.bytes, fit: BoxFit.cover)
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: GhinaColors.red.base),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  media.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
            ],
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: GhinaRadii.rMd,
          child: Container(
            width: size,
            height: size,
            color: g.surfaceAlt,
            child: body,
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -8,
            right: -8,
            child: Semantics(
              button: true,
              label: 'Hapus lampiran',
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: GhinaColors.red.base,
                    shape: BoxShape.circle,
                    border: Border.all(color: g.background, width: 2),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
