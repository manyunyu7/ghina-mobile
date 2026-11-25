import 'package:flutter/widgets.dart';

/// Posisi kursor Mac (ternormalisasi) + bentuk.
@immutable
class RemoteCursorState {
  const RemoteCursorState({
    this.position = const Offset(0.5, 0.5),
    this.visible = true,
    this.shape = 'arrow',
  });

  final Offset position;
  final bool visible;
  final String shape;

  RemoteCursorState copyWith({
    Offset? position,
    bool? visible,
    String? shape,
  }) => RemoteCursorState(
    position: position ?? this.position,
    visible: visible ?? this.visible,
    shape: shape ?? this.shape,
  );
}

/// Menggabungkan posisi dari host (`cursor`) dengan prediksi lokal dari `mr`.
///
/// Selama jari bergerak, prediksi lokal dipakai (host tertinggal 1 RTT dan
/// akan membuat kursor "ditarik mundur"). Setelah diam [settle], posisi host
/// diadopsi lagi sebagai kebenaran.
class RemoteCursorModel extends ValueNotifier<RemoteCursorState> {
  RemoteCursorModel({this.settle = const Duration(milliseconds: 180)})
    : super(const RemoteCursorState());

  final Duration settle;
  final Stopwatch _sinceLocal = Stopwatch();
  bool _hasLocal = false;

  /// Prediksi: gerak relatif [dx],[dy] piksel remote.
  void predict(int dx, int dy, Size remoteSize) {
    if (remoteSize.isEmpty) return;
    final p = value.position;
    value = value.copyWith(
      position: Offset(
        (p.dx + dx / remoteSize.width).clamp(0.0, 1.0),
        (p.dy + dy / remoteSize.height).clamp(0.0, 1.0),
      ),
    );
    _hasLocal = true;
    _sinceLocal
      ..reset()
      ..start();
  }

  /// Set langsung (mis. dari `mm` mode sentuh).
  void setPosition(Offset n) => value = value.copyWith(position: n);

  /// Pesan host `cursor`.
  void fromHost(Map<String, dynamic> m) {
    final x = (m['x'] as num?)?.toDouble();
    final y = (m['y'] as num?)?.toDouble();
    final visible = m['visible'] is bool ? m['visible'] as bool : null;
    final shape = m['shape'] is String ? m['shape'] as String : null;
    final local = _hasLocal && _sinceLocal.elapsed < settle;
    value = value.copyWith(
      position: (!local && x != null && y != null)
          ? Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0))
          : null,
      visible: visible,
      shape: shape,
    );
  }
}

/// Pelukis kursor gaya macOS (panah hitam bergaris putih, I-beam, tangan
/// disederhanakan jadi panah). Ujung kursor = titik [CustomPaint] (0,0).
class RemoteCursorPainter extends CustomPainter {
  const RemoteCursorPainter({required this.shape, this.scale = 1.0});

  final String shape;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final fill = Paint()..color = const Color(0xFF000000);
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    if (shape == 'ibeam') {
      final path = Path()
        ..moveTo(-3, -8)
        ..lineTo(3, -8)
        ..moveTo(0, -8)
        ..lineTo(0, 8)
        ..moveTo(-3, 8)
        ..lineTo(3, 8);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    } else {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 17)
        ..lineTo(4.2, 13.2)
        ..lineTo(7, 19.5)
        ..lineTo(9.8, 18.3)
        ..lineTo(7.1, 12.2)
        ..lineTo(12.5, 12.2)
        ..close();
      canvas.drawShadow(path, const Color(0xFF000000), 2, false);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RemoteCursorPainter old) =>
      old.shape != shape || old.scale != scale;
}
