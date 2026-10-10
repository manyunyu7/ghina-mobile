import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../people/widgets/people_widgets.dart' show SwitchRow;
import 'dream_manage_logic.dart';

/// Add / rename a category: emoji + label. The sheet owns its controllers (it
/// is still built while it animates away).
class DreamCategorySheet extends StatefulWidget {
  const DreamCategorySheet({super.key, required this.category});

  final DreamCategory? category;

  @override
  State<DreamCategorySheet> createState() => _DreamCategorySheetState();
}

class _DreamCategorySheetState extends State<DreamCategorySheet> {
  late final _label = TextEditingController(text: widget.category?.label);
  late final _emoji = TextEditingController(
    text: widget.category?.emoji ?? '🌟',
  );

  @override
  void dispose() {
    _label.dispose();
    _emoji.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyTextField(
            key: const ValueKey('category-emoji'),
            label: 'Emoji',
            controller: _emoji,
            maxLength: dreamCategoryEmojiMax,
          ),
          const SizedBox(height: 12),
          ChunkyTextField(
            key: const ValueKey('category-label'),
            label: 'Nama',
            controller: _label,
            maxLength: dreamCategoryLabelMax,
            autofocus: true,
          ),
          if (c != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Kunci "${c.key}" tidak berubah, jadi mimpi di kategori ini '
                'tetap terhubung.',
                style: GhinaType.caption.copyWith(
                  color: context.ghina.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 16),
          ChunkyButton(
            key: const ValueKey('category-save'),
            label: 'Simpan',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(
              context,
            ).pop((label: _label.text, emoji: _emoji.text)),
          ),
        ],
      ),
    );
  }
}

/// What the field sheet returns.
typedef DreamFieldSheetResult = ({
  String label,
  DreamFieldType type,
  List<String> options,
  List<String> appliesTo,
  bool showInList,
});

/// Add (def == null) or edit a custom column. On edit the type, options and
/// key stay; only the label, scope and "tampilkan di daftar" change.
class DreamFieldSheet extends StatefulWidget {
  const DreamFieldSheet({
    super.key,
    required this.def,
    required this.categories,
  });

  final DreamFieldDef? def;
  final List<DreamCategory> categories;

  @override
  State<DreamFieldSheet> createState() => _DreamFieldSheetState();
}

class _DreamFieldSheetState extends State<DreamFieldSheet> {
  late final _label = TextEditingController(text: widget.def?.label);
  late final _options = TextEditingController(
    text: widget.def?.options?.join(', '),
  );
  late DreamFieldType _type = widget.def?.type ?? DreamFieldType.text;
  late Set<String> _applies = {...?widget.def?.appliesTo};
  late bool _showInList = widget.def?.showInList ?? false;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final d = widget.def;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChunkyTextField(
              key: const ValueKey('field-label'),
              label: 'Nama kolom',
              controller: _label,
              maxLength: dreamFieldLabelMax,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            if (d == null) ...[
              Text(
                'Jenis',
                style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
              ),
              const SizedBox(height: 6),
              ChunkyChoiceChips<DreamFieldType>(
                key: const ValueKey('field-type'),
                options: [
                  for (final t in DreamFieldType.values)
                    ChunkyChoice(value: t, label: t.label),
                ],
                selected: {_type},
                onChanged: (s) => setState(() => _type = s.first),
              ),
              if (_type == DreamFieldType.select) ...[
                const SizedBox(height: 12),
                ChunkyTextField(
                  key: const ValueKey('field-options'),
                  label: 'Pilihan',
                  hint: 'Pisahkan dengan koma atau baris baru',
                  controller: _options,
                  maxLines: 3,
                ),
              ],
            ] else
              Text(
                'Jenis: ${d.type.label}. Jenis dan kunci ("${d.key}") tidak '
                'bisa diubah supaya isi yang sudah ada aman.',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
            const SizedBox(height: 12),
            Text(
              'Berlaku untuk',
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
            const SizedBox(height: 6),
            ChunkyChoiceChips<String>(
              key: const ValueKey('field-applies'),
              multi: true,
              allowEmpty: true,
              options: [
                for (final c in widget.categories)
                  ChunkyChoice(value: c.key, label: '${c.emoji} ${c.label}'),
              ],
              selected: _applies,
              onChanged: (s) => setState(() => _applies = s),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _applies.isEmpty
                    ? 'Kosong berarti semua kategori.'
                    : 'Hanya kategori yang dipilih.',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
            SwitchRow(
              title: 'Tampilkan di daftar',
              value: _showInList,
              onChanged: (v) => setState(() => _showInList = v),
            ),
            const SizedBox(height: 8),
            ChunkyButton(
              key: const ValueKey('field-save'),
              label: 'Simpan',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop((
                label: _label.text,
                type: _type,
                options: parseFieldOptions(_options.text),
                appliesTo: [
                  for (final c in widget.categories)
                    if (_applies.contains(c.key)) c.key,
                ],
                showInList: _showInList,
              )),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Hapus kategori?" with a choice of where its dreams go. Pops the target
/// category key, or null on cancel.
class DreamMoveDialog extends StatefulWidget {
  const DreamMoveDialog({
    super.key,
    required this.category,
    required this.count,
    required this.targets,
  });

  final DreamCategory category;
  final int count;
  final List<({String key, String label})> targets;

  @override
  State<DreamMoveDialog> createState() => _DreamMoveDialogState();
}

class _DreamMoveDialogState extends State<DreamMoveDialog> {
  late String _target = widget.targets.any((t) => t.key == 'other')
      ? 'other'
      : widget.targets.first.key;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return ChunkyDialog(
      title: 'Hapus kategori?',
      mood: MascotMood.sad,
      message:
          '${widget.count} mimpi di "${c.emoji} ${c.label}" akan dipindah. '
          'Pilih tujuannya:',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in widget.targets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ChunkyTile(
                key: ValueKey('move-to-${t.key}'),
                dense: true,
                title: t.label,
                tinted: t.key == _target ? GhinaColors.blue : null,
                trailing: t.key == _target
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => setState(() => _target = t.key),
              ),
            ),
        ],
      ),
      actions: [
        ChunkyButton(
          key: const ValueKey('move-confirm'),
          label: 'Pindahkan & hapus',
          variant: ChunkyButtonVariant.danger,
          onPressed: () => Navigator.of(context).pop(_target),
        ),
        ChunkyButton(
          key: const ValueKey('move-cancel'),
          label: 'Batal',
          variant: ChunkyButtonVariant.ghost,
          color: GhinaColors.blue,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
