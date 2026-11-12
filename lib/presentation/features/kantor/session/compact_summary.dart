// Ringkasan otomatis saat konteks sesi penuh ("This session is being
// continued…"), dari kompaksi Claude Code atau yang ditempel pemilik.
// Port dari web/js/compact.js di Kantor; fungsi murni, dites tanpa widget.

final _phrase = RegExp(
  r'This session is being continued from a previous conversation',
);
final _head = RegExp(
  r'^\s*This session is being continued from a previous conversation',
);
final _paste = RegExp(
  r'<pasted_content[^>]*>([\s\S]*?)(?:</pasted_content[^>]*>|$)',
);
final _reminder = RegExp(r'<system-reminder>[\s\S]*?</system-reminder>');
final _summaryLine = RegExp(r'^\s*Summary:\s*$', multiLine: true);

class CompactSummary {
  const CompactSummary({
    required this.preview,
    required this.body,
    required this.rest,
  });

  /// Satu kalimat dari bagian pertama ringkasan, tanpa tanda markdown.
  final String preview;

  /// Ringkasan lengkap (markdown) tanpa pengantar dan system-reminder.
  final String body;

  /// Tulisan pemilik di luar ringkasan, mis. kalimat sebelum menempelnya.
  final String rest;
}

/// Null kalau [text] tidak memuat ringkasan kompaksi.
CompactSummary? compactSummary(String text) {
  final pos = text.indexOf(_phrase);
  if (pos < 0) return null;
  RegExpMatch? blk;
  for (final m in _paste.allMatches(text)) {
    if (m.start <= pos && pos <= m.end) {
      blk = m;
      break;
    }
  }
  final sum = blk != null ? blk.group(1)! : text.substring(pos);
  final rest =
      (blk != null
              ? text.substring(0, blk.start) + text.substring(blk.end)
              : text.substring(0, pos))
          .replaceAll(RegExp(r'</?pasted_content[^>]*>'), ' ')
          .trim();
  var body = sum.replaceAll(_reminder, '').replaceFirst(_head, '');
  final nl = body.indexOf('\n');
  body = nl < 0 ? '' : body.substring(nl + 1);
  final at = body.indexOf(_summaryLine);
  if (at >= 0) {
    body = body.substring(at).replaceFirst(RegExp(r'^\s*Summary:\s*\n'), '');
  }
  body = body.trim();
  final lines = [
    for (final l in body.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  var pick = lines.isEmpty ? '' : lines.first;
  for (var i = 1; i < lines.length; i++) {
    if (!RegExp(r'^\d+\.\s').hasMatch(lines[i])) {
      pick = lines[i];
      break;
    }
  }
  var preview = pick
      .replaceFirst(RegExp(r'^[-*#>\s]+'), '')
      .replaceAll(RegExp(r'[*_`]'), '');
  if (preview.length > 220) preview = preview.substring(0, 220);
  return CompactSummary(preview: preview, body: body, rest: rest);
}
