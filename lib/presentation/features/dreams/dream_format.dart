/// Pure text helpers of the Mimpi screens (Bahasa Indonesia, no Flutter).
/// Target dates use the domain's formatter so a quarter reads "Q1 2027".
library;

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';

/// The target as shown on cards: the date at its precision, else the horizon,
/// else "" (no target).
String dreamTargetText(Dream d) {
  final t = formatTarget(d.targetDate, d.targetPrecision);
  if (t.isNotEmpty) return t;
  return d.horizon?.label ?? '';
}

/// "Target 2027-03-31" style line for the detail screen: the date at its
/// precision, or "Belum ada target".
String dreamTargetLine(Dream d) {
  final t = dreamTargetText(d);
  return t.isEmpty ? 'Belum ada target' : t;
}

/// "Prioritas 2", or "Belum diprioritaskan".
String dreamPriorityText(int? p) =>
    p == null ? 'Belum diprioritaskan' : 'Prioritas $p';

/// Compact priority for chips and cards: "P2", or "" when unset.
String dreamPriorityShort(int? p) => p == null ? '' : 'P$p';

/// "Diperbarui hari ini / kemarin / 12 hari lalu / 4 bulan lalu".
String dreamUpdatedText(int lastMs, int nowMs) {
  final days = ((nowMs - lastMs) / 86400000).floor();
  if (days <= 0) return 'Diperbarui hari ini';
  if (days == 1) return 'Diperbarui kemarin';
  if (days < 60) return 'Diperbarui $days hari lalu';
  return 'Diperbarui ${days ~/ 30} bulan lalu';
}

/// Days until a target: "Hari ini", "Besok", "Tersisa 12 hari",
/// "Lewat 3 hari". Empty for no target.
String dreamDueText(int? days) {
  if (days == null) return '';
  if (days == 0) return 'Hari ini';
  if (days == 1) return 'Besok';
  if (days < 0) return 'Lewat ${-days} hari';
  return 'Tersisa $days hari';
}

/// A number as Indonesians write it: "72", "72,5" (never "72.0").
String dreamNumberText(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1).replaceAll('.', ',');
}

/// "72,5 kg" with the metric's unit (its own, else the source default).
String dreamMetricValueText(DreamMetric m, double v) {
  final unit = (m.unit ?? m.source.defaultUnit).trim();
  final n = dreamNumberText(v);
  return unit.isEmpty ? n : '$n $unit';
}

/// "63%" or "—" when unknown.
String dreamPercentText(int? pct) => pct == null ? '—' : '$pct%';

/// Plural-free count with its noun: "3 mimpi".
String dreamCountText(int n) => '$n mimpi';

/// The reason lines of the review queue, in Indonesian.
List<String> dreamReviewReasonTexts({
  required bool stale,
  required bool overdue,
  required bool tagged,
  bool? onTrack,
}) => [
  if (stale) 'Belum diperbarui lebih dari $dreamStaleDays hari',
  if (overdue) 'Target sudah lewat',
  if (tagged) 'Ditandai perlu ditinjau',
  if (onTrack == false) 'Metrik meleset dari jalur',
];
