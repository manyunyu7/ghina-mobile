import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../design_system/design_system.dart';
import 'konten_data.dart';
import 'konten_model.dart';
import 'konten_widgets.dart';

/// Slide yang bisa digeser (4:5) atau sampul video dengan tombol putar.
class KontenMediaStrip extends StatefulWidget {
  const KontenMediaStrip({super.key, required this.repo, required this.media});
  final KontenRepo repo;
  final KontenMediaSet media;

  @override
  State<KontenMediaStrip> createState() => _StripState();
}

class _StripState extends State<KontenMediaStrip> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final m = widget.media;
    final repo = widget.repo;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: GhinaRadii.rLg,
            child: m.slides.isNotEmpty
                ? PageView.builder(
                    itemCount: m.slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => _ImageViewer(
                            repo: repo,
                            urls: [for (final s in m.slides) s.url],
                            start: i,
                          ),
                        ),
                      ),
                      child: KontenImage(
                        repo: repo,
                        url: m.slides[i].thumb ?? m.slides[i].url,
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) =>
                            KontenVideoPage(repo: repo, file: m.video!),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        KontenImage(
                          repo: repo,
                          url: m.cover?.thumb ?? m.video?.thumb ?? m.cover?.url,
                        ),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 64,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (m.slides.length > 1) ...[
          const SizedBox(height: GhinaSpace.sm),
          Text(
            'Slide ${_page + 1} dari ${m.slides.length}',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.repo,
    required this.urls,
    required this.start,
  });
  final KontenRepo repo;
  final List<String> urls;
  final int start;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: PageView.builder(
      controller: PageController(initialPage: start),
      itemCount: urls.length,
      itemBuilder: (_, i) => InteractiveViewer(
        child: KontenImage(repo: repo, url: urls[i], fit: BoxFit.contain),
      ),
    ),
  );
}

class KontenVideoPage extends StatefulWidget {
  const KontenVideoPage({super.key, required this.repo, required this.file});
  final KontenRepo repo;
  final KontenFile file;

  @override
  State<KontenVideoPage> createState() => _VideoState();
}

class _VideoState extends State<KontenVideoPage> {
  late final VideoPlayerController _v = VideoPlayerController.networkUrl(
    widget.repo.uri(widget.file.url),
    httpHeaders: widget.repo.headers,
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _v
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _v.play();
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: _failed
          ? const Text(
              'Video tidak bisa diputar.',
              style: TextStyle(color: Colors.white),
            )
          : !_v.value.isInitialized
          ? const CircularProgressIndicator()
          : GestureDetector(
              onTap: () =>
                  setState(() => _v.value.isPlaying ? _v.pause() : _v.play()),
              child: AspectRatio(
                aspectRatio: _v.value.aspectRatio,
                child: VideoPlayer(_v),
              ),
            ),
    ),
  );
}
