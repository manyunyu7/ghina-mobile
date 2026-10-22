import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';
import 'pratinjau_viewers.dart';
import 'pratinjau_widgets.dart';

/// Mode `pilihan`: the options side by side (2–3 fit a landscape screen; more
/// scroll sideways), each with a "Pilih" button. Pops with the updated item.
class PratinjauComparePage extends ConsumerStatefulWidget {
  const PratinjauComparePage({super.key, required this.item});
  final PratinjauItem item;

  @override
  ConsumerState<PratinjauComparePage> createState() => _CompareState();
}

class _CompareState extends ConsumerState<PratinjauComparePage> {
  String? _busy;

  Future<void> _pick(PratinjauFile f) async {
    final it = widget.item;
    final api = ref.read(kantorApiProvider);
    if (api == null || _busy != null) return;
    final note = await showPratinjauNoteSheet(
      context,
      title: 'Pilih ${f.name}?',
      action: 'Pilih yang ini',
    );
    if (note == null || !mounted) return;
    setState(() => _busy = f.id);
    PratinjauItem? next;
    await kantorGuard(context, () async {
      next = await api.pratinjauPilih(it.office, it.id, f.id, catatan: note);
    });
    if (!mounted) return;
    setState(() => _busy = null);
    if (next != null) {
      kantorToast(context, '${f.name} dipilih');
      Navigator.of(context).pop(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final api = ref.watch(kantorApiProvider);
    final it = widget.item;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: Text('Bandingkan · ${it.title}')),
      body: api == null
          ? const SizedBox.shrink()
          : it.files.length == 2 && it.files.every((f) => f.kind == 'video')
          ? _SyncedVideos(
              api: api,
              item: it,
              busy: _busy,
              onPick: it.isPilihan ? _pick : null,
            )
          : LayoutBuilder(
              builder: (_, box) {
                final n = it.files.length;
                final fits = n <= 3 && box.maxWidth / n >= 220;
                final w = fits
                    ? box.maxWidth / n
                    : (box.maxWidth * 0.8).clamp(220.0, 420.0);
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: fits
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: n,
                  itemBuilder: (_, i) {
                    final f = it.files[i];
                    final picked = it.picked == f.id;
                    return SizedBox(
                      width: w,
                      child: Padding(
                        padding: const EdgeInsets.all(GhinaSpace.xs),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: GhinaRadii.rMd,
                                  border: Border.all(
                                    width: picked ? 3 : 1,
                                    color: picked
                                        ? GhinaColors.green.base
                                        : g.border,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: PratinjauFileView(
                                  api: api,
                                  item: it,
                                  file: f,
                                ),
                              ),
                            ),
                            const SizedBox(height: GhinaSpace.xs),
                            Text(
                              '${String.fromCharCode(65 + i)} · ${f.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.caption.copyWith(
                                color: g.textSecondary,
                              ),
                            ),
                            const SizedBox(height: GhinaSpace.xs),
                            if (it.isPilihan)
                            SafeArea(
                              top: false,
                              child: ChunkyButton(
                                label: picked ? 'Dipilih' : 'Pilih',
                                icon: picked
                                    ? Icons.check_rounded
                                    : Icons.touch_app_rounded,
                                size: ChunkyButtonSize.small,
                                expand: true,
                                loading: _busy == f.id,
                                variant: picked
                                    ? ChunkyButtonVariant.secondary
                                    : ChunkyButtonVariant.primary,
                                onPressed: picked || _busy != null
                                    ? null
                                    : () => _pick(f),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Two videos side by side with one play/pause and one seek bar.
class _SyncedVideos extends StatefulWidget {
  const _SyncedVideos({
    required this.api,
    required this.item,
    required this.busy,
    required this.onPick,
  });

  final KantorApi api;
  final PratinjauItem item;
  final String? busy;
  final ValueChanged<PratinjauFile>? onPick;

  @override
  State<_SyncedVideos> createState() => _SyncedVideosState();
}

class _SyncedVideosState extends State<_SyncedVideos> {
  late final List<VideoPlayerController> _cs = [
    for (final f in widget.item.files)
      VideoPlayerController.networkUrl(pratinjauUri(widget.api, f.playUrl)),
  ];
  double? _drag;

  @override
  void initState() {
    super.initState();
    for (final c in _cs) {
      c.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {});
    }
    _cs.first.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cs.first.removeListener(_tick);
    for (final c in _cs) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _playing => _cs.any((c) => c.value.isPlaying);

  Duration get _len {
    var d = Duration.zero;
    for (final c in _cs) {
      if (c.value.duration > d) d = c.value.duration;
    }
    return d;
  }

  Future<void> _toggle() async {
    if (_playing) {
      for (final c in _cs) {
        await c.pause();
      }
    } else {
      final at = _cs.first.value.position;
      for (final c in _cs) {
        await c.seekTo(at);
      }
      for (final c in _cs) {
        c.play();
      }
    }
  }

  Future<void> _seek(double s) async {
    final at = Duration(milliseconds: (s * 1000).round());
    for (final c in _cs) {
      await c.seekTo(at);
    }
  }

  String _t(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final it = widget.item;
    final len = _len.inMilliseconds / 1000;
    final pos = _drag ?? _cs.first.value.position.inMilliseconds / 1000;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < _cs.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(GhinaSpace.xs),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: GhinaRadii.rMd,
                                border: Border.all(
                                  width: it.picked == it.files[i].id ? 3 : 1,
                                  color: it.picked == it.files[i].id
                                      ? GhinaColors.green.base
                                      : g.border,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Center(
                                child: _cs[i].value.isInitialized
                                    ? AspectRatio(
                                        aspectRatio: _cs[i].value.aspectRatio,
                                        child: VideoPlayer(_cs[i]),
                                      )
                                    : const CircularProgressIndicator(),
                              ),
                            ),
                          ),
                          const SizedBox(height: GhinaSpace.xs),
                          Text(
                            '${String.fromCharCode(65 + i)} · ${it.files[i].name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhinaType.caption.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                          if (widget.onPick != null) ...[
                            const SizedBox(height: GhinaSpace.xs),
                            ChunkyButton(
                              label: it.picked == it.files[i].id
                                  ? 'Dipilih'
                                  : '⭐ Pilih',
                              size: ChunkyButtonSize.small,
                              expand: true,
                              loading: widget.busy == it.files[i].id,
                              onPressed:
                                  it.picked == it.files[i].id ||
                                      widget.busy != null
                                  ? null
                                  : () => widget.onPick!(it.files[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: _toggle,
              ),
              Expanded(
                child: Slider(
                  value: len <= 0 ? 0 : pos.clamp(0, len),
                  max: len <= 0 ? 1 : len,
                  onChanged: len <= 0 ? null : (v) => setState(() => _drag = v),
                  onChangeEnd: (v) async {
                    await _seek(v);
                    if (mounted) setState(() => _drag = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: GhinaSpace.sm),
                child: Text(
                  '${_t(Duration(milliseconds: (pos * 1000).round()))} / ${_t(_len)}',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
