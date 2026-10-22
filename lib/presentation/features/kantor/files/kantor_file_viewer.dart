import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_markdown.dart';
import '../widgets/kantor_states.dart';
import 'kantor_files_model.dart';

/// Opens one file: text with line numbers, markdown, or an image.
class KantorFileViewerScreen extends ConsumerStatefulWidget {
  const KantorFileViewerScreen({
    super.key,
    required this.officeId,
    required this.path,
    required this.root,
  });

  final String officeId;
  final String path;

  /// Absolute office folder, for "Salin path".
  final String root;

  @override
  ConsumerState<KantorFileViewerScreen> createState() => _FileViewerState();
}

class _FileViewerState extends ConsumerState<KantorFileViewerScreen> {
  KantorFileInfo? _info;
  Object? _error;
  bool _raw = false;

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
        '${kantorFilesBase(widget.officeId)}/read',
        query: {'path': widget.path},
      );
      if (mounted)
        setState(
          () => _info = KantorFileInfo.fromJson(
            (j as Map).cast<String, dynamic>(),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final info = _info;
    final name = widget.path.split('/').last;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          if (info != null && info.kind == 'text' && info.ext == '.md')
            IconButton(
              tooltip: _raw ? 'Tampilan rapi' : 'Teks mentah',
              icon: Icon(_raw ? Icons.article_rounded : Icons.code_rounded),
              onPressed: () => setState(() => _raw = !_raw),
            ),
          IconButton(
            tooltip: 'Salin path',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: '${widget.root}/${widget.path}'),
              );
              if (context.mounted) kantorToast(context, 'Path disalin');
            },
          ),
        ],
      ),
      body: _error != null
          ? KantorErrorView(error: _error!, onRetry: _load)
          : info == null
          ? const KantorLoading(count: 4)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.sm,
                    GhinaSpace.page,
                    GhinaSpace.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.path} · ${kantorFileSize(info.size)}${info.mtime == null ? '' : ' · diubah ${kantorAgo(info.mtime!.toUtc().toIso8601String())}'}${info.truncated ? ' · hanya 1 MB pertama' : ''}',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                ),
                Expanded(child: _body(context, info)),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, KantorFileInfo info) {
    switch (info.kind) {
      case 'image':
        final api = ref.watch(kantorApiProvider);
        if (api == null) return const SizedBox.shrink();
        if (info.ext == '.svg') {
          return const EmptyState(
            title: 'Gambar SVG',
            message:
                'SVG tidak ditampilkan di aplikasi. Salin path untuk membukanya di Mac.',
            compact: true,
          );
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.network(
              api.url('${kantorFilesBase(widget.officeId)}/raw', {
                'path': widget.path,
              }).toString(),
              headers: api.authHeaders,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) =>
                  const EmptyState(title: 'Gambar gagal dimuat', compact: true),
            ),
          ),
        );
      case 'text':
        if (info.ext == '.md' && !_raw) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            child: KantorMarkdown(info.text, selectable: true),
          );
        }
        return _code(context, info.text);
      case 'video' || 'audio' || 'pdf':
        return EmptyState(
          title: 'Belum bisa dibuka di sini',
          message:
              'File ${info.kind} (${kantorFileSize(info.size)}) dibuka di Mac. Salin path lewat tombol di atas.',
          compact: true,
        );
      default:
        return const EmptyState(
          title: 'File biner',
          message: 'Tidak bisa ditampilkan sebagai teks.',
          compact: true,
        );
    }
  }

  Widget _code(BuildContext context, String text) {
    final g = context.ghina;
    final lines = text.split('\n');
    final digits = '${lines.length}'.length;
    final style = GhinaType.caption.copyWith(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: g.textPrimary,
    );
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: GhinaSpace.sm,
          vertical: GhinaSpace.sm,
        ),
        itemCount: lines.length,
        itemBuilder: (_, i) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: digits * 8.0 + 10,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: style.copyWith(color: g.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(lines[i].isEmpty ? ' ' : lines[i], style: style),
            ),
          ],
        ),
      ),
    );
  }
}
