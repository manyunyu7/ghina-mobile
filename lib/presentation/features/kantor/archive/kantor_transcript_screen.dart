import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';

/// Read-only transcript of one session (the last stretch of the conversation).
class KantorTranscriptScreen extends ConsumerStatefulWidget {
  const KantorTranscriptScreen({
    super.key,
    required this.sid,
    required this.title,
  });

  final String sid;
  final String title;

  @override
  ConsumerState<KantorTranscriptScreen> createState() => _TranscriptState();
}

class _TranscriptState extends ConsumerState<KantorTranscriptScreen> {
  List<Map<String, dynamic>>? _items;
  bool _missing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    setState(() => _error = null);
    try {
      final j = await api.get(
        '/api/sessions/${Uri.encodeComponent(widget.sid)}/transcript',
        query: {'n': 200},
      );
      final m = (j as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _missing = m['missing'] == true;
        _items = [
          for (final i in (m['items'] as List?) ?? const [])
            if (i is Map) i.cast<String, dynamic>(),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final items = _items;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : items == null
          ? const KantorLoading()
          : items.isEmpty
          ? EmptyState(
              title: 'Transkrip kosong',
              message: _missing
                  ? 'Berkas transkrip sesi ini sudah tidak ada di Mac.'
                  : 'Belum ada percakapan yang tercatat.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(GhinaSpace.page),
              itemCount: items.length,
              itemBuilder: (_, i) => _item(context, items[i]),
            ),
    );
  }

  Widget _item(BuildContext context, Map<String, dynamic> it) {
    final g = context.ghina;
    final s = it['s'] as String? ?? '';
    final time = kantorHhmm(it['at'] as String?);
    switch (it['k']) {
      case 'user':
        return Padding(
          padding: const EdgeInsets.only(
            bottom: GhinaSpace.md,
            left: GhinaSpace.xl,
          ),
          child: ChunkyCard(
            tinted: GhinaColors.blue,
            padding: const EdgeInsets.all(GhinaSpace.md),
            depth: GhinaDepth.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kamu · $time',
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  s,
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
              ],
            ),
          ),
        );
      case 'text':
        return Padding(
          padding: const EdgeInsets.only(
            bottom: GhinaSpace.md,
            right: GhinaSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(time, style: GhinaType.caption.copyWith(color: g.textMuted)),
              KantorMarkdown(s, selectable: true),
            ],
          ),
        );
      case 'tool':
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '› $s',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(
              color: g.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        );
      case 'result':
        final err = it['err'] == true;
        return Padding(
          padding: const EdgeInsets.only(
            bottom: GhinaSpace.sm,
            left: GhinaSpace.md,
          ),
          child: Text(
            s,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.caption.copyWith(
              color: err ? GhinaColors.red.base : g.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
