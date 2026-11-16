import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Salin-tempel terminal Kantor.
///
/// Terminalnya `tmux attach`, jadi isi layar ada di buffer xterm lokal dan
/// seleksi (tekan lama / seret mouse) dipegang [TerminalController]. Bawaan
/// xterm 4.0.0 hanya menyalin lewat Ctrl+Shift+C, tanpa tombol apa pun di
/// layar sentuh, dan memakai Ctrl+A untuk "pilih semua" (merebut Ctrl+A dari
/// shell). Helper di sini dipakai tombol bar terminal dan [termClipKey].

/// Teks yang sedang dipilih, sudah dirapikan; null kalau tidak ada seleksi
/// atau seleksinya kosong.
String? termSelectionText(Terminal t, TerminalController c) {
  final range = c.selection;
  if (range == null) return null;
  final text = tidyCopied(t.buffer.getText(range));
  return text.isEmpty ? null : text;
}

/// Seluruh layar yang terlihat (baris paling bawah buffer setinggi layar).
String termScreenText(Terminal t) {
  final b = t.buffer;
  final top = (b.height - t.viewHeight).clamp(0, b.height);
  if (b.height == 0) return '';
  return tidyCopied(
    b.getText(
      BufferRangeLine(
        CellOffset(0, top),
        CellOffset(t.viewWidth, b.height - 1),
      ),
    ),
  );
}

/// Buang spasi di ujung tiap baris (sel kosong tmux) dan baris kosong di
/// akhir.
String tidyCopied(String raw) {
  final lines = raw.split('\n').map((l) => l.trimRight()).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

/// Teks clipboard yang siap dikirim: baris baru jadi `\r` (seperti Enter di
/// terminal sungguhan) dan penanda bracketed paste dibuang supaya isi
/// clipboard tidak bisa keluar dari mode tempel aman.
String pasteReady(String text) => text
    .replaceAll('\x1b[200~', '')
    .replaceAll('\x1b[201~', '')
    .replaceAll('\r\n', '\r')
    .replaceAll('\n', '\r');

/// Jumlah baris [ready] (hasil [pasteReady]) yang akan ter-Enter kalau
/// program di terminal tidak memakai bracketed paste. 0 berarti aman.
int pasteEnters(Terminal t, String ready) {
  if (t.bracketedPasteMode) return 0;
  return '\r'.allMatches(ready).length;
}

/// Aksi keyboard fisik untuk salin-tempel.
enum TermClipKey {
  /// Salin seleksi ke clipboard.
  copy,

  /// Tempel isi clipboard.
  paste,

  /// Ctrl+Shift+C tanpa seleksi: ditelan, jangan sampai jadi ^C.
  swallow,
}

/// Tombol salin-tempel pada [event], atau null kalau bukan urusan clipboard
/// (dikirim ke terminal seperti biasa).
///
/// - Ctrl+Shift+C / ⌘C: salin seleksi.
/// - Ctrl+C: salin kalau ada seleksi; tanpa seleksi tetap ^C ke program.
/// - Ctrl+V / Ctrl+Shift+V / ⌘V: tempel.
TermClipKey? termClipKey(KeyEvent event, {required bool hasSelection}) {
  if (event is KeyUpEvent) return null;
  final kb = HardwareKeyboard.instance;
  final ctrl = kb.isControlPressed;
  final meta = kb.isMetaPressed;
  final shift = kb.isShiftPressed;
  if (kb.isAltPressed || (!ctrl && !meta) || (ctrl && meta)) return null;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.keyV) return TermClipKey.paste;
  if (key != LogicalKeyboardKey.keyC) return null;
  if (meta || shift) {
    return hasSelection ? TermClipKey.copy : TermClipKey.swallow;
  }
  return hasSelection ? TermClipKey.copy : null;
}
