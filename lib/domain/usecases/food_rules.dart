/// Pure food rules (`docs/habits-food-enrichment.md`): calorie ranges, daily
/// and weekly totals (mirror of `foodSummary` in `src/lib/food-server.ts`),
/// meal labels and tags.
library;

import '../../core/dates.dart';
import '../entities/entities.dart';

/// Calories an entry adds: `calories` as the minimum, `caloriesMax ?? calories`
/// as the maximum. Entries without calories add nothing (but are counted).
final class FoodTotals {
  const FoodTotals({
    this.min = 0,
    this.max = 0,
    this.count = 0,
    this.noCalories = 0,
  });

  final int min;
  final int max;

  /// Entries, with or without calories.
  final int count;

  /// Entries that carry no calories.
  final int noCalories;

  /// Rounded midpoint, like the server (`Math.round((min + max) / 2)`).
  int get mid => _round((min + max) / 2);

  bool get isRange => max > min;
  bool get hasCalories => count > noCalories;

  FoodTotals plus(FoodLog l) {
    final lo = l.calories;
    if (lo == null) {
      return FoodTotals(
        min: min,
        max: max,
        count: count + 1,
        noCalories: noCalories + 1,
      );
    }
    return FoodTotals(
      min: min + lo,
      max: max + (l.caloriesMax ?? lo),
      count: count + 1,
      noCalories: noCalories,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FoodTotals &&
      other.min == min &&
      other.max == max &&
      other.count == count &&
      other.noCalories == noCalories;

  @override
  int get hashCode => Object.hash(min, max, count, noCalories);

  @override
  String toString() => 'FoodTotals($min–$max, $count)';
}

/// JS `Math.round` for non-negative numbers (half up).
int _round(num v) => (v + 0.5).floor();

/// Totals of [logs].
FoodTotals foodTotals(Iterable<FoodLog> logs) =>
    logs.fold(const FoodTotals(), (t, l) => t.plus(l));

/// `700` | `700–900` (en dash), or null when the entry has no calories.
String? calorieNumbers(FoodLog l) {
  final lo = l.calories;
  if (lo == null) return null;
  final hi = l.caloriesMax;
  return hi != null && hi > lo ? '$lo–$hi' : '$lo';
}

/// Minimum–maximum text of [t] with thousands dots: `1.700–1.900`, or a single
/// number when it is not a range.
String formatCalorieSpan(FoodTotals t, String Function(int) number) =>
    t.isRange ? '${number(t.min)}–${number(t.max)}' : number(t.min);

/// One day of the summary.
final class FoodSummaryDay {
  const FoodSummaryDay(this.date, this.totals);

  /// Local `YYYY-MM-DD`.
  final String date;
  final FoodTotals totals;
}

/// The average of the days that have entries.
final class FoodAverage {
  const FoodAverage({required this.min, required this.mid, required this.max});
  final int min;
  final int mid;
  final int max;
}

/// A tag with how often it appears.
final class FoodTagCount {
  const FoodTagCount(this.tag, this.count);
  final String tag;
  final int count;
}

/// What `GET /api/mobile/food/summary` returns, computed from local data.
final class FoodSummary {
  const FoodSummary({
    required this.from,
    required this.to,
    required this.days,
    required this.byMeal,
    required this.avgPerDay,
    required this.topTags,
  });

  final String from;
  final String to;

  /// Days that have entries, oldest first.
  final List<FoodSummaryDay> days;

  /// Keyed by the stored meal (`breakfast`… or the free label; `(none)`),
  /// most entries first.
  final Map<String, FoodTotals> byMeal;

  /// Null when no day has entries.
  final FoodAverage? avgPerDay;

  /// Up to 10, most used first.
  final List<FoodTagCount> topTags;

  int get daysLogged => days.length;
}

/// The key of an entry in [FoodSummary.byMeal].
String foodMealKey(FoodLog l) => l.meal?.wire ?? l.mealLabel ?? '(none)';

/// Summary of the logs between [from] and [to] (local `YYYY-MM-DD`,
/// inclusive) — same semantics as the server: entries add `calories` to `min`
/// and `caloriesMax ?? calories` to `max`; `avgPerDay` is over days with
/// entries.
FoodSummary summarizeFood(
  Iterable<FoodLog> logs, {
  required String from,
  required String to,
}) {
  final days = <String, FoodTotals>{};
  final meals = <String, FoodTotals>{};
  final tags = <String, FoodTagCount>{};
  for (final l in logs) {
    final day = dateKey(l.date);
    if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
    days[day] = (days[day] ?? const FoodTotals()).plus(l);
    final m = foodMealKey(l);
    meals[m] = (meals[m] ?? const FoodTotals()).plus(l);
    for (final t in l.tags) {
      final k = t.toLowerCase();
      final e = tags[k];
      tags[k] = FoodTagCount(e?.tag ?? t, (e?.count ?? 0) + 1);
    }
  }
  final dayList = [
    for (final k in days.keys.toList()..sort()) FoodSummaryDay(k, days[k]!),
  ];
  final n = dayList.length;
  final sumMin = dayList.fold(0, (s, d) => s + d.totals.min);
  final sumMax = dayList.fold(0, (s, d) => s + d.totals.max);
  final mealKeys = meals.keys.toList()
    ..sort((a, b) => meals[b]!.count.compareTo(meals[a]!.count));
  final tagList = tags.values.toList()
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
    });
  return FoodSummary(
    from: from,
    to: to,
    days: dayList,
    byMeal: {for (final k in mealKeys) k: meals[k]!},
    avgPerDay: n == 0
        ? null
        : FoodAverage(
            min: _round(sumMin / n),
            mid: _round((sumMin / n + sumMax / n) / 2),
            max: _round(sumMax / n),
          ),
    topTags: tagList.take(10).toList(),
  );
}

/// The last 7 days ending [today] (the server's default window).
FoodSummary weeklyFoodSummary(Iterable<FoodLog> logs, DateTime today) =>
    summarizeFood(
      logs,
      from: dateKey(addDays(startOfDay(today), -6)),
      to: dateKey(today),
    );

// ---------------------------------------------------------------- meal labels

/// Max length of a free-text meal label.
const foodMealLabelMax = 24;

/// A typed meal: a canonical [MealType] when the text names one (wire value or
/// Indonesian label, any case), else a free [label].
({MealType? meal, String? label}) resolveMealText(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return (meal: null, label: null);
  final lower = t.toLowerCase();
  for (final m in MealType.values) {
    if (m.wire == lower || m.label.toLowerCase() == lower) {
      return (meal: m, label: null);
    }
  }
  return (meal: null, label: t);
}

/// Custom meal labels from [logs] (newest first), most recent first, each
/// once (case-insensitive), at most [limit].
List<String> recentMealLabels(Iterable<FoodLog> logs, {int limit = 6}) {
  final seen = <String>{};
  final out = <String>[];
  for (final l in logs) {
    final label = l.mealLabel;
    if (label == null || !seen.add(label.toLowerCase())) continue;
    out.add(label);
    if (out.length >= limit) break;
  }
  return out;
}

// ---------------------------------------------------------------- tags

const foodTagsMax = 10;
const foodTagMax = 30;

/// Every tag in [logs] with its count, most used first (case-insensitive,
/// first spelling wins).
List<FoodTagCount> foodTagCounts(Iterable<FoodLog> logs) {
  final tags = <String, FoodTagCount>{};
  for (final l in logs) {
    for (final t in l.tags) {
      final k = t.toLowerCase();
      final e = tags[k];
      tags[k] = FoodTagCount(e?.tag ?? t, (e?.count ?? 0) + 1);
    }
  }
  return tags.values.toList()..sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
  });
}

/// The logs carrying [tag] (case-insensitive); all of them for a null tag.
List<FoodLog> filterFoodByTag(Iterable<FoodLog> logs, String? tag) {
  if (tag == null) return logs.toList();
  final k = tag.toLowerCase();
  return [
    for (final l in logs)
      if (l.tags.any((t) => t.toLowerCase() == k)) l,
  ];
}

/// Adds [raw] to [tags] when valid: trimmed, non-empty, ≤ 30 characters, not a
/// duplicate (case-insensitive), at most 10 tags. Returns [tags] unchanged
/// otherwise.
List<String> addFoodTag(List<String> tags, String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty || t.length > foodTagMax || tags.length >= foodTagsMax) {
    return tags;
  }
  if (tags.any((x) => x.toLowerCase() == t.toLowerCase())) return tags;
  return [...tags, t];
}

// ---------------------------------------------------------------- range input

/// Parses the min / max calorie fields of the form. A blank field is null;
/// anything else must be a whole number 0–20000. Returns an error text per
/// field (`calories` / `caloriesMax`).
({int? min, int? max, Map<String, String> errors}) parseCalorieRange(
  String minText,
  String maxText,
) {
  final errors = <String, String>{};
  int? parse(String raw, String field) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0 || v > 20000) {
      errors[field] = 'Kalori sepertinya salah (0–20.000)';
      return null;
    }
    return v;
  }

  final lo = parse(minText, 'calories');
  final hi = parse(maxText, 'caloriesMax');
  if (errors.isEmpty && hi != null) {
    if (lo == null) {
      errors['caloriesMax'] = 'Isi kalori minimum dulu sebelum rentang';
    } else if (hi < lo) {
      errors['caloriesMax'] = 'Kalori maksimum harus ≥ kalori minimum';
    }
  }
  return (min: lo, max: hi, errors: errors);
}
