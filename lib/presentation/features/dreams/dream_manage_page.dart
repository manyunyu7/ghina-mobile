import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../design_system/design_system.dart';
import '../../shared/widgets/widgets.dart';
import 'dream_manage_logic.dart';
import 'dream_manage_sheets.dart';

/// `/dreams/manage`: categories and custom columns of Mimpi — add, rename,
/// reorder and delete. Deleting a category asks where its dreams go; deleting
/// a column warns how many dreams hold a value for it.
class DreamManagePage extends ConsumerWidget {
  const DreamManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final cats = ref.watch(watchDreamCategoriesProvider);
    final fields = ref.watch(watchDreamFieldsProvider);
    // Kept alive so the delete flows can count dreams with a plain read.
    ref.watch(watchDreamsProvider);
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
                'Belum ada kategori. Tambah sendiri: perjalanan, uang, '
                'rumah…',
              ),
              AsyncData(:final value) => _CategoryList(
                categories: value,
                onEdit: (c) => _editCategory(context, ref, c),
                onDelete: (c) => _deleteCategory(context, ref, c, value),
              ),
              AsyncError() => ErrorRetry(
                onRetry: () => ref.invalidate(watchDreamCategoriesProvider),
              ),
              _ => const SkeletonList(count: 3),
            },
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Kolom khusus',
              subtitle: 'Muncul di form mimpi sesuai kategorinya',
              trailing: IconButton(
                key: const ValueKey('add-field'),
                tooltip: 'Kolom baru',
                icon: const Icon(Icons.add_circle_rounded),
                onPressed: () =>
                    _editField(context, ref, null, cats.value ?? const []),
              ),
            ),
            switch (fields) {
              AsyncData(:final value) when value.isEmpty => _hint(
                context,
                'Belum ada kolom. Buat sendiri: anggaran, lokasi, '
                'tautan referensi…',
              ),
              AsyncData(:final value) => _FieldList(
                defs: value,
                categories: cats.value ?? const [],
                onEdit: (d) =>
                    _editField(context, ref, d, cats.value ?? const []),
                onDelete: (d) => _deleteField(context, ref, d),
              ),
              AsyncError() => ErrorRetry(
                onRetry: () => ref.invalidate(watchDreamFieldsProvider),
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
    DreamCategory? c,
  ) async {
    final r = await showChunkyBottomSheet<({String label, String emoji})>(
      context,
      title: c == null ? 'Kategori baru' : 'Ubah kategori',
      showClose: true,
      builder: (_) => DreamCategorySheet(category: c),
    );
    if (r == null || !context.mounted) return;
    final res = c == null
        ? await ref.read(createDreamCategoryProvider)(
            label: r.label,
            emoji: r.emoji,
          )
        : await ref.read(updateDreamCategoryProvider)(
            id: c.id,
            label: r.label,
            emoji: r.emoji,
          );
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }

  /// Asks where the dreams go, moves each one, then deletes the category. A
  /// failed move stops before the delete, so no dream is left in a category
  /// that is gone.
  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    DreamCategory c,
    List<DreamCategory> all,
  ) async {
    final dreams = dreamsInCategory(
      ref.read(watchDreamsProvider).value ?? const <Dream>[],
      c.key,
    );
    String? target;
    if (dreams.isEmpty) {
      final ok = await showChunkyConfirm(
        context,
        title: 'Hapus kategori?',
        message: '"${c.emoji} ${c.label}" belum punya mimpi, jadi aman.',
        confirmLabel: 'Hapus kategori',
        destructive: true,
      );
      if (!ok) return;
    } else {
      target = await showChunkyDialog<String>(
        context,
        builder: (_) => DreamMoveDialog(
          category: c,
          count: dreams.length,
          targets: moveTargets(all, c.key),
        ),
      );
      if (target == null) return;
    }
    if (!context.mounted) return;
    for (final d in dreams) {
      final r = await ref.read(moveDreamCategoryProvider)(d.id, target!);
      if (!context.mounted) return;
      if (r case Err(:final failure)) {
        showFailureToast(context, failure);
        return;
      }
    }
    final res = await ref.read(deleteDreamCategoryProvider)(c.id);
    if (!context.mounted) return;
    switch (res) {
      case Err(:final failure):
        showFailureToast(context, failure);
      default:
        showOkToast(
          context,
          dreams.isEmpty
              ? 'Kategori dihapus'
              : 'Kategori dihapus, ${dreams.length} mimpi dipindah',
        );
    }
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    DreamFieldDef? d,
    List<DreamCategory> categories,
  ) async {
    final r = await showChunkyBottomSheet<DreamFieldSheetResult>(
      context,
      title: d == null ? 'Kolom baru' : 'Ubah kolom',
      showClose: true,
      builder: (_) => DreamFieldSheet(def: d, categories: categories),
    );
    if (r == null || !context.mounted) return;
    final res = d == null
        ? await ref.read(createDreamFieldProvider)(
            label: r.label,
            type: r.type,
            options: r.type == DreamFieldType.select ? r.options : null,
            appliesTo: r.appliesTo,
            showInList: r.showInList,
          )
        : await ref.read(updateDreamFieldProvider)(
            id: d.id,
            label: r.label,
            appliesTo: r.appliesTo,
            showInList: r.showInList,
          );
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }

  Future<void> _deleteField(
    BuildContext context,
    WidgetRef ref,
    DreamFieldDef d,
  ) async {
    final n = dreamsWithFieldCount(
      ref.read(watchDreamsProvider).value ?? const <Dream>[],
      d.key,
    );
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus kolom "${d.label}"?',
      message: n == 0
          ? 'Belum ada mimpi yang mengisi kolom ini.'
          : '$n mimpi punya isi di kolom ini dan isinya akan ikut hilang. '
                'Ini tidak bisa dibatalkan.',
      confirmLabel: 'Hapus kolom',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final res = await ref.read(deleteDreamFieldProvider)(d.id);
    if (!context.mounted) return;
    if (res case Err(:final failure)) showFailureToast(context, failure);
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({
    required this.categories,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DreamCategory> categories;
  final ValueChanged<DreamCategory> onEdit;
  final ValueChanged<DreamCategory> onDelete;

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
        final r = await ref.read(reorderDreamCategoriesProvider)(ids);
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canDeleteCategory(c))
                  IconButton(
                    key: ValueKey('cat-delete-${c.id}'),
                    tooltip: 'Hapus kategori',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: g.textMuted,
                    ),
                    onPressed: () => onDelete(c),
                  ),
                Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
              ],
            ),
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
    required this.onDelete,
  });

  final List<DreamFieldDef> defs;
  final List<DreamCategory> categories;
  final ValueChanged<DreamFieldDef> onEdit;
  final ValueChanged<DreamFieldDef> onDelete;

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
        final r = await ref.read(reorderDreamFieldsProvider)(ids);
        if (!context.mounted) return;
        if (r case Err(:final failure)) showFailureToast(context, failure);
      },
      itemBuilder: (_, i) {
        final d = defs[i];
        return Padding(
          key: ValueKey('def-${d.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            dense: true,
            leading: Icon(Icons.view_column_rounded, color: g.textSecondary),
            title: d.label,
            subtitle: '${d.type.label} · ${fieldScopeText(d, categories)}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('def-delete-${d.id}'),
                  tooltip: 'Hapus kolom',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: g.textMuted,
                  ),
                  onPressed: () => onDelete(d),
                ),
                Icon(Icons.edit_rounded, size: 18, color: g.textMuted),
              ],
            ),
            onTap: () => onEdit(d),
          ),
        );
      },
    );
  }
}
