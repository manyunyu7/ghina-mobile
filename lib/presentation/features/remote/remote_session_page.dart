import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../di/kantor_providers.dart';
import 'input/remote_input.dart';
import 'remote_protocol.dart';
import 'remote_session.dart';
import 'remote_widgets.dart';

/// Full-screen remote desktop of one Mac. Touch, keyboard and the local
/// pointer come from `input/` ([RemoteInputLayer], [RemoteKeyboardBar]);
/// this page owns the session, the video, zoom state, the toolbar,
/// clipboard, reconnects and the device-sized virtual display (`vd`).
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

/// Input mode is remembered per form factor: phone / Fold closed vs
/// tablet / Fold open (RESEARCH.md: trackpad vs touch by default).
String _prefModeFor(bool wide) =>
    wide ? 'ravel.remote.mode.wide' : 'ravel.remote.mode.narrow';

/// Shortest side ≥ 600dp: tablet or an open Fold.
bool remoteIsWideDevice(Size logical) =>
    math.min(logical.width, logical.height) >= 600;

InputMode remoteDefaultMode(bool wide) =>
    wide ? InputMode.touch : InputMode.trackpad;
const _prefQuality = 'ravel.remote.quality';
const _prefVd = 'ravel.remote.vd';

enum _Rotation { auto, landscape, portrait }

class _RemoteSessionPageState extends ConsumerState<RemoteSessionPage>
    with WidgetsBindingObserver {
  RemoteSession? _s;
  final _zoom = TransformationController();
  final _kb = RemoteKeyboardController();
  InputMode _mode = InputMode.trackpad;

  bool _toolbar = true;
  bool _fullscreen = true;
  bool _keyBar = false;
  bool _warnDismissed = false;
  bool _wantVd = false;
  _Rotation _rotation = _Rotation.auto;

  Size? _stage;
  Timer? _vdDebounce;
  Timer? _toolbarHide;
  StreamSubscription<String>? _clipSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zoom.addListener(_onZoom);
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
      s.setMaxStream(_physicalSize());
      s.start();
    }
    _loadPrefs();
    WakelockPlus.enable().catchError((_) {});
    _applyFullscreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vdDebounce?.cancel();
    _toolbarHide?.cancel();
    _clipSub?.cancel();
    _s?.removeListener(_onSession);
    _s?.dispose();
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    _kb.dispose();
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
        s.onBackground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Fold opened/closed or rotated: new stream cap (and new virtual display
  /// size, handled by the stage layout).
  @override
  void didChangeMetrics() {
    _s?.setMaxStream(_physicalSize());
    _onFormChange();
  }

  static Size _physicalSize() =>
      WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;

  static double _dpr() =>
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  Map<String, String> _viewerInfo() {
    final px = _physicalSize();
    final dpr = _dpr();
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
    final q = p.getString(_prefQuality);
    final quality = RemoteQuality.values.where((v) => v.wire == q);
    if (quality.isNotEmpty) _s?.quality = quality.first;
    setState(() {
      _mode = _storedMode(p, _wide);
      _wantVd = p.getBool(_prefVd) ?? false;
    });
    _s?.setCursorMode(_cursorFor(_mode));
    _syncVirtualDisplay();
  }

  static bool get _wideNow => remoteIsWideDevice(_physicalSize() / _dpr());
  bool _wide = _wideNow;

  static InputMode _storedMode(SharedPreferences p, bool wide) =>
      switch (p.getString(_prefModeFor(wide))) {
        'touch' => InputMode.touch,
        'trackpad' => InputMode.trackpad,
        _ => remoteDefaultMode(wide),
      };

  /// Fold opened/closed: switch to that posture's mode.
  Future<void> _onFormChange() async {
    final wide = _wideNow;
    if (wide == _wide) return;
    _wide = wide;
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final m = _storedMode(p, wide);
    if (m == _mode) return;
    setState(() => _mode = m);
    _s?.setCursorMode(_cursorFor(m));
  }

  static RemoteCursorMode _cursorFor(InputMode m) =>
      m == InputMode.trackpad ? RemoteCursorMode.local : RemoteCursorMode.video;

  void _onSession() {
    if (!mounted) return;
    final s = _s!;
    if (s.live && s.hasVideo && _toolbar && _toolbarHide == null) {
      _toolbarHide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toolbar = false);
      });
    }
    setState(() {});
  }

  void _onZoom() {
    // only the "Pas layar" button depends on zoom; rebuild when it flips
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _wasZoomed) setState(() => _wasZoomed = zoomed);
  }

  bool _wasZoomed = false;

  void _onHostClip(String text) {
    if (!mounted) return;
    _toast('Clipboard Mac disalin ke HP (${text.characters.length} karakter)');
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
  // virtual display (`vd`)

  void _onStageSize(Size size) {
    if (size == _stage) return;
    _stage = size;
    if (!_wantVd) return;
    // Fold opening/closing and rotation come in several layout passes
    _vdDebounce?.cancel();
    _vdDebounce = Timer(const Duration(milliseconds: 700), _syncVirtualDisplay);
  }

  void _syncVirtualDisplay() {
    final s = _s;
    final stage = _stage;
    if (s == null) return;
    if (!_wantVd) {
      s.setVirtualDisplay(on: false);
      return;
    }
    if (stage == null || stage.isEmpty) return;
    s.setVirtualDisplay(
      on: true,
      points: stage,
      scale: _dpr() >= 1.5 ? 2 : 1,
      name: s.viewer['device'],
    );
  }

  Future<void> _toggleVd() async {
    setState(() => _wantVd = !_wantVd);
    _zoom.value = Matrix4.identity();
    _syncVirtualDisplay();
    _toast(
      _wantVd
          ? 'Layar virtual seukuran perangkat ini dibuat di Mac'
          : 'Kembali ke layar Mac',
    );
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefVd, _wantVd);
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

  Future<void> _setMode(InputMode m) async {
    setState(() => _mode = m);
    _s?.setCursorMode(_cursorFor(m));
    _toast(
      m == InputMode.trackpad
          ? 'Mode trackpad: geser untuk gerakkan kursor, ketuk untuk klik'
          : 'Mode sentuh langsung: ketuk tepat di titik yang mau diklik',
    );
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefModeFor(_wide),
      m == InputMode.touch ? 'touch' : 'trackpad',
    );
  }

  Future<void> _setQuality(RemoteQuality q) async {
    _s?.setQuality(q);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefQuality, q.wire);
  }

  void _openKeyboard() {
    setState(() {
      _keyBar = true;
      _toolbar = false;
    });
    _kb.showSoftKeyboard();
  }

  void _closeKeyboard() {
    _kb.hideSoftKeyboard();
    setState(() => _keyBar = false);
  }

  void _shortcut(String code, Set<RemoteMod> mods) {
    _s?.send(Ctl.key(code, mods));
    HapticFeedback.selectionClick();
  }

  Future<void> _leave() async {
    final nav = Navigator.of(context);
    await _s?.close();
    if (mounted) nav.pop();
  }

  Future<void> _confirmTrust() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Percayai identitas baru?'),
        content: Text(
          'Sidik jari ${widget.host.name} berbeda dari yang tersimpan. Ini wajar '
          'hanya kalau ravel-host baru dipasang ulang atau sertifikatnya diganti. '
          'Kalau tidak yakin, batalkan dan periksa Mac-nya dulu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Percayai'),
          ),
        ],
      ),
    );
    if (ok == true) await _s?.trustNewIdentity();
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
        if (_keyBar) {
          _closeKeyboard();
        } else {
          _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: s == null
            ? _noConnection()
            : Column(
                children: [
                  Expanded(child: _stageView(s)),
                  if (_keyBar)
                    Material(
                      color: const Color(0xF0202124),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(child: RemoteKeyboardBar(controller: _kb)),
                            IconButton(
                              tooltip: 'Tutup baris tombol',
                              color: Colors.white70,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _closeKeyboard,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
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

  Widget _stageView(RemoteSession s) {
    return LayoutBuilder(
      builder: (context, c) {
        _onStageSize(c.biggest);
        final pad = MediaQuery.paddingOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            RemoteInputLayer(
              send: s.send,
              hostMessages: s.hostMessages,
              remoteSize: Size(s.logicalWidth, s.logicalHeight),
              mode: _mode,
              transformationController: _zoom,
              keyboardController: _kb,
              enabled: s.live,
              settings: RemoteInputSettings(
                showLocalCursor: _mode == InputMode.trackpad,
              ),
              child: s.hasVideo
                  ? RTCVideoView(
                      s.renderer,
                      filterQuality: _wasZoomed
                          ? FilterQuality.medium
                          : FilterQuality.low,
                    )
                  : const SizedBox.expand(),
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
                if (s.pinChanged)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB3261E),
                    ),
                    onPressed: _confirmTrust,
                    icon: const Icon(Icons.gpp_maybe_rounded),
                    label: const Text('Percayai lagi'),
                  )
                else if (!spinner)
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
              _mode == InputMode.trackpad
                  ? Icons.mouse_rounded
                  : Icons.touch_app_rounded,
              _mode == InputMode.trackpad
                  ? 'Mode trackpad (ketuk untuk sentuh langsung)'
                  : 'Mode sentuh langsung (ketuk untuk trackpad)',
              () => _setMode(
                _mode == InputMode.trackpad
                    ? InputMode.touch
                    : InputMode.trackpad,
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
            btn(
              Icons.fit_screen_rounded,
              _wantVd
                  ? 'Matikan layar virtual'
                  : 'Layar virtual seukuran perangkat ini',
              _toggleVd,
              color: _wantVd ? Theme.of(context).colorScheme.primary : null,
            ),
            if (_wasZoomed)
              btn(
                Icons.zoom_out_map_rounded,
                'Pas layar',
                () => _zoom.value = Matrix4.identity(),
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
