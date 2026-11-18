import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/platform/kantor_downloads.dart';
import '../../../../di/kantor_providers.dart';
import 'pratinjau_widgets.dart';

void openKantorDownloads(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const KantorDownloadsPage()));

class KantorDownloadsButton extends StatelessWidget {
  const KantorDownloadsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Unduhan',
    icon: const Icon(Icons.download_for_offline_outlined),
    onPressed: () => openKantorDownloads(context),
  );
}

/// A visible action by the selected file, also reused by fullscreen and menus.
class PratinjauDownloadActions extends StatefulWidget {
  const PratinjauDownloadActions({
    super.key,
    required this.api,
    required this.item,
    this.file,
  });
  final KantorApi api;
  final PratinjauItem item;
  final PratinjauFile? file;
  @override
  State<PratinjauDownloadActions> createState() => _PreviewDownloadsState();
}

class _PreviewDownloadsState extends State<PratinjauDownloadActions> {
  bool _busy = false;
  Future<void> _download(List<PratinjauFile> files) async {
    if (_busy) return;
    setState(() => _busy = true);
    var count = 0;
    String? error;
    try {
      for (final file in files) {
        final url = pratinjauUri(widget.api, file.url);
        final base = Uri.parse(widget.api.config.baseUrl);
        if (url.origin != base.origin) throw const FormatException();
        await KantorDownloads.instance.enqueue(
          url: url,
          name: file.name,
          mime: file.mime,
          description: '${widget.item.title} · ${base.host}',
        );
        count++;
      }
    } on MissingPluginException {
      error = 'Unduhan background tersedia di aplikasi Android terbaru.';
    } catch (_) {
      error =
          'Tidak bisa memulai unduhan. Buka ulang pratinjau lalu coba lagi.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '$count berkas masuk antrean. Boleh tinggalkan Ravel.'
              : '$error${count > 0 ? ' $count berkas sudah masuk antrean.' : ''}',
        ),
        action: SnackBarAction(
          label: 'Unduhan',
          onPressed: () => openKantorDownloads(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.item.files;
    if (files.isEmpty || widget.item.filesPurged) {
      return const SizedBox.shrink();
    }
    final selected = widget.file ?? files.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _download([selected]),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              _busy
                  ? 'Menyiapkan…'
                  : 'Unduh asli · ${downloadBytes(selected.size)}',
            ),
          ),
          if (files.length > 1)
            OutlinedButton(
              onPressed: _busy ? null : () => _download(files),
              child: Text('Unduh semua (${files.length})'),
            ),
          TextButton.icon(
            onPressed: () => openKantorDownloads(context),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Unduhan'),
          ),
        ],
      ),
    );
  }
}

Future<void> showPratinjauDownloads(
  BuildContext context,
  KantorApi api,
  PratinjauItem item,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .6,
    minChildSize: .3,
    builder: (_, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Unduh pratinjau', style: Theme.of(c).textTheme.titleLarge),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Berkas asli disimpan di perangkat. Unduhan tetap berjalan saat aplikasi ditinggal.',
          ),
        ),
        for (final file in item.files) ...[
          Text(file.name, style: Theme.of(c).textTheme.titleSmall),
          PratinjauDownloadActions(api: api, item: item, file: file),
          const Divider(),
        ],
      ],
    ),
  ),
);

class KantorDownloadsPage extends StatefulWidget {
  const KantorDownloadsPage({super.key});
  @override
  State<KantorDownloadsPage> createState() => _DownloadsState();
}

class _DownloadsState extends State<KantorDownloadsPage>
    with WidgetsBindingObserver {
  List<KantorDownload> _items = [];
  final Set<int> _busy = {};
  Timer? _timer;
  String? _error;
  bool _loading = true, _fetching = false;
  String _filter = 'all';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final items = await KantorDownloads.instance.list();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Tidak bisa membaca unduhan. Coba lagi atau perbarui aplikasi Android.';
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _act(String action, KantorDownload item) async {
    if (_busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    try {
      await KantorDownloads.instance.action(action, item.id);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Berkas tidak dapat diproses. Pastikan berkas masih ada dan aplikasi pembukanya tersedia.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Unduhan'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Boleh tinggalkan Ravel. Unduhan tetap ditangani Android saat layar mati. Buka atau bagikan hasilnya dari sini.',
          ),
          const SizedBox(height: 16),
          if (_items.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (key, label, count) in [
                  ('all', 'Semua', _items.length),
                  ('active', 'Berjalan', _items.where((r) => r.active).length),
                  (
                    'complete',
                    'Selesai',
                    _items.where((r) => r.complete).length,
                  ),
                  (
                    'other',
                    'Perlu perhatian',
                    _items.where((r) => !r.active && !r.complete).length,
                  ),
                ])
                  ChoiceChip(
                    label: Text('$label ($count)'),
                    selected: _filter == key,
                    onSelected: (_) => setState(() => _filter = key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!),
          if (!_loading && _items.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 56),
                  SizedBox(height: 12),
                  Text('Belum ada unduhan'),
                  Text('Buka pratinjau lalu pilih Unduh asli.'),
                ],
              ),
            ),
          for (final item in _items.where(
            (r) => switch (_filter) {
              'active' => r.active,
              'complete' => r.complete,
              'other' => !r.active && !r.complete,
              _ => true,
            },
          ))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          item.complete
                              ? Icons.task_alt_rounded
                              : item.active
                              ? Icons.downloading_rounded
                              : Icons.info_outline_rounded,
                          color: item.complete
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: item.complete ? Colors.green : null,
                      ),
                    ),
                    if (item.active) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: item.progress),
                      const SizedBox(height: 4),
                      Text(
                        '${downloadBytes(item.received)} / ${downloadBytes(item.total)}'
                        '${item.progress == null ? '' : ' · ${(item.progress! * 100).round()}%'}',
                      ),
                    ],
                    if (item.complete) Text(item.location),
                    if (item.complete && item.total >= 0)
                      Text(downloadBytes(item.total)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (item.complete) ...[
                          FilledButton.tonalIcon(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _act('open', item),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Buka'),
                          ),
                          TextButton.icon(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _act('share', item),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Bagikan'),
                          ),
                        ] else
                          TextButton.icon(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _act(
                                    item.active ? 'cancel' : 'retry',
                                    item,
                                  ),
                            icon: Icon(
                              item.active
                                  ? Icons.close_rounded
                                  : Icons.refresh_rounded,
                            ),
                            label: Text(item.active ? 'Batalkan' : 'Coba lagi'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
