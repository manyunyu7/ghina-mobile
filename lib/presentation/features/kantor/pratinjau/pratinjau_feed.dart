import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'pratinjau_actions.dart';
import 'pratinjau_widgets.dart';

const _filters = <(String, String)>[
  ('baru', 'Baru'),
  ('perlu', 'Perlu keputusan'),
  ('semua', 'Semua'),
  ('disimpan', 'Disimpan'),
  ('arsip', 'Arsip'),
];

/// `/kantor/o/:office/pratinjau`: the feed as its own page.
class KantorPratinjauPage extends StatelessWidget {
  const KantorPratinjauPage({super.key, required this.officeId});
  final String officeId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ghina.background,
    appBar: AppBar(title: const Text('Pratinjau')),
    body: KantorPratinjauFeed(officeId: officeId),
  );
}

/// Feed body (also the shell's "Pratinjau" tab): status filter chips with
/// counts, then one card per preview with a swipeable thumbnail carousel.
class KantorPratinjauFeed extends ConsumerStatefulWidget {
  const KantorPratinjauFeed({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KantorPratinjauFeed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<KantorPratinjauFeed> {
  String _status = 'perlu';
  bool _auto = true;
  Map<String, int> _counts = const {};

  @override
  Widget build(BuildContext context) {
    final key = (widget.officeId, _status);
    final feed = ref.watch(kantorPratinjauFeedProvider(key));
    final api = ref.watch(kantorApiProvider);
    final counts = feed.value?.counts;
    if (counts != null && counts.isNotEmpty) _counts = counts;
    // first load: nothing to decide → show everything
    if (_auto && counts != null && _status == 'perlu') {
      _auto = false;
      if ((counts['perlu'] ?? counts['menunggu'] ?? 0) == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _status = 'semua');
        });
      }
    }
    final usage = ref.watch(kantorPratinjauUsageProvider(widget.officeId));

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.sm,
              GhinaSpace.page,
              GhinaSpace.xs,
            ),
            children: [
              for (final (k, label) in _filters) ...[
                ChunkyChip(
                  label: _counts[k] == null ? label : '$label ${_counts[k]}',
                  selected: _status == k,
                  onTap: () => setState(() {
                    _auto = false;
                    _status = k;
                  }),
                ),
                const SizedBox(width: GhinaSpace.sm),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.refresh(kantorPratinjauFeedProvider(key).future),
            child: feed.when(
              skipLoadingOnRefresh: true,
              data: (f) => f.items.isEmpty || api == null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: GhinaSpace.xl),
                        EmptyState(
                          title: _status == 'perlu'
                              ? 'Tidak ada yang perlu diputuskan'
                              : 'Belum ada pratinjau',
                          message:
                              'Agen mengirim pratinjau (desain, halaman, PDF, video) ke sini untuk kamu periksa.',
                          compact: true,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        GhinaSpace.page,
                        GhinaSpace.sm,
                        GhinaSpace.page,
                        GhinaSpace.xxl,
                      ),
                      itemCount: f.items.length + 1,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: GhinaSpace.md),
                      itemBuilder: (_, i) => i == f.items.length
                          ? _UsageHint(usage.value)
                          : PratinjauCard(
                              key: ValueKey(f.items[i].id),
                              api: api,
                              item: f.items[i],
                            ),
                    ),
              error: (e, _) => KantorErrorView(
                error: e,
                onRetry: () =>
                    ref.invalidate(kantorPratinjauFeedProvider(key)),
              ),
              loading: () => const KantorLoading(count: 3),
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageHint extends StatelessWidget {
  const _UsageHint(this.usage);
  final PratinjauUsage? usage;

  @override
  Widget build(BuildContext context) {
    final u = usage;
    if (u == null || u.bytes <= 0) return const SizedBox.shrink();
    return Center(
      child: Text(
        'Penyimpanan pratinjau: ${(u.bytes / 1024 / 1024).toStringAsFixed(1)} MB'
        ' · ${u.items} pratinjau · ${u.files} file',
        style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
      ),
    );
  }
}

class PratinjauCard extends StatefulWidget {
  const PratinjauCard({
    super.key,
    required this.api,
    required this.item,
    this.showActions = true,
  });
  final KantorApi api;
  final PratinjauItem item;
  final bool showActions;

  @override
  State<PratinjauCard> createState() => _PratinjauCardState();
}

class _PratinjauCardState extends State<PratinjauCard> {
  int _page = 0;
  PratinjauItem? _fresh;

  @override
  void didUpdateWidget(PratinjauCard old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) _fresh = null;
  }

  PratinjauItem get _it => _fresh ?? widget.item;

  void _open([String? fileId]) {
    final it = _it;
    final r = pratinjauRoute(it.office, it.id);
    context.push(fileId == null ? r : '$r?f=${Uri.encodeComponent(fileId)}');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final it = _it;
    final files = it.files;
    void onItem(PratinjauItem n) {
      if (mounted) setState(() => _fresh = n);
    }

    return ChunkyCard(
      padding: const EdgeInsets.all(GhinaSpace.md),
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  it.title.isEmpty ? '(tanpa judul)' : it.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              const SizedBox(width: GhinaSpace.sm),
              PratinjauVersionBadge(it.version),
              const SizedBox(width: GhinaSpace.xs),
              PratinjauStatusPill(it.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              pratinjauFromLine(it),
              pratinjauJenisLabel(it.jenis),
              if (it.pinned) '📌',
              if (it.snoozed) '⏸',
              if (it.archived) '🗂',
            ].join(' · '),
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          if (it.note != null) ...[
            const SizedBox(height: GhinaSpace.sm),
            Text(
              it.note!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.body.copyWith(color: g.textSecondary),
            ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.md),
            ClipRRect(
              borderRadius: GhinaRadii.rMd,
              child: SizedBox(
                height: 190,
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: files.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _open(files[i].id),
                        child: PratinjauThumb(
                          api: widget.api,
                          file: files[i],
                          purged: it.filesPurged,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 8,
                      child: Row(
                        children: [
                          Flexible(
                            child: _Tag(
                              files[_page.clamp(0, files.length - 1)].name,
                            ),
                          ),
                          const Spacer(),
                          if (files.length > 1)
                            _Tag('${_page + 1}/${files.length}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (it.ownerNote != null) ...[
            const SizedBox(height: GhinaSpace.sm),
            Text(
              'Catatanmu: ${it.ownerNote}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
          if (it.filesPurged) ...[
            const SizedBox(height: GhinaSpace.xs),
            const PratinjauPurgedHint(),
          ],
          if (it.comments.isNotEmpty) ...[
            const SizedBox(height: GhinaSpace.xs),
            Text(
              '💬 ${it.comments.length} komentar · terakhir: ${it.comments.last.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
          if (widget.showActions) ...[
            const SizedBox(height: GhinaSpace.sm),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: PratinjauReactions(item: it, onItem: onItem),
                  ),
                ),
                PratinjauMenuButton(item: it, onItem: onItem),
              ],
            ),
            PratinjauActionBar(
              item: it,
              onItem: onItem,
              compact: true,
              onOpen: () => _open(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: GhinaRadii.rSm,
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GhinaType.caption.copyWith(color: Colors.white),
    ),
  );
}
