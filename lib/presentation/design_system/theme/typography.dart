import 'package:flutter/material.dart';

/// Nunito typography. Nunito is bundled as a *variable* font, so every style
/// sets both [FontWeight] and a matching `wght` [FontVariation] – otherwise
/// some engines render everything at the default weight.
///
/// When you change the weight of a style, use [TextStyleWeight.w] instead of
/// `copyWith(fontWeight: ...)`:
///
/// ```dart
/// Text('Halo', style: GhinaType.body.w(800));
/// ```
abstract final class GhinaType {
  static const String family = 'Nunito';

  /// Creates a Nunito style with the variable weight axis set correctly.
  static TextStyle nunito(
    double size, {
    int weight = 700,
    Color? color,
    double? height,
    double? letterSpacing,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: _fw(weight),
      fontVariations: [FontVariation('wght', weight.toDouble())],
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: features,
    );
  }

  static FontWeight _fw(int w) {
    final i = ((w.clamp(100, 900) / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[i];
  }

  static const _tabular = [FontFeature.tabularFigures()];

  // ---- Money / display numbers (tabular figures) ---------------------------
  /// Hero balance, amount entry. 44/900.
  static final _moneyXL = nunito(
    44,
    weight: 900,
    height: 1.05,
    letterSpacing: -1,
    features: _tabular,
  );

  /// Card totals. 30/900.
  static final _moneyL = nunito(
    30,
    weight: 900,
    height: 1.1,
    letterSpacing: -0.5,
    features: _tabular,
  );

  /// List amounts. 17/800.
  static final _moneyM = nunito(
    17,
    weight: 800,
    height: 1.2,
    features: _tabular,
  );

  /// Small amounts in captions. 13/800.
  static final _moneyS = nunito(
    13,
    weight: 800,
    height: 1.2,
    features: _tabular,
  );

  // ---- Headings -------------------------------------------------------------
  /// Celebration titles ("Mantap!"). 36/900.
  static final _display = nunito(
    36,
    weight: 900,
    height: 1.1,
    letterSpacing: -0.5,
  );

  /// Screen titles. 26/900.
  static final _h1 = nunito(26, weight: 900, height: 1.2, letterSpacing: -0.3);

  /// Section / card titles. 20/800.
  static final _h2 = nunito(20, weight: 800, height: 1.25);

  /// Tile titles. 17/800.
  static final _h3 = nunito(17, weight: 800, height: 1.3);

  // ---- Body -----------------------------------------------------------------
  static final _bodyL = nunito(17, weight: 600, height: 1.45);
  static final _body = nunito(15, weight: 600, height: 1.45);
  static final _bodyS = nunito(13, weight: 600, height: 1.4);

  /// Small labels, timestamps. 12/700.
  static final _caption = nunito(12, weight: 700, height: 1.3);

  /// ALL-CAPS tracking label ("TOTAL XP", section overlines). 13/800.
  static final _overline = nunito(
    13,
    weight: 800,
    height: 1.2,
    letterSpacing: 1.1,
  );

  /// Button label (apply `.toUpperCase()` to text – Duolingo-style caps). 15/800.
  static final _button = nunito(
    15,
    weight: 800,
    height: 1.1,
    letterSpacing: 0.8,
  );

  // ---- Public styles ----------------------------------------------------------
  // Nunito by default; the system font (SF Pro / Roboto, lighter weights,
  // tighter headings) while the "Minimal" style is on.
  static TextStyle get moneyXL => usesSystemFont ? _moneyXLSys : _moneyXL;
  static TextStyle get moneyL => usesSystemFont ? _moneyLSys : _moneyL;
  static TextStyle get moneyM => usesSystemFont ? _moneyMSys : _moneyM;
  static TextStyle get moneyS => usesSystemFont ? _moneySSys : _moneyS;
  static TextStyle get display => usesSystemFont ? _displaySys : _display;
  static TextStyle get h1 => usesSystemFont ? _h1Sys : _h1;
  static TextStyle get h2 => usesSystemFont ? _h2Sys : _h2;
  static TextStyle get h3 => usesSystemFont ? _h3Sys : _h3;
  static TextStyle get bodyL => usesSystemFont ? _bodyLSys : _bodyL;
  static TextStyle get body => usesSystemFont ? _bodySys : _body;
  static TextStyle get bodyS => usesSystemFont ? _bodySSys : _bodyS;
  static TextStyle get caption => usesSystemFont ? _captionSys : _caption;
  static TextStyle get overline => usesSystemFont ? _overlineSys : _overline;
  static TextStyle get button => usesSystemFont ? _buttonSys : _button;

  static final _moneyXLSys = _system(_moneyXL, _Track.heading);
  static final _moneyLSys = _system(_moneyL, _Track.heading);
  static final _moneyMSys = _system(_moneyM, _Track.plain);
  static final _moneySSys = _system(_moneyS, _Track.plain);
  static final _displaySys = _system(_display, _Track.heading);
  static final _h1Sys = _system(_h1, _Track.heading);
  static final _h2Sys = _system(_h2, _Track.heading);
  static final _h3Sys = _system(_h3, _Track.heading);
  static final _bodyLSys = _system(_bodyL, _Track.plain);
  static final _bodySys = _system(_body, _Track.plain);
  static final _bodySSys = _system(_bodyS, _Track.plain);
  static final _captionSys = _system(_caption, _Track.plain);
  static final _overlineSys = _system(_overline, _Track.overline);
  static final _buttonSys = _system(_button, _Track.button);

  /// Builds a system-font copy of a Nunito style.
  static TextStyle _system(TextStyle s, _Track track) {
    final size = s.fontSize!;
    return TextStyle(
      fontSize: size,
      fontWeight: _fw(_systemWeight(_weightOf(s))),
      height: s.height,
      letterSpacing: switch (track) {
        _Track.heading => -0.01 * size,
        _Track.overline => 0.02 * size,
        _Track.button => 0,
        _Track.plain => s.letterSpacing,
      },
      fontFeatures: s.fontFeatures,
    );
  }

  static int _weightOf(TextStyle s) => (s.fontWeight?.value ?? 400);

  /// Nunito's heavy weights mapped to the 500–600 range (700 for the
  /// heaviest).
  static int _systemWeight(int w) => w >= 900
      ? 700
      : w >= 700
      ? 600
      : w >= 600
      ? 500
      : w;

  /// True while the "Minimal" style is on: every style above (and
  /// [TextStyleWeight.w]) uses the system font. Set by `GhinaTheme`;
  /// the app root rebuilds the tree when it flips.
  static bool usesSystemFont = false;

  /// Material [TextTheme] mapping, colored for a brightness.
  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: moneyXL.copyWith(color: primary),
      displayMedium: display.copyWith(color: primary),
      displaySmall: moneyL.copyWith(color: primary),
      headlineLarge: h1.copyWith(color: primary),
      headlineMedium: h1.copyWith(color: primary, fontSize: 24),
      headlineSmall: h2.copyWith(color: primary),
      titleLarge: h2.copyWith(color: primary),
      titleMedium: h3.copyWith(color: primary),
      titleSmall: body.w(800).copyWith(color: primary),
      bodyLarge: bodyL.copyWith(color: primary),
      bodyMedium: body.copyWith(color: primary),
      bodySmall: bodyS.copyWith(color: secondary),
      labelLarge: button.copyWith(color: primary),
      labelMedium: caption.copyWith(color: secondary),
      labelSmall: overline.copyWith(color: secondary, fontSize: 11),
    );
  }
}

/// Weight helper that keeps the variable-font axis in sync.
extension TextStyleWeight on TextStyle {
  /// Returns this style at [weight] (100–1000), e.g. `GhinaType.body.w(800)`.
  TextStyle w(int weight) {
    if (GhinaType.usesSystemFont && fontFamily == null) {
      return copyWith(
        fontWeight: GhinaType._fw(GhinaType._systemWeight(weight)),
      );
    }
    return copyWith(
      fontWeight: GhinaType._fw(weight),
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }
}

enum _Track { heading, overline, button, plain }
