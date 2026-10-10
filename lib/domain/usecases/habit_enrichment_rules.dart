/// Pure rules of the habit enrichment (`docs/habits-food-enrichment.md`,
/// port of `src/lib/habit-extras.ts`): coping tools, dimension (`habitFields`)
/// applicability and `extra` validation. The server rejects a whole row whose
/// `extra` doesn't fit, so the app validates exactly the same way before it
/// saves.
library;

import '../../core/failure.dart';
import '../entities/entities.dart';
import 'habit_rules.dart' show cleanHabitLine;

const habitToolsMax = 30;
const habitToolTitleMax = 80;
const habitToolDetailMax = 500;
const habitNotesMarkdownMax = 100000;
const habitExtraMaxKeys = 30;
const habitExtraTextMax = 500;
const habitEventLabelMax = 60;
const habitEventNoteMax = 2000;
const habitScaleDefaultMin = 1;
const habitScaleDefaultMax = 10;

/// Scopes whose dimensions show only when the def lists them explicitly (a
/// def without `appliesTo` means "every relapse / urge / event", not "every
/// check-in": the one-tap check-in stays one tap).
const habitStrictScopes = {'done', 'skip'};

/// The tools list as the server stores it: trimmed one-line titles, details
/// ≤ 500, ≤ 30 tools. Throws a `ValidationFailure(field: 'tools')`.
List<HabitTool> validateHabitTools(Iterable<HabitTool> tools) {
  final out = <HabitTool>[];
  for (final t in tools) {
    final title = cleanHabitLine(t.title);
    if (title.isEmpty) {
      throw const ValidationFailure('Judul alat wajib diisi', field: 'tools');
    }
    if (title.length > habitToolTitleMax) {
      throw const ValidationFailure(
        'Judul alat maksimal $habitToolTitleMax karakter',
        field: 'tools',
      );
    }
    final detail = t.detail.trim();
    if (detail.length > habitToolDetailMax) {
      throw const ValidationFailure(
        'Detail alat maksimal $habitToolDetailMax karakter',
        field: 'tools',
      );
    }
    out.add(HabitTool(title: title, detail: detail, kind: t.kind));
  }
  if (out.length > habitToolsMax) {
    throw const ValidationFailure(
      'Maksimal $habitToolsMax alat',
      field: 'tools',
    );
  }
  return out;
}

/// Tools grouped by kind in the declared kind order (empty groups left out).
List<({HabitToolKind kind, List<HabitTool> tools})> groupToolsByKind(
  Iterable<HabitTool> tools,
) => [
  for (final k in HabitToolKind.values)
    if (tools.any((t) => t.kind == k))
      (
        kind: k,
        tools: [
          for (final t in tools)
            if (t.kind == k) t,
        ],
      ),
];

// ---------------------------------------------------------------- dimensions

/// The defs that apply to a habit: global ones plus the habit's own.
List<HabitFieldDef> fieldsForHabit(
  Iterable<HabitFieldDef> defs,
  String habitId,
) => [
  for (final d in defs)
    if (d.habitId == null || d.habitId == habitId) d,
];

/// Whether [def] shows for [scope] (a log type wire or an event kind wire).
bool fieldAppliesTo(HabitFieldDef def, String scope) {
  final list = def.appliesTo;
  if (list == null || list.isEmpty) return !habitStrictScopes.contains(scope);
  return list.contains(scope);
}

/// The defs to render in the entry form of [scope] for [habitId].
List<HabitFieldDef> fieldsForScope(
  Iterable<HabitFieldDef> defs,
  String habitId,
  String scope,
) => [
  for (final d in fieldsForHabit(defs, habitId))
    if (fieldAppliesTo(d, scope)) d,
];

int fieldScaleMin(HabitFieldDef d) => d.min ?? habitScaleDefaultMin;
int fieldScaleMax(HabitFieldDef d) => d.max ?? habitScaleDefaultMax;

/// Null when [value] fits [def], else the server's error message.
String? checkExtraValue(HabitFieldDef def, Object? value) {
  final l = def.label;
  switch (def.type) {
    case HabitFieldType.text:
      if (value is! String) return '$l harus teks';
      final v = value.trim();
      if (v.isEmpty) return '$l tidak boleh kosong';
      if (v.length > habitExtraTextMax) {
        return '$l maksimal $habitExtraTextMax karakter';
      }
      return null;
    case HabitFieldType.number:
      return value is num && value.isFinite ? null : '$l harus angka';
    case HabitFieldType.scale:
      if (value is! num || !value.isFinite) return '$l harus angka';
      final lo = fieldScaleMin(def);
      final hi = fieldScaleMax(def);
      return value >= lo && value <= hi ? null : '$l harus $lo–$hi';
    case HabitFieldType.boolean:
      return value is bool ? null : '$l harus ya atau tidak';
    case HabitFieldType.select:
      if (value is! String) return '$l harus salah satu opsi';
      final options = def.options ?? const <String>[];
      return options.contains(value)
          ? null
          : '$l harus salah satu: ${options.join(', ')}';
  }
}

/// A whole `extra` map against [defs] (the defs that apply to the habit):
/// every key needs a def, null values are dropped, every value must fit,
/// ≤ 30 keys. Throws a `ValidationFailure(field: 'extra')`.
Map<String, Object> validateExtra(
  Map<String, Object?> extra,
  Iterable<HabitFieldDef> defs,
) {
  final byKey = {for (final d in defs) d.key: d};
  final out = <String, Object>{};
  for (final e in extra.entries) {
    final def = byKey[e.key];
    if (def == null) {
      throw ValidationFailure(
        'Dimensi "${e.key}" belum didefinisikan',
        field: 'extra',
      );
    }
    final v = e.value;
    if (v == null) continue;
    final err = checkExtraValue(def, v);
    if (err != null) throw ValidationFailure(err, field: 'extra');
    out[e.key] = v is String ? v.trim() : v;
  }
  if (out.length > habitExtraMaxKeys) {
    throw const ValidationFailure(
      'Maksimal $habitExtraMaxKeys dimensi per catatan',
      field: 'extra',
    );
  }
  return out;
}

/// [current] with [patch] applied per key (a null value removes the key).
Map<String, Object> mergeExtra(
  Map<String, Object> current,
  Map<String, Object?> patch,
) {
  final out = {...current};
  for (final e in patch.entries) {
    final v = e.value;
    if (v == null) {
      out.remove(e.key);
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

/// A value for display: `7`, `Ya`, `capek`, `7 / 10` for scales.
String formatExtraValue(HabitFieldDef def, Object value) {
  if (value is bool) return value ? 'Ya' : 'Tidak';
  if (value is num) {
    final s = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return def.type == HabitFieldType.scale ? '$s/${fieldScaleMax(def)}' : s;
  }
  return '$value';
}

/// `Label: value` chips of an `extra` map, in def order; keys without a def
/// (deleted dimension that hasn't synced yet) are left out.
List<({HabitFieldDef def, Object value})> extraEntries(
  Map<String, Object> extra,
  Iterable<HabitFieldDef> defs,
) => [
  for (final d in defs)
    if (extra[d.key] case final v?) (def: d, value: v),
];

/// Distinct `key` list of the defs a delete would strip, with how many logs
/// and events carry the key.
({int logs, int events}) fieldUsage(
  String key,
  Iterable<HabitLog> logs,
  Iterable<HabitEvent> events,
) => (
  logs: logs.where((l) => l.extra.containsKey(key)).length,
  events: events.where((e) => e.extra.containsKey(key)).length,
);

/// Validated event label (1–60, one line).
String validateEventLabel(String? raw) {
  final s = cleanHabitLine(raw);
  if (s.isEmpty) {
    throw const ValidationFailure('Judul kejadian wajib diisi', field: 'label');
  }
  if (s.length > habitEventLabelMax) {
    throw const ValidationFailure(
      'Judul maksimal $habitEventLabelMax karakter',
      field: 'label',
    );
  }
  return s;
}

/// Validated event note (≤ 2000, empty → null).
String? validateEventNote(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  if (s.length > habitEventNoteMax) {
    throw const ValidationFailure(
      'Catatan maksimal $habitEventNoteMax karakter',
      field: 'note',
    );
  }
  return s;
}
