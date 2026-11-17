import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
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
/// merender markdown, transkrip menyimpan teks mentahnya. [partial]: awal
/// jawaban tidak terlihat di layar, jadi [live] cukup ada di dalam pesan.
bool kantorStreamCovered(
  String live,
  List<ChatEntry> entries, {
  bool partial = false,
}) {
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
    if (partial) {
      if (c.contains(s)) return true;
      if (s.length >= head && c.contains(s.substring(0, head))) return true;
      continue;
    }
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

/// Isi bubble "sedang menulis": teks terbaru dan apakah awalnya tidak
/// terlihat di layar terminal (`partial: true` dari daemon).
typedef KantorLive = ({String text, bool partial});

/// Kecepatan dasar munculnya teks, grafem per detik.
const kantorLiveBase = 50.0;

/// Sisa teks yang belum tampil dikejar dalam waktu ini (detik).
const kantorLiveCatchUp = 0.9;

/// Lama crossfade bubble sementara ke bubble final (dan saat teks dikoreksi).
const kantorLiveFade = Duration(milliseconds: 150);

/// Laju munculnya teks untuk [backlog] grafem yang belum tampil: paling
/// lambat [kantorLiveBase], lebih cepat bila perlu supaya sisa teks terkejar
/// dalam [kantorLiveCatchUp] detik (ala ChatGPT: bongkah besar tetap mengalir,
/// tidak muncul sekaligus).
double kantorLiveRate(int backlog) =>
    math.max(kantorLiveBase, backlog / kantorLiveCatchUp);

bool _isSpace(String c) => c.trim().isEmpty;

/// Pagar kode di awal baris (paling banyak 3 spasi indentasi).
final _fenceRe = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Tautan yang alamatnya belum selesai di ujung teks: `[teks](http://exa`.
final _openLinkRe = RegExp(r'\[[^\]\n]*\]\([^)\s]*$');

/// Baris yang rusak bila kursor ditempel di ujungnya: garis/penanda daftar
/// saja, judul kosong, nomor daftar, baris tabel, HTML, atau pagar kode.
final _noCursorRe = RegExp(
  r'^([-*_=+\s]+|#{1,6}|\d{1,9}[.)]|.*\|.*|<.*|(`{3,}|~{3,}).*)$',
);

bool _closesFence(String line, String fence) {
  final t = line.trim();
  if (t.length < fence.length) return false;
  for (var i = 0; i < t.length; i++) {
    if (t[i] != fence[0]) return false;
  }
  return true;
}

/// Sumber markdown untuk ekor teks yang belum selesai ditulis. Penanda yang
/// masih terbuka ditutup sementara (pagar ```, `` ` ``, `**`, `*`, alamat
/// tautan) dan penanda pembuka yang belum berisi dibuang, supaya tidak ada
/// penanda mentah yang tampil lalu tiba-tiba hilang. [cursor]: tempel
/// [kantorCursorMark] di ujung bila letaknya aman (bukan di dalam blok kode,
/// baris tabel, atau penanda daftar/judul yang belum berisi).
String kantorLiveMarkdown(String src, {bool cursor = false}) {
  var s = src;
  // garis miring terbalik di paling ujung: karakter yang di-escape belum datang
  var slashes = 0;
  while (slashes < s.length && s[s.length - 1 - slashes] == r'\') {
    slashes++;
  }
  if (slashes.isOdd) s = s.substring(0, s.length - 1);

  // blok kode berpagar yang belum ditutup; awal paragraf terakhir
  String? fence;
  var para = 0;
  var pos = 0;
  for (final line in s.split('\n')) {
    final next = pos + line.length + 1;
    if (fence == null) {
      final m = _fenceRe.firstMatch(line);
      if (m != null) {
        fence = m[1];
      } else if (line.trim().isEmpty) {
        para = next;
      }
    } else if (_closesFence(line, fence)) {
      fence = null;
      para = next;
    }
    pos = next;
  }
  if (fence != null) return '$s${s.endsWith('\n') ? '' : '\n'}$fence';

  // penanda sebaris di paragraf terakhir (paragraf sebelumnya sudah selesai:
  // penanda yang tidak tertutup di sana memang teks biasa, sama dengan final)
  para = math.min(para, s.length);
  final p = s.substring(para);
  var code = 0; // panjang deret backtick pembuka kode sebaris
  var codeAt = -1;
  final open = <String>[];
  final openAt = <int>[];
  var i = 0;
  while (i < p.length) {
    final c = p[i];
    if (code == 0 && c == r'\') {
      i += 2;
      continue;
    }
    if (c == '`') {
      var j = i;
      while (j < p.length && p[j] == '`') {
        j++;
      }
      if (code == 0) {
        code = j - i;
        codeAt = para + i;
      } else if (j - i == code) {
        code = 0;
      }
      i = j;
      continue;
    }
    if (code > 0 || c != '*') {
      i++;
      continue;
    }
    var j = i;
    while (j < p.length && p[j] == '*') {
      j++;
    }
    final before = i == 0 ? ' ' : p[i - 1];
    final after = j < p.length ? p[j] : '';
    final ls = p.lastIndexOf('\n', i) + 1;
    final bullet = p.substring(ls, i).trim().isEmpty && (after == ' ');
    final canClose = !_isSpace(before);
    final canOpen = after.isEmpty || !_isSpace(after);
    if (!bullet && (canClose || canOpen)) {
      final k = j - i;
      for (final tok in [if (k >= 2) '**', if (k != 2) '*']) {
        final at = open.lastIndexOf(tok);
        if (canClose && at >= 0) {
          open.removeAt(at);
          openAt.removeAt(at);
        } else if (canOpen) {
          open.add(tok);
          openAt.add(para + i + (tok == '*' && k >= 3 ? 2 : 0));
        }
      }
    }
    i = j;
  }

  var out = s;
  if (code > 0) {
    if (out.substring(codeAt + code).trim().isEmpty) {
      // pembuka tanpa isi: belum ditampilkan
      out = out.substring(0, codeAt).trimRight();
    } else {
      out += '`' * code;
    }
  } else if (_openLinkRe.hasMatch(out)) {
    out += ')';
  }
  for (var k = open.length - 1; k >= 0; k--) {
    out = out.trimRight();
    final at = openAt[k];
    if (at >= out.length) continue;
    if (out.length <= at + open[k].length) {
      out = out.substring(0, at).trimRight();
    } else {
      out += open[k];
    }
  }

  if (cursor) {
    final t = out.trimRight();
    final last = t.substring(t.lastIndexOf('\n') + 1);
    final code4 = last.startsWith('    ') || last.startsWith('\t');
    if (t.isNotEmpty && !code4 && !_noCursorRe.hasMatch(last.trim())) {
      out = '$t$kantorCursorMark';
    }
  }
  return out;
}

/// Awal baris yang pasti memulai blok baru setelah baris kosong (bukan butir
/// daftar, lanjutan berindentasi, tabel, kutipan, atau HTML).
bool _blockStart(String line) {
  if (line.isEmpty) return false;
  final c = line[0];
  if (_isSpace(c)) return false;
  if ('-*+_=|><:0123456789'.contains(c)) return false;
  return true;
}

/// Titik potong [text]: kepala (blok yang sudah selesai, tidak berubah lagi
/// dan dirender sekali) dan ekor (blok terakhir yang masih tumbuh, dirender
/// ulang tiap frame). Hanya dipotong di baris kosong di luar blok kode,
/// sebelum baris yang jelas memulai blok baru, supaya hasilnya sama dengan
/// merender seluruh teks sekaligus.
int kantorLiveSplit(String text) {
  var cut = 0;
  var pos = 0;
  String? fence;
  var blank = false;
  for (final line in text.split('\n')) {
    if (fence != null) {
      if (_closesFence(line, fence)) fence = null;
      blank = false;
    } else if (line.trim().isEmpty) {
      blank = true;
    } else {
      if (blank && pos > 0 && _blockStart(line)) cut = pos;
      blank = false;
      fence = _fenceRe.firstMatch(line)?[1];
    }
    pos += line.length + 1;
  }
  return cut;
}

/// Ujung (code unit) tiap grafem [s]: teks dipotong hanya di batas grafem,
/// jadi emoji gabungan dan aksara multi-byte tidak pernah tampil separuh.
List<int> _graphemeEnds(String s) {
  final out = <int>[];
  var at = 0;
  for (final g in s.characters) {
    at += g.length;
    out.add(at);
  }
  return out;
}

/// Banyak grafem yang ujungnya paling jauh di [len].
int _countUpTo(List<int> ends, int len) {
  var lo = 0, hi = ends.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (ends[mid] <= len) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

final _space = RegExp(r'\s+');

/// Bubble "sedang menulis": teks muncul bertahap per frame dengan laju
/// [kantorLiveRate], dirender markdown dengan gaya yang sama dengan bubble
/// final ([KantorMarkdown]) plus kursor berkedip di ujungnya. [follow] false
/// (pengguna sedang membaca ke atas): teks berhenti tumbuh supaya isi chat
/// tidak bergeser. [animate] false: langsung tampil penuh (cuplikan untuk
/// crossfade ke final). [partial]: awal jawaban tidak terlihat di layar.
class KantorLiveText extends StatefulWidget {
  const KantorLiveText({
    super.key,
    required this.text,
    this.follow = true,
    this.animate = true,
    this.partial = false,
    this.lineHeight = 1.45,
    this.codeScale = 1,
    this.wrapCode = false,
  });

  final String text;
  final bool follow;
  final bool animate;
  final bool partial;
  final double lineHeight;
  final double codeScale;
  final bool wrapCode;

  @override
  State<KantorLiveText> createState() => _KantorLiveTextState();
}

class _KantorLiveTextState extends State<KantorLiveText>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  )..repeat(reverse: true);

  /// Ujung tiap grafem [KantorLiveText.text].
  late List<int> _ends;

  /// Grafem yang sudah tampil; [_shown] versi pecahannya (laju per frame).
  int _n = 0;
  double _shown = 0;
  double _rate = kantorLiveBase;
  Duration _last = Duration.zero;

  /// Naik tiap kali teks dikoreksi server (bukan perpanjangan): isi lama
  /// di-crossfade ke isi baru, bukan dihapus mundur huruf demi huruf.
  int _gen = 0;

  /// Kepala markdown (blok yang sudah selesai) dan widgetnya: widget yang
  /// sama dipakai ulang di tiap frame, jadi tidak dibangun/di-layout ulang.
  String? _headSrc;
  Widget? _head;

  @override
  void initState() {
    super.initState();
    _ends = _graphemeEnds(widget.text);
    _n = widget.animate ? 0 : _ends.length;
    _shown = _n.toDouble();
    _rate = kantorLiveRate(_ends.length - _n);
    _kick();
  }

  String _visible(String text, List<int> ends, int n) =>
      n <= 0 ? '' : text.substring(0, ends[math.min(n, ends.length) - 1]);

  @override
  void didUpdateWidget(KantorLiveText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      final before = _visible(old.text, _ends, _n);
      final count = _n;
      _ends = _graphemeEnds(widget.text);
      if (!widget.animate) {
        _n = _ends.length;
      } else if (widget.text.startsWith(before)) {
        // perpanjangan: lanjut dari yang sudah tampil
        _n = _countUpTo(_ends, before.length);
      } else {
        // dikoreksi: tetap tampilkan sebanyak tadi dari teks baru (tidak
        // mundur). Beda hanya di spasi/baris (layar dibungkus ulang): diganti
        // diam-diam; beda isi: crossfade singkat.
        final a = before.replaceAll(_space, '');
        final b = widget.text.replaceAll(_space, '');
        if (!b.startsWith(a)) _gen++;
        _n = math.min(count, _ends.length);
      }
      _shown = _n.toDouble();
      _rate = kantorLiveRate(_ends.length - _n);
    }
    if (old.lineHeight != widget.lineHeight ||
        old.codeScale != widget.codeScale ||
        old.wrapCode != widget.wrapCode) {
      _headSrc = null;
      _head = null;
    }
    _kick();
  }

  void _kick() {
    final more = _n < _ends.length && widget.follow && widget.animate;
    if (more && !_ticker.isActive) {
      _last = Duration.zero;
      _rate = kantorLiveRate(_ends.length - _n);
      _ticker.start();
    } else if (!more && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final total = _ends.length;
    if (_n >= total || !widget.follow) {
      _ticker.stop();
      return;
    }
    _shown = math.min(total.toDouble(), _shown + _rate * dt);
    final n = _shown.floor();
    if (n != _n) setState(() => _n = n);
    if (n >= total) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blink.dispose();
    super.dispose();
  }

  KantorMarkdown _md(String src, {Widget? cursor}) => KantorMarkdown(
    src,
    lineHeight: widget.lineHeight,
    codeScale: widget.codeScale,
    wrapCode: widget.wrapCode,
    cursor: cursor,
  );

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final muted = GhinaType.caption.copyWith(color: g.textMuted);
    final shown = _visible(widget.text, _ends, _n);
    final dot = FadeTransition(
      opacity: _blink,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: g.textMuted, shape: BoxShape.circle),
      ),
    );
    Widget? body;
    var inline = false;
    if (shown.isNotEmpty) {
      final cut = kantorLiveSplit(shown);
      final head = shown.substring(0, cut).trimRight();
      final tail = kantorLiveMarkdown(shown.substring(cut), cursor: true);
      inline = tail.endsWith(kantorCursorMark);
      if (head.isEmpty) {
        _headSrc = null;
        _head = null;
      } else if (head != _headSrc) {
        _headSrc = head;
        _head = RepaintBoundary(child: _md(head));
      }
      body = KeyedSubtree(
        key: ValueKey(_gen),
        child: Column(
          key: const ValueKey('chat-live-md'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_head != null) ...[_head!, const SizedBox(height: 8)],
            _md(
              tail,
              cursor: inline
                  ? Padding(padding: const EdgeInsets.only(left: 3), child: dot)
                  : null,
            ),
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('chat-live-text'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.partial)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              key: const ValueKey('chat-live-partial'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '…',
                  style: GhinaType.body.copyWith(
                    color: g.textMuted,
                    height: widget.lineHeight,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'awal jawaban tidak terlihat',
                    style: muted.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        AnimatedSwitcher(
          duration: kantorLiveFade,
          layoutBuilder: _topLeft,
          child: body,
        ),
        Padding(
          padding: EdgeInsets.only(top: shown.isEmpty ? 0 : 4),
          child: Row(
            key: const ValueKey('chat-live-label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 12, color: g.textMuted),
              const SizedBox(width: 4),
              Text('sedang menulis…', style: muted),
              // kursor tidak bisa sebaris (mis. di dalam blok kode): di sini
              if (!inline) ...[const SizedBox(width: 4), dot],
            ],
          ),
        ),
      ],
    );
  }
}

Widget _topLeft(Widget? current, List<Widget> previous) =>
    Stack(alignment: Alignment.topLeft, children: [...previous, ?current]);

/// Pergantian bubble "sedang menulis" ke jawaban final di tempat yang sama:
/// satu frame cuplikan bubble sementara [from] (sama persis dengan frame
/// sebelumnya), lalu crossfade [kantorLiveFade] ke [child]. Perubahan tinggi
/// dianimasikan (AnimatedSize, berpangkal di atas), jadi isi chat tidak
/// meloncat; di daftar terbalik dasar chat tetap di tempatnya.
class KantorHandoff extends StatefulWidget {
  const KantorHandoff({super.key, required this.from, required this.child});

  final Widget from;
  final Widget child;

  @override
  State<KantorHandoff> createState() => _KantorHandoffState();
}

class _KantorHandoffState extends State<KantorHandoff> {
  bool _final = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _final = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: kantorLiveFade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: _topLeft,
      child: _final
          ? KeyedSubtree(key: const ValueKey('final'), child: widget.child)
          : KeyedSubtree(
              key: const ValueKey('from'),
              child: IgnorePointer(child: widget.from),
            ),
    ),
  );
}
