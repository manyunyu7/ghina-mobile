import 'enums.dart';

/// A logged meal/food item.
final class FoodLog {
  const FoodLog({
    required this.id,
    required this.date,
    required this.name,
    this.meal,
    this.mealLabel,
    this.calories,
    this.caloriesMax,
    this.tags = const [],
    this.photoUrl,
    this.localPhotoPath,
    this.note,
    this.transactionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final String name;
  final MealType? meal;

  /// A free-text meal label (≤ 24) that isn't one of the canonical [MealType]s
  /// (`docs/habits-food-enrichment.md`: "makan malam", "brunch"…). [meal] is
  /// null then. Kept so a sync round trip never drops it.
  final String? mealLabel;

  /// The lower bound — or the point value when [caloriesMax] is null.
  final int? calories;

  /// Upper bound of a range (≥ [calories], needs it); null = not a range.
  final int? caloriesMax;

  /// ≤ 10 tags of ≤ 30 characters.
  final List<String> tags;

  /// What the meal is called: the canonical label, else the free text.
  String? get mealText => meal?.label ?? mealLabel;

  /// Server path such as `/uploads/abc.jpg` (resolve with `AppConfig.resolveUrl`).
  final String? photoUrl;

  /// Local file of a photo taken offline and not uploaded yet. Prefer it over
  /// [photoUrl] for display when non-null.
  final String? localPhotoPath;
  final String? note;

  /// The expense this meal was paid with (`docs/food-transaction-link.md`);
  /// several food logs may share one. Null = not linked.
  final String? transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasPhoto => photoUrl != null || localPhotoPath != null;

  bool get isLinked => transactionId != null;

  /// The same log linked to [transactionId] (null = unlinked), edited at [at].
  FoodLog withTransaction(String? transactionId, DateTime at) => FoodLog(
    id: id,
    date: date,
    name: name,
    meal: meal,
    mealLabel: mealLabel,
    calories: calories,
    caloriesMax: caloriesMax,
    tags: tags,
    photoUrl: photoUrl,
    localPhotoPath: localPhotoPath,
    note: note,
    transactionId: transactionId,
    createdAt: createdAt,
    updatedAt: at,
  );

  @override
  bool operator ==(Object other) =>
      other is FoodLog &&
      other.id == id &&
      other.date == date &&
      other.name == name &&
      other.meal == meal &&
      other.mealLabel == mealLabel &&
      other.calories == calories &&
      other.caloriesMax == caloriesMax &&
      _listEq(other.tags, tags) &&
      other.photoUrl == photoUrl &&
      other.localPhotoPath == localPhotoPath &&
      other.note == note &&
      other.transactionId == transactionId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    date,
    name,
    meal,
    mealLabel,
    calories,
    caloriesMax,
    Object.hashAll(tags),
    photoUrl,
    localPhotoPath,
    note,
    transactionId,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'FoodLog($id, $name)';
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
