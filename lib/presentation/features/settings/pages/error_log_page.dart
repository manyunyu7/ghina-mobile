import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../data/diagnostics/error_log.dart';
import '../../../design_system/design_system.dart';

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Diagnostik › Log error: the last errors caught by [ErrorLog].
class ErrorLogPage extends StatelessWidget {
  const ErrorLogPage({super.key, this.logOverride});

  /// Tests inject their own log.
  final ErrorLog? logOverride;

  ErrorLog get log => logOverride ?? ErrorLog.instance;

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus semua log error?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) await log.clear();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final items = log.entries;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Log error'),
            actions: [
              IconButton(
                key: const ValueKey('error-log-share-all'),
                tooltip: 'Bagikan semua',
                onPressed: items.isEmpty
                    ? null
                    : () => SharePlus.instance.share(
                        ShareParams(
                          text: items.map((e) => e.toText()).join('\n---\n'),
                          subject: 'Log error Ghina',
                        ),
                      ),
                icon: const Icon(Icons.ios_share_rounded),
              ),
              IconButton(
                key: const ValueKey('error-log-clear'),
                tooltip: 'Hapus semua',
                onPressed: items.isEmpty ? null : () => _clear(context),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: items.isEmpty
              ? const EmptyState(
                  mood: MascotMood.happy,
                  title: 'Belum ada error',
                  message: 'Kalau ada yang gagal, jejaknya muncul di sini.',
                  compact: true,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    GhinaSpace.lg,
                    GhinaSpace.page,
                    GhinaSpace.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => GhinaSpace.gapSm,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return ChunkyTile(
                      key: ValueKey('error-log-$i'),
                      title: e.message,
                      subtitle:
                          '${_stamp(e.time)}${e.route == null ? '' : ' · ${e.route}'}'
                          '${e.count > 1 ? ' · x${e.count}' : ''}\n${e.kind}',
                      leading: CategoryAvatar(
                        icon: Icons.bug_report_rounded,
                        color: GhinaColors.red.base,
                        size: 40,
                      ),
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ErrorDetailPage(entry: e, log: log),
                        ),
                      ),
                    );
                  },
                ),
          backgroundColor: g.background,
        );
      },
    );
  }
}

class ErrorDetailPage extends StatelessWidget {
  const ErrorDetailPage({super.key, required this.entry, required this.log});

  final ErrorEntry entry;
  final ErrorLog log;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final text = entry.toText();
    return Scaffold(
      appBar: AppBar(title: const Text('Detail error')),
      body: ListView(
        padding: const EdgeInsets.all(GhinaSpace.page),
        children: [
          ChunkyCard(
            child: SelectableText(
              text,
              key: const ValueKey('error-detail-text'),
              style: GhinaType.bodyS.copyWith(
                color: g.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          GhinaSpace.gapLg,
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Salin',
                  variant: ChunkyButtonVariant.outline,
                  icon: Icons.copy_rounded,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      showToastBadge(
                        context,
                        message: 'Tersalin',
                        icon: Icons.check_rounded,
                        color: GhinaColors.green,
                      );
                    }
                  },
                ),
              ),
              GhinaSpace.gapSm,
              Expanded(
                child: ChunkyButton(
                  label: 'Bagikan',
                  icon: Icons.ios_share_rounded,
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: text, subject: 'Error Ghina'),
                  ),
                ),
              ),
            ],
          ),
          GhinaSpace.gapMd,
          ChunkyButton(
            label: 'Hapus entri ini',
            variant: ChunkyButtonVariant.danger,
            icon: Icons.delete_outline_rounded,
            onPressed: () {
              log.remove(entry); // in-memory list updates at once; file async
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
