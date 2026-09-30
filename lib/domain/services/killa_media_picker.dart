import '../entities/killa.dart';

/// Picks files to attach to a Killa message (implemented in `data/platform/`
/// with the image picker + file picker). Photos come back re-encoded as JPEG,
/// longest side ≤ 2048 px.
abstract interface class KillaMediaPicker {
  /// Photos from the gallery (at most [max]); empty when cancelled.
  Future<List<KillaOutgoingMedia>> pickPhotos({int max = 3});

  /// One photo from the camera; null when cancelled.
  Future<KillaOutgoingMedia?> takePhoto();

  /// PDF documents (at most [max]); empty when cancelled.
  Future<List<KillaOutgoingMedia>> pickPdfs({int max = 3});
}
