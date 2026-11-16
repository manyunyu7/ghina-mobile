import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import 'terminal_clipboard.dart';
import 'terminal_prefs.dart';
import 'terminal_scroll.dart';
import 'terminal_themes.dart';

/// Live terminal of a session (`{kind: 'session', sid}`) or a room shell
/// (`{kind: 'shell', office, room}`) through the daemon's `/ws/term`.
/// Input goes out raw; resizing is `'\x00' + json {cols, rows}`.
class KantorTerminalPanel extends ConsumerStatefulWidget {
  const KantorTerminalPanel({
    super.key,
    required this.query,
    this.active = true,
  });

  /// Query of `/ws/term` without `cols` / `rows`.
  final Map<String, String> query;

  /// False while another tab is showing: the terminal gives up the keyboard
  /// focus and stays out of focus traversal.
  final bool active;

  factory KantorTerminalPanel.session(
    String sid, {
    Key? key,
    bool active = true,
  }) => KantorTerminalPanel(
    key: key,
    active: active,
    query: {'kind': 'session', 'sid': sid},
  );

  factory KantorTerminalPanel.shell(String office, String room, {Key? key}) =>
      KantorTerminalPanel(
        key: key,
        query: {'kind': 'shell', 'office': office, 'room': room},
      );

  @override
  ConsumerState<KantorTerminalPanel> createState() =>
      _KantorTerminalPanelState();
}

class _KantorTerminalPanelState extends ConsumerState<KantorTerminalPanel>
    with AutomaticKeepAliveClientMixin {
  // a swipe scrolls the tmux pane (copy mode): see TermWheelHandler
  final _wheel = TermWheelHandler();
  late final _terminal = Terminal(maxLines: 5000, mouseHandler: _wheel);
  final _controller = TerminalController();
  final _focus = FocusNode();
  WebSocket? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _resizeTimer;
  Timer? _fallback;
  ByteConversionSink? _bytes;
  bool _ctrl = false;
  bool _connecting = false;
  bool _closed = false;
  int _cols = 80;
  int _rows = 24;
  bool _sized = false;
  // ada seleksi di layar: bar terminal menampilkan tombol "Salin"
  bool _selecting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _onOutput;
    _terminal.onResize = _onResize;
    _controller.addListener(_onSelection);
    // normally the first layout reports the real size; if it never does
    // (hidden tab), connect with the default size after a moment
    _fallback = Timer(const Duration(milliseconds: 1500), () {
      if (!_sized) _connect();
    });
  }

  @override
  void didUpdateWidget(KantorTerminalPanel old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _focus.unfocus();
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _resizeTimer?.cancel();
    _sub?.cancel();
    _ws?.close();
    _focus.dispose();
    _controller
      ..removeListener(_onSelection)
      ..dispose();
    super.dispose();
  }

  void _onResize(int w, int h, int pw, int ph) {
    _cols = w;
    _rows = h;
    if (!_sized) {
      _sized = true;
      // dipanggil dari layout xterm: setState di _connect harus menunggu
      // frame ini selesai
      scheduleMicrotask(_connect);
      return;
    }
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 160), () {
      final ws = _ws;
      if (ws != null && ws.readyState == WebSocket.open) {
        ws.add('\x00${jsonEncode({'cols': _cols, 'rows': _rows})}');
      }
    });
  }

  void _onOutput(String data) {
    final mouse = _wheel.isOwn(data);
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    if (mouse) {
      ws.add(data);
      return;
    }
    var out = data;
    if (_ctrl) {
      setState(() => _ctrl = false);
      if (data.length == 1 && RegExp('[a-zA-Z]').hasMatch(data)) {
        out = String.fromCharCode(data.toUpperCase().codeUnitAt(0) - 64);
      }
    }
    ws.add(_live(out));
  }

  /// [input] preceded by the wheel-downs that bring a scrolled-back pane to
  /// the live end, so typing never lands in tmux copy mode.
  String _live(String input) => '${_wheel.release()}$input';

  void _send(String seq) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) ws.add(_live(seq));
    if (_ctrl) setState(() => _ctrl = false);
  }

  Future<void> _connect() async {
    final api = ref.read(kantorApiProvider);
    if (api == null || _connecting) return;
    _connecting = true;
    _fallback?.cancel();
    if (mounted) setState(() => _closed = false);
    await _sub?.cancel();
    try {
      final ws = await api.connectWs(
        '/ws/term',
        query: {...widget.query, 'cols': '$_cols', 'rows': '$_rows'},
      );
      _ws = ws;
      _wheel.reset();
      _bytes?.close();
      _bytes = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(_TermSink(_terminal));
      _sub = ws.listen(
        (d) {
          if (d is String) {
            _terminal.write(d);
          } else if (d is List<int>) {
            _bytes?.add(d);
          }
        },
        onDone: _onClosed,
        onError: (_) {
          _terminal.write(
            '\r\n\x1b[31m[gagal tersambung ke terminal]\x1b[0m\r\n',
          );
          _onClosed();
        },
      );
    } catch (e) {
      _terminal.write('\r\n\x1b[31m[gagal tersambung ke terminal]\x1b[0m\r\n');
      _onClosed();
    } finally {
      _connecting = false;
    }
  }

  void _onClosed() {
    _terminal.write('\r\n\x1b[2m[koneksi terminal tertutup]\x1b[0m\r\n');
    if (mounted) setState(() => _closed = true);
  }

  void _arrow(String letter) =>
      _send('${_terminal.cursorKeysMode ? '\x1bO' : '\x1b['}$letter');

  void _onSelection() {
    final on = _controller.selection != null;
    if (on != _selecting && mounted) setState(() => _selecting = on);
  }

  void _toast(String message, {bool ok = true}) => showToastBadge(
    context,
    message: message,
    icon: ok ? Icons.check_rounded : Icons.info_outline_rounded,
    color: ok ? GhinaColors.green : GhinaColors.orange,
    tag: 'kantor-term-clip',
    haptics: false,
  );

  /// Salin teks yang dipilih (tekan lama / seret mouse), lalu lepas seleksi.
  Future<void> _copySelection() async {
    final text = termSelectionText(_terminal, _controller);
    if (text == null) {
      _toast('Belum ada teks yang dipilih', ok: false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _controller.clearSelection();
    if (mounted) _toast('Disalin');
  }

  /// Salin seluruh layar yang terlihat: jalan pintas yang selalu berhasil.
  Future<void> _copyScreen() async {
    final text = termScreenText(_terminal);
    if (text.isEmpty) {
      _toast('Layar masih kosong', ok: false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('Layar disalin');
  }

  /// Tempel isi clipboard ke sesi lewat jalur input websocket yang sama
  /// dengan ketikan ([Terminal.paste] -> [_onOutput]). Kalau program memakai
  /// bracketed paste (Claude Code, shell modern), teks multi-baris masuk
  /// sebagai satu tempelan; kalau tidak, minta konfirmasi dulu karena tiap
  /// baris baru akan terkirim sebagai Enter.
  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final text = d?.text;
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      _toast('Clipboard kosong', ok: false);
      return;
    }
    final ready = pasteReady(text);
    final enters = pasteEnters(_terminal, ready);
    if (enters > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Tempel teks multi-baris?'),
          content: Text(
            'Program di terminal tidak memakai tempel aman, jadi $enters '
            'baris baru akan terkirim sebagai Enter (perintah bisa langsung '
            'jalan).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Tempel'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _controller.clearSelection();
    _terminal.paste(ready);
  }

  /// Salin-tempel dari keyboard fisik; tombol lain diteruskan ke xterm.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    switch (termClipKey(event, hasSelection: _controller.selection != null)) {
      case TermClipKey.copy:
        _copySelection();
        return KeyEventResult.handled;
      case TermClipKey.paste:
        _paste();
        return KeyEventResult.handled;
      case TermClipKey.swallow:
        return KeyEventResult.handled;
      case null:
        return KeyEventResult.ignored;
    }
  }

  void _zoom(double d) => ref
      .read(terminalPrefsProvider.notifier)
      .update((p) => p.copyWith(fontSize: p.fontSize + d));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final g = context.ghina;
    final look = ref.watch(terminalPrefsProvider);
    final font = look.fontSize;
    return Column(
      children: [
        Container(
          color: g.surface,
          padding: const EdgeInsets.symmetric(
            horizontal: GhinaSpace.md,
            vertical: 2,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _closed ? g.textMuted : GhinaColors.green.base,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _closed ? 'terputus' : 'live',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
              if (_closed)
                TextButton(
                  onPressed: _connect,
                  child: const Text('Sambung ulang'),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Perkecil huruf',
                icon: const Icon(Icons.remove_rounded, size: 18),
                onPressed: font > termFontMin ? () => _zoom(-1) : null,
              ),
              Text(
                '${font.round()}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Perbesar huruf',
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: font < termFontMax ? () => _zoom(1) : null,
              ),
              if (_selecting)
                TextButton.icon(
                  key: const ValueKey('term-copy'),
                  onPressed: _copySelection,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Salin'),
                )
              else
                IconButton(
                  key: const ValueKey('term-copy-screen'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Salin layar',
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  onPressed: _copyScreen,
                ),
              IconButton(
                key: const ValueKey('term-paste'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Tempel',
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                onPressed: _paste,
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _focus.requestFocus,
            child: TerminalView(
              _terminal,
              controller: _controller,
              focusNode: _focus,
              autofocus: false,
              hardwareKeyboardOnly: false,
              theme: look.themeDef.toTerminalTheme(),
              textStyle: TerminalStyle(
                fontSize: font,
                fontFamily: look.face.family,
                fontFamilyFallback: TermFace.fallback,
              ),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              keyboardType: TextInputType.visiblePassword,
              deleteDetection: true,
              // salin-tempel ditangani _onKey; tanpa shortcut bawaan xterm,
              // Ctrl+A kembali ke shell (bukan "pilih semua")
              shortcuts: const {},
              onKeyEvent: _onKey,
            ),
          ),
        ),
        _KeyBar(
          ctrl: _ctrl,
          onCtrl: () => setState(() => _ctrl = !_ctrl),
          onSeq: _send,
          onArrow: _arrow,
        ),
      ],
    );
  }
}

/// Feeds decoded text from the byte decoder into the terminal.
class _TermSink implements Sink<String> {
  _TermSink(this._t);
  final Terminal _t;
  @override
  void add(String data) => _t.write(data);
  @override
  void close() {}
}

class _KeyBar extends StatelessWidget {
  const _KeyBar({
    required this.ctrl,
    required this.onCtrl,
    required this.onSeq,
    required this.onArrow,
  });

  final bool ctrl;
  final VoidCallback onCtrl;
  final void Function(String seq) onSeq;
  final void Function(String letter) onArrow;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget key(String label, VoidCallback f, {bool on = false}) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? GhinaColors.orange.base : g.surfaceAlt,
        borderRadius: GhinaRadii.rMd,
        child: InkWell(
          borderRadius: GhinaRadii.rMd,
          onTap: f,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: GhinaType.bodyS
                  .w(800)
                  .copyWith(color: on ? GhinaColors.orange.on : g.textPrimary),
            ),
          ),
        ),
      ),
    );
    return Container(
      color: g.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: GhinaSpace.sm,
        vertical: 4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            key('Esc', () => onSeq('\x1b')),
            key('Tab', () => onSeq('\t')),
            key('Ctrl', onCtrl, on: ctrl),
            key('↑', () => onArrow('A')),
            key('↓', () => onArrow('B')),
            key('←', () => onArrow('D')),
            key('→', () => onArrow('C')),
            key('⇧Tab', () => onSeq('\x1b[Z')),
            key('⏎', () => onSeq('\r')),
            key('^C', () => onSeq('\x03')),
            key('/', () => onSeq('/')),
          ],
        ),
      ),
    );
  }
}
