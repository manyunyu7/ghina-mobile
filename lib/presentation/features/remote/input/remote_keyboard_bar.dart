import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'key_codes.dart';
import 'remote_input_layer.dart';
import 'remote_keyboard_controller.dart';

/// Baris tombol ekstra di atas keyboard HP (gaya Termux/RD client).
///
/// Baris 1: tombol keyboard, Esc, Tab, ⌘ ⌃ ⌥ ⇧ (sticky: ketuk = sekali,
/// tahan = terkunci), panah, Home/End, PgUp/PgDn.
/// Baris 2 (geser): pintasan cepat ⌘C ⌘V ⌘Z ⌘Tab ⌘Space ⌘Q ⌃C lalu F1–F12.
///
/// [controller] null → diambil dari [RemoteKeyboardScope] (yaitu bila bar
/// diletakkan di dalam subtree [RemoteInputLayer]).
class RemoteKeyboardBar extends StatelessWidget {
  const RemoteKeyboardBar({
    super.key,
    this.controller,
    this.showKeyboardToggle = true,
    this.showFunctionRow = true,
    this.height = 44,
    this.onHaptic,
  });

  final RemoteKeyboardController? controller;
  final bool showKeyboardToggle;
  final bool showFunctionRow;

  /// Tinggi tiap baris.
  final double height;

  /// Override getaran (default [HapticFeedback.selectionClick]).
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final kb = controller ?? RemoteKeyboardScope.maybeOf(context);
    assert(
      kb != null,
      'RemoteKeyboardBar butuh controller atau RemoteKeyboardScope',
    );
    if (kb == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: kb,
      builder: (context, _) {
        void tap() => (onHaptic ?? HapticFeedback.selectionClick)();
        Widget key(
          String label,
          String code, {
          String? tooltip,
          bool repeat = false,
        }) => _BarKey(
          label: label,
          tooltip: tooltip,
          repeat: repeat,
          onPressed: () {
            tap();
            kb.sendKey(code);
          },
        );
        Widget shortcut(String label, String code, List<RemoteModifier> mods) =>
            _BarKey(
              label: label,
              onPressed: () {
                tap();
                kb.sendShortcut(code, mods);
              },
            );

        final row1 = <Widget>[
          if (showKeyboardToggle)
            _BarKey(
              key: const ValueKey('kb-toggle'),
              icon: kb.softKeyboardRequested
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_outlined,
              tooltip: 'Keyboard',
              onPressed: () {
                tap();
                kb.toggleSoftKeyboard();
              },
            ),
          key('Esc', 'Escape'),
          key('Tab', 'Tab'),
          for (final m in RemoteModifier.values)
            _ModifierKey(
              modifier: m,
              state: kb.stateOf(m),
              onTap: () {
                tap();
                kb.tapModifier(m);
              },
              onLock: () {
                HapticFeedback.mediumImpact();
                kb.lockModifier(m);
              },
            ),
          key('←', 'ArrowLeft', tooltip: 'Kiri', repeat: true),
          key('↑', 'ArrowUp', tooltip: 'Atas', repeat: true),
          key('↓', 'ArrowDown', tooltip: 'Bawah', repeat: true),
          key('→', 'ArrowRight', tooltip: 'Kanan', repeat: true),
          key('Home', 'Home'),
          key('End', 'End'),
          key('PgUp', 'PageUp', repeat: true),
          key('PgDn', 'PageDown', repeat: true),
          key('⌫', 'Backspace', tooltip: 'Backspace', repeat: true),
          key('⌦', 'Delete', tooltip: 'Delete', repeat: true),
        ];

        const meta = [RemoteModifier.meta];
        final row2 = <Widget>[
          shortcut('⌘C', 'KeyC', meta),
          // clipboard HP → Mac dulu, lalu ⌘V
          _BarKey(
            label: '⌘V',
            onPressed: () {
              tap();
              kb.paste();
            },
          ),
          shortcut('⌘Z', 'KeyZ', meta),
          shortcut('⇧⌘Z', 'KeyZ', const [
            RemoteModifier.meta,
            RemoteModifier.shift,
          ]),
          shortcut('⌘A', 'KeyA', meta),
          shortcut('⌘Tab', 'Tab', meta),
          shortcut('⌘Space', 'Space', meta),
          shortcut('⌘W', 'KeyW', meta),
          shortcut('⌘Q', 'KeyQ', meta),
          shortcut('⌃C', 'KeyC', const [RemoteModifier.ctrl]),
          const _Divider(),
          for (var i = 1; i <= 12; i++) key('F$i', 'F$i'),
        ];

        return Material(
          color: scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Row(height: height, children: row1),
                if (showFunctionRow) _Row(height: height, children: row2),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.height, required this.children});
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: VerticalDivider(
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// Tombol baris; [repeat] = tahan untuk mengulang (panah, backspace).
class _BarKey extends StatefulWidget {
  const _BarKey({
    super.key,
    this.label,
    this.icon,
    this.tooltip,
    this.repeat = false,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool repeat;
  final VoidCallback onPressed;

  @override
  State<_BarKey> createState() => _BarKeyState();
}

class _BarKeyState extends State<_BarKey> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelLarge;
    Widget content = widget.icon != null
        ? Icon(widget.icon, size: 20, color: scheme.onSurface)
        : Text(
            widget.label ?? '',
            style: text?.copyWith(color: scheme.onSurface),
          );
    content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          canRequestFocus: false,
          onTap: widget.onPressed,
          onLongPress: widget.repeat
              ? () {
                  widget.onPressed();
                  _repeat = Timer.periodic(
                    const Duration(milliseconds: 70),
                    (_) => widget.onPressed(),
                  );
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.repeat) {
      content = Listener(
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: content,
      );
    }
    final tip = widget.tooltip;
    return tip == null ? content : Tooltip(message: tip, child: content);
  }
}

class _ModifierKey extends StatelessWidget {
  const _ModifierKey({
    required this.modifier,
    required this.state,
    required this.onTap,
    required this.onLock,
  });

  final RemoteModifier modifier;
  final StickyState state;
  final VoidCallback onTap;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (state) {
      StickyState.off => (scheme.surfaceContainerHighest, scheme.onSurface),
      StickyState.once => (scheme.primaryContainer, scheme.onPrimaryContainer),
      StickyState.locked => (scheme.primary, scheme.onPrimary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        toggled: state != StickyState.off,
        label: modifier.name,
        child: Material(
          key: ValueKey('mod-${modifier.wire}'),
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            canRequestFocus: false,
            onTap: onTap,
            onLongPress: onLock,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Center(
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        modifier.symbol,
                        style: TextStyle(fontSize: 16, color: fg, height: 1.1),
                      ),
                      if (state == StickyState.locked)
                        Container(width: 12, height: 2, color: fg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
