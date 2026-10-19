import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../../data/repositories/statement_repository_impl.dart'
    show statementMaxBytes;
import '../../../../../di/di.dart';
import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/widgets/widgets.dart';
import '../statement_state.dart';
import '../widgets/statement_confirm_sheet.dart';
import '../widgets/statement_status.dart';
import '../widgets/statement_upload_sheet.dart';

/// "Impor mutasi" (`/transactions/import`): the bank statements uploaded
/// before and "Unggah PDF". [sharedPdfPath] is a PDF shared to Ghina from
/// another app: the upload sheet opens with it right away.
class StatementImportsPage extends ConsumerStatefulWidget {
  const StatementImportsPage({super.key, this.sharedPdfPath});

  final String? sharedPdfPath;

  @override
  ConsumerState<StatementImportsPage> createState() =>
      _StatementImportsPageState();
}

class _StatementImportsPageState extends ConsumerState<StatementImportsPage> {
  /// Deleted here and not refetched yet.
  final Set<String> _hidden = {};
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedPdfPath;
    if (shared != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _upload(shared));
    }
  }

  Future<void> _upload(String path) async {
    final file = File(path);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (mounted) showErrorToast(context, 'PDF-nya nggak bisa dibuka.');
      return;
    } finally {
      // The intake copy is only needed for this read.
      try {
        if (mounted) await file.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    await _openSheet(p.basename(path), bytes);
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ref.read(killaMediaPickerProvider).pickPdfs(max: 1);
      if (picked.isEmpty || !mounted) return;
      await _openSheet(picked.first.name, picked.first.bytes);
    } catch (_) {
      if (mounted) showErrorToast(context, 'PDF-nya nggak bisa dibuka.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openSheet(String name, Uint8List bytes) async {
    if (bytes.length > statementMaxBytes) {
      showErrorToast(
        context,
        'PDF-nya lebih dari 10 MB. Coba file yang lebih kecil.',
      );
      return;
    }
    final created = await showStatementUploadSheet(
      context,
      fileName: name,
      bytes: bytes,
    );
    if (created == null || !mounted) return;
    ref.invalidate(statementImportsProvider);
    context.push('/transactions/import/${created.id}');
  }

  Future<bool> _delete(StatementImport i) async {
    final ok = await showStatementConfirmSheet(
      context,
      title: 'Hapus impor ini?',
      message:
          'Impor "${i.fileName}" dan PDF-nya dihapus. Transaksi yang sudah '
          'tersimpan tetap ada.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return false;
    try {
      await ref.read(statementRepositoryProvider).delete(i.id);
    } on StatementException catch (e) {
      if (mounted) showErrorToast(context, e.message);
      return false;
    }
    if (!mounted) return true;
    setState(() => _hidden.add(i.id));
    ref.invalidate(statementImportsProvider);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(statementImportsProvider);
    final forbidden = async.hasError && isStatementForbidden(async.error!);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Impor mutasi')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.refresh(statementImportsProvider.future),
              // Any known list wins, so the badge's background refetch
              // (statementAttentionProvider) never flashes a skeleton.
              child: switch (async) {
                AsyncValue(:final value?) => _list([
                  for (final i in value)
                    if (!_hidden.contains(i.id)) i,
                ]),
                AsyncError(:final error) when isStatementForbidden(error) =>
                  const ScrollableFill(
                    child: EmptyState(
                      key: Key('statement-forbidden'),
                      mood: MascotMood.thinking,
                      title: 'Impor mutasi belum aktif',
                      message:
                          'Fitur ini lagi dibuka buat akun tertentu dulu. '
                          'Akun kamu belum termasuk.',
                    ),
                  ),
                AsyncError(:final error) => ScrollableFill(
                  child: ErrorRetry(
                    message: statementErrorMessage(error),
                    onRetry: () => ref.invalidate(statementImportsProvider),
                  ),
                ),
                _ => const LoadingListView(hero: false, tiles: 3),
              },
            ),
          ),
          if (!forbidden)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  8,
                  GhinaSpace.page,
                  12,
                ),
                child: ChunkyButton(
                  key: const Key('statement-upload'),
                  label: 'Unggah PDF',
                  icon: Icons.upload_file_rounded,
                  size: ChunkyButtonSize.large,
                  loading: _picking,
                  onPressed: _picking ? null : _pick,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(List<StatementImport> items) {
    if (items.isEmpty) {
      return const ScrollableFill(
        child: EmptyState(
          key: Key('statement-empty'),
          mood: MascotMood.happy,
          title: 'Belum ada mutasi yang diimpor',
          message:
              'Unggah PDF mutasi rekening, Killa yang bacain. Kamu tinggal '
              'cek dan simpan.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        16,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, k) {
        final i = items[k];
        return Dismissible(
          key: ValueKey('statement-dismiss-${i.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _delete(i),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: GhinaColors.red.base,
              borderRadius: GhinaRadii.rXl,
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          child: _ImportTile(
            item: i,
            onTap: () => context.push('/transactions/import/${i.id}'),
            onDelete: () => _delete(i),
          ),
        );
      },
    );
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final StatementImport item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final i = item;
    final swatch = statementStatusSwatch(i.status);
    final c = i.counts;
    final caption = statementCaption(i);
    final detail = switch (i.status) {
      StatementStatus.ready =>
        '${c.pending} belum diputuskan · ${c.newRows} baru'
            '${c.uncertain + c.duplicate > 0 ? ' · ${c.uncertain + c.duplicate} mungkin dobel' : ''}',
      StatementStatus.done =>
        '${c.approved} tersimpan · ${c.ignored} diabaikan',
      StatementStatus.failed => i.error ?? 'Killa belum bisa membaca ini.',
      StatementStatus.parsing => 'Killa lagi baca mutasimu…',
    };
    return ChunkyCard(
      key: Key('statement-import-${i.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: onTap,
      child: Row(
        children: [
          StatementStatusAvatar(status: i.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption.isEmpty ? i.fileName : caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                if (caption.isNotEmpty)
                  Text(
                    i.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 6),
                ChunkyPill(
                  label: i.status.label,
                  color: swatch,
                  soft: true,
                  uppercase: false,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('statement-delete-${i.id}'),
            tooltip: 'Hapus impor',
            icon: Icon(Icons.delete_outline_rounded, color: g.textMuted),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
