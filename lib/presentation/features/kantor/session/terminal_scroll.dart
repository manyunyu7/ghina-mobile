import 'dart:math';

import 'package:xterm/xterm.dart';

/// Mouse handler of the Kantor terminal: makes a vertical swipe scroll the
/// tmux pane's history.
///
/// The terminal is a `tmux attach`, so it always sits in the alternate screen
/// and has no local scrollback: xterm turns a swipe into mouse-wheel reports
/// and tmux (`mouse on`) answers a wheel-up with `copy-mode -e`. But xterm
/// 4.0.0 reports the wheel as button 68/69 (64 + 4/5), which in the xterm
/// protocol is shift+wheel; tmux maps that to `S-WheelUpPane`, which has no
/// binding, so the swipe did nothing. This handler reports the real ids
/// (64/65, 66/67 sideways) and leaves every other event to xterm's handler.
///
/// It also counts the wheel-up ticks not undone yet, so [release] can bring
/// tmux back to the live end before the user types (`copy-mode -e` leaves
/// copy mode when it reaches the bottom).
class TermWheelHandler implements TerminalMouseHandler {
  TermWheelHandler([this._fallback = defaultMouseHandler]);

  final TerminalMouseHandler _fallback;

  /// Wheel-up ticks sent and not yet undone by a wheel-down.
  int get back => _back;
  int _back = 0;

  /// Wheel-down report at the position of the last wheel event.
  String? _down;

  /// Last report this handler produced, not yet claimed by [isOwn].
  String? _pending;

  @override
  String? call(TerminalMouseEvent event) {
    final out = event.button.isWheel ? _wheel(event) : _fallback(event);
    _pending = out;
    return out;
  }

  String? _wheel(TerminalMouseEvent e) {
    // wheel buttons have no release report
    if (e.buttonState != TerminalMouseButtonState.down) return null;
    switch (e.state.mouseMode) {
      case MouseMode.none:
      case MouseMode.clickOnly:
        return null; // xterm falls back to arrow keys
      case MouseMode.upDownScroll:
      case MouseMode.upDownScrollDrag:
      case MouseMode.upDownScrollMove:
        break;
    }
    final mode = e.state.mouseReportMode;
    final id = switch (e.button) {
      TerminalMouseButton.wheelUp => 64,
      TerminalMouseButton.wheelDown => 65,
      TerminalMouseButton.wheelLeft => 66,
      _ => 67,
    };
    _down = encodeMouse(65, e.position, mode);
    if (id == 64) _back++;
    if (id == 65) _back = max(0, _back - 1);
    return encodeMouse(id, e.position, mode);
  }

  /// True (once) when [data] is the report this handler just produced, so
  /// the caller can tell mouse output from typed input.
  bool isOwn(String data) {
    if (_pending == null || data != _pending) return false;
    _pending = null;
    return true;
  }

  /// Wheel-downs that undo every wheel-up sent so far, or '' when the pane
  /// is already at the live end. Resets the count.
  String release() {
    final down = _down;
    final n = _back;
    _back = 0;
    return down == null || n == 0 ? '' : down * n;
  }

  /// Forgets the scroll position, e.g. after a reconnect.
  void reset() {
    _back = 0;
    _pending = null;
  }
}

/// Mouse button press report for button [id] at the 0-based [p].
String encodeMouse(int id, CellOffset p, MouseReportMode mode) {
  final x = p.x + 1;
  final y = p.y + 1;
  switch (mode) {
    case MouseReportMode.sgr:
      return '\x1b[<$id;$x;${y}M';
    case MouseReportMode.urxvt:
      return '\x1b[${32 + id};$x;${y}M';
    case MouseReportMode.normal:
    case MouseReportMode.utf:
      final limit = mode == MouseReportMode.normal ? 223 : 2015;
      String c(int v) => v > limit ? '\x00' : String.fromCharCode(32 + v);
      return '\x1b[M${String.fromCharCode(32 + id)}${c(x)}${c(y)}';
  }
}
