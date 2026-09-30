import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../controllers/killa_data_providers.dart';
import '../widgets/killa_common.dart';

/// One workspace file (`/killa/file?path=`): Markdown rendered (with a
/// "Sumber" toggle), anything else monospace. **Edit** → monospace editor →
/// Simpan (`PUT file`); the **Commit** bar commits the workspace and shows the
/// new hash. Edits are never committed automatically.
class KillaFilePage extends ConsumerStatefulWidget {
  const KillaFilePage({super.key, required this.path});

  final String path;

  @override
  ConsumerState<KillaFilePage> createState() => _KillaFilePageState();
}

class _KillaFilePageState extends ConsumerState<KillaFilePage> {
  final _editor = TextEditingController();
  final _commitMsg = TextEditingController();
  bool _editing = false;
  bool _source = false;
  bool _saving = false;
  bool _committing = false;
  bool _dirtySinceCommit = false;
  String? _lastHash;
  String? _original;

  @override
  void dispose() {
    _editor.dispose();
    _commitMsg.dispose();
    super.dispose();
  }

  bool get _changed =>
      _editing && _original != null && _editor.text != _original;

  void _startEdit(KillaFileContent f) {
    setState(() {
      _original = f.content;
      _editor.text = f.content;
      _editing = true;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    return showChunkyConfirm(
      context,
      title: 'Buang perubahan?',
      message: 'Perubahan yang belum disimpan akan hilang.',
      confirmLabel: 'Buang',
      destructive: true,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(saveKillaFileProvider)(widget.path, _editor.text);
      if (!mounted) return;
      ref.invalidate(killaFileProvider(widget.path));
      setState(() {
        _editing = false;
        _dirtySinceCommit = true;
        _original = null;
      });
      showOkToast(context, 'Tersimpan. Jangan lupa commit, ya 👍');
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commit() async {
    FocusScope.of(context).unfocus();
    setState(() => _committing = true);
    try {
      final hash = await ref.read(commitKillaWorkspaceProvider)(
        message: _commitMsg.text,
      );
      if (!mounted) return;
      setState(() {
        _lastHash = hash;
        _dirtySinceCommit = false;
      });
      _commitMsg.clear();
      if (hash == null) {
        showToastBadge(
          context,
          message: 'Nggak ada perubahan untuk di-commit',
          icon: Icons.info_rounded,
          color: GhinaColors.blue,
        );
      } else {
        HapticFeedback.mediumImpact();
        showOkToast(context, 'Commit ${_short(hash)} berhasil ✅');
        ref.invalidate(killaCommitsProvider);
      }
    } on KillaException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  static String _short(String h) => h.length > 7 ? h.substring(0, 7) : h;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(killaFileProvider(widget.path));
    final name = widget.path.split('/').last;
    final file = async.value;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _editing = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: g.background,
        appBar: AppBar(
          title: Text(name, overflow: TextOverflow.ellipsis),
          actions: [
            if (file != null && !_editing && file.isMarkdown)
              IconButton(
                tooltip: _source ? 'Tampilan' : 'Sumber',
                icon: Icon(
                  _source ? Icons.visibility_rounded : Icons.code_rounded,
                ),
                onPressed: () => setState(() => _source = !_source),
              ),
            if (file != null && !_editing)
              IconButton(
                tooltip: 'Salin isi',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: file.content));
                  showOkToast(context, 'Isi berkas disalin');
                },
              ),
            if (file != null && !_editing)
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => _startEdit(file),
              ),
            if (_editing)
              IconButton(
                tooltip: 'Batal',
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  if (await _confirmDiscard() && mounted) {
                    setState(() => _editing = false);
                  }
                },
              ),
          ],
        ),
        body: switch (async) {
          AsyncData(:final value) => _editing ? _editorView() : _view(value),
          AsyncError(:final error) => KillaErrorView(
            error: error,
            onRetry: () => ref.invalidate(killaFileProvider(widget.path)),
          ),
          _ => const LoadingListView(hero: false, tiles: 8),
        },
        bottomNavigationBar: file == null ? null : _bottomBar(),
      ),
    );
  }

  Widget _view(KillaFileContent f) {
    final g = context.ghina;
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(killaFileProvider(widget.path).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            f.path,
            style: GhinaType.caption.copyWith(
              color: g.textMuted,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          ChunkyCard(
            padding: const EdgeInsets.all(14),
            child: f.isMarkdown && !_source
                ? KillaMarkdown(text: f.content)
                : KillaMonospace(text: f.content),
          ),
        ],
      ),
    );
  }

  Widget _editorView() {
    final g = context.ghina;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        key: const ValueKey('killa-editor'),
        controller: _editor,
        expands: true,
        maxLines: null,
        minLines: null,
        autofocus: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        style: GhinaType.bodyS.copyWith(
          fontFamily: 'monospace',
          color: g.textPrimary,
          height: 1.45,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: g.surfaceAlt,
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: GhinaRadii.rLg,
            borderSide: BorderSide(color: g.border, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: GhinaRadii.rLg,
            borderSide: BorderSide(color: g.border, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: GhinaRadii.rLg,
            borderSide: BorderSide(color: killaSwatch.base, width: 2),
          ),
          helperText: '${_editor.text.length} / $killaFileMax karakter',
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final g = context.ghina;
    final pad = EdgeInsets.fromLTRB(
      GhinaSpace.page,
      10,
      GhinaSpace.page,
      10 + MediaQuery.paddingOf(context).bottom,
    );
    if (_editing) {
      return Container(
        padding: pad,
        decoration: BoxDecoration(
          color: g.background,
          border: Border(top: BorderSide(color: g.border, width: 2)),
        ),
        child: ChunkyButton(
          label: _changed ? 'Simpan' : 'Belum ada perubahan',
          icon: Icons.save_rounded,
          color: killaSwatch,
          loading: _saving,
          onPressed: _changed && !_saving ? _save : null,
        ),
      );
    }
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: g.background,
        border: Border(top: BorderSide(color: g.border, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_lastHash != null || _dirtySinceCommit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    _dirtySinceCommit
                        ? Icons.pending_rounded
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: _dirtySinceCommit
                        ? GhinaColors.orange.base
                        : GhinaColors.green.base,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _dirtySinceCommit
                          ? 'Ada perubahan yang belum di-commit'
                          : 'Commit terakhir: ${_short(_lastHash!)}',
                      style: GhinaType.caption
                          .w(700)
                          .copyWith(
                            color: g.textSecondary,
                            fontFamily: _dirtySinceCommit ? null : 'monospace',
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('killa-commit-msg'),
                  controller: _commitMsg,
                  maxLength: killaCommitMessageMax,
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Pesan commit (opsional)',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: g.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: GhinaRadii.rLg,
                      borderSide: BorderSide(color: g.border, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: GhinaRadii.rLg,
                      borderSide: BorderSide(color: g.border, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ChunkyButton(
                label: 'Commit',
                icon: Icons.commit_rounded,
                size: ChunkyButtonSize.medium,
                expand: false,
                color: killaSwatch,
                loading: _committing,
                onPressed: _committing ? null : _commit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
