import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../di/di.dart';

/// One process of the office dock (`GET /api/offices/<id>/procs`).
final class KantorProc {
  const KantorProc({
    required this.id,
    required this.room,
    required this.roomName,
    required this.name,
    required this.cmd,
    required this.status,
    required this.pending,
    required this.auto,
    required this.stopping,
    this.code,
    this.port,
    this.url,
    this.since,
  });

  factory KantorProc.fromJson(Map<String, dynamic> j) => KantorProc(
    id: '${j['id']}',
    room: '${j['room'] ?? ''}',
    roomName: '${j['roomName'] ?? j['room'] ?? ''}',
    name: '${j['name'] ?? j['cmd'] ?? ''}',
    cmd: '${j['cmd'] ?? ''}',
    status: '${j['status'] ?? 'berhenti'}',
    pending: j['pending'] == true,
    auto: j['auto'] == true,
    stopping: j['stopping'] == true,
    code: (j['code'] as num?)?.toInt(),
    port: (j['port'] as num?)?.toInt(),
    url: j['url'] as String?,
    since: DateTime.tryParse('${j['since'] ?? ''}'),
  );

  final String id, room, roomName, name, cmd;

  /// `jalan`, `berhenti` or `gagal`.
  final String status;

  /// Proposed by an agent, waiting for the owner's approval.
  final bool pending;

  /// Added from a detected suggestion rather than typed by hand.
  final bool auto;
  final bool stopping;
  final int? code, port;
  final String? url;
  final DateTime? since;

  bool get running => status == 'jalan';

  /// Who put the command in the dock.
  String get origin => pending
      ? 'Diusulkan agen'
      : auto
      ? 'Saran otomatis'
      : 'Dibuat manual';
}

/// A command the daemon found in a room's folder.
final class KantorProcSuggestion {
  const KantorProcSuggestion(this.room, this.name, this.cmd, this.why);
  final String room, name, cmd, why;
}

final class KantorProcs {
  const KantorProcs(this.procs, this.suggestions);
  final List<KantorProc> procs;
  final List<KantorProcSuggestion> suggestions;
}

/// Compact duration for a running process ("5 mnt", "2 jam 10 mnt").
String kantorDuration(DateTime? since, [DateTime? now]) {
  if (since == null) return '';
  final s = (now ?? DateTime.now()).difference(since).inSeconds;
  if (s < 60) return 'baru mulai';
  if (s < 3600) return '${s ~/ 60} mnt';
  if (s < 86400) {
    final m = (s % 3600) ~/ 60;
    return '${s ~/ 3600} jam${m > 0 ? ' $m mnt' : ''}';
  }
  return '${s ~/ 86400} hari';
}

/// Strips terminal escapes and folds carriage returns (progress bars) so the
/// daemon's raw log reads as plain text.
String kantorCleanLog(String raw) {
  var t = raw
      .replaceAll(RegExp('\x1B\\][^\x07\x1B]*(\x07|\x1B\\\\)'), '')
      .replaceAll(RegExp('\x1B\\[[0-9;?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp('\x1B[@-Z\\\\-_]'), '')
      .replaceAll('\r\n', '\n');
  if (!t.contains('\r')) return t;
  t = [
    for (final line in t.split('\n'))
      line.split('\r').lastWhere((p) => p.isNotEmpty, orElse: () => ''),
  ].join('\n');
  return t;
}

/// Processes of one office. Refetches (debounced) when the daemon pushes a
/// `proc` event for it.
final kantorProcsProvider = FutureProvider.autoDispose
    .family<KantorProcs, String>((ref, office) async {
      final api = ref.watch(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      Timer? debounce;
      ref.onDispose(() => debounce?.cancel());
      ref.listen(kantorEventsProvider, (_, next) {
        final e = next.value;
        if (e == null || e['t'] != 'proc' || e['office'] != office) return;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 300), ref.invalidateSelf);
      });
      final m = Map<String, dynamic>.from(
        await api.get('/api/offices/${Uri.encodeComponent(office)}/procs')
            as Map,
      );
      final sugg = <KantorProcSuggestion>[];
      (m['suggestions'] as Map? ?? const {}).forEach((room, list) {
        for (final s in (list as List? ?? const [])) {
          final x = Map<String, dynamic>.from(s as Map);
          sugg.add(
            KantorProcSuggestion(
              '$room',
              '${x['name'] ?? x['cmd']}',
              '${x['cmd']}',
              '${x['why'] ?? ''}',
            ),
          );
        }
      });
      return KantorProcs([
        for (final p in (m['procs'] as List? ?? const []))
          KantorProc.fromJson(Map<String, dynamic>.from(p as Map)),
      ], sugg);
    });
