/// Pure parts of the "Segarkan" review (no Flutter): the session queue, the
/// "3 / 43" position text and the helpers that rebuild a [DreamInput] from a
/// stored dream so one field can change without losing the rest.
library;

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import 'dream_list_logic.dart';

/// Ids of the review queue in list order; captured once per session so the
/// position stays put while saves reshuffle the live queue.
List<String> reviewSessionIds(Iterable<DreamRow> rows) => [
  for (final r in reviewQueue(rows)) r.id,
];

/// "3 / 43" for the zero-based [index] of [total].
String reviewPositionText(int index, int total) => '${index + 1} / $total';

/// [tags] without [dreamReviewTag] (case-insensitive); others keep their order.
List<String> removeReviewTag(Iterable<String> tags) => [
  for (final t in tags)
    if (t.toLowerCase() != dreamReviewTag) t,
];

const _keep = Object();

/// The input that saves [d] unchanged. Pass [tags], [status], [targetDate],
/// [targetPrecision] or [progressManual] to change just that one; null is a
/// real value for the last three (clears them).
DreamInput dreamInputOf(
  Dream d, {
  List<String>? tags,
  DreamStatus? status,
  Object? targetDate = _keep,
  Object? targetPrecision = _keep,
  Object? progressManual = _keep,
}) => DreamInput(
  title: d.title,
  emoji: d.emoji,
  category: d.category,
  status: status ?? d.status,
  priority: d.priority,
  horizon: d.horizon,
  targetDate: identical(targetDate, _keep)
      ? d.targetDate
      : targetDate as String?,
  targetPrecision: identical(targetPrecision, _keep)
      ? (d.targetDate == null ? null : d.targetPrecision)
      : targetPrecision as TargetPrecision?,
  condition: d.condition,
  why: d.why,
  summary: d.summary,
  costEstimate: d.costEstimate,
  costNote: d.costNote,
  progressManual: identical(progressManual, _keep)
      ? d.progressManual
      : progressManual as int?,
  startedAt: d.startedAt,
  completedAt: d.completedAt,
  noteId: d.noteId,
  parentId: d.parentId,
  tags: tags ?? d.tags,
  fields: d.fields,
  links: d.links,
  sortOrder: d.sortOrder,
);
