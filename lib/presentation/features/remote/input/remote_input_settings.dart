import 'package:flutter/foundation.dart';

/// Cara sentuhan diterjemahkan ke mouse Mac.
enum InputMode {
  /// Layar HP jadi trackpad: kursor relatif (`mr`), ketuk = klik.
  trackpad,

  /// Sentuh langsung: ketuk di titik = klik di titik itu (`mm` + `click`).
  touch,
}

/// Getaran halus yang dipicu gestur.
enum RemoteHaptic {
  /// Klik biasa.
  click,

  /// Mulai drag / klik kanan lewat tahan.
  heavy,

  /// Tombol baris keyboard.
  selection,
}

/// Pengaturan input yang bisa diubah pengguna. Semua nilai punya default
/// yang nyaman; inti boleh menyimpan & memberikan versi dari preferensi.
@immutable
class RemoteInputSettings {
  const RemoteInputSettings({
    this.pointerSpeed = 1.0,
    this.acceleration = 1.0,
    this.scrollSpeed = 1.0,
    this.naturalScroll = true,
    this.scrollInertia = true,
    this.doubleTapWindow = const Duration(milliseconds: 250),
    this.longPressDelay = const Duration(milliseconds: 420),
    this.touchLongPressDelay = const Duration(milliseconds: 550),
    this.tapSlop = 10.0,
    this.doubleTapSlop = 48.0,
    this.zoomThreshold = 0.12,
    this.scrollSlop = 10.0,
    this.allowZoom = true,
    this.maxZoom = 5.0,
    this.haptics = true,
    this.showLocalCursor = true,
    this.imeSuggestions = true,
  });

  /// Kecepatan kursor mode trackpad (pengali, 0.25..4).
  final double pointerSpeed;

  /// Seberapa kuat kurva akselerasi (0 = linear, 1 = default, 2 = agresif).
  final double acceleration;

  /// Pengali kecepatan scroll 2 jari.
  final double scrollSpeed;

  /// true: konten ikut jari (seperti trackpad Mac default).
  final bool naturalScroll;

  /// Scroll meluncur setelah jari diangkat cepat.
  final bool scrollInertia;

  /// Jendela ketuk ganda. Ketuk tunggal ditunda selama ini supaya ketuk ganda
  /// terkirim sebagai satu `click` n=2. Duration.zero = klik langsung.
  final Duration doubleTapWindow;

  /// Tahan 1 jari (trackpad) sampai drag dimulai.
  final Duration longPressDelay;

  /// Tahan 1 jari (sentuh) sampai klik kanan.
  final Duration touchLongPressDelay;

  /// Gerak maksimal (dp) agar masih dihitung ketukan.
  final double tapSlop;

  /// Jarak maksimal (dp) antar ketukan untuk ketuk ganda.
  final double doubleTapSlop;

  /// Perubahan skala relatif 2 jari sebelum dianggap pinch-zoom tampilan.
  final double zoomThreshold;

  /// Pergeseran titik tengah 2 jari (dp) sebelum dianggap scroll.
  final double scrollSlop;

  /// Pinch boleh memperbesar tampilan lokal.
  final bool allowZoom;
  final double maxZoom;

  final bool haptics;

  /// Gambar kursor lokal di mode trackpad.
  final bool showLocalCursor;

  /// Saran/autokoreksi keyboard HP di TextField tersembunyi.
  final bool imeSuggestions;

  RemoteInputSettings copyWith({
    double? pointerSpeed,
    double? acceleration,
    double? scrollSpeed,
    bool? naturalScroll,
    bool? scrollInertia,
    Duration? doubleTapWindow,
    Duration? longPressDelay,
    Duration? touchLongPressDelay,
    bool? allowZoom,
    double? maxZoom,
    bool? haptics,
    bool? showLocalCursor,
    bool? imeSuggestions,
  }) {
    return RemoteInputSettings(
      pointerSpeed: pointerSpeed ?? this.pointerSpeed,
      acceleration: acceleration ?? this.acceleration,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      naturalScroll: naturalScroll ?? this.naturalScroll,
      scrollInertia: scrollInertia ?? this.scrollInertia,
      doubleTapWindow: doubleTapWindow ?? this.doubleTapWindow,
      longPressDelay: longPressDelay ?? this.longPressDelay,
      touchLongPressDelay: touchLongPressDelay ?? this.touchLongPressDelay,
      tapSlop: tapSlop,
      doubleTapSlop: doubleTapSlop,
      zoomThreshold: zoomThreshold,
      scrollSlop: scrollSlop,
      allowZoom: allowZoom ?? this.allowZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      haptics: haptics ?? this.haptics,
      showLocalCursor: showLocalCursor ?? this.showLocalCursor,
      imeSuggestions: imeSuggestions ?? this.imeSuggestions,
    );
  }
}
