import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../../notes/widgets/link_open.dart';
import '../widgets/kantor_markdown.dart';
import 'wiki_documents.dart';
import 'wiki_format.dart';

/// Markdown for the Kantor wiki and notes: `[[Judul]]` links to wiki pages,
/// `/api/…/media/…` images fetched with the office token, tappable task items.
class WikiMarkdown extends StatelessWidget {
  const WikiMarkdown({
    super.key,
    required this.text,
    required this.api,
    this.onWikiLink,
    this.onToggleTask,
    this.onMedia,
  });

  final String text;
  final KantorApi? api;

  /// Tapped `[[Judul]]` (the title as written).
  final void Function(String title)? onWikiLink;

  /// Tapped task item, 0-based. Null = read-only checkboxes.
  final void Function(int index)? onToggleTask;

  /// Tapped link to an uploaded attachment (`/api/offices/…/media/<id>`).
  final void Function(String path)? onMedia;

  static final _videoExt = RegExp(
    r'\.(mp4|webm|mov|m4v)(?:[?#].*)?$',
    caseSensitive: false,
  );
  static final _videoLink = RegExp(r'\[([^\]\n]+)\]\((/api/[^)\s]+)\)');
  static final _youtube = RegExp(
    r'^\s*(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/watch\?(?:[^\s&]*&)*v=|youtu\.be/|youtube\.com/shorts/)([\w-]{11})(?:[&?#]\S*)?\s*$',
    multiLine: true,
  );

  /// Video url = path ending in a video extension (`…/media/<id>.mp4`).
  static bool isVideoUri(Uri uri) => _videoExt.hasMatch(uri.path);

  static String prepare(String src) => _prepareLinks(
    src
        // legacy file links `[📎 klip.mp4](/api/…/media/<id>)` become `![klip](/api/…/media/<id>.mp4)`
        .replaceAllMapped(_videoLink, (m) {
          final label = m[1]!.replaceFirst(RegExp(r'^\s*📎\s*'), '');
          final ext = _videoExt.firstMatch(label)?[1];
          if (m.start > 0 && src[m.start - 1] == '!') return m[0]!;
          // legacy PDF / markdown / text links become preview cards too
          final doc = RegExp(
            r'\.(pdf|md|markdown|txt)$',
            caseSensitive: false,
          ).firstMatch(label)?[1];
          if (ext == null && doc != null) {
            final url = isPdfUri(Uri.parse(m[2]!)) || isDocUri(Uri.parse(m[2]!))
                ? m[2]!
                : '${m[2]}.${doc.toLowerCase()}';
            return '![${label.replaceAll(']', ')')}]($url)';
          }
          if (ext == null) return m[0]!;
          final name = label.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
          final url = _videoExt.hasMatch(m[2]!) ? m[2]! : '${m[2]}.$ext';
          return '![${name.replaceAll(']', ')')}]($url)';
        })
        // a lone YouTube link becomes a card that opens the app/browser
        .replaceAllMapped(
          _youtube,
          (m) => '[▶ Putar di YouTube](https://youtu.be/${m[1]})',
        ),
  );

  static String _prepareLinks(String src) =>
      src.replaceAllMapped(RegExp(r'\[\[([^\]\n]+)\]\]'), (m) {
        final t = m[1]!.trim();
        final enc = Uri.encodeComponent(
          t,
        ).replaceAll('(', '%28').replaceAll(')', '%29');
        return '[${t.replaceAll('[', '(').replaceAll(']', ')')}](wiki:$enc)';
      });

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final base = Theme.of(context).textTheme;
    final body = GhinaType.body.copyWith(color: g.textPrimary, height: 1.5);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      h1: GhinaType.h1.copyWith(color: g.textPrimary),
      h2: GhinaType.h2.copyWith(color: g.textPrimary),
      h3: GhinaType.h3.copyWith(color: g.textPrimary),
      h4: GhinaType.body.w(800).copyWith(color: g.textPrimary),
      a: body.copyWith(
        color: GhinaColors.blue.base,
        decoration: TextDecoration.underline,
      ),
      listBullet: body,
      blockquote: body.copyWith(color: g.textSecondary),
      code: (base.bodyMedium ?? body).copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        color: g.textPrimary,
        backgroundColor: g.surfaceAlt,
      ),
      codeblockDecoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        border: Border.all(color: g.border),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: g.border, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: g.border)),
      ),
    );
    final styled = kantorTableSheet(sheet, g, body);
    final total = taskCount(text);
    var seen = 0;
    return MarkdownBody(
      data: prepare(text),
      styleSheet: styled,
      shrinkWrap: true,
      onTapLink: (label, href, _) {
        if (href == null) return;
        if (href.startsWith('wiki:')) {
          onWikiLink?.call(Uri.decodeComponent(href.substring(5)));
        } else if (href.startsWith('/api/')) {
          onMedia?.call(href);
        } else {
          openLink(context, href);
        }
      },
      checkboxBuilder: (checked) {
        final idx = total == 0 ? 0 : seen++ % total;
        return GestureDetector(
          onTap: onToggleTask == null ? null : () => onToggleTask!(idx),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 22,
              color: checked ? GhinaColors.green.base : g.textMuted,
            ),
          ),
        );
      },
      imageBuilder: (uri, title, alt) => isVideoUri(uri)
          ? _MediaVideo(uri: uri, alt: alt, api: api)
          : isPdfUri(uri)
          ? WikiPdfCard(uri: uri, alt: alt, api: api)
          : isDocUri(uri)
          ? WikiDocCard(uri: uri, alt: alt, api: api)
          : _MediaImage(uri: uri, alt: alt, api: api),
    );
  }
}

/// Image from the office media endpoint (token header) or a public https URL
/// (never sent the token).
class _MediaImage extends StatelessWidget {
  const _MediaImage({required this.uri, required this.alt, required this.api});

  final Uri uri;
  final String? alt;
  final KantorApi? api;

  @override
  Widget build(BuildContext context) {
    final own =
        uri.path.startsWith('/api/') && (!uri.hasScheme || uri.host.isEmpty);
    final String src;
    final Map<String, String>? headers;
    if (own) {
      if (api == null) return const SizedBox.shrink();
      src = api!
          .url(uri.path, uri.hasQuery ? uri.queryParameters : null)
          .toString();
      headers = api!.authHeaders;
    } else if (uri.scheme == 'https') {
      src = uri.toString();
      headers = null;
    } else {
      return const SizedBox.shrink();
    }
    final img = Image.network(
      src,
      headers: headers,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _Broken(alt: alt),
      loadingBuilder: (c, child, p) => p == null
          ? child
          : const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Image.network(
                      src,
                      headers: headers,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(borderRadius: GhinaRadii.rMd, child: img),
      ),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken({this.alt, this.what = 'Gambar'});
  final String? alt;
  final String what;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(GhinaSpace.md),
    decoration: BoxDecoration(
      color: context.ghina.surfaceAlt,
      borderRadius: GhinaRadii.rMd,
    ),
    child: Text(
      '$what tidak termuat${alt == null || alt!.isEmpty ? '' : ': $alt'}',
      style: GhinaType.bodyS.copyWith(color: context.ghina.textMuted),
    ),
  );
}

/// Inline video from the office media endpoint (token header) or public https:
/// first frame with a play button, seek bar, full screen on tap of the corner icon.
class _MediaVideo extends StatefulWidget {
  const _MediaVideo({required this.uri, required this.alt, required this.api});

  final Uri uri;
  final String? alt;
  final KantorApi? api;

  @override
  State<_MediaVideo> createState() => _MediaVideoState();
}

class _MediaVideoState extends State<_MediaVideo> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final uri = widget.uri;
    final own =
        uri.path.startsWith('/api/') && (!uri.hasScheme || uri.host.isEmpty);
    final Uri src;
    final Map<String, String> headers;
    if (own) {
      if (widget.api == null) {
        _failed = true;
        return;
      }
      src = widget.api!.url(
        uri.path,
        uri.hasQuery ? uri.queryParameters : null,
      );
      headers = widget.api!.authHeaders;
    } else if (uri.scheme == 'https') {
      src = uri;
      headers = const {};
    } else {
      _failed = true;
      return;
    }
    final c = VideoPlayerController.networkUrl(src, httpHeaders: headers);
    _c = c;
    c
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _fullscreen() {
    final c = _c!;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(child: _Controls(c: c, dark: true)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = _c;
    if (_failed || c == null) {
      return _Broken(alt: widget.alt, what: 'Video');
    }
    if (!c.value.isInitialized) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rMd,
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: GhinaRadii.rMd,
        child: Container(
          color: g.surfaceAlt,
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: c,
                      builder: (_, _) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                        child: c.value.isPlaying
                            ? const SizedBox.shrink()
                            : const Center(
                                child: Icon(
                                  Icons.play_circle_rounded,
                                  size: 56,
                                  color: Colors.white,
                                  shadows: [Shadow(blurRadius: 12)],
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Layar penuh',
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 8)],
                      ),
                      onPressed: _fullscreen,
                    ),
                  ),
                ],
              ),
              _Controls(c: c, dark: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.c, required this.dark});
  final VideoPlayerController c;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : context.ghina.textPrimary;
    return ListenableBuilder(
      listenable: c,
      builder: (_, _) => Row(
        children: [
          IconButton(
            color: fg,
            icon: Icon(
              c.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
          ),
          Expanded(
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: GhinaSpace.sm),
            ),
          ),
          const SizedBox(width: GhinaSpace.md),
        ],
      ),
    );
  }
}
