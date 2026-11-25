import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ime_text_tracker.dart';
import 'key_codes.dart';
import 'remote_actions.dart';
import 'remote_cursor.dart';
import 'remote_geometry.dart';
import 'remote_gesture_engine.dart';
import 'remote_input_settings.dart';
import 'remote_keyboard_controller.dart';

/// Menyediakan [RemoteKeyboardController] milik [RemoteInputLayer] ke
/// turunannya (mis. [RemoteKeyboardBar] tanpa controller eksplisit).
class RemoteKeyboardScope extends InheritedNotifier<RemoteKeyboardController> {
  const RemoteKeyboardScope({
    super.key,
    required RemoteKeyboardController controller,
    required super.child,
  }) : super(notifier: controller);

  static RemoteKeyboardController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RemoteKeyboardScope>()
      ?.notifier;
}

/// Lapisan input layar remote. Membungkus [child] (video) dan mengubah
/// sentuhan, keyboard HP, keyboard fisik, dan mouse menjadi pesan `ctl`
/// (PROTOCOL.md §2) lewat [send].
///
/// Zoom/pan tampilan: layer MENERAPKAN sendiri `Transform` dari
/// [transformationController] ke [child] — inti tidak perlu membungkus child
/// dengan InteractiveViewer/Transform. Pinch 2 jari mengubah controller ini
/// (tidak dikirim ke Mac); inti boleh mereset/menganimasikannya (mis. tombol
/// "100%"). Video diasumsikan digambar dengan [fit] (default contain, di
/// tengah) di seluruh ukuran layer, rasio [remoteSize].
class RemoteInputLayer extends StatefulWidget {
  const RemoteInputLayer({
    super.key,
    required this.send,
    required this.hostMessages,
    required this.remoteSize,
    required this.mode,
    required this.child,
    this.transformationController,
    this.keyboardController,
    this.settings = const RemoteInputSettings(),
    this.fit = BoxFit.contain,
    this.autofocus = true,
    this.enabled = true,
    this.onHaptic,
  });

  /// Kirim satu pesan `ctl` (Map JSON).
  final void Function(Map<String, dynamic>) send;

  /// Pesan host → viewer yang sudah di-decode (`cursor`, `hello`, …).
  final Stream<Map<String, dynamic>> hostMessages;

  /// Ukuran display remote (w,h dari `hello`/`display`); dipakai untuk rasio
  /// video dan satuan `mr`.
  final Size remoteSize;

  final InputMode mode;

  /// Video remote.
  final Widget child;

  /// Zoom/pan tampilan lokal. Null → layer membuat sendiri.
  final TransformationController? transformationController;

  /// Status keyboard bersama dengan [RemoteKeyboardBar]. Null → layer
  /// membuat sendiri (tersedia lewat [RemoteKeyboardScope]).
  final RemoteKeyboardController? keyboardController;

  final RemoteInputSettings settings;
  final BoxFit fit;
  final bool autofocus;

  /// false: semua input diabaikan (mis. saat menyambung ulang).
  final bool enabled;

  /// Override getaran (default [HapticFeedback]); berguna untuk tes.
  final void Function(RemoteHaptic kind)? onHaptic;

  @override
  State<RemoteInputLayer> createState() => RemoteInputLayerState();
}

class RemoteInputLayerState extends State<RemoteInputLayer>
    with WidgetsBindingObserver
    implements RemoteGestureViewport {
  TransformationController? _ownTc;
  RemoteKeyboardController? _ownKb;
  late final RemoteActions _actions;
  late final RemoteGestureEngine _engine;
  final RemoteCursorModel _cursor = RemoteCursorModel();

  final FocusNode _keyFocus = FocusNode(debugLabel: 'RemoteInputLayer.keys');
  final FocusNode _textFocus = FocusNode(debugLabel: 'RemoteInputLayer.ime');
  final TextEditingController _text = TextEditingController.fromValue(
    ImeTextTracker.initialValue,
  );
  TextEditingValue _lastImeValue = ImeTextTracker.initialValue;
  bool _applyingReset = false;
  int _seenShowToken = 0;

  StreamSubscription<Map<String, dynamic>>? _hostSub;
  Size _viewSize = Size.zero;

  /// Kode W3C tombol fisik yang sedang ditekan (dilepas saat fokus hilang).
  final Set<String> _pressedKeys = {};

  /// Tombol mouse fisik yang sedang ditekan per pointer.
  final Map<int, int> _mouseButtons = {};

  TransformationController get transformation =>
      widget.transformationController ??
      (_ownTc ??= TransformationController());

  RemoteKeyboardController get keyboard =>
      widget.keyboardController ?? (_ownKb ??= RemoteKeyboardController());

  /// Model kursor lokal (untuk tes / inti).
  RemoteCursorModel get cursor => _cursor;

  RemoteViewGeometry get geometry => RemoteViewGeometry(
    viewSize: _viewSize,
    remoteSize: widget.remoteSize,
    transform: transformation.value,
    fit: widget.fit,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _actions = RemoteActions(
      send: _send,
      takeModifiers: () => keyboard.takeModifiers(),
    );
    _engine = RemoteGestureEngine(
      actions: _actions,
      viewport: this,
      mode: widget.mode,
      settings: widget.settings,
    );
    _attachKeyboard(keyboard);
    _text.addListener(_onTextChanged);
    _subscribe();
  }

  void _send(Map<String, dynamic> m) {
    if (!widget.enabled) return;
    widget.send(m);
  }

  void _attachKeyboard(RemoteKeyboardController kb) {
    kb.send = _send;
    kb.addListener(_onKeyboardChanged);
  }

  void _detachKeyboard(RemoteKeyboardController kb) {
    kb.removeListener(_onKeyboardChanged);
    kb.send = null;
  }

  void _subscribe() {
    _hostSub?.cancel();
    _hostSub = widget.hostMessages.listen(_onHostMessage);
  }

  @override
  void didUpdateWidget(RemoteInputLayer oldWidget) {
    final old = oldWidget;
    super.didUpdateWidget(old);
    if (old.hostMessages != widget.hostMessages) _subscribe();
    if (old.keyboardController != widget.keyboardController) {
      _detachKeyboard(old.keyboardController ?? _ownKb!);
      _attachKeyboard(keyboard);
    }
    _engine
      ..settings = widget.settings
      ..mode = widget.mode;
    if (!widget.enabled && old.enabled) _releaseEverything();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseEverything();
    _engine.dispose();
    _hostSub?.cancel();
    _detachKeyboard(keyboard);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _keyFocus.dispose();
    _textFocus.dispose();
    _cursor.dispose();
    _ownTc?.dispose();
    _ownKb?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------- host messages

  void _onHostMessage(Map<String, dynamic> m) {
    if (m['t'] == 'cursor') _cursor.fromHost(m);
  }

  // ---------------------------------------------------------- lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _releaseEverything();
      _send({'t': 'release'});
    }
  }

  @override
  void didChangeMetrics() {
    final view = View.maybeOf(context);
    if (view == null) return;
    keyboard.setSoftKeyboardVisible(
      view.viewInsets.bottom > 0 && _textFocus.hasFocus,
    );
  }

  void _releaseEverything() {
    _engine.reset();
    for (final code in _pressedKeys) {
      _send({'t': 'ku', 'code': code});
    }
    _pressedKeys.clear();
    for (final b in _mouseButtons.values) {
      _send({'t': 'mu', 'b': b});
    }
    _mouseButtons.clear();
  }

  // ------------------------------------------------------------ viewport

  @override
  Offset normalize(Offset local) {
    final n = geometry.toNormalized(local);
    _cursor.setPosition(n);
    return n;
  }

  @override
  double get trackpadPxPerDp =>
      geometry.remotePixelsPerDp / matrixScale(transformation.value) * 0.9;

  @override
  void zoomView({
    required Offset focal,
    required double scaleRatio,
    required Offset pan,
  }) {
    if (!widget.settings.allowZoom || _viewSize.isEmpty) return;
    transformation.value = applyZoom(
      transformation.value,
      focal: focal,
      scaleRatio: scaleRatio,
      pan: pan,
      viewSize: _viewSize,
      maxScale: widget.settings.maxZoom,
    );
  }

  @override
  void predictCursor(int dx, int dy) {
    _cursor.predict(dx, dy, widget.remoteSize);
    _keepCursorVisible();
  }

  /// Saat diperbesar di mode trackpad, geser tampilan mengikuti kursor.
  void _keepCursorVisible() {
    if (matrixScale(transformation.value) <= 1.001 || _viewSize.isEmpty) return;
    final p = geometry.toLocal(_cursor.value.position);
    const margin = 32.0;
    var dx = 0.0;
    var dy = 0.0;
    if (p.dx < margin) dx = margin - p.dx;
    if (p.dx > _viewSize.width - margin) dx = _viewSize.width - margin - p.dx;
    if (p.dy < margin) dy = margin - p.dy;
    if (p.dy > _viewSize.height - margin) dy = _viewSize.height - margin - p.dy;
    if (dx == 0 && dy == 0) return;
    transformation.value = panBy(
      transformation.value,
      Offset(dx, dy),
      _viewSize,
    );
  }

  @override
  void haptic(RemoteHaptic kind) {
    final custom = widget.onHaptic;
    if (custom != null) return custom(kind);
    switch (kind) {
      case RemoteHaptic.click:
        HapticFeedback.selectionClick();
      case RemoteHaptic.heavy:
        HapticFeedback.mediumImpact();
      case RemoteHaptic.selection:
        HapticFeedback.selectionClick();
    }
  }

  // -------------------------------------------------------------- pointer

  bool _isMouse(PointerEvent e) => e.kind == PointerDeviceKind.mouse;

  int _mouseButton(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 1;
    if (buttons & kMiddleMouseButton != 0) return 2;
    return 0;
  }

  void _onPointer(PointerEvent e) {
    if (!widget.enabled) return;
    if (_isMouse(e)) return _onMouse(e);
    _engine.handle(e);
  }

  /// Mouse fisik (Bluetooth/DeX): selalu absolut, seperti di desktop.
  void _onMouse(PointerEvent e) {
    switch (e) {
      case PointerDownEvent():
        final b = _mouseButton(e.buttons);
        _mouseButtons[e.pointer] = b;
        _actions.moveAbs(normalize(e.localPosition));
        _actions.buttonDown(b);
      case PointerMoveEvent():
        _actions.moveAbs(normalize(e.localPosition));
      case PointerUpEvent() || PointerCancelEvent():
        final b = _mouseButtons.remove(e.pointer);
        if (b != null) _actions.buttonUp(b);
      default:
        break;
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (!widget.enabled || !_isMouse(e)) return;
    _actions.moveAbs(normalize(e.localPosition));
  }

  void _onSignal(PointerSignalEvent e) {
    if (!widget.enabled) return;
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScrollEvent;
        _actions.wheel(s.scrollDelta.dx, s.scrollDelta.dy);
      });
    }
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    if (!widget.enabled) return;
    // Touchpad fisik: geser 2 jari → scroll (natural, konten ikut jari).
    final k = widget.settings.naturalScroll ? -1.0 : 1.0;
    _actions.wheel(e.localPanDelta.dx * k, e.localPanDelta.dy * k);
  }

  // ------------------------------------------------------- hardware keys

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final code = w3cCodeForKeyEvent(e);
    if (code == null) return KeyEventResult.ignored;
    switch (e) {
      case KeyDownEvent():
        _pressedKeys.add(code);
        _send({'t': 'kd', 'code': code});
      case KeyRepeatEvent():
        _send({'t': 'kd', 'code': code});
      case KeyUpEvent():
        _pressedKeys.remove(code);
        _send({'t': 'ku', 'code': code});
    }
    // Ditangani → tidak sampai ke Shortcuts Flutter (Tab pindah fokus,
    // Esc = kembali) maupun ke IME (tidak ada ketikan ganda).
    return KeyEventResult.handled;
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus) return;
    for (final code in _pressedKeys) {
      _send({'t': 'ku', 'code': code});
    }
    _pressedKeys.clear();
  }

  // ------------------------------------------------------ soft keyboard

  void _onKeyboardChanged() {
    final kb = keyboard;
    if (kb.softKeyboardRequested) {
      if (!_textFocus.hasFocus) {
        _textFocus.requestFocus();
      } else if (kb.showToken != _seenShowToken) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
      _seenShowToken = kb.showToken;
    } else if (_textFocus.hasFocus) {
      _keyFocus.requestFocus();
    }
  }

  void _onTextChanged() {
    if (_applyingReset) return;
    final v = _text.value;
    if (v.text == _lastImeValue.text &&
        v.composing == _lastImeValue.composing) {
      _lastImeValue = v;
      return;
    }
    _lastImeValue = v;
    final reset = keyboard.handleImeValue(v);
    if (reset == null) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      _applyingReset = true;
      _text.value = reset;
      _lastImeValue = reset;
      _applyingReset = false;
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        final showCursor =
            widget.mode == InputMode.trackpad &&
            widget.settings.showLocalCursor;
        return RemoteKeyboardScope(
          controller: keyboard,
          child: Focus(
            focusNode: _keyFocus,
            autofocus: widget.autofocus,
            onKeyEvent: _onKey,
            onFocusChange: _onFocusChange,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointer,
              onPointerMove: _onPointer,
              onPointerUp: _onPointer,
              onPointerCancel: _onPointer,
              onPointerHover: _onHover,
              onPointerSignal: _onSignal,
              onPointerPanZoomUpdate: _onPanZoom,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  AnimatedBuilder(
                    animation: transformation,
                    builder: (context, child) => Transform(
                      transform: transformation.value,
                      child: child,
                    ),
                    child: widget.child,
                  ),
                  if (showCursor)
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([transformation, _cursor]),
                        builder: (context, _) {
                          final c = _cursor.value;
                          return CustomPaint(
                            painter: _CursorLayerPainter(
                              at: geometry.toLocal(c.position),
                              visible: c.visible,
                              shape: c.shape,
                            ),
                          );
                        },
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 1,
                    height: 1,
                    child: IgnorePointer(
                      child: Opacity(opacity: 0, child: _hiddenField()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hiddenField() {
    final suggest = widget.settings.imeSuggestions;
    return EditableText(
      key: const ValueKey('remote-ime-field'),
      controller: _text,
      focusNode: _textFocus,
      style: const TextStyle(fontSize: 1, color: Color(0x00000000)),
      cursorColor: const Color(0x00000000),
      backgroundCursorColor: const Color(0x00000000),
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      maxLines: null,
      autocorrect: suggest,
      enableSuggestions: suggest,
      enableIMEPersonalizedLearning: false,
      showCursor: false,
      enableInteractiveSelection: false,
      rendererIgnoresPointer: true,
      onTapOutside: (_) {},
    );
  }
}

class _CursorLayerPainter extends CustomPainter {
  _CursorLayerPainter({
    required this.at,
    required this.visible,
    required this.shape,
  });

  final Offset at;
  final bool visible;
  final String shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    RemoteCursorPainter(shape: shape).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CursorLayerPainter old) =>
      old.at != at || old.visible != visible || old.shape != shape;
}
