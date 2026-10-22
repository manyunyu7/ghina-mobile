import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// What the metrics dashboard asks the daemon for. Value-equal so the family
/// provider caches per range.
class KantorMetricsQuery {
  const KantorMetricsQuery(
    this.officeId, {
    this.range = 'today',
    this.from = '',
    this.to = '',
    this.stuckHours = 3,
  });

  final String officeId;

  /// today | night | 24h | 7d | custom
  final String range;
  final String from;
  final String to;
  final int stuckHours;

  bool get global => officeId == '_kompleks';

  Map<String, dynamic> get params => {
    'range': range,
    if (range == 'custom' && from.isNotEmpty) 'from': from,
    if (range == 'custom' && to.isNotEmpty) 'to': to,
    if (stuckHours != 3) 'stuck': '$stuckHours',
  };

  String get path => global
      ? '/api/metrics'
      : '/api/offices/${Uri.encodeComponent(officeId)}/metrics';

  @override
  bool operator ==(Object other) =>
      other is KantorMetricsQuery &&
      other.officeId == officeId &&
      other.range == range &&
      other.from == from &&
      other.to == to &&
      other.stuckHours == stuckHours;

  @override
  int get hashCode => Object.hash(officeId, range, from, to, stuckHours);
}

/// `GET /api/offices/<id>/metrics` (or `/api/metrics` for the complex).
final kantorMetricsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, KantorMetricsQuery>((ref, q) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      final d = await api.get(q.path, query: q.params);
      if (d is! Map) {
        throw const KantorException(
          KantorFailure.server,
          'Jawaban metrik tidak dikenali.',
        );
      }
      return Map<String, dynamic>.from(d);
    });

/// `GET /api/offices/<id>/metrics/report`: the shift report as markdown.
Future<String> fetchKantorShiftReport(
  KantorApi api,
  KantorMetricsQuery q,
) async {
  final d = await api.get('${q.path}/report', query: q.params);
  return d is Map ? '${d['markdown'] ?? ''}' : '';
}

/// A finite number from untyped JSON, or null.
double? metricNum(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

Map<String, dynamic> metricMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

List<Map<String, dynamic>> metricRows(Object? v) => [
  for (final x in (v is List ? v : const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

/// 45 dtk / 12 mnt / 1,8 jam.
String metricDur(Object? seconds) {
  final s = metricNum(seconds);
  if (s == null) return '-';
  if (s < 90) return '${s.round()} dtk';
  if (s < 5400) return '${(s / 60).round()} mnt';
  return '${(s / 3600).toStringAsFixed(1).replaceAll('.', ',')} jam';
}

/// 1,8 jam (for values already in hours).
String metricHours(Object? h) {
  final v = metricNum(h);
  return v == null ? '-' : '${v.toString().replaceAll('.', ',')} jam';
}
