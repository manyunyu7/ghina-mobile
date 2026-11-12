import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'konten_data.dart';
import 'konten_media.dart';
import 'konten_model.dart';
import 'konten_viewers.dart';
import 'konten_widgets.dart';

/// Paket Posting: semua yang dibutuhkan untuk posting manual dari HP. Slide
/// atau video, simpan ke galeri, bagikan, caption per platform, tandai sudah
/// tayang, performa. Kartu tahap Review juga dapat tombol Setuju dan Revisi.
class KontenPackagePage extends ConsumerWidget {
  const KontenPackagePage({
    super.key,
    required this.officeId,
    required this.itemId,
  });

  final String officeId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(kontenItemProvider((officeId, itemId)));
    return Scaffold(
      backgroundColor: context.ghina.background,
      appBar: AppBar(title: const Text('Paket Posting')),
      body: item.when(
        data: (i) => KontenPackageBody(officeId: officeId, item: i),
        loading: () => const KantorLoading(),
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kontenItemProvider((officeId, itemId))),
        ),
      ),
    );
  }
}

class KontenPackageBody extends ConsumerStatefulWidget {
  const KontenPackageBody({
    super.key,
    required this.officeId,
    required this.item,
  });

  final String officeId;
  final KontenItem item;

  @override
  ConsumerState<KontenPackageBody> createState() => _PackageState();
}

class _PackageState extends ConsumerState<KontenPackageBody> {
  String? _busy;

  KontenItem get item => widget.item;

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    showToastBadge(
      context,
      message: msg,
      icon: ok ? Icons.check_rounded : Icons.error_outline_rounded,
      color: ok ? GhinaColors.green : GhinaColors.red,
      tag: 'konten',
    );
  }

  void _refresh() {
    ref.invalidate(kontenItemProvider((widget.officeId, item.id)));
    ref.invalidate(kontenListProvider(widget.officeId));
    ref.invalidate(kontenJadwalProvider(widget.officeId));
  }

  /// Berkas yang dibagikan atau disimpan: semua slide, atau videonya.
  List<KontenFile> get _files => [
    ...item.media.slides,
    if (item.media.video != null) item.media.video!,
  ];

  Future<List<String>?> _download() async {
    final repo = ref.read(kontenRepoProvider);
    if (repo == null) return null;
    final files = _files;
    final paths = await ref
        .read(kontenMediaProvider)
        .fetchAll(
          repo,
          item.id,
          files,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _busy = 'Mengunduh ${done + 1} dari $total');
            }
          },
        );
    return paths;
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    try {
      await body();
    } on KantorException catch (e) {
      _toast(e.message, ok: false);
    } catch (e) {
      _toast('Gagal: $e', ok: false);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveAll() => _run('Mengunduh', () async {
    final paths = await _download();
    if (paths == null || paths.isEmpty) return;
    final ok = await ref.read(kontenMediaProvider).saveToGallery(paths);
    _toast(
      ok
          ? '${paths.length} berkas masuk galeri'
          : 'Izin galeri ditolak. Aktifkan di pengaturan HP.',
      ok: ok,
    );
  });

  Future<void> _share() => _run('Mengunduh', () async {
    final paths = await _download();
    if (paths == null || paths.isEmpty) return;
    await ref.read(kontenMediaProvider).share(paths);
  });

  Future<void> _review(bool setuju) async {
    String? catatan;
    if (!setuju) {
      catatan = await showChunkyBottomSheet<String>(
        context,
        title: 'Minta revisi',
        builder: (_) => const _NoteSheet(
          label: 'Catatan revisi',
          hint: 'Apa yang perlu diubah?',
          action: 'Kirim revisi',
        ),
      );
      if (catatan == null) return;
    }
    final repo = ref.read(kontenRepoProvider);
    if (repo == null) return;
    await _run('Mengirim', () async {
      await repo.review(
        widget.officeId,
        item.id,
        setuju: setuju,
        catatan: catatan,
      );
      _toast(setuju ? 'Disetujui, masuk Siap tayang' : 'Revisi dikirim');
      _refresh();
    });
  }

  Future<void> _tayang(String platform) async {
    final link = await showChunkyBottomSheet<String>(
      context,
      title: 'Sudah tayang di ${kontenPlatformName(platform)}',
      builder: (_) => const _NoteSheet(
        label: 'Link posting (boleh kosong)',
        hint: 'https://',
        action: 'Tandai sudah tayang',
        keyboard: TextInputType.url,
        multiline: false,
      ),
    );
    if (link == null) return;
    final repo = ref.read(kontenRepoProvider);
    if (repo == null) return;
    await _run('Menyimpan', () async {
      final cek = await repo.tayang(
        widget.officeId,
        item.id,
        platform,
        link: link,
      );
      _toast(
        cek.isEmpty
            ? 'Ditandai tayang di ${kontenPlatformName(platform)}'
            : 'Tayang. ${cek.length} berkas masih menyebut path lama, cek di web',
      );
      _refresh();
    });
  }

  Future<void> _performa(String platform) async {
    final angka = await showChunkyBottomSheet<Map<String, int>>(
      context,
      title: 'Performa ${kontenPlatformName(platform)}',
      builder: (_) => _PerformaSheet(initial: item.perf[platform] ?? const {}),
    );
    if (angka == null) return;
    final repo = ref.read(kontenRepoProvider);
    if (repo == null) return;
    await _run('Menyimpan', () async {
      await repo.performa(widget.officeId, item.id, platform, angka);
      _toast('Performa tersimpan');
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final repo = ref.watch(kontenRepoProvider);
    final media = item.media;
    final hasFiles = _files.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.xxl,
      ),
      children: [
        Text(item.title, style: GhinaType.h2.copyWith(color: g.textPrimary)),
        const SizedBox(height: GhinaSpace.sm),
        Wrap(
          spacing: GhinaSpace.sm,
          runSpacing: GhinaSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KontenStagePill(item),
            ChunkyPill(label: item.jenis, color: GhinaColors.gray, soft: true),
            if (item.sensitif)
              const ChunkyPill(
                label: 'Sensitif',
                color: GhinaColors.red,
                soft: true,
                icon: Icons.warning_amber_rounded,
              ),
            if (item.tanggal != null)
              Text(
                '${kontenDateLabel(item.tanggal!)}${item.jam == null ? '' : ' ${item.jam}'}'
                '${item.usulan ? ' (usulan)' : ''}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
          ],
        ),
        if (item.catatan != null) ...[
          const SizedBox(height: GhinaSpace.sm),
          Text(
            item.catatan!,
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ],
        const SizedBox(height: GhinaSpace.lg),
        if (repo != null && !media.isEmpty)
          KontenMediaStrip(repo: repo, media: media)
        else
          ChunkyCard(
            child: Text(
              'Belum ada media di paket ini.',
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          ),
        const SizedBox(height: GhinaSpace.lg),
        if (item.tahap == 'review') ...[
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Revisi',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.medium,
                  onPressed: _busy == null ? () => _review(false) : null,
                ),
              ),
              const SizedBox(width: GhinaSpace.md),
              Expanded(
                child: ChunkyButton(
                  label: 'Setuju',
                  size: ChunkyButtonSize.medium,
                  onPressed: _busy == null ? () => _review(true) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: GhinaSpace.lg),
        ],
        ChunkyButton(
          label: _busy ?? 'Simpan semua ke galeri',
          icon: Icons.download_rounded,
          expand: true,
          loading: _busy != null,
          onPressed: hasFiles && _busy == null ? _saveAll : null,
        ),
        const SizedBox(height: GhinaSpace.sm),
        ChunkyButton(
          label: 'Bagikan',
          icon: Icons.ios_share_rounded,
          variant: ChunkyButtonVariant.secondary,
          size: ChunkyButtonSize.medium,
          expand: true,
          onPressed: hasFiles && _busy == null ? _share : null,
        ),
        if (item.lagu != null) ...[
          const SizedBox(height: GhinaSpace.lg),
          Row(
            children: [
              Icon(Icons.music_note_rounded, size: 18, color: g.textSecondary),
              const SizedBox(width: GhinaSpace.sm),
              Expanded(
                child: Text(
                  'Saran lagu: ${item.lagu}',
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: GhinaSpace.xl),
        Text('Caption', style: GhinaType.h3.copyWith(color: g.textPrimary)),
        const SizedBox(height: GhinaSpace.sm),
        for (final p in item.targets)
          _CaptionCard(
            platform: p,
            text: item.captions[p],
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: item.captions[p]!));
              _toast('Caption ${kontenPlatformName(p)} disalin');
            },
          ),
        const SizedBox(height: GhinaSpace.lg),
        Text('Tayang', style: GhinaType.h3.copyWith(color: g.textPrimary)),
        const SizedBox(height: GhinaSpace.sm),
        for (final p in item.targets)
          _PostedRow(
            key: ValueKey('tayang-$p'),
            platform: p,
            posted: item.platforms[p],
            perf: item.perf[p],
            enabled: _busy == null,
            onMark: () => _tayang(p),
            onPerf: () => _performa(p),
          ),
      ],
    );
  }
}

class _CaptionCard extends StatelessWidget {
  const _CaptionCard({
    required this.platform,
    required this.text,
    required this.onCopy,
  });
  final String platform;
  final String? text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        padding: const EdgeInsets.all(GhinaSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kontenPlatformName(platform),
                    style: GhinaType.bodyS
                        .w(900)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                if (text != null)
                  ChunkyButton(
                    key: ValueKey('salin-$platform'),
                    label: 'Salin',
                    icon: Icons.copy_rounded,
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    onPressed: onCopy,
                  ),
              ],
            ),
            const SizedBox(height: GhinaSpace.sm),
            Text(
              text ?? 'Belum ada caption untuk platform ini.',
              style: GhinaType.bodyS.copyWith(
                color: text == null ? g.textMuted : g.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostedRow extends StatelessWidget {
  const _PostedRow({
    super.key,
    required this.platform,
    required this.posted,
    required this.perf,
    required this.enabled,
    required this.onMark,
    required this.onPerf,
  });

  final String platform;
  final KontenPosted? posted;
  final Map<String, int>? perf;
  final bool enabled;
  final VoidCallback onMark;
  final VoidCallback onPerf;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final done = posted != null;
    final link = posted?.link;
    final at = kontenDate(posted?.at);
    final stats = perf == null || perf!.isEmpty
        ? null
        : [
            for (final (k, l) in const [
              ('reach', 'jangkauan'),
              ('like', 'suka'),
              ('comment', 'komentar'),
              ('save', 'simpan'),
              ('share', 'bagikan'),
            ])
              if (perf![k] != null) '${perf![k]} $l',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        padding: const EdgeInsets.all(GhinaSpace.md),
        tinted: done ? GhinaColors.green : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: done ? GhinaColors.green.base : g.textMuted,
                ),
                const SizedBox(width: GhinaSpace.sm),
                Expanded(
                  child: Text(
                    kontenPlatformName(platform),
                    style: GhinaType.bodyS
                        .w(900)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
                if (!done)
                  ChunkyButton(
                    key: ValueKey('tandai-$platform'),
                    label: 'Sudah tayang',
                    size: ChunkyButtonSize.small,
                    onPressed: enabled ? onMark : null,
                  )
                else
                  ChunkyButton(
                    key: ValueKey('performa-$platform'),
                    label: 'Performa',
                    size: ChunkyButtonSize.small,
                    variant: ChunkyButtonVariant.outline,
                    onPressed: enabled ? onPerf : null,
                  ),
              ],
            ),
            if (done && (link != null || at != null)) ...[
              const SizedBox(height: GhinaSpace.xs),
              Text(
                [if (at != null) kontenDateLabel(at), ?link].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              if (link != null && Uri.tryParse(link)?.hasScheme == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Buka posting'),
                  ),
                ),
            ],
            if (stats != null && stats.isNotEmpty) ...[
              const SizedBox(height: GhinaSpace.xs),
              Text(
                stats,
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sheet satu isian teks; menutup dengan teksnya (bisa kosong) atau null.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.label,
    required this.hint,
    required this.action,
    this.keyboard,
    this.multiline = true,
  });

  final String label;
  final String hint;
  final String action;
  final TextInputType? keyboard;
  final bool multiline;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChunkyTextField(
        key: const ValueKey('konten-note'),
        label: widget.label,
        hint: widget.hint,
        controller: _c,
        keyboardType: widget.keyboard,
        maxLines: widget.multiline ? 4 : 1,
        minLines: widget.multiline ? 2 : 1,
        textCapitalization: widget.multiline
            ? TextCapitalization.sentences
            : TextCapitalization.none,
      ),
      const SizedBox(height: GhinaSpace.lg),
      ChunkyButton(
        key: const ValueKey('konten-note-ok'),
        label: widget.action,
        expand: true,
        onPressed: () => Navigator.of(context).pop(_c.text),
      ),
    ],
  );
}

class _PerformaSheet extends StatefulWidget {
  const _PerformaSheet({required this.initial});
  final Map<String, int> initial;

  @override
  State<_PerformaSheet> createState() => _PerformaSheetState();
}

class _PerformaSheetState extends State<_PerformaSheet> {
  static const _fields = [
    ('reach', 'Jangkauan'),
    ('like', 'Suka'),
    ('comment', 'Komentar'),
    ('save', 'Simpan'),
    ('share', 'Bagikan'),
  ];
  late final Map<String, TextEditingController> _c = {
    for (final (k, _) in _fields)
      k: TextEditingController(
        text: widget.initial[k] == null ? '' : '${widget.initial[k]}',
      ),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (k, label) in _fields) ...[
        ChunkyTextField(
          key: ValueKey('perf-$k'),
          label: label,
          controller: _c[k],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: GhinaSpace.sm),
      ],
      const SizedBox(height: GhinaSpace.sm),
      ChunkyButton(
        key: const ValueKey('perf-ok'),
        label: 'Simpan performa',
        expand: true,
        onPressed: () => Navigator.of(context).pop({
          for (final e in _c.entries)
            e.key: int.tryParse(e.value.text.trim()) ?? 0,
        }),
      ),
    ],
  );
}
