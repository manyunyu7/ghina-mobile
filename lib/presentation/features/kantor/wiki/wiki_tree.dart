/// Page tree math, same rules as the web sidebar: a page whose parent is
/// unknown sits at the top, siblings sort by `ord`, "beranda" first, then
/// title.
class WikiTree {
  WikiTree(List<dynamic> raw)
    : pages = [
        for (final p in raw)
          if (p is Map) Map<String, dynamic>.from(p),
      ] {
    _slugs = {for (final p in pages) p['slug'] as String};
    for (final p in pages) {
      final parent = p['parent'] as String?;
      final key = parent != null && _slugs.contains(parent) ? parent : '';
      (_kids[key] ??= []).add(p);
    }
    for (final l in _kids.values) {
      l.sort((a, b) {
        final o = ((a['ord'] as num?) ?? 0).compareTo((b['ord'] as num?) ?? 0);
        if (o != 0) return o;
        if (a['slug'] == 'beranda') return -1;
        if (b['slug'] == 'beranda') return 1;
        return (a['title'] as String).toLowerCase().compareTo(
          (b['title'] as String).toLowerCase(),
        );
      });
    }
  }

  final List<Map<String, dynamic>> pages;
  late final Set<String> _slugs;
  final Map<String, List<Map<String, dynamic>>> _kids = {};

  Map<String, dynamic>? byId(String? slug) {
    for (final p in pages) {
      if (p['slug'] == slug) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> kids(String parent) => _kids[parent] ?? const [];

  bool hasKids(String slug) => kids(slug).isNotEmpty;

  /// Is [slug] somewhere below [ancestor]?
  bool isDescendant(String slug, String ancestor) {
    var c = byId(slug);
    for (var i = 0; c != null && i < 100; i++) {
      final p = c['parent'] as String?;
      if (p == ancestor) return true;
      c = byId(p);
    }
    return false;
  }

  Map<String, dynamic>? find(String title) {
    final l = title.toLowerCase();
    for (final p in pages) {
      if ((p['title'] as String).toLowerCase() == l) return p;
    }
    return null;
  }

  /// Visible rows for the sidebar: (page, depth).
  List<(Map<String, dynamic>, int)> flatten(Set<String> open) {
    final out = <(Map<String, dynamic>, int)>[];
    void walk(String parent, int depth) {
      for (final p in kids(parent)) {
        out.add((p, depth));
        if (open.contains(p['slug'])) walk(p['slug'] as String, depth + 1);
      }
    }

    walk('', 0);
    return out;
  }

  /// Every page that can become the parent of [slug] (not itself or below),
  /// in tree order with depth, for the move dialog.
  List<(Map<String, dynamic>, int)> parentChoices(String slug) {
    final out = <(Map<String, dynamic>, int)>[];
    void walk(String parent, int depth) {
      for (final p in kids(parent)) {
        final s = p['slug'] as String;
        if (s == slug || isDescendant(s, slug)) continue;
        out.add((p, depth));
        walk(s, depth + 1);
      }
    }

    walk('', 0);
    return out;
  }
}
