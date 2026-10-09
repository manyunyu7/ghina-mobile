import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/people_widgets.dart' show SwitchRow;
import '../widgets/person_form_sheets.dart';

/// `/people/manage`: categories and custom fields — list, add, rename,
/// reorder. No delete or retype (those are destructive; use the web).
class PeopleManagePage extends ConsumerWidget {
  const PeopleManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final cats = ref.watch(watchPersonCategoriesProvider);
    final fields = ref.watch(watchPersonFieldsProvider);
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(title: const Text('Kategori & kolom')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            32,
          ),
          children: [
            SectionHeader(
              title: 'Kategori',
              subtitle: 'Tahan dan geser untuk mengurutkan',
              trailing: IconButton(
                key: const ValueKey('add-category'),
                tooltip: 'Kategori baru',
                icon: const Icon(Icons.add_circle_rounded),
                onPressed: () => _editCategory(context, ref, null),
              ),
            ),
            switch (cats) {
              AsyncData(:final value) when value.isEmpty => _hint(
                context,
                'Kategori standar muncul setelah sinkronisasi pertama.',
              ),
              AsyncData(:final value) => _CategoryList(
                categories: value,
                onEdit: (c) => _editCategory(context, ref, c),
              ),
              AsyncError() => ErrorRetry(
                onRetry: () => ref.invalidate(watchPersonCategoriesProvider),
              ),
              _ => const SkeletonList(count: 3),
            },
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Kolom khusus',
              subtitle: 'Muncul di form orang sesuai kategorinya',
              trailing: IconButton(
                key: const ValueKey('add-field-manage'),
                tooltip: 'Kolom baru',
                icon: const Icon(Icons.add_circle_rounded),
                onPressed: () => showAddFieldSheet(context),
              ),
            ),
            switch (fields) {
              AsyncData(:final value) when value.isEmpty => _hint(
                context,
                'Belum ada kolom. Buat sendiri: ukuran sepatu, hobi, '
                'golongan darah…',
              ),
              AsyncData(:final value) => _FieldList(
                defs: value,
                categories: cats.value ?? const [],
                onEdit: (d) => _editField(context, ref, d),
              ),
              AsyncError() => ErrorRetry(
                onRetry: () => ref.invalidate(watchPersonFieldsProvider),
              ),
              _ => const SkeletonList(count: 3),
            },
          ],
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: GhinaType.body.copyWith(color: context.ghina.textSecondary),
  );

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    PersonCategory? c,
  ) async {
    final r = await showChunkyBottomSheet<({String label, String emoji})>(
      context,
      title: c == null ? 'Kategori baru' : 'Ubah kategori',
      showClose: true,
      builder: (_) => _CategorySheet(category: c),
    );
    if (r == null || !context.mounted) return;
    final res = c == null
        ? await ref.read(createPersonCategoryProvider)(
            label: r.label,
            emoji: r.emoji,
          )
        : await ref.read(updatePersonCategoryProvider)(
            c.id,
            label: r.label,
            emoji: r.emoji,
          );
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    PersonFieldDef d,
  ) async {
    final r = await showChunkyBottomSheet<({String label, bool showInList})>(
      context,
      title: 'Ubah kolom',
      showClose: true,
      builder: (_) => _FieldSheet(def: d),
    );
    if (r == null || !context.mounted) return;
    final res = await ref.read(updatePersonFieldProvider)(
      d.id,
      label: r.label,
      showInList: r.showInList,
    );
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }
}

/// Add / rename a category: emoji + label. The sheet owns its controllers (it
/// is still built while it animates away).
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.category});

  final PersonCategory? category;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final _label = TextEditingController(text: widget.category?.label);
  late final _emoji = TextEditingController(
    text: widget.category?.emoji ?? '👤',
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
            maxLength: personCategoryEmojiMax,
          ),
          const SizedBox(height: 12),
          ChunkyTextField(
            key: const ValueKey('category-label'),
            label: 'Nama',
            controller: _label,
            maxLength: personCategoryLabelMax,
            autofocus: true,
          ),
          if (c != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Kunci "${c.key}" tidak berubah, jadi orang di kategori ini '
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

/// Rename a field / toggle "Tampilkan di daftar". Type, options and key stay.
class _FieldSheet extends StatefulWidget {
  const _FieldSheet({required this.def});

  final PersonFieldDef def;

  @override
  State<_FieldSheet> createState() => _FieldSheetState();
}

class _FieldSheetState extends State<_FieldSheet> {
  late final _label = TextEditingController(text: widget.def.label);
  late bool _showInList = widget.def.showInList;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChunkyTextField(
            key: const ValueKey('field-rename'),
            label: 'Nama kolom',
            controller: _label,
            maxLength: fieldLabelMax,
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Jenis: ${d.type.label}. Jenis dan kunci ("${d.key}") tidak bisa '
            'diubah di sini supaya isi yang sudah ada aman.',
            style: GhinaType.caption.copyWith(
              color: context.ghina.textSecondary,
            ),
          ),
          SwitchRow(
            title: 'Tampilkan di daftar',
            value: _showInList,
            onChanged: (v) => setState(() => _showInList = v),
          ),
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('field-rename-save'),
            label: 'Simpan',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(
              context,
            ).pop((label: _label.text, showInList: _showInList)),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories, required this.onEdit});

  final List<PersonCategory> categories;
  final ValueChanged<PersonCategory> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return ReorderableListView.builder(
      key: const ValueKey('category-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      onReorderItem: (from, to) async {
        final ids = [for (final c in categories) c.id];
        final id = ids.removeAt(from);
        ids.insert(to, id);
        final r = await ref.read(reorderPersonCategoriesProvider)(ids);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureToast(context, failure);
      },
      itemBuilder: (_, i) {
        final c = categories[i];
        return Padding(
          key: ValueKey('cat-${c.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            dense: true,
            leading: Text(c.emoji, style: const TextStyle(fontSize: 22)),
            title: c.label,
            subtitle: c.key,
            trailing: Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
            onTap: () => onEdit(c),
          ),
        );
      },
    );
  }
}

class _FieldList extends ConsumerWidget {
  const _FieldList({
    required this.defs,
    required this.categories,
    required this.onEdit,
  });

  final List<PersonFieldDef> defs;
  final List<PersonCategory> categories;
  final ValueChanged<PersonFieldDef> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return ReorderableListView.builder(
      key: const ValueKey('field-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: defs.length,
      onReorderItem: (from, to) async {
        final ids = [for (final d in defs) d.id];
        final id = ids.removeAt(from);
        ids.insert(to, id);
        final r = await ref.read(reorderPersonFieldsProvider)(ids);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureToast(context, failure);
      },
      itemBuilder: (_, i) {
        final d = defs[i];
        final scope = d.appliesTo == null || d.appliesTo!.isEmpty
            ? 'semua kategori'
            : d.appliesTo!
                  .map(
                    (k) =>
                        categories
                            .where((c) => c.key == k)
                            .firstOrNull
                            ?.label ??
                        k,
                  )
                  .join(', ');
        return Padding(
          key: ValueKey('def-${d.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            dense: true,
            leading: Icon(Icons.view_column_rounded, color: g.textSecondary),
            title: d.label,
            subtitle: '${d.type.label} · $scope',
            trailing: Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
            onTap: () => onEdit(d),
          ),
        );
      },
    );
  }
}
