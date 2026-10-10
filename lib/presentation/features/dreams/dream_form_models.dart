import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';

/// A step as the form holds it: edited in memory and written when the dream is
/// saved. [id] is client-made, so saving twice updates instead of duplicating.
final class StepDraft {
  const StepDraft({
    required this.id,
    required this.title,
    this.notes,
    this.done = false,
    this.dueDate,
    this.cost,
    this.reward,
    this.metricRef,
    this.atValue,
    this.persisted = false,
  });

  factory StepDraft.of(DreamStep s) => StepDraft(
    id: s.id,
    title: s.title,
    notes: s.notes,
    done: s.done,
    dueDate: s.dueDate,
    cost: s.cost,
    reward: s.reward,
    metricRef: s.metricRef,
    atValue: s.atValue,
    persisted: true,
  );

  final String id;
  final String title;
  final String? notes;
  final bool done;
  final String? dueDate;
  final double? cost;
  final String? reward;
  final String? metricRef;
  final double? atValue;

  /// Already stored (edit mode); only these need a delete when removed.
  final bool persisted;

  StepDraft copyWith({bool? done, bool? persisted}) => StepDraft(
    id: id,
    title: title,
    notes: notes,
    done: done ?? this.done,
    dueDate: dueDate,
    cost: cost,
    reward: reward,
    metricRef: metricRef,
    atValue: atValue,
    persisted: persisted ?? this.persisted,
  );

  DreamStepInput toInput() => DreamStepInput(
    title: title,
    notes: notes,
    done: done,
    dueDate: dueDate,
    cost: cost,
    reward: reward,
    metricRef: metricRef,
    atValue: atValue,
  );
}

/// A metric as the form holds it (see [StepDraft]).
final class MetricDraft {
  const MetricDraft({
    required this.id,
    required this.label,
    required this.source,
    this.sourceRef,
    this.direction,
    this.unit,
    this.startValue,
    this.startDate,
    required this.targetValue,
    this.targetDate,
    this.manualValue,
    this.manualAt,
    this.persisted = false,
  });

  factory MetricDraft.of(DreamMetric m) => MetricDraft(
    id: m.id,
    label: m.label,
    source: m.source,
    sourceRef: m.sourceRef,
    direction: m.direction,
    unit: m.unit,
    startValue: m.startValue,
    startDate: m.startDate,
    targetValue: m.targetValue,
    targetDate: m.targetDate,
    manualValue: m.manualValue,
    manualAt: m.manualAt,
    persisted: true,
  );

  final String id;
  final String label;
  final MetricSource source;
  final Map<String, Object?>? sourceRef;
  final MetricDirection? direction;
  final String? unit;
  final double? startValue;
  final String? startDate;
  final double targetValue;
  final String? targetDate;
  final double? manualValue;
  final DateTime? manualAt;
  final bool persisted;

  MetricDraft copyWith({bool? persisted}) => MetricDraft(
    id: id,
    label: label,
    source: source,
    sourceRef: sourceRef,
    direction: direction,
    unit: unit,
    startValue: startValue,
    startDate: startDate,
    targetValue: targetValue,
    targetDate: targetDate,
    manualValue: manualValue,
    manualAt: manualAt,
    persisted: persisted ?? this.persisted,
  );

  DreamMetricInput toInput() => DreamMetricInput(
    label: label,
    source: source,
    sourceRef: sourceRef,
    direction: direction,
    unit: unit,
    startValue: startValue,
    startDate: startDate,
    targetValue: targetValue,
    targetDate: targetDate,
    manualValue: manualValue,
    manualAt: manualAt,
  );
}

/// What a step or metric sheet hands back: a saved draft, or a delete.
final class DraftResult<T> {
  const DraftResult.save(T this.draft) : delete = false;
  const DraftResult.remove() : draft = null, delete = true;

  final T? draft;
  final bool delete;
}
