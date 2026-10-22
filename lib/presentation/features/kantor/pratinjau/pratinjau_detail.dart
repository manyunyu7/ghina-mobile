import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_states.dart';
import '../wiki/wiki_page_screen.dart';
import 'pratinjau_actions.dart';
import 'pratinjau_compare.dart';
import 'pratinjau_ig_frame.dart';
import 'pratinjau_viewers.dart';
import 'pratinjau_widgets.dart';

/// `/kantor/o/:office/pratinjau/:id`: viewer + thumbnail strip, version
/// switcher, per-file verdicts, approve / revise, and "Jadikan wiki".
class KantorPratinjauDetailPage extends ConsumerStatefulWidget {
  const KantorPratinjauDetailPage({
    super.key,
    required this.officeId,
    required this.itemId,
    this.fileId,
  });

  final String officeId;
  final String itemId;

  /// File to show first (`?f=`).
  final String? fileId;

  @override
  ConsumerState<KantorPratinjauDetailPage> createState() => _DetailState();
}

class _DetailState extends ConsumerState<KantorPratinjauDetailPage> {
  late String _id = widget.itemId;
  String? _fileId;
  PratinjauItem? _fresh;
  bool _busy = false;
  bool _ig = false;
  final _video = GlobalKey<PratinjauVideoState>();

  @override
  void initState() {
    super.initState();
    _fileId = widget.fileId;
    pratinjauIgFrameLoad().then((v) {
      if (mounted && v != _ig) setState(() => _ig = v);
    });
  }

  (String, String) get _key => (widget.officeId, _id);

  Future<void> _run(
    Future<PratinjauItem> Function(KantorApi api) action,
    String done,
  ) async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _busy) return;
    setState(() => _busy = true);
    final ok = await kantorGuard(context, () async {
      final item = await action(api);
      if (mounted) setState(() => _fresh = item);
      ref.invalidate(kantorPratinjauFeedProvider);
    });
    if (mounted) {
      setState(() => _busy = false);
      if (ok) kantorToast(context, done);
    }
  }

  void _set(PratinjauItem? n) {
    if (n != null && mounted) setState(() => _fresh = n);
  }

  Future<void> _commentAt(PratinjauItem it, PratinjauFile f, double t) async =>
      _set(await pratinjauComment(context, ref, it, file: f, t: t));

  Future<void> _fileVerdict(
    PratinjauItem it,
    PratinjauFile f,
    String status,
  ) async {
    String? note;
    if (status == 'revisi') {
      note = await showPratinjauNoteSheet(
        context,
        title: 'Revisi ${f.name}',
        action: 'Tandai revisi',
        hint: 'Apa yang perlu diubah di file ini?',
        variant: ChunkyButtonVariant.danger,
        initial: f.status == 'revisi' ? f.note : null,
      );
      if (note == null) return;
    }
    await _run(
      (api) => api.pratinjauFile(
        it.office,
        it.id,
        f.id,
        status: status,
        catatan: note,
      ),
      status == 'oke' ? '${f.name} oke' : '${f.name} ditandai revisi',
    );
  }

  Future<void> _wiki(PratinjauItem it) async {
    final judul = await showPratinjauNoteSheet(
      context,
      title: 'Jadikan halaman wiki',
      action: 'Buat halaman',
      hint: 'Judul halaman',
      initial: it.title,
      message: 'Isi pratinjau disalin ke halaman wiki baru di kantor ini.',
    );
    if (judul == null || !mounted) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    ({String slug, String title})? page;
    await kantorGuard(context, () async {
      page = await api.pratinjauWiki(it.office, it.id, judul: judul);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    final p = page;
    if (p == null || p.slug.isEmpty) return;
    kantorToast(context, 'Halaman wiki "${p.title}" dibuat');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WikiPageScreen(officeId: widget.officeId, pageRef: p.slug),
      ),
    );
  }

  Future<void> _compare(PratinjauItem it) async {
    final picked = await Navigator.of(context).push<PratinjauItem>(
      MaterialPageRoute(builder: (_) => PratinjauComparePage(item: it)),
    );
    if (picked != null && mounted) {
      setState(() => _fresh = picked);
      ref.invalidate(kantorPratinjauFeedProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final api = ref.watch(kantorApiProvider);
    final async = ref.watch(kantorPratinjauItemProvider(_key));
    final loaded = async.value;
    // An action's answer wins until the provider catches up with it.
    final item = _fresh != null && _fresh!.id == _id ? _fresh : loaded;

    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(
          item?.title ?? 'Pratinjau',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (item != null && pratinjauIgImages(item).isNotEmpty)
            IconButton(
              tooltip: _ig ? 'Tampilan biasa' : 'Bingkai Instagram',
              isSelected: _ig,
              icon: const Icon(Icons.phone_iphone_rounded),
              selectedIcon: const Icon(Icons.grid_view_rounded),
              onPressed: () {
                setState(() => _ig = !_ig);
                pratinjauIgFrameSave(_ig);
              },
            ),
          if (item != null)
            PratinjauMenuButton(
              item: item,
              onItem: _set,
              extra: [
                if (item.files.length > 1 && !item.filesPurged)
                  ('banding', 'Bandingkan'),
                ('wiki', 'Jadikan wiki'),
              ],
              onExtra: (v) {
                if (v == 'wiki') _wiki(item);
                if (v == 'banding') _compare(item);
              },
            ),
        ],
      ),
      body: item == null || api == null
          ? async.hasError
                ? KantorErrorView(
                    error: async.error!,
                    onRetry: () =>
                        ref.invalidate(kantorPratinjauItemProvider(_key)),
                  )
                : const KantorLoading(count: 3)
          : _body(context, api, item),
    );
  }

  Widget _body(BuildContext context, KantorApi api, PratinjauItem it) {
    final g = context.ghina;
    final files = it.files;
    final idx = files.indexWhere((f) => f.id == _fileId);
    final file = files.isEmpty ? null : files[idx < 0 ? 0 : idx];
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.sm,
        GhinaSpace.page,
        GhinaSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    pratinjauFromLine(it),
                    pratinjauJenisLabel(it.jenis),
                    pratinjauModeLabel(it.mode),
                    if (it.pinned) '📌',
                    if (it.snoozed) '⏸',
                    if (it.archived) '🗂',
                  ].join(' · '),
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ),
              PratinjauStatusPill(it.status),
            ],
          ),
          if (it.versions.length > 1) ...[
            const SizedBox(height: GhinaSpace.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final v in it.versions) ...[
                    ChunkyChip(
                      label: 'v${v.version}',
                      selected: v.id == it.id,
                      color: v.status == 'disetujui'
                          ? GhinaColors.green
                          : v.status == 'revisi'
                          ? GhinaColors.red
                          : null,
                      onTap: v.id == it.id
                          ? null
                          : () => setState(() {
                              _id = v.id;
                              _fileId = null;
                              _fresh = null;
                            }),
                    ),
                    const SizedBox(width: GhinaSpace.xs),
                  ],
                ],
              ),
            ),
          ],
          if (it.note != null && !landscape) ...[
            const SizedBox(height: GhinaSpace.xs),
            Text(
              it.note!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          ],
          if (it.ownerNote != null) ...[
            const SizedBox(height: GhinaSpace.xs),
            Text(
              'Catatanmu: ${it.ownerNote}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );

    final igImages = _ig && !it.filesPurged
        ? pratinjauIgImages(it)
        : const <PratinjauFile>[];
    final viewer = file == null
        ? const EmptyState(title: 'Tidak ada file', compact: true)
        : it.filesPurged
        ? Column(
            children: [
              Expanded(
                child: PratinjauThumb(
                  api: api,
                  file: file,
                  purged: true,
                  fit: BoxFit.contain,
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(GhinaSpace.sm),
                child: PratinjauPurgedHint(),
              ),
            ],
          )
        : igImages.isNotEmpty
        ? PratinjauIgFrame(
            key: ValueKey('ig/${it.id}'),
            api: api,
            item: it,
            images: igImages,
            initialId: file.kind == 'image' || file.kind == 'video'
                ? file.id
                : null,
            onPage: (f) => setState(() => _fileId = f.id),
          )
        : Stack(
            children: [
              Positioned.fill(
                child: PratinjauFileView(
                  key: ValueKey('${it.id}/${file.id}'),
                  api: api,
                  item: it,
                  file: file,
                  videoKey: _video,
                  onCommentAt: (t) => _commentAt(it, file, t),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Layar penuh',
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PratinjauFullscreen(api: api, item: it, file: file),
                    ),
                  ),
                ),
              ),
            ],
          );

    final fileBar = file == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.sm,
              GhinaSpace.page,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                      if (file.note != null)
                        Text(
                          file.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (it.isPilihan && it.picked == file.id) ...[
                  const ChunkyPill(
                    label: 'Dipilih',
                    color: GhinaColors.green,
                    icon: Icons.check_rounded,
                    uppercase: false,
                  ),
                  const SizedBox(width: GhinaSpace.xs),
                ],
                ChunkyChip(
                  label: '💬',
                  selected: false,
                  onTap: _busy
                      ? null
                      : () async =>
                            _set(await pratinjauComment(context, ref, it, file: file)),
                ),
                const SizedBox(width: GhinaSpace.xs),
                if (it.isPilihan)
                  ChunkyChip(
                    label: '⭐ Pilih',
                    selected: it.picked == file.id,
                    onTap: _busy || it.picked == file.id
                        ? null
                        : () => _pick(it, file),
                  )
                else if (!it.isInfo) ...[
                  ChunkyChip(
                    label: 'Oke',
                    icon: Icons.check_rounded,
                    color: GhinaColors.green,
                    selected: file.status == 'oke',
                    onTap: _busy ? null : () => _fileVerdict(it, file, 'oke'),
                  ),
                  const SizedBox(width: GhinaSpace.xs),
                  ChunkyChip(
                    label: 'Revisi',
                    icon: Icons.edit_rounded,
                    color: GhinaColors.red,
                    selected: file.status == 'revisi',
                    onTap: _busy
                        ? null
                        : () => _fileVerdict(it, file, 'revisi'),
                  ),
                ],
              ],
            ),
          );

    final strip = files.length < 2
        ? const SizedBox.shrink()
        : SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.sm,
                GhinaSpace.page,
                GhinaSpace.xs,
              ),
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(width: GhinaSpace.sm),
              itemBuilder: (_, i) {
                final f = files[i];
                final sel = f.id == file?.id;
                final (_, color) = pratinjauStatusLook(f.status);
                return GestureDetector(
                  onTap: () => setState(() => _fileId = f.id),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: GhinaRadii.rSm,
                      border: Border.all(
                        width: sel ? 3 : 1,
                        color: sel ? g.highlight.base : g.border,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: GhinaRadii.rSm,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PratinjauThumb(
                              api: api,
                              file: f,
                              compact: true,
                              purged: it.filesPurged,
                            ),
                          ),
                          if (f.status != 'menunggu' ||
                              (it.isPilihan && it.picked == f.id))
                            Positioned(
                              right: 2,
                              top: 2,
                              child: CircleAvatar(
                                radius: 8,
                                backgroundColor: it.picked == f.id
                                    ? GhinaColors.green.base
                                    : color.base,
                                child: Icon(
                                  f.status == 'revisi'
                                      ? Icons.edit_rounded
                                      : Icons.check_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );

    final actions = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          GhinaSpace.sm,
          GhinaSpace.page,
          GhinaSpace.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PratinjauReactions(item: it, onItem: _set),
            const SizedBox(height: GhinaSpace.xs),
            PratinjauActionBar(
              item: it,
              onItem: _set,
              file: it.isPilihan ? file : null,
              trailing: it.files.length > 1 && !it.filesPurged
                  ? ChunkyButton(
                      label: 'Bandingkan',
                      icon: Icons.compare_rounded,
                      size: ChunkyButtonSize.medium,
                      variant: ChunkyButtonVariant.secondary,
                      onPressed: _busy ? null : () => _compare(it),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );

    final comments = it.comments.isEmpty
        ? const SizedBox.shrink()
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: landscape ? 400 : 130),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                GhinaSpace.sm,
                GhinaSpace.page,
                0,
              ),
              child: PratinjauComments(
                item: it,
                onSeek: (c) {
                  final f = c.file == null
                      ? null
                      : files.where((x) => x.id == c.file).firstOrNull;
                  if (f != null && f.id != file?.id) {
                    setState(() => _fileId = f.id);
                  } else {
                    _video.currentState?.seek(c.t!);
                  }
                },
              ),
            ),
          );

    if (landscape) {
      return Row(
        children: [
          Expanded(flex: 3, child: viewer),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [header, fileBar, strip, comments],
                    ),
                  ),
                ),
                actions,
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        header,
        Expanded(child: viewer),
        fileBar,
        strip,
        comments,
        actions,
      ],
    );
  }

  Future<void> _pick(PratinjauItem it, PratinjauFile f) async =>
      _set(await pratinjauPick(context, ref, it, f));
}
