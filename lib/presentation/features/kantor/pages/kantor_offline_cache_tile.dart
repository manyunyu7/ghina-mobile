import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../session/kantor_snapshot_store.dart';

/// "1,2 MB" / "340 KB" with an Indonesian decimal comma.
String kantorCacheSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb ~/ 10) {
    final kb = (bytes / 1024).ceil();
    return '$kb KB';
  }
  final v = bytes / mb;
  final s = v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');
  return '$s MB';
}

/// Pengaturan: how much the offline snapshot uses, and a button to clear it
/// (disk and the in-memory chat cache).
class KantorOfflineCacheTile extends ConsumerWidget {
  const KantorOfflineCacheTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(kantorSnapshotStoreProvider);
    return ValueListenableBuilder<int>(
      valueListenable: store.usedBytes,
      builder: (context, used, _) => ChunkyTile(
        key: const ValueKey('kantor-offline-cache'),
        title: 'Cache offline',
        subtitle:
            '${kantorCacheSize(used)} dari ${kantorCacheSize(store.maxBytes)}'
            ' - kantor dan chat terakhir, tampil saat app baru dibuka',
        leading: const Icon(Icons.offline_pin_outlined),
        trailing: TextButton(
          onPressed: used == 0
              ? null
              : () async {
                  await store.clearAll();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache offline dihapus')),
                  );
                },
          child: const Text('Hapus cache'),
        ),
      ),
    );
  }
}
