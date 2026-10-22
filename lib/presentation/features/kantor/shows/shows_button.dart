import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';
import '../widgets/kantor_states.dart';
import 'shows_data.dart';
import 'shows_model.dart';
import 'shows_screen.dart';

/// AppBar eye: unseen badge, a light notice when an agent opens something,
/// and the list of what was opened.
class KantorShowsButton extends ConsumerWidget {
  const KantorShowsButton({super.key, this.hideWhenIdle = false});

  /// Saat true, tombol hanya tampil bila ada yang belum dilihat (listener
  /// snackbar tetap aktif) — untuk app bar yang sempit.
  final bool hideWhenIdle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(kantorShowsProvider.select((s) => s.fresh), (prev, next) {
      if (next == null || next.id == prev?.id) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${next.who} membukakan ${kantorShort(next.label, 40)} untukmu',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => openKantorShow(context, next),
          ),
        ),
      );
    });
    final unseen = ref.watch(kantorShowsProvider.select((s) => s.unseen));
    if (hideWhenIdle && unseen == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Dibuka untukmu',
      onPressed: () => showKantorShows(context),
      icon: Badge(
        isLabelVisible: unseen > 0,
        label: Text(unseen > 9 ? '9+' : '$unseen'),
        child: const Icon(Icons.visibility_outlined),
      ),
    );
  }
}

Future<void> showKantorShows(BuildContext context) {
  final navigator = Navigator.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => _ShowsList(
        scroll: scroll,
        onOpen: (s) {
          Navigator.of(sheet).pop();
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => KantorShowScreen(show: s)),
          );
        },
      ),
    ),
  );
}

class _ShowsList extends ConsumerWidget {
  const _ShowsList({required this.scroll, required this.onOpen});

  final ScrollController scroll;
  final void Function(KantorShow) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final st = ref.watch(kantorShowsProvider);
    final names = {
      for (final o
          in (ref.watch(kantorStateProvider).value?['offices'] as List? ??
              const []))
        '${(o as Map)['id']}': '${o['name']}',
    };
    final notifier = ref.read(kantorShowsProvider.notifier);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            0,
            GhinaSpace.sm,
            GhinaSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Dibuka untukmu',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              if (st.items.isNotEmpty)
                TextButton(
                  onPressed: notifier.closeAll,
                  child: const Text('Tutup semua'),
                ),
            ],
          ),
        ),
        Expanded(
          child: !st.loaded
              ? const KantorLoading(count: 3)
              : st.items.isEmpty
              ? st.error != null
                    ? KantorErrorView(
                        error: st.error!,
                        onRetry: notifier.refresh,
                      )
                    : const EmptyState(
                        title: 'Belum ada yang dibukakan',
                        message: 'Minta agen: "tunjukkan file itu".',
                        compact: true,
                      )
              : RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView.separated(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: st.items.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: g.border),
                    itemBuilder: (_, i) {
                      final s = st.items[i];
                      return ListTile(
                        key: ValueKey('show-${s.id}'),
                        leading: Badge(
                          isLabelVisible: !s.seen,
                          smallSize: 9,
                          child: Icon(
                            s.isUrl
                                ? Icons.link_rounded
                                : s.isFolder
                                ? Icons.folder_rounded
                                : Icons.description_rounded,
                          ),
                        ),
                        title: Text(
                          '${s.who} · ${kantorShort(s.label, 36)}',
                          style: TextStyle(
                            fontWeight: s.seen
                                ? FontWeight.w500
                                : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (s.note.isNotEmpty) kantorShort(s.note, 120),
                            '${names[s.office] ?? s.office} · ${kantorAgo(s.at)}'
                                '${s.lines == null ? '' : ' · baris ${s.lines!.$1}${s.lines!.$2 > s.lines!.$1 ? '–${s.lines!.$2}' : ''}'}',
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: s.note.isNotEmpty,
                        trailing: IconButton(
                          tooltip: 'Tutup',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => notifier.close(s.id),
                        ),
                        onTap: () => onOpen(s),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
