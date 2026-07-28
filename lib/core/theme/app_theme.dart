import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Hinata "Hive" Material theme — redesign 2026.
///
/// Key shifts from the old pastel-glassmorphism theme:
///   • Tighter radii: cards 14 (was 28), controls 10 — crisp, not bubbly.
///   • Hairline borders + a whisper of shadow instead of heavy soft cards.
///   • Warm-paper canvas (#F4F3EF) instead of lavender-grey.
///   • Sora is reserved for display/headings; IBM Plex Sans drives dense UI,
///     IBM Plex Mono renders issue IDs & numeric metrics.
///   • Honey-amber accent used for highlights/active/focus.
abstract final class AppTheme {
  static const radiusCard = 14.0;
  static const radiusControl = 10.0;
  static const radiusPill = 999.0;

  static const fontBrand = 'Sora'; // headings, wordmark
  static const fontUi = 'IBMPlexSans'; // body / dense UI
  static const fontMono = 'IBMPlexMono'; // ids, metrics

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Builds the Material theme for [brightness]. Neutral surface/ink values are
  /// read from the explicit per-theme [AppColors] constants (NOT the runtime
  /// `AppColors.<token>` getters) so each [ThemeData] is deterministic
  /// regardless of which mode is currently active when it's constructed.
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final canvas = dark ? AppColors.canvasDark : AppColors.canvasLight;
    final surface = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceMuted = dark
        ? AppColors.surfaceMutedDark
        : AppColors.surfaceMutedLight;
    final ink = dark ? AppColors.inkDark : AppColors.inkLight;
    final inkSoft = dark ? AppColors.inkSoftDark : AppColors.inkSoftLight;
    final inkFaint = dark ? AppColors.inkFaintDark : AppColors.inkFaintLight;
    final hairline = dark ? AppColors.hairlineDark : AppColors.hairlineLight;
    final hairline2 = dark ? AppColors.hairline2Dark : AppColors.hairline2Light;
    final accentSoft = dark
        ? AppColors.accentSoftDark
        : AppColors.accentSoftLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: brightness,
      primary: dark ? AppColors.accent : AppColors.navy,
      secondary: AppColors.accent,
      surface: surface,
      error: AppColors.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontUi,
    );
    final text = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: fontBrand,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: ink,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: fontBrand,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusControl),
      borderSide: BorderSide(color: c, width: w),
    );

    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: text,
      dividerColor: hairline,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          minimumSize: const Size(44, 44),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? AppColors.accent : AppColors.navy,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: border(hairline),
        enabledBorder: border(hairline),
        focusedBorder: border(AppColors.accent, 1.5),
        hintStyle: TextStyle(color: inkFaint),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceMuted,
        side: BorderSide(color: hairline2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: TextStyle(color: inkSoft, fontSize: 11),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: AppColors.rail,
        indicatorColor: Color(0x14FFFFFF),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navyDeep,
        // The surface is deep navy in both themes, so the content must stay
        // light — otherwise dark mode inherits a dark on-surface text colour and
        // the message reads near-invisible.
        contentTextStyle: const TextStyle(
          color: Color(0xFFECEBF3),
          fontFamily: fontUi,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        width: 360,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
      ),
    );
  }
}
