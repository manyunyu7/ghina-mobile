import 'dart:math' as math;
import 'dart:ui';

import 'remote_protocol.dart';

/// How touches drive the Mac's pointer.
enum RemoteInputMode {
  /// The screen is a laptop trackpad: the pointer moves relative to the
  /// finger, a tap clicks wherever the pointer is. Default.
  trackpad,

  /// The finger is the pointer: a tap clicks right where it lands.
  direct,
}

/// Zoom/pan of the remote picture inside the session view.
///
/// Coordinates: a point `p` of the unzoomed layout is drawn at
/// `p * scale + offset`. The remote picture is fitted (contain) into [view].
class RemoteViewport {
  RemoteViewport({this.maxScale = 6});

  final double maxScale;
  Size view = Size.zero;
  Size content = const Size(16, 10);
  double scale = 1;
  Offset offset = Offset.zero;

  /// Picture rectangle at zoom 1.
  Rect get fitted {
    if (view.isEmpty || content.isEmpty) return Offset.zero & view;
    final s = math.min(
      view.width / content.width,
      view.height / content.height,
    );
    final w = content.width * s;
    final h = content.height * s;
    return Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
  }

  /// Picture rectangle as currently drawn.
  Rect get shown {
    final f = fitted;
    return Rect.fromLTWH(
      f.left * scale + offset.dx,
      f.top * scale + offset.dy,
      f.width * scale,
      f.height * scale,
    );
  }

  bool get zoomed => scale > 1.001;

  /// View point → normalized 0..1 remote coordinate (clamped).
  Offset toRemote(Offset p) {
    final r = shown;
    if (r.isEmpty) return const Offset(0.5, 0.5);
    return Offset(
      ((p.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((p.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  /// Normalized remote coordinate → view point.
  Offset fromRemote(Offset n) {
    final r = shown;
    return Offset(r.left + n.dx * r.width, r.top + n.dy * r.height);
  }

  /// Remote pixels per view dp at the current zoom, for a remote picture
  /// [remoteWidth] logical pixels wide.
  double gain(double remoteWidth) {
    final w = shown.width;
    return w <= 0 ? 1 : remoteWidth / w;
  }

  void setGeometry(Size view, Size content) {
    if (view == this.view && content == this.content) return;
    this.view = view;
    if (!content.isEmpty) this.content = content;
    _clamp();
  }

  void zoom(double factor, Offset focal) {
    final next = (scale * factor).clamp(1.0, maxScale);
    final k = next / scale;
    offset = focal - (focal - offset) * k;
    scale = next;
    _clamp();
  }

  void pan(Offset delta) {
    offset += delta;
    _clamp();
  }

  void reset() {
    scale = 1;
    offset = Offset.zero;
    _clamp();
  }

  /// Pans just enough to keep the remote point [n] at least [margin] dp from
  /// the view edges (used to follow the trackpad pointer while zoomed).
  /// Returns whether anything moved.
  bool follow(Offset n, {double margin = 48}) {
    if (!zoomed) return false;
    final p = fromRemote(n);
    var dx = 0.0;
    var dy = 0.0;
    final m = math.min(margin, math.min(view.width, view.height) / 4);
    if (p.dx < m) dx = m - p.dx;
    if (p.dx > view.width - m) dx = view.width - m - p.dx;
    if (p.dy < m) dy = m - p.dy;
    if (p.dy > view.height - m) dy = view.height - m - p.dy;
    if (dx == 0 && dy == 0) return false;
    final before = offset;
    pan(Offset(dx, dy));
    return offset != before;
  }

  void _clamp() {
    final f = fitted;
    double axis(double off, double viewLen, double start, double len) {
      final shownLen = len * scale;
      final base = start * scale;
      if (shownLen <= viewLen) return (viewLen - shownLen) / 2 - base;
      return off.clamp(viewLen - shownLen - base, -base);
    }

    offset = Offset(
      axis(offset.dx, view.width, f.left, f.width),
      axis(offset.dy, view.height, f.top, f.height),
    );
  }
}

/// What a touch sequence asks the session to do.
sealed class GestureAction {
  const GestureAction();
}

/// Send this message on the `ctl` channel.
class SendCtl extends GestureAction {
  const SendCtl(this.msg);
  final Map<String, Object?> msg;
  @override
  String toString() => 'SendCtl($msg)';
}

/// Zoom the picture by [factor] around [focal] (view coordinates).
class ZoomView extends GestureAction {
  const ZoomView(this.factor, this.focal);
  final double factor;
  final Offset focal;
}

/// Pan the picture by [delta] (view dp).
class PanView extends GestureAction {
  const PanView(this.delta);
  final Offset delta;
}

/// Light haptic tick (long-press recognized).
class Haptic extends GestureAction {
  const Haptic();
}

/// Two-finger scroll ended with speed: keep scrolling with momentum.
/// [velocity] is already in `wh` units per second (remote px, sign applied).
class ScrollFling extends GestureAction {
  const ScrollFling(this.velocity);
  final Offset velocity;
}

class _Pt {
  _Pt(this.start, this.t) : pos = start, last = start;
  final Offset start;
  final Duration t;
  Offset pos;
  Offset last;
}

enum _Phase { idle, oneDown, holdReady, moving, dragging, two, three, done }

enum _TwoKind { undecided, scroll, pinch }

/// Turns raw touch pointers into ctl messages and view changes. Pure logic
/// with injected clocks (every call takes the event time) so it can be
/// unit-tested without widgets.
///
/// Trackpad mode: one-finger move = `mr`, tap = left click (double tap =
/// double click), two-finger tap = right click, two-finger move = scroll,
/// press-and-hold then move = drag, hold and lift = right click.
/// Direct mode: tap = `mm` + click at that point, one-finger drag = mouse
/// drag, hold and lift = right click there.
/// Both: pinch = zoom the picture, three-finger move = pan the picture,
/// three-finger tap = middle click.
class RemoteGestureEngine {
  RemoteGestureEngine({
    required this.toRemote,
    required this.gain,
    this.mode = RemoteInputMode.trackpad,
  });

  /// View point → normalized remote point.
  final Offset Function(Offset view) toRemote;

  /// Remote logical px per view dp at the current zoom.
  final double Function() gain;

  RemoteInputMode mode;

  static const slop = 10.0;
  static const tapMax = Duration(milliseconds: 300);
  static const holdDelay = Duration(milliseconds: 450);
  static const multiClickWindow = Duration(milliseconds: 380);
  static const multiClickDistance = 40.0;
  static const pinchThreshold = 0.12;

  final Map<int, _Pt> _pts = {};
  _Phase _phase = _Phase.idle;
  _TwoKind _two = _TwoKind.undecided;
  Duration _phaseT = Duration.zero;
  Offset _c0 = Offset.zero;
  Offset _cLast = Offset.zero;
  double _d0 = 1;
  double _dLast = 1;
  bool _multiMoved = false;
  int? _dragId;

  Duration? _lastTapT;
  Offset? _lastTapPos;
  int _tapCount = 0;

  // recent scroll samples (time, wh delta) for momentum
  final List<(Duration, Offset)> _scrollSamples = [];
  Duration _lastMoveT = Duration.zero;

  bool get active => _pts.isNotEmpty;

  /// When [tick] should next be called (long-press detection), or null.
  Duration? get holdDeadline =>
      _phase == _Phase.oneDown ? _phaseT + holdDelay : null;

  List<GestureAction> down(int id, Offset pos, Duration t) {
    final out = <GestureAction>[];
    if (_pts.length >= 3 || _phase == _Phase.done) {
      _pts[id] = _Pt(pos, t);
      return out;
    }
    _pts[id] = _Pt(pos, t);
    switch (_pts.length) {
      case 1:
        _phase = _Phase.oneDown;
        _phaseT = t;
        _lastMoveT = t;
      case 2:
        if (_phase == _Phase.dragging) break; // extra finger while dragging
        _phase = _Phase.two;
        _two = _TwoKind.undecided;
        _startMulti(t);
      case 3:
        if (_phase == _Phase.dragging) break;
        _phase = _Phase.three;
        _startMulti(t);
    }
    return out;
  }

  List<GestureAction> move(int id, Offset pos, Duration t) {
    final p = _pts[id];
    if (p == null) return const [];
    p.last = p.pos;
    p.pos = pos;
    final out = <GestureAction>[];
    switch (_phase) {
      case _Phase.oneDown:
        if ((pos - p.start).distance > slop) {
          _phase = mode == RemoteInputMode.trackpad
              ? _Phase.moving
              : _Phase.dragging;
          if (_phase == _Phase.moving) {
            out.add(SendCtl(_relative(pos - p.start, t)));
          } else {
            _dragId = id;
            out
              ..add(
                SendCtl(
                  Ctl.moveAbs(toRemote(p.start).dx, toRemote(p.start).dy),
                ),
              )
              ..add(SendCtl(Ctl.down(RemoteButton.left)))
              ..add(SendCtl(_abs(pos)));
          }
        }
      case _Phase.holdReady:
        if ((pos - p.start).distance > slop) {
          _phase = _Phase.dragging;
          _dragId = id;
          if (mode == RemoteInputMode.trackpad) {
            out
              ..add(SendCtl(Ctl.down(RemoteButton.left)))
              ..add(SendCtl(_relative(pos - p.start, t)));
          } else {
            out
              ..add(SendCtl(_abs(p.start)))
              ..add(SendCtl(Ctl.down(RemoteButton.left)))
              ..add(SendCtl(_abs(pos)));
          }
        }
      case _Phase.moving:
        out.add(SendCtl(_relative(pos - p.last, t)));
      case _Phase.dragging:
        if (id != _dragId) break; // only the first finger drags
        out.add(
          SendCtl(
            mode == RemoteInputMode.trackpad
                ? _relative(pos - p.last, t)
                : _abs(pos),
          ),
        );
      case _Phase.two:
        out.addAll(_moveTwo(t));
      case _Phase.three:
        final c = _centroid();
        if ((c - _c0).distance > slop) _multiMoved = true;
        if (_multiMoved) out.add(PanView(c - _cLast));
        _cLast = c;
      case _Phase.idle:
      case _Phase.done:
        break;
    }
    return out;
  }

  List<GestureAction> up(int id, Duration t) {
    final p = _pts.remove(id);
    if (p == null) return const [];
    final out = <GestureAction>[];
    switch (_phase) {
      case _Phase.oneDown:
        final n = _countTap(p.pos, t);
        if (mode == RemoteInputMode.direct) out.add(SendCtl(_abs(p.pos)));
        out.add(SendCtl(Ctl.click(RemoteButton.left, n)));
        _phase = _Phase.idle;
      case _Phase.holdReady:
        if (mode == RemoteInputMode.direct) out.add(SendCtl(_abs(p.pos)));
        out.add(SendCtl(Ctl.click(RemoteButton.right)));
        _tapCount = 0;
        _phase = _Phase.idle;
      case _Phase.dragging:
        if (id == _dragId) {
          out.add(SendCtl(Ctl.up(RemoteButton.left)));
          _dragId = null;
          _phase = _pts.isEmpty ? _Phase.idle : _Phase.done;
        }
        _tapCount = 0;
      case _Phase.moving:
        _phase = _Phase.idle;
        _tapCount = 0;
      case _Phase.two:
        if (_two == _TwoKind.undecided &&
            !_multiMoved &&
            t - _phaseT <= tapMax) {
          if (mode == RemoteInputMode.direct) out.add(SendCtl(_abs(_c0)));
          out.add(SendCtl(Ctl.click(RemoteButton.right)));
        } else if (_two == _TwoKind.scroll) {
          final v = _scrollVelocity(t);
          if (v != null) out.add(ScrollFling(v));
        }
        _tapCount = 0;
        _phase = _Phase.done;
      case _Phase.three:
        if (!_multiMoved && t - _phaseT <= tapMax) {
          if (mode == RemoteInputMode.direct) out.add(SendCtl(_abs(_c0)));
          out.add(SendCtl(Ctl.click(RemoteButton.middle)));
        }
        _tapCount = 0;
        _phase = _Phase.done;
      case _Phase.idle:
      case _Phase.done:
        break;
    }
    if (_pts.isEmpty) _phase = _Phase.idle;
    return out;
  }

  /// Pointer cancelled by the system: never leave a button pressed.
  List<GestureAction> cancel(int id) {
    final had = _pts.remove(id) != null;
    final out = <GestureAction>[];
    if (had && _phase == _Phase.dragging && id == _dragId) {
      _dragId = null;
      out.add(SendCtl(Ctl.up(RemoteButton.left)));
      _phase = _pts.isEmpty ? _Phase.idle : _Phase.done;
    }
    if (_pts.isEmpty) _phase = _Phase.idle;
    return out;
  }

  /// Call around [holdDeadline]; recognizes press-and-hold.
  List<GestureAction> tick(Duration t) {
    if (_phase == _Phase.oneDown && t - _phaseT >= holdDelay) {
      _phase = _Phase.holdReady;
      return const [Haptic()];
    }
    return const [];
  }

  /// Drops all touches (mode switch, session reset), releasing a drag.
  List<GestureAction> reset() {
    final out = <GestureAction>[];
    if (_phase == _Phase.dragging) {
      out.add(SendCtl(Ctl.up(RemoteButton.left)));
    }
    _pts.clear();
    _phase = _Phase.idle;
    _tapCount = 0;
    return out;
  }

  // -------------------------------------------------------------------------

  void _startMulti(Duration t) {
    _phaseT = t;
    _c0 = _centroid();
    _cLast = _c0;
    _d0 = math.max(_spread(), 1);
    _dLast = _d0;
    _multiMoved = false;
    _scrollSamples.clear();
  }

  List<GestureAction> _moveTwo(Duration t) {
    final out = <GestureAction>[];
    final c = _centroid();
    final d = math.max(_spread(), 1.0);
    if (_two == _TwoKind.undecided) {
      if ((d / _d0 - 1).abs() > pinchThreshold) {
        _two = _TwoKind.pinch;
        _multiMoved = true;
        _dLast = d;
        _cLast = c;
        return out;
      }
      if ((c - _c0).distance > slop) {
        _two = _TwoKind.scroll;
        _multiMoved = true;
      }
    } else if (_two == _TwoKind.scroll && (d / _d0 - 1).abs() > 0.35) {
      // fingers clearly spreading: the user wants to zoom after all
      _two = _TwoKind.pinch;
      _dLast = d;
      _cLast = c;
      return out;
    }
    switch (_two) {
      case _TwoKind.scroll:
        final delta = c - _cLast;
        final g = gain();
        // natural scrolling: fingers up = content up = scroll down (+dy)
        final wh = Offset(-delta.dx * g, -delta.dy * g);
        if (wh != Offset.zero) {
          out.add(SendCtl(Ctl.wheel(wh.dx, wh.dy)));
          _scrollSamples.add((t, wh));
          if (_scrollSamples.length > 8) _scrollSamples.removeAt(0);
        }
      case _TwoKind.pinch:
        out
          ..add(ZoomView(d / _dLast, c))
          ..add(PanView(c - _cLast));
      case _TwoKind.undecided:
        break;
    }
    _cLast = c;
    _dLast = d;
    return out;
  }

  Offset? _scrollVelocity(Duration now) {
    final recent = _scrollSamples
        .where((s) => now - s.$1 <= const Duration(milliseconds: 100))
        .toList();
    if (recent.length < 2) return null;
    final span = (now - recent.first.$1).inMicroseconds / 1e6;
    if (span <= 0) return null;
    final sum = recent.fold(Offset.zero, (a, s) => a + s.$2);
    final v = sum / math.max(span, 0.016);
    return v.distance < 300 ? null : v;
  }

  Map<String, Object?> _relative(Offset deltaDp, Duration t) {
    final dtMs = math.max((t - _lastMoveT).inMicroseconds / 1000, 1.0);
    _lastMoveT = t;
    final speed = deltaDp.distance / dtMs; // dp per ms
    final accel = (0.8 + 1.1 * speed).clamp(0.8, 3.0);
    final g = gain() * accel;
    return Ctl.moveRel(deltaDp.dx * g, deltaDp.dy * g);
  }

  Map<String, Object?> _abs(Offset viewPos) {
    final n = toRemote(viewPos);
    return Ctl.moveAbs(n.dx, n.dy);
  }

  int _countTap(Offset pos, Duration t) {
    final lastT = _lastTapT;
    final lastP = _lastTapPos;
    if (lastT != null &&
        lastP != null &&
        t - lastT <= multiClickWindow &&
        (pos - lastP).distance <= multiClickDistance &&
        _tapCount < 3) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTapT = t;
    _lastTapPos = pos;
    return _tapCount;
  }

  Offset _centroid() {
    if (_pts.isEmpty) return Offset.zero;
    var s = Offset.zero;
    for (final p in _pts.values) {
      s += p.pos;
    }
    return s / _pts.length.toDouble();
  }

  double _spread() {
    if (_pts.length < 2) return 0;
    final v = _pts.values.toList();
    return (v[0].pos - v[1].pos).distance;
  }
}
