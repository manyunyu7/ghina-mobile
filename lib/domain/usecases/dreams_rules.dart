/// Pure rules of Dreams ("Mimpi"): a Dart port of the server's
/// `src/lib/dreams.ts` (`docs/dreams.md`) — flexible target dates, validation
/// limits, metric progress / trend / projection, step auto-completion, costs,
/// staleness and review, plus list sort / group helpers. No Flutter, no I/O.
/// Messages are Indonesian; limits and algorithms match the server.
///
/// Date keys are `YYYY-MM-DD` strings. "Today" and "now" are passed in, so the
/// rules stay deterministic (the server uses the user's `tz`).
library;

import '../../core/failure.dart';
import '../entities/entities.dart';
import 'people_rules.dart' show normalizeTags;

// ---------------------------------------------------------------- limits

const dreamTitleMax = 160;
const dreamEmojiMax = 8;
const dreamConditionMax = 300;
const dreamWhyMax = 1000;
const dreamSummaryMax = 1000;
const dreamCostNoteMax = 300;
const dreamTagsMax = 20;
const dreamTagMax = 40;
const dreamFieldsMaxKeys = 60;
const dreamFieldValueMax = 2000;
const dreamLinksMax = 20;
const dreamPriorityMin = 1;
const dreamPriorityMax = 5;
const stepTitleMax = 200;
const stepNotesMax = 1000;
const stepRewardMax = 200;
const stepsPerDreamMax = 200;
const metricLabelMax = 80;
const metricUnitMax = 16;
const metricsPerDreamMax = 20;
const dreamCategoryLabelMax = 60;
const dreamCategoryEmojiMax = 8;
const dreamFieldLabelMax = 80;
const dreamFieldOptionMax = 80;
const dreamFieldOptionsMax = 50;

/// A dream is "stale" when nothing about it changed for this many days.
const dreamStaleDays = 60;

/// Trend window and thresholds of the metric projection.
const dreamTrendDays = 60;
const dreamTrendMinPoints = 3;
const dreamTrendMinSpanDays = 7;

/// "Coming up" window of the `due=soon` filter.
const dreamSoonDays = 90;

/// Projections further out than this are not shown.
const dreamMaxProjectionDays = 3650;

final _dreamKeyRe = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
final _dateKeyRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _urlRe = RegExp(r'^https?://[^\s]+$', caseSensitive: false);

// ---------------------------------------------------------------- date keys

String _pad2(int n) => n.toString().padLeft(2, '0');
String _keyOf(int y, int m, int d) => '$y-${_pad2(m)}-${_pad2(d)}';
int _lastDayOf(int y, int m) => DateTime.utc(y, m + 1, 0).day;
int _dayMs(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch;
}

String _keyFromMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return _keyOf(d.year, d.month, d.day);
}

/// `YYYY-MM-DD` that is a real calendar day (the server's `isDateKey`).
bool isDreamDateKey(String s) {
  final m = _dateKeyRe.firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  return mo >= 1 && mo <= 12 && d >= 1 && d <= _lastDayOf(y, mo);
}

/// Whole days from [a] to [b] (date keys; negative when [b] is earlier).
int daysBetweenKeys(String a, String b) =>
    ((_dayMs(b) - _dayMs(a)) / 86400000).round();

/// [key] moved by [n] days.
String addDreamDays(String key, int n) {
  final p = key.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2] + n);
  return _keyOf(d.year, d.month, d.day);
}

/// The LAST day of the period [date] falls in (day: itself; month; quarter;
/// year). A stored target is always this value.
String snapToPeriodEnd(String date, TargetPrecision precision) {
  final p = date.split('-').map(int.parse).toList();
  final y = p[0], m = p[1], d = p[2];
  return switch (precision) {
    TargetPrecision.day => _keyOf(y, m, d),
    TargetPrecision.month => _keyOf(y, m, _lastDayOf(y, m)),
    TargetPrecision.quarter => () {
      final qm = ((m + 2) ~/ 3) * 3;
      return _keyOf(y, qm, _lastDayOf(y, qm));
    }(),
    TargetPrecision.year => _keyOf(y, 12, 31),
  };
}

/// First day of the period a target date stands for.
String periodStart(String date, TargetPrecision precision) {
  final p = date.split('-').map(int.parse).toList();
  final y = p[0], m = p[1], d = p[2];
  return switch (precision) {
    TargetPrecision.day => _keyOf(y, m, d),
    TargetPrecision.month => _keyOf(y, m, 1),
    TargetPrecision.quarter => _keyOf(y, ((m - 1) ~/ 3) * 3 + 1, 1),
    TargetPrecision.year => _keyOf(y, 1, 1),
  };
}

// ---------------------------------------------------------------- flexible target dates

const _monthNames = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

final Map<String, int> _monthLookup = () {
  final m = <String, int>{};
  void add(int n, List<String> names) {
    for (final x in names) {
      m[x] = n;
    }
  }

  add(1, ['januari', 'january', 'jan']);
  add(2, ['februari', 'pebruari', 'february', 'feb', 'peb']);
  add(3, ['maret', 'march', 'mar']);
  add(4, ['april', 'apr']);
  add(5, ['mei', 'may']);
  add(6, ['juni', 'june', 'jun']);
  add(7, ['juli', 'july', 'jul']);
  add(8, ['agustus', 'august', 'agu', 'aug', 'agt']);
  add(9, ['september', 'sep', 'sept']);
  add(10, ['oktober', 'october', 'okt', 'oct']);
  add(11, ['november', 'nov', 'nop']);
  add(12, ['desember', 'december', 'des', 'dec']);
  return m;
}();

bool _yearOk(int y) => y >= 1900 && y <= 2200;

/// A target date parsed from free text: [date] is the last day of the period.
typedef DreamTarget = ({String date, TargetPrecision precision});

/// "Q1 2027", "kuartal 2 2027", "Januari 2027", "Jan 2027", "2027-01", "2027",
/// "15 Maret 2027", "2027-03-15" → the target (null when not understood).
DreamTarget? parseFlexibleTarget(String text) {
  final t = text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  var m = _dateKeyRe.firstMatch(t);
  if (m != null) {
    return isDreamDateKey(t) ? (date: t, precision: TargetPrecision.day) : null;
  }
  m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(t);
  if (m != null) {
    final y = int.parse(m[1]!), mo = int.parse(m[2]!);
    if (_yearOk(y) && mo >= 1 && mo <= 12) {
      return (
        date: snapToPeriodEnd(_keyOf(y, mo, 1), TargetPrecision.month),
        precision: TargetPrecision.month,
      );
    }
  }
  m = RegExp(r'^(\d{4})$').firstMatch(t);
  if (m != null && _yearOk(int.parse(m[1]!))) {
    return (
      date: _keyOf(int.parse(m[1]!), 12, 31),
      precision: TargetPrecision.year,
    );
  }
  DreamTarget? quarter(int q, String yRaw) {
    final y = yRaw.length == 2 ? 2000 + int.parse(yRaw) : int.parse(yRaw);
    if (q >= 1 && q <= 4 && _yearOk(y)) {
      return (
        date: snapToPeriodEnd(_keyOf(y, q * 3, 1), TargetPrecision.quarter),
        precision: TargetPrecision.quarter,
      );
    }
    return null;
  }

  m = RegExp(
    r"^(?:q|kuartal|kuarter|triwulan|quarter)\s*([1-4])\s*[-/' ]?\s*(\d{4}|\d{2})$",
  ).firstMatch(t);
  if (m != null) return quarter(int.parse(m[1]!), m[2]!);
  m = RegExp(
    r'^(\d{4})\s*[-/ ]?\s*(?:q|kuartal|kuarter|triwulan|quarter)\s*([1-4])$',
  ).firstMatch(t);
  if (m != null) return quarter(int.parse(m[2]!), m[1]!);
  m = RegExp(r'^([a-z]+)\s+(\d{4})$').firstMatch(t);
  if (m != null && _monthLookup[m[1]!] != null && _yearOk(int.parse(m[2]!))) {
    return (
      date: snapToPeriodEnd(
        _keyOf(int.parse(m[2]!), _monthLookup[m[1]!]!, 1),
        TargetPrecision.month,
      ),
      precision: TargetPrecision.month,
    );
  }
  m = RegExp(r'^(\d{4})\s+([a-z]+)$').firstMatch(t);
  if (m != null && _monthLookup[m[2]!] != null && _yearOk(int.parse(m[1]!))) {
    return (
      date: snapToPeriodEnd(
        _keyOf(int.parse(m[1]!), _monthLookup[m[2]!]!, 1),
        TargetPrecision.month,
      ),
      precision: TargetPrecision.month,
    );
  }
  m = RegExp(r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})$').firstMatch(t);
  if (m != null && _monthLookup[m[2]!] != null) {
    final key = _keyOf(
      int.parse(m[3]!),
      _monthLookup[m[2]!]!,
      int.parse(m[1]!),
    );
    return isDreamDateKey(key)
        ? (date: key, precision: TargetPrecision.day)
        : null;
  }
  return null;
}

/// "15 Mar 2027" / "Maret 2027" / "Q1 2027" / "2027"; "" without a date.
String formatTarget(
  String? date, [
  TargetPrecision precision = TargetPrecision.day,
]) {
  if (date == null || !isDreamDateKey(date)) return '';
  final p = date.split('-').map(int.parse).toList();
  final y = p[0], m = p[1], d = p[2];
  return switch (precision) {
    TargetPrecision.year => '$y',
    TargetPrecision.quarter => 'Q${((m + 2) ~/ 3)} $y',
    TargetPrecision.month => '${_monthNames[m - 1]} $y',
    TargetPrecision.day => '$d ${_monthShort[m - 1]} $y',
  };
}

/// Whole days from [today] to the target (negative = passed). Null without a date.
int? daysUntilTarget(String? date, String today) =>
    date != null && isDreamDateKey(date) ? daysBetweenKeys(today, date) : null;

/// Normalises a target from a stored/typed date and precision: a full date is
/// snapped to the end of its [precision] period (day by default); free text is
/// parsed (and sets the precision); null or blank means no target.
/// Throws [ValidationFailure] for text that is not understood.
({String? targetDate, TargetPrecision targetPrecision}) normalizeDreamTarget(
  String? date, [
  TargetPrecision? precision,
]) {
  final raw = date?.trim();
  if (raw == null || raw.isEmpty) {
    return (targetDate: null, targetPrecision: TargetPrecision.day);
  }
  final p = precision ?? TargetPrecision.day;
  if (isDreamDateKey(raw)) {
    return (targetDate: snapToPeriodEnd(raw, p), targetPrecision: p);
  }
  final f = parseFlexibleTarget(raw);
  if (f == null) {
    throw const ValidationFailure(
      'Target harus berupa tanggal YYYY-MM-DD atau teks seperti "Q1 2027", "Januari 2027", "2027"',
      field: 'targetDate',
    );
  }
  return (targetDate: f.date, targetPrecision: f.precision);
}

// ---------------------------------------------------------------- custom fields

/// Display form of a stored custom-field value ("Ya", "15 Mar 2027", "38").
String formatDreamFieldValue(DreamFieldDef def, Object? value) {
  if (value == null) return '';
  if (def.type == DreamFieldType.boolean) return value == true ? 'Ya' : 'Tidak';
  if (def.type == DreamFieldType.date &&
      value is String &&
      isDreamDateKey(value)) {
    return formatTarget(value);
  }
  if (value is num && value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return '$value';
}

/// The type check of one custom-column value (the server's `personFields`
/// rules, dream field types). Returns the value to store.
Object checkDreamFieldValue(DreamFieldDef def, Object? value) {
  final label = def.label;
  ValidationFailure fail(String m) => ValidationFailure(m, field: 'fields');
  String str([int max = dreamFieldValueMax]) {
    if (value is! String) throw fail('$label harus berupa teks');
    final v = value.trim();
    if (v.isEmpty) throw fail('$label nggak boleh kosong');
    if (v.length > max) throw fail('$label terlalu panjang (maks $max)');
    return v;
  }

  switch (def.type) {
    case DreamFieldType.text:
    case DreamFieldType.longtext:
      return str();
    case DreamFieldType.phone:
      return str(40);
    case DreamFieldType.email:
      final v = str(200);
      if (!_emailRe.hasMatch(v)) throw fail('$label harus berupa email');
      return v;
    case DreamFieldType.url:
      final v = str();
      if (!_urlRe.hasMatch(v)) throw fail('$label harus berupa tautan http(s)');
      return v;
    case DreamFieldType.date:
      final v = str(10);
      if (!isDreamDateKey(v)) throw fail('$label harus berupa tanggal');
      return v;
    case DreamFieldType.number:
      if (value is num && value.isFinite) return value;
      throw fail('$label harus berupa angka');
    case DreamFieldType.boolean:
      if (value is bool) return value;
      throw fail('$label harus Ya atau Tidak');
    case DreamFieldType.select:
      final v = str(dreamFieldOptionMax);
      if (!(def.options ?? const []).contains(v)) {
        throw fail(
          '$label harus salah satu: ${(def.options ?? []).join(', ')}',
        );
      }
      return v;
  }
}

/// Validates a whole custom-column map against the defs: every key needs a
/// def and every value must fit its type; ≤ 60 keys. Null values are dropped.
Map<String, Object> validateDreamFields(
  Map<String, Object?> fields,
  Iterable<DreamFieldDef> defs,
) {
  if (fields.length > dreamFieldsMaxKeys) {
    throw const ValidationFailure(
      'Terlalu banyak kolom ($dreamFieldsMaxKeys maks)',
      field: 'fields',
    );
  }
  final byKey = {for (final d in defs) d.key: d};
  final out = <String, Object>{};
  for (final e in fields.entries) {
    final def = byKey[e.key];
    if (def == null) {
      throw ValidationFailure('Kolom "${e.key}" belum ada', field: 'fields');
    }
    if (e.value == null) continue;
    out[e.key] = checkDreamFieldValue(def, e.value);
  }
  return out;
}

/// Whether [def] still accepts every value (the retype safety check).
bool dreamFieldStillFits(DreamFieldDef def, Iterable<Object?> values) {
  for (final v in values) {
    try {
      checkDreamFieldValue(def, v);
    } on ValidationFailure {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------- sources

/// Validates a `sourceRef` for [source] and returns the clean ref: the id the
/// source needs (`habitId` / `walletId` / `categoryId` + `period`, default
/// `month`), or null when the source takes none. Throws [ValidationFailure].
Map<String, Object?>? checkDreamSourceRef(
  MetricSource source,
  Map<String, Object?>? raw,
) {
  String? id(String k) {
    final v = raw?[k];
    return v is String && v.isNotEmpty && v.length <= 128 ? v : null;
  }

  switch (source.refKind) {
    case MetricRefKind.none:
      return null;
    case MetricRefKind.habit:
      final habitId = id('habitId');
      if (habitId == null) {
        throw ValidationFailure(
          '${source.wire} butuh sourceRef {habitId}',
          field: 'sourceRef',
        );
      }
      return {'habitId': habitId};
    case MetricRefKind.wallet:
      final walletId = id('walletId');
      if (walletId == null) {
        throw ValidationFailure(
          '${source.wire} butuh sourceRef {walletId}',
          field: 'sourceRef',
        );
      }
      return {'walletId': walletId};
    case MetricRefKind.category:
      final categoryId = id('categoryId');
      if (categoryId == null) {
        throw const ValidationFailure(
          'spend_category butuh sourceRef {categoryId, period}',
          field: 'sourceRef',
        );
      }
      final rawPeriod = raw?['period'];
      final period = rawPeriod == null
          ? SpendPeriod.month
          : SpendPeriod.values.where((p) => p.wire == rawPeriod).firstOrNull;
      if (period == null) {
        throw ValidationFailure(
          'period harus salah satu dari ${SpendPeriod.values.map((p) => p.wire).join('/')}',
          field: 'sourceRef',
        );
      }
      return {'categoryId': categoryId, 'period': period.wire};
  }
}

// ---------------------------------------------------------------- inputs & validation

/// What the user typed for a dream (before validation). Dates may be free
/// text ("Q1 2027") for [targetDate].
final class DreamInput {
  const DreamInput({
    required this.title,
    this.emoji,
    this.category = 'other',
    this.status = DreamStatus.idea,
    this.priority,
    this.horizon,
    this.targetDate,
    this.targetPrecision,
    this.condition,
    this.why,
    this.summary,
    this.costEstimate,
    this.costNote,
    this.progressManual,
    this.startedAt,
    this.completedAt,
    this.noteId,
    this.parentId,
    this.tags = const [],
    this.fields = const {},
    this.links = DreamLinks.empty,
    this.sortOrder = 0,
  });

  final String title;
  final String? emoji;
  final String category;
  final DreamStatus status;
  final int? priority;
  final DreamHorizon? horizon;
  final String? targetDate;
  final TargetPrecision? targetPrecision;
  final String? condition;
  final String? why;
  final String? summary;
  final double? costEstimate;
  final String? costNote;
  final int? progressManual;
  final String? startedAt;
  final String? completedAt;
  final String? noteId;
  final String? parentId;
  final List<String> tags;
  final Map<String, Object?> fields;
  final DreamLinks links;
  final int sortOrder;
}

String _required(String? v, int max, String what, String field) {
  final s = (v ?? '').trim();
  if (s.isEmpty) throw ValidationFailure('$what wajib diisi', field: field);
  if (s.length > max) {
    throw ValidationFailure(
      '$what terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

String? _optional(String? v, int max, String what, String field) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (s.length > max) {
    throw ValidationFailure(
      '$what terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

String? _dateOrNull(String? v, String field) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (!isDreamDateKey(s)) {
    throw ValidationFailure(
      '$field harus berupa tanggal YYYY-MM-DD',
      field: field,
    );
  }
  return s;
}

List<String> _idList(Iterable<String> raw, String field) {
  final out = <String>{};
  for (final v in raw) {
    final s = v.trim();
    if (s.isEmpty) continue;
    if (s.length > 128) {
      throw ValidationFailure('Id tautan terlalu panjang', field: field);
    }
    out.add(s);
  }
  if (out.length > dreamLinksMax) {
    throw ValidationFailure(
      'Terlalu banyak tautan (maks $dreamLinksMax)',
      field: field,
    );
  }
  return out.toList();
}

/// Validated, normalised dream (mirrors `dreamSchema`): lengths, priority,
/// the flexible target date, dates, costs, tags, custom fields (must fit
/// [defs]), the category (one of [categoryKeys]; `other` always passes) and
/// the soft links. [createdAt] / [updatedAt] are stamped by the caller.
Dream validateDream({
  required String id,
  required DreamInput input,
  required Iterable<String> categoryKeys,
  required Iterable<DreamFieldDef> defs,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  final title = _required(input.title, dreamTitleMax, 'Judul', 'title');
  final category = input.category.trim();
  if (!_dreamKeyRe.hasMatch(category)) {
    throw const ValidationFailure(
      'Kategori tidak valid (a-z, 0-9, _)',
      field: 'category',
    );
  }
  if (category != 'other' && !categoryKeys.contains(category)) {
    throw ValidationFailure(
      'Kategori "$category" belum ada',
      field: 'category',
    );
  }
  final priority = input.priority;
  if (priority != null &&
      (priority < dreamPriorityMin || priority > dreamPriorityMax)) {
    throw const ValidationFailure('Prioritas harus 1–5', field: 'priority');
  }
  final progress = input.progressManual;
  if (progress != null && (progress < 0 || progress > 100)) {
    throw const ValidationFailure(
      'Progres harus 0–100',
      field: 'progressManual',
    );
  }
  final cost = input.costEstimate;
  if (cost != null && (!cost.isFinite || cost < 0)) {
    throw const ValidationFailure(
      'Estimasi biaya tidak boleh negatif',
      field: 'costEstimate',
    );
  }
  final target = normalizeDreamTarget(input.targetDate, input.targetPrecision);
  final tags = normalizeTags(input.tags);
  if (tags.length > dreamTagsMax) {
    throw const ValidationFailure('Terlalu banyak tag', field: 'tags');
  }
  return Dream(
    id: id,
    title: title,
    emoji: _optional(input.emoji, dreamEmojiMax, 'Emoji', 'emoji'),
    category: category,
    status: input.status,
    priority: priority,
    horizon: input.horizon,
    targetDate: target.targetDate,
    targetPrecision: target.targetPrecision,
    condition: _optional(
      input.condition,
      dreamConditionMax,
      'Syarat',
      'condition',
    ),
    why: _optional(input.why, dreamWhyMax, 'Alasan', 'why'),
    summary: _optional(input.summary, dreamSummaryMax, 'Ringkasan', 'summary'),
    costEstimate: cost,
    costNote: _optional(
      input.costNote,
      dreamCostNoteMax,
      'Catatan biaya',
      'costNote',
    ),
    progressManual: progress,
    startedAt: _dateOrNull(input.startedAt, 'startedAt'),
    completedAt: _dateOrNull(input.completedAt, 'completedAt'),
    noteId: input.noteId,
    parentId: input.parentId,
    tags: tags,
    fields: validateDreamFields(input.fields, defs),
    links: DreamLinks(
      taskIds: _idList(input.links.taskIds, 'links'),
      habitIds: _idList(input.links.habitIds, 'links'),
    ),
    sortOrder: input.sortOrder < 0 ? 0 : input.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// What the user typed for a step.
final class DreamStepInput {
  const DreamStepInput({
    required this.title,
    this.notes,
    this.done = false,
    this.dueDate,
    this.cost,
    this.reward,
    this.metricRef,
    this.atValue,
    this.sortOrder = 0,
  });

  final String title;
  final String? notes;
  final bool done;
  final String? dueDate;
  final double? cost;
  final String? reward;
  final String? metricRef;
  final double? atValue;
  final int sortOrder;
}

/// Validated step (mirrors `dreamStepSchema`). A done step is stamped with
/// [now] unless it was already done: then [previousDoneAt] is kept. An undone
/// step has no `doneAt`.
DreamStep validateDreamStep({
  required String id,
  required String dreamId,
  required DreamStepInput input,
  required DateTime now,
  DateTime? previousDoneAt,
  DateTime? createdAt,
}) {
  final title = _required(input.title, stepTitleMax, 'Judul langkah', 'title');
  final cost = input.cost;
  if (cost != null && (!cost.isFinite || cost < 0)) {
    throw const ValidationFailure(
      'Biaya langkah tidak boleh negatif',
      field: 'cost',
    );
  }
  final hasRef = input.metricRef != null && input.metricRef!.isNotEmpty;
  if (hasRef != (input.atValue != null)) {
    throw const ValidationFailure(
      'Metrik dan nilai ambang harus diisi berdua',
      field: 'metricRef',
    );
  }
  return DreamStep(
    id: id,
    dreamId: dreamId,
    title: title,
    notes: _optional(input.notes, stepNotesMax, 'Catatan', 'notes'),
    done: input.done,
    doneAt: input.done ? (previousDoneAt ?? now) : null,
    dueDate: _dateOrNull(input.dueDate, 'dueDate'),
    cost: cost,
    reward: _optional(input.reward, stepRewardMax, 'Hadiah', 'reward'),
    metricRef: hasRef ? input.metricRef : null,
    atValue: hasRef ? input.atValue : null,
    sortOrder: input.sortOrder < 0 ? 0 : input.sortOrder,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
}

/// What the user typed for a metric.
final class DreamMetricInput {
  const DreamMetricInput({
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
    this.sortOrder = 0,
  });

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
  final int sortOrder;
}

/// Validated metric (mirrors `dreamMetricSchema`): the label, the unit, the
/// `sourceRef` the source needs, the direction (derived when omitted), dates,
/// and manual readings only for `manual` metrics.
DreamMetric validateDreamMetric({
  required String id,
  required String dreamId,
  required DreamMetricInput input,
  required DateTime now,
  DateTime? createdAt,
}) {
  final label = _required(input.label, metricLabelMax, 'Label', 'label');
  final unit = (input.unit ?? '').trim();
  if (unit.length > metricUnitMax) {
    throw ValidationFailure(
      'Satuan terlalu panjang (maks $metricUnitMax)',
      field: 'unit',
    );
  }
  if (!input.targetValue.isFinite) {
    throw const ValidationFailure(
      'Target harus berupa angka',
      field: 'targetValue',
    );
  }
  if (input.source != MetricSource.manual &&
      (input.manualValue != null || input.manualAt != null)) {
    throw const ValidationFailure(
      'Nilai manual hanya untuk sumber manual',
      field: 'manualValue',
    );
  }
  final metric = DreamMetric(
    id: id,
    dreamId: dreamId,
    label: label,
    source: input.source,
    sourceRef: checkDreamSourceRef(input.source, input.sourceRef),
    direction: input.direction,
    unit: unit.isEmpty ? null : unit,
    startValue: input.startValue,
    startDate: _dateOrNull(input.startDate, 'startDate'),
    targetValue: input.targetValue,
    targetDate: _dateOrNull(input.targetDate, 'targetDate'),
    manualValue: input.manualValue,
    manualAt: input.manualValue != null ? (input.manualAt ?? now) : null,
    sortOrder: input.sortOrder < 0 ? 0 : input.sortOrder,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );
  return metric;
}

/// Validated `dreamCategories` row (the People category rules).
({String key, String label, String emoji}) validateDreamCategoryFields({
  required String key,
  required String label,
  required String emoji,
}) {
  final k = key.trim();
  if (!_dreamKeyRe.hasMatch(k)) {
    throw const ValidationFailure(
      'Kunci kategori: huruf kecil, angka, _ (maks 40)',
      field: 'key',
    );
  }
  return (
    key: k,
    label: _required(label, dreamCategoryLabelMax, 'Nama kategori', 'label'),
    emoji: _required(emoji, dreamCategoryEmojiMax, 'Emoji', 'emoji'),
  );
}

/// Validated `dreamFields` row (the People field-def rules).
({String key, String label, List<String>? options, List<String>? appliesTo})
validateDreamFieldFields({
  required String key,
  required String label,
  DreamFieldType type = DreamFieldType.text,
  List<String>? options,
  List<String>? appliesTo,
}) {
  final k = key.trim();
  if (!_dreamKeyRe.hasMatch(k)) {
    throw const ValidationFailure(
      'Kunci kolom: huruf kecil, angka, _ (maks 40)',
      field: 'key',
    );
  }
  final cleanOptions = options == null
      ? null
      : [
          for (final o in options)
            if (o.trim().isNotEmpty) o.trim(),
        ];
  if (type == DreamFieldType.select) {
    if (cleanOptions == null || cleanOptions.isEmpty) {
      throw const ValidationFailure('Pilihan wajib diisi', field: 'options');
    }
    if (cleanOptions.length > dreamFieldOptionsMax ||
        cleanOptions.any((o) => o.length > dreamFieldOptionMax)) {
      throw const ValidationFailure(
        'Pilihan terlalu banyak / panjang',
        field: 'options',
      );
    }
  }
  return (
    key: k,
    label: _required(label, dreamFieldLabelMax, 'Label kolom', 'label'),
    options: type == DreamFieldType.select ? cleanOptions : null,
    appliesTo: (appliesTo == null || appliesTo.isEmpty) ? null : appliesTo,
  );
}

// ---------------------------------------------------------------- metric math

/// Progress 0–100 (integer) from start → target given the current value; null
/// when it can't be known.
int? metricProgressPct({
  required double? start,
  required double target,
  required MetricDirection direction,
  required double? current,
}) {
  if (current == null || !current.isFinite) return null;
  if (metricReached(direction, target, current)) return 100;
  if (start == null || !start.isFinite) return null;
  if (start == target) return 0;
  // Start on the wrong side of the target for the direction: no travel.
  if (direction == MetricDirection.down ? start < target : start > target) {
    return 0;
  }
  final pct = ((current - start) / (target - start)) * 100;
  return pct.clamp(0, 100).round();
}

/// Whether [current] has reached / crossed [target] in [direction].
bool metricReached(MetricDirection direction, double target, double current) =>
    direction == MetricDirection.down ? current <= target : current >= target;

/// One reading of a metric's history.
final class DreamTrendPoint {
  const DreamTrendPoint({required this.at, required this.value});

  /// Epoch milliseconds.
  final int at;
  final double value;
}

/// The fitted line of a trend.
final class DreamTrendFit {
  const DreamTrendFit({
    required this.slopePerDay,
    required this.n,
    required this.intercept,
    required this.t0,
  });

  final double slopePerDay;
  final int n;
  final double intercept;
  final int t0;

  double valueAt(int ms) => intercept + slopePerDay * ((ms - t0) / 86400000);
}

/// Least-squares trend over the last [dreamTrendDays] days. Needs
/// [dreamTrendMinPoints] points spanning [dreamTrendMinSpanDays] days,
/// otherwise null.
DreamTrendFit? fitTrend(List<DreamTrendPoint> points, int nowMs) {
  final from = nowMs - dreamTrendDays * 86400000;
  final pts =
      points
          .where(
            (p) => p.at >= from && p.at <= nowMs + 86400000 && p.value.isFinite,
          )
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
  if (pts.length < dreamTrendMinPoints) return null;
  final t0 = pts.first.at;
  if ((pts.last.at - t0) / 86400000 < dreamTrendMinSpanDays) return null;
  final xs = [for (final p in pts) (p.at - t0) / 86400000];
  final ys = [for (final p in pts) p.value];
  final n = pts.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0;
  var sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx == 0) return null;
  final slope = sxy / sxx;
  return DreamTrendFit(
    slopePerDay: slope,
    n: n,
    intercept: my - slope * mx,
    t0: t0,
  );
}

/// The date the trend line reaches [target] (`YYYY-MM-DD`), or null: no usable
/// trend, the trend moves away from the target, or more than 10 years out.
/// When the line already passed the target, it is "today".
String? projectDate(
  List<DreamTrendPoint> points,
  double target,
  MetricDirection direction,
  int nowMs,
) {
  final t = fitTrend(points, nowMs);
  if (t == null || t.slopePerDay.abs() < 1e-9) return null;
  if (direction == MetricDirection.down
      ? t.slopePerDay >= 0
      : t.slopePerDay <= 0) {
    return null;
  }
  final nowV = t.valueAt(nowMs);
  final days = ((target - nowV) / t.slopePerDay).clamp(0, double.infinity);
  if (!days.isFinite || days > dreamMaxProjectionDays) return null;
  return _keyFromMs(nowMs + days.ceil() * 86400000);
}

/// Projection for a metric that grows at a known constant [ratePerDay] (an
/// ongoing streak): today + remaining / rate.
String? projectLinear(
  double current,
  double target,
  double ratePerDay,
  String todayKey,
) {
  if (!(ratePerDay > 0) || current >= target) return null;
  final days = ((target - current) / ratePerDay).ceil();
  return days > dreamMaxProjectionDays ? null : addDreamDays(todayKey, days);
}

/// The definition of a metric that [computeMetric] needs.
final class DreamMetricSpec {
  const DreamMetricSpec({
    required this.direction,
    required this.startValue,
    required this.targetValue,
    this.targetDate,
  });

  final MetricDirection direction;
  final double? startValue;
  final double targetValue;
  final String? targetDate;
}

/// What the server knows about a metric right now.
final class DreamMetricSample {
  const DreamMetricSample({
    this.currentValue,
    this.currentAt,
    this.points = const [],
    this.defaultStart,
    this.ratePerDay,
    this.unavailable,
  });

  final double? currentValue;

  /// Epoch milliseconds of the reading.
  final int? currentAt;
  final List<DreamTrendPoint> points;

  /// Start used when the metric has no `startValue`.
  final double? defaultStart;

  /// Constant growth per day (ongoing streaks): a deterministic projection.
  final double? ratePerDay;
  final MetricUnavailable? unavailable;
}

/// Combines a metric's definition with a sample: progress %, projected date
/// and on-track. [onTrack] is true when already reached or projected on/before
/// the target date (the metric's, else [fallbackTargetDate]); false when
/// projected after it or when the date passed unreached; null when unknown.
DreamMetricReading computeMetric(
  DreamMetricSpec spec,
  DreamMetricSample sample,
  int nowMs,
  String today, {
  String? fallbackTargetDate,
}) {
  final unavailable =
      sample.unavailable ??
      (sample.currentValue == null ? MetricUnavailable.noData : null);
  final current = sample.currentValue;
  if (current == null || unavailable != null) {
    return DreamMetricReading(
      unavailable: unavailable ?? MetricUnavailable.noData,
    );
  }
  final start = spec.startValue ?? sample.defaultStart;
  final progress = metricProgressPct(
    start: start,
    target: spec.targetValue,
    direction: spec.direction,
    current: current,
  );
  final reached = metricReached(spec.direction, spec.targetValue, current);
  String? projected;
  if (!reached) {
    projected = sample.ratePerDay != null
        ? projectLinear(current, spec.targetValue, sample.ratePerDay!, today)
        : projectDate(sample.points, spec.targetValue, spec.direction, nowMs);
  }
  final target = spec.targetDate ?? fallbackTargetDate;
  bool? onTrack;
  if (reached) {
    onTrack = true;
  } else if (target != null) {
    if (target.compareTo(today) < 0) {
      onTrack = false;
    } else if (projected != null) {
      onTrack = projected.compareTo(target) <= 0;
    }
  }
  return DreamMetricReading(
    currentValue: current,
    currentAt: sample.currentAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            sample.currentAt!,
            isUtc: true,
          ).toLocal(),
    progressPct: progress,
    onTrack: onTrack,
    projectedDate: projected,
  );
}

// ---------------------------------------------------------------- steps

/// Ids of undone steps whose metric crossed `atValue` — to be marked done.
/// Idempotent: done steps are never returned.
List<String> stepsToAutoComplete(
  Iterable<DreamStep> steps,
  Map<String, ({MetricDirection direction, double? currentValue})> metrics,
) {
  final out = <String>[];
  for (final s in steps) {
    if (s.done || s.metricRef == null || s.atValue == null) continue;
    final m = metrics[s.metricRef];
    if (m != null &&
        m.currentValue != null &&
        metricReached(m.direction, s.atValue!, m.currentValue!)) {
      out.add(s.id);
    }
  }
  return out;
}

/// `done / total` of a checklist.
({int done, int total}) stepProgress(Iterable<DreamStep> steps) {
  var done = 0;
  var total = 0;
  for (final s in steps) {
    total++;
    if (s.done) done++;
  }
  return (done: done, total: total);
}

// ---------------------------------------------------------------- costs

double _round2(double n) => (n * 100).round() / 100;

/// Cost totals of a dream. [DreamCost.effective] is the estimate, else the sum
/// of the steps' costs (what "total estimated cost of open dreams" adds up).
DreamCost costTotals(double? costEstimate, Iterable<DreamStep> steps) {
  var total = 0.0;
  var done = 0.0;
  var withCost = 0;
  for (final s in steps) {
    final c = s.cost;
    if (c == null) continue;
    withCost++;
    total += c;
    if (s.done) done += c;
  }
  return DreamCost(
    estimate: costEstimate,
    stepsTotal: _round2(total),
    stepsDone: _round2(done),
    stepsRemaining: _round2(total - done),
    stepsWithCost: withCost,
    diff: costEstimate != null && withCost > 0
        ? _round2(costEstimate - total)
        : null,
    effective: costEstimate ?? (withCost > 0 ? _round2(total) : null),
  );
}

/// Sum of the effective costs of the open dreams (done / dropped left out).
/// [stepsOf] gives each dream's steps.
double estimatedCostOpen(
  Iterable<Dream> dreams,
  Iterable<DreamStep> Function(Dream d) stepsOf,
) {
  var sum = 0.0;
  for (final d in dreams) {
    if (!d.status.isOpen) continue;
    sum += costTotals(d.costEstimate, stepsOf(d)).effective ?? 0;
  }
  return _round2(sum);
}

// ---------------------------------------------------------------- dream-level progress

/// Overall progress: done → 100; else `progressManual`; else the mean of the
/// metrics' progress; else done/total steps; else null. onTrack: false if any
/// metric is off track, true if some are on track and none off, else null.
/// projectedDate: the latest projection among unreached metrics.
DreamProgressView dreamProgress(
  Dream dream,
  Iterable<DreamStep> steps,
  Iterable<DreamMetricReading> metrics,
) {
  final stepList = steps.toList();
  final metricList = metrics.toList();
  final prog = stepProgress(stepList);
  final pcts = [
    for (final m in metricList)
      if (m.progressPct != null) m.progressPct!,
  ];
  int? pct;
  if (dream.status == DreamStatus.done) {
    pct = 100;
  } else if (dream.progressManual != null) {
    pct = dream.progressManual;
  } else if (pcts.isNotEmpty) {
    pct = (pcts.reduce((a, b) => a + b) / pcts.length).round();
  } else if (stepList.isNotEmpty) {
    pct = (prog.done / stepList.length * 100).round();
  }
  final bool? onTrack;
  if (metricList.any((m) => m.onTrack == false)) {
    onTrack = false;
  } else if (metricList.any((m) => m.onTrack == true)) {
    onTrack = true;
  } else {
    onTrack = null;
  }
  final projected = [
    for (final m in metricList)
      if (m.projectedDate != null) m.projectedDate!,
  ]..sort();
  return DreamProgressView(
    pct: pct,
    onTrack: onTrack,
    projectedDate: projected.isEmpty ? null : projected.last,
    metricCount: metricList.length,
    stepsDone: prog.done,
    stepsTotal: prog.total,
  );
}

// ---------------------------------------------------------------- staleness, review, filters

/// Latest of several timestamps (epoch ms); 0 when none.
int lastActivityMs(Iterable<DateTime?> times) {
  var best = 0;
  for (final t in times) {
    if (t == null) continue;
    final ms = t.millisecondsSinceEpoch;
    if (ms > best) best = ms;
  }
  return best;
}

/// An open dream with no update (dream, steps, metrics, manual readings) for
/// more than [days] days.
bool isStaleDream(
  DreamStatus status,
  int lastActivity,
  int nowMs, {
  int days = dreamStaleDays,
}) => status.isOpen && nowMs - lastActivity > days * 86400000;

/// Open and the target date is before [today].
bool isOverdueDream(DreamStatus status, String? targetDate, String today) =>
    status.isOpen && targetDate != null && targetDate.compareTo(today) < 0;

/// Why a dream needs a look in the "Segarkan" review.
enum DreamReviewReason {
  stale('stale'),
  overdue('overdue'),
  offTrack('off_track');

  const DreamReviewReason(this.wire);
  final String wire;
}

/// Review reasons of an open dream (none for done / dropped ones).
List<DreamReviewReason> reviewReasons({
  required DreamStatus status,
  required String? targetDate,
  required bool stale,
  required bool? onTrack,
  required String today,
}) {
  if (!status.isOpen) return const [];
  return [
    if (stale) DreamReviewReason.stale,
    if (isOverdueDream(status, targetDate, today)) DreamReviewReason.overdue,
    if (onTrack == false) DreamReviewReason.offTrack,
  ];
}

/// A `due` filter predicate: "overdue", "soon" (open, next [dreamSoonDays]
/// days), "YYYY", "YYYY-MM" or "YYYY-MM..YYYY-MM" (the target date falls
/// inside). Throws [ValidationFailure] for anything else.
bool Function(Dream d, String today) dreamDueFilter(String due) {
  final v = due.trim();
  if (v == 'overdue') {
    return (d, today) => isOverdueDream(d.status, d.targetDate, today);
  }
  if (v == 'soon') {
    return (d, today) =>
        d.status.isOpen &&
        d.targetDate != null &&
        d.targetDate!.compareTo(today) >= 0 &&
        daysBetweenKeys(today, d.targetDate!) <= dreamSoonDays;
  }
  final m = RegExp(
    r'^(\d{4}(?:-\d{2})?)(?:\.\.(\d{4}(?:-\d{2})?))?$',
  ).firstMatch(v);
  if (m == null) {
    throw const ValidationFailure(
      'due harus overdue, soon, YYYY, YYYY-MM atau YYYY-MM..YYYY-MM',
      field: 'due',
    );
  }
  final lo = m[1]!;
  final hi = m[2] ?? m[1]!;
  return (d, today) {
    final t = d.targetDate;
    if (t == null) return false;
    return t.substring(0, lo.length).compareTo(lo) >= 0 &&
        t.substring(0, hi.length).compareTo(hi) <= 0;
  };
}

// ---------------------------------------------------------------- hierarchy

/// Whether making [parentId] the parent of [id] would create a loop
/// ([parentOf] maps a dream id to its parent id).
bool wouldCreateDreamCycle(
  String id,
  String? parentId,
  Map<String, String?> parentOf,
) {
  String? cur = parentId;
  final seen = <String>{};
  while (cur != null) {
    if (cur == id) return true;
    if (!seen.add(cur)) return true;
    cur = parentOf[cur];
  }
  return false;
}

// ---------------------------------------------------------------- lists: sort & group

/// Nearest target first; undated last.
int _byTarget(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

/// The list order: `sortOrder`, nearest target first (undated last), title.
int compareDreamsForList(Dream a, Dream b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  if (c != 0) return c;
  final t = _byTarget(a.targetDate, b.targetDate);
  if (t != 0) return t;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Nearest target first; undated last; then title.
List<Dream> sortDreamsByTarget(Iterable<Dream> dreams) =>
    [...dreams]..sort((a, b) {
      final t = _byTarget(a.targetDate, b.targetDate);
      if (t != 0) return t;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

/// Board view: every status in its declared order, empty ones included.
Map<DreamStatus, List<Dream>> groupDreamsByStatus(Iterable<Dream> dreams) {
  final out = {for (final s in DreamStatus.values) s: <Dream>[]};
  for (final d in [...dreams]..sort(compareDreamsForList)) {
    out[d.status]!.add(d);
  }
  return out;
}

/// One category section of a grouped list.
final class DreamGroup with ValueEquality {
  const DreamGroup({
    required this.key,
    required this.label,
    required this.emoji,
    required this.dreams,
  });

  final String key;
  final String label;
  final String emoji;
  final List<Dream> dreams;

  @override
  List<Object?> get props => [key, label, emoji, dreams];
}

/// Category sections in category order (sort order, then label). Dreams of an
/// unknown category are grouped under `other`.
List<DreamGroup> groupDreamsByCategory(
  Iterable<Dream> dreams,
  Iterable<DreamCategory> categories,
) {
  final cats = [...categories]
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
  final known = {for (final c in cats) c.key};
  final buckets = <String, List<Dream>>{};
  for (final d in dreams) {
    final key = known.contains(d.category) ? d.category : 'other';
    buckets.putIfAbsent(key, () => []).add(d);
  }
  return [
    for (final c in cats)
      if (buckets.containsKey(c.key))
        DreamGroup(
          key: c.key,
          label: c.label,
          emoji: c.emoji,
          dreams: [...buckets[c.key]!]..sort(compareDreamsForList),
        ),
  ];
}

/// Timeline bucket of a dream: horizon first (someday / ongoing), else the
/// target year (plus quarter), else `undated`.
String timelineKey({
  required DreamHorizon? horizon,
  required String? targetDate,
  required TargetPrecision precision,
}) {
  if (targetDate != null && isDreamDateKey(targetDate)) {
    final p = targetDate.split('-').map(int.parse).toList();
    return precision == TargetPrecision.year
        ? '${p[0]}'
        : '${p[0]}-Q${((p[1] + 2) ~/ 3)}';
  }
  return horizon?.wire ?? 'undated';
}
