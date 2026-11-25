import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'key_codes.dart';

typedef RemoteSend = void Function(Map<String, dynamic> message);

/// Pembuat pesan `ctl` (PROTOCOL.md §2) dari aksi mouse tingkat tinggi.
///
/// [takeModifiers] mengambil modifier sticky dari [RemoteKeyboardBar]
/// (sekali pakai dikonsumsi). Klik/drag dengan modifier aktif dibungkus
/// `kd <Mod>` … `ku <Mod>` karena `click`/`md` tidak punya field mods.
class RemoteActions {
  RemoteActions({required this.send, this.takeModifiers});

  RemoteSend send;
  List<RemoteModifier> Function()? takeModifiers;

  final List<RemoteModifier> _heldForDrag = [];

  void moveAbs(Offset n) =>
      send({'t': 'mm', 'x': _round(n.dx, 5), 'y': _round(n.dy, 5)});

  void moveRel(int dx, int dy) {
    if (dx == 0 && dy == 0) return;
    send({'t': 'mr', 'dx': dx, 'dy': dy});
  }

  void click(int button, {int n = 1}) {
    final mods = takeModifiers?.call() ?? const [];
    for (final m in mods) {
      send({'t': 'kd', 'code': m.code});
    }
    send({'t': 'click', 'b': button, 'n': n});
    for (final m in mods.reversed) {
      send({'t': 'ku', 'code': m.code});
    }
  }

  void buttonDown(int button) {
    final mods = takeModifiers?.call() ?? const [];
    for (final m in mods) {
      send({'t': 'kd', 'code': m.code});
    }
    _heldForDrag
      ..clear()
      ..addAll(mods);
    send({'t': 'md', 'b': button});
  }

  void buttonUp(int button) {
    send({'t': 'mu', 'b': button});
    for (final m in _heldForDrag.reversed) {
      send({'t': 'ku', 'code': m.code});
    }
    _heldForDrag.clear();
  }

  void wheel(double dx, double dy) {
    final x = _round(dx, 2);
    final y = _round(dy, 2);
    if (x == 0 && y == 0) return;
    send({'t': 'wh', 'dx': x, 'dy': y});
  }

  static double _round(double v, int digits) {
    final f = math.pow(10, digits);
    return (v * f).roundToDouble() / f;
  }
}

/// Kurva akselerasi gaya trackpad: gerak pelan presisi (< 1×), gerak cepat
/// melaju (hingga ~3×). Sisa pecahan disimpan agar gerak lambat tidak hilang.
class PointerAccelerator {
  PointerAccelerator({this.speed = 1.0, this.acceleration = 1.0});

  double speed;
  double acceleration;

  double _velocity = 0; // dp/ms, dihaluskan (EMA)
  Duration? _lastTs;
  double _remX = 0;
  double _remY = 0;

  void reset() {
    _velocity = 0;
    _lastTs = null;
    _remX = 0;
    _remY = 0;
  }

  /// Faktor kurva untuk kecepatan [v] dp/ms (tanpa [speed]).
  double curve(double v) {
    const slow = 0.55;
    const fast = 3.0;
    final raw = (slow + (v - 0.12) * 1.8).clamp(slow, fast);
    // acceleration 0 → linear 1.0; 1 → kurva penuh; >1 → dilebihkan.
    final a = acceleration.clamp(0.0, 2.0);
    return 1.0 + (raw - 1.0) * a;
  }

  /// Delta jari [delta] (dp) pada waktu [ts] → delta remote bulat.
  /// [basePxPerDp] = piksel remote per dp pada kecepatan 1×.
  (int, int) apply(Offset delta, Duration ts, double basePxPerDp) {
    final last = _lastTs;
    _lastTs = ts;
    var dtMs = last == null ? 8.0 : (ts - last).inMicroseconds / 1000.0;
    if (dtMs <= 0) dtMs = 8.0;
    if (dtMs > 100) dtMs = 100;
    final inst = delta.distance / dtMs;
    _velocity = last == null ? inst : _velocity * 0.5 + inst * 0.5;
    final gain =
        basePxPerDp * speed.clamp(0.1, 6.0) * math.max(0.05, curve(_velocity));
    final fx = delta.dx * gain + _remX;
    final fy = delta.dy * gain + _remY;
    final ix = fx.truncate();
    final iy = fy.truncate();
    _remX = fx - ix;
    _remY = fy - iy;
    return (ix, iy);
  }
}
