import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_hubs.dart';
import 'remote_protocol.dart';
import 'remote_security.dart';

enum RemoteStatus {
  /// Opening the signaling socket / waiting for the Mac.
  connecting,

  /// Signaling is up, waiting for the Mac's offer.
  waiting,

  /// Offer answered, ICE in progress.
  negotiating,

  connected,

  /// Lost the connection; trying again on its own.
  reconnecting,

  /// Stopped with an error; retries on a timer or on "Coba lagi".
  failed,

  /// App sat in the background too long; resumes on return.
  paused,

  closed,
}

/// Live stats for the optional overlay.
class RemoteStats {
  const RemoteStats({
    this.fps,
    this.kbps,
    this.rttMs,
    this.width,
    this.height,
    this.encMs,
    this.codec,
    this.decoder,
  });

  final double? fps;
  final double? kbps;
  final double? rttMs;
  final int? width;
  final int? height;
  final double? encMs;
  final String? codec;

  /// `decoderImplementation` (c2.qti…/c2.exynos… = hardware).
  final String? decoder;
}

/// One remote-desktop session with a Mac: signaling WS to kantor-claude,
/// WebRTC peer connection (the Mac offers, we answer), and the `ctl`
/// DataChannel for input, clipboard and stream settings.
class RemoteSession extends ChangeNotifier {
  RemoteSession({
    required this.hubs,
    required this.host,
    required this.viewer,
    this.backgroundGrace = const Duration(minutes: 2),
    RemotePinStore? pins,
  }) : pins = pins ?? SecureRemotePinStore();

  /// Pinned DTLS fingerprints (trust on first use, per Mac).
  final RemotePinStore pins;

  /// The last offer was refused because the Mac's fingerprint changed since
  /// it was first trusted (the UI offers "trust again").
  bool pinChanged = false;
  String? _announcedFp;
  List<Map<String, dynamic>> _iceServers = const [];

  /// Every hub refused this device: the UI sends the owner to pairing.
  bool needsPairing = false;

  /// Signaling hubs (several addresses of the same Kantor, failover).
  final RemoteHubClient hubs;
  final RemoteHost host;

  /// Sent as query params so kantor-claude can fill `join.viewer`.
  final Map<String, String> viewer;

  /// How long the app may stay in the background before the session closes
  /// (it reconnects when the app comes back).
  final Duration backgroundGrace;

  final RTCVideoRenderer renderer = RTCVideoRenderer();

  RemoteStatus status = RemoteStatus.connecting;
  String? error;
  String? hostWarning;
  bool hasVideo = false;
  HostHello? hello;
  int? display;
  int remoteW = 0;
  int remoteH = 0;
  Offset cursor = const Offset(0.5, 0.5);
  bool cursorVisible = false;
  String cursorShape = 'arrow';
  RemoteQuality quality = RemoteQuality.auto;
  RemoteStats stats = const RemoteStats();
  bool statsEnabled = false;
  int attempt = 0;

  /// Raw host → viewer ctl messages, for `RemoteInputLayer.hostMessages`.
  Stream<Map<String, dynamic>> get hostMessages => _hostRaw.stream;
  final _hostRaw = StreamController<Map<String, dynamic>>.broadcast();

  /// Pointer drawn by the app (trackpad) or burnt into the video (touch).
  RemoteCursorMode cursorMode = RemoteCursorMode.video;

  /// Largest stream size worth decoding on this screen (pixels).
  Size? maxStream;

  /// Virtual display request currently wanted (null = off).
  Map<String, Object?>? _vd;
  bool get virtualDisplayOn => _vd != null;

  /// Text the Mac put on its clipboard (already copied to the phone).
  Stream<String> get clipFromHost => _clipOut.stream;
  final _clipOut = StreamController<String>.broadcast();

  WebSocket? _ws;
  RTCPeerConnection? _pc;
  RTCDataChannel? _ctl;
  String? _sid;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  bool _closing = false;
  bool _disposed = false;
  bool _inBackground = false;
  int _gen = 0;
  Timer? _retry;
  Timer? _ping;
  Timer? _statsTimer;
  Timer? _dropGrace;
  Timer? _offerTimeout;
  Timer? _bgTimer;
  String? _lastClip;
  int? _lastBytes;
  double? _lastBytesAt;
  double? _rttApp;

  bool get ctlOpen => _ctl?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get live => status == RemoteStatus.connected;

  /// The display being streamed, from `hello.displays`.
  RemoteDisplay? get activeDisplay {
    final list = hello?.displays ?? host.displays;
    for (final d in list) {
      if (d.id == display) return d;
    }
    return list.isEmpty ? null : list.first;
  }

  List<RemoteDisplay> get displays => hello?.displays ?? host.displays;

  /// Size of the remote picture. Prefers the decoded video (exact aspect),
  /// then what the Mac announced.
  Size get pictureSize {
    final vw = renderer.videoWidth;
    final vh = renderer.videoHeight;
    if (hasVideo && vw > 0 && vh > 0) return Size(vw.toDouble(), vh.toDouble());
    if (remoteW > 0 && remoteH > 0) {
      return Size(remoteW.toDouble(), remoteH.toDouble());
    }
    final d = activeDisplay;
    if (d != null && d.w > 0 && d.h > 0) {
      return Size(d.w.toDouble(), d.h.toDouble());
    }
    return const Size(16, 10);
  }

  /// Coordinate space of the stream: exactly `w`,`h` of the latest
  /// `hello`/`display` (PROTOCOL.md §5). The Mac converts `mr` with the same
  /// numbers, so never derive it from anything else. Null until known.
  Size? get streamSize => remoteW > 0 && remoteH > 0
      ? Size(remoteW.toDouble(), remoteH.toDouble())
      : null;

  static Future<void>? _rtcInit;

  /// Low-latency playout and WARP; must run before any other flutter_webrtc
  /// call (its first method call would otherwise init without options).
  static Future<void> ensureWebRtc() => _rtcInit ??= WebRTC.initialize(
    options: {'zeroPlayoutDelay': true, 'enableWARP': true},
  ).catchError((Object _) {});

  Future<void> start() async {
    await ensureWebRtc();
    await renderer.initialize();
    renderer.onResize = _notify;
    if (_disposed) return;
    _connect();
  }

  /// "Coba lagi" or coming back from the background.
  void reconnectNow() {
    if (_closing) return;
    attempt = 0;
    _retry?.cancel();
    _connect();
  }

  // ---------------------------------------------------------------------------
  // signaling

  Future<void> _connect() async {
    final gen = ++_gen;
    _retry?.cancel();
    await _teardown(sendBye: false);
    if (gen != _gen || _closing) return;
    status = attempt == 0 ? RemoteStatus.connecting : RemoteStatus.reconnecting;
    _notify();
    final WebSocket ws;
    try {
      ws = await hubs.connectWs(
        '/api/remote/ws',
        query: {'machine': host.machine, ...viewer},
      );
    } on RemoteHubsFailed catch (e) {
      if (gen != _gen || _closing) return;
      needsPairing = e.needPairing.isNotEmpty;
      _fail(e.message, retry: false);
      return;
    } catch (e) {
      if (gen != _gen || _closing) return;
      _fail(_connectError(e), retry: _retryable(e));
      return;
    }
    if (gen != _gen || _closing) {
      unawaited(ws.close());
      return;
    }
    ws.pingInterval = const Duration(seconds: 15);
    _ws = ws;
    _offerTimeout = Timer(const Duration(seconds: 20), () {
      if (gen == _gen && !_remoteSet) {
        _fail('Mac tidak menjawab. Pastikan ravel-host berjalan di Mac.');
      }
    });
    ws.listen(
      (raw) {
        if (gen != _gen || raw is! String) return;
        final msg = SignalMessage.decode(raw);
        if (msg != null) _onSignal(msg, gen);
      },
      onDone: () {
        if (gen != _gen || _closing) return;
        // Signaling dropped. A live peer connection keeps working without
        // it; only reconnect when media is not flowing.
        _ws = null;
        if (status != RemoteStatus.connected) {
          _fail('Sambungan ke kantor terputus.');
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _onSignal(SignalMessage msg, int gen) {
    switch (msg) {
      case SignalReady(:final session, :final fingerprint, :final iceServers):
        _sid = session ?? _sid;
        _announcedFp = fingerprint;
        _iceServers = iceServers;
        // TODO(ravel-remote): relay TURN credentials expire after ~1 h; a
        // session that needs an ICE restart later should fetch fresh ones.
        if (status != RemoteStatus.connected) {
          status = RemoteStatus.waiting;
          _notify();
        }
      case SignalError(:final message):
        _fail(_friendlyError(message), retry: true);
      case SignalOffer(:final session, :final sdp):
        _sid = session ?? _sid;
        _onOffer(sdp, gen);
      case SignalIce(:final candidate, :final sdpMid, :final mLineIndex):
        final c = RTCIceCandidate(candidate, sdpMid, mLineIndex);
        if (_pc != null && _remoteSet) {
          _pc!.addCandidate(c).catchError((_) {});
        } else {
          _pendingIce.add(c);
        }
      case SignalBye(:final reason):
        // kantor-claude reasons: host-putus / host-diganti (Mac dropped,
        // retry), token-dicabut (this device was revoked, stop); ravel-host
        // may also end it on purpose ("Putuskan semua").
        final byUser =
            reason != null &&
            RegExp(
              r'dicabut|revoked|putuskan|disconnect.?all|by.?user|pemilik',
              caseSensitive: false,
            ).hasMatch(reason);
        if (byUser) {
          _fail(
            reason.contains('dicabut')
                ? 'Izin perangkat ini dicabut. Pasangkan ulang dari daftar Mac.'
                : 'Sesi diputus dari Mac ($reason).',
            retry: false,
          );
        } else {
          _fail('Mac memutus sesi${reason == null ? '' : ' ($reason)'}.');
        }
      case SignalOther():
        break;
    }
  }

  Future<void> _onOffer(String sdp, int gen) async {
    if (!await _verifyFingerprint(sdp, gen)) return;
    try {
      var pc = _pc;
      if (pc == null) {
        pc = await createPeerConnection({
          'iceServers': _iceServers,
          'sdpSemantics': 'unified-plan',
        });
        if (gen != _gen) {
          await pc.close();
          return;
        }
        _pc = pc;
        _wirePeer(pc, gen);
      }
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteSet = true;
      _offerTimeout?.cancel();
      for (final c in _pendingIce) {
        await pc.addCandidate(c).catchError((_) {});
      }
      _pendingIce.clear();
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      if (gen != _gen) return;
      _signal(SignalOut.answer(_sid, answer.sdp ?? ''));
      if (status != RemoteStatus.connected) {
        status = RemoteStatus.negotiating;
        _notify();
      }
    } catch (e) {
      if (gen == _gen) _fail('Gagal menyiapkan video: $e');
    }
  }

  /// DTLS pinning: the offer must carry the fingerprint kantor-claude
  /// announced in `ready`, and the one pinned for this Mac (TOFU).
  Future<bool> _verifyFingerprint(String sdp, int gen) async {
    String? pinned;
    try {
      pinned = await pins.read(host.machine);
    } catch (_) {}
    if (gen != _gen) return false;
    final r = checkFingerprint(
      sdp: sdp,
      announced: _announcedFp,
      pinned: pinned,
    );
    switch (r) {
      case PinResult.ok:
        pinChanged = false;
        if (pinned == null) {
          final fp = sdpFingerprints(sdp).single;
          try {
            await pins.write(host.machine, fp);
          } catch (_) {}
        }
        return gen == _gen;
      case PinResult.missing:
        _fail(
          'Mac tidak mengirim sidik jari DTLS. Sesi ditolak.',
          retry: false,
        );
      case PinResult.mismatchAnnounced:
        _fail(
          'Sidik jari video tidak sama dengan yang didaftarkan Mac ke kantor. '
          'Sesi ditolak demi keamanan.',
          retry: false,
        );
      case PinResult.mismatchPinned:
        pinChanged = true;
        _fail(
          'Identitas ${host.name} berubah sejak pertama dipercaya. Kalau kamu '
          'baru memasang ulang ravel-host, percayai lagi; kalau tidak, jangan.',
          retry: false,
        );
    }
    return false;
  }

  /// After the owner confirms: forget the old pin and connect again.
  Future<void> trustNewIdentity() async {
    try {
      await pins.clear(host.machine);
    } catch (_) {}
    pinChanged = false;
    reconnectNow();
  }

  void _wirePeer(RTCPeerConnection pc, int gen) {
    pc.onIceCandidate = (c) {
      if (gen != _gen || c.candidate == null) return;
      _signal(SignalOut.ice(_sid, c.candidate!, c.sdpMid, c.sdpMLineIndex));
    };
    pc.onTrack = (e) async {
      if (gen != _gen || e.track.kind != 'video') return;
      var stream = e.streams.isNotEmpty ? e.streams.first : null;
      if (stream == null) {
        stream = await createLocalMediaStream('ravel-remote');
        await stream.addTrack(e.track);
      }
      if (gen != _gen) return;
      renderer.srcObject = stream;
      hasVideo = true;
      _notify();
    };
    pc.onDataChannel = (ch) {
      if (gen != _gen || ch.label != 'ctl') return;
      _wireCtl(ch, gen);
    };
    pc.onConnectionState = (s) {
      if (gen != _gen) return;
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _dropGrace?.cancel();
          status = RemoteStatus.connected;
          attempt = 0;
          error = null;
          _startTimers(gen);
          _notify();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Wi-Fi ↔ cellular hand-off often recovers by itself
          _dropGrace?.cancel();
          _dropGrace = Timer(const Duration(seconds: 4), () {
            if (gen == _gen && status != RemoteStatus.closed) {
              _fail('Jaringan terputus.');
            }
          });
          status = RemoteStatus.reconnecting;
          _notify();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _fail(
            'Koneksi video gagal. Pastikan Tailscale menyala di HP dan Mac.',
          );
        default:
          break;
      }
    };
  }

  void _wireCtl(RTCDataChannel ch, int gen) {
    _ctl = ch;
    ch.onMessage = (m) {
      if (gen != _gen || m.isBinary) return;
      try {
        final raw = jsonDecode(m.text);
        if (raw is Map) _hostRaw.add(Map<String, dynamic>.from(raw));
      } catch (_) {}
      final msg = HostMessage.decode(m.text);
      if (msg != null) _onHost(msg);
    };
    ch.onDataChannelState = (s) {
      if (gen != _gen) return;
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _sendStreamConfig();
        final vd = _vd;
        if (vd != null) send(vd);
        send(Ctl.ping(_nowMs()));
      }
      _notify();
    };
    // the channel may already be open when handed over
    if (ch.state == RTCDataChannelState.RTCDataChannelOpen) _notify();
  }

  void _onHost(HostMessage msg) {
    switch (msg) {
      case HostHello():
        hello = msg;
        display = msg.display ?? display;
        remoteW = msg.w;
        remoteH = msg.h;
        final missing = [
          if (!msg.screenPerm) 'Perekaman Layar',
          if (!msg.inputPerm) 'Aksesibilitas',
        ];
        hostWarning = missing.isEmpty
            ? null
            : 'Izin ${missing.join(' dan ')} belum diberi di Mac '
                  '(Pengaturan Sistem › Privasi & Keamanan › ravel-host).'
                  '${msg.inputPerm ? '' : ' Klik dan ketik belum bisa sampai ke Mac.'}';
      case HostDisplay():
        display = msg.display ?? display;
        if (msg.w > 0) remoteW = msg.w;
        if (msg.h > 0) remoteH = msg.h;
      case HostCursor():
        cursor = Offset(msg.x.clamp(0.0, 1.0), msg.y.clamp(0.0, 1.0));
        cursorVisible = msg.visible;
        cursorShape = msg.shape ?? 'arrow';
        return; // ≤30/s; the input layer draws it, no page rebuild
      case HostClip(:final text):
        if (text.isEmpty || text == _lastClip) return;
        _lastClip = text;
        Clipboard.setData(ClipboardData(text: text));
        _clipOut.add(text);
        return;
      case HostPong(:final ts):
        final rtt = (_nowMs() - ts).toDouble();
        if (rtt >= 0 && rtt < 60000) {
          _rttApp = _rttApp == null ? rtt : _rttApp! * 0.7 + rtt * 0.3;
        }
        if (!statsEnabled) return;
      case HostStats(:final encMs):
        stats = RemoteStats(
          fps: stats.fps,
          kbps: stats.kbps,
          rttMs: stats.rttMs,
          width: stats.width,
          height: stats.height,
          encMs: encMs ?? stats.encMs,
          codec: stats.codec,
          decoder: stats.decoder,
        );
        if (!statsEnabled) return;
      case HostWarn(:final message):
        if (message.isNotEmpty) hostWarning = message;
    }
    _notify();
  }

  // ---------------------------------------------------------------------------
  // outgoing

  /// Sends one ctl message. Returns false while the channel is not open.
  bool send(Map<String, Object?> msg) {
    final ch = _ctl;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
      return false;
    }
    ch.send(RTCDataChannelMessage(encodeCtl(msg))).catchError((_) {});
    return true;
  }

  void _sendStreamConfig() {
    final m = maxStream;
    send(
      Ctl.cfg(
        quality: quality == RemoteQuality.auto ? null : quality,
        cursor: cursorMode,
        maxW: m?.width.round(),
        maxH: m?.height.round(),
      ),
    );
  }

  void setCursorMode(RemoteCursorMode mode) {
    if (mode == cursorMode) return;
    cursorMode = mode;
    send(Ctl.cfg(cursor: mode));
  }

  /// Pixel budget that keeps 60 fps (2560×1440).
  static const maxStreamPixels = 2560 * 1440;

  /// Caps the stream to this screen by AREA, not by its short side: the
  /// device's physical size, scaled down only when w×h exceeds
  /// [maxStreamPixels], sent landscape (long, short) so a landscape Mac
  /// stream is not squeezed by a portrait phone's short side. The host fits
  /// its own aspect inside. Sent again when the screen changes (Fold,
  /// rotation).
  static Size streamCapFor(Size physical) {
    final long = math.max(physical.width, physical.height);
    final short = math.min(physical.width, physical.height);
    if (long <= 0 || short <= 0) return Size.zero;
    final area = long * short;
    final k = area > maxStreamPixels ? math.sqrt(maxStreamPixels / area) : 1.0;
    return Size((long * k).floorToDouble(), (short * k).floorToDouble());
  }

  void setMaxStream(Size physical) {
    final next = streamCapFor(physical);
    if (next.isEmpty || next == maxStream) return;
    maxStream = next;
    send(Ctl.cfg(maxW: next.width.round(), maxH: next.height.round()));
  }

  /// Turns the device-sized virtual display on (or resizes it) / off.
  void setVirtualDisplay({
    required bool on,
    Size? points,
    int scale = 2,
    String? name,
  }) {
    if (!on) {
      if (_vd == null) return;
      _vd = null;
      send(Ctl.virtualDisplay(on: false));
      _notify();
      return;
    }
    final p = points;
    if (p == null || p.isEmpty) return;
    // even sizes keep H.264 happy
    int even(double v) => (v.round() ~/ 2) * 2;
    final msg = Ctl.virtualDisplay(
      on: true,
      w: even(p.width),
      h: even(p.height),
      scale: scale,
      name: name,
    );
    if (_vd != null && mapEquals(_vd, msg)) return;
    _vd = msg;
    send(msg);
    _notify();
  }

  void setQuality(RemoteQuality q) {
    quality = q;
    send(Ctl.cfg(quality: q));
    _notify();
  }

  void selectDisplay(int id) {
    display = id;
    send(Ctl.cfg(display: id));
    _notify();
  }

  void setStatsEnabled(bool on) {
    statsEnabled = on;
    if (!on) stats = const RemoteStats();
    _notify();
  }

  /// Phone clipboard → Mac. Returns true when something new was sent.
  Future<bool> pushClipboard({bool force = false}) async {
    if (!ctlOpen) return false;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return false;
    if (!force && text == _lastClip) return false;
    _lastClip = text;
    return send(Ctl.clip(text));
  }

  // ---------------------------------------------------------------------------
  // lifecycle

  void onBackground() {
    if (_inBackground) return;
    _inBackground = true;
    send(Ctl.release());
    _bgTimer?.cancel();
    _bgTimer = Timer(backgroundGrace, () async {
      if (_closing || !_inBackground) return;
      _gen++;
      _cancelTimers();
      await _teardown(sendBye: true);
      status = RemoteStatus.paused;
      _notify();
    });
  }

  void onForeground() {
    if (!_inBackground) return;
    _inBackground = false;
    _bgTimer?.cancel();
    if (status == RemoteStatus.paused || status == RemoteStatus.failed) {
      reconnectNow();
    } else {
      pushClipboard();
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _gen++;
    _cancelTimers();
    send(Ctl.release());
    await _teardown(sendBye: true);
    status = RemoteStatus.closed;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      close().whenComplete(() {
        renderer.srcObject = null;
        renderer.dispose();
      }),
    );
    _clipOut.close();
    _hostRaw.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // internals

  void _fail(String message, {bool retry = true}) {
    if (_closing) return;
    _gen++;
    _cancelTimers();
    error = message;
    status = RemoteStatus.failed;
    _notify();
    unawaited(_teardown(sendBye: true));
    if (!retry || _inBackground) return;
    attempt++;
    final secs = math.min(30, 1 << math.min(attempt, 5));
    _retry = Timer(Duration(seconds: secs), () {
      if (!_closing && status == RemoteStatus.failed) _connect();
    });
  }

  /// Seconds until the next automatic try (for the status card).
  int get retryInSeconds => math.min(30, 1 << math.min(attempt, 5));
  bool get willRetry => _retry?.isActive ?? false;

  Future<void> _teardown({required bool sendBye}) async {
    _offerTimeout?.cancel();
    _dropGrace?.cancel();
    final ws = _ws;
    final pc = _pc;
    final ctl = _ctl;
    _ws = null;
    _pc = null;
    _ctl = null;
    _remoteSet = false;
    _pendingIce.clear();
    _lastBytes = null;
    if (hasVideo) {
      hasVideo = false;
      renderer.srcObject = null;
    }
    if (ws != null) {
      if (sendBye) {
        try {
          ws.add(SignalOut.bye(_sid, 'viewer closed'));
        } catch (_) {}
      }
      unawaited(ws.close().catchError((_) {}));
    }
    _sid = null;
    try {
      await ctl?.close();
    } catch (_) {}
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
  }

  void _signal(String frame) {
    try {
      _ws?.add(frame);
    } catch (_) {}
  }

  void _startTimers(int gen) {
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 2), (_) {
      if (gen != _gen) return;
      send(Ctl.ping(_nowMs()));
    });
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (gen == _gen && statsEnabled) _pollStats();
    });
  }

  Future<void> _pollStats() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final reports = await pc.getStats();
      double? fps;
      double? kbps;
      double? rtt;
      int? w;
      int? h;
      String? codecId;
      String? decoder;
      final codecs = <String, String>{};
      for (final r in reports) {
        final v = r.values;
        if (r.type == 'codec') {
          codecs[r.id] = (v['mimeType'] ?? '').toString().split('/').last;
        }
        if (r.type == 'inbound-rtp' &&
            (v['kind'] == 'video' || v['mediaType'] == 'video')) {
          fps = _toD(v['framesPerSecond']);
          w = _toD(v['frameWidth'])?.toInt();
          h = _toD(v['frameHeight'])?.toInt();
          codecId = v['codecId']?.toString();
          decoder = v['decoderImplementation']?.toString();
          final bytes = _toD(v['bytesReceived'])?.toInt();
          final at = r.timestamp;
          if (bytes != null) {
            if (_lastBytes != null && _lastBytesAt != null) {
              // timestamps are in ms (or µs on some builds)
              var dt = (at - _lastBytesAt!) / 1000;
              if (dt > 100) dt /= 1000;
              if (dt > 0) kbps = (bytes - _lastBytes!) * 8 / 1000 / dt;
            }
            _lastBytes = bytes;
            _lastBytesAt = at;
          }
        }
        if (r.type == 'candidate-pair' &&
            (v['state'] == 'succeeded') &&
            v['currentRoundTripTime'] != null) {
          rtt = (_toD(v['currentRoundTripTime']) ?? 0) * 1000;
        }
      }
      stats = RemoteStats(
        fps: fps,
        kbps: kbps ?? stats.kbps,
        rttMs: _rttApp ?? rtt,
        width: w,
        height: h,
        encMs: stats.encMs,
        codec: codecId == null ? stats.codec : codecs[codecId],
        decoder: decoder ?? stats.decoder,
      );
      _notify();
    } catch (_) {}
  }

  void _cancelTimers() {
    _retry?.cancel();
    _ping?.cancel();
    _statsTimer?.cancel();
    _dropGrace?.cancel();
    _offerTimeout?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static double? _toD(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static bool _retryable(Object e) {
    final s = '$e';
    return !(s.contains('401') || s.contains('403') || s.contains('404'));
  }

  static String _connectError(Object e) {
    final s = '$e';
    if (s.contains('401') || s.contains('403')) {
      return 'Token Kantor ditolak. Periksa di Pengaturan Kantor.';
    }
    if (s.contains('404')) {
      return 'Kantor belum punya fitur Remote. Perbarui kantor-claude.';
    }
    if (e is TimeoutException || e is SocketException) {
      return 'Kantor tidak terjangkau. Nyalakan Tailscale di HP ini.';
    }
    return 'Tidak bisa membuka sesi: $s';
  }

  static String _friendlyError(String m) {
    final s = m.toLowerCase();
    if (s.contains('offline') ||
        s.contains('not online') ||
        s.contains('tidak online')) {
      return 'Mac sedang offline. Pastikan Mac menyala dan ravel-host berjalan.';
    }
    if (s.contains('busy') ||
        s.contains('penuh') ||
        s.contains('max') ||
        s.contains('dipakai')) {
      return 'Mac sedang dipakai sesi lain (maksimal tercapai).';
    }
    return m;
  }
}
