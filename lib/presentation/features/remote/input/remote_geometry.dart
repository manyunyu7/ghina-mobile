import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Geometri tampilan remote: video (rasio [remoteSize]) dipasang ke
/// [viewSize] dengan [fit] (default contain, di tengah), lalu seluruh child
/// diberi [transform] (zoom/pan lokal, sama seperti InteractiveViewer).
///
/// Dipakai untuk:
///  * titik sentuh lokal → koordinat ternormalisasi 0..1 (`mm`),
///  * posisi kursor ternormalisasi → titik lokal (kursor lokal).
@immutable
class RemoteViewGeometry {
  const RemoteViewGeometry({
    required this.viewSize,
    required this.remoteSize,
    required this.transform,
    this.fit = BoxFit.contain,
  });

  final Size viewSize;
  final Size remoteSize;
  final Matrix4 transform;
  final BoxFit fit;

  /// Kotak video di koordinat child (sebelum transform).
  Rect get videoRect {
    final view = Offset.zero & viewSize;
    if (remoteSize.isEmpty || viewSize.isEmpty) return view;
    final fitted = applyBoxFit(fit, remoteSize, viewSize);
    return Alignment.center.inscribe(fitted.destination, view);
  }

  /// Titik lokal (koordinat layer, sudah termasuk transform) → 0..1.
  Offset toNormalized(Offset local) {
    final inverse = Matrix4.tryInvert(transform) ?? Matrix4.identity();
    final p = MatrixUtils.transformPoint(inverse, local);
    final r = videoRect;
    if (r.isEmpty) return Offset.zero;
    return Offset(
      ((p.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((p.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  /// 0..1 → titik lokal di layar (setelah transform).
  Offset toLocal(Offset normalized) {
    final r = videoRect;
    final p = Offset(
      r.left + normalized.dx * r.width,
      r.top + normalized.dy * r.height,
    );
    return MatrixUtils.transformPoint(transform, p);
  }

  /// Berapa piksel remote per 1 dp jari pada zoom 1×.
  double get remotePixelsPerDp {
    final r = videoRect;
    if (r.isEmpty || remoteSize.isEmpty) return 1.0;
    return remoteSize.width / r.width;
  }
}

/// Skala efektif matriks zoom (sumbu x).
double matrixScale(Matrix4 m) => m.getMaxScaleOnAxis();

/// Terapkan pinch: skala [scaleRatio] di [focal] lalu geser [pan] (semua
/// dalam koordinat layar). Hasil di-clamp ke 1..[maxScale] dan translasi
/// dijaga supaya child tetap menutupi viewport.
Matrix4 applyZoom(
  Matrix4 current, {
  required Offset focal,
  required double scaleRatio,
  required Offset pan,
  required Size viewSize,
  double maxScale = 5.0,
}) {
  final s0 = matrixScale(current);
  final target = (s0 * scaleRatio).clamp(1.0, math.max(1.0, maxScale));
  final r = target / s0;
  final step =
      Matrix4.translationValues(focal.dx + pan.dx, focal.dy + pan.dy, 0)
          .multiplied(Matrix4.diagonal3Values(r, r, 1))
          .multiplied(Matrix4.translationValues(-focal.dx, -focal.dy, 0));
  return clampPan(step.multiplied(current), viewSize);
}

/// Geser matriks [m] sebesar [delta] dp (layar), lalu clamp.
Matrix4 panBy(Matrix4 m, Offset delta, Size viewSize) {
  return clampPan(
    Matrix4.translationValues(delta.dx, delta.dy, 0).multiplied(m),
    viewSize,
  );
}

/// Pastikan child (ukuran [viewSize]) setelah transform tetap menutupi
/// viewport (tidak ada celah kosong saat diperbesar).
Matrix4 clampPan(Matrix4 m, Size viewSize) {
  final s = matrixScale(m);
  final out = m.clone();
  final minX = viewSize.width - viewSize.width * s;
  final minY = viewSize.height - viewSize.height * s;
  out.storage[12] = out.storage[12].clamp(math.min(minX, 0.0), 0.0);
  out.storage[13] = out.storage[13].clamp(math.min(minY, 0.0), 0.0);
  return out;
}
