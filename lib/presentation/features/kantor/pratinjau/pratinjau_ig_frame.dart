import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import 'pratinjau_widgets.dart';

const _prefsKey = 'kantor.pratinjau.igFrame';

/// "Bingkai Instagram" toggle, remembered on this device.
Future<bool> pratinjauIgFrameLoad() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_prefsKey) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> pratinjauIgFrameSave(bool on) async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_prefsKey, on);
  } catch (_) {}
}

/// Image and video files of [it] (the frame is offered when there is at
/// least one).
List<PratinjauFile> pratinjauIgImages(PratinjauItem it) => [
  for (final f in it.files)
    if (f.kind == 'image' || f.kind == 'video') f,
];

const _ratios = <(String, double)>[('4:5', 4 / 5), ('1:1', 1), ('9:16', 9 / 16)];

/// Images shown as an Instagram post: header (avatar + name), swipeable
/// square/4:5 carousel with dots, caption from the item's note.
class PratinjauIgFrame extends StatefulWidget {
  const PratinjauIgFrame({
    super.key,
    required this.api,
    required this.item,
    required this.images,
    this.initialId,
    this.onPage,
  });

  final KantorApi api;
  final PratinjauItem item;
  final List<PratinjauFile> images;
  final String? initialId;
  final ValueChanged<PratinjauFile>? onPage;

  @override
  State<PratinjauIgFrame> createState() => _IgState();
}

class _IgState extends State<PratinjauIgFrame> {
  late int _page = widget.images
      .indexWhere((f) => f.id == widget.initialId)
      .clamp(0, widget.images.length - 1);
  late final _ctrl = PageController(initialPage: _page);
  int _ratio = 0; // 4:5 (IG portrait) → 1:1 → 9:16 (Reels)

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final it = widget.item;
    final name = (it.fromName ?? 'agen').trim();
    final handle = name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final imgs = widget.images;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: GhinaSpace.sm),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth.clamp(0, 420)),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: GhinaSpace.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: g.border, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: DefaultTextStyle(
                style: GhinaType.bodyS.copyWith(color: Colors.black87),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF58CC02),
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              handle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _ratio = (_ratio + 1) % _ratios.length,
                            ),
                            child: Text(
                              _ratio == 2 ? '9:16 Reels' : _ratios[_ratio].$1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AspectRatio(
                      aspectRatio: _ratios[_ratio].$2,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _ctrl,
                            itemCount: imgs.length,
                            onPageChanged: (i) {
                              setState(() => _page = i);
                              widget.onPage?.call(imgs[i]);
                            },
                            itemBuilder: (_, i) => ColoredBox(
                              color: const Color(0xFFF2F2F2),
                              child: imgs[i].kind == 'video'
                                  ? _IgVideo(
                                      key: ValueKey(imgs[i].id),
                                      uri: pratinjauUri(
                                        widget.api,
                                        imgs[i].playUrl,
                                      ),
                                      active: i == _page,
                                    )
                                  : Image.network(
                                pratinjauUri(
                                  widget.api,
                                  imgs[i].url,
                                ).toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                          if (imgs.length > 1)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_page + 1}/${imgs.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite_border_rounded,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.send_outlined,
                            color: Colors.black87,
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (imgs.length > 1)
                                  for (var i = 0; i < imgs.length; i++)
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: i == _page
                                            ? const Color(0xFF0095F6)
                                            : Colors.black26,
                                      ),
                                    ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 60),
                          const Icon(
                            Icons.bookmark_border_rounded,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$handle ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(text: it.note ?? it.title),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Video inside the frame: autoplays muted and loops; tap to (un)mute.
class _IgVideo extends StatefulWidget {
  const _IgVideo({super.key, required this.uri, required this.active});
  final Uri uri;
  final bool active;

  @override
  State<_IgVideo> createState() => _IgVideoState();
}

class _IgVideoState extends State<_IgVideo> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    widget.uri,
  );
  bool _muted = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c
        .initialize()
        .then((_) async {
          await _c.setLooping(true);
          await _c.setVolume(0);
          if (widget.active) await _c.play();
          if (mounted) setState(() {});
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void didUpdateWidget(_IgVideo old) {
    super.didUpdateWidget(old);
    if (!_c.value.isInitialized) return;
    if (widget.active) {
      _c.play();
    } else {
      _c.pause();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Icon(Icons.videocam_off_rounded));
    }
    if (!_c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final size = _c.value.size;
    return GestureDetector(
      onTap: () {
        setState(() => _muted = !_muted);
        _c.setVolume(_muted ? 0 : 1);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(_c),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
