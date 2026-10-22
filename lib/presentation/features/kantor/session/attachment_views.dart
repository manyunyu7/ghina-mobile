import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'attachment_files.dart';
import 'attachment_model.dart';
import 'attachment_uploader.dart';
import 'chat_model.dart' show hhmm;

const _mediaWidth = 232.0;

void _toast(BuildContext context, String message, {bool ok = true}) =>
    showToastBadge(
      context,
      message: message,
      icon: ok ? Icons.check_rounded : Icons.error_outline_rounded,
      color: ok ? GhinaColors.green : GhinaColors.red,
      tag: 'kantor-att',
    );

/// An attachment in the chat stream: agent's on the left, owner's on the
/// right. Image/video show the thumbnail (bearer header); a tap opens the
/// full-screen viewer; other files are a card with download/share.
class AttachmentBubble extends StatefulWidget {
  const AttachmentBubble({super.key, required this.item, required this.api});

  final KantorAttachment item;
  final KantorApi? api;

  @override
  State<AttachmentBubble> createState() => _AttachmentBubbleState();
}

class _AttachmentBubbleState extends State<AttachmentBubble> {
  double? _progress;

  KantorAttachment get a => widget.item;

  void _open() {
    final api = widget.api;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => a.kind == AttachmentKind.video
            ? KantorVideoViewer(item: a, api: api)
            : KantorImageViewer(item: a, api: api),
      ),
    );
  }

  Future<void> _download() async {
    final api = widget.api;
    if (api == null || _progress != null) return;
    setState(() => _progress = 0);
    try {
      final f = await downloadAttachment(
        api,
        a,
        onProgress: (got, total) {
          if (mounted && total > 0) setState(() => _progress = got / total);
        },
      );
      if (mounted) setState(() => _progress = null);
      await shareAttachmentFile(f, a);
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        _toast(context, 'Gagal mengunduh ${a.name}', ok: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final mine = a.mine;
    final body = switch (a.kind) {
      AttachmentKind.file || AttachmentKind.audio => _fileCard(g),
      _ => _media(g),
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!mine && a.agent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                a.agent,
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: mine ? GhinaColors.blue.base : g.surface,
              borderRadius: BorderRadius.circular(GhinaRadii.lg),
              border: mine ? null : Border.all(color: g.border, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body,
                if (a.mine && !a.delivered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                    child: Text(
                      'Tersimpan, belum diketik ke agen.',
                      style: GhinaType.caption.copyWith(
                        color: GhinaColors.blue.on,
                      ),
                    ),
                  ),
                if (a.caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _mediaWidth),
                      child: SelectableText(
                        a.caption,
                        style: GhinaType.body.copyWith(
                          color: mine ? GhinaColors.blue.on : g.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hhmm(a.at).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                hhmm(a.at),
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _media(GhinaTokens g) {
    final api = widget.api;
    final video = a.kind == AttachmentKind.video;
    return Semantics(
      button: true,
      label: video ? 'Putar ${a.name}' : 'Buka ${a.name}',
      child: InkWell(
        key: ValueKey('att-${a.id}'),
        borderRadius: BorderRadius.circular(GhinaRadii.md),
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GhinaRadii.md),
          child: SizedBox(
            width: _mediaWidth,
            height: 176,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: g.surfaceAlt),
                if (api != null && a.hasThumb)
                  Image.network(
                    api.url(a.thumbPath).toString(),
                    headers: api.authHeaders,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        video ? Icons.videocam_rounded : Icons.image_rounded,
                        color: g.textMuted,
                        size: 36,
                      ),
                    ),
                  ),
                if (video && a.processing)
                  const Positioned(
                    left: 8,
                    bottom: 8,
                    child: _Pill('Memproses...'),
                  ),
                if (video)
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileCard(GhinaTokens g) {
    final fg = a.mine ? GhinaColors.blue.on : g.textPrimary;
    return InkWell(
      key: ValueKey('att-${a.id}'),
      borderRadius: BorderRadius.circular(GhinaRadii.md),
      onTap: _download,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _mediaWidth + 40,
          minWidth: 180,
        ),
        child: Padding(
          padding: const EdgeInsets.all(GhinaSpace.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                a.kind == AttachmentKind.audio
                    ? Icons.audiotrack_rounded
                    : Icons.insert_drive_file_rounded,
                color: fg,
                size: 30,
              ),
              const SizedBox(width: GhinaSpace.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GhinaType.bodyS.w(800).copyWith(color: fg),
                    ),
                    Text(
                      fmtSize(a.size),
                      style: GhinaType.caption.copyWith(
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                    if (_progress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 4,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              Icon(Icons.ios_share_rounded, color: fg, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}

/// The file being sent: name, progress bar, Batal while it runs, Coba lagi /
/// Buang when it failed.
class UploadBubble extends StatelessWidget {
  const UploadBubble({
    super.key,
    required this.job,
    required this.onCancel,
    required this.onRetry,
  });

  final UploadJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final failed = job.status == UploadStatus.failed;
    final status = switch (job.status) {
      UploadStatus.queued => 'Menunggu giliran...',
      UploadStatus.uploading => 'Mengunggah ${job.percent}%',
      UploadStatus.done => 'Terkirim',
      UploadStatus.failed => job.error ?? 'Gagal mengunggah',
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: ValueKey('upload-${job.id}'),
        constraints: const BoxConstraints(maxWidth: _mediaWidth + 40),
        padding: const EdgeInsets.all(GhinaSpace.sm),
        decoration: BoxDecoration(
          color: g.surface,
          borderRadius: BorderRadius.circular(GhinaRadii.lg),
          border: Border.all(
            color: failed ? GhinaColors.red.base : g.border,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  job.isVideo
                      ? Icons.videocam_rounded
                      : job.isImage
                      ? Icons.image_rounded
                      : Icons.insert_drive_file_rounded,
                  color: g.textSecondary,
                ),
                const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  child: Text(
                    job.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                Text(
                  fmtSize(job.size),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
            if (!failed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: job.status == UploadStatus.queued
                      ? null
                      : job.fraction,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              status,
              style: GhinaType.caption.copyWith(
                color: failed ? GhinaColors.red.base : g.textSecondary,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (failed)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Coba lagi'),
                  ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(failed ? 'Buang' : 'Batal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerActions extends StatefulWidget {
  const _ViewerActions({required this.item, required this.api});

  final KantorAttachment item;
  final KantorApi api;

  @override
  State<_ViewerActions> createState() => _ViewerActionsState();
}

class _ViewerActionsState extends State<_ViewerActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(File f) go) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await go(await downloadAttachment(widget.api, widget.item));
    } catch (e) {
      if (mounted) _toast(context, 'Gagal: $e', ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Simpan ke galeri',
          icon: const Icon(Icons.download_rounded),
          onPressed: () => _run((f) async {
            final ok = await saveToGallery(f, widget.item);
            if (mounted && context.mounted) {
              _toast(
                context,
                ok ? 'Tersimpan di galeri' : 'Izin galeri dibutuhkan',
                ok: ok,
              );
            }
          }),
        ),
        IconButton(
          tooltip: 'Bagikan',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => _run((f) => shareAttachmentFile(f, widget.item)),
        ),
      ],
    );
  }
}

/// Full-screen picture: pinch / double-tap zoom, save to gallery, share.
class KantorImageViewer extends StatefulWidget {
  const KantorImageViewer({super.key, required this.item, required this.api});

  final KantorAttachment item;
  final KantorApi api;

  @override
  State<KantorImageViewer> createState() => _KantorImageViewerState();
}

class _KantorImageViewerState extends State<KantorImageViewer>
    with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  Offset _tap = Offset.zero;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (_tc.value.getMaxScaleOnAxis() > 1.05) {
      _tc.value = Matrix4.identity();
    } else {
      const s = 2.5;
      _tc.value = Matrix4.identity()
        ..translateByDouble(-_tap.dx * (s - 1), -_tap.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.item;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          a.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [_ViewerActions(item: a, api: widget.api)],
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _tap = d.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          key: const ValueKey('image-zoom'),
          transformationController: _tc,
          minScale: 1,
          maxScale: 8,
          child: Center(
            child: Image.network(
              widget.api.url(a.rawPath).toString(),
              headers: widget.api.authHeaders,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : Center(
                      child: CircularProgressIndicator(
                        value: p.expectedTotalBytes == null
                            ? null
                            : p.cumulativeBytesLoaded / p.expectedTotalBytes!,
                        color: Colors.white,
                      ),
                    ),
              errorBuilder: (_, _, _) => const Center(
                child: Text(
                  'Gambar tidak bisa dimuat.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Streams the video from `/raw` (Range requests, bearer header).
class KantorVideoViewer extends StatefulWidget {
  const KantorVideoViewer({super.key, required this.item, required this.api});

  final KantorAttachment item;
  final KantorApi api;

  @override
  State<KantorVideoViewer> createState() => _KantorVideoViewerState();
}

class _KantorVideoViewerState extends State<KantorVideoViewer> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    widget.api.url(widget.item.rawPath),
    httpHeaders: widget.api.authHeaders,
  );
  Object? _error;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _c.play();
          _autoHide();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
    _c.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  String _t(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [_ViewerActions(item: widget.item, api: widget.api)],
      ),
      body: _error != null
          ? const Center(
              child: Text(
                'Video tidak bisa diputar.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : !v.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _controls = !_controls);
                if (_controls) _autoHide();
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_c),
                    ),
                  ),
                  if (v.isBuffering)
                    const CircularProgressIndicator(color: Colors.white),
                  if (_controls)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                key: const ValueKey('video-toggle'),
                                color: Colors.white,
                                icon: Icon(
                                  v.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: () {
                                  if (v.isPlaying) {
                                    _c.pause();
                                  } else {
                                    _c.play();
                                    _autoHide();
                                  }
                                },
                              ),
                              Text(
                                _t(v.position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: v.position.inMilliseconds
                                      .clamp(0, v.duration.inMilliseconds)
                                      .toDouble(),
                                  max: v.duration.inMilliseconds
                                      .toDouble()
                                      .clamp(1, double.infinity),
                                  onChanged: (x) => _c.seekTo(
                                    Duration(milliseconds: x.round()),
                                  ),
                                ),
                              ),
                              Text(
                                _t(v.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
