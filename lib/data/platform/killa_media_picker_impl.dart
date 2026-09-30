import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/killa.dart';
import '../../domain/services/killa_media_picker.dart';

/// Longest side of a photo sent to Killa (the web composer's limit).
const killaMaxImageSide = 2048;

/// [KillaMediaPicker] on `image_picker` (photos / camera) + `file_picker`
/// (PDFs). Photos are re-encoded to JPEG (quality 85) with the longest side
/// ≤ [killaMaxImageSide] px before they are base64'd; GIFs are sent as they
/// are (keeps the animation) when small enough.
class DeviceKillaMediaPicker implements KillaMediaPicker {
  DeviceKillaMediaPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<KillaOutgoingMedia>> pickPhotos({int max = 3}) async {
    if (max < 1) return const [];
    final xs = max == 1
        ? [?await _picker.pickImage(source: ImageSource.gallery)]
        : await _picker.pickMultiImage(limit: max);
    final out = <KillaOutgoingMedia>[];
    for (final x in xs.take(max)) {
      out.add(await _prepareImage(x.path, x.name));
    }
    return out;
  }

  @override
  Future<KillaOutgoingMedia?> takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera);
    if (x == null) return null;
    return _prepareImage(x.path, x.name);
  }

  @override
  Future<List<KillaOutgoingMedia>> pickPdfs({int max = 3}) async {
    if (max < 1) return const [];
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final out = <KillaOutgoingMedia>[];
    for (final f in files.take(max)) {
      out.add(
        KillaOutgoingMedia(
          name: f.name,
          mimeType: 'application/pdf',
          bytes: await f.readAsBytes(),
        ),
      );
    }
    return out;
  }

  Future<KillaOutgoingMedia> _prepareImage(String path, String name) async {
    final original = await File(path).readAsBytes();
    final lower = name.toLowerCase();
    if (lower.endsWith('.gif') && original.length <= 8 * 1024 * 1024) {
      return KillaOutgoingMedia(
        name: name,
        mimeType: 'image/gif',
        bytes: original,
      );
    }
    final jpeg = await compressToJpeg(original);
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return KillaOutgoingMedia(
      name: '${base.isEmpty ? 'foto' : base}.jpg',
      mimeType: 'image/jpeg',
      bytes: jpeg,
    );
  }
}

/// Target for `flutter_image_compress`'s `minWidth`/`minHeight` so the
/// **longest** side ends at ≤ [maxSide] whatever the EXIF rotation: the plugin
/// scales until one side reaches its minimum, so giving both the scaled
/// short side makes the long side land on [maxSide].
int killaCompressTarget(
  int width,
  int height, {
  int maxSide = killaMaxImageSide,
}) {
  final long = math.max(width, height), short = math.min(width, height);
  if (long <= 0 || short <= 0) return (maxSide * 3) ~/ 4;
  if (long <= maxSide) return short;
  return math.max(1, (short * maxSide / long).floor());
}

/// Re-encodes [bytes] (JPEG/PNG/WebP/HEIC…) as JPEG, longest side ≤ 2048.
Future<Uint8List> compressToJpeg(Uint8List bytes) async {
  var target = (killaMaxImageSide * 3) ~/ 4;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    target = killaCompressTarget(descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
  } catch (e) {
    // Undecodable here (e.g. HEIC on some Android versions): the plugin
    // still decodes it natively; assume a 4:3 photo.
    debugPrint('killa: image size unknown ($e)');
  }
  return FlutterImageCompress.compressWithList(
    bytes,
    minWidth: target,
    minHeight: target,
    quality: 85,
    format: CompressFormat.jpeg,
  );
}

/// Off-device (tests, desktop): nothing to pick.
class NoopKillaMediaPicker implements KillaMediaPicker {
  const NoopKillaMediaPicker();

  @override
  Future<List<KillaOutgoingMedia>> pickPhotos({int max = 3}) async => const [];

  @override
  Future<KillaOutgoingMedia?> takePhoto() async => null;

  @override
  Future<List<KillaOutgoingMedia>> pickPdfs({int max = 3}) async => const [];
}
