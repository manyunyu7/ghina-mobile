import 'dart:convert';

/// Ravel Remote protocol v1 (ravel-remote/docs/PROTOCOL.md): the JSON shapes
/// the app exchanges with kantor-claude (signaling) and with ravel-host (the
/// `ctl` DataChannel). Pure Dart so it can be unit tested.

/// Max text per `txt`/`clip` message (1 MB in the contract; counted in UTF-8).
const kRemoteTextLimit = 1000000;

/// One display of a Mac.
class RemoteDisplay {
  const RemoteDisplay({
    required this.id,
    required this.name,
    required this.w,
    required this.h,
    this.scale = 1,
  });

  final int id;
  final String name;
  final int w;
  final int h;
  final double scale;

  static RemoteDisplay? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    if (id == null) return null;
    return RemoteDisplay(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : 'Layar $id',
      w: _int(raw['w']) ?? 0,
      h: _int(raw['h']) ?? 0,
      scale: _num(raw['scale'])?.toDouble() ?? 1,
    );
  }

  String get sizeLabel => w > 0 && h > 0 ? '$w×$h' : '';
}

/// An entry of `GET /api/remote/hosts`.
class RemoteHost {
  const RemoteHost({
    required this.machine,
    required this.name,
    required this.online,
    this.displays = const [],
    this.version = '',
    this.busy = false,
  });

  final String machine;
  final String name;
  final bool online;
  final List<RemoteDisplay> displays;
  final String version;
  final bool busy;

  static RemoteHost? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final machine = raw['machine'];
    if (machine is! String || machine.isEmpty) return null;
    final displays = raw['displays'];
    return RemoteHost(
      machine: machine,
      name: raw['name'] is String && (raw['name'] as String).isNotEmpty
          ? raw['name'] as String
          : machine,
      online: raw['online'] == true,
      displays: displays is List
          ? displays
                .map(RemoteDisplay.fromJson)
                .whereType<RemoteDisplay>()
                .toList()
          : const [],
      version: raw['version']?.toString() ?? '',
      // `busy` may be a bool or a session count
      busy: raw['busy'] == true || (_num(raw['busy']) ?? 0) > 0,
    );
  }

  /// Accepts a bare list or `{hosts: [...]}`.
  static List<RemoteHost> listFromJson(Object? raw) {
    final list = raw is Map ? raw['hosts'] : raw;
    if (list is! List) return const [];
    final hosts = list.map(fromJson).whereType<RemoteHost>().toList();
    hosts.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return hosts;
  }
}

// ---------------------------------------------------------------------------
// Signaling (WebSocket to kantor-claude)

sealed class SignalMessage {
  const SignalMessage();

  /// Parses one WS text frame. Unknown types come back as [SignalOther].
  static SignalMessage? decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final session = json['session']?.toString();
    switch (json['type']) {
      case 'ready':
        return SignalReady(session, json['fingerprint']?.toString());
      case 'error':
        return SignalError(json['message']?.toString() ?? 'Kesalahan sesi.');
      case 'offer':
        final sdp = json['sdp'];
        return sdp is String ? SignalOffer(session, sdp) : null;
      case 'ice':
        final c = json['candidate'];
        if (c is! String) return null;
        return SignalIce(
          session,
          c,
          json['sdpMid']?.toString(),
          _int(json['sdpMLineIndex']),
        );
      case 'bye':
        return SignalBye(session, json['reason']?.toString());
      default:
        return SignalOther(json['type']?.toString() ?? '');
    }
  }
}

class SignalReady extends SignalMessage {
  const SignalReady(this.session, [this.fingerprint]);
  final String? session;

  /// DTLS fingerprint the Mac registered with (`sha-256 AB:CD:…`).
  final String? fingerprint;
}

class SignalError extends SignalMessage {
  const SignalError(this.message);
  final String message;
}

class SignalOffer extends SignalMessage {
  const SignalOffer(this.session, this.sdp);
  final String? session;
  final String sdp;
}

class SignalIce extends SignalMessage {
  const SignalIce(this.session, this.candidate, this.sdpMid, this.mLineIndex);
  final String? session;
  final String candidate;
  final String? sdpMid;
  final int? mLineIndex;
}

class SignalBye extends SignalMessage {
  const SignalBye(this.session, this.reason);
  final String? session;
  final String? reason;
}

class SignalOther extends SignalMessage {
  const SignalOther(this.type);
  final String type;
}

abstract final class SignalOut {
  static String answer(String? session, String sdp) =>
      jsonEncode({'type': 'answer', 'session': ?session, 'sdp': sdp});

  static String ice(
    String? session,
    String candidate,
    String? sdpMid,
    int? mLineIndex,
  ) => jsonEncode({
    'type': 'ice',
    'session': ?session,
    'candidate': candidate,
    'sdpMid': ?sdpMid,
    'sdpMLineIndex': ?mLineIndex,
  });

  static String bye(String? session, String reason) =>
      jsonEncode({'type': 'bye', 'session': ?session, 'reason': reason});
}

// ---------------------------------------------------------------------------
// `ctl` DataChannel: viewer → host

/// Mouse buttons as the protocol numbers them.
enum RemoteButton {
  left(0),
  right(1),
  middle(2);

  const RemoteButton(this.code);
  final int code;
}

/// Modifiers for `key` messages, in the contract's spelling.
enum RemoteMod {
  meta('meta', 'MetaLeft'),
  ctrl('ctrl', 'ControlLeft'),
  alt('alt', 'AltLeft'),
  shift('shift', 'ShiftLeft');

  const RemoteMod(this.wire, this.code);
  final String wire;

  /// W3C code of the left-hand key, for kd/ku of a held modifier.
  final String code;
}

/// Builders for every viewer → host message. Each returns the JSON map; use
/// [encodeCtl] to turn it into the text frame.
abstract final class Ctl {
  static Map<String, Object?> moveAbs(double x, double y) => {
    't': 'mm',
    'x': _unit(x),
    'y': _unit(y),
  };

  static Map<String, Object?> moveRel(double dx, double dy) => {
    't': 'mr',
    'dx': _round(dx),
    'dy': _round(dy),
  };

  static Map<String, Object?> down(RemoteButton b) => {'t': 'md', 'b': b.code};
  static Map<String, Object?> up(RemoteButton b) => {'t': 'mu', 'b': b.code};

  static Map<String, Object?> click(RemoteButton b, [int n = 1]) => {
    't': 'click',
    'b': b.code,
    'n': n.clamp(1, 3),
  };

  static Map<String, Object?> wheel(double dx, double dy) => {
    't': 'wh',
    'dx': _round(dx),
    'dy': _round(dy),
  };

  static Map<String, Object?> keyDown(String code) => {'t': 'kd', 'code': code};
  static Map<String, Object?> keyUp(String code) => {'t': 'ku', 'code': code};

  static Map<String, Object?> key(
    String code, [
    Iterable<RemoteMod> mods = const [],
  ]) {
    // stable order so equal shortcuts encode equally
    final sorted = RemoteMod.values.where(mods.contains).map((m) => m.wire);
    return {'t': 'key', 'code': code, 'mods': sorted.toList()};
  }

  static Map<String, Object?> text(String s) => {'t': 'txt', 's': clampText(s)};
  static Map<String, Object?> clip(String s) => {
    't': 'clip',
    's': clampText(s),
  };

  static Map<String, Object?> cfg({
    int? display,
    int? maxFps,
    int? maxW,
    int? maxH,
    int? bitrate,
    RemoteQuality? quality,
    RemoteCursorMode? cursor,
  }) => {
    't': 'cfg',
    'display': ?display,
    'maxFps': ?maxFps,
    'maxW': ?maxW,
    'maxH': ?maxH,
    'bitrate': ?bitrate,
    'quality': ?quality?.wire,
    'cursor': ?cursor?.name,
  };

  /// Virtual display sized like this device (CGVirtualDisplay on the Mac).
  /// [w]/[h] in points, [scale] 1..3. `on:false` removes it.
  static Map<String, Object?> virtualDisplay({
    required bool on,
    int? w,
    int? h,
    int? scale,
    String? name,
  }) => {
    't': 'vd',
    'on': on,
    'w': ?w,
    'h': ?h,
    'scale': ?scale?.clamp(1, 3),
    'name': ?name,
  };

  static Map<String, Object?> ping(int ts) => {'t': 'ping', 'ts': ts};
  static Map<String, Object?> release() => {'t': 'release'};

  static double _unit(double v) => _round(v.clamp(0.0, 1.0), 10000);
  static double _round(double v, [double k = 100]) => (v * k).round() / k;
}

String encodeCtl(Map<String, Object?> msg) => jsonEncode(msg);

/// Cuts [s] so its UTF-8 size stays within [kRemoteTextLimit].
String clampText(String s) {
  if (s.length * 3 <= kRemoteTextLimit) return s;
  final bytes = utf8.encode(s);
  if (bytes.length <= kRemoteTextLimit) return s;
  return utf8
      .decode(bytes.sublist(0, kRemoteTextLimit), allowMalformed: true)
      .replaceAll('�', '');
}

/// Who draws the pointer: `local` = the app (from `cursor` messages, the Mac
/// stops burning it into the video), `video` = it is part of the picture.
enum RemoteCursorMode { local, video }

enum RemoteQuality {
  auto('auto', 'Otomatis'),
  sharp('tajam', 'Tajam'),
  saver('hemat', 'Hemat');

  const RemoteQuality(this.wire, this.label);
  final String wire;
  final String label;
}

// ---------------------------------------------------------------------------
// `ctl` DataChannel: host → viewer

sealed class HostMessage {
  const HostMessage();

  static HostMessage? decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    switch (json['t']) {
      case 'hello':
        final perms = json['perms'];
        final displays = json['displays'];
        return HostHello(
          machine: json['machine']?.toString() ?? '',
          name: json['name']?.toString() ?? '',
          displays: displays is List
              ? displays
                    .map(RemoteDisplay.fromJson)
                    .whereType<RemoteDisplay>()
                    .toList()
              : const [],
          display: _int(json['display']),
          w: _int(json['w']) ?? 0,
          h: _int(json['h']) ?? 0,
          screenPerm: perms is Map ? perms['screen'] != false : true,
          inputPerm: perms is Map ? perms['input'] != false : true,
        );
      case 'display':
        return HostDisplay(
          _int(json['display']),
          _int(json['w']) ?? 0,
          _int(json['h']) ?? 0,
        );
      case 'cursor':
        final x = _num(json['x']);
        final y = _num(json['y']);
        if (x == null || y == null) return null;
        return HostCursor(
          x.toDouble(),
          y.toDouble(),
          json['visible'] != false,
          json['shape']?.toString(),
        );
      case 'clip':
        final s = json['s'];
        return s is String ? HostClip(s) : null;
      case 'pong':
        return HostPong(_int(json['ts']) ?? 0, _int(json['hostTs']));
      case 'stats':
        return HostStats(
          fps: _num(json['fps'])?.toDouble(),
          kbps: _num(json['kbps'])?.toDouble(),
          encMs: _num(json['encMs'])?.toDouble(),
        );
      case 'warn':
        return HostWarn(json['message']?.toString() ?? '');
      default:
        return null;
    }
  }
}

class HostHello extends HostMessage {
  const HostHello({
    required this.machine,
    required this.name,
    required this.displays,
    required this.display,
    required this.w,
    required this.h,
    required this.screenPerm,
    required this.inputPerm,
  });

  final String machine;
  final String name;
  final List<RemoteDisplay> displays;
  final int? display;
  final int w;
  final int h;
  final bool screenPerm;
  final bool inputPerm;
}

class HostDisplay extends HostMessage {
  const HostDisplay(this.display, this.w, this.h);
  final int? display;
  final int w;
  final int h;
}

class HostCursor extends HostMessage {
  const HostCursor(this.x, this.y, this.visible, this.shape);
  final double x;
  final double y;
  final bool visible;
  final String? shape;
}

class HostClip extends HostMessage {
  const HostClip(this.text);
  final String text;
}

class HostPong extends HostMessage {
  const HostPong(this.ts, this.hostTs);
  final int ts;
  final int? hostTs;
}

class HostStats extends HostMessage {
  const HostStats({this.fps, this.kbps, this.encMs});
  final double? fps;
  final double? kbps;
  final double? encMs;
}

class HostWarn extends HostMessage {
  const HostWarn(this.message);
  final String message;
}

num? _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);
int? _int(Object? v) => _num(v)?.toInt();
