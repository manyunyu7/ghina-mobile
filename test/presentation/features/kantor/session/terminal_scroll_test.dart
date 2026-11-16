import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/session/terminal_scroll.dart';
import 'package:xterm/xterm.dart';

/// A terminal the way `tmux attach` with `mouse on` leaves it: alternate
/// screen, button-event tracking, SGR reports.
(Terminal, TermWheelHandler, List<String>) tmuxLike() {
  final wheel = TermWheelHandler();
  final out = <String>[];
  final t = Terminal(maxLines: 1000, mouseHandler: wheel)
    ..onOutput = out.add
    ..write('\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006h');
  return (t, wheel, out);
}

void main() {
  group('TermWheelHandler', () {
    test('reports the plain wheel ids tmux binds (64/65), not 68/69', () {
      final (t, wheel, out) = tmuxLike();
      final at = const CellOffset(2, 3);
      t.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        at,
      );
      t.mouseInput(
        TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        at,
      );
      expect(out, ['\x1b[<64;3;4M', '\x1b[<65;3;4M']);
      expect(wheel.back, 0);
    });

    test('normal report mode encodes the button and 1-based cell', () {
      final (t, _, out) = tmuxLike();
      t.write('\x1b[?1006l');
      t.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
      );
      expect(out.single, '\x1b[M${String.fromCharCode(96)}!!');
    });

    test('without mouse tracking the wheel is left to xterm', () {
      final wheel = TermWheelHandler();
      final out = <String>[];
      final t = Terminal(mouseHandler: wheel)..onOutput = out.add;
      t.write('\x1b[?1049h');
      final handled = t.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
      );
      expect(handled, isFalse);
      expect(wheel.back, 0);
    });

    test('release undoes the wheel-ups once and claims own output', () {
      final (t, wheel, out) = tmuxLike();
      for (var i = 0; i < 3; i++) {
        t.mouseInput(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
        );
      }
      expect(wheel.isOwn(out.last), isTrue);
      expect(wheel.isOwn(out.last), isFalse);
      expect(wheel.isOwn('a'), isFalse);
      expect(wheel.back, 3);
      expect(wheel.release(), '\x1b[<65;1;1M' * 3);
      expect(wheel.release(), '');
    });

    test('clicks still go through the default handler', () {
      final (t, _, out) = tmuxLike();
      t.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(0, 0),
      );
      expect(out.single, '\x1b[<0;1;1M');
    });
  });

  testWidgets('a vertical swipe on the terminal sends wheel reports', (
    t,
  ) async {
    final (term, wheel, out) = tmuxLike();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 500,
            child: TerminalView(term, hardwareKeyboardOnly: true),
          ),
        ),
      ),
    );
    await t.pump();
    out.clear();

    // finger down = back in history
    await t.drag(find.byType(TerminalView), const Offset(0, 200));
    await t.pumpAndSettle();
    final ups = out.where((s) => s.startsWith('\x1b[<64;')).length;
    expect(ups, greaterThan(0));
    expect(out.any((s) => s.startsWith('\x1b[<68;')), isFalse);
    expect(wheel.back, ups);

    // finger up = towards the live end
    out.clear();
    await t.drag(find.byType(TerminalView), const Offset(0, -100));
    await t.pumpAndSettle();
    expect(out.where((s) => s.startsWith('\x1b[<65;')), isNotEmpty);
    expect(wheel.back, lessThan(ups));
  });
}
