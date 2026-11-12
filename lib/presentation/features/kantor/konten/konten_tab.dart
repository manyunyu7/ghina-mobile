import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'konten_data.dart';
import 'konten_jadwal.dart';
import 'konten_model.dart';
import 'konten_package_page.dart';
import 'konten_widgets.dart';

void openKontenPackage(BuildContext context, String officeId, String id) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KontenPackagePage(officeId: officeId, itemId: id),
      ),
    );

/// Tab "Konten" di shell kantor: Galeri, Review dan Jadwal. Kit dan Grid
/// hanya ada di web (tautan di menu kecil).
class KantorKontenTab extends ConsumerStatefulWidget {
  const KantorKontenTab({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KantorKontenTab> createState() => _KontenTabState();
}

class _KontenTabState extends ConsumerState<KantorKontenTab> {
  String _view = 'galeri';

  Future<void> _web(String sub) async {
    final repo = ref.read(kontenRepoProvider);
    if (repo == null) return;
    try {
      await launchUrl(
        repo.webUrl(widget.officeId, sub),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(kontenListProvider(widget.officeId));
    final reviewN =
        list.value?.items.where((i) => i.tahap == 'review').length ?? 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.sm,
            GhinaSpace.xs,
            GhinaSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: ChunkySegmented<String>(
                  height: 44,
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                  segments: [
                    const ChunkySegment(value: 'galeri', label: 'Galeri'),
                    ChunkySegment(
                      value: 'review',
                      label: reviewN > 0 ? 'Review $reviewN' : 'Review',
                    ),
                    const ChunkySegment(value: 'jadwal', label: 'Jadwal'),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Buka di web',
                icon: const Icon(Icons.open_in_new_rounded),
                onSelected: _web,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'kit', child: Text('Kit di web')),
                  PopupMenuItem(value: 'grid', child: Text('Grid di web')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_view) {
            'jadwal' => KontenJadwalView(officeId: widget.officeId),
            'review' => _ListView(officeId: widget.officeId, reviewOnly: true),
            _ => _ListView(officeId: widget.officeId),
          },
        ),
      ],
    );
  }
}

class _ListView extends ConsumerStatefulWidget {
  const _ListView({required this.officeId, this.reviewOnly = false});
  final String officeId;
  final bool reviewOnly;

  @override
  ConsumerState<_ListView> createState() => _ListViewState();
}

class _ListViewState extends ConsumerState<_ListView> {
  String _tahap = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kontenListProvider(widget.officeId));
    final repo = ref.watch(kontenRepoProvider);
    return async.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kontenListProvider(widget.officeId)),
      ),
      data: (data) {
        Future<void> refresh() async {
          ref.invalidate(kontenListProvider(widget.officeId));
          await ref.read(kontenListProvider(widget.officeId).future);
        }

        if (data.unsupported || repo == null) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: const KontenEmpty(
              title: kontenUnsupportedTitle,
              message: kontenUnsupportedMessage,
            ),
          );
        }
        var items = data.items;
        if (widget.reviewOnly) {
          items = [
            for (final i in items)
              if (i.tahap == 'review') i,
          ]..sort((a, b) => (a.updatedAt ?? '').compareTo(b.updatedAt ?? ''));
        } else if (_tahap.isNotEmpty) {
          items = [
            for (final i in items)
              if (i.tahap == _tahap) i,
          ];
        }
        return Column(
          children: [
            if (!widget.reviewOnly)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: GhinaSpace.page,
                    vertical: GhinaSpace.xs,
                  ),
                  children: [
                    ChunkyChip(
                      label: 'Semua ${data.items.length}',
                      selected: _tahap.isEmpty,
                      onTap: () => setState(() => _tahap = ''),
                    ),
                    for (final s in data.stages)
                      if (s.n > 0) ...[
                        const SizedBox(width: GhinaSpace.sm),
                        ChunkyChip(
                          key: ValueKey('tahap-${s.id}'),
                          label: '${s.name} ${s.n}',
                          selected: _tahap == s.id,
                          color: kontenStageColor(s.id),
                          onTap: () => setState(() => _tahap = s.id),
                        ),
                      ],
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: items.isEmpty
                    ? KontenEmpty(
                        title: widget.reviewOnly
                            ? 'Tidak ada yang menunggu review'
                            : 'Belum ada konten',
                        message: widget.reviewOnly
                            ? 'Kartu yang dikirim editor muncul di sini.'
                            : null,
                      )
                    : GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(GhinaSpace.page),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: GhinaSpace.md,
                              mainAxisSpacing: GhinaSpace.md,
                              childAspectRatio: 0.68,
                            ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _Tile(
                          repo: repo,
                          item: items[i],
                          onTap: () => openKontenPackage(
                            context,
                            widget.officeId,
                            items[i].id,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.repo, required this.item, required this.onTap});
  final KontenRepo repo;
  final KontenItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      key: ValueKey('konten-${item.id}'),
      padding: EdgeInsets.zero,
      borderRadius: GhinaRadii.rLg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: KontenImage(repo: repo, url: item.coverUrl),
                ),
                if (item.jenis == 'video')
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                if (item.sensitif)
                  const Positioned(
                    left: 6,
                    top: 6,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(GhinaSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS.w(800).copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: GhinaSpace.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: KontenStagePill(item),
                ),
                const SizedBox(height: GhinaSpace.xs),
                KontenPlatformBadges(item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
