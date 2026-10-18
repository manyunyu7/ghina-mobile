import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import 'ghina_appearance.dart';

/// Theme-aware neutrals & semantic colors. Read with `context.ghina`.
///
/// ```dart
/// final g = context.ghina;
/// Container(color: g.surface, child: Text('Hai', style: TextStyle(color: g.textPrimary)));
/// ```
@immutable
class GhinaTokens extends ThemeExtension<GhinaTokens> {
  const GhinaTokens({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderEdge,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.disabled,
    required this.disabledEdge,
    required this.onDisabled,
    this.accent = GhinaColors.green,
    this.highlight = GhinaColors.blue,
    this.style = GhinaStyle.chunky,
  });

  static const light = GhinaTokens(
    brightness: Brightness.light,
    background: GhinaColors.snow,
    surface: GhinaColors.snow,
    surfaceAlt: GhinaColors.polar,
    border: GhinaColors.swan,
    borderEdge: GhinaColors.swanEdge,
    textPrimary: GhinaColors.ink,
    textSecondary: GhinaColors.wolf,
    textMuted: GhinaColors.hare,
    skeleton: Color(0xFFEDEDED),
    skeletonHighlight: Color(0xFFF9F9F9),
    disabled: GhinaColors.swan,
    disabledEdge: GhinaColors.swanEdge,
    onDisabled: GhinaColors.hare,
  );

  static const dark = GhinaTokens(
    brightness: Brightness.dark,
    background: GhinaColors.darkBackground,
    surface: GhinaColors.darkBackground,
    surfaceAlt: GhinaColors.darkSurface,
    border: GhinaColors.darkBorder,
    borderEdge: GhinaColors.darkBorder,
    textPrimary: GhinaColors.darkTextPrimary,
    textSecondary: GhinaColors.darkTextSecondary,
    textMuted: GhinaColors.darkTextMuted,
    skeleton: Color(0xFF22323A),
    skeletonHighlight: Color(0xFF2E4049),
    disabled: GhinaColors.darkBorder,
    disabledEdge: GhinaColors.darkBorderEdge,
    onDisabled: GhinaColors.darkTextMuted,
  );

  /// Neutrals of the "Minimal" style (light): white page, grey panels.
  static const minimalLight = GhinaTokens(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F7),
    surfaceAlt: Color(0xFFECECEF),
    border: Color(0xFFE3E3E7),
    borderEdge: Color(0xFFE3E3E7),
    textPrimary: Color(0xFF171717),
    textSecondary: Color(0xFF6B6B70),
    textMuted: Color(0xFFA1A1A6),
    skeleton: Color(0xFFEAEAED),
    skeletonHighlight: Color(0xFFF5F5F7),
    disabled: Color(0xFFEAEAED),
    disabledEdge: Color(0xFFE3E3E7),
    onDisabled: Color(0xFFA1A1A6),
    accent: GhinaColors.monoLight,
    highlight: GhinaColors.monoLight,
    style: GhinaStyle.minimal,
  );

  /// Neutrals of the "Minimal" style (dark): near-black page.
  static const minimalDark = GhinaTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0B0B0C),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF2C2C2E),
    border: Color(0xFF2E2E32),
    borderEdge: Color(0xFF2E2E32),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA1A1A6),
    textMuted: Color(0xFF6B6B70),
    skeleton: Color(0xFF2C2C2E),
    skeletonHighlight: Color(0xFF3A3A3D),
    disabled: Color(0xFF2C2C2E),
    disabledEdge: Color(0xFF2E2E32),
    onDisabled: Color(0xFF6B6B70),
    accent: GhinaColors.monoDark,
    highlight: GhinaColors.monoDark,
    style: GhinaStyle.minimal,
  );

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// Card face.
  final Color surface;

  /// Input fills, progress tracks, subtle panels.
  final Color surfaceAlt;

  /// 2px card / input border.
  final Color border;

  /// Bottom "3D" edge for neutral cards.
  final Color borderEdge;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color skeleton;
  final Color skeletonHighlight;
  final Color disabled;
  final Color disabledEdge;
  final Color onDisabled;

  /// Brand accent (the user's pick in "Tampilan", green by default): primary
  /// CTAs, nav center button, switches, progress, FAB. Not for semantic
  /// meaning (income / success / done stay [GhinaColors.green]).
  final ChunkySwatch accent;

  /// Selection & focus (selected tab / chip / segment, focused field).
  /// Blue next to the default green accent, else the accent itself.
  final ChunkySwatch highlight;

  /// "Gaya": chunky (3D edge), datar (flat) or minimal.
  final GhinaStyle style;

  /// No 3D bottom edge (Datar / Minimal).
  bool get flat => style.isFlat;

  /// Minimal: system font, 1px borders, soft shadows, 14 / 24 radii.
  bool get minimal => style == GhinaStyle.minimal;

  bool get isDark => brightness == Brightness.dark;

  Color get income => GhinaColors.income.base;
  Color get expense => GhinaColors.expense.base;
  Color get transfer => GhinaColors.transfer.base;
  Color get warning => GhinaColors.warning.base;

  /// Theme-aware pale tint of a swatch.
  Color tint(ChunkySwatch s) => s.tint(brightness);

  @override
  GhinaTokens copyWith({
    Color? background,
    Color? surface,
    ChunkySwatch? accent,
    ChunkySwatch? highlight,
    GhinaStyle? style,
  }) => GhinaTokens(
    brightness: brightness,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt,
    border: border,
    borderEdge: borderEdge,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    skeleton: skeleton,
    skeletonHighlight: skeletonHighlight,
    disabled: disabled,
    disabledEdge: disabledEdge,
    onDisabled: onDisabled,
    accent: accent ?? this.accent,
    highlight: highlight ?? this.highlight,
    style: style ?? this.style,
  );

  @override
  GhinaTokens lerp(GhinaTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GhinaTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      borderEdge: l(borderEdge, other.borderEdge),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      skeleton: l(skeleton, other.skeleton),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
      disabled: l(disabled, other.disabled),
      disabledEdge: l(disabledEdge, other.disabledEdge),
      onDisabled: l(onDisabled, other.onDisabled),
      accent: ChunkySwatch.lerp(accent, other.accent, t),
      highlight: ChunkySwatch.lerp(highlight, other.highlight, t),
      style: t < 0.5 ? style : other.style,
    );
  }
}

/// `context.ghina` – quick access to [GhinaTokens] (falls back to light).
extension GhinaContext on BuildContext {
  GhinaTokens get ghina =>
      Theme.of(this).extension<GhinaTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? GhinaTokens.dark
          : GhinaTokens.light);
}
