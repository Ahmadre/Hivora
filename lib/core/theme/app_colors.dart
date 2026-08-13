import 'package:flutter/material.dart';

/// Hinata "Hive" design tokens — redesign 2026.
/// Navy nav-rail · warm-paper workspace · honey-amber signature accent.
///
/// Neutral surface/ink tokens are theme-aware: they resolve against the
/// currently active [brightness] (driven from the app's [ThemeMode] in
/// `app.dart`). Brand/accent/status hues stay constant across light & dark so
/// the honey-amber signature reads identically in both modes.
///
/// Hex values are derived from an oklch model (constant L/C, varied hue) so
/// status & accent tints stay perceptually harmonious.
abstract final class AppColors {
  // ---- active brightness (drives the neutral getters below) ----
  // Set once per frame from the resolved theme in `app.dart`'s MaterialApp
  // builder. Defaults to light so the very first build (and any non-widget
  // access) is well-defined.
  static Brightness brightness = Brightness.light;
  static bool get _dark => brightness == Brightness.dark;

  // ---- brand (constant across themes) ----
  static const navy = Color(0xFF2D2B55); // primary action
  static const navyDeep = Color(0xFF1E1C3A);

  // ---- ink / text (theme-aware) ----
  static const inkLight = Color(0xFF23223F);
  static const inkDark = Color(0xFFECEBF3);
  static Color get ink => _dark ? inkDark : inkLight; // primary text

  static const inkSoftLight = Color(0xFF6B6A85);
  static const inkSoftDark = Color(0xFFA8A6C2);
  static Color get inkSoft => _dark ? inkSoftDark : inkSoftLight; // secondary

  static const inkFaintLight = Color(0xFF9A99B0);
  static const inkFaintDark = Color(0xFF6F6D88);
  static Color get inkFaint => _dark ? inkFaintDark : inkFaintLight; // hints

  // ---- workspace surfaces (theme-aware) ----
  static const canvasLight = Color(0xFFF4F3EF); // warm paper
  static const canvasDark = Color(0xFF131119); // warm-tinted near-black
  static Color get canvas => _dark ? canvasDark : canvasLight; // app background

  static const canvas2Light = Color(0xFFEFEEE8);
  static const canvas2Dark = Color(0xFF0E0D14);
  static Color get canvas2 => _dark ? canvas2Dark : canvas2Light; // recessed

  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1B25);
  static Color get surface => _dark ? surfaceDark : surfaceLight; // cards

  static const surfaceMutedLight = Color(0xFFFAF9F6);
  static const surfaceMutedDark = Color(0xFF232231);
  static Color get surfaceMuted => _dark ? surfaceMutedDark : surfaceMutedLight;

  static const hairlineLight = Color(0xFFE7E5DE);
  static const hairlineDark = Color(0xFF2E2D3B);
  static Color get hairline => _dark ? hairlineDark : hairlineLight; // borders

  static const hairline2Light = Color(0xFFEFEDE6);
  static const hairline2Dark = Color(0xFF27262F);
  static Color get hairline2 => _dark ? hairline2Dark : hairline2Light;

  // ---- nav rail (deep navy in both themes) ----
  static const rail = Color(0xFF211F3D);
  static const rail2 = Color(0xFF1A1830);
  static const railInk = Color(0xFFC9C7E0);
  static const railFaint = Color(0xFF807EA0);

  // ---- signature honey-amber accent (hue 70, constant across themes) ----
  static const accent = Color(0xFFD9A032); // oklch(.74 .135 70)
  static const accentStrong = Color(0xFFB9831F); // oklch(.66 .145 70)
  static const accentLine = Color(0xFFE4CE96); // oklch(.86 .07 70)

  // Soft accent fill (active pill / unread highlight). Theme-aware: an opaque
  // cream tint in light, a translucent amber wash on dark surfaces.
  static const accentSoftLight = Color(0xFFF3E9D2); // oklch(.94 .045 70)
  static const accentSoftDark = Color(0x29D9A032); // ~16% amber over dark
  static Color get accentSoft => _dark ? accentSoftDark : accentSoftLight;

  // ---- workflow status (varied hue, constant L/C ~ oklch .6 .13) ----
  static const stBacklog = Color(0xFF7E81AE); // hue 255, muted slate
  static const stTodo = Color(0xFF5B86D6); // hue 250
  static const stProgress = Color(0xFFC58A22); // hue 70 (honey)
  static const stReview = Color(0xFF9A6BD0); // hue 300
  static const stDone = Color(0xFF2FA06E); // hue 155

  // ---- priority ----
  static const priUrgent = Color(0xFFD9544B); // hue 22
  static const priHigh = Color(0xFFD98A2B); // hue 45
  static const priNormal = Color(0xFF5B86D6); // hue 250
  static const priLow = Color(0xFF9A99B0); // muted

  // ---- semantic ----
  static const danger = Color(0xFFD9544B);
  static const dangerSoft = Color(0xFFFBE7E4);
  static const success = Color(0xFF2FA06E);
  static const warning = Color(0xFFD9A032);

  // ---- compatibility aliases (migrate screens progressively) ----
  static Color get textPrimary => ink;
  static Color get textSecondary => inkSoft;
  static const textOnDark = Colors.white;
  static const navyDark = navyDeep;
  static const lavender = stReview; // closest purple equivalent
  static Color get background => canvas;
  static Color get backgroundEnd => canvas2;

  // Brand-tinted foreground for icons/labels sitting ON a theme surface. The
  // raw [navy] is a fixed dark brand colour and is unreadable on dark surfaces,
  // so this lifts to a light lavender in dark mode.
  static Color get brandInk => _dark ? railInk : navy;

  // Pastel card tints — light & warm on light, muted & dark (white-text safe)
  // on dark, so colourful cards keep their hue without losing legibility.
  static const pastelBlue = Color(0xFFE9EEF8);
  static const pastelLavender = Color(0xFFEFEBF8);
  static const pastelPeach = Color(0xFFF3E9D2); // = accentSoftLight
  static const pastelMint = Color(0xFFE4F2EC);
  static const pastels = [pastelBlue, pastelLavender, pastelPeach, pastelMint];
  static const pastelsDark = [
    Color(0xFF20263A), // blue-slate
    Color(0xFF272138), // lavender
    Color(0xFF2E2716), // amber-brown
    Color(0xFF16291F), // green
  ];
  static Color pastelFor(int index) =>
      (_dark ? pastelsDark : pastels)[index % pastels.length];
  // old accent names → new semantic equivalents
  static const accentOrange = accent;
  static const accentPurple = stReview;
  static const accentBlue = stTodo;
  static const accentTeal = stDone;

  /// Maps a workflow state to its signature colour. Accepts both canonical
  /// codes (`IN_PROGRESS`) and human/display variants (`In Progress`, `in-progress`)
  /// by normalising case and any space/underscore/hyphen separators first — so a
  /// column whose `states` carry display names still tints to the theme colour
  /// instead of silently falling through to the backlog slate.
  static Color stateColor(String state) =>
      switch (state.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '')) {
        'TODO' => stTodo,
        'INPROGRESS' => stProgress,
        'INREVIEW' => stReview,
        'DONE' => stDone,
        'BACKLOG' => stBacklog,
        _ => stBacklog,
      };

  static Color priorityColor(String priority) =>
      switch (priority.toUpperCase()) {
        // Backend Issue.Priority enum.
        'SHOWSTOPPER' || 'CRITICAL' => priUrgent,
        'MAJOR' => priHigh,
        'NORMAL' => priNormal,
        'MINOR' || 'TRIVIAL' => priLow,
        // Legacy aliases.
        'URGENT' => priUrgent,
        'HIGH' => priHigh,
        'LOW' => priLow,
        _ => priLow,
      };

  /// Soft tint of any base color for badge / chip backgrounds (~oklch .96 tint).
  static Color soft(Color base) =>
      Color.alphaBlend(base.withValues(alpha: 0.12), surface);
}
