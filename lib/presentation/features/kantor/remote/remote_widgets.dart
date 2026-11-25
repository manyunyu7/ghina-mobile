import 'package:flutter/material.dart';

import 'remote_keys.dart';
import 'remote_protocol.dart';
import 'remote_session.dart';

/// Local pointer drawn on top of the video so trackpad moves feel instant.
class RemoteCursorPainter extends CustomPainter {
  RemoteCursorPainter({required this.at, required this.shape});

  final Offset at;
  final String shape;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white;
    final edge = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (shape == 'ibeam') {
      final p = Path()
        ..moveTo(-4, -9)
        ..lineTo(4, -9)
        ..moveTo(0, -9)
        ..lineTo(0, 9)
        ..moveTo(-4, 9)
        ..lineTo(4, 9);
      canvas.drawPath(
        p,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4,
      );
      canvas.drawPath(
        p,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    } else {
      final p = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 17)
        ..lineTo(4.2, 13)
        ..lineTo(7.2, 19.5)
        ..lineTo(9.8, 18.3)
        ..lineTo(6.9, 12)
        ..lineTo(12.3, 12)
        ..close();
      canvas.drawShadow(p, Colors.black, 2, false);
      canvas.drawPath(p, fill);
      canvas.drawPath(p, edge);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RemoteCursorPainter old) =>
      old.at != at || old.shape != shape;
}

/// Row of extra keys above the phone keyboard: Esc, Tab, sticky
/// modifiers, arrows and quick Mac shortcuts. Scrolls sideways on narrow
/// screens (Fold cover).
class RemoteKeyBar extends StatelessWidget {
  const RemoteKeyBar({
    super.key,
    required this.sticky,
    required this.onKey,
    required this.onMod,
    required this.onShortcut,
    required this.onPaste,
    required this.onClose,
  });

  final StickyModifiers sticky;

  /// A plain key (W3C code); the page adds armed modifiers.
  final ValueChanged<String> onKey;
  final ValueChanged<RemoteMod> onMod;

  /// Shortcut ignoring sticky state: (code, mods).
  final void Function(String code, Set<RemoteMod> mods) onShortcut;
  final VoidCallback onPaste;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label,
      VoidCallback onTap, {
      String? tip,
      IconData? icon,
    }) => _KeyChip(label: label, icon: icon, tooltip: tip, onTap: onTap);

    Widget mod(RemoteMod m, String label, String tip) {
      final s = sticky.of(m);
      return _KeyChip(
        label: label,
        tooltip: '$tip (ketuk sekali = sekali pakai, dua kali = kunci)',
        selected: s != StickyState.off,
        locked: s == StickyState.locked,
        onTap: () => onMod(m),
      );
    }

    return Material(
      color: const Color(0xF0202124),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  children: [
                    key('esc', () => onKey('Escape'), tip: 'Escape'),
                    key('tab', () => onKey('Tab'), tip: 'Tab'),
                    mod(RemoteMod.meta, '⌘', 'Command'),
                    mod(RemoteMod.ctrl, '⌃', 'Control'),
                    mod(RemoteMod.alt, '⌥', 'Option'),
                    mod(RemoteMod.shift, '⇧', 'Shift'),
                    key(
                      '',
                      () => onKey('ArrowLeft'),
                      icon: Icons.keyboard_arrow_left_rounded,
                      tip: 'Kiri',
                    ),
                    key(
                      '',
                      () => onKey('ArrowUp'),
                      icon: Icons.keyboard_arrow_up_rounded,
                      tip: 'Atas',
                    ),
                    key(
                      '',
                      () => onKey('ArrowDown'),
                      icon: Icons.keyboard_arrow_down_rounded,
                      tip: 'Bawah',
                    ),
                    key(
                      '',
                      () => onKey('ArrowRight'),
                      icon: Icons.keyboard_arrow_right_rounded,
                      tip: 'Kanan',
                    ),
                    const _Gap(),
                    key(
                      '⌘C',
                      () => onShortcut('KeyC', {RemoteMod.meta}),
                      tip: 'Salin di Mac',
                    ),
                    key('⌘V', onPaste, tip: 'Tempel clipboard HP di Mac'),
                    key(
                      '⌘Z',
                      () => onShortcut('KeyZ', {RemoteMod.meta}),
                      tip: 'Urungkan',
                    ),
                    key(
                      '⌘⇥',
                      () => onShortcut('Tab', {RemoteMod.meta}),
                      tip: 'Ganti aplikasi',
                    ),
                    key(
                      '⌘␣',
                      () => onShortcut('Space', {RemoteMod.meta}),
                      tip: 'Spotlight',
                    ),
                    const _Gap(),
                    key('del', () => onKey('Delete'), tip: 'Hapus maju'),
                    key('home', () => onKey('Home')),
                    key('end', () => onKey('End')),
                    key('pgup', () => onKey('PageUp')),
                    key('pgdn', () => onKey('PageDown')),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tutup keyboard',
                color: Colors.white70,
                icon: const Icon(Icons.keyboard_hide_rounded),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 10);
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.tooltip,
    this.selected = false,
    this.locked = false,
  });

  final String label;
  final IconData? icon;
  final String? tooltip;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? accent : const Color(0xFF3C4043),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: locked
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                  )
                : null,
            child: icon != null
                ? Icon(icon, size: 20, color: Colors.white)
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Small translucent stats box (fps, RTT, bitrate, resolution).
class RemoteStatsOverlay extends StatelessWidget {
  const RemoteStatsOverlay({super.key, required this.stats});

  final RemoteStats stats;

  @override
  Widget build(BuildContext context) {
    String f(double? v, String unit, [int digits = 0]) =>
        v == null ? '–' : '${v.toStringAsFixed(digits)} $unit';
    final lines = [
      'fps ${f(stats.fps, '')}'.trim(),
      'RTT ${f(stats.rttMs, 'ms')}',
      'bitrate ${stats.kbps == null
          ? '–'
          : stats.kbps! >= 1000
          ? '${(stats.kbps! / 1000).toStringAsFixed(1)} Mbps'
          : '${stats.kbps!.toStringAsFixed(0)} kbps'}',
      if (stats.width != null) '${stats.width}×${stats.height}',
      if (stats.codec != null && stats.codec!.isNotEmpty) stats.codec!,
      if (stats.encMs != null) 'enc ${stats.encMs!.toStringAsFixed(1)} ms',
    ];
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          lines.join('\n'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.3,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Mac shortcuts offered in the toolbar's "Pintasan" menu.
const remoteShortcuts = <(String, IconData, String, Set<RemoteMod>)>[
  ('Spotlight (⌘ Spasi)', Icons.search_rounded, 'Space', {RemoteMod.meta}),
  ('Ganti aplikasi (⌘ Tab)', Icons.swap_horiz_rounded, 'Tab', {RemoteMod.meta}),
  (
    'Mission Control (⌃ ↑)',
    Icons.view_quilt_rounded,
    'ArrowUp',
    {RemoteMod.ctrl},
  ),
  (
    'Paksa keluar (⌘⌥ Esc)',
    Icons.cancel_rounded,
    'Escape',
    {RemoteMod.meta, RemoteMod.alt},
  ),
  ('Tutup jendela (⌘ W)', Icons.close_rounded, 'KeyW', {RemoteMod.meta}),
  ('Keluar app (⌘ Q)', Icons.logout_rounded, 'KeyQ', {RemoteMod.meta}),
  (
    'Tangkap area (⌘⇧ 4)',
    Icons.screenshot_rounded,
    'Digit4',
    {RemoteMod.meta, RemoteMod.shift},
  ),
  (
    'Kunci layar Mac (⌃⌘ Q)',
    Icons.lock_rounded,
    'KeyQ',
    {RemoteMod.ctrl, RemoteMod.meta},
  ),
];
