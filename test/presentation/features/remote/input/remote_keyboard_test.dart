import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';

const _s = ImeTextTracker.sentinel;

TextEditingValue _v(String text, {TextRange composing = TextRange.empty}) =>
    TextEditingValue(
      text: _s + text,
      selection: TextSelection.collapsed(offset: _s.length + text.length),
      composing: composing.isValid
          ? TextRange(
              start: composing.start + _s.length,
              end: composing.end + _s.length,
            )
          : TextRange.empty,
    );

void main() {
  group('W3C code mapping', () {
    test('tombol fisik umum', () {
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.keyA], 'KeyA');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.digit7], 'Digit7');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.metaLeft], 'MetaLeft');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.metaRight], 'MetaRight');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.altLeft], 'AltLeft');
      expect(
        kPhysicalKeyToW3c[PhysicalKeyboardKey.controlRight],
        'ControlRight',
      );
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.enter], 'Enter');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.backquote], 'Backquote');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.arrowUp], 'ArrowUp');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.f12], 'F12');
      expect(kPhysicalKeyToW3c[PhysicalKeyboardKey.numpadEnter], 'NumpadEnter');
      expect(
        kPhysicalKeyToW3c[PhysicalKeyboardKey.intlBackslash],
        'IntlBackslash',
      );
    });

    test('semua nilai unik dan berbentuk W3C', () {
      final values = kPhysicalKeyToW3c.values.toList();
      expect(values.toSet().length, values.length);
      for (final v in values) {
        expect(v, matches(RegExp(r'^[A-Z][A-Za-z0-9]*$')));
      }
    });

    test('karakter → tombol (US)', () {
      expect(charToKey('c'), const CharKey('KeyC'));
      expect(charToKey('C'), const CharKey('KeyC', shift: true));
      expect(charToKey('5'), const CharKey('Digit5'));
      expect(charToKey('?'), const CharKey('Slash', shift: true));
      expect(charToKey(' '), const CharKey('Space'));
      expect(charToKey('é'), isNull);
    });
  });

  group('ImeTextTracker', () {
    test('ketik biasa tanpa composing langsung terkirim', () {
      final t = ImeTextTracker();
      expect(t.update(_v('h')).insert, 'h');
      expect(t.update(_v('hi')).insert, 'hi'.substring(1));
    });

    test('composing ditahan sampai komit, tanpa duplikat', () {
      final t = ImeTextTracker();
      var e = t.update(_v('hel', composing: const TextRange(start: 0, end: 3)));
      expect(e.isEmpty, isTrue);
      e = t.update(_v('hello', composing: const TextRange(start: 0, end: 5)));
      expect(e.isEmpty, isTrue);
      e = t.update(_v('hello '));
      expect(e.backspaces, 0);
      expect(e.insert, 'hello ');
      // Event berulang dengan nilai sama tidak mengirim apa-apa lagi.
      expect(t.update(_v('hello ')).isEmpty, isTrue);
    });

    test('Gboard membuka ulang kata sebagai composing saat backspace', () {
      final t = ImeTextTracker();
      t.update(_v('hello '));
      // Backspace: spasi hilang, "hello" jadi composing lagi.
      var e = t.update(
        _v('hello', composing: const TextRange(start: 0, end: 5)),
      );
      expect(e.backspaces, 1);
      expect(e.insert, '');
      // Backspace lagi di dalam composing.
      e = t.update(_v('hell', composing: const TextRange(start: 0, end: 4)));
      expect(e.backspaces, 1);
      // Ketik "o" → composing "hello": belum dikirim.
      e = t.update(_v('hello', composing: const TextRange(start: 0, end: 5)));
      expect(e.isEmpty, isTrue);
      // Saran Gboard mengganti composing jadi "help": tetap ditahan.
      e = t.update(_v('help', composing: const TextRange(start: 0, end: 4)));
      expect(e.isEmpty, isTrue);
      // Komit: cukup 1 backspace + "p ", tanpa menghapus seluruh kata.
      e = t.update(_v('help '));
      expect(e.backspaces, 1);
      expect(e.insert, 'p ');
    });

    test('autokoreksi mengganti kata = backspace + teks baru', () {
      final t = ImeTextTracker();
      t.update(_v('teh '));
      final e = t.update(_v('the '));
      expect(e.backspaces, 3);
      expect(e.insert, 'he ');
    });

    test('dikte suara: hasil sementara tidak dikirim, hanya hasil akhir', () {
      final t = ImeTextTracker();
      for (final partial in ['halo', 'halo apa', 'halo apa kabar']) {
        final e = t.update(
          _v(partial, composing: TextRange(start: 0, end: partial.length)),
        );
        expect(e.isEmpty, isTrue);
      }
      final e = t.update(_v('halo apa kabar'));
      expect(e.insert, 'halo apa kabar');
    });

    test('IME CJK: pinyin tidak bocor, hanya hanzi', () {
      final t = ImeTextTracker();
      t.update(_v('ni', composing: const TextRange(start: 0, end: 2)));
      t.update(_v('nihao', composing: const TextRange(start: 0, end: 5)));
      final e = t.update(_v('你好'));
      expect(e.backspaces, 0);
      expect(e.insert, '你好');
    });

    test('backspace di buffer kosong (sentinel) terdeteksi lalu direset', () {
      final t = ImeTextTracker();
      final e = t.update(
        const TextEditingValue(
          text: '​',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(e.backspaces, 1);
      expect(e.resetTo, ImeTextTracker.initialValue);
      expect(t.sent, _s);
    });

    test('emoji = 1 backspace (per grafem)', () {
      final t = ImeTextTracker();
      t.update(_v('a👍🏽'));
      final e = t.update(_v('a'));
      expect(e.backspaces, 1);
    });

    test('buffer panjang direset tanpa mengirim apa pun', () {
      final t = ImeTextTracker(maxBuffer: 10);
      final e = t.update(_v('abcdefghijkl'));
      expect(e.insert, 'abcdefghijkl');
      expect(e.resetTo, isNotNull);
      expect(t.update(ImeTextTracker.initialValue).isEmpty, isTrue);
    });
  });

  group('RemoteKeyboardController', () {
    late List<Map<String, dynamic>> sent;
    late RemoteKeyboardController kb;
    setUp(() {
      sent = [];
      kb = RemoteKeyboardController(send: sent.add);
    });

    test('teks → txt; enter/tab/backspace → key', () {
      kb.handleImeValue(_v('ab\n'));
      expect(sent, [
        {'t': 'txt', 's': 'ab'},
        {'t': 'key', 'code': 'Enter', 'mods': <String>[]},
      ]);
      sent.clear();
      kb.handleImeValue(ImeTextTracker.initialValue);
      kb.handleImeValue(_v('x\ty'));
      expect(sent, [
        {'t': 'txt', 's': 'x'},
        {'t': 'key', 'code': 'Tab', 'mods': <String>[]},
        {'t': 'txt', 's': 'y'},
      ]);
      sent.clear();
      kb.handleImeValue(_v('x\t'));
      expect(sent, [
        {'t': 'key', 'code': 'Backspace', 'mods': <String>[]},
      ]);
    });

    test(
      'sticky sekali pakai: ⌘ lalu "c" dari keyboard HP = key KeyC [meta]',
      () {
        kb.tapModifier(RemoteModifier.meta);
        expect(kb.stateOf(RemoteModifier.meta), StickyState.once);
        kb.handleImeValue(_v('c'));
        expect(sent, [
          {
            't': 'key',
            'code': 'KeyC',
            'mods': ['meta'],
          },
        ]);
        expect(kb.stateOf(RemoteModifier.meta), StickyState.off);
        sent.clear();
        kb.handleImeValue(_v('cd'));
        expect(sent, [
          {'t': 'txt', 's': 'd'},
        ]);
      },
    );

    test('sticky terkunci bertahan; ketuk lagi melepas', () {
      kb.lockModifier(RemoteModifier.ctrl);
      kb.tapModifier(RemoteModifier.shift);
      kb.sendKey('ArrowLeft');
      kb.sendKey('ArrowLeft');
      expect(sent, [
        {
          't': 'key',
          'code': 'ArrowLeft',
          'mods': ['ctrl', 'shift'],
        },
        {
          't': 'key',
          'code': 'ArrowLeft',
          'mods': ['ctrl'],
        },
      ]);
      kb.tapModifier(RemoteModifier.ctrl);
      expect(kb.hasActiveModifiers, isFalse);
    });

    test('pintasan tetap tidak memakan sticky', () {
      kb.tapModifier(RemoteModifier.alt);
      kb.sendShortcut('KeyV', const [RemoteModifier.meta]);
      expect(sent.single, {
        't': 'key',
        'code': 'KeyV',
        'mods': ['meta'],
      });
      expect(kb.stateOf(RemoteModifier.alt), StickyState.once);
    });
  });
}
