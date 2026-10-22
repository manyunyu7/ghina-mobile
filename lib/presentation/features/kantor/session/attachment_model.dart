import 'chat_model.dart';
import 'kantor_feed.dart';

enum AttachmentKind { image, video, audio, file }

/// One attachment of a session, from `GET /api/sessions/:sid/attachments` or
/// the live `attachment` event. The shape is read loosely (same as the web
/// chat) because the daemon's contract may still move.
class KantorAttachment {
  const KantorAttachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.mine,
    required this.agent,
    required this.caption,
    required this.at,
    this.kindName = '',
    this.thumb,
    this.processing = false,
    this.delivered = true,
    this.duration,
  });

  final String id;
  final String name;
  final String mime;
  final int size;

  /// Sent by the owner (right side) rather than by the agent.
  final bool mine;
  final String agent;
  final String caption;

  /// ISO string, empty when the daemon gave none.
  final String at;

  /// The daemon's own `kind` (image | video | audio | file), empty if absent.
  final String kindName;

  /// Thumbnail path; null for kinds without one.
  final String? thumb;

  /// Video/audio still being probed (frames, duration) on the daemon.
  final bool processing;

  /// Owner's file: the note about it was typed into the agent session. False
  /// means it is only stored.
  final bool delivered;

  /// Seconds, for video/audio when known.
  final double? duration;

  factory KantorAttachment.fromJson(Json j) {
    final dir = '${j['dir'] ?? j['from'] ?? j['by'] ?? j['direction'] ?? ''}';
    final at = j['at'] ?? j['created_at'] ?? j['ts'];
    return KantorAttachment(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? 'file'}',
      mime: '${j['mime'] ?? ''}',
      size: (j['size'] as num?)?.toInt() ?? 0,
      mine: const ['in', 'up', 'owner', 'user', 'me'].contains(dir),
      agent: '${j['agent'] ?? j['name_agent'] ?? j['sender'] ?? ''}',
      caption: '${j['caption'] ?? ''}',
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch(
              at.toInt(),
            ).toUtc().toIso8601String()
          : '${at ?? ''}',
      kindName: '${j['kind'] ?? ''}',
      thumb: j['thumb'] is String ? j['thumb'] as String : null,
      processing: j['processing'] == true,
      delivered: j['delivered'] != false,
      duration: (j['duration'] as num?)?.toDouble(),
    );
  }

  AttachmentKind get kind {
    final k = kindName.isNotEmpty ? kindName : mime.split('/').first;
    return switch (k) {
      'image' => AttachmentKind.image,
      'video' => AttachmentKind.video,
      'audio' => AttachmentKind.audio,
      _ => AttachmentKind.file,
    };
  }

  String get rawPath => '/api/attachments/${Uri.encodeComponent(id)}/raw';
  String get thumbPath =>
      thumb ?? '/api/attachments/${Uri.encodeComponent(id)}/thumb';

  /// Images and videos have a thumbnail (a video's may still be on its way).
  bool get hasThumb =>
      kind == AttachmentKind.image ||
      (kind == AttachmentKind.video && thumb != null);

  /// "screenshot", "video", "file" for the notification text.
  String get noun => switch (kind) {
    AttachmentKind.image => 'gambar',
    AttachmentKind.video => 'video',
    AttachmentKind.audio => 'audio',
    AttachmentKind.file => 'file',
  };
}

/// Accepts a bare list or `{items: …}` / `{attachments: …}`.
List<KantorAttachment> parseAttachments(Object? data) {
  final list = data is List
      ? data
      : (data is Map ? (data['items'] ?? data['attachments']) : null);
  return [for (final j in asJsonList(list)) KantorAttachment.fromJson(j)];
}

/// Puts each attachment before the first entry that is newer than it, so
/// files read in time order with the messages. Entries without a usable time
/// keep their place; attachments without one go last.
List<ChatEntry> mergeAttachments(
  List<ChatEntry> entries,
  List<KantorAttachment> atts,
) {
  if (atts.isEmpty) return entries;
  final sorted = [...atts]
    ..sort((a, b) {
      final x = DateTime.tryParse(a.at), y = DateTime.tryParse(b.at);
      if (x == null || y == null) {
        return x == null && y == null ? 0 : (x == null ? 1 : -1);
      }
      return x.compareTo(y);
    });
  final out = <ChatEntry>[];
  var i = 0;
  for (final e in entries) {
    final t = DateTime.tryParse(e.at);
    if (t != null) {
      while (i < sorted.length) {
        final at = DateTime.tryParse(sorted[i].at);
        if (at == null || at.isAfter(t)) break;
        out.add(AttachmentEntry(sorted[i++]));
      }
    }
    out.add(e);
  }
  while (i < sorted.length) {
    out.add(AttachmentEntry(sorted[i++]));
  }
  return out;
}

String fmtSize(int n) {
  if (n >= 1073741824) return '${(n / 1073741824).toStringAsFixed(1)} GB';
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  if (n >= 1024) return '${(n / 1024).round()} KB';
  return '$n B';
}
