import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../notes/widgets/note_markdown.dart';

/// The markdown notes of a person — **online-only**: fetched with
/// `GET /api/mobile/people/{id}`, never stored on the device.
///
/// A `sensitive` person's notes stay collapsed behind "Tampilkan catatan
/// sensitif" and are fetched only on tap (and dropped from memory again on
/// "Sembunyikan"). Edit uses `PUT …/notes` with `expectedUpdatedAt`; "Tambah
/// catatan" uses the append endpoint.
class PersonNotesSection extends ConsumerStatefulWidget {
  const PersonNotesSection({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<PersonNotesSection> createState() => _PersonNotesSectionState();
}

class _PersonNotesSectionState extends ConsumerState<PersonNotesSection> {
  PersonNotes? _notes;
  bool _loading = false;
  Failure? _error;

  Person get _p => widget.person;

  @override
  void initState() {
    super.initState();
    if (!_p.sensitive && _p.hasNotes) _load();
  }

  @override
  void didUpdateWidget(PersonNotesSection old) {
    super.didUpdateWidget(old);
    // The mirror flips after the first notes write syncs; a person that just
    // became non-sensitive loads too. A sensitive one never loads by itself.
    if (!_p.sensitive && _p.hasNotes && _notes == null && !_loading) _load();
    if (_p.sensitive && !old.person.sensitive) {
      setState(() => _notes = null); // drop it from memory
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref.read(getPersonNotesProvider)(_p.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (r) {
        case Ok(:final value):
          _notes = value;
        case Err(:final failure):
          _error = failure;
      }
    });
  }

  Future<void> _edit() async {
    final current = _notes;
    if (current == null) return;
    final saved = await Navigator.of(context).push<PersonNotes>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PersonNotesEditorPage(person: _p, initial: current),
      ),
    );
    if (saved != null && mounted) setState(() => _notes = saved);
  }

  Future<void> _append() async {
    final done = await showChunkyBottomSheet<bool>(
      context,
      title: 'Tambah catatan',
      showClose: true,
      builder: (c) => _AppendSheet(personId: _p.id),
    );
    if (done == true && mounted && (_notes != null || !_p.sensitive)) {
      await _load();
    } else if (done == true && mounted) {
      showOkToast(context, 'Catatan ditambahkan');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final hidden = _p.sensitive && _notes == null && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Catatan',
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          trailing: _p.sensitive
              ? ChunkyPill(
                  label: 'Sensitif',
                  icon: Icons.lock_rounded,
                  color: GhinaColors.orange,
                  soft: true,
                )
              : null,
        ),
        if (_loading)
          const SkeletonList(count: 2)
        else if (_error != null)
          ChunkyCard(
            tinted: GhinaColors.orange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error is NetworkFailure
                      ? 'Catatan cuma bisa dibuka saat online.'
                      : _error!.message,
                  style: GhinaType.body.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 10),
                ChunkyButton(
                  key: const ValueKey('notes-retry'),
                  label: 'Coba lagi',
                  size: ChunkyButtonSize.small,
                  expand: false,
                  icon: Icons.refresh_rounded,
                  onPressed: _load,
                ),
              ],
            ),
          )
        else if (hidden && _p.hasNotes)
          ChunkyCard(
            key: const ValueKey('notes-hidden'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_rounded, color: g.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Catatan disembunyikan (${_p.notesLength} karakter). '
                        'Baru diambil dari server saat kamu menampilkannya.',
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ChunkyButton(
                  key: const ValueKey('show-sensitive-notes'),
                  label: 'Tampilkan catatan sensitif',
                  variant: ChunkyButtonVariant.outline,
                  size: ChunkyButtonSize.medium,
                  icon: Icons.visibility_rounded,
                  uppercase: false,
                  onPressed: _load,
                ),
              ],
            ),
          )
        else if (_notes != null && _notes!.notes.trim().isNotEmpty)
          ChunkyCard(
            key: const ValueKey('notes-body'),
            child: NoteMarkdown(data: _notes!.notes),
          )
        else
          Text(
            'Belum ada catatan.',
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_notes != null)
              ChunkyButton(
                key: const ValueKey('notes-edit'),
                label: 'Ubah catatan',
                size: ChunkyButtonSize.small,
                expand: false,
                variant: ChunkyButtonVariant.outline,
                icon: Icons.edit_rounded,
                onPressed: _edit,
              ),
            ChunkyButton(
              key: const ValueKey('notes-append'),
              label: 'Tambah catatan',
              size: ChunkyButtonSize.small,
              expand: false,
              variant: ChunkyButtonVariant.outline,
              icon: Icons.add_rounded,
              onPressed: _append,
            ),
            if (_p.sensitive && _notes != null)
              ChunkyButton(
                key: const ValueKey('notes-hide'),
                label: 'Sembunyikan',
                size: ChunkyButtonSize.small,
                expand: false,
                variant: ChunkyButtonVariant.ghost,
                icon: Icons.visibility_off_rounded,
                onPressed: () => setState(() => _notes = null),
              ),
          ],
        ),
      ],
    );
  }
}

/// Full-screen editor of the notes. Saves with the `updatedAt` it read; when
/// the notes changed elsewhere meanwhile it says so and offers the latest.
class PersonNotesEditorPage extends ConsumerStatefulWidget {
  const PersonNotesEditorPage({
    super.key,
    required this.person,
    required this.initial,
  });

  final Person person;
  final PersonNotes initial;

  @override
  ConsumerState<PersonNotesEditorPage> createState() =>
      _PersonNotesEditorPageState();
}

class _PersonNotesEditorPageState extends ConsumerState<PersonNotesEditorPage> {
  late final _text = TextEditingController(text: widget.initial.notes);
  late DateTime _expected = widget.initial.updatedAt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(replacePersonNotesProvider)(
      widget.person.id,
      _text.text,
      expectedUpdatedAt: _expected,
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        showOkToast(context, 'Catatan tersimpan 👍');
        Navigator.of(
          context,
        ).pop(PersonNotes(notes: _text.text, updatedAt: value.updatedAt));
      case Err(:final failure):
        setState(() => _saving = false);
        if (failure is ConflictFailure) {
          await _conflict(failure);
        } else {
          setState(() => _error = failure.message);
        }
    }
  }

  Future<void> _conflict(ConflictFailure f) async {
    final reload = await showChunkyConfirm(
      context,
      title: 'Catatan berubah di tempat lain',
      message:
          '${f.message}\n\nTeksmu akan disalin ke clipboard dulu, lalu '
          'versi terbaru dimuat.',
      confirmLabel: 'Muat versi terbaru',
      cancelLabel: 'Tetap di sini',
    );
    if (!reload || !mounted) return;
    // Fire and forget: the user's unsaved text is only a courtesy copy.
    unawaited(Clipboard.setData(ClipboardData(text: _text.text)));
    final fresh = await ref.read(getPersonNotesProvider)(widget.person.id);
    if (!mounted) return;
    switch (fresh) {
      case Ok(:final value):
        setState(() {
          _text.text = value.notes;
          _expected = value.updatedAt;
        });
        showOkToast(context, 'Versi terbaru dimuat. Teksmu ada di clipboard.');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text('Catatan · ${widget.person.name}'),
        actions: [
          TextButton(
            key: const ValueKey('notes-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(GhinaSpace.page),
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
                ),
              ),
            Expanded(
              child: TextField(
                key: const ValueKey('notes-field'),
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: GhinaType.bodyL.copyWith(color: g.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Tulis catatan (Markdown)…',
                  filled: true,
                  fillColor: g.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: GhinaRadii.rLg,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppendSheet extends ConsumerStatefulWidget {
  const _AppendSheet({required this.personId});
  final String personId;

  @override
  ConsumerState<_AppendSheet> createState() => _AppendSheetState();
}

class _AppendSheetState extends ConsumerState<_AppendSheet> {
  final _heading = TextEditingController();
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _heading.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(appendPersonNotesProvider)(
      widget.personId,
      _text.text,
      heading: _heading.text,
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _saving = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('append-heading'),
          label: 'Judul (opsional)',
          hint: 'mis. 2026-10-10',
          controller: _heading,
          maxLength: 80,
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const ValueKey('append-text'),
          label: 'Catatan',
          hint: 'Tambahan baru…',
          controller: _text,
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          errorText: _error,
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          key: const ValueKey('append-save'),
          label: 'Tambahkan',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
  );
}
