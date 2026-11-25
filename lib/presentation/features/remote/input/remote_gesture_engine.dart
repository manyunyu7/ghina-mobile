import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'remote_actions.dart';
import 'remote_input_settings.dart';

/// Yang dibutuhkan mesin gestur dari tampilan (diisi [RemoteInputLayer]).
abstract class RemoteGestureViewport {
  /// Titik lokal → koordinat ternormalisasi 0..1 (memperhitungkan zoom/pan).
  Offset normalize(Offset local);

  /// Piksel remote per dp jari untuk mode trackpad (sudah dibagi zoom).
  double get trackpadPxPerDp;

  /// Pinch tampilan lokal (TIDAK dikirim ke Mac).
  void zoomView({
    required Offset focal,
    required double scaleRatio,
    required Offset pan,
  });

  /// Kursor diprediksi bergerak (mode trackpad) sebesar dx/dy piksel remote.
  void predictCursor(int dx, int dy);

  void haptic(RemoteHaptic kind);
}

enum _Phase {
  idle,

  /// 1 jari, belum jelas: ketuk / gerak / tahan.
  pending,

  /// Trackpad: 1 jari menggerakkan kursor.
  moving,

  /// Tombol kiri ditekan (md) dan jari menyeret.
  dragging,

  /// Sentuh: tahan sudah jadi klik kanan; sisa gestur diabaikan.
  consumed,

  /// ≥2 jari, belum jelas: ketuk / scroll / zoom.
  multiPending,
  scrolling,
  zooming,

  /// 3+ jari: geser tampilan yang diperbesar (tidak dikirim ke Mac).
  panning,

  /// Gestur multi-jari selesai sebagian; tunggu semua jari terangkat.
  trailing,
}

class _Ptr {
  _Ptr(this.start, this.startTs) : pos = start, last = start;
  final Offset start;
  final Duration startTs;
  Offset pos;
  Offset last;
  double maxTravel = 0;
}

/// Mesin gestur: [PointerEvent] mentah → aksi remote.
///
/// Sengaja tidak memakai gesture arena Flutter supaya jumlah jari, ketuk
/// multi-jari, tap-tap-drag, dan pembeda zoom vs scroll bisa dikendalikan
/// penuh dan diuji dengan event sintetis.
class RemoteGestureEngine {
  RemoteGestureEngine({
    required this.actions,
    required this.viewport,
    required this._mode,
    RemoteInputSettings settings = const RemoteInputSettings(),
  }) : _settings = settings,
       _accel = PointerAccelerator(
         speed: settings.pointerSpeed,
         acceleration: settings.acceleration,
       );

  final RemoteActions actions;
  final RemoteGestureViewport viewport;
  final PointerAccelerator _accel;

  InputMode _mode;
  InputMode get mode => _mode;
  set mode(InputMode m) {
    if (m == _mode) return;
    reset();
    _mode = m;
  }

  RemoteInputSettings _settings;
  RemoteInputSettings get settings => _settings;
  set settings(RemoteInputSettings s) {
    _settings = s;
    _accel
      ..speed = s.pointerSpeed
      ..acceleration = s.acceleration;
  }

  final Map<int, _Ptr> _ptrs = {};
  _Phase _phase = _Phase.idle;
  int _maxPointers = 0;
  Duration _gestureStartTs = Duration.zero;

  Timer? _longPressTimer;
  Timer? _pendingClickTimer;
  Timer? _inertiaTimer;

  /// Ketukan pertama yang kliknya masih ditunda (menunggu ketuk ganda).
  Offset? _lastTapPos;

  /// true bila jari sekarang adalah ketukan ke-2 dalam jendela ketuk ganda.
  bool _secondTap = false;

  // Multi-jari.
  Offset _c0 = Offset.zero;
  double _spread0 = 0;
  Offset _lastCentroid = Offset.zero;
  double _lastSpread = 0;
  Offset _scrollVel = Offset.zero; // dp/ms
  Duration? _lastScrollTs;

  bool get isIdle => _phase == _Phase.idle && _ptrs.isEmpty;

  /// Batalkan gestur berjalan dengan aman (lepas tombol bila sedang drag).
  void reset() {
    if (_phase == _Phase.dragging) actions.buttonUp(0);
    _flushPendingClick();
    _cancelTimers();
    _ptrs.clear();
    _phase = _Phase.idle;
    _secondTap = false;
    _lastTapPos = null;
    _accel.reset();
  }

  void dispose() {
    reset();
    _inertiaTimer?.cancel();
  }

  void _cancelTimers() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _inertiaTimer?.cancel();
    _inertiaTimer = null;
  }

  void handle(PointerEvent e) {
    switch (e) {
      case PointerDownEvent():
        _onDown(e);
      case PointerMoveEvent():
        _onMove(e);
      case PointerUpEvent():
        _onUp(e, cancelled: false);
      case PointerCancelEvent():
        _onUp(e, cancelled: true);
      default:
        break;
    }
  }

  // ---------------------------------------------------------------- down

  void _onDown(PointerDownEvent e) {
    _inertiaTimer?.cancel();
    _inertiaTimer = null;
    _ptrs[e.pointer] = _Ptr(e.localPosition, e.timeStamp);

    if (_ptrs.length == 1) {
      _maxPointers = 1;
      _gestureStartTs = e.timeStamp;
      _phase = _Phase.pending;
      _accel.reset();
      final lastTap = _lastTapPos;
      _secondTap =
          _pendingClickTimer != null &&
          lastTap != null &&
          (lastTap - e.localPosition).distance <= _settings.doubleTapSlop;
      if (_secondTap) {
        // Klik pertama ditahan: nanti jadi klik ganda, drag, atau dikirim.
        _pendingClickTimer?.cancel();
        _pendingClickTimer = null;
      } else {
        _flushPendingClick();
      }
      final delay = _mode == InputMode.trackpad
          ? _settings.longPressDelay
          : _settings.touchLongPressDelay;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(delay, _onLongPress);
      return;
    }

    _maxPointers = math.max(_maxPointers, _ptrs.length);
    switch (_phase) {
      case _Phase.pending:
      case _Phase.moving:
      case _Phase.multiPending:
        _longPressTimer?.cancel();
        _longPressTimer = null;
        _releaseOwedFirstTap();
        _phase = _Phase.multiPending;
        _resetMultiBaseline();
      case _Phase.scrolling:
      case _Phase.zooming:
      case _Phase.panning:
        _resetMultiBaseline(keepOrigin: true);
      default:
        // dragging / consumed / trailing: jari tambahan diabaikan.
        break;
    }
  }

  // ---------------------------------------------------------------- move

  void _onMove(PointerMoveEvent e) {
    final p = _ptrs[e.pointer];
    if (p == null) return;
    p.last = p.pos;
    p.pos = e.localPosition;
    p.maxTravel = math.max(p.maxTravel, (p.pos - p.start).distance);

    switch (_phase) {
      case _Phase.pending:
        if (p.maxTravel <= _settings.tapSlop) return;
        _longPressTimer?.cancel();
        _longPressTimer = null;
        if (_mode == InputMode.trackpad) {
          if (_secondTap) {
            _secondTap = false;
            _startDrag(); // ketuk-ketuk-geser
          } else {
            _phase = _Phase.moving;
          }
          _relative(p.pos - p.start, e.timeStamp);
        } else {
          _releaseOwedFirstTap();
          actions.moveAbs(viewport.normalize(p.start));
          _startDrag();
          actions.moveAbs(viewport.normalize(p.pos));
        }
      case _Phase.moving:
        _relative(p.pos - p.last, e.timeStamp);
      case _Phase.dragging:
        if (_mode == InputMode.trackpad) {
          _relative(p.pos - p.last, e.timeStamp);
        } else {
          actions.moveAbs(viewport.normalize(p.pos));
        }
      case _Phase.multiPending:
        _decideMulti(e.timeStamp);
      case _Phase.scrolling:
        _scroll(e.timeStamp);
      case _Phase.zooming:
        _zoom();
      case _Phase.panning:
        _pan();
      default:
        break;
    }
  }

  void _relative(Offset deltaDp, Duration ts) {
    final (dx, dy) = _accel.apply(deltaDp, ts, viewport.trackpadPxPerDp);
    if (dx == 0 && dy == 0) return;
    actions.moveRel(dx, dy);
    viewport.predictCursor(dx, dy);
  }

  void _startDrag() {
    _phase = _Phase.dragging;
    actions.buttonDown(0);
    _haptic(RemoteHaptic.heavy);
  }

  // ----------------------------------------------------------- multi-finger

  Offset _centroid() {
    var sum = Offset.zero;
    for (final p in _ptrs.values) {
      sum += p.pos;
    }
    return sum / _ptrs.length.toDouble();
  }

  double _spread(Offset c) {
    if (_ptrs.length < 2) return 0;
    var sum = 0.0;
    for (final p in _ptrs.values) {
      sum += (p.pos - c).distance;
    }
    return sum / _ptrs.length;
  }

  void _resetMultiBaseline({bool keepOrigin = false}) {
    final c = _centroid();
    final s = _spread(c);
    if (!keepOrigin) {
      _c0 = c;
      _spread0 = s;
    }
    _lastCentroid = c;
    _lastSpread = s;
  }

  void _decideMulti(Duration ts) {
    if (_ptrs.length < 2) return;
    final c = _centroid();
    final s = _spread(c);
    final ratio = _spread0 > 1 ? s / _spread0 : 1.0;
    if (_settings.allowZoom &&
        _ptrs.length == 2 &&
        (ratio - 1).abs() > _settings.zoomThreshold) {
      _phase = _Phase.zooming;
      // Mulai relatif dari titik awal supaya zoom terasa langsung.
      _lastCentroid = _c0;
      _lastSpread = _spread0;
      _zoom();
      return;
    }
    if ((c - _c0).distance > _settings.scrollSlop) {
      if (_ptrs.length != 2) {
        // 3+ jari menggeser: geser tampilan (berguna saat diperbesar).
        _phase = _settings.allowZoom ? _Phase.panning : _Phase.trailing;
        _lastCentroid = _c0;
        if (_phase == _Phase.panning) _pan();
        return;
      }
      _phase = _Phase.scrolling;
      _scrollVel = Offset.zero;
      _lastScrollTs = ts;
      _lastCentroid = c;
    }
  }

  void _scroll(Duration ts) {
    if (_ptrs.length < 2) return;
    final c = _centroid();
    final delta = c - _lastCentroid;
    _lastCentroid = c;
    final last = _lastScrollTs;
    _lastScrollTs = ts;
    var dt = last == null ? 8.0 : (ts - last).inMicroseconds / 1000.0;
    if (dt <= 0) dt = 8.0;
    final inst = delta / math.min(dt, 64.0);
    _scrollVel = _scrollVel * 0.4 + inst * 0.6;
    _emitWheel(delta);
  }

  void _emitWheel(Offset fingerDelta) {
    final k = _settings.scrollSpeed * (_settings.naturalScroll ? -1.0 : 1.0);
    actions.wheel(fingerDelta.dx * k, fingerDelta.dy * k);
  }

  void _zoom() {
    if (_ptrs.length < 2) return;
    final c = _centroid();
    final s = _spread(c);
    final ratio = _lastSpread > 1 ? s / _lastSpread : 1.0;
    viewport.zoomView(
      focal: _lastCentroid,
      scaleRatio: ratio,
      pan: c - _lastCentroid,
    );
    _lastCentroid = c;
    _lastSpread = s;
  }

  void _pan() {
    if (_ptrs.length < 2) return;
    final c = _centroid();
    viewport.zoomView(focal: c, scaleRatio: 1.0, pan: c - _lastCentroid);
    _lastCentroid = c;
  }

  void _startInertia(Duration liftTs) {
    if (!_settings.scrollInertia) return;
    final last = _lastScrollTs;
    // Jari sudah berhenti sebelum diangkat → tanpa luncuran.
    if (last != null && (liftTs - last).inMilliseconds > 80) return;
    var v = _scrollVel;
    if (v.distance < 0.25) return;
    const tick = Duration(milliseconds: 16);
    var elapsed = 0;
    _inertiaTimer?.cancel();
    _inertiaTimer = Timer.periodic(tick, (t) {
      elapsed += 16;
      v = v * 0.93;
      if (v.distance < 0.03 || elapsed > 2500) {
        t.cancel();
        if (identical(_inertiaTimer, t)) _inertiaTimer = null;
        return;
      }
      _emitWheel(v * 16.0);
    });
  }

  bool get isCoasting => _inertiaTimer != null;

  // ------------------------------------------------------------------ up

  void _onUp(PointerEvent e, {required bool cancelled}) {
    final p = _ptrs.remove(e.pointer);
    if (p == null) return;

    if (_ptrs.isNotEmpty) {
      switch (_phase) {
        case _Phase.scrolling:
          if (!cancelled) _startInertia(e.timeStamp);
          _phase = _Phase.trailing;
        case _Phase.zooming:
        case _Phase.panning:
          _phase = _Phase.trailing;
        case _Phase.multiPending:
          _resetMultiBaseline(keepOrigin: true);
        default:
          break;
      }
      return;
    }

    // Semua jari terangkat.
    _longPressTimer?.cancel();
    _longPressTimer = null;
    final duration = e.timeStamp - _gestureStartTs;
    final phase = _phase;
    _phase = _Phase.idle;

    if (cancelled) {
      if (phase == _Phase.dragging) actions.buttonUp(0);
      _secondTap = false;
      return;
    }

    switch (phase) {
      case _Phase.pending:
        _onTap(p.start);
      case _Phase.dragging:
        actions.buttonUp(0);
      case _Phase.multiPending:
        final quick = duration <= const Duration(milliseconds: 350);
        if (quick && _maxPointers >= 2) {
          final button = _maxPointers == 2 ? 1 : 2;
          if (_mode == InputMode.touch) {
            actions.moveAbs(viewport.normalize(_c0));
          }
          actions.click(button);
          _haptic(RemoteHaptic.click);
        }
      case _Phase.scrolling:
        _startInertia(e.timeStamp);
      default:
        break;
    }
    _secondTap = false;
  }

  void _onTap(Offset pos) {
    if (_secondTap) {
      _secondTap = false;
      _lastTapPos = null;
      if (_mode == InputMode.touch) actions.moveAbs(viewport.normalize(pos));
      actions.click(0, n: 2);
      _haptic(RemoteHaptic.click);
      return;
    }
    if (_mode == InputMode.touch) actions.moveAbs(viewport.normalize(pos));
    _haptic(RemoteHaptic.click);
    if (_settings.doubleTapWindow <= Duration.zero) {
      actions.click(0);
      return;
    }
    _lastTapPos = pos;
    _pendingClickTimer?.cancel();
    _pendingClickTimer = Timer(_settings.doubleTapWindow, () {
      _pendingClickTimer = null;
      _lastTapPos = null;
      actions.click(0);
    });
  }

  /// Ketukan tertunda dikirim sekarang (gestur berikutnya bukan ketuk ganda).
  void _flushPendingClick() {
    final t = _pendingClickTimer;
    if (t == null) return;
    t.cancel();
    _pendingClickTimer = null;
    _lastTapPos = null;
    actions.click(0);
  }

  /// Jari kedua ternyata bukan ketuk ganda / drag: kirim klik pertama.
  void _releaseOwedFirstTap() {
    if (!_secondTap) return;
    _secondTap = false;
    _lastTapPos = null;
    actions.click(0);
  }

  void _onLongPress() {
    _longPressTimer = null;
    if (_phase != _Phase.pending || _ptrs.length != 1) return;
    final p = _ptrs.values.first;
    if (_mode == InputMode.trackpad) {
      // Tahan-lalu-geser (atau ketuk-ketuk-tahan) = drag.
      _secondTap = false;
      _lastTapPos = null;
      _accel.reset();
      _startDrag();
    } else {
      _releaseOwedFirstTap();
      actions.moveAbs(viewport.normalize(p.start));
      actions.click(1);
      _haptic(RemoteHaptic.heavy);
      _phase = _Phase.consumed;
    }
  }

  void _haptic(RemoteHaptic kind) {
    if (_settings.haptics) viewport.haptic(kind);
  }
}
