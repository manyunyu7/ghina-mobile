import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../../di/di.dart';
import '../../../design_system/design_system.dart';

final _theme = TerminalTheme(
  cursor: GhinaColors.orange.base,
  selection: GhinaColors.blue.base.withValues(alpha: 0.35),
  foreground: const Color(0xFFD4DAE3),
  background: const Color(0xFF0E1218),
  black: const Color(0xFF1A2A31),
  red: GhinaColors.red.base,
  green: GhinaColors.green.base,
  yellow: GhinaColors.yellow.base,
  blue: GhinaColors.blue.base,
  magenta: GhinaColors.purple.base,
  cyan: const Color(0xFF2DD4BF),
  white: GhinaColors.darkTextSecondary,
  brightBlack: GhinaColors.darkTextMuted,
  brightRed: const Color(0xFFFF7A7A),
  brightGreen: GhinaColors.lime.base,
  brightYellow: const Color(0xFFFFE066),
  brightBlue: const Color(0xFF6CCBFA),
  brightMagenta: GhinaColors.pink.base,
  brightCyan: const Color(0xFF7DE8D8),
  brightWhite: Colors.white,
  searchHitBackground: GhinaColors.yellow.base,
  searchHitBackgroundCurrent: GhinaColors.orange.base,
  searchHitForeground: Colors.black,
);

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
  final _terminal = Terminal(maxLines: 5000);
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
  double _font = 13;
  int _cols = 80;
  int _rows = 24;
  bool _sized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _onOutput;
    _terminal.onResize = _onResize;
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
    _controller.dispose();
    super.dispose();
  }

  void _onResize(int w, int h, int pw, int ph) {
    _cols = w;
    _rows = h;
    if (!_sized) {
      _sized = true;
      _connect();
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
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    var out = data;
    if (_ctrl) {
      setState(() => _ctrl = false);
      if (data.length == 1 && RegExp('[a-zA-Z]').hasMatch(data)) {
        out = String.fromCharCode(data.toUpperCase().codeUnitAt(0) - 64);
      }
    }
    ws.add(out);
  }

  void _send(String seq) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) ws.add(seq);
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

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    if (d?.text != null) _terminal.paste(d!.text!);
  }

  void _zoom(double d) => setState(() => _font = (_font + d).clamp(9, 20));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final g = context.ghina;
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
                onPressed: () => _zoom(-1),
              ),
              Text(
                '${_font.round()}',
                style: GhinaType.caption.copyWith(color: g.textSecondary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Perbesar huruf',
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: () => _zoom(1),
              ),
              IconButton(
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
              theme: _theme,
              textStyle: TerminalStyle(fontSize: _font),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              keyboardType: TextInputType.visiblePassword,
              deleteDetection: true,
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
