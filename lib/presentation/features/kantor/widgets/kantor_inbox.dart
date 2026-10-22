import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../kantor_format.dart';

/// Pending permission requests with Izinkan / Tolak. [offices] (from
/// `/api/state`) lets the row show which office asked.
class KantorInboxList extends ConsumerStatefulWidget {
  const KantorInboxList({
    super.key,
    required this.items,
    this.offices = const [],
    this.showOffice = true,
  });

  final List<dynamic> items;
  final List<dynamic> offices;
  final bool showOffice;

  @override
  ConsumerState<KantorInboxList> createState() => _KantorInboxListState();
}

class _KantorInboxListState extends ConsumerState<KantorInboxList> {
  final _busy = <String>{};

  Future<void> _answer(String id, String behavior) async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _busy.add(id));
    try {
      await api.post('/api/inbox/$id', {'behavior': behavior});
      ref.invalidate(kantorStateProvider);
      if (mounted) {
        showToastBadge(
          context,
          message: behavior == 'allow' ? 'Diizinkan' : 'Ditolak',
          icon: behavior == 'allow' ? Icons.check_rounded : Icons.block_rounded,
          color: behavior == 'allow' ? GhinaColors.green : GhinaColors.red,
        );
      }
    } on KantorException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (widget.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: GhinaSpace.sm),
        child: Text(
          'Tidak ada yang menunggu izin.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        for (final raw in widget.items)
          Builder(
            builder: (_) {
              final it = Map<String, dynamic>.from(raw as Map);
              final id = '${it['id']}';
              final office = widget.offices
                  .whereType<Map>()
                  .where((o) => o['id'] == it['office'])
                  .firstOrNull;
              final held = it['held'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: GhinaSpace.md),
                child: ChunkyCard(
                  tinted: GhinaColors.orange,
                  padding: const EdgeInsets.all(GhinaSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          '${it['who'] ?? 'Sesi'}',
                          if (widget.showOffice && office != null)
                            '${office['name']}',
                          '${it['tool'] ?? ''}',
                          kantorAgo(it['created_at']),
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: GhinaType.bodyS
                            .w(800)
                            .copyWith(color: g.textPrimary),
                      ),
                      const SizedBox(height: GhinaSpace.xs),
                      Text(
                        kantorShort(it['summary'], 220),
                        style: GhinaType.caption.copyWith(
                          fontFamily: 'monospace',
                          color: g.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GhinaSpace.sm),
                      if (held)
                        Row(
                          children: [
                            Expanded(
                              child: ChunkyButton(
                                label: 'Izinkan',
                                size: ChunkyButtonSize.small,
                                loading: _busy.contains(id),
                                onPressed: _busy.contains(id)
                                    ? null
                                    : () => _answer(id, 'allow'),
                              ),
                            ),
                            const SizedBox(width: GhinaSpace.sm),
                            Expanded(
                              child: ChunkyButton(
                                label: 'Tolak',
                                size: ChunkyButtonSize.small,
                                variant: ChunkyButtonVariant.outline,
                                onPressed: _busy.contains(id)
                                    ? null
                                    : () => _answer(id, 'deny'),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Sudah pindah ke terminal sesinya. Jawab dari sana.',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
