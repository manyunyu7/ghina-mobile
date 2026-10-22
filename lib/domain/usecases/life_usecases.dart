/// Health and food log use cases (prayers: `prayer_usecases.dart`).
library;

import '../../core/clock.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'validation.dart';

// ---------------------------------------------------------------- health

final class HealthInput {
  const HealthInput({
    required this.date,
    this.weight,
    this.systolic,
    this.diastolic,
    this.pulse,
    this.note,
  });

  final DateTime date;
  final double? weight;
  final int? systolic;
  final int? diastolic;
  final int? pulse;
  final String? note;
}

/// Web `health/actions.ts` parse rules.
void validateHealth(HealthInput i) {
  final w = i.weight, s = i.systolic, d = i.diastolic, p = i.pulse;
  if (w != null && (!w.isFinite || w < 1 || w > 500)) {
    throw const ValidationFailure(
      'Berat badan sepertinya salah (1–500 kg)',
      field: 'weight',
    );
  }
  if (s != null && (s < 50 || s > 300)) {
    throw const ValidationFailure(
      'Sistolik sepertinya salah (50–300)',
      field: 'systolic',
    );
  }
  if (d != null && (d < 30 || d > 200)) {
    throw const ValidationFailure(
      'Diastolik sepertinya salah (30–200)',
      field: 'diastolic',
    );
  }
  if (p != null && (p < 20 || p > 250)) {
    throw const ValidationFailure(
      'Denyut nadi sepertinya salah (20–250)',
      field: 'pulse',
    );
  }
  if ((s != null) != (d != null)) {
    throw const ValidationFailure(
      'Isi sistolik dan diastolik untuk tekanan darah',
      field: 'systolic',
    );
  }
  if (w == null && s == null && p == null) {
    throw const ValidationFailure('Isi minimal satu pengukuran');
  }
}

HealthEntry _health(
  String id,
  HealthInput i,
  DateTime createdAt,
  DateTime now,
) {
  validateHealth(i);
  return HealthEntry(
    id: id,
    date: i.date,
    weight: i.weight,
    systolic: i.systolic,
    diastolic: i.diastolic,
    pulse: i.pulse,
    note: optionalText(i.note),
    createdAt: createdAt,
    updatedAt: now,
  );
}

/// Newest first; optional inclusive range.
final class WatchHealthEntries {
  const WatchHealthEntries(this._repo);
  final HealthRepository _repo;

  Stream<List<HealthEntry>> call({DateTime? from, DateTime? to}) =>
      _repo.watchAll(from: from, to: to);
}

final class WatchHealthEntry {
  const WatchHealthEntry(this._repo);
  final HealthRepository _repo;

  Stream<HealthEntry?> call(String id) => _repo.watchById(id);
}

final class CreateHealthEntry {
  const CreateHealthEntry(this._repo, this._clock);
  final HealthRepository _repo;
  final Clock _clock;

  Future<Result<HealthEntry>> call(HealthInput input) => guard(() async {
    final now = _clock.now();
    final e = _health(newId(), input, now, now);
    await _repo.save(e);
    return e;
  });
}

final class UpdateHealthEntry {
  const UpdateHealthEntry(this._repo, this._clock);
  final HealthRepository _repo;
  final Clock _clock;

  Future<Result<HealthEntry>> call(String id, HealthInput input) =>
      guard(() async {
        final old = await _repo.getById(id);
        if (old == null) throw const NotFoundFailure('Catatan tidak ditemukan');
        final e = _health(id, input, old.createdAt, _clock.now());
        await _repo.save(e);
        return e;
      });
}

final class DeleteHealthEntry {
  const DeleteHealthEntry(this._repo);
  final HealthRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}

// ---------------------------------------------------------------- food

final class FoodInput {
  const FoodInput({
    required this.date,
    required this.name,
    this.meal,
    this.mealLabel,
    this.clearMealLabel = false,
    this.calories,
    this.caloriesMax,
    this.clearCaloriesMax = false,
    this.tags,
    this.note,
  });

  final DateTime date;
  final String name;
  final MealType? meal;

  /// Free-text meal (≤ 24, one line), used when [meal] is null. On an update a
  /// null here keeps the stored label (an imported "makan malam" survives a
  /// form that only knows the canonical meals).
  final String? mealLabel;

  /// On an update: drop the stored [mealLabel] (the user emptied the field).
  final bool clearMealLabel;
  final num? calories;

  /// Upper bound of a calorie range (≥ [calories]). On an update null keeps
  /// the stored max (dropped when it no longer fits [calories]); set
  /// [clearCaloriesMax] to remove the range.
  final num? caloriesMax;
  final bool clearCaloriesMax;

  /// ≤ 10 tags of ≤ 30. Null = unchanged (create: none).
  final List<String>? tags;
  final String? note;
}

String? _mealLabel(String? v) {
  final s = v?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s == null || s.isEmpty) return null;
  if (s.length > 24) {
    throw const ValidationFailure(
      'Label makan terlalu panjang (maks 24 karakter)',
      field: 'meal',
    );
  }
  return s;
}

List<String> _foodTags(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final t in raw) {
    final v = t.trim();
    if (v.isEmpty || !seen.add(v.toLowerCase())) continue;
    if (v.length > 30) {
      throw const ValidationFailure(
        'Tag terlalu panjang (maks 30 karakter)',
        field: 'tags',
      );
    }
    out.add(v);
  }
  if (out.length > 10) {
    throw const ValidationFailure('Maksimal 10 tag', field: 'tags');
  }
  return out;
}

/// `caloriesMax` of a food log: explicit values must fit, a kept one that no
/// longer fits (calories lowered or removed) is dropped like the server does.
int? _caloriesMax(int? calories, num? max, {required bool explicit}) {
  if (max == null) return null;
  if (!max.isFinite || max < 0 || max > 20000) {
    throw const ValidationFailure(
      'Kalori maksimum sepertinya salah (0–20000)',
      field: 'caloriesMax',
    );
  }
  final m = max.round();
  if (calories == null || m < calories) {
    if (!explicit) return null;
    throw ValidationFailure(
      calories == null
          ? 'Isi kalori dulu sebelum rentang'
          : 'Kalori maksimum harus ≥ kalori minimum',
      field: 'caloriesMax',
    );
  }
  return m;
}

int? _calories(num? c) {
  if (c == null) return null;
  if (!c.isFinite || c < 0 || c > 20000) {
    throw const ValidationFailure(
      'Kalori sepertinya salah (0–20000)',
      field: 'calories',
    );
  }
  return c.round();
}

/// Newest first; optional inclusive range.
final class WatchFoodLogs {
  const WatchFoodLogs(this._repo);
  final FoodRepository _repo;

  Stream<List<FoodLog>> call({DateTime? from, DateTime? to}) =>
      _repo.watchAll(from: from, to: to);
}

final class WatchFoodLog {
  const WatchFoodLog(this._repo);
  final FoodRepository _repo;

  Stream<FoodLog?> call(String id) => _repo.watchById(id);
}

/// Logs food. [photoPath] is a picked image file (compress it first, ≤ 5 MB); it is
/// kept locally and uploaded on the next sync.
final class CreateFoodLog {
  const CreateFoodLog(this._repo, this._clock);
  final FoodRepository _repo;
  final Clock _clock;

  /// [transactionId] links the new log to an expense
  /// (`docs/food-transaction-link.md`; checked by `LinkFoodToTransaction`'s
  /// callers — the server stores a non-expense id as null).
  Future<Result<FoodLog>> call(
    FoodInput input, {
    String? photoPath,
    String? transactionId,
  }) => guard(() async {
    final now = _clock.now();
    final calories = _calories(input.calories);
    final log = FoodLog(
      id: newId(),
      date: input.date,
      name: requireName(input.name, max: 120),
      meal: input.meal,
      mealLabel: input.meal == null ? _mealLabel(input.mealLabel) : null,
      calories: calories,
      caloriesMax: _caloriesMax(calories, input.caloriesMax, explicit: true),
      tags: _foodTags(input.tags ?? const []),
      note: optionalText(input.note),
      transactionId: transactionId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(log, newPhotoPath: photoPath);
    return log;
  });
}

/// Updates a food log. Pass [photoPath] to replace the photo, or [removePhoto].
final class UpdateFoodLog {
  const UpdateFoodLog(this._repo, this._clock);
  final FoodRepository _repo;
  final Clock _clock;

  Future<Result<FoodLog>> call(
    String id,
    FoodInput input, {
    String? photoPath,
    bool removePhoto = false,
  }) => guard(() async {
    final old = await _repo.getById(id);
    if (old == null) throw const NotFoundFailure('Catatan tidak ditemukan');
    final keepPhoto = !removePhoto && photoPath == null;
    final calories = _calories(input.calories);
    final explicitMax = input.caloriesMax != null;
    final log = FoodLog(
      id: id,
      date: input.date,
      name: requireName(input.name, max: 120),
      meal: input.meal,
      mealLabel: input.meal != null
          ? null
          : (input.clearMealLabel
                ? null
                : (_mealLabel(input.mealLabel) ?? old.mealLabel)),
      calories: calories,
      caloriesMax: input.clearCaloriesMax
          ? null
          : _caloriesMax(
              calories,
              explicitMax ? input.caloriesMax : old.caloriesMax,
              explicit: explicitMax,
            ),
      tags: input.tags == null ? old.tags : _foodTags(input.tags!),
      photoUrl: keepPhoto ? old.photoUrl : null,
      localPhotoPath: keepPhoto ? old.localPhotoPath : null,
      note: optionalText(input.note),
      // Links change through LinkFoodToTransaction only.
      transactionId: old.transactionId,
      createdAt: old.createdAt,
      updatedAt: _clock.now(),
    );
    await _repo.save(log, newPhotoPath: photoPath);
    return log;
  });
}

final class DeleteFoodLog {
  const DeleteFoodLog(this._repo);
  final FoodRepository _repo;

  Future<Result<void>> call(String id) => guard(() => _repo.delete(id));
}
