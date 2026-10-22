import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';
import '../roles/kantor_role.dart';
import '../roles/kantor_ui.dart';
import '../widgets/kantor_states.dart';
import 'kantor_file_viewer.dart';
import 'kantor_files_model.dart';

/// Tab "File": browse the office folder, read files, upload, make folders.
class KantorFilesTab extends ConsumerStatefulWidget {
  const KantorFilesTab({super.key, required this.officeId});

  final String officeId;

  @override
  ConsumerState<KantorFilesTab> createState() => _KantorFilesTabState();
}

class _KantorFilesTabState extends ConsumerState<KantorFilesTab> {
  String _dir = '';
  bool _all = false;
  String _q = '';
  List<KantorFileEntry>? _results;
  Timer? _searchTimer;
  bool _uploading = false;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  ({String office, String path, bool all}) get _key =>
      (office: widget.officeId, path: _dir, all: _all);

  void _cd(String path) => setState(() {
    _dir = path;
    _q = '';
    _results = null;
  });

  void _search(String q) {
    _q = q;
    _searchTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      final api = ref.read(kantorApiProvider);
      if (api == null) return;
      try {
        final j = await api.get(
          kantorFilesBase(widget.officeId),
          query: {'path': _dir, 'q': q.trim()},
        );
        if (!mounted || _q != q) return;
        setState(() {
          _results = [
            for (final r in ((j as Map)['results'] as List?) ?? const [])
              if (r is Map) KantorFileEntry.fromJson(r.cast<String, dynamic>()),
          ];
        });
      } catch (e) {
        if (mounted) kantorToast(context, kantorErrorText(e), bad: true);
      }
    });
  }

  Future<void> _mkdir() async {
    final c = TextEditingController();
    final name = await showChunkyDialog<String>(
      context,
      builder: (d) => ChunkyDialog(
        title: 'Folder baru',
        message: 'Dibuat di ${_dir.isEmpty ? 'folder kantor' : _dir}',
        content: ChunkyTextField(
          controller: c,
          label: 'Nama folder',
          autofocus: true,
          textCapitalization: TextCapitalization.none,
        ),
        actions: [
          ChunkyButton(
            label: 'Buat',
            onPressed: () => Navigator.of(d).pop(c.text.trim()),
          ),
          ChunkyButton(
            label: 'Batal',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(d).pop(),
          ),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    String? path;
    final ok = await kantorGuard(context, () async {
      final r = await api.post('${kantorFilesBase(widget.officeId)}/mkdir', {
        'path': _dir,
        'name': name,
      });
      path = (r as Map)['path'] as String?;
    });
    if (!ok || !mounted) return;
    if (path != null) {
      _cd(path!);
    } else {
      ref.invalidate(kantorFolderProvider(_key));
    }
  }

  Future<void> _upload() async {
    final api = ref.read(kantorApiProvider);
    if (api == null) return;
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final dir = _dir;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(minutes: 5),
      ),
    );
    var done = 0;
    for (final f in picked) {
      try {
        final bytes = await f.readAsBytes();
        final r = await dio.post<Map<String, dynamic>>(
          api.url('${kantorFilesBase(widget.officeId)}/upload', {
            'path': dir,
            'name': f.name,
          }).toString(),
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {
              ...api.authHeaders,
              Headers.contentLengthHeader: bytes.length,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
          ),
        );
        done++;
        if (r.data?['renamed'] == true && mounted) {
          kantorToast(
            context,
            '${f.name} sudah ada, disimpan sebagai ${r.data?['name']}',
            warn: true,
          );
        }
      } on DioException catch (e) {
        final msg =
            (e.response?.data is Map
                ? (e.response!.data as Map)['error']
                : null) ??
            e.message ??
            'gagal';
        if (mounted) kantorToast(context, '${f.name}: $msg', bad: true);
      } catch (e) {
        if (mounted) kantorToast(context, '${f.name}: $e', bad: true);
      }
    }
    dio.close();
    if (!mounted) return;
    setState(() => _uploading = false);
    ref.invalidate(
      kantorFolderProvider((office: widget.officeId, path: dir, all: _all)),
    );
    if (done > 0)
      kantorToast(context, done > 1 ? '$done file diupload' : 'File diupload');
  }

  void _openFile(KantorFileEntry e, String root) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KantorFileViewerScreen(
          officeId: widget.officeId,
          path: e.path,
          root: root,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    ref.listen(kantorEventsProvider, (_, next) {
      final m = next.value;
      if (m != null &&
          m['t'] == 'files' &&
          m['office'] == widget.officeId &&
          m['path'] == _dir) {
        ref.invalidate(kantorFolderProvider(_key));
      }
    });
    final folder = ref.watch(kantorFolderProvider(_key));
    final officeName =
        ref.watch(kantorOfficeProvider(widget.officeId)).value?.name ??
        'Kantor';
    final parts = _dir.isEmpty ? const <String>[] : _dir.split('/');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.md,
            GhinaSpace.page,
            GhinaSpace.sm,
          ),
          child: Column(
            children: [
              ChunkyTextField(
                hint: 'Cari nama file',
                prefixIcon: Icons.search_rounded,
                onChanged: _search,
              ),
              const SizedBox(height: GhinaSpace.sm),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  children: [
                    Row(
                      children: [
                        _crumb(context, officeName, () => _cd('')),
                        for (var i = 0; i < parts.length; i++) ...[
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: g.textMuted,
                          ),
                          _crumb(
                            context,
                            parts[i],
                            () => _cd(parts.take(i + 1).join('/')),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: GhinaSpace.sm,
                      children: [
                        ChunkyButton(
                          label: 'Folder',
                          icon: Icons.create_new_folder_rounded,
                          size: ChunkyButtonSize.small,
                          variant: ChunkyButtonVariant.outline,
                          onPressed: _mkdir,
                        ),
                        ChunkyButton(
                          label: 'Upload',
                          icon: Icons.upload_rounded,
                          size: ChunkyButtonSize.small,
                          loading: _uploading,
                          onPressed: _uploading ? null : _upload,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Tersembunyi',
                    style: GhinaType.caption.copyWith(color: g.textMuted),
                  ),
                  Switch(
                    value: _all,
                    onChanged: (v) => setState(() {
                      _all = v;
                      _results = null;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: folder.when(
            loading: () => const KantorLoading(),
            error: (e, _) => KantorErrorView(
              error: e,
              onRetry: () => ref.invalidate(kantorFolderProvider(_key)),
            ),
            data: (f) {
              final rows = _results ?? f.entries;
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(kantorFolderProvider(_key));
                  await ref.read(kantorFolderProvider(_key).future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    0,
                    GhinaSpace.page,
                    96,
                  ),
                  children: [
                    if (_dir.isNotEmpty && _results == null)
                      _tile(
                        context,
                        icon: Icons.arrow_upward_rounded,
                        title: '..',
                        onTap: () =>
                            _cd(parts.take(parts.length - 1).join('/')),
                      ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(GhinaSpace.xl),
                        child: Center(
                          child: Text(
                            _results != null
                                ? 'Tidak ada yang cocok.'
                                : 'Folder kosong. Upload file untuk mengisinya.',
                            style: GhinaType.body.copyWith(color: g.textMuted),
                          ),
                        ),
                      ),
                    for (final e in rows)
                      _tile(
                        context,
                        icon: e.dir
                            ? Icons.folder_rounded
                            : e.isImage
                            ? Icons.image_rounded
                            : Icons.description_rounded,
                        iconColor: e.dir ? GhinaColors.blue.base : null,
                        title: _results != null ? e.path : e.name,
                        subtitle: e.dir
                            ? null
                            : [
                                kantorFileSize(e.size),
                                if (e.mtime != null)
                                  kantorAgo(e.mtime!.toUtc().toIso8601String()),
                              ].where((s) => s.isNotEmpty).join(' · '),
                        onTap: () => e.dir ? _cd(e.path) : _openFile(e, f.root),
                      ),
                    if (_results == null && f.hidden > 0)
                      Padding(
                        padding: const EdgeInsets.all(GhinaSpace.md),
                        child: Text(
                          '${f.hidden} item tersembunyi (dotfile, node_modules, build…)',
                          textAlign: TextAlign.center,
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _crumb(BuildContext context, String label, VoidCallback onTap) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label),
      );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
    child: ChunkyTile(
      title: title,
      subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
      leading: Icon(icon, color: iconColor ?? context.ghina.textSecondary),
      dense: true,
      onTap: onTap,
    ),
  );
}
