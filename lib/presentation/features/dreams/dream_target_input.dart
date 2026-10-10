// Pure logic of the Mimpi form (no Flutter): the target-date precision picker,
// the free-text target, amounts and the metric source reference.
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';

String _p2(int n) => n.toString().padLeft(2, '0');

/// `YYYY-MM-DD` of a calendar day.
String dreamDateKey(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

/// A calendar day of a stored key; null when it is not a real date.
DateTime? dreamKeyToDate(String? key) {
  if (key == null || !isDreamDateKey(key)) return null;
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// A period picked for a month / quarter / year target: [year] plus [index]
/// (month 1-12, quarter 1-4; unused for a year).
typedef DreamPeriod = ({int year, int index});

/// The stored target date of a picked period: always its last day
/// (Q1 2027 -> 2027-03-31, Feb 2028 -> 2028-02-29, 2027 -> 2027-12-31).
String periodTargetDate(TargetPrecision precision, DreamPeriod period) {
  final month = switch (precision) {
    TargetPrecision.day => period.index.clamp(1, 12),
    TargetPrecision.month => period.index.clamp(1, 12),
    TargetPrecision.quarter => (period.index.clamp(1, 4) - 1) * 3 + 1,
    TargetPrecision.year => 1,
  };
  return snapToPeriodEnd('${period.year}-${_p2(month)}-01', precision);
}

/// The period a stored target date falls in (the reverse of
/// [periodTargetDate]); null when [date] is not a date key.
DreamPeriod? periodOfTarget(String? date, TargetPrecision precision) {
  if (date == null || !isDreamDateKey(date)) return null;
  final p = date.split('-').map(int.parse).toList();
  return switch (precision) {
    TargetPrecision.day => (year: p[0], index: p[1]),
    TargetPrecision.month => (year: p[0], index: p[1]),
    TargetPrecision.quarter => (year: p[0], index: (p[1] + 2) ~/ 3),
    TargetPrecision.year => (year: p[0], index: 1),
  };
}

/// "Q1 2027", "Maret 2027", "2027" for a picked period.
String periodLabel(TargetPrecision precision, DreamPeriod period) =>
    formatTarget(periodTargetDate(precision, period), precision);

/// Short names for the month chips of the period picker.
const dreamMonthShort = [
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

/// Moves a stored target to another precision (keeps the period it is in).
String? resnapTarget(String? date, TargetPrecision precision) =>
    date == null || !isDreamDateKey(date)
    ? null
    : snapToPeriodEnd(date, precision);

/// Result of typing a target: the target, or [error] when not understood.
/// Blank text is "no target" (both null).
typedef DreamTargetParse = ({DreamTarget? target, String? error});

const dreamTargetNotUnderstood = 'Tidak dimengerti';

DreamTargetParse parseTargetText(String text) {
  if (text.trim().isEmpty) return (target: null, error: null);
  final t = parseFlexibleTarget(text);
  if (t == null) return (target: null, error: dreamTargetNotUnderstood);
  return (target: t, error: null);
}

/// An amount as typed in Indonesian or plain style: "1500000", "1.500.000",
/// "1.500.000,50", "Rp 2,5". Null when it is not a number; null for blank too,
/// so check blank first.
double? parseDreamAmount(String text) {
  var t = text.trim().toLowerCase().replaceAll(RegExp(r'^rp\.?\s*'), '');
  t = t.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  if (!RegExp(r'^-?[0-9.,]+$').hasMatch(t)) return null;
  if (t.contains('.') && t.contains(',')) {
    // The last separator is the decimal point.
    final decimalComma = t.lastIndexOf(',') > t.lastIndexOf('.');
    t = decimalComma
        ? t.replaceAll('.', '').replaceAll(',', '.')
        : t.replaceAll(',', '');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  } else if (RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(',', '');
  } else {
    t = t.replaceAll(',', '.');
  }
  final n = double.tryParse(t);
  return n != null && n.isFinite ? n : null;
}

/// The `sourceRef` map of a metric source from the ids the user picked
/// (`habitId` / `walletId` / `categoryId` + `period`); null when the source
/// takes none or the needed id is missing.
Map<String, Object?>? buildSourceRef(
  MetricSource source, {
  String? refId,
  SpendPeriod period = SpendPeriod.month,
}) {
  if (source.refKind == MetricRefKind.none) return null;
  if (refId == null || refId.isEmpty) return null;
  return switch (source.refKind) {
    MetricRefKind.habit => {'habitId': refId},
    MetricRefKind.wallet => {'walletId': refId},
    MetricRefKind.category => {'categoryId': refId, 'period': period.wire},
    MetricRefKind.none => null,
  };
}

/// The reverse of [buildSourceRef]: the picked id and spend period.
({String? refId, SpendPeriod period}) readSourceRef(
  MetricSource source,
  Map<String, Object?>? ref,
) {
  String? id(String k) {
    final v = ref?[k];
    return v is String && v.isNotEmpty ? v : null;
  }

  return switch (source.refKind) {
    MetricRefKind.none => (refId: null, period: SpendPeriod.month),
    MetricRefKind.habit => (refId: id('habitId'), period: SpendPeriod.month),
    MetricRefKind.wallet => (refId: id('walletId'), period: SpendPeriod.month),
    MetricRefKind.category => (
      refId: id('categoryId'),
      period: SpendPeriod.fromWire(ref?['period'] as String?),
    ),
  };
}

/// Adds [raw] to [tags] unless blank, a duplicate (case-insensitive) or the
/// list is full. A leading "#" is dropped.
List<String> addDreamTag(List<String> tags, String raw) {
  final t = raw.trim().replaceAll(RegExp(r'^#+'), '').trim();
  if (t.isEmpty || t.length > dreamTagMax || tags.length >= dreamTagsMax) {
    return tags;
  }
  if (tags.any((x) => x.toLowerCase() == t.toLowerCase())) return tags;
  return [...tags, t];
}
