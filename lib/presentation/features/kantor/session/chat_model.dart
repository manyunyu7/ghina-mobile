import '../../../../data/models/kantor_pratinjau.dart';
import 'attachment_model.dart';
import 'kantor_feed.dart';

class ToolCall {
  ToolCall(this.name, this.label, this.at);
  final String name;
  final String label;
  final String at;
  Json? result;

  bool get failed => result?['err'] == true;
  bool get done => result != null;
  String get resultText => '${result?['s'] ?? ''}';

  /// `mcp__server__tool` is shown as the server name, like the web chat.
  String get shortName {
    if (name == 'AskUserQuestion') return 'Bertanya';
    if (!name.startsWith('mcp__')) return name;
    final parts = name.split('__');
    return parts.length > 1 ? parts[1] : name;
  }
}

sealed class ChatEntry {
  const ChatEntry(this.at);
  final String at;
}

class UserEntry extends ChatEntry {
  const UserEntry(this.text, super.at);
  final String text;
}

class ClaudeEntry extends ChatEntry {
  const ClaudeEntry(this.text, super.at);
  final String text;
}

class AttachmentEntry extends ChatEntry {
  AttachmentEntry(this.item) : super(item.at);
  final KantorAttachment item;
}

/// An upload that has not landed in the transcript yet; always shown last.
class UploadEntry extends ChatEntry {
  const UploadEntry(this.localId, super.at);
  final String localId;
}

class ToolsEntry extends ChatEntry {
  ToolsEntry(super.at);
  final List<ToolCall> calls = [];

  /// Pictures the agent looked at during this run (`src: 'view'`).
  final List<ChatImage> images = [];
}

/// Transcript image item: `{k:'image', src:'gen'|'view'|'user', path, name, s?}`.
/// Served by `GET /api/sessions/:sid/image?path=…[&thumb=1]`.
class ChatImage {
  const ChatImage({
    required this.src,
    required this.path,
    required this.name,
    this.caption = '',
  });

  final String src;
  final String path;
  final String name;

  /// Revised prompt for generated images.
  final String caption;

  bool get generated => src == 'gen';
  bool get mine => src == 'user';
}

class ImageEntry extends ChatEntry {
  const ImageEntry(this.image, super.at);
  final ChatImage image;
}

/// A pratinjau this session sent, placed by its `createdAt`.
class PratinjauEntry extends ChatEntry {
  PratinjauEntry(this.item) : super(item.createdAt ?? '');
  final PratinjauItem item;
}

/// Flat transcript items (`user`, `text`, `tool`, `result`) into bubbles and
/// runs of tool calls; each result is paired with the oldest open call.
List<ChatEntry> buildChat(List<Json> items) {
  final out = <ChatEntry>[];
  final pending = <ToolCall>[];
  ToolsEntry? cur;
  for (final it in items) {
    final at = '${it['at'] ?? ''}';
    final s = '${it['s'] ?? ''}';
    switch (it['k']) {
      case 'tool':
        final i = s.indexOf(' ');
        final call = ToolCall(
          i < 0 ? s : s.substring(0, i),
          i < 0 ? '' : s.substring(i + 1),
          at,
        );
        cur ??= ToolsEntry(at);
        if (cur.calls.isEmpty && cur.images.isEmpty) out.add(cur);
        cur.calls.add(call);
        pending.add(call);
        final ip = readImagePath(call);
        if (ip != null &&
            ip.startsWith('/') &&
            !cur.images.any((x) => x.path == ip)) {
          cur.images.add(
            ChatImage(src: 'view', path: ip, name: ip.split('/').last),
          );
        }
      case 'result':
        if (pending.isNotEmpty) pending.removeAt(0).result = it;
      case 'image':
        final path = '${it['path'] ?? ''}';
        if (path.isEmpty) break;
        final img = ChatImage(
          src: '${it['src'] ?? ''}',
          path: path,
          name: '${it['name'] ?? ''}',
          caption: s,
        );
        if (img.src == 'view') {
          cur ??= ToolsEntry(at);
          if (cur.calls.isEmpty && cur.images.isEmpty) out.add(cur);
          if (!cur.images.any((x) => x.path == img.path)) cur.images.add(img);
        } else {
          cur = null;
          out.add(ImageEntry(img, at));
        }
      case 'user':
        cur = null;
        out.add(UserEntry(s, at));
      default:
        cur = null;
        out.add(ClaudeEntry(s, at));
    }
  }
  return out;
}

String hhmm(String at) {
  final t = DateTime.tryParse(at)?.toLocal();
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

final _imgExt = RegExp(
  r'\.(png|jpe?g|gif|webp|avif|heic|heif|bmp)$',
  caseSensitive: false,
);

/// Image a Read / view_image call opened (absolute path or, as the daemon
/// shortens Read labels, just the file name), else null.
String? readImagePath(ToolCall c) {
  if (c.name != 'Read' && c.name != 'view_image' && c.name != 'ImageView') {
    return null;
  }
  final p = c.label.trim().split('\n').first.trim();
  return _imgExt.hasMatch(p) ? p : null;
}
