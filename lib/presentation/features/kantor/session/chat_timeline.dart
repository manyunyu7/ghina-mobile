import 'attachment_model.dart';
import 'chat_model.dart';

/// Plain text for comparing a prompt with what the daemon sent: pasted
/// content tags dropped, whitespace collapsed, a trailing ellipsis (the
/// transcript sometimes cuts long prompts) removed.
String normTimelineText(String? text) {
  final t = (text ?? '')
      .replaceAllMapped(
        RegExp(
          r'<pasted_content\b[^>]*>\n?([\s\S]*?)\n?</pasted_content\b[^>]*>',
        ),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (t.endsWith('…') ? t.substring(0, t.length - 1) : t).trim();
}

/// True when [a] and [b] are the same prompt: equal after [normTimelineText],
/// or (both longer than 20 characters) one is the start of the other.
bool sameTimelineText(String? a, String? b) {
  final x = normTimelineText(a);
  final y = normTimelineText(b);
  return x == y ||
      (x.length > 20 && y.length > 20 && (x.startsWith(y) || y.startsWith(x)));
}

/// What the owner typed for each combined attachment message the daemon typed
/// into the session (`deliverBatch`): message -> note. The last item with the
/// same message wins.
Map<String, String> batchNotes(Iterable<KantorAttachment> atts) => {
  for (final a in atts)
    if (a.message != null && a.message!.isNotEmpty) a.message!: a.note ?? '',
};

/// For a prompt [text]: null when it is not a combined attachment message,
/// otherwise the owner's own words (empty = hide it altogether, the files are
/// already cards).
String? batchNoteFor(String text, Map<String, String> batches) {
  for (final e in batches.entries) {
    if (sameTimelineText(text, e.key)) return e.value;
  }
  return null;
}

/// The transcript with combined attachment messages replaced by the owner's
/// note, or dropped when there is none. Other entries stay as they are.
List<ChatEntry> hideBatchMessages(
  List<ChatEntry> entries,
  List<KantorAttachment> atts,
) {
  final batches = batchNotes(atts);
  if (batches.isEmpty) return entries;
  return [
    for (final e in entries)
      if (e is UserEntry)
        ...switch (batchNoteFor(e.text, batches)) {
          null => [e],
          '' => const <ChatEntry>[],
          final note => [UserEntry(note, e.at)],
        }
      else
        e,
  ];
}
