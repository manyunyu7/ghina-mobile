import 'package:flutter/material.dart';

import 'remote_protocol.dart';
import 'remote_session.dart';

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
      if (stats.decoder != null && stats.decoder!.isNotEmpty)
        'dec ${stats.decoder}',
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
