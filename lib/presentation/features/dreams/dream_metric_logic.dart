/// Pure helpers of the metric cards on the Mimpi detail screen (no Flutter).
/// The core safety rule: an unknown on-track state is never shown as on track.
library;

import '../../../domain/entities/dreams.dart';

/// What the badge of a metric says.
enum MetricTrack { onTrack, offTrack, unknown }

/// `true` -> on track, `false` -> off track, `null` -> unknown. Never collapse
/// null into "on track" (or "off track").
MetricTrack metricTrackOf(bool? onTrack) => switch (onTrack) {
  true => MetricTrack.onTrack,
  false => MetricTrack.offTrack,
  null => MetricTrack.unknown,
};

/// Badge text of a [MetricTrack].
String metricTrackLabel(MetricTrack t) => switch (t) {
  MetricTrack.onTrack => 'Di jalur',
  MetricTrack.offTrack => 'Meleset',
  MetricTrack.unknown => 'Belum bisa dinilai',
};

/// Which values a metric card shows.
enum MetricValueMode {
  /// Server-computed reading (current value, progress, on-track, projection).
  computed,

  /// Offline, manual metric: the stored reading and a locally computed progress.
  storedManual,

  /// Offline, any other source: the stored target only, with a note.
  targetOnly,
}

/// Decides what a card shows. A computed reading is used only when the online
/// detail loaded and carries this metric; otherwise a manual metric falls back
/// to its stored reading and every other source to its stored target.
MetricValueMode metricValueMode({
  required bool hasOnlineReading,
  required MetricSource source,
}) {
  if (hasOnlineReading) return MetricValueMode.computed;
  return source.isManual
      ? MetricValueMode.storedManual
      : MetricValueMode.targetOnly;
}

/// The "needs internet" note: shown for [MetricValueMode.targetOnly] once the
/// online call has finished (not while it is still loading).
bool metricNeedsInternetNote(MetricValueMode mode, {required bool loading}) =>
    mode == MetricValueMode.targetOnly && !loading;

/// Result of parsing the manual-reading field.
final class ManualInput {
  const ManualInput.value(double this.value) : error = null;
  const ManualInput.error(String this.error) : value = null;

  final double? value;
  final String? error;

  bool get ok => value != null;
}

/// Parses what was typed: "72", "72,5" and "72.5" are fine; empty,
/// non-numeric and non-finite input is an error message.
ManualInput parseManualValue(String? raw) {
  final s = (raw ?? '').trim().replaceAll(' ', '');
  if (s.isEmpty) return const ManualInput.error('Isi nilainya dulu ya');
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null || !v.isFinite) {
    return const ManualInput.error('Nilai harus berupa angka');
  }
  return ManualInput.value(v);
}
