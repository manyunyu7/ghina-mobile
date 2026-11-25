import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../di/kantor_providers.dart';
import 'remote_gestures.dart';
import 'remote_keys.dart';
import 'remote_protocol.dart';
import 'remote_session.dart';
import 'remote_widgets.dart';

/// Full-screen remote desktop of one Mac.
class RemoteSessionPage extends ConsumerStatefulWidget {
  const RemoteSessionPage({super.key, required this.host, this.api});

  final RemoteHost host;

  /// Viewer client (device token from pairing). Falls back to the active
  /// Kantor connection, which kantor-claude only accepts if it is a viewer
  /// token.
  final KantorApi? api;

  static Future<void> open(
    BuildContext context,
    RemoteHost host, {
    KantorApi? api,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => RemoteSessionPage(host: host, api: api),
    ),
  );

  @override
  ConsumerState<RemoteSessionPage> createState() => _RemoteSessionPageState();
}

const _prefMode = 'ravel.remote.mode';
const _prefQuality = 'ravel.remote.quality';

/// Zero-width text kept in the hidden field so Backspace always has
/// something to delete (and so shows up as an edit we can forward).
const _sentinel = '​​​​';

enum _Rotation { auto, landscape, portrait }

class _RemoteSessionPageState extends ConsumerState<RemoteSessionPage>
    with WidgetsBindingObserver {
  RemoteSession? _s;
  final _vp = RemoteViewport();
  late final RemoteGestureEngine _g;
  RemoteInputMode _mode = RemoteInputMode.trackpad;

  bool _toolbar = true;
  bool _fullscreen = true;
  bool _kbd = false;
  bool _warnDismissed = false;
  _Rotation _rotation = _Rotation.auto;

  final _input = TextEditingController(text: _sentinel);
  String _prevText = _sentinel;
  final _inputFocus = FocusNode(debugLabel: 'remote-ime');
  final _pageFocus = FocusNode(debugLabel: 'remote-page');
  final _sticky = StickyModifiers();
  final Set<String> _swallowUp = {};

  final _clock = Stopwatch()..start();
  Timer? _holdTimer;
  Timer? _fling;
  Timer? _toolbarHide;
  RemoteButton? _mouseButton;
  StreamSubscription<String>? _clipSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _g = RemoteGestureEngine(
      toRemote: _vp.toRemote,
      gain: () => _vp.gain(_s?.logicalWidth ?? 1440),
    );
    _input.addListener(_onImeChanged);
    final api = widget.api ?? ref.read(kantorApiProvider);
    if (api != null) {
      final s = RemoteSession(
        api: api,
        host: widget.host,
        viewer: _viewerInfo(),
      );
      _s = s;
      s.addListener(_onSession);
      _clipSub = s.clipFromHost.listen(_onHostClip);
      s.start();
    }
    _loadPrefs();
    WakelockPlus.enable().catchError((_) {});
    _applyFullscreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTimer?.cancel();
    _fling?.cancel();
    _toolbarHide?.cancel();
    _clipSub?.cancel();
    _s?.removeListener(_onSession);
    _s?.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _pageFocus.dispose();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _s;
    if (s == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        s.onForeground();
        _applyFullscreen();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _apply(_g.reset());
        _stopFling();
        s.onBackground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Map<String, String> _viewerInfo() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final px = view.physicalSize;
    final dpr = view.devicePixelRatio;
    final shortest = math.min(px.width, px.height) / dpr;
    return {
      'device': shortest >= 600 ? 'Ravel (tablet)' : 'Ravel (HP)',
      'w': px.width.round().toString(),
      'h': px.height.round().toString(),
      'dpr': dpr.toStringAsFixed(2),
    };
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final mode = p.getString(_prefMode);
    final q = p.getString(_prefQuality);
    setState(() {
      _mode = mode == 'direct'
          ? RemoteInputMode.direct
          : RemoteInputMode.trackpad;
      _g.mode = _mode;
    });
    final quality = RemoteQuality.values.where((v) => v.wire == q);
    if (quality.isNotEmpty) _s?.quality = quality.first;
  }

  void _onSession() {
    if (!mounted) return;
    final s = _s!;
    // collapse the toolbar a moment after the picture shows up
    if (s.live && s.hasVideo && _toolbar && _toolbarHide == null) {
      _toolbarHide = Timer(const Duration(seconds: 4), () {
        if (mounted && !_kbd) setState(() => _toolbar = false);
      });
    }
    setState(() {});
  }

  void _onHostClip(String text) {
    if (!mounted) return;
    final n = text.characters.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Clipboard Mac disalin ke HP ($n karakter)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // touch & mouse

  void _apply(List<GestureAction> actions) {
    final s = _s;
    if (actions.isEmpty || s == null) return;
    var changed = false;
    for (final a in actions) {
      switch (a) {
        case SendCtl(:final msg):
          if (s.send(msg)) changed = true;
          if (msg['t'] == 'mr' && _vp.zoomed) _vp.follow(s.cursor);
        case ZoomView(:final factor, :final focal):
          _vp.zoom(factor, focal);
          changed = true;
        case PanView(:final delta):
          _vp.pan(delta);
          changed = true;
        case Haptic():
          HapticFeedback.mediumImpact();
        case ScrollFling(:final velocity):
          _startFling(velocity);
      }
    }
    if (changed) setState(() {});
  }

  void _onDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      final b = (e.buttons & kSecondaryMouseButton) != 0
          ? RemoteButton.right
          : (e.buttons & kMiddleMouseButton) != 0
          ? RemoteButton.middle
          : RemoteButton.left;
      _mouseButton = b;
      _sendMouseMove(e.localPosition);
      _s?.send(Ctl.down(b));
      return;
    }
    _stopFling();
    _apply(_g.down(e.pointer, e.localPosition, _clock.elapsed));
    _holdTimer?.cancel();
    _holdTimer = Timer(
      RemoteGestureEngine.holdDelay + const Duration(milliseconds: 10),
      () => _apply(_g.tick(_clock.elapsed)),
    );
  }

  void _onMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      _sendMouseMove(e.localPosition);
      return;
    }
    _apply(_g.move(e.pointer, e.localPosition, _clock.elapsed));
  }

  void _onUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      final b = _mouseButton;
      if (b != null) _s?.send(Ctl.up(b));
      _mouseButton = null;
      return;
    }
    _apply(_g.up(e.pointer, _clock.elapsed));
    if (!_g.active) _holdTimer?.cancel();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      final b = _mouseButton;
      if (b != null) _s?.send(Ctl.up(b));
      _mouseButton = null;
      return;
    }
    _apply(_g.cancel(e.pointer));
    if (!_g.active) _holdTimer?.cancel();
  }

  void _onHover(PointerHoverEvent e) {
    if (e.kind == PointerDeviceKind.mouse ||
        e.kind == PointerDeviceKind.stylus) {
      _sendMouseMove(e.localPosition);
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _s?.send(Ctl.wheel(e.scrollDelta.dx, e.scrollDelta.dy));
    }
  }

  void _sendMouseMove(Offset p) {
    final n = _vp.toRemote(p);
    if (_s?.send(Ctl.moveAbs(n.dx, n.dy)) ?? false) setState(() {});
  }

  void _startFling(Offset velocity) {
    _stopFling();
    var v = velocity;
    const dt = 0.016;
    _fling = Timer.periodic(const Duration(milliseconds: 16), (t) {
      v = v * 0.93;
      if (v.distance < 60) {
        t.cancel();
        return;
      }
      _s?.send(Ctl.wheel(v.dx * dt, v.dy * dt));
    });
  }

  void _stopFling() {
    _fling?.cancel();
    _fling = null;
  }

  // ---------------------------------------------------------------------------
  // keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final s = _s;
    if (s == null || !s.ctlOpen) return KeyEventResult.ignored;
    final code = w3cCode(e.physicalKey);
    if (code == null) return KeyEventResult.ignored;
    final isMod = RemoteMod.values.any(
      (m) => code.startsWith(m.code.replaceAll('Left', '')),
    );
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (_sticky.any && !isMod && e is KeyDownEvent) {
        s.send(Ctl.key(code, _sticky.active));
        _swallowUp.add(code);
        setState(_sticky.consume);
      } else {
        s.send(Ctl.keyDown(code));
      }
    } else if (e is KeyUpEvent) {
      if (!_swallowUp.remove(code)) s.send(Ctl.keyUp(code));
    }
    return KeyEventResult.handled;
  }

  void _onImeChanged() {
    final v = _input.value;
    final text = v.text;
    if (text == _prevText) return;
    final d = textDiff(_prevText, text);
    _prevText = text;
    final s = _s;
    if (s != null) {
      for (var i = 0; i < d.deleted; i++) {
        s.send(Ctl.key('Backspace', _sticky.active));
      }
      if (d.inserted.isNotEmpty) {
        final mods = _sticky.active;
        for (final m in textToCtl(d.inserted, mods)) {
          s.send(m);
        }
      }
      if (_sticky.any && (d.deleted > 0 || d.inserted.isNotEmpty)) {
        setState(_sticky.consume);
      }
    }
    // Reset the buffer between words (never while the IME is composing).
    final composing = v.composing.isValid && !v.composing.isCollapsed;
    if (!composing && (!text.startsWith(_sentinel) || text.length > 48)) {
      _prevText = _sentinel;
      _input.value = const TextEditingValue(
        text: _sentinel,
        selection: TextSelection.collapsed(offset: _sentinel.length),
      );
    }
  }

  void _sendKey(String code) {
    final s = _s;
    if (s == null) return;
    s.send(Ctl.key(code, _sticky.active));
    if (_sticky.any) setState(_sticky.consume);
  }

  void _shortcut(String code, Set<RemoteMod> mods) {
    _s?.send(Ctl.key(code, mods));
    HapticFeedback.selectionClick();
  }

  Future<void> _pasteToMac() async {
    final s = _s;
    if (s == null) return;
    await s.pushClipboard(force: true);
    s.send(Ctl.key('KeyV', {RemoteMod.meta}));
  }

  void _openKeyboard() {
    setState(() {
      _kbd = true;
      _toolbar = false;
    });
    if (_inputFocus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _closeKeyboard() {
    _inputFocus.unfocus();
    _pageFocus.requestFocus();
    setState(() {
      _kbd = false;
      _sticky.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // toolbar actions

  void _applyFullscreen() {
    SystemChrome.setEnabledSystemUIMode(
      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _cycleRotation() {
    final next =
        _Rotation.values[(_rotation.index + 1) % _Rotation.values.length];
    setState(() => _rotation = next);
    SystemChrome.setPreferredOrientations(switch (next) {
      _Rotation.auto => const [],
      _Rotation.landscape => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      _Rotation.portrait => const [DeviceOrientation.portraitUp],
    });
    _toast(switch (next) {
      _Rotation.auto => 'Rotasi otomatis',
      _Rotation.landscape => 'Terkunci mendatar',
      _Rotation.portrait => 'Terkunci tegak',
    });
  }

  Future<void> _setMode(RemoteInputMode m) async {
    _apply(_g.reset());
    setState(() {
      _mode = m;
      _g.mode = m;
    });
    _toast(
      m == RemoteInputMode.trackpad
          ? 'Mode trackpad: geser untuk gerakkan kursor, ketuk untuk klik'
          : 'Mode sentuh langsung: ketuk tepat di titik yang mau diklik',
    );
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefMode,
      m == RemoteInputMode.direct ? 'direct' : 'trackpad',
    );
  }

  Future<void> _setQuality(RemoteQuality q) async {
    _s?.setQuality(q);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefQuality, q.wire);
  }

  Future<void> _leave() async {
    final nav = Navigator.of(context);
    await _s?.close();
    if (mounted) nav.pop();
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Putuskan sesi?'),
        content: Text('Sambungan ke ${widget.host.name} akan ditutup.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Putuskan'),
          ),
        ],
      ),
    );
    if (ok == true) await _leave();
  }

  // ---------------------------------------------------------------------------
  // build

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_kbd) {
          _closeKeyboard();
        } else {
          _confirmLeave();
        }
      },
      child: Focus(
        focusNode: _pageFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: s == null
              ? _noConnection()
              : Column(
                  children: [
                    Expanded(child: _stage(s)),
                    if (_kbd)
                      RemoteKeyBar(
                        sticky: _sticky,
                        onKey: _sendKey,
                        onMod: (m) => setState(() => _sticky.tap(m)),
                        onShortcut: _shortcut,
                        onPaste: _pasteToMac,
                        onClose: _closeKeyboard,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _noConnection() => SafeArea(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Kantor belum tersambung. Isi token di Pengaturan Kantor.',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kembali'),
          ),
        ],
      ),
    ),
  );

  Widget _stage(RemoteSession s) {
    return LayoutBuilder(
      builder: (context, c) {
        _vp.setGeometry(c.biggest, s.pictureSize);
        final shown = _vp.shown;
        final showCursor =
            _mode == RemoteInputMode.trackpad &&
            s.live &&
            s.hasVideo &&
            s.cursorVisible;
        final pad = MediaQuery.paddingOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              onPointerHover: _onHover,
              onPointerSignal: _onSignal,
              child: ClipRect(
                child: Stack(
                  children: [
                    if (s.hasVideo)
                      Positioned.fromRect(
                        rect: shown,
                        child: RTCVideoView(
                          s.renderer,
                          filterQuality: _vp.zoomed
                              ? FilterQuality.medium
                              : FilterQuality.low,
                        ),
                      ),
                    if (showCursor)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: RemoteCursorPainter(
                              at: _vp.fromRemote(s.cursor),
                              shape: s.cursorShape,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!s.live || !s.hasVideo) _statusCard(s),
            if (s.hostWarning != null && !_warnDismissed)
              Positioned(
                left: 8 + pad.left,
                right: 8 + pad.right,
                bottom: 8,
                child: _warning(s.hostWarning!),
              ),
            if (s.statsEnabled)
              Positioned(
                left: 8 + pad.left,
                top: 8 + pad.top,
                child: RemoteStatsOverlay(stats: s.stats),
              ),
            Positioned(
              top: pad.top + 6,
              left: 8 + pad.left,
              right: 8 + pad.right,
              child: Align(
                alignment: Alignment.topCenter,
                child: _toolbar ? _toolbarBar(s) : _toolbarHandle(),
              ),
            ),
            // hidden text field: the phone keyboard (IME, dictation) types here
            Positioned(
              left: 0,
              bottom: 0,
              width: 2,
              height: 2,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  autocorrect: true,
                  enableSuggestions: true,
                  enableInteractiveSelection: false,
                  showCursor: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration.collapsed(hintText: ''),
                  style: const TextStyle(
                    fontSize: 1,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusCard(RemoteSession s) {
    final name = widget.host.name;
    final (String title, String? detail, bool spinner) = switch (s.status) {
      RemoteStatus.connecting => ('Menghubungkan ke $name…', null, true),
      RemoteStatus.waiting => ('Menunggu $name menjawab…', null, true),
      RemoteStatus.negotiating => ('Menyiapkan video…', null, true),
      RemoteStatus.connected => ('Menunggu gambar dari Mac…', null, true),
      RemoteStatus.reconnecting => ('Menyambung ulang…', s.error, true),
      RemoteStatus.failed => (
        'Tidak tersambung',
        [
          s.error ?? 'Sambungan gagal.',
          if (s.willRetry)
            'Mencoba lagi otomatis dalam ${s.retryInSeconds} dtk.',
        ].join('\n'),
        false,
      ),
      RemoteStatus.paused => (
        'Sesi dijeda',
        'App lama di latar belakang. Sambungkan lagi untuk melanjutkan.',
        false,
      ),
      RemoteStatus.closed => ('Sesi ditutup', null, false),
    };
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xE6202124),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              const Icon(
                Icons.desktop_access_disabled_rounded,
                color: Colors.white70,
                size: 32,
              ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (!spinner)
                  FilledButton.icon(
                    onPressed: s.reconnectNow,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Coba lagi'),
                  ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: _leave,
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _warning(String text) => Material(
    color: const Color(0xF0B26A00),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Tutup',
            color: Colors.white,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _warnDismissed = true),
          ),
        ],
      ),
    ),
  );

  Widget _toolbarHandle() => Material(
    color: Colors.black54,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: () => setState(() => _toolbar = true),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Icon(Icons.expand_more_rounded, color: Colors.white, size: 22),
      ),
    ),
  );

  Widget _toolbarBar(RemoteSession s) {
    Widget btn(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      Color? color,
    }) => IconButton(
      tooltip: tip,
      color: color ?? Colors.white,
      icon: Icon(icon),
      onPressed: onTap,
    );
    final displays = s.displays;
    return Material(
      color: const Color(0xE6202124),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (displays.length > 1)
              PopupMenuButton<int>(
                tooltip: 'Pilih layar',
                icon: const Icon(Icons.monitor_rounded, color: Colors.white),
                onSelected: s.selectDisplay,
                itemBuilder: (_) => [
                  for (final d in displays)
                    CheckedPopupMenuItem(
                      value: d.id,
                      checked: d.id == s.activeDisplay?.id,
                      child: Text(
                        d.sizeLabel.isEmpty
                            ? d.name
                            : '${d.name} · ${d.sizeLabel}',
                      ),
                    ),
                ],
              ),
            PopupMenuButton<RemoteQuality>(
              tooltip: 'Kualitas: ${s.quality.label}',
              icon: Icon(switch (s.quality) {
                RemoteQuality.auto => Icons.hdr_auto_rounded,
                RemoteQuality.sharp => Icons.hd_rounded,
                RemoteQuality.saver => Icons.data_saver_on_rounded,
              }, color: Colors.white),
              onSelected: _setQuality,
              itemBuilder: (_) => [
                for (final q in RemoteQuality.values)
                  CheckedPopupMenuItem(
                    value: q,
                    checked: q == s.quality,
                    child: Text(switch (q) {
                      RemoteQuality.auto => 'Otomatis',
                      RemoteQuality.sharp => 'Tajam (resolusi penuh)',
                      RemoteQuality.saver => 'Hemat data',
                    }),
                  ),
              ],
            ),
            btn(
              _mode == RemoteInputMode.trackpad
                  ? Icons.mouse_rounded
                  : Icons.touch_app_rounded,
              _mode == RemoteInputMode.trackpad
                  ? 'Mode trackpad (ketuk untuk sentuh langsung)'
                  : 'Mode sentuh langsung (ketuk untuk trackpad)',
              () => _setMode(
                _mode == RemoteInputMode.trackpad
                    ? RemoteInputMode.direct
                    : RemoteInputMode.trackpad,
              ),
            ),
            btn(Icons.keyboard_rounded, 'Keyboard', _openKeyboard),
            PopupMenuButton<int>(
              tooltip: 'Pintasan Mac',
              icon: const Icon(
                Icons.keyboard_command_key_rounded,
                color: Colors.white,
              ),
              onSelected: (i) {
                final (_, _, code, mods) = remoteShortcuts[i];
                _shortcut(code, mods);
              },
              itemBuilder: (_) => [
                for (var i = 0; i < remoteShortcuts.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(remoteShortcuts[i].$2),
                      title: Text(remoteShortcuts[i].$1),
                    ),
                  ),
              ],
            ),
            btn(
              Icons.content_paste_go_rounded,
              'Kirim clipboard HP ke Mac',
              () async {
                final sent = await s.pushClipboard(force: true);
                if (mounted) {
                  _toast(
                    sent
                        ? 'Clipboard HP dikirim ke Mac'
                        : 'Clipboard HP kosong atau sesi belum siap',
                  );
                }
              },
            ),
            if (_vp.zoomed)
              btn(
                Icons.zoom_out_map_rounded,
                'Pas layar',
                () => setState(_vp.reset),
              ),
            btn(
              switch (_rotation) {
                _Rotation.auto => Icons.screen_rotation_rounded,
                _Rotation.landscape => Icons.stay_current_landscape_rounded,
                _Rotation.portrait => Icons.stay_current_portrait_rounded,
              },
              'Rotasi',
              _cycleRotation,
            ),
            btn(
              _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              _fullscreen ? 'Keluar layar penuh' : 'Layar penuh',
              () {
                setState(() => _fullscreen = !_fullscreen);
                _applyFullscreen();
              },
            ),
            btn(
              Icons.speed_rounded,
              s.statsEnabled ? 'Sembunyikan statistik' : 'Statistik',
              () => s.setStatsEnabled(!s.statsEnabled),
              color: s.statsEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            btn(
              Icons.power_settings_new_rounded,
              'Putuskan',
              _leave,
              color: const Color(0xFFFF6B6B),
            ),
            btn(
              Icons.expand_less_rounded,
              'Sembunyikan menu',
              () => setState(() => _toolbar = false),
            ),
          ],
        ),
      ),
    );
  }
}
