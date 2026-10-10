/// Pure parts of the Mimpi manage screen (no Flutter).
library;

import '../../../domain/entities/entities.dart';

/// Options typed as one text: split on commas and new lines, trimmed, empty
/// pieces dropped. The domain validates count and length.
List<String> parseFieldOptions(String text) => [
  for (final p in text.split(RegExp(r'[,\n]')))
    if (p.trim().isNotEmpty) p.trim(),
];

/// "semua kategori", or the labels of the categories a field applies to (an
/// unknown key reads as itself).
String fieldScopeText(DreamFieldDef d, List<DreamCategory> categories) {
  final keys = d.appliesTo;
  if (keys == null || keys.isEmpty) return 'semua kategori';
  return keys
      .map(
        (k) =>
            categories
                .where((c) => c.key == k)
                .map((c) => c.label)
                .firstOrNull ??
            k,
      )
      .join(', ');
}

/// Dreams in the category [key].
List<Dream> dreamsInCategory(Iterable<Dream> dreams, String key) => [
  for (final d in dreams)
    if (d.category == key) d,
];

/// Dreams that hold a value under the custom-field [key].
int dreamsWithFieldCount(Iterable<Dream> dreams, String key) =>
    dreams.where((d) => d.fields.containsKey(key)).length;

/// Where the dreams of a deleted category can go: every other category, plus
/// the built-in `other` when it has no row of its own.
List<({String key, String label})> moveTargets(
  List<DreamCategory> categories,
  String deletedKey,
) => [
  for (final c in categories)
    if (c.key != deletedKey) (key: c.key, label: '${c.emoji} ${c.label}'),
  if (deletedKey != 'other' && !categories.any((c) => c.key == 'other'))
    (key: 'other', label: '✨ Lainnya'),
];

/// Whether the category can be deleted (the built-in `other` cannot).
bool canDeleteCategory(DreamCategory c) => c.key != 'other';
