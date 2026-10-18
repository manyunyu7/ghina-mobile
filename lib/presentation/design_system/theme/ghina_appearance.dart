import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// The brand accent the user picked in "Tampilan". Drives CTAs, the nav
/// center button, switches, progress bars and the FAB (via
/// `context.ghina.accent`), plus selection / focus (`context.ghina.highlight`).
///
/// Semantic colors (income green, expense red, done / success) never follow
/// it.
enum GhinaAccent {
  hijau('hijau', 'Hijau Ghina', GhinaColors.green),
  biru('biru', 'Biru', GhinaColors.blue),
  ungu('ungu', 'Ungu', GhinaColors.purple),
  pink('pink', 'Pink', GhinaColors.pink),
  oranye('oranye', 'Oranye', GhinaColors.orange),
  merah('merah', 'Merah', GhinaColors.red),
  teal('teal', 'Teal', GhinaColors.teal),
  emas('emas', 'Kuning Emas', GhinaColors.yellow),

  /// Near-black buttons (near-white in dark mode). The Minimal style's
  /// default.
  monokrom('monokrom', 'Monokrom', GhinaColors.monoLight);

  const GhinaAccent(this.id, this.label, this.swatch);

  /// Stable id for storage (never rename).
  final String id;

  /// Indonesian display name.
  final String label;

  /// The light-theme swatch (see [swatchFor]).
  final ChunkySwatch swatch;

  /// The swatch for a theme brightness: only [monokrom] flips (near-white
  /// in dark mode).
  ChunkySwatch swatchFor(Brightness b) =>
      this == GhinaAccent.monokrom && b == Brightness.dark
      ? GhinaColors.monoDark
      : swatch;

  /// Selection / focus color. The original green look pairs green CTAs with
  /// blue selection; every other accent uses itself.
  ChunkySwatch highlightFor(Brightness b) =>
      this == GhinaAccent.hijau ? GhinaColors.blue : swatchFor(b);

  /// A brighter companion (snackbar action, dark-mode container text).
  Color get glow => switch (this) {
    GhinaAccent.hijau => GhinaColors.lime.base,
    GhinaAccent.monokrom => Colors.white,
    _ => Color.lerp(swatch.base, Colors.white, 0.3)!,
  };

  static const fallback = GhinaAccent.hijau;

  static GhinaAccent fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return fallback;
  }
}

/// "Ukuran teks": multiplies the system text scale.
enum GhinaTextSize {
  kecil('kecil', 'Kecil', 0.9),
  normal('normal', 'Normal', 1),
  besar('besar', 'Besar', 1.15),
  ekstra('ekstra', 'Ekstra', 1.3);

  const GhinaTextSize(this.id, this.label, this.factor);

  final String id;
  final String label;
  final double factor;

  static const fallback = GhinaTextSize.normal;

  /// Bounds of the combined (system × chosen) scale.
  static const minScale = 0.8;
  static const maxScale = 2.0;

  static GhinaTextSize fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return fallback;
  }

  /// [system] times [factor], clamped. [GhinaTextSize.normal] returns
  /// [system] untouched.
  TextScaler apply(TextScaler system) {
    if (this == GhinaTextSize.normal) return system;
    final v = (system.scale(1) * factor).clamp(minScale, maxScale);
    return TextScaler.linear(v);
  }
}

/// "Gaya": the chunky 3D look (a darker bottom edge), flat, or minimal
/// (system font, neutral greys, soft shadows, 14/24 radii).
enum GhinaStyle {
  chunky('chunky', 'Chunky'),
  datar('datar', 'Datar'),
  minimal('minimal', 'Minimal');

  const GhinaStyle(this.id, this.label);

  final String id;
  final String label;

  static const fallback = GhinaStyle.chunky;

  /// No 3D bottom edge (Datar and Minimal).
  bool get isFlat => this != GhinaStyle.chunky;

  /// The accent this style suggests: Monokrom for Minimal, else Hijau.
  GhinaAccent get defaultAccent =>
      this == GhinaStyle.minimal ? GhinaAccent.monokrom : GhinaAccent.hijau;

  static GhinaStyle fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return fallback;
  }
}

/// Everything on the "Tampilan" page. Device-local.
///
/// ```dart
/// const a = GhinaAppearance();                 // system mode, green, normal
/// a.copyWith(accent: GhinaAccent.ungu);
/// ```
@immutable
class GhinaAppearance {
  const GhinaAppearance({
    this.mode = ThemeMode.system,
    this.accent = GhinaAccent.fallback,
    this.textSize = GhinaTextSize.fallback,
    this.style = GhinaStyle.fallback,
  });

  final ThemeMode mode;
  final GhinaAccent accent;
  final GhinaTextSize textSize;
  final GhinaStyle style;

  bool get isDefault => this == const GhinaAppearance();

  GhinaAppearance copyWith({
    ThemeMode? mode,
    GhinaAccent? accent,
    GhinaTextSize? textSize,
    GhinaStyle? style,
  }) => GhinaAppearance(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    textSize: textSize ?? this.textSize,
    style: style ?? this.style,
  );

  @override
  bool operator ==(Object other) =>
      other is GhinaAppearance &&
      other.mode == mode &&
      other.accent == accent &&
      other.textSize == textSize &&
      other.style == style;

  @override
  int get hashCode => Object.hash(mode, accent, textSize, style);

  @override
  String toString() =>
      'GhinaAppearance(${mode.name}, ${accent.id}, ${textSize.id}, '
      '${style.id})';
}
