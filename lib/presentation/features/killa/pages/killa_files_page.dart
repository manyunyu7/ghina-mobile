import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_data_providers.dart';
import '../widgets/killa_common.dart';

/// Joins a workspace directory and an entry name (`""` = root).
String killaJoin(String dir, String name) =>
    dir.isEmpty ? name : '${dir.endsWith('/') ? dir : '$dir/'}$name';

/// Human size: `812 B`, `4,2 KB`, `1,3 MB`.
String killaSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Killa's workspace browser (`/killa/files?path=`).
class KillaFilesPage extends ConsumerWidget {
  const KillaFilesPage({super.key, this.path = ''});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final async = ref.watch(killaDirProvider(path));
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(parts.isEmpty ? 'Berkas Killa' : parts.last),
        actions: [
          IconButton(
            tooltip: 'Commit',
            icon: const Icon(Icons.commit_rounded),
            onPressed: () => context.push('/killa/commits'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(killaDirProvider(path).future),
        child: switch (async) {
          AsyncData(:final value) => ListView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              8,
              GhinaSpace.page,
              32,
            ),
            children: [
              _Breadcrumb(parts: parts),
              const SizedBox(height: 12),
              if (value.entries.isEmpty)
                const EmptyState(
                  compact: true,
                  title: 'Folder kosong',
                  message: 'Belum ada berkas di sini.',
                )
              else
                ChunkyCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final e in value.entries)
                        ChunkyTile(
                          framed: false,
                          dense: true,
                          leading: Icon(
                            e.isDir ? Icons.folder_rounded : _fileIcon(e.name),
                            color: e.isDir
                                ? GhinaColors.yellow.base
                                : killaSwatch.base,
                          ),
                          title: e.name,
                          subtitle: e.isDir ? null : killaSize(e.size),
                          showChevron: true,
                          onTap: () {
                            final p = killaJoin(path, e.name);
                            context.push(
                              e.isDir
                                  ? '/killa/files?path=${Uri.encodeQueryComponent(p)}'
                                  : '/killa/file?path=${Uri.encodeQueryComponent(p)}',
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => KillaErrorView(
            error: error,
            onRetry: () => ref.invalidate(killaDirProvider(path)),
          ),
          _ => const LoadingListView(hero: false, tiles: 6),
        },
      ),
    );
  }

  static IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.md') || n.endsWith('.markdown')) {
      return Icons.article_rounded;
    }
    if (RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(n)) {
      return Icons.image_rounded;
    }
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (RegExp(r'\.(json|ya?ml|toml|js|ts|py|sh|dart)$').hasMatch(n)) {
      return Icons.code_rounded;
    }
    return Icons.description_rounded;
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final crumbs = <(String, String)>[('workspace', '')];
    for (var i = 0; i < parts.length; i++) {
      crumbs.add((parts[i], parts.sublist(0, i + 1).join('/')));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, (label, p)) in crumbs.indexed) ...[
            if (i > 0)
              Icon(Icons.chevron_right_rounded, size: 18, color: g.textMuted),
            ActionChip(
              avatar: i == 0
                  ? Icon(Icons.home_rounded, size: 16, color: killaSwatch.base)
                  : null,
              label: Text(label),
              onPressed: i == crumbs.length - 1
                  ? null
                  : () => context.push(
                      '/killa/files?path=${Uri.encodeQueryComponent(p)}',
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
