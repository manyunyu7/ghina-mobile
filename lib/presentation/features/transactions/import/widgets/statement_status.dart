import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../domain/entities/entities.dart';
import '../../../../design_system/design_system.dart';
import '../statement_state.dart';

/// Most status cards shown at once on the Transactions page; the rest are
/// behind "Lihat semua impor".
const _maxCards = 2;

/// The status icon of an import; while Killa is reading, a spinner circles it.
class StatementStatusAvatar extends StatelessWidget {
  const StatementStatusAvatar({
    super.key,
    required this.status,
    this.size = 40,
  });

  final StatementStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final swatch = statementStatusSwatch(status);
    final avatar = CategoryAvatar(
      icon: statementStatusIcon(status),
      color: swatch.base,
      size: size,
      soft: true,
    );
    if (status != StatementStatus.parsing) return avatar;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatar,
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: swatch.base,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Impor mutasi" in the Transactions app bar, with a badge: the number of
/// imports ready to review (orange), else a dot for a failure (red) or for one
/// Killa is still reading (blue).
class StatementImportButton extends ConsumerWidget {
  const StatementImportButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(statementAttentionProvider);
    const icon = Icon(Icons.upload_file_rounded);
    final Widget badged;
    if (a.ready.isNotEmpty) {
      badged = Badge(
        key: const ValueKey('tx-import-badge-ready'),
        label: Text('${a.ready.length}'),
        backgroundColor: GhinaColors.orange.base,
        child: icon,
      );
    } else if (a.failed.isNotEmpty || a.parsing.isNotEmpty) {
      final failed = a.failed.isNotEmpty;
      badged = Badge(
        key: ValueKey(
          failed ? 'tx-import-badge-failed' : 'tx-import-badge-parsing',
        ),
        smallSize: 9,
        backgroundColor: (failed ? GhinaColors.red : GhinaColors.blue).base,
        child: icon,
      );
    } else {
      badged = icon;
    }
    return IconButton(
      key: const ValueKey('tx-import'),
      tooltip: a.ready.isNotEmpty
          ? 'Impor mutasi: siap direview'
          : a.failed.isNotEmpty
          ? 'Impor mutasi: ada yang gagal'
          : a.parsing.isNotEmpty
          ? 'Impor mutasi: Killa lagi membaca'
          : 'Impor mutasi',
      icon: badged,
      onPressed: () => context.push('/transactions/import'),
    );
  }
}

/// Status cards above the transaction list, one per import that needs a look
/// (being read, ready to review, failed). Tapping opens the import. Nothing
/// when there is nothing to tell.
class StatementStatusCards extends ConsumerWidget {
  const StatementStatusCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(statementAttentionProvider).items;
    if (items.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    final more = items.length - _maxCards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in items.take(_maxCards)) ...[
          _StatusCard(
            item: i,
            onTap: () => context.push('/transactions/import/${i.id}'),
          ),
          const SizedBox(height: GhinaSpace.sm),
        ],
        if (more > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('statement-status-more'),
              onPressed: () => context.push('/transactions/import'),
              child: Text(
                'Lihat semua impor (+$more)',
                style: GhinaType.caption
                    .w(800)
                    .copyWith(color: g.textSecondary),
              ),
            ),
          ),
        const SizedBox(height: GhinaSpace.sm),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.item, required this.onTap});

  final StatementImport item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final i = item;
    final caption = statementCaption(i);
    final label = caption.isEmpty ? i.fileName : caption;
    final (title, detail, action) = switch (i.status) {
      StatementStatus.parsing => (
        'Killa lagi baca mutasimu…',
        '$label · boleh ditinggal, kabarnya muncul di sini',
        null,
      ),
      StatementStatus.ready => (
        'Mutasi siap direview',
        '$label · ${i.counts.pending} baris nunggu keputusanmu',
        'Review',
      ),
      StatementStatus.failed => (
        'Impor mutasi gagal',
        i.error ?? 'Killa belum bisa membaca $label.',
        'Lihat',
      ),
      StatementStatus.done => ('Impor selesai', label, null),
    };
    final swatch = statementStatusSwatch(i.status);
    return ChunkyCard(
      key: Key('statement-status-${i.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      tinted: swatch,
      onTap: onTap,
      semanticLabel: '$title. $detail',
      child: Row(
        children: [
          StatementStatusAvatar(status: i.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            ChunkyPill(
              label: action,
              color: swatch,
              soft: true,
              uppercase: false,
            ),
          ] else
            Icon(Icons.chevron_right_rounded, color: g.textMuted),
        ],
      ),
    );
  }
}
