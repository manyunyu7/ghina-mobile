import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../pratinjau/pratinjau_feed.dart';
import '../widgets/kantor_states.dart';
import 'kantor_actions.dart';

/// Sesi > "Pratinjau": pratinjau yang dikirim sesi ini (atau role-nya), plus
/// tombol "Minta pratinjau" yang mengetik permintaan ke agen.
/// Disaring di server (`?sid=`).
class KantorSessionPratinjauTab extends ConsumerStatefulWidget {
  const KantorSessionPratinjauTab({
    super.key,
    required this.officeId,
    required this.sid,
    required this.role,
    required this.actions,
  });

  final String officeId;
  final String sid;
  final String? role;
  final KantorActions? actions;

  @override
  ConsumerState<KantorSessionPratinjauTab> createState() => _State();
}

class _State extends ConsumerState<KantorSessionPratinjauTab> {
  bool _sending = false;

  static const _ask =
      'Tolong kirim pratinjau hasilnya lewat pratinjau_kirim '
      '(folder/berkas yang relevan).';

  Future<void> _request() async {
    final a = widget.actions;
    if (a == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await a.sendText(widget.sid, _ask);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Permintaan pratinjau terkirim ke agen')),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Gagal mengirim: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.officeId, widget.sid);
    final feed = ref.watch(kantorPratinjauSessionProvider(key));
    final api = ref.watch(kantorApiProvider);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        GhinaSpace.md,
        GhinaSpace.page,
        GhinaSpace.sm,
      ),
      child: ChunkyButton(
        label: 'Minta pratinjau',
        icon: Icons.preview_rounded,
        size: ChunkyButtonSize.medium,
        variant: ChunkyButtonVariant.secondary,
        loading: _sending,
        expand: true,
        onPressed: widget.actions == null ? null : _request,
      ),
    );
    return RefreshIndicator(
      onRefresh: () => ref.refresh(kantorPratinjauSessionProvider(key).future),
      child: feed.when(
        skipLoadingOnRefresh: true,
        data: (f) {
          final items = f.items;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: GhinaSpace.xxl),
            children: [
              header,
              if (items.isEmpty || api == null)
                const EmptyState(
                  title: 'Belum ada pratinjau dari agen ini',
                  message:
                      'Ketuk "Minta pratinjau" agar agen mengirim hasilnya (desain, carousel, halaman, PDF) ke sini.',
                  compact: true,
                )
              else
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      GhinaSpace.page,
                      GhinaSpace.sm,
                      GhinaSpace.page,
                      GhinaSpace.sm,
                    ),
                    child: PratinjauCard(key: ValueKey(it.id), api: api, item: it),
                  ),
            ],
          );
        },
        error: (e, _) => KantorErrorView(
          error: e,
          onRetry: () => ref.invalidate(kantorPratinjauSessionProvider(key)),
        ),
        loading: () => const KantorLoading(count: 2),
      ),
    );
  }
}
