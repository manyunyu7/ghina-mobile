import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import 'chat_model.dart';
import 'kantor_feed.dart';

/// Jarak ulang `POST /api/sessions/:sid/watch` (daemon menyimpan ttl 30 dtk).
const kantorWatchEvery = Duration(seconds: 20);

/// Meminta daemon membaca teks yang sedang ditulis agen di layar terminalnya
/// selama chat sesi ini terlihat: `POST /watch` diulang tiap
/// [kantorWatchEvery], dan sekali `GET /stream` tiap kali mulai terlihat untuk
/// keadaan awal. Daemon lama (404) atau gagal: diam saja dan berhenti; 404
/// tidak dicoba lagi sampai chat dibuka ulang (State baru), gagal lain dicoba
/// lagi saat chat terlihat kembali.
class KantorStreamWatch {
  KantorStreamWatch({
    required this.api,
    required this.sid,
    required this.onStream,
  });

  final KantorApi api;
  final String sid;

  /// Jawaban `GET /stream` (`{text, seq, at}`), diperlakukan seperti event WS.
  final void Function(Json) onStream;

  Timer? _timer;
  bool _on = false;
  bool _gone = false;
  bool _streamGone = false;
  bool _disposed = false;
  bool _pinging = false;

  /// Sedang mengulang `POST /watch`.
  bool get running => _timer != null;

  /// Hidupkan / matikan sesuai terlihat-tidaknya chat.
  void set(bool on) {
    if (_disposed || on == _on) return;
    _on = on;
    if (!on) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_gone) return;
    _timer = Timer.periodic(kantorWatchEvery, (_) => _ping());
    unawaited(_ping());
    unawaited(_initial());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ping() async {
    if (_pinging || _disposed) return;
    _pinging = true;
    try {
      await api.post('/api/sessions/$sid/watch', const <String, dynamic>{});
    } on KantorException catch (e) {
      // daemon lama tanpa rute watch: jangan diulang selama chat ini terbuka
      if (e.kind == KantorFailure.notFound) _gone = true;
      _stop();
    } catch (_) {
      _stop(); // dicoba lagi saat chat terlihat kembali
    } finally {
      _pinging = false;
    }
  }

  Future<void> _initial() async {
    if (_streamGone || _disposed) return;
    try {
      final r = await api.get('/api/sessions/$sid/stream');
      if (_disposed || !_on || r is! Map) return;
      onStream(Map<String, dynamic>.from(r));
    } on KantorException catch (e) {
      if (e.kind == KantorFailure.notFound) _streamGone = true;
    } catch (_) {
      // keadaan awal hanya pelengkap: event WS berikutnya tetap membawa teks
    }
  }
}

final _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _norm(String s) => s.toLowerCase().replaceAll(_notWord, '');

/// Teks sementara [live] sudah tercatat sebagai pesan asisten terakhir di
/// transkrip (sama, atau masih awalannya karena layar tertinggal). Dibanding
/// tanpa tanda baca, spasi, dan markdown: layar terminal membungkus baris dan
/// merender markdown, transkrip menyimpan teks mentahnya.
bool kantorStreamCovered(String live, List<ChatEntry> entries) {
  final s = _norm(live);
  if (s.isEmpty) return true;
  var seen = 0;
  for (var i = entries.length - 1; i >= 0 && seen < 3; i--) {
    final e = entries[i];
    if (e is UserEntry) break; // giliran sebelumnya bukan jawaban ini
    if (e is! ClaudeEntry) continue;
    seen++;
    final c = _norm(e.text);
    if (c.startsWith(s)) return true;
    const head = 40;
    if (s.length >= head &&
        c.length >= head &&
        s.substring(0, head) == c.substring(0, head)) {
      return true;
    }
  }
  return false;
}

/// Pesan asisten terakhir di [entries] (untuk tahu apakah jawaban final baru
/// saja masuk).
ClaudeEntry? kantorLastClaude(List<ChatEntry> entries) {
  for (var i = entries.length - 1; i >= 0; i--) {
    final e = entries[i];
    if (e is ClaudeEntry) return e;
  }
  return null;
}

/// Isi bubble "sedang menulis": teks polos yang muncul bertahap (per frame,
/// paling banyak 60 karakter) sampai teks terbaru, baris kode monospace, dan
/// tanda pena + titik berkedip. [follow] false (pengguna sedang membaca ke
/// atas): teks berhenti tumbuh supaya isi chat tidak bergeser.
class KantorLiveText extends StatefulWidget {
  const KantorLiveText({
    super.key,
    required this.text,
    this.follow = true,
    this.lineHeight = 1.45,
    this.codeScale = 1,
  });

  final String text;
  final bool follow;
  final double lineHeight;
  final double codeScale;

  @override
  State<KantorLiveText> createState() => _KantorLiveTextState();
}

class _KantorLiveTextState extends State<KantorLiveText>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  /// Banyak karakter yang sudah tampil.
  int _n = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _kick();
  }

  @override
  void didUpdateWidget(KantorLiveText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // teks diganti (bukan hanya bertambah): mundur ke awalan yang sama
      final a = old.text, b = widget.text;
      final max = math.min(_n, math.min(a.length, b.length));
      var p = 0;
      while (p < max && a.codeUnitAt(p) == b.codeUnitAt(p)) {
        p++;
      }
      if (_n > p) _n = p;
    }
    _kick();
  }

  void _kick() {
    final more = _n < widget.text.length && widget.follow;
    if (more && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!more && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final len = widget.text.length;
    final rest = len - _n;
    if (rest <= 0 || !widget.follow) {
      _ticker.stop();
      return;
    }
    // cepat mengejar teks terbaru, tapi tidak melompat kasar
    final ms = math.max(16, dt.inMilliseconds);
    final step = (rest * ms / 90).ceil().clamp(1, 60);
    var n = math.min(len, _n + step);
    // jangan memotong pasangan surrogate (emoji)
    if (n < len && n > 0) {
      final u = widget.text.codeUnitAt(n - 1);
      if (u >= 0xD800 && u <= 0xDBFF) n++;
    }
    setState(() => _n = n);
    if (_n >= len) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final body = GhinaType.body.copyWith(
      color: g.textPrimary,
      height: widget.lineHeight,
    );
    final mono = body.copyWith(
      fontFamily: 'monospace',
      fontSize: 13 * widget.codeScale,
      backgroundColor: g.surfaceAlt,
    );
    final shown = widget.text.substring(0, math.min(_n, widget.text.length));
    final lines = shown.split('\n');
    final spans = <InlineSpan>[];
    var fence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.trimLeft().startsWith('```')) {
        fence = !fence; // pagar kode tidak ditampilkan
        continue;
      }
      final code = fence || line.startsWith('    ') || line.startsWith('\t');
      spans.add(
        TextSpan(
          text: spans.isEmpty ? line : '\n$line',
          style: code ? mono : null,
        ),
      );
    }
    final muted = GhinaType.caption.copyWith(color: g.textMuted);
    return Column(
      key: const ValueKey('chat-live-text'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown.isNotEmpty) Text.rich(TextSpan(children: spans), style: body),
        Padding(
          padding: EdgeInsets.only(top: shown.isEmpty ? 0 : 4),
          child: Row(
            key: const ValueKey('chat-live-label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 12, color: g.textMuted),
              const SizedBox(width: 4),
              Text('sedang menulis…', style: muted),
              const SizedBox(width: 4),
              FadeTransition(
                opacity: _blink,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: g.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
