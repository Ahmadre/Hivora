import 'package:flutter/material.dart';

/// Liquid-glass material tokens for the global search palette.
///
/// A 1:1 port of the light/dark token sets in `Design/search/app/search.css`
/// (§2 of `INTEGRATION.md`). Keep this file the single source of truth so the
/// Flutter surface stays in lockstep with the HTML reference.
@immutable
class SearchTokens {
  const SearchTokens({
    required this.tint,
    required this.glassFill,
    required this.tintStrong,
    required this.edge,
    required this.edgeSoft,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.rowHover,
    required this.selTint,
    required this.selEdge,
    required this.glare,
    required this.scrim,
    required this.popoverScrim,
    required this.field,
    required this.markBg,
    required this.panelShadow,
  });

  /// Panel base tint (the translucent glass fill).
  final Color tint;

  /// Light glass-color fed to the liquid-glass lens. Much lower alpha than
  /// [tint] — the iOS-26 effect is refraction + specular, not an opaque fill;
  /// a heavy fill buries the glass and reads as a flat card.
  final Color glassFill;

  /// Stronger tint for active chips / footer.
  final Color tintStrong;

  /// Bright specular edge (top-left of the rim).
  final Color edge;

  /// Dimmed specular edge (the rim's falloff).
  final Color edgeSoft;

  final Color ink; // primary text
  final Color inkSoft; // secondary text
  final Color inkFaint; // hints / faint glyphs

  final Color hairline; // 1px dividers / borders
  final Color rowHover; // hover lozenge fill
  final Color selTint; // selected-row lozenge fill
  final Color selEdge; // selected-row inset highlight
  final Color glare; // pointer-tracked sheen
  final Color scrim; // dim layer behind the panel

  /// Dim layer behind an *anchored* panel — a dropdown or field picker.
  ///
  /// Much lighter than [scrim]: a palette takes over the screen and dims it
  /// like a modal, while a dropdown is an inline editor that has to leave its
  /// page readable. It exists at all because glass is only legible against
  /// what it floats over, and a dropdown lands wherever its field happens to
  /// be — over a dark hero card, over an image, over a coloured chip.
  final Color popoverScrim;

  final Color field; // inset field / kbd / icon tile fill
  final Color markBg; // matched-substring highlight background

  final List<BoxShadow> panelShadow;

  /// Light glass (`.gs-root`).
  static const light = SearchTokens(
    tint: Color.fromRGBO(252, 251, 248, 0.62),
    // Raised from 0.22 → 0.42 so the dark app behind the glass can't bleed
    // through and wash out the (dark) text — the previous near-transparent
    // fill left the placeholder and labels barely legible (a11y).
    glassFill: Color.fromRGBO(252, 251, 248, 0.42),
    tintStrong: Color.fromRGBO(252, 251, 248, 0.80),
    edge: Color.fromRGBO(255, 255, 255, 0.85),
    edgeSoft: Color.fromRGBO(255, 255, 255, 0.35),
    ink: Color(0xFF23223F),
    // Darkened secondary inks for WCAG-AA contrast on the glass. Previous
    // values (#6B6A85 / #9A99B0) failed AA for body/hint text.
    inkSoft: Color(0xFF4C4B64),
    inkFaint: Color(0xFF6A6984),
    hairline: Color.fromRGBO(35, 34, 63, 0.09),
    rowHover: Color.fromRGBO(35, 34, 63, 0.05),
    selTint: Color.fromRGBO(255, 255, 255, 0.78),
    selEdge: Color.fromRGBO(255, 255, 255, 0.95),
    glare: Color.fromRGBO(255, 255, 255, 0.55),
    scrim: Color.fromRGBO(22, 20, 45, 0.30),
    popoverScrim: Color.fromRGBO(22, 20, 45, 0.12),
    field: Color.fromRGBO(255, 255, 255, 0.55),
    // oklch(0.92 0.10 70 / 0.6) ≈ a pale honey wash.
    markBg: Color.fromRGBO(247, 224, 150, 0.65),
    panelShadow: [
      BoxShadow(
        color: Color.fromRGBO(20, 18, 45, 0.55),
        offset: Offset(0, 40),
        blurRadius: 90,
        spreadRadius: -30,
      ),
      BoxShadow(
        color: Color.fromRGBO(20, 18, 45, 0.30),
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: -12,
      ),
    ],
  );

  /// Dark glass (`.gs-root[data-theme="dark"]`).
  static const dark = SearchTokens(
    tint: Color.fromRGBO(34, 32, 60, 0.58),
    // Raised from 0.28 → 0.48 so the bright app behind the glass can't bleed
    // through and wash out the (light) text (a11y — see light counterpart).
    glassFill: Color.fromRGBO(30, 28, 52, 0.48),
    tintStrong: Color.fromRGBO(38, 36, 66, 0.80),
    edge: Color.fromRGBO(255, 255, 255, 0.20),
    edgeSoft: Color.fromRGBO(255, 255, 255, 0.07),
    ink: Color(0xFFF2F1F8),
    // Lightened secondary inks for WCAG-AA contrast on the dark glass.
    inkSoft: Color(0xFFCAC8DE),
    inkFaint: Color(0xFF9E9CBC),
    hairline: Color.fromRGBO(255, 255, 255, 0.09),
    rowHover: Color.fromRGBO(255, 255, 255, 0.06),
    selTint: Color.fromRGBO(255, 255, 255, 0.13),
    selEdge: Color.fromRGBO(255, 255, 255, 0.22),
    glare: Color.fromRGBO(255, 255, 255, 0.16),
    scrim: Color.fromRGBO(8, 7, 20, 0.52),
    popoverScrim: Color.fromRGBO(8, 7, 20, 0.24),
    field: Color.fromRGBO(255, 255, 255, 0.06),
    // oklch(0.55 0.13 70 / 0.45) ≈ a muted amber wash.
    markBg: Color.fromRGBO(150, 110, 40, 0.55),
    panelShadow: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.75),
        offset: Offset(0, 50),
        blurRadius: 110,
        spreadRadius: -28,
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.60),
        offset: Offset(0, 6),
        blurRadius: 22,
        spreadRadius: -10,
      ),
    ],
  );

  static SearchTokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
