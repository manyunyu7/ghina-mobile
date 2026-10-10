import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import 'dream_list_logic.dart';

/// Every dream as a [DreamRow] (steps, metrics and the clock joined in), or
/// the first error / loading of its sources. Fully local: works offline.
final dreamRowsProvider = Provider.autoDispose<AsyncValue<List<DreamRow>>>((
  ref,
) {
  final dreams = ref.watch(watchDreamsProvider);
  final steps = ref.watch(watchDreamStepsProvider);
  final metrics = ref.watch(watchDreamMetricsProvider);
  final sources = [dreams, steps, metrics];
  for (final s in sources) {
    if (s.hasError) {
      return AsyncValue.error(s.error!, s.stackTrace ?? StackTrace.current);
    }
  }
  if (!sources.every((s) => s.hasValue)) {
    return const AsyncValue.loading();
  }
  final now = ref.watch(clockProvider).now();
  return AsyncValue.data(
    buildDreamRows(
      dreams: dreams.requireValue,
      stepsByDream: steps.requireValue,
      metricsByDream: metrics.requireValue,
      now: now,
    ),
  );
});

/// Category label "🌟 Perjalanan" by key; a key the user no longer has reads
/// as its plain key.
String dreamCategoryLabel(String key, List<DreamCategory> categories) {
  for (final c in categories) {
    if (c.key == key) return '${c.emoji} ${c.label}';
  }
  return key == 'other' ? '✨ Lainnya' : key;
}
