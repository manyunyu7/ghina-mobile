import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/page_transitions.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'ghina_appearance.dart';
import 'ghina_tokens.dart';
import 'typography.dart';

/// Entry points for the app theme. [accent] and [style] come from the
/// user's "Tampilan" choice; the defaults are the original look.
///
/// Building a theme also sets [GhinaType.usesSystemFont] (on for
/// [GhinaStyle.minimal]), since the text styles are static.
///
/// ```dart
/// MaterialApp.router(
///   theme: GhinaTheme.light(accent: GhinaAccent.ungu),
///   darkTheme: GhinaTheme.dark(accent: GhinaAccent.ungu),
///   themeMode: ThemeMode.system,
/// );
/// ```
abstract final class GhinaTheme {
  static ThemeData light({
    GhinaAccent accent = GhinaAccent.fallback,
    GhinaStyle style = GhinaStyle.fallback,
  }) => _build(_tokens(Brightness.light, accent, style), accent);

  static ThemeData dark({
    GhinaAccent accent = GhinaAccent.fallback,
    GhinaStyle style = GhinaStyle.fallback,
  }) => _build(_tokens(Brightness.dark, accent, style), accent);

  static GhinaTokens _tokens(
    Brightness b,
    GhinaAccent accent,
    GhinaStyle style,
  ) {
    GhinaType.usesSystemFont = style == GhinaStyle.minimal;
    final dark = b == Brightness.dark;
    final base = style == GhinaStyle.minimal
        ? (dark ? GhinaTokens.minimalDark : GhinaTokens.minimalLight)
        : (dark ? GhinaTokens.dark : GhinaTokens.light);
    if (accent == GhinaAccent.fallback && style == GhinaStyle.fallback) {
      return base;
    }
    return base.copyWith(
      accent: accent.swatchFor(b),
      highlight: accent.highlightFor(b),
      style: style,
    );
  }

  static ThemeData _build(GhinaTokens g, GhinaAccent accent) {
    final isDark = g.isDark;
    final scheme = ColorScheme(
      brightness: g.brightness,
      primary: g.accent.base,
      onPrimary: g.accent.on,
      primaryContainer: g.tint(g.accent),
      onPrimaryContainer: isDark ? accent.glow : g.accent.edge,
      secondary: GhinaColors.blue.base,
      onSecondary: Colors.white,
      secondaryContainer: g.tint(GhinaColors.blue),
      onSecondaryContainer: GhinaColors.blue.edge,
      tertiary: GhinaColors.purple.base,
      onTertiary: Colors.white,
      error: GhinaColors.red.base,
      onError: Colors.white,
      errorContainer: g.tint(GhinaColors.red),
      onErrorContainer: GhinaColors.red.edge,
      surface: g.surface,
      onSurface: g.textPrimary,
      onSurfaceVariant: g.textSecondary,
      surfaceContainerLowest: g.background,
      surfaceContainerLow: g.surfaceAlt,
      surfaceContainer: g.surfaceAlt,
      surfaceContainerHigh: isDark
          ? GhinaColors.darkSurfaceAlt
          : GhinaColors.polar,
      surfaceContainerHighest: g.border,
      outline: g.border,
      outlineVariant: g.border,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? GhinaColors.darkTextPrimary : GhinaColors.eel,
      onInverseSurface: isDark ? GhinaColors.darkBackground : Colors.white,
      inversePrimary: accent.glow,
    );

    final text = GhinaType.textTheme(g.textPrimary, g.textSecondary);
    // Minimal: 14 / 24 radii and 1px lines.
    BorderRadius rad(BorderRadius r) => g.minimal ? GhinaRadii.minimal(r) : r;
    final line = g.minimal ? 1.0 : GhinaDepth.border;
    final r = rad(GhinaRadii.rLg);
    OutlineInputBorder inBorder(Color c, [double? w]) => OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: c, width: w ?? line),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: g.brightness,
      colorScheme: scheme,
      fontFamily: g.minimal ? null : GhinaType.family,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: g.background,
      canvasColor: g.background,
      dividerColor: g.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [g],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GhinaPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: GhinaPageTransitionsBuilder(),
          TargetPlatform.windows: GhinaPageTransitionsBuilder(),
        },
      ),
      iconTheme: IconThemeData(color: g.textSecondary, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: g.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: g.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GhinaType.h2.copyWith(color: g.textPrimary),
        iconTheme: IconThemeData(color: g.textMuted, size: 28),
        actionsIconTheme: IconThemeData(color: g.textMuted, size: 26),
        shape: Border(
          bottom: BorderSide(color: g.border, width: line),
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: g.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: g.tint(g.highlight),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: rad(GhinaRadii.rMd),
          side: BorderSide(
            color: g.highlight.tintBorder(g.brightness),
            width: line,
          ),
        ),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GhinaType.caption.copyWith(
            color: s.contains(WidgetState.selected)
                ? g.highlight.base
                : g.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 28,
            color: s.contains(WidgetState.selected)
                ? g.highlight.base
                : g.textMuted,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: g.background,
        selectedItemColor: g.highlight.base,
        unselectedItemColor: g.textMuted,
        selectedLabelStyle: GhinaType.caption,
        unselectedLabelStyle: GhinaType.caption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: g.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: GhinaType.bodyL.copyWith(color: g.textMuted),
        labelStyle: GhinaType.body.w(700).copyWith(color: g.textSecondary),
        floatingLabelStyle: GhinaType.body
            .w(800)
            .copyWith(color: g.highlight.base),
        helperStyle: GhinaType.caption.copyWith(color: g.textSecondary),
        errorStyle: GhinaType.caption.copyWith(color: GhinaColors.red.base),
        prefixIconColor: g.textMuted,
        suffixIconColor: g.textMuted,
        border: inBorder(g.border),
        enabledBorder: inBorder(g.border),
        focusedBorder: inBorder(g.highlight.base),
        errorBorder: inBorder(GhinaColors.red.base),
        focusedErrorBorder: inBorder(GhinaColors.red.base),
        disabledBorder: inBorder(g.border.withValues(alpha: 0.5)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: g.highlight.base,
        selectionColor: g.highlight.base.withValues(alpha: 0.3),
        selectionHandleColor: g.highlight.base,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: g.surface,
        selectedColor: g.tint(g.highlight),
        disabledColor: g.disabled,
        labelStyle: GhinaType.body.w(800).copyWith(color: g.textSecondary),
        secondaryLabelStyle: GhinaType.body
            .w(800)
            .copyWith(color: g.highlight.base),
        side: BorderSide(color: g.border, width: line),
        shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rMd)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        checkmarkColor: g.highlight.base,
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: rad(GhinaRadii.rXxl),
          side: BorderSide(color: g.border, width: line),
        ),
        titleTextStyle: GhinaType.h2.copyWith(color: g.textPrimary),
        contentTextStyle: GhinaType.bodyL.copyWith(color: g.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: g.surface,
        modalBackgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: g.border,
        dragHandleSize: const Size(48, 6),
        shape: RoundedRectangleBorder(
          borderRadius: rad(
            const BorderRadius.vertical(top: Radius.circular(GhinaRadii.xxl)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.eel,
        contentTextStyle: GhinaType.body.w(700).copyWith(color: Colors.white),
        actionTextColor: accent.glow,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: rad(GhinaRadii.rLg),
          side: BorderSide(
            color: isDark ? GhinaColors.darkBorder : Colors.black,
            width: 0,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? g.accent.base : g.border,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? g.accent.edge : g.borderEdge,
        ),
        trackOutlineWidth: WidgetStatePropertyAll(line),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Icon(Icons.check_rounded, size: 16, color: g.accent.base)
              : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? g.highlight.base
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(g.highlight.on),
        side: BorderSide(color: g.border, width: line),
        shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rSm)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? g.highlight.base : g.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: g.accent.base,
        linearTrackColor: g.border,
        circularTrackColor: g.border,
        linearMinHeight: 12,
        borderRadius: GhinaRadii.rPill,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: g.accent.base,
        inactiveTrackColor: g.border,
        thumbColor: g.accent.base,
        overlayColor: g.accent.base.withValues(alpha: 0.15),
        trackHeight: 10,
      ),
      dividerTheme: DividerThemeData(
        color: g.border,
        thickness: line,
        space: line,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: g.textSecondary,
        textColor: g.textPrimary,
        titleTextStyle: GhinaType.h3.copyWith(color: g.textPrimary),
        subtitleTextStyle: GhinaType.bodyS.copyWith(color: g.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rLg)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: g.highlight.base,
        unselectedLabelColor: g.textMuted,
        labelStyle: GhinaType.button,
        unselectedLabelStyle: GhinaType.button,
        indicatorColor: g.highlight.base,
        dividerColor: g.border,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.eel,
          borderRadius: rad(GhinaRadii.rMd),
        ),
        textStyle: GhinaType.bodyS.w(700).copyWith(color: Colors.white),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: GhinaType.body.w(700).copyWith(color: g.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: rad(GhinaRadii.rLg),
          side: BorderSide(color: g.border, width: line),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: g.accent.base,
        headerForegroundColor: g.accent.on,
        shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rXxl)),
        dayStyle: GhinaType.body.w(700),
        todayBorder: BorderSide(color: g.accent.base, width: 2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: g.accent.base,
        foregroundColor: g.accent.on,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rXl)),
      ),
      // Fallback Material buttons, styled flat-chunky. Prefer ChunkyButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: g.accent.base,
          foregroundColor: g.accent.on,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rLg)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: g.accent.base,
          foregroundColor: g.accent.on,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rLg)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: g.highlight.base,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          side: BorderSide(color: g.border, width: line),
          shape: RoundedRectangleBorder(borderRadius: rad(GhinaRadii.rLg)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: g.highlight.base,
          textStyle: GhinaType.button,
        ),
      ),
    );
  }
}
