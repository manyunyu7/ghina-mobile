import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_format.dart';
import 'pratinjau_widgets.dart';

/// Shows one pratinjau file at full size: image (pinch zoom), PDF (pdfrx),
/// video, HTML / bundle (WebView locked to the item's own `/pv/` prefix), or
/// a placeholder with "open in browser".
class PratinjauFileView extends StatelessWidget {
  const PratinjauFileView({
    super.key,
    required this.api,
    required this.item,
    required this.file,
    this.onCommentAt,
    this.videoKey,
  });

  final KantorApi api;
  final PratinjauItem item;
  final PratinjauFile file;

  /// Video only: "Komentar di 0:12" → called with the position in seconds.
  final ValueChanged<double>? onCommentAt;
  final GlobalKey<PratinjauVideoState>? videoKey;

  @override
  Widget build(BuildContext context) {
    final uri = pratinjauUri(api, file.url);
    return switch (file.kind) {
      'image' => InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            loadingBuilder: (_, child, p) => p == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) =>
                const EmptyState(title: 'Gambar gagal dimuat', compact: true),
          ),
        ),
      ),
      'pdf' => PdfViewer.uri(uri),
      'video' => PratinjauVideo(
        key: videoKey ?? ValueKey(uri),
        uri: pratinjauUri(api, file.playUrl),
        fallback: file.putarUrl != null ? uri : null,
        hint: file.putar == 'menyiapkan' ? 'menyiapkan video…' : null,
        markers: [
          for (final c in item.comments)
            if (c.t != null && (c.file == null || c.file == file.id)) c,
        ],
        onCommentAt: onCommentAt,
      ),
      'html' => PratinjauWeb(
        key: ValueKey(uri),
        uri: uri,
        prefix: pratinjauPrefix(api, file),
      ),
      _ => _Other(file: file, uri: uri),
    };
  }
}

class _Other extends StatelessWidget {
  const _Other({required this.file, required this.uri});
  final PratinjauFile file;
  final Uri uri;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(GhinaSpace.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pratinjauKindIcon(file.kind),
            size: 56,
            color: context.ghina.textMuted,
          ),
          const SizedBox(height: GhinaSpace.md),
          Text(
            file.name,
            textAlign: TextAlign.center,
            style: GhinaType.h3.copyWith(color: context.ghina.textPrimary),
          ),
          const SizedBox(height: GhinaSpace.xs),
          Text(
            '${file.mime.isEmpty ? file.kind : file.mime} · ${_size(file.size)}',
            style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
          ),
          const SizedBox(height: GhinaSpace.lg),
          ChunkyButton(
            label: 'Buka di browser',
            icon: Icons.open_in_new_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    ),
  );
}

String _size(int b) => b < 1024
    ? '$b B'
    : b < 1024 * 1024
    ? '${(b / 1024).toStringAsFixed(0)} KB'
    : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

/// HTML preview. JavaScript on; navigation outside [prefix] is blocked.
class PratinjauWeb extends StatefulWidget {
  const PratinjauWeb({super.key, required this.uri, required this.prefix});

  final Uri uri;
  final String prefix;

  @override
  State<PratinjauWeb> createState() => _PratinjauWebState();
}

class _PratinjauWebState extends State<PratinjauWeb> {
  late final WebViewController _c;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              r.url.startsWith(widget.prefix) ||
                  r.url.startsWith('about:') ||
                  r.url.startsWith('data:') ||
                  r.url.startsWith('blob:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return EmptyState(
        title: 'Halaman gagal dimuat',
        message: 'Pastikan kantor terjangkau, lalu coba lagi.',
        compact: true,
        actionLabel: 'Coba lagi',
        onAction: () {
          setState(() => _failed = false);
          _c.loadRequest(widget.uri);
        },
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _c),
        if (_progress < 100)
          LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
      ],
    );
  }
}

/// Minimal video player (signed URL, Range supported, no headers), with
/// comment markers over the progress bar and "Komentar di 0:12".
class PratinjauVideo extends StatefulWidget {
  const PratinjauVideo({
    super.key,
    required this.uri,
    this.fallback,
    this.hint,
    this.markers = const [],
    this.onCommentAt,
  });
  final Uri uri;

  /// Tried when [uri] fails (the original when [uri] is the H.264 copy).
  final Uri? fallback;
  final String? hint;
  final List<PratinjauComment> markers;
  final ValueChanged<double>? onCommentAt;

  @override
  State<PratinjauVideo> createState() => PratinjauVideoState();
}

class PratinjauVideoState extends State<PratinjauVideo> {
  late VideoPlayerController _c = VideoPlayerController.networkUrl(
    widget.uri,
  );
  Object? _error;
  bool _usedFallback = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _c
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          final fb = widget.fallback;
          if (fb != null && !_usedFallback && mounted) {
            _usedFallback = true;
            _c.removeListener(_tick);
            _c.dispose();
            setState(() => _c = VideoPlayerController.networkUrl(fb));
            _init();
            return;
          }
          if (mounted) setState(() => _error = e);
        });
    _c.addListener(_tick);
  }

  /// Seeks to [seconds] (comment markers / comment list).
  Future<void> seek(double seconds) =>
      _c.seekTo(Duration(milliseconds: (seconds * 1000).round()));

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  String _t(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    if (_error != null) {
      return EmptyState(
        title: 'Video tidak bisa diputar',
        compact: true,
        actionLabel: 'Buka di browser',
        onAction: () =>
            launchUrl(widget.uri, mode: LaunchMode.externalApplication),
      );
    }
    if (!v.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (widget.hint != null) ...[
              const SizedBox(height: GhinaSpace.sm),
              Text(
                widget.hint!,
                style: GhinaType.caption.copyWith(
                  color: context.ghina.textMuted,
                ),
              ),
            ],
          ],
        ),
      );
    }
    final total = v.duration.inMilliseconds / 1000;
    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => v.isPlaying ? _c.pause() : _c.play(),
              child: Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio,
                  child: VideoPlayer(_c),
                ),
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(
                  v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
              ),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: LayoutBuilder(
                    builder: (_, box) => Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        VideoProgressIndicator(_c, allowScrubbing: true),
                        if (total > 0)
                          for (final m in widget.markers)
                            Positioned(
                              left:
                                  (m.t! / total).clamp(0.0, 1.0) *
                                      box.maxWidth -
                                  7,
                              top: 0,
                              child: Tooltip(
                                message: m.text,
                                child: GestureDetector(
                                  onTap: () => seek(m.t!),
                                  child: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 14,
                                    color: Color(0xFFFFC800),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_t(v.position)} / ${_t(v.duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          if (widget.onCommentAt != null || widget.hint != null)
            Row(
              children: [
                if (widget.hint != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      widget.hint!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Spacer(),
                if (widget.onCommentAt != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.add_comment_rounded, size: 18),
                    label: Text('Komentar di ${_t(v.position)}'),
                    onPressed: () {
                      _c.pause();
                      widget.onCommentAt!(
                        v.position.inMilliseconds / 1000,
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Full-screen viewer for one file.
class PratinjauFullscreen extends StatelessWidget {
  const PratinjauFullscreen({
    super.key,
    required this.api,
    required this.item,
    required this.file,
  });

  final KantorApi api;
  final PratinjauItem item;
  final PratinjauFile file;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ghina.background,
    appBar: AppBar(
      title: Text(kantorShort(file.name, 40), overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Buka di browser',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => launchUrl(
            pratinjauUri(api, file.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: PratinjauFileView(api: api, item: item, file: file),
    ),
  );
}
