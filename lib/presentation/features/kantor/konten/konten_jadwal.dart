import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_states.dart';
import 'konten_data.dart';
import 'konten_model.dart';
import 'konten_tab.dart';
import 'konten_widgets.dart';

/// Jadwal: peringatan, target per minggu, daftar per tanggal, ganti tanggal
/// lewat pemilih, setujui usulan editor.
class KontenJadwalView extends ConsumerStatefulWidget {
  const KontenJadwalView({super.key, required this.officeId});
  final String officeId;

  @override
  ConsumerState<KontenJadwalView> createState() => _JadwalState();
}

class _JadwalState extends ConsumerState<KontenJadwalView> {
  bool _busy = false;

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
    ref.invalidate(kontenJadwalProvider(widget.officeId));
    ref.invalidate(kontenListProvider(widget.officeId));
  }

  Future<void> _act(String ok, Future<void> Function(KontenRepo) body) async {
    final repo = ref.read(kontenRepoProvider);
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await body(repo);
      _toast(ok);
      _refresh();
    } on KantorException catch (e) {
      _toast(e.message, ok: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(KontenItem i) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: i.tanggal != null && i.tanggal!.isAfter(now)
          ? i.tanggal!
          : now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Tanggal tayang',
    );
    if (d == null) return;
    await _act(
      'Jadwal ${kontenDateLabel(d)}',
      (r) => r.setTanggal(
        widget.officeId,
        i.id,
        publishAt: kontenDateKey(d),
        jam: i.jam,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(kontenJadwalProvider(widget.officeId));
    final list = ref.watch(kontenListProvider(widget.officeId));
    final repo = ref.watch(kontenRepoProvider);
    return async.when(
      loading: () => const KantorLoading(),
      error: (e, _) => KantorErrorView(
        error: e,
        onRetry: () => ref.invalidate(kontenJadwalProvider(widget.officeId)),
      ),
      data: (data) {
        Future<void> refresh() async {
          _refresh();
          await ref.read(kontenJadwalProvider(widget.officeId).future);
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
        final dated =
            [
              for (final i in data.items)
                if (i.tanggal != null) i,
            ]..sort((a, b) {
              final c = a.tanggal!.compareTo(b.tanggal!);
              return c != 0 ? c : (a.jam ?? '').compareTo(b.jam ?? '');
            });
        final byDay = <String, List<KontenItem>>{};
        for (final i in dated) {
          byDay.putIfAbsent(kontenDateKey(i.tanggal!), () => []).add(i);
        }
        final siap = [
          for (final i in list.value?.items ?? const <KontenItem>[])
            if (i.tahap == 'siap') i,
        ];
        final usulan = [
          for (final i in dated)
            if (i.usulan) i.id,
        ];
        final empty = byDay.isEmpty && siap.isEmpty && data.peringatan.isEmpty;

        return RefreshIndicator(
          onRefresh: refresh,
          child: empty
              ? const KontenEmpty(
                  title: 'Belum ada jadwal',
                  message:
                      'Konten yang sudah dijadwalkan muncul per tanggal di sini.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.sm,
                    GhinaSpace.page,
                    GhinaSpace.xxl,
                  ),
                  children: [
                    for (final w in data.peringatan)
                      Padding(
                        padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
                        child: ChunkyCard(
                          tinted: GhinaColors.orange,
                          padding: const EdgeInsets.all(GhinaSpace.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 20,
                                color: GhinaColors.orange.base,
                              ),
                              const SizedBox(width: GhinaSpace.sm),
                              Expanded(
                                child: Text(
                                  w.pesan.isEmpty ? w.kode : w.pesan,
                                  style: GhinaType.bodyS.copyWith(
                                    color: g.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (data.minggu.isNotEmpty) ...[
                      Wrap(
                        spacing: GhinaSpace.sm,
                        runSpacing: GhinaSpace.xs,
                        children: [
                          for (final m in data.minggu)
                            ChunkyPill(
                              label:
                                  'Minggu ${m.mulai.length >= 10 ? m.mulai.substring(5) : m.mulai}: ${m.n}/${m.target}',
                              color: m.target > 0 && m.n >= m.target
                                  ? GhinaColors.green
                                  : GhinaColors.gray,
                              soft: true,
                              uppercase: false,
                            ),
                        ],
                      ),
                      const SizedBox(height: GhinaSpace.md),
                    ],
                    if (usulan.isNotEmpty) ...[
                      ChunkyButton(
                        key: const ValueKey('setujui-semua'),
                        label: 'Setujui ${usulan.length} usulan',
                        icon: Icons.done_all_rounded,
                        expand: true,
                        loading: _busy,
                        onPressed: _busy
                            ? null
                            : () => _act(
                                'Jadwal disetujui',
                                (r) => r.setujuiJadwal(widget.officeId, usulan),
                              ),
                      ),
                      const SizedBox(height: GhinaSpace.md),
                    ],
                    for (final e in byDay.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: GhinaSpace.sm,
                          bottom: GhinaSpace.xs,
                        ),
                        child: Text(
                          kontenDateLabel(DateTime.parse(e.key)),
                          style: GhinaType.h3.copyWith(color: g.textPrimary),
                        ),
                      ),
                      for (final i in e.value)
                        _Row(
                          repo: repo,
                          item: i,
                          busy: _busy,
                          onOpen: () =>
                              openKontenPackage(context, widget.officeId, i.id),
                          onDate: () => _pickDate(i),
                          onApprove: i.usulan
                              ? () => _act(
                                  'Jadwal disetujui',
                                  (r) =>
                                      r.setujuiJadwal(widget.officeId, [i.id]),
                                )
                              : null,
                        ),
                    ],
                    if (siap.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: GhinaSpace.lg,
                          bottom: GhinaSpace.xs,
                        ),
                        child: Text(
                          'Siap tayang, belum ada tanggal',
                          style: GhinaType.h3.copyWith(color: g.textPrimary),
                        ),
                      ),
                      for (final i in siap)
                        _Row(
                          repo: repo,
                          item: i,
                          busy: _busy,
                          onOpen: () =>
                              openKontenPackage(context, widget.officeId, i.id),
                          onDate: () => _pickDate(i),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.repo,
    required this.item,
    required this.busy,
    required this.onOpen,
    required this.onDate,
    this.onApprove,
  });

  final KontenRepo repo;
  final KontenItem item;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDate;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: ChunkyCard(
        key: ValueKey('jadwal-${item.id}'),
        padding: const EdgeInsets.all(GhinaSpace.sm),
        borderRadius: GhinaRadii.rLg,
        onTap: onOpen,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 60,
              child: ClipRRect(
                borderRadius: GhinaRadii.rMd,
                child: KontenImage(repo: repo, url: item.coverUrl),
              ),
            ),
            const SizedBox(width: GhinaSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS
                        .w(800)
                        .copyWith(color: g.textPrimary),
                  ),
                  const SizedBox(height: GhinaSpace.xs),
                  Wrap(
                    spacing: GhinaSpace.xs,
                    children: [
                      if (item.jam != null)
                        Text(
                          item.jam!,
                          style: GhinaType.caption.copyWith(
                            color: g.textSecondary,
                          ),
                        ),
                      if (item.usulan)
                        const ChunkyPill(
                          label: 'Usulan',
                          color: GhinaColors.orange,
                          soft: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onApprove != null)
              IconButton(
                key: ValueKey('setujui-${item.id}'),
                tooltip: 'Setujui jadwal',
                onPressed: busy ? null : onApprove,
                icon: const Icon(Icons.check_circle_outline_rounded),
              ),
            IconButton(
              key: ValueKey('tanggal-${item.id}'),
              tooltip: 'Ganti tanggal',
              onPressed: busy ? null : onDate,
              icon: const Icon(Icons.event_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
