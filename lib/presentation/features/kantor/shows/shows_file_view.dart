import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../files/kantor_files_model.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';
import 'shows_mac.dart';

/// Reads one office file and shows it by kind: code with line numbers (the
/// [lines] range highlighted and scrolled into view), markdown, a zoomable
/// image, a player, or an info card with "Buka di Mac".
class KantorShowFileView extends ConsumerStatefulWidget {
  const KantorShowFileView({
    super.key,
    required this.office,
    required this.path,
    this.lines,
  });

  final String office;
  final String path;
  final (int, int)? lines;

  @override
  ConsumerState<KantorShowFileView> createState() => _KantorShowFileViewState();
}

class _KantorShowFileViewState extends ConsumerState<KantorShowFileView> {
  KantorFileInfo? _info;
  Object? _error;
  bool _raw = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _error = null);
    try {
      final j = await api.get(
        '${kantorFilesBase(widget.office)}/read',
        query: {'path': widget.path},
      );
      if (mounted)
        setState(
          () => _info = KantorFileInfo.fromJson(
            (j as Map).cast<String, dynamic>(),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _rawUrl(KantorApi api) => api.url(
    '${kantorFilesBase(widget.office)}/raw',
    {'path': widget.path},
  ).toString();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final info = _info;
    if (_error != null) return KantorErrorView(error: _error!, onRetry: _load);
    if (info == null) return const KantorLoading(count: 4);
    final isMd = info.kind == 'text' && info.ext == '.md';
    final range = widget.lines;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.sm,
            GhinaSpace.sm,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${info.path} · ${kantorFileSize(info.size)}'
                  '${info.truncated ? ' · hanya 1 MB pertama' : ''}'
                  '${range == null ? '' : ' · baris ${range.$1}${range.$2 > range.$1 ? '–${range.$2}' : ''} disorot'}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
              if (isMd)
                TextButton(
                  onPressed: () => setState(() => _raw = !_raw),
                  child: Text(_raw ? 'Tampilan rapi' : 'Lihat mentah'),
                ),
            ],
          ),
        ),
        Expanded(child: _body(context, info)),
      ],
    );
  }

  Widget _infoCard(KantorFileInfo info, String message) => ListView(
    children: [
      EmptyState(title: info.name, message: message, compact: true),
      KantorMacActions(office: widget.office, path: widget.path),
    ],
  );

  Widget _body(BuildContext context, KantorFileInfo info) {
    final api = ref.watch(kantorApiProvider);
    if (api == null) return const SizedBox.shrink();
    switch (info.kind) {
      case 'image':
        if (info.ext == '.svg')
          return _infoCard(info, 'Gambar SVG tidak ditampilkan di aplikasi.');
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.network(
              _rawUrl(api),
              headers: api.authHeaders,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) =>
                  const EmptyState(title: 'Gambar gagal dimuat', compact: true),
            ),
          ),
        );
      case 'text':
        if (info.ext == '.md' && !_raw && widget.lines == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            child: KantorMarkdown(info.text, selectable: true),
          );
        }
        return KantorShowCode(text: info.text, range: widget.lines);
      case 'video':
        return _VideoPlayerBody(
          url: _rawUrl(api),
          headers: api.authHeaders,
          fallback: _infoCard(
            info,
            'Video tidak bisa diputar di sini (${kantorFileSize(info.size)}).',
          ),
        );
      case 'audio':
        return _AudioPlayerBody(
          name: info.name,
          url: _rawUrl(api),
          headers: api.authHeaders,
          fallback: _infoCard(
            info,
            'Audio tidak bisa diputar di sini (${kantorFileSize(info.size)}).',
          ),
        );
      case 'pdf':
        return _infoCard(
          info,
          'PDF (${kantorFileSize(info.size)}) dibuka di Mac.',
        );
      default:
        return _infoCard(
          info,
          'File biner (${kantorFileSize(info.size)}) tidak bisa ditampilkan di HP.',
        );
    }
  }
}

/// Monospace lines with numbers. Fixed line height lets the highlighted range
/// be scrolled to without building every row; long lines scroll sideways.
class KantorShowCode extends StatefulWidget {
  const KantorShowCode({super.key, required this.text, this.range});

  final String text;
  final (int, int)? range;

  @override
  State<KantorShowCode> createState() => _KantorShowCodeState();
}

class _KantorShowCodeState extends State<KantorShowCode> {
  static const _lineHeight = 20.0;
  static const _fontSize = 12.5;
  static const _charWidth = _fontSize * 0.62;

  final _scroll = ScrollController();
  late final List<String> _lines = widget.text.split('\n');

  @override
  void initState() {
    super.initState();
    final r = widget.range;
    if (r != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target =
            (r.$1 - 1) * _lineHeight - _scroll.position.viewportDimension / 3;
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = widget.range;
    final digits = '${_lines.length}'.length;
    final gutter = digits * _charWidth + 14;
    final longest = _lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final style = GhinaType.caption.copyWith(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.0,
      color: g.textPrimary,
    );
    return LayoutBuilder(
      builder: (_, c) {
        final width = (gutter + longest * _charWidth + 24).clamp(
          c.maxWidth,
          12000.0,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _lineHeight,
              itemCount: _lines.length,
              itemBuilder: (_, i) {
                final hl = r != null && i + 1 >= r.$1 && i + 1 <= r.$2;
                return Container(
                  key: ValueKey('code-line-${i + 1}'),
                  color: hl
                      ? GhinaColors.yellow.base.withValues(alpha: 0.28)
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: GhinaSpace.sm,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      SizedBox(
                        width: gutter - 8,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: style.copyWith(color: g.textMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lines[i],
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _VideoPlayerBody extends StatefulWidget {
  const _VideoPlayerBody({
    required this.url,
    required this.headers,
    required this.fallback,
  });

  final String url;
  final Map<String, String> headers;
  final Widget fallback;

  @override
  State<_VideoPlayerBody> createState() => _VideoPlayerBodyState();
}

class _VideoPlayerBodyState extends State<_VideoPlayerBody> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
    httpHeaders: widget.headers,
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c
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
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    if (!_c.value.isInitialized)
      return const Center(child: CircularProgressIndicator());
    return ListenableBuilder(
      listenable: _c,
      builder: (_, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: _c.value.aspectRatio,
            child: VideoPlayer(_c),
          ),
          VideoProgressIndicator(
            _c,
            allowScrubbing: true,
            padding: const EdgeInsets.all(GhinaSpace.md),
          ),
          IconButton(
            iconSize: 40,
            icon: Icon(
              _c.value.isPlaying
                  ? Icons.pause_circle_rounded
                  : Icons.play_circle_rounded,
            ),
            onPressed: () => _c.value.isPlaying ? _c.pause() : _c.play(),
          ),
        ],
      ),
    );
  }
}

class _AudioPlayerBody extends StatefulWidget {
  const _AudioPlayerBody({
    required this.name,
    required this.url,
    required this.headers,
    required this.fallback,
  });

  final String name;
  final String url;
  final Map<String, String> headers;
  final Widget fallback;

  @override
  State<_AudioPlayerBody> createState() => _AudioPlayerBodyState();
}

class _AudioPlayerBodyState extends State<_AudioPlayerBody> {
  final _p = AudioPlayer();
  Duration? _total;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _p
        .setUrl(widget.url, headers: widget.headers)
        .then((d) {
          if (mounted) setState(() => _total = d);
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final total = _total?.inMilliseconds ?? 0;
    return Padding(
      padding: const EdgeInsets.all(GhinaSpace.page),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.name,
            style: GhinaType.h3.copyWith(color: context.ghina.textPrimary),
          ),
          StreamBuilder<Duration>(
            stream: _p.positionStream,
            builder: (_, snap) {
              final pos = (snap.data ?? Duration.zero).inMilliseconds;
              return Slider(
                value: total == 0 ? 0 : pos.clamp(0, total).toDouble(),
                max: total == 0 ? 1 : total.toDouble(),
                onChanged: total == 0
                    ? null
                    : (v) => _p.seek(Duration(milliseconds: v.round())),
              );
            },
          ),
          StreamBuilder<PlayerState>(
            stream: _p.playerStateStream,
            builder: (_, snap) {
              final playing = snap.data?.playing ?? false;
              return IconButton(
                iconSize: 48,
                icon: Icon(
                  playing
                      ? Icons.pause_circle_rounded
                      : Icons.play_circle_rounded,
                ),
                onPressed: () => playing ? _p.pause() : _p.play(),
              );
            },
          ),
        ],
      ),
    );
  }
}
