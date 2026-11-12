import 'dart:convert';

/// A message from another Claude session that reached this one as a user
/// prompt (`<teammate-message …>`). Ported from `web/js/teammate.js`: pure
/// text work, no UI.
class TeammateMsg {
  const TeammateMsg({
    required this.from,
    required this.color,
    required this.summary,
    required this.body,
    required this.kind,
  });

  final String from;

  /// Color name from the tag (`blue`, `green`, …); empty when absent.
  final String color;
  final String summary;
  final String body;

  /// "pesan", "selesai", "minta berhenti", "berhenti", "tugas baru", or the
  /// type of an unknown JSON message with underscores turned into spaces.
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is TeammateMsg &&
      other.from == from &&
      other.color == color &&
      other.summary == summary &&
      other.body == body &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(from, color, summary, body, kind);

  @override
  String toString() => 'TeammateMsg($from, $kind, $summary)';
}

final _msgRe = RegExp(
  r'<teammate-message([^>]*)>([\s\S]*?)(?:</teammate-message>|$)',
);
final _attrRe = RegExp(r'([\w-]+)="([^"]*)"');

const _kinds = {
  'idle_notification': 'selesai',
  'shutdown_request': 'minta berhenti',
  'shutdown_response': 'berhenti',
  'task_assignment': 'tugas baru',
};

/// The messages in [text], or null when it is not an inter-session message.
List<TeammateMsg>? teammateMsgs(String? text) {
  final t = text ?? '';
  if (!t.contains('<teammate-message')) return null;
  final out = <TeammateMsg>[];
  for (final m in _msgRe.allMatches(t)) {
    final attrs = {
      for (final a in _attrRe.allMatches(m.group(1) ?? ''))
        a.group(1)!: a.group(2)!,
    };
    final raw = (m.group(2) ?? '').trim();
    var from = _or(attrs['teammate_id'], 'sesi lain');
    var summary = attrs['summary'] ?? '';
    var body = raw;
    var kind = 'pesan';
    if (raw.startsWith('{')) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) {
          from = _or(d['from'], from);
          final type = d['type'];
          kind =
              _kinds['$type'] ??
              (_truthy(type) ? '$type'.replaceAll('_', ' ') : kind);
          summary = _or(d['summary'], summary);
          final b = d['result'] ?? d['message'] ?? d['content'] ?? d['text'];
          body = b == null
              ? ''
              : b is String
              ? b
              : const JsonEncoder.withIndent('  ').convert(b);
        }
      } catch (_) {
        // not whole JSON (e.g. cut off): show it as it is
      }
    }
    body = body.trim();
    // no summary: the first line of the body is the preview, without markdown marks
    if (summary.isEmpty && body.isNotEmpty) {
      final line = body
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      final clean = line
          .replaceFirst(RegExp(r'^[#>*\-\s]+'), '')
          .replaceAll(RegExp(r'[*_`]'), '');
      summary = clean.length > 160 ? clean.substring(0, 160) : clean;
    }
    out.add(
      TeammateMsg(
        from: from,
        color: attrs['color'] ?? '',
        summary: summary,
        body: body,
        kind: kind,
      ),
    );
  }
  return out.isEmpty ? null : out;
}

bool _truthy(Object? v) => v != null && v != '' && v != false && v != 0;

/// [v] as text when it is set, else [fallback] (JS `v || fallback`).
String _or(Object? v, String fallback) => _truthy(v) ? '$v' : fallback;

/// The owner's own words outside the inter-session messages (e.g. a sentence
/// typed after pasting one); empty when there are none.
String teammateRest(String? text) => (text ?? '')
    .replaceAll(_msgRe, ' ')
    .replaceAll('Another Claude session sent a message:', ' ')
    .replaceAll(RegExp(r'</?pasted_content[^>]*>'), ' ')
    .replaceAll(RegExp(r'\s+\n'), '\n')
    .trim();
