import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A file chosen to send: where it is, what to call it, its type.
class PickedAttachment {
  const PickedAttachment(this.file, this.name, this.mime);
  final File file;
  final String name;
  final String mime;
}

enum AttachSource { photos, cameraPhoto, videos, cameraVideo, document }

/// What the "+" sheet returns: the source and whether photos go as they are.
class AttachChoice {
  const AttachChoice(this.source, {required this.original});
  final AttachSource source;
  final bool original;
}

/// Photos above this are re-encoded unless "Kirim asli" is on.
const attachCompressFrom = 600 * 1024;
const attachMaxSide = 2560;

String mimeFor(String name, [List<int>? head]) =>
    lookupMimeType(name, headerBytes: head) ?? 'application/octet-stream';

/// Sheet with the sources and the "Kirim asli" switch.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  var original = false;
  return showModalBottomSheet<AttachChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget tile(IconData icon, String label, AttachSource s) => ListTile(
          key: ValueKey('attach-${s.name}'),
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.pop(ctx, AttachChoice(s, original: original)),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(
                Icons.photo_library_rounded,
                'Foto dari galeri',
                AttachSource.photos,
              ),
              tile(
                Icons.photo_camera_rounded,
                'Foto dari kamera',
                AttachSource.cameraPhoto,
              ),
              tile(
                Icons.video_library_rounded,
                'Video dari galeri',
                AttachSource.videos,
              ),
              tile(
                Icons.videocam_rounded,
                'Rekam video',
                AttachSource.cameraVideo,
              ),
              tile(
                Icons.insert_drive_file_rounded,
                'Dokumen / file lain',
                AttachSource.document,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey('attach-original'),
                value: original,
                onChanged: (v) => setState(() => original = v),
                title: const Text('Kirim asli'),
                subtitle: const Text(
                  'Foto tidak dikompres, ukuran lebih besar.',
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Opens the system picker for [choice]; empty when cancelled. Photos are
/// compressed unless [AttachChoice.original].
Future<List<PickedAttachment>> pickAttachments(AttachChoice choice) async {
  final picker = ImagePicker();
  final out = <PickedAttachment>[];
  switch (choice.source) {
    case AttachSource.photos:
      for (final x in await picker.pickMultiImage()) {
        out.add(await _photo(x.path, x.name, choice.original));
      }
    case AttachSource.cameraPhoto:
      final x = await picker.pickImage(source: ImageSource.camera);
      if (x != null) out.add(await _photo(x.path, x.name, choice.original));
    case AttachSource.videos:
      final x = await picker.pickVideo(source: ImageSource.gallery);
      if (x != null) {
        out.add(PickedAttachment(File(x.path), x.name, mimeFor(x.name)));
      }
    case AttachSource.cameraVideo:
      final x = await picker.pickVideo(source: ImageSource.camera);
      if (x != null) {
        out.add(PickedAttachment(File(x.path), x.name, mimeFor(x.name)));
      }
    case AttachSource.document:
      for (final f in await FilePicker.pickFiles()) {
        final path = f.path;
        if (path != null) {
          out.add(PickedAttachment(File(path), f.name, mimeFor(f.name)));
        }
      }
  }
  return out;
}

Future<PickedAttachment> _photo(String path, String name, bool original) async {
  final lower = name.toLowerCase();
  final keep = PickedAttachment(File(path), name, mimeFor(name));
  // GIFs lose their animation when re-encoded; PNG screenshots keep their text sharp.
  if (original || lower.endsWith('.gif') || lower.endsWith('.png')) return keep;
  try {
    if (await File(path).length() < attachCompressFrom) return keep;
    final dir = await getTemporaryDirectory();
    final target = p.join(
      dir.path,
      'kantor_pick_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final res = await FlutterImageCompress.compressAndGetFile(
      path,
      target,
      minWidth: attachMaxSide,
      minHeight: attachMaxSide,
      quality: 82,
    );
    if (res == null) return keep;
    final small = File(res.path);
    // never send a "compressed" file that grew
    if (await small.length() >= await File(path).length()) return keep;
    final base = p.basenameWithoutExtension(name);
    return PickedAttachment(
      small,
      '${base.isEmpty ? 'foto' : base}.jpg',
      'image/jpeg',
    );
  } catch (e) {
    debugPrint('kantor attach: compress failed ($e), sending the original');
    return keep;
  }
}
