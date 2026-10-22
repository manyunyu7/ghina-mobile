/// The signed-in user (`user` object of the auth endpoints).
final class AppUser {
  const AppUser({
    required this.id,
    this.name,
    this.email,
    this.image,
    required this.currency,
    required this.syncEpoch,
    this.foodCategoryIds,
  });

  final String id;
  final String? name;
  final String? email;
  final String? image;

  /// ISO code, e.g. `IDR`. Format money with this.
  final String currency;
  final String syncEpoch;

  /// "Kategori makanan" (`docs/food-transaction-link.md`): expense category ids
  /// picked by hand; null = automatic (by category name).
  final List<String>? foodCategoryIds;

  /// First name or email prefix, for greetings.
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n.split(RegExp(r'\s+')).first;
    final e = email;
    if (e != null && e.contains('@')) return e.split('@').first;
    return 'Kamu';
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.image == image &&
      other.currency == currency &&
      other.syncEpoch == syncEpoch &&
      _sameIds(other.foodCategoryIds, foodCategoryIds);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    email,
    image,
    currency,
    syncEpoch,
    foodCategoryIds == null ? null : Object.hashAll(foodCategoryIds!),
  );

  @override
  String toString() => 'AppUser($id, $email, $currency)';
}

bool _sameIds(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
