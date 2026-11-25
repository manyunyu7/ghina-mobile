import 'package:flutter/services.dart';

/// Pemetaan tombol fisik Flutter → string W3C `KeyboardEvent.code`
/// (kontrak `kd`/`ku`/`key` di PROTOCOL.md §2).
///
/// Dipetakan dari [PhysicalKeyboardKey] (posisi tombol, bukan karakter),
/// jadi tata letak keyboard Android tidak memengaruhi hasil: Mac yang
/// menerapkan tata letaknya sendiri, sama seperti keyboard USB biasa.
final Map<PhysicalKeyboardKey, String> kPhysicalKeyToW3c = {
  PhysicalKeyboardKey.keyA: 'KeyA',
  PhysicalKeyboardKey.keyB: 'KeyB',
  PhysicalKeyboardKey.keyC: 'KeyC',
  PhysicalKeyboardKey.keyD: 'KeyD',
  PhysicalKeyboardKey.keyE: 'KeyE',
  PhysicalKeyboardKey.keyF: 'KeyF',
  PhysicalKeyboardKey.keyG: 'KeyG',
  PhysicalKeyboardKey.keyH: 'KeyH',
  PhysicalKeyboardKey.keyI: 'KeyI',
  PhysicalKeyboardKey.keyJ: 'KeyJ',
  PhysicalKeyboardKey.keyK: 'KeyK',
  PhysicalKeyboardKey.keyL: 'KeyL',
  PhysicalKeyboardKey.keyM: 'KeyM',
  PhysicalKeyboardKey.keyN: 'KeyN',
  PhysicalKeyboardKey.keyO: 'KeyO',
  PhysicalKeyboardKey.keyP: 'KeyP',
  PhysicalKeyboardKey.keyQ: 'KeyQ',
  PhysicalKeyboardKey.keyR: 'KeyR',
  PhysicalKeyboardKey.keyS: 'KeyS',
  PhysicalKeyboardKey.keyT: 'KeyT',
  PhysicalKeyboardKey.keyU: 'KeyU',
  PhysicalKeyboardKey.keyV: 'KeyV',
  PhysicalKeyboardKey.keyW: 'KeyW',
  PhysicalKeyboardKey.keyX: 'KeyX',
  PhysicalKeyboardKey.keyY: 'KeyY',
  PhysicalKeyboardKey.keyZ: 'KeyZ',
  PhysicalKeyboardKey.digit0: 'Digit0',
  PhysicalKeyboardKey.digit1: 'Digit1',
  PhysicalKeyboardKey.digit2: 'Digit2',
  PhysicalKeyboardKey.digit3: 'Digit3',
  PhysicalKeyboardKey.digit4: 'Digit4',
  PhysicalKeyboardKey.digit5: 'Digit5',
  PhysicalKeyboardKey.digit6: 'Digit6',
  PhysicalKeyboardKey.digit7: 'Digit7',
  PhysicalKeyboardKey.digit8: 'Digit8',
  PhysicalKeyboardKey.digit9: 'Digit9',
  PhysicalKeyboardKey.enter: 'Enter',
  PhysicalKeyboardKey.escape: 'Escape',
  PhysicalKeyboardKey.backspace: 'Backspace',
  PhysicalKeyboardKey.tab: 'Tab',
  PhysicalKeyboardKey.space: 'Space',
  PhysicalKeyboardKey.minus: 'Minus',
  PhysicalKeyboardKey.equal: 'Equal',
  PhysicalKeyboardKey.bracketLeft: 'BracketLeft',
  PhysicalKeyboardKey.bracketRight: 'BracketRight',
  PhysicalKeyboardKey.backslash: 'Backslash',
  PhysicalKeyboardKey.semicolon: 'Semicolon',
  PhysicalKeyboardKey.quote: 'Quote',
  PhysicalKeyboardKey.backquote: 'Backquote',
  PhysicalKeyboardKey.comma: 'Comma',
  PhysicalKeyboardKey.period: 'Period',
  PhysicalKeyboardKey.slash: 'Slash',
  PhysicalKeyboardKey.capsLock: 'CapsLock',
  PhysicalKeyboardKey.f1: 'F1',
  PhysicalKeyboardKey.f2: 'F2',
  PhysicalKeyboardKey.f3: 'F3',
  PhysicalKeyboardKey.f4: 'F4',
  PhysicalKeyboardKey.f5: 'F5',
  PhysicalKeyboardKey.f6: 'F6',
  PhysicalKeyboardKey.f7: 'F7',
  PhysicalKeyboardKey.f8: 'F8',
  PhysicalKeyboardKey.f9: 'F9',
  PhysicalKeyboardKey.f10: 'F10',
  PhysicalKeyboardKey.f11: 'F11',
  PhysicalKeyboardKey.f12: 'F12',
  PhysicalKeyboardKey.f13: 'F13',
  PhysicalKeyboardKey.f14: 'F14',
  PhysicalKeyboardKey.f15: 'F15',
  PhysicalKeyboardKey.f16: 'F16',
  PhysicalKeyboardKey.f17: 'F17',
  PhysicalKeyboardKey.f18: 'F18',
  PhysicalKeyboardKey.f19: 'F19',
  PhysicalKeyboardKey.f20: 'F20',
  PhysicalKeyboardKey.f21: 'F21',
  PhysicalKeyboardKey.f22: 'F22',
  PhysicalKeyboardKey.f23: 'F23',
  PhysicalKeyboardKey.f24: 'F24',
  PhysicalKeyboardKey.printScreen: 'PrintScreen',
  PhysicalKeyboardKey.scrollLock: 'ScrollLock',
  PhysicalKeyboardKey.pause: 'Pause',
  PhysicalKeyboardKey.insert: 'Insert',
  PhysicalKeyboardKey.home: 'Home',
  PhysicalKeyboardKey.pageUp: 'PageUp',
  PhysicalKeyboardKey.delete: 'Delete',
  PhysicalKeyboardKey.end: 'End',
  PhysicalKeyboardKey.pageDown: 'PageDown',
  PhysicalKeyboardKey.arrowRight: 'ArrowRight',
  PhysicalKeyboardKey.arrowLeft: 'ArrowLeft',
  PhysicalKeyboardKey.arrowDown: 'ArrowDown',
  PhysicalKeyboardKey.arrowUp: 'ArrowUp',
  PhysicalKeyboardKey.numLock: 'NumLock',
  PhysicalKeyboardKey.numpadDivide: 'NumpadDivide',
  PhysicalKeyboardKey.numpadMultiply: 'NumpadMultiply',
  PhysicalKeyboardKey.numpadSubtract: 'NumpadSubtract',
  PhysicalKeyboardKey.numpadAdd: 'NumpadAdd',
  PhysicalKeyboardKey.numpadEnter: 'NumpadEnter',
  PhysicalKeyboardKey.numpad0: 'Numpad0',
  PhysicalKeyboardKey.numpad1: 'Numpad1',
  PhysicalKeyboardKey.numpad2: 'Numpad2',
  PhysicalKeyboardKey.numpad3: 'Numpad3',
  PhysicalKeyboardKey.numpad4: 'Numpad4',
  PhysicalKeyboardKey.numpad5: 'Numpad5',
  PhysicalKeyboardKey.numpad6: 'Numpad6',
  PhysicalKeyboardKey.numpad7: 'Numpad7',
  PhysicalKeyboardKey.numpad8: 'Numpad8',
  PhysicalKeyboardKey.numpad9: 'Numpad9',
  PhysicalKeyboardKey.numpadDecimal: 'NumpadDecimal',
  PhysicalKeyboardKey.numpadEqual: 'NumpadEqual',
  PhysicalKeyboardKey.numpadComma: 'NumpadComma',
  PhysicalKeyboardKey.numpadParenLeft: 'NumpadParenLeft',
  PhysicalKeyboardKey.numpadParenRight: 'NumpadParenRight',
  PhysicalKeyboardKey.intlBackslash: 'IntlBackslash',
  PhysicalKeyboardKey.intlRo: 'IntlRo',
  PhysicalKeyboardKey.intlYen: 'IntlYen',
  PhysicalKeyboardKey.contextMenu: 'ContextMenu',
  PhysicalKeyboardKey.power: 'Power',
  PhysicalKeyboardKey.controlLeft: 'ControlLeft',
  PhysicalKeyboardKey.shiftLeft: 'ShiftLeft',
  PhysicalKeyboardKey.altLeft: 'AltLeft',
  PhysicalKeyboardKey.metaLeft: 'MetaLeft',
  PhysicalKeyboardKey.controlRight: 'ControlRight',
  PhysicalKeyboardKey.shiftRight: 'ShiftRight',
  PhysicalKeyboardKey.altRight: 'AltRight',
  PhysicalKeyboardKey.metaRight: 'MetaRight',
  PhysicalKeyboardKey.audioVolumeMute: 'AudioVolumeMute',
  PhysicalKeyboardKey.audioVolumeUp: 'AudioVolumeUp',
  PhysicalKeyboardKey.audioVolumeDown: 'AudioVolumeDown',
  PhysicalKeyboardKey.mediaPlayPause: 'MediaPlayPause',
  PhysicalKeyboardKey.mediaTrackNext: 'MediaTrackNext',
  PhysicalKeyboardKey.mediaTrackPrevious: 'MediaTrackPrevious',
  PhysicalKeyboardKey.mediaStop: 'MediaStop',
  PhysicalKeyboardKey.lang1: 'Lang1',
  PhysicalKeyboardKey.lang2: 'Lang2',
  PhysicalKeyboardKey.fn: 'Fn',
  PhysicalKeyboardKey.help: 'Help',
};

/// Fallback lewat [LogicalKeyboardKey] untuk event yang kode fisiknya tidak
/// dikenal (mis. event sintetis dari keyboard virtual).
final Map<LogicalKeyboardKey, String> _logicalFallback = {
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'NumpadEnter',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
  LogicalKeyboardKey.arrowRight: 'ArrowRight',
  LogicalKeyboardKey.arrowUp: 'ArrowUp',
  LogicalKeyboardKey.arrowDown: 'ArrowDown',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.metaLeft: 'MetaLeft',
  LogicalKeyboardKey.metaRight: 'MetaRight',
  LogicalKeyboardKey.controlLeft: 'ControlLeft',
  LogicalKeyboardKey.controlRight: 'ControlRight',
  LogicalKeyboardKey.altLeft: 'AltLeft',
  LogicalKeyboardKey.altRight: 'AltRight',
  LogicalKeyboardKey.shiftLeft: 'ShiftLeft',
  LogicalKeyboardKey.shiftRight: 'ShiftRight',
};

/// Kode W3C untuk sebuah [KeyEvent], atau null bila tidak bisa dipetakan.
String? w3cCodeForKeyEvent(KeyEvent event) =>
    kPhysicalKeyToW3c[event.physicalKey] ?? _logicalFallback[event.logicalKey];

/// Nama modifier di pesan `key` (PROTOCOL.md §2).
enum RemoteModifier {
  meta('meta', 'MetaLeft', '⌘'),
  ctrl('ctrl', 'ControlLeft', '⌃'),
  alt('alt', 'AltLeft', '⌥'),
  shift('shift', 'ShiftLeft', '⇧');

  const RemoteModifier(this.wire, this.code, this.symbol);

  /// Nilai di array `mods`.
  final String wire;

  /// Kode W3C tombol modifier kiri (untuk `kd`/`ku`).
  final String code;

  /// Simbol gaya Mac untuk tombol di [RemoteKeyboardBar].
  final String symbol;
}

/// Hasil [charToKey]: kode W3C + apakah perlu Shift (tata letak US).
class CharKey {
  const CharKey(this.code, {this.shift = false});
  final String code;
  final bool shift;

  @override
  bool operator ==(Object other) =>
      other is CharKey && other.code == code && other.shift == shift;

  @override
  int get hashCode => Object.hash(code, shift);

  @override
  String toString() => 'CharKey($code${shift ? ', shift' : ''})';
}

const Map<String, CharKey> _punct = {
  ' ': CharKey('Space'),
  '-': CharKey('Minus'),
  '_': CharKey('Minus', shift: true),
  '=': CharKey('Equal'),
  '+': CharKey('Equal', shift: true),
  '[': CharKey('BracketLeft'),
  '{': CharKey('BracketLeft', shift: true),
  ']': CharKey('BracketRight'),
  '}': CharKey('BracketRight', shift: true),
  '\\': CharKey('Backslash'),
  '|': CharKey('Backslash', shift: true),
  ';': CharKey('Semicolon'),
  ':': CharKey('Semicolon', shift: true),
  "'": CharKey('Quote'),
  '"': CharKey('Quote', shift: true),
  '`': CharKey('Backquote'),
  '~': CharKey('Backquote', shift: true),
  ',': CharKey('Comma'),
  '<': CharKey('Comma', shift: true),
  '.': CharKey('Period'),
  '>': CharKey('Period', shift: true),
  '/': CharKey('Slash'),
  '?': CharKey('Slash', shift: true),
  '!': CharKey('Digit1', shift: true),
  '@': CharKey('Digit2', shift: true),
  '#': CharKey('Digit3', shift: true),
  r'$': CharKey('Digit4', shift: true),
  '%': CharKey('Digit5', shift: true),
  '^': CharKey('Digit6', shift: true),
  '&': CharKey('Digit7', shift: true),
  '*': CharKey('Digit8', shift: true),
  '(': CharKey('Digit9', shift: true),
  ')': CharKey('Digit0', shift: true),
  '\n': CharKey('Enter'),
  '\t': CharKey('Tab'),
};

/// Karakter tunggal dari keyboard HP → tombol fisik (US), untuk pintasan
/// seperti ⌘ sticky + "c" dari Gboard. Null bila bukan ASCII yang dikenal.
CharKey? charToKey(String ch) {
  if (ch.length != 1) return null;
  final c = ch.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return CharKey('Key${ch.toUpperCase()}');
  if (c >= 0x41 && c <= 0x5a) return CharKey('Key$ch', shift: true);
  if (c >= 0x30 && c <= 0x39) return CharKey('Digit$ch');
  return _punct[ch];
}
