import 'package:flutter/material.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'chat_model.dart';

Uri chatImageUrl(
  KantorApi api,
  String sid,
  ChatImage img, {
  bool thumb = false,
}) => api.url('/api/sessions/$sid/image', {
  'path': img.path,
  if (thumb) 'thumb': '1',
});

void openChatImage(
  BuildContext context,
  KantorApi api,
  String sid,
  ChatImage img,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChatImageViewer(api: api, sid: sid, image: img),
    ),
  );
}

/// Thumbnail that hides itself when the file is gone (the daemon answers 404).
class _Thumb extends StatefulWidget {
  const _Thumb({
    required this.api,
    required this.sid,
    required this.image,
    required this.size,
    this.fit = BoxFit.cover,
  });

  final KantorApi api;
  final String sid;
  final ChatImage image;
  final double size;
  final BoxFit fit;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget box(Widget child) => Container(
      width: widget.size < 100 ? widget.size : null,
      height: widget.size < 100 ? widget.size * 0.75 : null,
      constraints: BoxConstraints(
        maxWidth: widget.size,
        maxHeight: widget.size,
        minWidth: 64,
        minHeight: 48,
      ),
      color: g.surfaceAlt,
      alignment: Alignment.center,
      child: child,
    );
    return GestureDetector(
      key: ValueKey('chat-thumb-${widget.image.path}'),
      onTap: () => openChatImage(context, widget.api, widget.sid, widget.image),
      child: ClipRRect(
        borderRadius: GhinaRadii.rMd,
        child: Image.network(
          chatImageUrl(
            widget.api,
            widget.sid,
            widget.image,
            thumb: true,
          ).toString(),
          headers: widget.api.authHeaders,
          fit: widget.fit,
          width: widget.size < 100 ? widget.size : null,
          height: widget.size < 100 ? widget.size * 0.75 : null,
          frameBuilder: (_, child, frame, sync) => frame == null && !sync
              ? box(
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.size,
                    maxHeight: widget.size,
                  ),
                  child: child,
                ),
          errorBuilder: (_, _, _) => box(
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 14,
                    color: g.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'gambar tidak tersedia',
                      maxLines: 2,
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A generated (`gen`) or owner-sent (`user`) picture in the conversation.
class ChatImageBubble extends StatelessWidget {
  const ChatImageBubble({
    super.key,
    required this.api,
    required this.sid,
    required this.image,
    required this.big,
  });

  final KantorApi? api;
  final String sid;
  final ChatImage image;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final a = api;
    if (a == null) return const SizedBox.shrink();
    final g = context.ghina;
    final w = MediaQuery.sizeOf(context).width;
    final size = big ? w * 0.7 : 120.0;
    final mine = image.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          _Thumb(
            api: a,
            sid: sid,
            image: image,
            size: size,
            fit: BoxFit.contain,
          ),
          if (image.generated)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size < 200 ? 220 : size),
              child: Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  image.caption.isEmpty
                      ? 'Gambar dibuat'
                      : 'Gambar dibuat: ${image.caption}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small thumbnails of pictures the agent viewed, shown with its tool run.
class ChatImageThumbs extends StatelessWidget {
  const ChatImageThumbs({
    super.key,
    required this.api,
    required this.sid,
    required this.images,
  });

  final KantorApi? api;
  final String sid;
  final List<ChatImage> images;

  @override
  Widget build(BuildContext context) {
    final a = api;
    if (a == null || images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final i in images) _Thumb(api: a, sid: sid, image: i, size: 96),
        ],
      ),
    );
  }
}

/// Full-screen picture with pinch / double-tap zoom.
class ChatImageViewer extends StatefulWidget {
  const ChatImageViewer({
    super.key,
    required this.api,
    required this.sid,
    required this.image,
  });

  final KantorApi api;
  final String sid;
  final ChatImage image;

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
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
    final img = widget.image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          img.name.isEmpty ? 'Gambar' : img.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _tap = d.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          key: const ValueKey('chat-image-zoom'),
          transformationController: _tc,
          minScale: 1,
          maxScale: 8,
          child: Center(
            child: Image.network(
              chatImageUrl(widget.api, widget.sid, img).toString(),
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
