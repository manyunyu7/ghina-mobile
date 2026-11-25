import 'package:flutter/services.dart';

import 'remote_protocol.dart';

/// W3C `KeyboardEvent.code` for a physical key from a Bluetooth/USB keyboard,
/// or null for keys the host does not know.
String? w3cCode(PhysicalKeyboardKey key) => _physical[key];

final Map<PhysicalKeyboardKey, String> _physical = {
  for (var i = 0; i < 26; i++)
    _letters[i]: 'Key${String.fromCharCode(0x41 + i)}',
  for (var i = 0; i < 10; i++) _digits[i]: 'Digit$i',
  for (var i = 0; i < 12; i++) _fkeys[i]: 'F${i + 1}',
  PhysicalKeyboardKey.enter: 'Enter',
  PhysicalKeyboardKey.numpadEnter: 'NumpadEnter',
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
  PhysicalKeyboardKey.intlBackslash: 'IntlBackslash',
  PhysicalKeyboardKey.capsLock: 'CapsLock',
  PhysicalKeyboardKey.printScreen: 'PrintScreen',
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
  PhysicalKeyboardKey.controlLeft: 'ControlLeft',
  PhysicalKeyboardKey.shiftLeft: 'ShiftLeft',
  PhysicalKeyboardKey.altLeft: 'AltLeft',
  PhysicalKeyboardKey.metaLeft: 'MetaLeft',
  PhysicalKeyboardKey.controlRight: 'ControlRight',
  PhysicalKeyboardKey.shiftRight: 'ShiftRight',
  PhysicalKeyboardKey.altRight: 'AltRight',
  PhysicalKeyboardKey.metaRight: 'MetaRight',
  PhysicalKeyboardKey.contextMenu: 'ContextMenu',
  PhysicalKeyboardKey.numpadDivide: 'NumpadDivide',
  PhysicalKeyboardKey.numpadMultiply: 'NumpadMultiply',
  PhysicalKeyboardKey.numpadSubtract: 'NumpadSubtract',
  PhysicalKeyboardKey.numpadAdd: 'NumpadAdd',
  PhysicalKeyboardKey.numpadDecimal: 'NumpadDecimal',
  PhysicalKeyboardKey.numpadEqual: 'NumpadEqual',
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
  PhysicalKeyboardKey.audioVolumeMute: 'AudioVolumeMute',
  PhysicalKeyboardKey.audioVolumeUp: 'AudioVolumeUp',
  PhysicalKeyboardKey.audioVolumeDown: 'AudioVolumeDown',
};

const _letters = [
  PhysicalKeyboardKey.keyA,
  PhysicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyC,
  PhysicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyI,
  PhysicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyM,
  PhysicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyR,
  PhysicalKeyboardKey.keyS,
  PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyX,
  PhysicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ,
];

const _digits = [
  PhysicalKeyboardKey.digit0,
  PhysicalKeyboardKey.digit1,
  PhysicalKeyboardKey.digit2,
  PhysicalKeyboardKey.digit3,
  PhysicalKeyboardKey.digit4,
  PhysicalKeyboardKey.digit5,
  PhysicalKeyboardKey.digit6,
  PhysicalKeyboardKey.digit7,
  PhysicalKeyboardKey.digit8,
  PhysicalKeyboardKey.digit9,
];

const _fkeys = [
  PhysicalKeyboardKey.f1,
  PhysicalKeyboardKey.f2,
  PhysicalKeyboardKey.f3,
  PhysicalKeyboardKey.f4,
  PhysicalKeyboardKey.f5,
  PhysicalKeyboardKey.f6,
  PhysicalKeyboardKey.f7,
  PhysicalKeyboardKey.f8,
  PhysicalKeyboardKey.f9,
  PhysicalKeyboardKey.f10,
  PhysicalKeyboardKey.f11,
  PhysicalKeyboardKey.f12,
];

/// W3C code (US layout) that types [char], plus whether Shift is needed.
/// Used when a sticky modifier is armed and the phone keyboard sends a
/// character: Cmd + "c" must reach the Mac as `key KeyC [meta]`, not text.
(String, bool)? codeForChar(String char) {
  if (char.length != 1) return null;
  final c = char.codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7A) {
    return ('Key${String.fromCharCode(c - 0x20)}', false);
  }
  if (c >= 0x41 && c <= 0x5A) return ('Key$char', true);
  if (c >= 0x30 && c <= 0x39) return ('Digit$char', false);
  return _punct[char];
}

const _punct = <String, (String, bool)>{
  ' ': ('Space', false),
  '\n': ('Enter', false),
  '\t': ('Tab', false),
  '-': ('Minus', false),
  '_': ('Minus', true),
  '=': ('Equal', false),
  '+': ('Equal', true),
  '[': ('BracketLeft', false),
  '{': ('BracketLeft', true),
  ']': ('BracketRight', false),
  '}': ('BracketRight', true),
  '\\': ('Backslash', false),
  '|': ('Backslash', true),
  ';': ('Semicolon', false),
  ':': ('Semicolon', true),
  "'": ('Quote', false),
  '"': ('Quote', true),
  '`': ('Backquote', false),
  '~': ('Backquote', true),
  ',': ('Comma', false),
  '<': ('Comma', true),
  '.': ('Period', false),
  '>': ('Period', true),
  '/': ('Slash', false),
  '?': ('Slash', true),
  '!': ('Digit1', true),
  '@': ('Digit2', true),
  '#': ('Digit3', true),
  r'$': ('Digit4', true),
  '%': ('Digit5', true),
  '^': ('Digit6', true),
  '&': ('Digit7', true),
  '*': ('Digit8', true),
  '(': ('Digit9', true),
  ')': ('Digit0', true),
};

/// Sticky modifier on the extra-key row: tap once = next key only, tap
/// again = locked until tapped a third time.
enum StickyState { off, once, locked }

class StickyModifiers {
  final Map<RemoteMod, StickyState> _state = {
    for (final m in RemoteMod.values) m: StickyState.off,
  };

  StickyState of(RemoteMod m) => _state[m]!;

  bool get any => _state.values.any((s) => s != StickyState.off);

  Set<RemoteMod> get active => {
    for (final e in _state.entries)
      if (e.value != StickyState.off) e.key,
  };

  void tap(RemoteMod m) {
    _state[m] = switch (_state[m]!) {
      StickyState.off => StickyState.once,
      StickyState.once => StickyState.locked,
      StickyState.locked => StickyState.off,
    };
  }

  /// After a key was sent: one-shot modifiers turn off, locked ones stay.
  void consume() {
    for (final m in RemoteMod.values) {
      if (_state[m] == StickyState.once) _state[m] = StickyState.off;
    }
  }

  void clear() {
    for (final m in RemoteMod.values) {
      _state[m] = StickyState.off;
    }
  }
}

/// Turns what the soft keyboard typed into ctl messages. [mods] are the
/// sticky modifiers currently armed (empty = plain typing).
///
/// - plain text goes out as one `txt` (so IME, emoji, dictation all work);
///   newlines become Enter and tabs become Tab;
/// - with modifiers armed, each mappable character becomes a `key` shortcut.
List<Map<String, Object?>> textToCtl(String text, Set<RemoteMod> mods) {
  final out = <Map<String, Object?>>[];
  if (text.isEmpty) return out;
  if (mods.isNotEmpty) {
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = codeForChar(ch);
      if (mapped == null) {
        out.add(Ctl.text(ch));
        continue;
      }
      final (code, shift) = mapped;
      out.add(Ctl.key(code, {...mods, if (shift) RemoteMod.shift}));
    }
    return out;
  }
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    out.add(Ctl.text(buf.toString()));
    buf.clear();
  }

  for (final rune in text.runes) {
    if (rune == 0x0A) {
      flush();
      out.add(Ctl.key('Enter'));
    } else if (rune == 0x09) {
      flush();
      out.add(Ctl.key('Tab'));
    } else if (rune != 0x0D) {
      buf.writeCharCode(rune);
    }
  }
  flush();
  return out;
}

/// Diff between two snapshots of the hidden text field: how many characters
/// were removed from the end of [before] and what was appended. Works on
/// runes so emoji are not split.
({int deleted, String inserted}) textDiff(String before, String after) {
  final a = before.runes.toList();
  final b = after.runes.toList();
  var p = 0;
  while (p < a.length && p < b.length && a[p] == b[p]) {
    p++;
  }
  return (deleted: a.length - p, inserted: String.fromCharCodes(b.sublist(p)));
}
