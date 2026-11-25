import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ime_text_tracker.dart';
import 'key_codes.dart';
import 'remote_actions.dart';

/// Status modifier sticky di [RemoteKeyboardBar].
enum StickyState {
  off,

  /// Ketuk sekali: berlaku untuk tombol/klik berikutnya lalu lepas.
  once,

  /// Tahan: terkunci sampai diketuk lagi.
  locked,
}

/// Status keyboard bersama antara [RemoteInputLayer] (TextField tersembunyi,
/// keyboard fisik, klik bermodifier) dan [RemoteKeyboardBar].
///
/// Buat satu per sesi remote dan berikan ke keduanya. Bila
/// [RemoteInputLayer.keyboardController] tidak diberikan, layer membuat
/// sendiri dan menyediakannya lewat [RemoteKeyboardScope].
class RemoteKeyboardController extends ChangeNotifier {
  RemoteKeyboardController({this._send});

  RemoteSend? _send;

  /// Dipasang oleh [RemoteInputLayer]; boleh juga diisi manual.
  set send(RemoteSend? value) => _send = value;

  final Map<RemoteModifier, StickyState> _sticky = {
    for (final m in RemoteModifier.values) m: StickyState.off,
  };

  final ImeTextTracker ime = ImeTextTracker();

  bool _softKeyboardRequested = false;
  bool _softKeyboardVisible = false;

  void _emit(Map<String, dynamic> m) => _send?.call(m);

  // ------------------------------------------------------------ sticky mods

  StickyState stateOf(RemoteModifier m) => _sticky[m]!;

  bool get hasActiveModifiers =>
      _sticky.values.any((s) => s != StickyState.off);

  /// Ketuk: off → once, once/locked → off.
  void tapModifier(RemoteModifier m) {
    _sticky[m] = _sticky[m] == StickyState.off
        ? StickyState.once
        : StickyState.off;
    notifyListeners();
  }

  /// Tahan: kunci.
  void lockModifier(RemoteModifier m) {
    _sticky[m] = StickyState.locked;
    notifyListeners();
  }

  void clearModifiers() {
    var changed = false;
    for (final m in RemoteModifier.values) {
      if (_sticky[m] != StickyState.off) {
        _sticky[m] = StickyState.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Modifier aktif (urutan tetap) dan lepas yang sekali pakai.
  List<RemoteModifier> takeModifiers() {
    final active = [
      for (final m in RemoteModifier.values)
        if (_sticky[m] != StickyState.off) m,
    ];
    var changed = false;
    for (final m in active) {
      if (_sticky[m] == StickyState.once) {
        _sticky[m] = StickyState.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    return active;
  }

  // ----------------------------------------------------------------- keys

  /// Tekan+lepas [code] dengan [mods] tambahan + modifier sticky.
  void sendKey(String code, {List<RemoteModifier> mods = const []}) {
    final all = {...mods, ...takeModifiers()};
    _emit({
      't': 'key',
      'code': code,
      'mods': [
        for (final m in RemoteModifier.values)
          if (all.contains(m)) m.wire,
      ],
    });
  }

  /// Pintasan tetap (⌘C dll): modifier sticky TIDAK ikut dikonsumsi.
  void sendShortcut(String code, List<RemoteModifier> mods) {
    _emit({
      't': 'key',
      'code': code,
      'mods': [
        for (final m in RemoteModifier.values)
          if (mods.contains(m)) m.wire,
      ],
    });
  }

  /// Ketik teks. Bila ada modifier sticky dan teks 1 karakter yang punya
  /// tombol fisik, dikirim sebagai pintasan (⌘ + c → key KeyC [meta]).
  void sendText(String s) {
    if (s.isEmpty) return;
    if (hasActiveModifiers) {
      final k = charToKey(s);
      if (k != null) {
        sendKey(k.code, mods: [if (k.shift) RemoteModifier.shift]);
        return;
      }
    }
    // Pecah supaya Enter/Tab jadi `key`, sisanya `txt` utuh.
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      final chunk = buf.toString();
      buf.clear();
      // Batas protokol 1 MB per pesan; potong aman per 64 K unit.
      for (var i = 0; i < chunk.length; i += 65536) {
        final end = i + 65536 < chunk.length ? i + 65536 : chunk.length;
        _emit({'t': 'txt', 's': chunk.substring(i, end)});
      }
    }

    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '\n' || ch == '\r') {
        flush();
        sendKey('Enter');
      } else if (ch == '\t') {
        flush();
        sendKey('Tab');
      } else if (ch == '​') {
        // sentinel buffer, abaikan
      } else {
        buf.write(ch);
      }
    }
    flush();
  }

  // ------------------------------------------------------------------ IME

  /// Dipanggil layer setiap nilai TextField tersembunyi berubah.
  /// Mengembalikan nilai reset untuk buffer, atau null.
  TextEditingValue? handleImeValue(TextEditingValue value) {
    final edit = ime.update(value);
    for (var i = 0; i < edit.backspaces; i++) {
      sendKey('Backspace');
    }
    if (edit.insert.isNotEmpty) sendText(edit.insert);
    return edit.resetTo;
  }

  // ------------------------------------------------------- soft keyboard

  /// Keyboard HP sedang diminta tampil.
  bool get softKeyboardRequested => _softKeyboardRequested;

  /// Keyboard HP benar-benar terlihat (inset bawah > 0).
  bool get softKeyboardVisible => _softKeyboardVisible;

  void showSoftKeyboard() {
    _softKeyboardRequested = true;
    _showToken++;
    notifyListeners();
  }

  void hideSoftKeyboard() {
    if (!_softKeyboardRequested) return;
    _softKeyboardRequested = false;
    notifyListeners();
  }

  void toggleSoftKeyboard() {
    if (_softKeyboardRequested && _softKeyboardVisible) {
      hideSoftKeyboard();
    } else {
      showSoftKeyboard();
    }
  }

  /// Naik setiap [showSoftKeyboard] dipanggil (meski sudah requested), agar
  /// layer bisa memunculkan ulang keyboard yang ditutup lewat tombol back.
  int get showToken => _showToken;
  int _showToken = 0;

  /// Diisi layer dari inset tampilan.
  void setSoftKeyboardVisible(bool visible) {
    if (visible == _softKeyboardVisible) return;
    _softKeyboardVisible = visible;
    if (!visible && _softKeyboardRequested) {
      // Ditutup pengguna (back / tombol sembunyikan Gboard).
      _softKeyboardRequested = false;
    }
    notifyListeners();
  }
}
