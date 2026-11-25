import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';

class _Harness {
  final sent = <Map<String, dynamic>>[];
  final host = StreamController<Map<String, dynamic>>.broadcast();
  final keyboard = RemoteKeyboardController();
  final transform = TransformationController();

  List<String> get types => [for (final m in sent) m['t'] as String];

  Widget build({InputMode mode = InputMode.trackpad}) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: RemoteInputLayer(
                key: const ValueKey('layer'),
                send: sent.add,
                hostMessages: host.stream,
                // Rasio 2:1 di area 800×(600-88): video contain di tengah.
                remoteSize: const Size(1600, 800),
                mode: mode,
                transformationController: transform,
                keyboardController: keyboard,
                settings: const RemoteInputSettings(
                  doubleTapWindow: Duration.zero,
                ),
                onHaptic: (_) {},
                child: const ColoredBox(color: Colors.black),
              ),
            ),
            RemoteKeyboardBar(controller: keyboard, onHaptic: () {}),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('keyboard fisik → kd/ku W3C, Meta benar, tidak bocor ke IME', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    expect(h.sent, [
      {'t': 'kd', 'code': 'MetaLeft'},
      {'t': 'kd', 'code': 'KeyC'},
      {'t': 'ku', 'code': 'KeyC'},
      {'t': 'ku', 'code': 'MetaLeft'},
      {'t': 'kd', 'code': 'Tab'},
      {'t': 'ku', 'code': 'Tab'},
    ]);
  });

  testWidgets('keyboard HP: komposisi + komit dikirim tepat sekali', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.keyboard.showSoftKeyboard();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    const s = ImeTextTracker.sentinel;
    void ime(String text, {bool composing = false}) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: s + text,
          selection: TextSelection.collapsed(offset: s.length + text.length),
          composing: composing
              ? TextRange(start: s.length, end: s.length + text.length)
              : TextRange.empty,
        ),
      );
    }

    ime('he', composing: true);
    await tester.pump();
    ime('hello', composing: true);
    await tester.pump();
    expect(h.sent, isEmpty);
    ime('hello ');
    await tester.pump();
    ime('hello '); // IME mengirim ulang nilai sama
    await tester.pump();
    expect(h.sent, [
      {'t': 'txt', 's': 'hello '},
    ]);

    // Enter dari keyboard HP → key Enter, buffer direset.
    ime('hello \n');
    await tester.pump();
    expect(h.sent.last, {'t': 'key', 'code': 'Enter', 'mods': <String>[]});
    expect(tester.testTextInput.editingState?['text'], s);
  });

  testWidgets('mode sentuh: koordinat memperhitungkan letterbox & zoom', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.build(mode: InputMode.touch));
    final box = tester.getRect(find.byKey(const ValueKey('layer')));
    // Video 2:1 contain → lebar penuh, tinggi = width/2, di tengah vertikal.
    final video = Rect.fromCenter(
      center: box.center,
      width: box.width,
      height: box.width / 2,
    );

    await tester.tapAt(
      video.topLeft + Offset(video.width * 0.25, video.height * 0.5),
    );
    await tester.pump();
    expect(h.sent.first['t'], 'mm');
    expect(h.sent.first['x'], closeTo(0.25, 0.002));
    expect(h.sent.first['y'], closeTo(0.5, 0.002));
    expect(h.sent[1], {'t': 'click', 'b': 0, 'n': 1});

    // Zoom 2× di pojok kiri atas: titik layar (x,y) = konten (x/2, y/2).
    h.transform.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    h.sent.clear();
    final target =
        video.topLeft + Offset(video.width * 0.1, video.height * 0.2);
    final screen = box.topLeft + (target - box.topLeft) * 2;
    await tester.tapAt(screen);
    await tester.pump();
    expect(h.sent.first['x'], closeTo(0.1, 0.002));
    expect(h.sent.first['y'], closeTo(0.2, 0.002));
  });

  testWidgets('pinch mengubah TransformationController, tidak ke Mac', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    final c = tester.getCenter(find.byKey(const ValueKey('layer')));
    final g1 = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final g2 = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await g1.moveTo(c - Offset(40.0 + i * 8, 0));
      await g2.moveTo(c + Offset(40.0 + i * 8, 0));
    }
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.sent, isEmpty);
    expect(h.transform.value.getMaxScaleOnAxis(), closeTo(3.0, 0.05));
  });

  testWidgets('kursor lokal mengikuti pesan host cursor', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.host.add({
      't': 'cursor',
      'x': 0.75,
      'y': 0.25,
      'visible': true,
      'shape': 'ibeam',
    });
    await tester.pump();
    final state = tester.state<RemoteInputLayerState>(
      find.byKey(const ValueKey('layer')),
    );
    expect(state.cursor.value.position, const Offset(0.75, 0.25));
    expect(state.cursor.value.shape, 'ibeam');
  });

  testWidgets('baris tombol: Esc, sticky ⌘ + panah, pintasan, F-key', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());

    await tester.tap(find.text('Esc'));
    await tester.tap(find.byKey(const ValueKey('mod-meta')));
    await tester.pump();
    expect(h.keyboard.stateOf(RemoteModifier.meta), StickyState.once);
    await tester.tap(find.text('→'));
    await tester.pump();
    expect(h.keyboard.stateOf(RemoteModifier.meta), StickyState.off);
    // ⌘V pushes the phone clipboard first (session hook; none here)
    h.keyboard.beforePaste = () async {};
    await tester.tap(find.text('⌘V'));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('F5'),
      find.text('⌘V'),
      const Offset(-200, 0),
    );
    await tester.tap(find.text('F5'));
    await tester.pump();

    expect(h.sent, [
      {'t': 'key', 'code': 'Escape', 'mods': <String>[]},
      {
        't': 'key',
        'code': 'ArrowRight',
        'mods': ['meta'],
      },
      {
        't': 'key',
        'code': 'KeyV',
        'mods': ['meta'],
      },
      {'t': 'key', 'code': 'F5', 'mods': <String>[]},
    ]);
  });

  testWidgets('tahan modifier = terkunci', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.longPress(find.byKey(const ValueKey('mod-shift')));
    await tester.pump();
    expect(h.keyboard.stateOf(RemoteModifier.shift), StickyState.locked);
    await tester.tap(find.text('Tab'));
    await tester.tap(find.text('Tab'));
    expect(h.sent.every((m) => (m['mods'] as List).contains('shift')), isTrue);
    expect(h.sent.length, 2);
  });
}
