/// JSON wire format of the Dreams sync entities (`dreams`, `dreamSteps`,
/// `dreamMetrics`, `dreamCategories`, `dreamFields`; `docs/dreams.md`,
/// `docs/mobile-sync.md` → "Dreams") and the drift row ⇄ entity mappers.
///
/// `*ToWire` builds the push `data` (the row minus id / createdAt / updatedAt).
/// `*FromWire` parses a pulled row leniently; a null result means "ignore the
/// row" (a newer server, or a row without id / stamps). Computed values
/// (progress, metric current values, on-track) never travel and have no
/// mapper here: the online repository parses them.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../datasources/local/app_database.dart';
import 'habits_investments_wire.dart' show scalarMapFromJson;
import 'people_wire.dart' show stringListFromJson, stringListOrNull;
import 'wire.dart' show Json, isoUtc;

// ---------------------------------------------------------------- helpers

DateTime? _dateN(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
String? _strN(Object? v) => v is String && v.isNotEmpty ? v : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
double? _numN(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int? _intN(Object? v) => v is num && v.isFinite ? v.round() : null;
bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

({DateTime created, DateTime updated})? _stamps(Json j) {
  final created = _dateN(j['createdAt']);
  if (created == null) return null;
  return (created: created, updated: _dateN(j['updatedAt']) ?? created);
}

/// `sourceRef` JSON object → map, or null (also for a stored JSON string).
Map<String, Object?>? _objOrNull(Object? raw) {
  Object? v = raw;
  if (raw is String) {
    if (raw.isEmpty) return null;
    try {
      v = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  if (v is! Map) return null;
  return {
    for (final e in v.entries)
      if (e.key is String) e.key as String: e.value,
  };
}

String? _encodeOrNull(Object? v) => v == null ? null : jsonEncode(v);

// ---------------------------------------------------------------- dreams

Json dreamToWire(Dream d) => {
  'title': d.title,
  'emoji': d.emoji,
  'category': d.category,
  'status': d.status.wire,
  'priority': d.priority,
  'horizon': d.horizon?.wire,
  'targetDate': d.targetDate,
  'targetPrecision': d.targetPrecision.wire,
  'condition': d.condition,
  'why': d.why,
  'summary': d.summary,
  'costEstimate': d.costEstimate,
  'costNote': d.costNote,
  'progressManual': d.progressManual,
  'startedAt': d.startedAt,
  'completedAt': d.completedAt,
  'noteId': d.noteId,
  'parentId': d.parentId,
  'tags': d.tags,
  'fields': d.fields,
  'links': {'taskIds': d.links.taskIds, 'habitIds': d.links.habitIds},
  'sortOrder': d.sortOrder,
};

/// A pulled dream; null when the id or the stamps are missing.
Dream? dreamFromWire(Json j) {
  final id = _strN(j['id']);
  final st = _stamps(j);
  if (id == null || st == null) return null;
  final links = j['links'];
  return Dream(
    id: id,
    title: _str(j['title']),
    emoji: _strN(j['emoji']),
    category: _strN(j['category']) ?? 'other',
    status: DreamStatus.fromWire(j['status'] as String?),
    priority: _intN(j['priority']),
    horizon: DreamHorizon.tryFromWire(j['horizon'] as String?),
    targetDate: _strN(j['targetDate']),
    targetPrecision: TargetPrecision.fromWire(j['targetPrecision'] as String?),
    condition: _strN(j['condition']),
    why: _strN(j['why']),
    summary: _strN(j['summary']),
    costEstimate: _numN(j['costEstimate']),
    costNote: _strN(j['costNote']),
    progressManual: _intN(j['progressManual']),
    startedAt: _strN(j['startedAt']),
    completedAt: _strN(j['completedAt']),
    noteId: _strN(j['noteId']),
    parentId: _strN(j['parentId']),
    tags: stringListFromJson(j['tags']),
    fields: scalarMapFromJson(j['fields']),
    links: links is Map
        ? DreamLinks(
            taskIds: stringListFromJson(links['taskIds']),
            habitIds: stringListFromJson(links['habitIds']),
          )
        : DreamLinks.empty,
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension DreamRowX on DreamRow {
  Dream toEntity() => Dream(
    id: id,
    title: title,
    emoji: emoji,
    category: category,
    status: DreamStatus.fromWire(status),
    priority: priority,
    horizon: DreamHorizon.tryFromWire(horizon),
    targetDate: targetDate,
    targetPrecision: TargetPrecision.fromWire(targetPrecision),
    condition: condition,
    why: why,
    summary: summary,
    costEstimate: costEstimate,
    costNote: costNote,
    progressManual: progressManual,
    startedAt: startedAt,
    completedAt: completedAt,
    noteId: noteId,
    parentId: parentId,
    tags: stringListFromJson(tags),
    fields: scalarMapFromJson(fields),
    links: _linksFrom(links),
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

DreamLinks _linksFrom(String raw) {
  Object? v;
  try {
    v = jsonDecode(raw);
  } catch (_) {
    return DreamLinks.empty;
  }
  if (v is! Map) return DreamLinks.empty;
  return DreamLinks(
    taskIds: stringListFromJson(v['taskIds']),
    habitIds: stringListFromJson(v['habitIds']),
  );
}

extension DreamX on Dream {
  DreamsCompanion toCompanion() => DreamsCompanion.insert(
    id: id,
    title: title,
    emoji: Value(emoji),
    category: Value(category),
    status: Value(status.wire),
    priority: Value(priority),
    horizon: Value(horizon?.wire),
    targetDate: Value(targetDate),
    targetPrecision: Value(targetPrecision.wire),
    condition: Value(condition),
    why: Value(why),
    summary: Value(summary),
    costEstimate: Value(costEstimate),
    costNote: Value(costNote),
    progressManual: Value(progressManual),
    startedAt: Value(startedAt),
    completedAt: Value(completedAt),
    noteId: Value(noteId),
    parentId: Value(parentId),
    tags: Value(jsonEncode(tags)),
    fields: Value(jsonEncode(fields)),
    links: Value(
      jsonEncode({'taskIds': links.taskIds, 'habitIds': links.habitIds}),
    ),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- steps

Json dreamStepToWire(DreamStep s) => {
  'dreamId': s.dreamId,
  'title': s.title,
  'notes': s.notes,
  'done': s.done,
  'doneAt': s.doneAt == null ? null : isoUtc(s.doneAt!),
  'dueDate': s.dueDate,
  'cost': s.cost,
  'reward': s.reward,
  'metricRef': s.metricRef,
  'atValue': s.atValue,
  'sortOrder': s.sortOrder,
};

/// A pulled step; null when the id, dreamId, title or the stamps are missing.
DreamStep? dreamStepFromWire(Json j) {
  final id = _strN(j['id']);
  final dreamId = _strN(j['dreamId']);
  final title = _strN(j['title']);
  final st = _stamps(j);
  if (id == null || dreamId == null || title == null || st == null) return null;
  return DreamStep(
    id: id,
    dreamId: dreamId,
    title: title,
    notes: _strN(j['notes']),
    done: _bool(j['done']),
    doneAt: _dateN(j['doneAt']),
    dueDate: _strN(j['dueDate']),
    cost: _numN(j['cost']),
    reward: _strN(j['reward']),
    metricRef: _strN(j['metricRef']),
    atValue: _numN(j['atValue']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension DreamStepRowX on DreamStepRow {
  DreamStep toEntity() => DreamStep(
    id: id,
    dreamId: dreamId,
    title: title,
    notes: notes,
    done: done,
    doneAt: doneAt,
    dueDate: dueDate,
    cost: cost,
    reward: reward,
    metricRef: metricRef,
    atValue: atValue,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension DreamStepX on DreamStep {
  DreamStepsCompanion toCompanion() => DreamStepsCompanion.insert(
    id: id,
    dreamId: dreamId,
    title: title,
    notes: Value(notes),
    done: Value(done),
    doneAt: Value(doneAt),
    dueDate: Value(dueDate),
    cost: Value(cost),
    reward: Value(reward),
    metricRef: Value(metricRef),
    atValue: Value(atValue),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- metrics

Json dreamMetricToWire(DreamMetric m) => {
  'dreamId': m.dreamId,
  'label': m.label,
  'source': m.source.wire,
  'sourceRef': m.sourceRef,
  'direction': m.direction?.wire,
  'unit': m.unit,
  'startValue': m.startValue,
  'startDate': m.startDate,
  'targetValue': m.targetValue,
  'targetDate': m.targetDate,
  'manualValue': m.manualValue,
  'manualAt': m.manualAt == null ? null : isoUtc(m.manualAt!),
  'sortOrder': m.sortOrder,
};

/// A pulled metric; null for an unknown `source` (a newer server) or a row
/// without id / dreamId / label / targetValue / stamps.
DreamMetric? dreamMetricFromWire(Json j) {
  final id = _strN(j['id']);
  final dreamId = _strN(j['dreamId']);
  final label = _strN(j['label']);
  final source = MetricSource.tryFromWire(j['source'] as String?);
  final target = _numN(j['targetValue']);
  final st = _stamps(j);
  if (id == null ||
      dreamId == null ||
      label == null ||
      source == null ||
      target == null ||
      st == null) {
    return null;
  }
  return DreamMetric(
    id: id,
    dreamId: dreamId,
    label: label,
    source: source,
    sourceRef: _objOrNull(j['sourceRef']),
    direction: MetricDirection.tryFromWire(j['direction'] as String?),
    unit: _strN(j['unit']),
    startValue: _numN(j['startValue']),
    startDate: _strN(j['startDate']),
    targetValue: target,
    targetDate: _strN(j['targetDate']),
    manualValue: _numN(j['manualValue']),
    manualAt: _dateN(j['manualAt']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension DreamMetricRowX on DreamMetricRow {
  /// Null for a stored `source` this app doesn't know.
  DreamMetric? toEntityOrNull() {
    final s = MetricSource.tryFromWire(source);
    if (s == null) return null;
    return DreamMetric(
      id: id,
      dreamId: dreamId,
      label: label,
      source: s,
      sourceRef: _objOrNull(sourceRef),
      direction: MetricDirection.tryFromWire(direction),
      unit: unit,
      startValue: startValue,
      startDate: startDate,
      targetValue: targetValue,
      targetDate: targetDate,
      manualValue: manualValue,
      manualAt: manualAt,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension DreamMetricX on DreamMetric {
  DreamMetricsCompanion toCompanion() => DreamMetricsCompanion.insert(
    id: id,
    dreamId: dreamId,
    label: label,
    source: source.wire,
    sourceRef: Value(_encodeOrNull(sourceRef)),
    direction: Value(direction?.wire),
    unit: Value(unit),
    startValue: Value(startValue),
    startDate: Value(startDate),
    targetValue: targetValue,
    targetDate: Value(targetDate),
    manualValue: Value(manualValue),
    manualAt: Value(manualAt),
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- categories

Json dreamCategoryToWire(DreamCategory c) => {
  'key': c.key,
  'label': c.label,
  'emoji': c.emoji,
  'sortOrder': c.sortOrder,
};

DreamCategory? dreamCategoryFromWire(Json j) {
  final id = _strN(j['id']);
  final key = _strN(j['key']);
  final st = _stamps(j);
  if (id == null || key == null || st == null) return null;
  return DreamCategory(
    id: id,
    key: key,
    label: _str(j['label'], key),
    emoji: _strN(j['emoji']) ?? '✨',
    sortOrder: _intN(j['sortOrder']) ?? 0,
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension DreamCategoryRowX on DreamCategoryRow {
  DreamCategory toEntity() => DreamCategory(
    id: id,
    key: key,
    label: label,
    emoji: emoji,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension DreamCategoryX on DreamCategory {
  DreamCategoriesCompanion toCompanion() => DreamCategoriesCompanion.insert(
    id: id,
    key: key,
    label: label,
    emoji: emoji,
    sortOrder: Value(sortOrder),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------- fields

Json dreamFieldToWire(DreamFieldDef d) => {
  'key': d.key,
  'label': d.label,
  'type': d.type.wire,
  'options': d.options,
  'appliesTo': d.appliesTo,
  'sortOrder': d.sortOrder,
  'showInList': d.showInList,
};

/// Null for an unknown `type` (a newer server).
DreamFieldDef? dreamFieldFromWire(Json j) {
  final id = _strN(j['id']);
  final key = _strN(j['key']);
  final type = DreamFieldType.tryFromWire(j['type'] as String?);
  final st = _stamps(j);
  if (id == null || key == null || type == null || st == null) return null;
  return DreamFieldDef(
    id: id,
    key: key,
    label: _str(j['label'], key),
    type: type,
    options: stringListOrNull(j['options']),
    appliesTo: stringListOrNull(j['appliesTo']),
    sortOrder: _intN(j['sortOrder']) ?? 0,
    showInList: _bool(j['showInList']),
    createdAt: st.created,
    updatedAt: st.updated,
  );
}

extension DreamFieldRowX on DreamFieldRow {
  /// Null for a stored `type` this app doesn't know.
  DreamFieldDef? toEntityOrNull() {
    final t = DreamFieldType.tryFromWire(type);
    if (t == null) return null;
    return DreamFieldDef(
      id: id,
      key: key,
      label: label,
      type: t,
      options: stringListOrNull(options),
      appliesTo: stringListOrNull(appliesTo),
      sortOrder: sortOrder,
      showInList: showInList,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension DreamFieldX on DreamFieldDef {
  DreamFieldsCompanion toCompanion() => DreamFieldsCompanion.insert(
    id: id,
    key: key,
    label: label,
    type: Value(type.wire),
    options: Value(_encodeOrNull(options)),
    appliesTo: Value(_encodeOrNull(appliesTo)),
    sortOrder: Value(sortOrder),
    showInList: Value(showInList),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
